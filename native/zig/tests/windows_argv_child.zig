const std = @import("std");
const corpus = @import("windows_argv_corpus.zig");

const raw = struct {
    extern "kernel32" fn GetCommandLineW() callconv(.winapi) [*:0]const u16;
    extern "kernel32" fn GetCurrentDirectoryW(u32, [*]u16) callconv(.winapi) u32;
    extern "kernel32" fn GetEnvironmentVariableW([*:0]const u16, [*]u16, u32) callconv(.winapi) u32;
    extern "kernel32" fn LocalFree(?*anyopaque) callconv(.winapi) ?*anyopaque;
    extern "shell32" fn CommandLineToArgvW([*:0]const u16, *c_int) callconv(.winapi) ?[*][*:0]u16;
};

pub fn main(init: std.process.Init.Minimal) u8 {
    check(init) catch return 1;
    return 0;
}

fn check(init: std.process.Init.Minimal) !void {
    // No serializer import: the two parsers consume the OS-provided command line.
    var iterator = try init.args.iterateAllocator(std.heap.page_allocator);
    defer iterator.deinit();
    const application = iterator.next() orelse return error.MissingApplication;
    var count: c_int = 0;
    const native = raw.CommandLineToArgvW(raw.GetCommandLineW(), &count) orelse return error.NativeParserFailed;
    defer _ = raw.LocalFree(@ptrCast(native));
    if (count != corpus.arguments.len + 1) return error.ArgumentCountMismatch;
    try equalWide(application, std.mem.span(native[0]));
    for (corpus.arguments, 1..) |expected, index| {
        if (!std.mem.eql(u8, expected, iterator.next() orelse return error.MissingArgument)) return error.ZigArgumentMismatch;
        try equalWide(expected, std.mem.span(native[index]));
    }
    if (iterator.next() != null) return error.ExtraArgument;
    var marker: [64]u16 = undefined;
    const marker_len = raw.GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("TEXFLOW_ARGV_MARKER"), &marker, marker.len);
    if (marker_len == 0 or marker_len >= marker.len) return error.MissingExplicitEnvironment;
    try equalWide("explicit-only", marker[0..marker_len]);
    if (raw.GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("PATH"), &marker, marker.len) != 0) return error.InheritedPath;
    var expected_cwd: [32768]u16 = undefined;
    const expected_len = raw.GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("TEXFLOW_ARGV_CWD"), &expected_cwd, expected_cwd.len);
    var actual_cwd: [32768]u16 = undefined;
    const actual_len = raw.GetCurrentDirectoryW(actual_cwd.len, &actual_cwd);
    if (expected_len == 0 or expected_len >= expected_cwd.len or actual_len == 0 or actual_len >= actual_cwd.len) return error.InvalidDirectory;
    if (!std.mem.eql(u16, expected_cwd[0..expected_len], actual_cwd[0..actual_len])) return error.DirectoryMismatch;
}

fn equalWide(expected: []const u8, actual: []const u16) !void {
    const utf8 = try std.unicode.utf16LeToUtf8Alloc(std.heap.page_allocator, actual);
    defer std.heap.page_allocator.free(utf8);
    if (!std.mem.eql(u8, expected, utf8)) return error.NativeArgumentMismatch;
}
