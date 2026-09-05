const std = @import("std");
const builtin = @import("builtin");
const native = @import("shell_native");
const graphics = @import("graphics");
const shell = @import("windows_shell");
const com = @import("windows_com");
const w = std.unicode.utf8ToUtf16LeStringLiteral;

test "narrow Win32 declarations retain x64 SDK structure layouts and flags" {
    if (builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(native.WNDCLASSEXW));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(native.WNDCLASSEXW, "lpfnWndProc"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(native.WNDCLASSEXW, "hInstance"));
    try std.testing.expectEqual(@as(usize, 64), @offsetOf(native.WNDCLASSEXW, "lpszClassName"));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(native.MSG));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(native.MSG, "wParam"));
    try std.testing.expectEqual(@as(usize, 36), @offsetOf(native.MSG, "pt"));
    try std.testing.expectEqual(@as(u32, 0x800), native.dll_search_flags);
    try std.testing.expectEqual(@as(u32, 0xcf0000), native.window_style);
    try std.testing.expectEqual(@as(isize, -4), @as(isize, @bitCast(@intFromPtr(native.dpi_pmv2))));
}

test "DPI admission accepts only a non-null context proven equal to PMv2" {
    const pmv2: *anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -4))));
    const pmv1: *anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -2))));
    try std.testing.expect(native.acceptPmv2Context(pmv2, true));
    try std.testing.expect(!native.acceptPmv2Context(pmv1, false));
    try std.testing.expect(!native.acceptPmv2Context(null, false));
}

const Forbidden = struct {
    calls: usize = 0,
    pub fn restrictDllSearch(self: *@This()) bool {
        self.calls += 1;
        return false;
    }
    pub fn setDpiAwareness(_: *@This()) bool {
        unreachable;
    }
    pub fn initializeCom(_: *@This()) bool {
        unreachable;
    }
    pub fn uninitializeCom(_: *@This()) void {
        unreachable;
    }
    pub fn registerClass(_: *@This()) bool {
        unreachable;
    }
    pub fn unregisterClass(_: *@This()) bool {
        unreachable;
    }
    pub fn createWindow(_: *@This()) bool {
        unreachable;
    }
    pub fn destroyWindow(_: *@This()) bool {
        unreachable;
    }
    pub fn showWindow(_: *@This()) void {
        unreachable;
    }
    pub fn getMessage(_: *@This()) i32 {
        unreachable;
    }
    pub fn dispatchMessage(_: *@This()) void {
        unreachable;
    }
};

test "real native argv parser rejects invalid admission before backend setup" {
    @setEvalBranchQuota(10_000);
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const lines = [_][*:0]const u16{
        w("TExFlow.exe --worker"),                                                 w("TExFlow.exe --probe"),                                                                                       w("TExFlow.exe --internal"),
        w("TExFlow.exe --bootstrap-handle=7"),                                     w("TExFlow.exe --worker-bootstrap-handle=7"),                                                                   w("TExFlow.exe --trace-trial 00112233445566778899aabbccddeeff"),
        w("TExFlow.exe --trace-trial=00112233445566778899aabbccddeeff --unknown"), w("TExFlow.exe --trace-trial=00112233445566778899aabbccddeeff --trace-trial=00112233445566778899aabbccddeeff"), w("TExFlow.exe --trace-trial=00112233445566778899AABBCCDDEEFF"),
        w("TExFlow.exe --\u{1f642}"),
    };
    for (lines) |line| {
        var backend: Forbidden = .{};
        try std.testing.expectEqual(shell.ExitCode.admission_failed, native.runCommandLine(std.testing.allocator, line, &backend).code);
        try std.testing.expectEqual(@as(usize, 0), backend.calls);
    }
    const invalid = [_:0]u16{ 'T', 0xd800 };
    for ([_][*:0]const u16{ &invalid, w(""), w(" TExFlow.exe") }) |line| {
        var backend: Forbidden = .{};
        try std.testing.expectEqual(shell.ExitCode.command_line_failed, native.runCommandLine(std.testing.allocator, line, &backend).code);
        try std.testing.expectEqual(@as(usize, 0), backend.calls);
    }
}

test "native parser excludes Unicode argv0 and accepts quoted trial or OS entropy" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var backend: Forbidden = .{};
    var result = native.runCommandLine(std.testing.allocator, w("\"C:\\\u{3b1} dir\\TExFlow.exe\" \"--trace-trial=00112233445566778899aabbccddeeff\""), &backend);
    try std.testing.expectEqual(shell.ExitCode.dll_search_failed, result.code);
    try std.testing.expectEqual(.supplied, result.admission.?.origin);
    try std.testing.expectEqual(@as(u8, 0xff), result.admission.?.trace_trial[15]);
    try std.testing.expectEqual(@as(usize, 1), backend.calls);
    backend = .{};
    result = native.runCommandLine(std.testing.allocator, w("TExFlow.exe"), &backend);
    try std.testing.expectEqual(shell.ExitCode.dll_search_failed, result.code);
    try std.testing.expectEqual(.generated, result.admission.?.origin);
    try std.testing.expectEqual(@as(usize, 1), backend.calls);
}

test "real COM STA accepts nested initialization and balances both releases" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const raw = struct {
        extern "ole32" fn CoGetApartmentType(*i32, *i32) callconv(.winapi) i32;
    };
    var depth: u2 = 0;
    defer while (depth > 0) : (depth -= 1) com.uninitialize();
    try std.testing.expect(com.initializeSta());
    depth += 1;
    try std.testing.expect(com.initializeSta()); // S_FALSE still owns a release.
    depth += 1;
    var apartment: i32 = undefined;
    var qualifier: i32 = undefined;
    try std.testing.expectEqual(@as(i32, 0), raw.CoGetApartmentType(&apartment, &qualifier));
    try std.testing.expect(apartment == 0 or apartment == 3); // STA or MAINSTA
    com.uninitialize();
    depth -= 1;
    try std.testing.expectEqual(@as(i32, 0), raw.CoGetApartmentType(&apartment, &qualifier));
    com.uninitialize();
    depth -= 1;
    try std.testing.expect(raw.CoGetApartmentType(&apartment, &qualifier) < 0);
}

fn exerciseNativeAllocations(allocator: std.mem.Allocator) !void {
    var backend: Forbidden = .{};
    const result = native.runCommandLine(allocator, w("TExFlow.exe --trace-trial=00112233445566778899aabbccddeeff"), &backend);
    if (result.code == .admission_failed) {
        try std.testing.expectEqual(@as(usize, 0), backend.calls);
        return error.OutOfMemory;
    }
    try std.testing.expectEqual(shell.ExitCode.dll_search_failed, result.code);
    try std.testing.expectEqual(@as(usize, 1), backend.calls);
}

test "native command line frees conversions and skips setup on every allocator fault" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseNativeAllocations, .{});
}

test "real COM changed-mode failure preserves the callers existing MTA" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const raw = struct {
        extern "ole32" fn CoInitializeEx(?*anyopaque, u32) callconv(.winapi) i32;
        extern "ole32" fn CoGetApartmentType(*i32, *i32) callconv(.winapi) i32;
    };
    try std.testing.expectEqual(@as(i32, 0), raw.CoInitializeEx(null, 0)); // MTA
    defer com.uninitialize();
    try std.testing.expect(!com.initializeSta());
    var apartment: i32 = undefined;
    var qualifier: i32 = undefined;
    try std.testing.expectEqual(@as(i32, 0), raw.CoGetApartmentType(&apartment, &qualifier));
    try std.testing.expectEqual(@as(i32, 1), apartment);
}

test "native backend owns the first-frame render resources" {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    try std.testing.expect(@hasField(native.Backend, "swap_chain"));
    try std.testing.expect(@hasField(native.Backend, "back_buffer"));
}

test "native shell uses the admitted sequential baseline unless explicitly challenged" {
    const effect = native.configuredSwapEffect();
    try std.testing.expect(effect == graphics.SwapEffect.flip_sequential or effect == graphics.SwapEffect.flip_discard);
}

test "real native backend creates and presents its first frame before showing" {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    const raw = struct {
        extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.winapi) ?*anyopaque;
    };
    const instance = raw.GetModuleHandleW(null) orelse return error.SkipZigTest;
    var backend: native.Backend = .{ .instance = @ptrCast(instance), .show = 0 };
    try std.testing.expect(backend.registerClass());
    defer _ = backend.unregisterClass();
    try std.testing.expect(backend.createWindow());
    defer _ = backend.destroyWindow();
    try std.testing.expect(backend.hasFrameResources());
    try std.testing.expect(backend.renderFrame());
    backend.showWindow();
    try std.testing.expect(backend.frameTimerActive());
    try std.testing.expect(backend.tickFrame());
    try std.testing.expect(backend.resizeFrame(640, 480));
    try std.testing.expect(backend.rebuildFrameResources());
    try std.testing.expect(backend.destroyWindow());
    try std.testing.expect(!backend.hasFrameResources());
}

test "native frame admission rejects device-loss present outcomes" {
    try std.testing.expect(native.renderOutcomeUsable(.presented));
    try std.testing.expect(native.renderOutcomeUsable(.occluded));
    try std.testing.expect(!native.renderOutcomeUsable(.device_removed));
    try std.testing.expect(!native.renderOutcomeUsable(.device_reset));
    try std.testing.expect(!native.renderOutcomeUsable(.device_hung));
}

test "native shell routes only paint resize and its frame timer to rendering" {
    try std.testing.expect(native.isPaintMessage(0x000f));
    try std.testing.expect(native.isResizeMessage(0x0005));
    try std.testing.expect(native.isFrameTimerMessage(0x0113, native.frame_timer_id));
    try std.testing.expect(!native.isFrameTimerMessage(0x0113, native.frame_timer_id + 1));
    try std.testing.expect(!native.isFrameTimerMessage(0x000f, native.frame_timer_id));
}
