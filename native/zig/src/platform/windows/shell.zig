//! Portable startup/teardown contract for the UI shell. The backend owns native
//! resources; only successful acquisitions are released, in reverse order.
//! No Win32 imports, renderer, database, network, worker or command-line seams.
const std = @import("std");
const entry = @import("ui_entry");

pub const ExitCode = enum(i32) {
    success = 0,
    admission_failed = 2,
    command_line_failed = 3,
    dll_search_failed = 10,
    dpi_failed = 11,
    com_failed = 12,
    class_failed = 13,
    window_failed = 14,
    message_failed = 15,
    window_cleanup_failed = 16,
    class_cleanup_failed = 17,
};
pub const Result = struct { code: ExitCode = .success, admission: ?entry.Admission = null };

/// Arguments exclude argv[0]. Strict UTF-16 decoding and complete admission
/// finish before the first backend call; all conversion buffers are temporary.
pub fn admitWide(allocator: std.mem.Allocator, arguments: []const [*:0]const u16, entropy: entry.Entropy) !entry.Admission {
    const utf8 = try allocator.alloc([]const u8, arguments.len);
    var initialized: usize = 0;
    defer {
        for (utf8[0..initialized]) |argument| allocator.free(argument);
        allocator.free(utf8);
    }
    for (arguments, 0..) |argument, index| {
        utf8[index] = try std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.span(argument));
        initialized += 1;
    }
    return entry.admit(utf8, entropy);
}

pub fn run(allocator: std.mem.Allocator, arguments: []const [*:0]const u16, entropy: entry.Entropy, backend: anytype) Result {
    const admission = admitWide(allocator, arguments, entropy) catch return .{ .code = .admission_failed };
    var result: Result = .{ .admission = admission };
    runAdmitted(backend, &result.code);
    return result;
}

fn runAdmitted(backend: anytype, code: *ExitCode) void {
    if (!backend.restrictDllSearch()) {
        code.* = .dll_search_failed;
        return;
    }
    if (!backend.setDpiAwareness()) {
        code.* = .dpi_failed;
        return;
    }
    if (!backend.initializeCom()) {
        code.* = .com_failed;
        return;
    }
    defer backend.uninitializeCom();
    if (!backend.registerClass()) {
        code.* = .class_failed;
        return;
    }
    defer if (!backend.unregisterClass() and code.* == .success) {
        code.* = .class_cleanup_failed;
    };
    if (!backend.createWindow()) {
        code.* = .window_failed;
        return;
    }
    defer if (!backend.destroyWindow() and code.* == .success) {
        code.* = .window_cleanup_failed;
    };
    backend.showWindow();
    while (true) {
        const status = backend.getMessage();
        if (status < 0) {
            code.* = .message_failed;
            return;
        }
        if (status == 0) return;
        backend.dispatchMessage();
    }
}
