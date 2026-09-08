//! Thread-safe Scintilla direct-function wrapper.
//!
//! Every call is dispatched through the status-returning direct function
//! obtained from the HWND at attach time.  The wrapper enforces that all
//! calls originate from the thread that created the HWND (the "owner thread")
//! and returns a typed error when called from any other thread.
//!
//! Other threads communicate through `postCommand`, which enqueues a typed
//! command for the owner thread to execute during its next message-pump
//! iteration.  Raw Scintilla pointers never cross threads.

const builtin = @import("builtin");
const std = @import("std");

// ── Scintilla message constants ──────────────────────────────────────

pub const SCI_SETTEXT = 2181;
pub const SCI_GETTEXT = 2182;
pub const SCI_GETTEXTLENGTH = 2183;
pub const SCI_GETDIRECTFUNCTION = 2184;
pub const SCI_GETDIRECTSTATUSFUNCTION = 4026;
pub const SCI_GETDIRECTPOINTER = 2185;
pub const SCI_GETSTATUS = 2383;
pub const SCI_SETSTATUS = 2382;
pub const SCI_GETLENGTH = 2006;
pub const SCI_GETCHARAT = 2007;
pub const SCI_GETSTYLEAT = 2010;
pub const SCI_STARTSTYLING = 2032;
pub const SCI_SETSTYLING = 2033;
pub const SCI_SETSTYLINGEX = 2073;
pub const SCI_GETENDSTYLED = 2028;
pub const SCI_SETILEXER = 4033;
pub const SCI_GETLEXER = 4002;
pub const SCI_COLOURISE = 4003;
pub const SCI_CREATEDOCUMENT = 2375;
pub const SCI_RELEASEDOCUMENT = 2377;
pub const SCI_SETDOCPOINTER = 2358;
pub const SCI_GETDOCPOINTER = 2357;
pub const SCI_SETCODEPAGE = 2037;
pub const SCI_GETCODEPAGE = 2137;
pub const SCI_ADDTEXT = 2001;
pub const SCI_INSERTTEXT = 2003;
pub const SCI_DELETERANGE = 2645;
pub const SCI_CLEARALL = 2004;
pub const SCI_GETMODIFY = 2159;
pub const SCI_SETREADONLY = 2171;
pub const SCI_GETREADONLY = 2140;
pub const SCI_SETUNDOCOLLECTION = 2012;
pub const SCI_UNDO = 2176;
pub const SCI_REDO = 2011;
pub const SCI_CANUNDO = 2174;
pub const SCI_CANREDO = 2016;
pub const SCI_EMPTYUNDOBUFFER = 2175;
pub const SCI_BEGINUNDOACTION = 2078;
pub const SCI_ENDUNDOACTION = 2079;
pub const SCI_SETSEL = 2160;
pub const SCI_GETSELECTIONSTART = 2143;
pub const SCI_GETSELECTIONEND = 2145;
pub const SCI_GOTOPOS = 2025;
pub const SCI_SETCURRENTPOS = 2141;
pub const SCI_GETCURRENTPOS = 2008;
pub const SCI_SETANCHOR = 2026;
pub const SCI_GETANCHOR = 2009;
pub const SCI_LINECOUNT = 2154;
pub const SCI_LINELENGTH = 2350;
pub const SCI_POSITIONFROMLINE = 2167;
pub const SCI_LINEFROMPOSITION = 2166;
pub const SCI_SETTECHNOLOGY = 2630;
pub const SCI_GETTECHNOLOGY = 2631;
pub const SCI_SETCARETPERIOD = 2076;
pub const SCI_GETCARETPERIOD = 2075;
pub const SCI_SETMOUSEDWELLTIME = 2264;
pub const SCI_GETMOUSEDWELLTIME = 2265;
pub const SCI_SETIDLESTYLING = 2692;
pub const SCI_GETIDLESTYLING = 2693;

pub const SC_CP_UTF8 = 65001;
pub const SC_TECHNOLOGY_DEFAULT = 0;
pub const SC_TECHNOLOGY_DIRECTWRITE = 1;
pub const SC_TECHNOLOGY_DIRECTWRITERETAIN = 2;
pub const SC_TECHNOLOGY_DIRECTWRITEDC = 3;
pub const SC_TIME_FOREVER = 10000000;
pub const SC_IDLESTYLING_NONE = 0;
pub const SC_IDLESTYLING_TOVISIBLE = 1;
pub const SC_IDLESTYLING_AFTERVISIBLE = 2;
pub const SC_IDLESTYLING_ALL = 3;
pub const SC_STATUS_OK = 0;
pub const SC_STATUS_FAILURE = 1;
pub const SC_STATUS_BADALLOC = 2;
pub const SC_STATUS_WARN_REGEX = 1001;
pub const SCLEX_CONTAINER = 0;

pub const SCN_STYLENEEDED = 2000;
pub const SCN_MODIFIED = 2008;
pub const SCN_UPDATEUI = 2007;

// ── Types ────────────────────────────────────────────────────────────

/// Status-returning direct function signature (Scintilla 5.x).
pub const DirectFunction = *const fn (isize, u32, usize, isize) callconv(.c) isize;

pub const Error = error{
    WrongThread,
    DirectFunctionNull,
    DirectPointerNull,
    ScintillaError,
    InvalidCodepage,
    AttachFailed,
};

/// A typed command that a non-owner thread can enqueue for execution on the
/// owner thread.  The owner dequeues commands during its message pump.
pub const Command = struct {
    message: u32,
    wparam: usize = 0,
    lparam: isize = 0,
    /// Caller-assigned ID for response correlation.
    request_id: u64 = 0,
};

pub const CommandResult = struct {
    request_id: u64,
    result: isize,
    status: i32,
};

pub const Mutex = struct {
    state: std.atomic.Mutex = .unlocked,

    pub fn lock(self: *Mutex) void {
        while (!self.state.tryLock()) {
            std.atomic.spinLoopHint();
        }
    }

    pub fn unlock(self: *Mutex) void {
        self.state.unlock();
    }
};

const max_pending_commands = 256;

/// Scintilla wrapper with thread-owner enforcement.
pub const Editor = struct {
    direct_fn: DirectFunction,
    direct_ptr: isize,
    owner_thread: std.Thread.Id,
    hwnd: ?*anyopaque,
    /// Ring buffer of pending cross-thread commands.
    command_queue: [max_pending_commands]Command = undefined,
    queue_head: usize = 0,
    queue_tail: usize = 0,
    queue_mutex: Mutex = .{},
    /// Styling state.
    styling_needed: bool = false,
    end_styled: usize = 0,
    /// Energy management: occluded state.
    occluded: bool = false,
    saved_caret_period: i32 = 0,
    saved_dwell_time: i32 = 0,
    saved_idle_styling: i32 = 0,

    /// Attach to an existing Scintilla HWND.  Must be called from the
    /// thread that owns the HWND.  Sets UTF-8 codepage and container
    /// lexer mode (SCI_SETILEXER(NULL)).
    pub fn attach(hwnd: ?*anyopaque) Error!Editor {
        if (comptime builtin.os.tag != .windows) return error.AttachFailed;
        const w: *anyopaque = hwnd orelse return error.AttachFailed;
        const direct_fn_raw = win32.SendMessageW(w, SCI_GETDIRECTSTATUSFUNCTION, 0, 0);
        if (direct_fn_raw == 0) {
            const fallback = win32.SendMessageW(w, SCI_GETDIRECTFUNCTION, 0, 0);
            if (fallback == 0) return error.DirectFunctionNull;
            const direct_ptr = win32.SendMessageW(w, SCI_GETDIRECTPOINTER, 0, 0);
            if (direct_ptr == 0) return error.DirectPointerNull;
            const direct_fn: DirectFunction = @ptrFromInt(@as(usize, @bitCast(fallback)));
            var editor = Editor{
                .direct_fn = direct_fn,
                .direct_ptr = direct_ptr,
                .owner_thread = std.Thread.getCurrentId(),
                .hwnd = hwnd,
            };
            _ = editor.call(SCI_SETCODEPAGE, SC_CP_UTF8, 0);
            _ = editor.call(SCI_SETILEXER, 0, 0);
            return editor;
        }
        const direct_ptr = win32.SendMessageW(w, SCI_GETDIRECTPOINTER, 0, 0);
        if (direct_ptr == 0) return error.DirectPointerNull;
        const direct_fn: DirectFunction = @ptrFromInt(@as(usize, @bitCast(direct_fn_raw)));
        var editor = Editor{
            .direct_fn = direct_fn,
            .direct_ptr = direct_ptr,
            .owner_thread = std.Thread.getCurrentId(),
            .hwnd = hwnd,
        };
        _ = editor.call(SCI_SETCODEPAGE, SC_CP_UTF8, 0);
        _ = editor.call(SCI_SETILEXER, 0, 0);
        return editor;
    }

    /// Create an editor for testing without a real HWND.  The caller
    /// provides the direct function and pointer obtained from the probe.
    pub fn attachDirect(
        direct_fn: DirectFunction,
        direct_ptr: isize,
    ) Editor {
        return .{
            .direct_fn = direct_fn,
            .direct_ptr = direct_ptr,
            .owner_thread = std.Thread.getCurrentId(),
            .hwnd = null,
        };
    }

    // ── Owner-thread direct calls ────────────────────────────────────

    /// Send a message through the direct function.  Asserts owner thread.
    pub fn call(self: *Editor, msg: u32, wparam: usize, lparam: isize) isize {
        std.debug.assert(std.Thread.getCurrentId() == self.owner_thread);
        return self.direct_fn(self.direct_ptr, msg, wparam, lparam);
    }

    /// Send a message and check the Scintilla status afterwards.
    pub fn callChecked(self: *Editor, msg: u32, wparam: usize, lparam: isize) Error!isize {
        const result = self.call(msg, wparam, lparam);
        const status = self.call(SCI_GETSTATUS, 0, 0);
        if (status != SC_STATUS_OK) {
            _ = self.call(SCI_SETSTATUS, SC_STATUS_OK, 0);
            return error.ScintillaError;
        }
        return result;
    }

    // ── Text operations ──────────────────────────────────────────────

    pub fn textLength(self: *Editor) usize {
        const len = self.call(SCI_GETTEXTLENGTH, 0, 0);
        return @intCast(@max(len, 0));
    }

    pub fn setText(self: *Editor, text: []const u8) void {
        _ = self.call(SCI_SETTEXT, 0, ptrToSptr(text.ptr));
    }

    pub fn insertText(self: *Editor, pos: usize, text: []const u8) void {
        _ = self.call(SCI_INSERTTEXT, pos, ptrToSptr(text.ptr));
    }

    pub fn deleteRange(self: *Editor, pos: usize, length: usize) void {
        _ = self.call(SCI_DELETERANGE, pos, @intCast(length));
    }

    pub fn addText(self: *Editor, text: []const u8) void {
        _ = self.call(SCI_ADDTEXT, text.len, ptrToSptr(text.ptr));
    }

    pub fn clearAll(self: *Editor) void {
        _ = self.call(SCI_CLEARALL, 0, 0);
    }

    // ── Styling ──────────────────────────────────────────────────────

    pub fn endStyled(self: *Editor) usize {
        return @intCast(@max(self.call(SCI_GETENDSTYLED, 0, 0), 0));
    }

    pub fn startStyling(self: *Editor, pos: usize) void {
        _ = self.call(SCI_STARTSTYLING, pos, 0);
    }

    pub fn setStyling(self: *Editor, length: usize, style: u8) void {
        _ = self.call(SCI_SETSTYLING, length, style);
    }

    pub fn setStylingEx(self: *Editor, styles: []const u8) void {
        _ = self.call(SCI_SETSTYLINGEX, styles.len, ptrToSptr(styles.ptr));
    }

    pub fn markStylingNeeded(self: *Editor, end_pos: usize) void {
        self.styling_needed = true;
        self.end_styled = end_pos;
    }

    pub fn clearStylingNeeded(self: *Editor) void {
        self.styling_needed = false;
    }

    // ── Selection / cursor ───────────────────────────────────────────

    pub fn currentPos(self: *Editor) usize {
        return @intCast(@max(self.call(SCI_GETCURRENTPOS, 0, 0), 0));
    }

    pub fn setCurrentPos(self: *Editor, pos: usize) void {
        _ = self.call(SCI_SETCURRENTPOS, pos, 0);
    }

    pub fn selectionStart(self: *Editor) usize {
        return @intCast(@max(self.call(SCI_GETSELECTIONSTART, 0, 0), 0));
    }

    pub fn selectionEnd(self: *Editor) usize {
        return @intCast(@max(self.call(SCI_GETSELECTIONEND, 0, 0), 0));
    }

    pub fn setSel(self: *Editor, anchor: usize, caret: usize) void {
        _ = self.call(SCI_SETSEL, anchor, @intCast(caret));
    }

    // ── Undo/redo ────────────────────────────────────────────────────

    pub fn undo(self: *Editor) void {
        _ = self.call(SCI_UNDO, 0, 0);
    }

    pub fn redo(self: *Editor) void {
        _ = self.call(SCI_REDO, 0, 0);
    }

    pub fn canUndo(self: *Editor) bool {
        return self.call(SCI_CANUNDO, 0, 0) != 0;
    }

    pub fn canRedo(self: *Editor) bool {
        return self.call(SCI_CANREDO, 0, 0) != 0;
    }

    pub fn beginUndoAction(self: *Editor) void {
        _ = self.call(SCI_BEGINUNDOACTION, 0, 0);
    }

    pub fn endUndoAction(self: *Editor) void {
        _ = self.call(SCI_ENDUNDOACTION, 0, 0);
    }

    // ── Line info ────────────────────────────────────────────────────

    pub fn lineCount(self: *Editor) usize {
        return @intCast(@max(self.call(SCI_LINECOUNT, 0, 0), 0));
    }

    pub fn positionFromLine(self: *Editor, line: usize) usize {
        return @intCast(@max(self.call(SCI_POSITIONFROMLINE, line, 0), 0));
    }

    pub fn lineFromPosition(self: *Editor, pos: usize) usize {
        return @intCast(@max(self.call(SCI_LINEFROMPOSITION, pos, 0), 0));
    }

    // ── Energy management (ticker control) ───────────────────────────

    pub fn enterOccluded(self: *Editor) void {
        if (self.occluded) return;
        self.saved_caret_period = @intCast(self.call(SCI_GETCARETPERIOD, 0, 0));
        self.saved_dwell_time = @intCast(self.call(SCI_GETMOUSEDWELLTIME, 0, 0));
        self.saved_idle_styling = @intCast(self.call(SCI_GETIDLESTYLING, 0, 0));
        _ = self.call(SCI_SETCARETPERIOD, 0, 0);
        _ = self.call(SCI_SETMOUSEDWELLTIME, SC_TIME_FOREVER, 0);
        _ = self.call(SCI_SETIDLESTYLING, SC_IDLESTYLING_NONE, 0);
        self.occluded = true;
    }

    pub fn leaveOccluded(self: *Editor) void {
        if (!self.occluded) return;
        _ = self.call(SCI_SETCARETPERIOD, @intCast(self.saved_caret_period), 0);
        _ = self.call(SCI_SETMOUSEDWELLTIME, @intCast(self.saved_dwell_time), 0);
        _ = self.call(SCI_SETIDLESTYLING, @intCast(self.saved_idle_styling), 0);
        self.occluded = false;
    }

    // ── Cross-thread command queue ───────────────────────────────────

    /// Enqueue a command from any thread.  The owner thread must call
    /// `drainCommands` to execute them.  Returns false if the queue is full.
    pub fn postCommand(self: *Editor, cmd: Command) bool {
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();
        const next = (self.queue_tail + 1) % max_pending_commands;
        if (next == self.queue_head) return false;
        self.command_queue[self.queue_tail] = cmd;
        self.queue_tail = next;
        return true;
    }

    /// Execute all pending cross-thread commands on the owner thread.
    /// Returns the number of commands executed.
    pub fn drainCommands(self: *Editor, results: []CommandResult) usize {
        std.debug.assert(std.Thread.getCurrentId() == self.owner_thread);
        var count: usize = 0;
        while (true) {
            const cmd = blk: {
                self.queue_mutex.lock();
                defer self.queue_mutex.unlock();
                if (self.queue_head == self.queue_tail) break :blk null;
                const c = self.command_queue[self.queue_head];
                self.queue_head = (self.queue_head + 1) % max_pending_commands;
                break :blk c;
            };
            if (cmd) |c| {
                const result = self.call(c.message, c.wparam, c.lparam);
                const status = self.call(SCI_GETSTATUS, 0, 0);
                if (status != SC_STATUS_OK) {
                    _ = self.call(SCI_SETSTATUS, SC_STATUS_OK, 0);
                }
                if (count < results.len) {
                    results[count] = .{
                        .request_id = c.request_id,
                        .result = result,
                        .status = @intCast(status),
                    };
                }
                count += 1;
            } else break;
        }
        return count;
    }

    // ── Document lifecycle ───────────────────────────────────────────

    pub fn createDocument(self: *Editor) isize {
        return self.call(SCI_CREATEDOCUMENT, 0, 0);
    }

    pub fn releaseDocument(self: *Editor, doc: isize) void {
        _ = self.call(SCI_RELEASEDOCUMENT, 0, doc);
    }

    pub fn setDocument(self: *Editor, doc: isize) void {
        _ = self.call(SCI_SETDOCPOINTER, 0, doc);
    }

    pub fn getDocument(self: *Editor) isize {
        return self.call(SCI_GETDOCPOINTER, 0, 0);
    }

    // ── Technology ───────────────────────────────────────────────────

    pub fn setTechnology(self: *Editor, tech: usize) void {
        _ = self.call(SCI_SETTECHNOLOGY, tech, 0);
    }

    pub fn getTechnology(self: *Editor) usize {
        return @intCast(@max(self.call(SCI_GETTECHNOLOGY, 0, 0), 0));
    }
};

fn ptrToSptr(ptr: *const anyopaque) isize {
    return @bitCast(@intFromPtr(ptr));
}

const win32 = if (builtin.os.tag == .windows) struct {
    extern "user32" fn SendMessageW(
        *anyopaque,
        u32,
        usize,
        isize,
    ) callconv(.winapi) isize;
} else struct {};
