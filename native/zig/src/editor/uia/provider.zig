//! UIA text provider contract for the editor.
//!
//! This module defines the portable provider interface and its pattern
//! support declarations.  The actual COM/UIA wiring is Windows-only and
//! uses the snapshot/range/thread modules.  On non-Windows targets, the
//! provider compiles as a structural contract only.
//!
//! The provider advertises:
//!   - ITextProvider2 (Document control type)
//!   - ITextEditProvider
//!   - IScrollProvider
//!   - IRawElementProviderSimple (ServerSideProvider | UseComThreading)
//!   - IRawElementProviderFragment / FragmentRoot
//!
//! It does NOT advertise IValueProvider for this multiline document.

const std = @import("std");
const snapshot_mod = @import("uia_snapshot");
const range_mod = @import("uia_range");
const thread_mod = @import("uia_thread");

pub const PatternId = enum(u32) {
    text = 10014,
    text2 = 10024,
    text_edit = 10032,
    scroll = 10004,
    value = 10002,
};

pub const ControlType = enum(u32) {
    document = 50030,
};

pub const ProviderOptions = enum(u32) {
    server_side = 0x1,
    use_com_threading = 0x20,
};

/// Portable provider state — no COM pointers, just typed contracts.
pub const Provider = struct {
    thread: *thread_mod.ProviderThread,
    control_type: ControlType = .document,
    /// Supported pattern IDs.
    supported_patterns: [4]PatternId = .{
        .text,
        .text2,
        .text_edit,
        .scroll,
    },
    /// Whether this provider has been connected to UIA.
    connected: bool = false,
    /// Runtime ID components for UIA discovery.
    runtime_id: [2]u32 = .{ 0, 0 },

    pub fn init(prov_thread: *thread_mod.ProviderThread) Provider {
        return .{
            .thread = prov_thread,
        };
    }

    pub fn supportsPattern(self: *const Provider, pattern: PatternId) bool {
        for (self.supported_patterns) |p| {
            if (p == pattern) return true;
        }
        return false;
    }

    pub fn isValuePatternSupported(_: *const Provider) bool {
        return false;
    }

    pub fn documentRange(self: *Provider) ?range_mod.Range {
        const snap = self.thread.getSnapshot() orelse return null;
        const byte_len = snap.byteLen();
        const utf16_len = snap.utf16Length();
        return range_mod.Range.init(
            0,
            0,
            0,
            byte_len,
            utf16_len,
            snap.revision,
            self.thread.journal_generation,
        );
    }

    pub fn caretRange(self: *Provider) ?range_mod.Range {
        const snap = self.thread.getSnapshot() orelse return null;
        const caret = snap.caret_byte;
        const caret_utf16 = snap.index.byteToUtf16(caret) catch 0;
        return range_mod.Range.init(
            0,
            caret,
            caret_utf16,
            caret,
            caret_utf16,
            snap.revision,
            self.thread.journal_generation,
        );
    }

    pub fn getText(self: *Provider, max_length: usize) ?[]const u8 {
        const snap = self.thread.getSnapshot() orelse return null;
        const text = snap.text();
        if (max_length == 0 or max_length >= text.len) return text;
        // Find a valid UTF-8 boundary at or before max_length.
        var end = max_length;
        while (end > 0 and text[end] >= 0x80 and text[end] < 0xC0) {
            end -= 1;
        }
        return text[0..end];
    }

    pub fn connect(self: *Provider, runtime_id_0: u32, runtime_id_1: u32) void {
        self.runtime_id = .{ runtime_id_0, runtime_id_1 };
        self.connected = true;
    }

    pub fn disconnect(self: *Provider) void {
        self.connected = false;
        self.thread.range_pool.invalidateAll();
    }

    /// Request a mutation through the provider thread.
    pub fn requestMutation(
        self: *Provider,
        kind: thread_mod.MutationKind,
        arg0: usize,
        arg1: usize,
    ) ?u64 {
        const snap = self.thread.getSnapshot() orelse return null;
        const req_id = self.thread.allocateRequestId();
        const cmd = thread_mod.MutationCommand{
            .kind = kind,
            .request_id = req_id,
            .revision = snap.revision,
            .arg0 = arg0,
            .arg1 = arg1,
        };
        if (!self.thread.postMutation(cmd)) return null;
        return req_id;
    }
};
