//! Narrow product checks, not a release/security PE audit. Runtime probes own
//! and close only processes/windows they create; they never inspect other apps.
const std = @import("std");
const builtin = @import("builtin");
const contract = @import("product_contract");
const argv = @import("windows_argv");
const windows = std.os.windows;
const w = std.unicode.utf8ToUtf16LeStringLiteral;
const supported = builtin.os.tag == .windows and builtin.cpu.arch == .x86_64;

test "product exists only for x64 Windows and installs as TExFlow GUI" {
    try std.testing.expectEqual(supported, contract.has_product);
    if (!supported) {
        try std.testing.expect(contract.install_empty);
        return;
    }
    try std.testing.expectEqualStrings("TExFlow", contract.product_name);
    try std.testing.expectEqualStrings("TExFlow.exe", std.fs.path.basename(contract.path));
    try std.testing.expect(contract.install_reaches_product);
}

fn read(comptime T: type, bytes: []const u8, offset: usize) !T {
    if (offset > bytes.len or @sizeOf(T) > bytes.len - offset) return error.TruncatedPe;
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}

fn rvaOffset(bytes: []const u8, pe: usize, rva: u32) !usize {
    const count = try read(u16, bytes, pe + 6);
    const table = pe + 24 + try read(u16, bytes, pe + 20);
    for (0..count) |index| {
        const section = table + index * 40;
        const base = try read(u32, bytes, section + 12);
        const size = try read(u32, bytes, section + 16);
        if (rva >= base and rva - base < size) {
            const offset = @as(usize, try read(u32, bytes, section + 20)) + rva - base;
            if (offset >= bytes.len) return error.TruncatedPe;
            return offset;
        }
    }
    return error.UnmappedPeRva;
}

fn peString(bytes: []const u8, offset: usize) ![]const u8 {
    if (offset >= bytes.len) return error.TruncatedPe;
    const end = std.mem.indexOfScalar(u8, bytes[offset..], 0) orelse return error.UnterminatedPeString;
    return bytes[offset..][0..end];
}

test "actual product PE is AMD64 GUI with narrow Unicode shell imports" {
    if (!supported) return error.SkipZigTest;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, contract.path, std.testing.allocator, .limited(32 * 1024 * 1024));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("MZ", bytes[0..2]);
    const pe = try read(u32, bytes, 0x3c);
    try std.testing.expectEqual(@as(u32, 0x4550), try read(u32, bytes, pe));
    try std.testing.expectEqual(@as(u16, 0x8664), try read(u16, bytes, pe + 4));
    try std.testing.expectEqual(@as(u16, 0x20b), try read(u16, bytes, pe + 24));
    try std.testing.expectEqual(@as(u16, 2), try read(u16, bytes, pe + 24 + 68));
    try std.testing.expect((try read(u32, bytes, pe + 24 + 16)) != 0);
    const required = [_][]const u8{
        "GetCommandLineW", "CommandLineToArgvW", "SetDefaultDllDirectories", "SetProcessDpiAwarenessContext",
        "CoInitializeEx",  "CoUninitialize",     "RegisterClassExW",         "CreateWindowExW",
        "ShowWindow",      "GetMessageW",        "TranslateMessage",         "DispatchMessageW",
        "DestroyWindow",   "UnregisterClassW",   "BCryptGenRandom",
    };
    var found = [_]bool{false} ** required.len;
    var descriptor = try rvaOffset(bytes, pe, try read(u32, bytes, pe + 24 + 120));
    var imported_dlls: usize = 0;
    while (try read(u32, bytes, descriptor + 12) != 0) : (descriptor += 20) {
        imported_dlls += 1;
        if (imported_dlls > 16) return error.ExcessiveImports;
        const dll = try peString(bytes, try rvaOffset(bytes, pe, try read(u32, bytes, descriptor + 12)));
        var allowed = false;
        for ([_][]const u8{ "kernel32.dll", "ntdll.dll", "user32.dll", "shell32.dll", "ole32.dll", "bcrypt.dll" }) |name| {
            allowed = allowed or std.ascii.eqlIgnoreCase(dll, name);
        }
        try std.testing.expect(allowed);
        const original = try read(u32, bytes, descriptor);
        var thunk = try rvaOffset(bytes, pe, if (original != 0) original else try read(u32, bytes, descriptor + 16));
        while (try read(u64, bytes, thunk) != 0) : (thunk += 8) {
            const name_rva = try read(u64, bytes, thunk);
            try std.testing.expect(name_rva <= std.math.maxInt(u32));
            const name = try peString(bytes, (try rvaOffset(bytes, pe, @intCast(name_rva))) + 2);
            for (required, 0..) |expected, index| found[index] = found[index] or std.mem.eql(u8, name, expected);
            for ([_][]const u8{ "PeekMessageW", "PeekMessageA", "GetMessageA", "CreateWindowExA", "Sleep" }) |forbidden| {
                try std.testing.expect(!std.mem.eql(u8, name, forbidden));
            }
        }
    }
    for (found) |present| try std.testing.expect(present);
}

const raw = struct {
    extern "kernel32" fn WaitForSingleObject(windows.HANDLE, u32) callconv(.winapi) u32;
    extern "kernel32" fn GetExitCodeProcess(windows.HANDLE, *u32) callconv(.winapi) i32;
    extern "kernel32" fn TerminateProcess(windows.HANDLE, u32) callconv(.winapi) i32;
    extern "user32" fn EnumWindows(*const fn (*anyopaque, isize) callconv(.winapi) i32, isize) callconv(.winapi) i32;
    extern "user32" fn GetWindowThreadProcessId(*anyopaque, *u32) callconv(.winapi) u32;
    extern "user32" fn GetClassNameW(*anyopaque, [*]u16, i32) callconv(.winapi) i32;
    extern "user32" fn GetWindowTextW(*anyopaque, [*]u16, i32) callconv(.winapi) i32;
    extern "user32" fn GetWindowLongPtrW(*anyopaque, i32) callconv(.winapi) isize;
    extern "user32" fn GetWindowDpiAwarenessContext(*anyopaque) callconv(.winapi) ?*anyopaque;
    extern "user32" fn AreDpiAwarenessContextsEqual(?*anyopaque, ?*anyopaque) callconv(.winapi) i32;
    extern "user32" fn IsWindowVisible(*anyopaque) callconv(.winapi) i32;
    extern "user32" fn PostMessageW(*anyopaque, u32, usize, isize) callconv(.winapi) i32;
};

const Child = struct {
    process: windows.PROCESS.INFORMATION,

    fn deinit(self: *Child) void {
        if (raw.WaitForSingleObject(self.process.hProcess, 0) != 0) {
            _ = raw.TerminateProcess(self.process.hProcess, 99);
            _ = raw.WaitForSingleObject(self.process.hProcess, 5_000);
        }
        windows.CloseHandle(self.process.hThread);
        windows.CloseHandle(self.process.hProcess);
    }
    fn exitCode(self: *Child) !u32 {
        if (raw.WaitForSingleObject(self.process.hProcess, 5_000) != 0) return error.ChildTimeout;
        var code: u32 = undefined;
        if (raw.GetExitCodeProcess(self.process.hProcess, &code) == 0) return error.ChildExitUnavailable;
        return code;
    }
};

fn launch(arguments: []const []const u8) !Child {
    const path = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, contract.path, std.testing.allocator);
    defer std.testing.allocator.free(path);
    var prepared = try argv.prepare(std.testing.allocator, .{
        .application_path = path,
        .arguments = arguments,
        .current_directory = std.fs.path.dirname(path).?,
        .environment = &.{},
    });
    defer prepared.deinit(std.testing.allocator);
    var startup: windows.STARTUPINFOW = std.mem.zeroes(windows.STARTUPINFOW);
    startup.cb = @sizeOf(windows.STARTUPINFOW);
    startup.dwFlags = 1; // STARTF_USESHOWWINDOW
    startup.wShowWindow = 5; // SW_SHOW, explicitly exercising a visible HWND.
    var child: Child = undefined;
    if (!windows.kernel32.CreateProcessW(prepared.application_name.ptr, prepared.command_line.ptr, null, null, .FALSE, .{ .create_unicode_environment = true, .create_no_window = true }, prepared.environment.ptr, prepared.current_directory.ptr, &startup, &child.process).toBool()) return error.ChildCreationFailed;
    return child;
}

const Search = struct {
    pid: u32,
    window: ?*anyopaque = null,

    fn callback(hwnd: *anyopaque, context: isize) callconv(.winapi) i32 {
        const self: *Search = @ptrFromInt(@as(usize, @bitCast(context)));
        var pid: u32 = 0;
        _ = raw.GetWindowThreadProcessId(hwnd, &pid);
        if (pid == self.pid and raw.IsWindowVisible(hwnd) != 0) self.window = hwnd;
        return 1;
    }
};

test "real GUI process shows exact title class standard caption PMv2 and closes" {
    if (!supported) return error.SkipZigTest;
    for ([_][]const []const u8{ &.{"--trace-trial=00112233445566778899aabbccddeeff"}, &.{} }) |arguments| {
        var child = try launch(arguments);
        defer child.deinit();
        var search: Search = .{ .pid = child.process.dwProcessId };
        for (0..250) |_| {
            _ = raw.EnumWindows(Search.callback, @bitCast(@intFromPtr(&search)));
            if (search.window != null) break;
            if (raw.WaitForSingleObject(child.process.hProcess, 20) == 0) break;
        }
        const hwnd = search.window orelse return error.NoProductWindow;
        var text: [128]u16 = undefined;
        const title_len = raw.GetWindowTextW(hwnd, &text, text.len);
        try std.testing.expect(title_len > 0);
        try std.testing.expectEqualSlices(u16, w("TExFlow"), text[0..@intCast(title_len)]);
        const class_len = raw.GetClassNameW(hwnd, &text, text.len);
        try std.testing.expect(class_len > 0);
        try std.testing.expectEqualSlices(u16, w("texflow.main.v1"), text[0..@intCast(class_len)]);
        try std.testing.expectEqual(@as(isize, 0xcf0000), raw.GetWindowLongPtrW(hwnd, -16) & 0xcf0000);
        const pmv2: *anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -4))));
        try std.testing.expect(raw.AreDpiAwarenessContextsEqual(raw.GetWindowDpiAwarenessContext(hwnd), pmv2) != 0);
        try std.testing.expect(raw.PostMessageW(hwnd, 0x10, 0, 0) != 0); // WM_CLOSE
        try std.testing.expectEqual(@as(u32, 0), try child.exitCode());
    }
}

test "real product rejects worker probe bootstrap malformed and unknown arguments" {
    if (!supported) return error.SkipZigTest;
    for ([_][]const u8{ "--worker", "--probe", "--internal", "--bootstrap-handle=7", "--worker-bootstrap-handle=7", "--trace-trial=ABC", "--unknown", "--\u{1f642}" }) |argument| {
        var child = try launch(&.{argument});
        defer child.deinit();
        try std.testing.expectEqual(@as(u32, 2), try child.exitCode());
    }
}
