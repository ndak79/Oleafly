//! Real Win32 Scintilla lifecycle probe.
//!
//! This module is intentionally independent from the build graph.  The
//! Windows target that consumes it must link the pinned Scintilla static
//! library produced by the existing source snapshot.  Non-Windows targets
//! only compile the declarations and return `.not_in_scope`; they never claim
//! native-window evidence.
const builtin = @import("builtin");
const std = @import("std");

pub const Target = enum {
    windows_x86_64_msvc,
    linux_compile_only,
    unsupported_windows,
};

pub const Fact = enum {
    scintilla_class_registered,
    parent_class_registered,
    parent_handle_valid,
    child_handle_valid,
    parent_child_relation_valid,
    direct_function_resolved,
    direct_pointer_resolved,
    document_created,
    document_released,
    null_lexer_selected,
    style_notification_seen,
    batched_styling_applied,
};

pub const Handle = enum { parent, child };

pub const Facts = struct {
    scintilla_class_registered: bool = false,
    parent_class_registered: bool = false,
    parent_handle_valid: bool = false,
    child_handle_valid: bool = false,
    parent_child_relation_valid: bool = false,
    direct_function_resolved: bool = false,
    direct_pointer_resolved: bool = false,
    document_created: bool = false,
    document_released: bool = false,
    null_lexer_selected: bool = false,
    style_notification_seen: bool = false,
    batched_styling_applied: bool = false,
};

pub const Win32Operation = enum {
    get_module_handle,
    register_parent_class,
    register_scintilla_class,
    create_parent_window,
    create_scintilla_window,
    destroy_scintilla_window,
    release_scintilla_resources,
    destroy_parent_window,
    unregister_parent_class,
};

pub const Win32Failure = struct {
    operation: Win32Operation,
    last_error: u32,
};

pub const Result = union(enum) {
    satisfied: Facts,
    not_in_scope: Target,
    missing_fact: Fact,
    invalid_handle: Handle,
    win32_failure: Win32Failure,
};

/// Evaluate facts independently of Win32.  Keeping this oracle pure makes
/// missing-notification and invalid-handle behavior testable on Linux.
pub fn evaluate(target: Target, facts: Facts) Result {
    if (target != .windows_x86_64_msvc) return .{ .not_in_scope = target };

    if (!facts.parent_handle_valid) return .{ .invalid_handle = .parent };
    if (!facts.child_handle_valid) return .{ .invalid_handle = .child };

    const required = [_]struct { fact: Fact, value: bool }{
        .{ .fact = .scintilla_class_registered, .value = facts.scintilla_class_registered },
        .{ .fact = .parent_class_registered, .value = facts.parent_class_registered },
        .{ .fact = .parent_child_relation_valid, .value = facts.parent_child_relation_valid },
        .{ .fact = .direct_function_resolved, .value = facts.direct_function_resolved },
        .{ .fact = .direct_pointer_resolved, .value = facts.direct_pointer_resolved },
        .{ .fact = .document_created, .value = facts.document_created },
        .{ .fact = .document_released, .value = facts.document_released },
        .{ .fact = .null_lexer_selected, .value = facts.null_lexer_selected },
        .{ .fact = .style_notification_seen, .value = facts.style_notification_seen },
        .{ .fact = .batched_styling_applied, .value = facts.batched_styling_applied },
    };
    for (required) |item| {
        if (!item.value) return .{ .missing_fact = item.fact };
    }
    return .{ .satisfied = facts };
}

pub fn currentTarget() Target {
    if (builtin.os.tag != .windows) return .linux_compile_only;
    if (builtin.cpu.arch != .x86_64 or builtin.abi != .msvc) return .unsupported_windows;
    return .windows_x86_64_msvc;
}

pub fn run() Result {
    // Keep the Win32 extern set out of non-Windows compile-only artifacts.
    // A normal runtime conditional is not sufficient: Zig still resolves
    // referenced DLLs while compiling the function body for Linux.
    if (comptime builtin.os.tag != .windows) return .{ .not_in_scope = .linux_compile_only };
    if (comptime builtin.cpu.arch != .x86_64 or builtin.abi != .msvc) return .{ .not_in_scope = .unsupported_windows };
    return runWindows();
}

// Scintilla 5.6.6 deliberately has no legacy SCI_SETLEXER message.  The
// supported no-Lexilla path is SCI_SETILEXER(NULL), which reports
// SCLEX_CONTAINER (0).  Lexilla's SCLEX_NULL (1) is therefore not claimed or
// loaded by this probe.
pub const sclex_container: usize = 0;
pub const sclex_null: usize = 1;

const sci_set_text: u32 = 2181;
const sci_get_text_length: u32 = 2183;
const sci_get_direct_function: u32 = 2184;
const sci_get_direct_pointer: u32 = 2185;
const sci_get_style_at: u32 = 2010;
const sci_start_styling: u32 = 2032;
const sci_set_styling: u32 = 2033;
const sci_createdocument: u32 = 2375;
const sci_releasedocument: u32 = 2377;
const sci_get_lexer: u32 = 4002;
const sci_colourise: u32 = 4003;
const sci_set_ilexer: u32 = 4033;
const scn_styleneeded: u32 = 2000;

const ws_child: u32 = 0x40000000;
const wm_nccreate: u32 = 0x0081;
const wm_ncdestroy: u32 = 0x0082;
const wm_notify: u32 = 0x004e;
const gwlp_userdata: i32 = -21;
const sw_hide: i32 = 0;

const DirectFunction = *const fn (isize, u32, usize, isize) callconv(.c) isize;

const NotifyHeader = extern struct {
    hwnd_from: ?*anyopaque,
    id_from: usize,
    code: u32,
};

const StyleNotification = extern struct {
    header: NotifyHeader,
    position: isize,
};

const ProbeState = struct {
    facts: Facts = .{},
    parent: ?*anyopaque = null,
    child: ?*anyopaque = null,
    direct_function: ?DirectFunction = null,
    direct_pointer: isize = 0,
    styling_requested: bool = false,
};

const windows = struct {
    const WNDPROC = *const fn (*anyopaque, u32, usize, isize) callconv(.winapi) isize;

    const WNDCLASSEXW = extern struct {
        cb_size: u32,
        style: u32,
        lpfn_wnd_proc: WNDPROC,
        cb_cls_extra: i32,
        cb_wnd_extra: i32,
        h_instance: *anyopaque,
        h_icon: ?*anyopaque,
        h_cursor: ?*anyopaque,
        hbr_background: ?*anyopaque,
        lpsz_menu_name: ?[*:0]const u16,
        lpsz_class_name: [*:0]const u16,
        h_icon_sm: ?*anyopaque,
    };

    const CREATESTRUCTW = extern struct {
        lp_create_params: ?*anyopaque,
        h_instance: *anyopaque,
        h_menu: ?*anyopaque,
        hwnd_parent: ?*anyopaque,
        cy: i32,
        cx: i32,
        y: i32,
        x: i32,
        style: i32,
        lpsz_name: [*:0]const u16,
        lpsz_class: [*:0]const u16,
        dw_ex_style: u32,
    };

    extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
    extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.winapi) u16;
    extern "user32" fn UnregisterClassW([*:0]const u16, *anyopaque) callconv(.winapi) i32;
    extern "user32" fn CreateWindowExW(
        u32,
        [*:0]const u16,
        [*:0]const u16,
        u32,
        i32,
        i32,
        i32,
        i32,
        ?*anyopaque,
        ?*anyopaque,
        *anyopaque,
        ?*anyopaque,
    ) callconv(.winapi) ?*anyopaque;
    extern "user32" fn DestroyWindow(*anyopaque) callconv(.winapi) i32;
    extern "user32" fn ShowWindow(*anyopaque, i32) callconv(.winapi) i32;
    extern "user32" fn IsWindow(?*anyopaque) callconv(.winapi) i32;
    extern "user32" fn GetParent(*anyopaque) callconv(.winapi) ?*anyopaque;
    extern "user32" fn SendMessageW(*anyopaque, u32, usize, isize) callconv(.winapi) isize;
    extern "user32" fn DefWindowProcW(*anyopaque, u32, usize, isize) callconv(.winapi) isize;
    extern "user32" fn GetWindowLongPtrW(*anyopaque, i32) callconv(.winapi) isize;
    extern "user32" fn SetWindowLongPtrW(*anyopaque, i32, isize) callconv(.winapi) isize;

    extern fn Scintilla_RegisterClasses(?*anyopaque) callconv(.c) c_int;
    extern fn Scintilla_ReleaseResources() callconv(.c) c_int;
};

const parent_class_name = std.unicode.utf8ToUtf16LeStringLiteral("TExFlowScintillaNativeProbe");
const parent_window_title = std.unicode.utf8ToUtf16LeStringLiteral("TExFlow Scintilla native probe");
const scintilla_class_name = std.unicode.utf8ToUtf16LeStringLiteral("Scintilla");

fn ptrToSptr(ptr: *const anyopaque) isize {
    return @bitCast(@intFromPtr(ptr));
}

fn stateFromWindow(hwnd: *anyopaque) ?*ProbeState {
    const value = windows.GetWindowLongPtrW(hwnd, gwlp_userdata);
    if (value == 0) return null;
    return @ptrFromInt(@as(usize, @bitCast(value)));
}

fn parentWndProc(hwnd: *anyopaque, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
    if (message == wm_nccreate and lparam != 0) {
        const create: *const windows.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
        if (create.lp_create_params) |params| {
            _ = windows.SetWindowLongPtrW(hwnd, gwlp_userdata, @bitCast(@intFromPtr(params)));
        }
    }

    const state = stateFromWindow(hwnd);
    if (message == wm_notify and lparam != 0) {
        if (state) |probe| {
            const notification: *const StyleNotification = @ptrFromInt(@as(usize, @bitCast(lparam)));
            if (notification.header.code == scn_styleneeded and notification.header.hwnd_from == probe.child) {
                probe.facts.style_notification_seen = true;
                if (probe.direct_function) |direct| {
                    if (probe.direct_pointer != 0) {
                        _ = direct(probe.direct_pointer, sci_start_styling, 0, 0xff);
                        _ = direct(probe.direct_pointer, sci_set_styling, 4, 1);
                        _ = direct(probe.direct_pointer, sci_set_styling, 4, 2);
                        probe.styling_requested = true;
                    }
                }
                return 0;
            }
        }
    }

    if (message == wm_ncdestroy) {
        _ = windows.SetWindowLongPtrW(hwnd, gwlp_userdata, 0);
    }
    return windows.DefWindowProcW(hwnd, message, wparam, lparam);
}

const Cleanup = struct {
    instance: *anyopaque,
    parent_class_registered: bool = false,
    scintilla_class_registered: bool = false,
    parent: ?*anyopaque = null,
    child: ?*anyopaque = null,

    fn deinit(self: *Cleanup) ?Win32Failure {
        if (self.child) |child| {
            if (windows.DestroyWindow(child) == 0) return .{ .operation = .destroy_scintilla_window, .last_error = windows.GetLastError() };
            self.child = null;
        }
        if (self.scintilla_class_registered) {
            if (windows.Scintilla_ReleaseResources() == 0) return .{ .operation = .release_scintilla_resources, .last_error = windows.GetLastError() };
            self.scintilla_class_registered = false;
        }
        if (self.parent) |parent| {
            if (windows.DestroyWindow(parent) == 0) return .{ .operation = .destroy_parent_window, .last_error = windows.GetLastError() };
            self.parent = null;
        }
        if (self.parent_class_registered) {
            if (windows.UnregisterClassW(parent_class_name, self.instance) == 0) return .{ .operation = .unregister_parent_class, .last_error = windows.GetLastError() };
            self.parent_class_registered = false;
        }
        return null;
    }
};

fn runWindows() Result {
    var state = ProbeState{};
    const instance = windows.GetModuleHandleW(null) orelse return .{ .win32_failure = .{ .operation = .get_module_handle, .last_error = windows.GetLastError() } };
    var cleanup = Cleanup{ .instance = instance };
    defer _ = cleanup.deinit();

    const parent_class: windows.WNDCLASSEXW = .{
        .cb_size = @sizeOf(windows.WNDCLASSEXW),
        .style = 0,
        .lpfn_wnd_proc = parentWndProc,
        .cb_cls_extra = 0,
        .cb_wnd_extra = 0,
        .h_instance = instance,
        .h_icon = null,
        .h_cursor = null,
        .hbr_background = null,
        .lpsz_menu_name = null,
        .lpsz_class_name = parent_class_name,
        .h_icon_sm = null,
    };
    if (windows.RegisterClassExW(&parent_class) == 0) return .{ .win32_failure = .{ .operation = .register_parent_class, .last_error = windows.GetLastError() } };
    cleanup.parent_class_registered = true;
    state.facts.parent_class_registered = true;

    if (windows.Scintilla_RegisterClasses(instance) == 0) return .{ .win32_failure = .{ .operation = .register_scintilla_class, .last_error = windows.GetLastError() } };
    cleanup.scintilla_class_registered = true;
    state.facts.scintilla_class_registered = true;

    const parent = windows.CreateWindowExW(0, parent_class_name, parent_window_title, 0, 0, 0, 64, 64, null, null, instance, @ptrCast(&state)) orelse
        return .{ .win32_failure = .{ .operation = .create_parent_window, .last_error = windows.GetLastError() } };
    cleanup.parent = parent;
    state.parent = parent;
    _ = windows.ShowWindow(parent, sw_hide);
    if (windows.IsWindow(parent) == 0) return .{ .invalid_handle = .parent };
    state.facts.parent_handle_valid = true;

    const child = windows.CreateWindowExW(0, scintilla_class_name, parent_window_title, ws_child, 0, 0, 64, 64, parent, null, instance, null) orelse
        return .{ .win32_failure = .{ .operation = .create_scintilla_window, .last_error = windows.GetLastError() } };
    cleanup.child = child;
    state.child = child;
    if (windows.IsWindow(child) == 0) return .{ .invalid_handle = .child };
    state.facts.child_handle_valid = true;
    if (windows.GetParent(child) != parent) return .{ .missing_fact = .parent_child_relation_valid };
    state.facts.parent_child_relation_valid = true;

    const direct_function_raw = windows.SendMessageW(child, sci_get_direct_function, 0, 0);
    if (direct_function_raw == 0) return .{ .missing_fact = .direct_function_resolved };
    state.direct_function = @ptrFromInt(@as(usize, @bitCast(direct_function_raw)));
    state.facts.direct_function_resolved = true;

    state.direct_pointer = windows.SendMessageW(child, sci_get_direct_pointer, 0, 0);
    if (state.direct_pointer == 0) return .{ .missing_fact = .direct_pointer_resolved };
    state.facts.direct_pointer_resolved = true;
    const direct = state.direct_function.?;

    const document = direct(state.direct_pointer, sci_createdocument, 0, 0);
    if (document == 0) return .{ .missing_fact = .document_created };
    state.facts.document_created = true;
    _ = direct(state.direct_pointer, sci_releasedocument, 0, document);
    state.facts.document_released = true;

    _ = direct(state.direct_pointer, sci_set_ilexer, 0, 0);
    const lexer = direct(state.direct_pointer, sci_get_lexer, 0, 0);
    if (lexer != sclex_container) return .{ .missing_fact = .null_lexer_selected };
    state.facts.null_lexer_selected = true;

    const text = "abcdEFGH";
    _ = direct(state.direct_pointer, sci_set_text, 0, ptrToSptr(@ptrCast(text.ptr)));
    if (direct(state.direct_pointer, sci_get_text_length, 0, 0) != text.len) return .{ .missing_fact = .batched_styling_applied };
    _ = direct(state.direct_pointer, sci_colourise, 0, -1);
    if (!state.facts.style_notification_seen or !state.styling_requested) return .{ .missing_fact = .style_notification_seen };

    const first_style = direct(state.direct_pointer, sci_get_style_at, 0, 0);
    const second_style = direct(state.direct_pointer, sci_get_style_at, 4, 0);
    if (first_style != 1 or second_style != 2) return .{ .missing_fact = .batched_styling_applied };
    state.facts.batched_styling_applied = true;

    if (cleanup.deinit()) |failure| return .{ .win32_failure = failure };
    return evaluate(.windows_x86_64_msvc, state.facts);
}
