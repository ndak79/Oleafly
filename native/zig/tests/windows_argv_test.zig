const std = @import("std");
const argv = @import("windows_argv");
const corpus = @import("windows_argv_corpus.zig");
const builtin = @import("builtin");
const child_options = @import("argv_child_options");
const api = @import("windows_api");
const allocator = std.testing.allocator;
const app = "C:\\Program Files\\TExFlow\\worker.exe";

fn options(arguments: []const []const u8) argv.Options {
    return .{ .application_path = app, .arguments = arguments, .current_directory = "C:\\", .environment = &.{} };
}

fn expectWide(expected: []const u8, actual: []const u16) !void {
    const wide = try std.unicode.utf8ToUtf16LeAlloc(allocator, expected);
    defer allocator.free(wide);
    try std.testing.expectEqualSlices(u16, wide, actual);
}

fn expectRoundTrip(application: []const u8, arguments: []const []const u8, command_line: []const u16) !void {
    var parsed = try std.process.Args.Iterator.Windows.init(allocator, command_line);
    defer parsed.deinit();
    try std.testing.expectEqualStrings(application, parsed.next() orelse return error.MissingApplication);
    for (arguments) |argument| try std.testing.expectEqualStrings(argument, parsed.next() orelse return error.MissingArgument);
    try std.testing.expect(parsed.next() == null);
}

test "serializer owns a distinct writable command line with exact deterministic quoting" {
    var prepared = try argv.prepare(allocator, options(&.{ "", "two words", "a\"b", "tail\\" }));
    defer prepared.deinit(allocator);
    try expectWide(app, prepared.application_name);
    try expectWide("\"C:\\Program Files\\TExFlow\\worker.exe\" \"\" \"two words\" \"a\\\"b\" \"tail\\\\\"", prepared.command_line);
    prepared.command_line[0] = 'x';
    try expectWide(app, prepared.application_name);
    try std.testing.expectEqual(@as(u16, 0), prepared.command_line[prepared.command_line.len]);
    try expectWide("C:\\", prepared.current_directory);
    try std.testing.expectEqualSlices(u16, &.{ 0, 0 }, prepared.environment[0 .. prepared.environment.len + 1]);
}

test "independent CRT-compatible parser preserves all portable corpus arguments" {
    var prepared = try argv.prepare(allocator, options(corpus.arguments));
    defer prepared.deinit(allocator);
    try expectRoundTrip(app, corpus.arguments, prepared.command_line);
}

test "absent relative ambiguous and shell application paths are rejected" {
    var input = options(&.{});
    input.application_path = null;
    try std.testing.expectError(error.MissingApplicationPath, argv.prepare(allocator, input));
    for ([_][]const u8{ "", "worker.exe", "C:worker.exe", "\\worker.exe", ".\\worker.exe", "C:/worker.exe", "C:\\", "C:\\a\\..\\worker.exe", "C:\\a\\.\\worker.exe", "C:\\a\\\\worker.exe", "C:\\worker.exe ", "C:\\worker.exe.", "C:\\work\"er.exe", "C:\\worker.exe:stream", "\\\\?\\C:\\worker.exe", "\\\\.\\pipe\\worker.exe", "C:\\cmd.exe", "C:\\PowerShell.EXE", "C:\\pwsh.exe", "C:\\worker.cmd", "C:\\worker.bat" }) |path| {
        input.application_path = path;
        try std.testing.expectError(error.UnsafeApplicationPath, argv.prepare(allocator, input));
    }
}

test "absolute UNC application and explicit directory retain their exact spelling" {
    var input = options(&.{});
    input.application_path = "\\\\server\\share\\TExFlow\\worker.exe";
    input.current_directory = "\\\\server\\share";
    var prepared = try argv.prepare(allocator, input);
    defer prepared.deinit(allocator);
    try expectWide(input.application_path.?, prepared.application_name);
    try expectWide(input.current_directory, prepared.current_directory);
    try expectRoundTrip(input.application_path.?, &.{}, prepared.command_line);
}

test "embedded NUL and invalid UTF-8 fail before launch buffer construction" {
    try std.testing.expectError(error.EmbeddedNul, argv.prepare(allocator, options(&.{"before\x00after"})));
    try std.testing.expectError(error.InvalidUtf8, argv.prepare(allocator, options(&.{"\xff"})));
    var input = options(&.{});
    input.application_path = "C:\\wor\x00ker.exe";
    try std.testing.expectError(error.EmbeddedNul, argv.prepare(allocator, input));
    input.application_path = app;
    input.current_directory = "C:\\bad\x00cwd";
    try std.testing.expectError(error.EmbeddedNul, argv.prepare(allocator, input));
    input.current_directory = "relative";
    try std.testing.expectError(error.UnsafeCurrentDirectory, argv.prepare(allocator, input));
}

test "length limit counts encoded UTF-16 escaping and the terminating NUL" {
    // Always-quoted argv[0], one separator and the next argument's quotes.
    const available = argv.max_command_line_units - app.len - 5;
    const boundary = try allocator.alloc(u8, available + 1);
    defer allocator.free(boundary);
    @memset(boundary, 'x');
    var exact = try argv.prepare(allocator, options(&.{boundary[0..available]}));
    defer exact.deinit(allocator);
    try std.testing.expectEqual(argv.max_command_line_units, exact.command_line.len);
    try std.testing.expectError(error.CommandLineTooLong, argv.prepare(allocator, options(&.{boundary})));
    @memset(boundary, '\\');
    try std.testing.expectError(error.CommandLineTooLong, argv.prepare(allocator, options(&.{boundary[0 .. available / 2 + 1]})));
    const unicode = "\u{1f642}" ** 12000;
    var supplementary = try argv.prepare(allocator, options(&.{unicode}));
    defer supplementary.deinit(allocator);
    try expectRoundTrip(app, &.{unicode}, supplementary.command_line);
}

test "environment is explicit sorted double-NUL and rejects ambiguous names" {
    var input = options(&.{});
    input.environment = &.{ .{ .name = "z", .value = "last" }, .{ .name = "Alpha", .value = "a=b \u{e9}" } };
    var prepared = try argv.prepare(allocator, input);
    defer prepared.deinit(allocator);
    try expectWide("Alpha=a=b \u{e9}\x00z=last\x00", prepared.environment);
    try std.testing.expectEqual(@as(u16, 0), prepared.environment[prepared.environment.len]);
    input.environment = &.{ .{ .name = "Path", .value = "a" }, .{ .name = "PATH", .value = "b" } };
    try std.testing.expectError(error.DuplicateEnvironmentName, argv.prepare(allocator, input));
    for ([_][]const u8{ "", "A=B", "=C:", "bad\x00name", "nonascii\u{e9}" }) |name| {
        input.environment = &.{.{ .name = name, .value = "x" }};
        try std.testing.expectError(error.InvalidEnvironmentName, argv.prepare(allocator, input));
    }
    input.environment = &.{.{ .name = "OK", .value = "bad\x00value" }};
    try std.testing.expectError(error.EmbeddedNul, argv.prepare(allocator, input));
}

test "environment uppercase ordinal ordering places Z before underscore" {
    var input = options(&.{});
    input.environment = &.{ .{ .name = "_", .value = "underscore" }, .{ .name = "Z", .value = "letter" } };
    var prepared = try argv.prepare(allocator, input);
    defer prepared.deinit(allocator);
    try expectWide("Z=letter\x00_=underscore\x00", prepared.environment);
}

test "environment ordinal ordering preserves punctuation boundaries and prefixes" {
    var input = options(&.{});
    input.environment = &.{
        .{ .name = "{", .value = "" },
        .{ .name = "`", .value = "" },
        .{ .name = "_", .value = "" },
        .{ .name = "[", .value = "" },
        .{ .name = "z", .value = "" },
        .{ .name = "a_", .value = "" },
        .{ .name = "aZ", .value = "" },
        .{ .name = "Aa", .value = "" },
        .{ .name = "a", .value = "" },
        .{ .name = "@", .value = "" },
        .{ .name = "9", .value = "" },
    };
    var prepared = try argv.prepare(allocator, input);
    defer prepared.deinit(allocator);
    try expectWide("9=\x00@=\x00a=\x00Aa=\x00aZ=\x00a_=\x00z=\x00[=\x00_=\x00`=\x00{=\x00", prepared.environment);
}

test "environment rejects case-only duplicates among punctuation-bearing names" {
    var input = options(&.{});
    input.environment = &.{ .{ .name = "z", .value = "first" }, .{ .name = "_", .value = "punctuation" }, .{ .name = "Z", .value = "second" } };
    try std.testing.expectError(error.DuplicateEnvironmentName, argv.prepare(allocator, input));
    input.environment = &.{ .{ .name = "[a]", .value = "first" }, .{ .name = "Z", .value = "letter" }, .{ .name = "[A]", .value = "second" } };
    try std.testing.expectError(error.DuplicateEnvironmentName, argv.prepare(allocator, input));
}

test "application quoting itself cannot exceed the command-line limit" {
    const path = try allocator.alloc(u8, argv.max_command_line_units);
    defer allocator.free(path);
    @memset(path, 'x');
    @memcpy(path[0..3], "C:\\");
    @memcpy(path[path.len - 4 ..], ".exe");
    var input = options(&.{});
    input.application_path = path;
    try std.testing.expectError(error.CommandLineTooLong, argv.prepare(allocator, input));
}

test "Win32 reserved device components cannot identify an executable or directory" {
    var input = options(&.{});
    for ([_][]const u8{ "C:\\NUL.exe", "C:\\CON.exe", "C:\\COM1.exe", "C:\\Lpt9.exe", "C:\\AUX\\worker.exe", "C:\\COM\u{b9}.exe" }) |path| {
        input.application_path = path;
        try std.testing.expectError(error.UnsafeApplicationPath, argv.prepare(allocator, input));
    }
    input.application_path = app;
    input.current_directory = "C:\\PRN";
    try std.testing.expectError(error.UnsafeCurrentDirectory, argv.prepare(allocator, input));
}

test "exhaustive short quote slash and whitespace sequences round trip independently" {
    const alphabet = [_]u8{ 'a', ' ', '\\', '"', '\t' };
    var buffer: [5]u8 = undefined;
    var combinations: usize = 1;
    for (0..buffer.len + 1) |length| {
        for (0..combinations) |encoded| {
            var remainder = encoded;
            for (buffer[0..length]) |*byte| {
                byte.* = alphabet[remainder % alphabet.len];
                remainder /= alphabet.len;
            }
            const arguments: []const []const u8 = &.{buffer[0..length]};
            var prepared = try argv.prepare(allocator, options(arguments));
            defer prepared.deinit(allocator);
            try expectRoundTrip(app, arguments, prepared.command_line);
        }
        combinations *= alphabet.len;
    }
}

fn prepareWithAllocationFailures(gpa: std.mem.Allocator) !void {
    var input = options(corpus.arguments);
    input.environment = &.{ .{ .name = "ONE", .value = "value" }, .{ .name = "TWO", .value = "\u{1f642}" } };
    var prepared = try argv.prepare(gpa, input);
    defer prepared.deinit(gpa);
}

test "allocation failures release every partially prepared launch buffer" {
    try std.testing.checkAllAllocationFailures(allocator, prepareWithAllocationFailures, .{});
}

test "typed platform allowlist declares required narrow namespaces only" {
    try std.testing.expectEqual(@as(usize, 16), api.namespace_allowlist.len);
    for (api.namespace_allowlist, 0..) |namespace, index| {
        const path = api.sourcePath(namespace);
        try std.testing.expect(std.mem.startsWith(u8, path, "win32/"));
        try std.testing.expect(std.mem.endsWith(u8, path, ".zig"));
        try std.testing.expect(std.mem.indexOf(u8, path, "everything") == null);
        for (api.namespace_allowlist[0..index]) |previous| try std.testing.expect(previous != namespace);
    }
    try std.testing.expectEqualStrings("win32/graphics/direct3d11.zig", api.sourcePath(.direct3d11));
    try std.testing.expectEqualStrings("win32/graphics/dxgi.zig", api.sourcePath(.dxgi));
    try std.testing.expectEqualStrings("win32/graphics/imaging.zig", api.sourcePath(.imaging));
    try std.testing.expectEqualStrings("win32/ui/accessibility.zig", api.sourcePath(.accessibility));
}

test "raw CreateProcessW child checks actual Windows parsers environment and directory" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const child_path = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, child_options.path, allocator);
    defer allocator.free(child_path);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = cwd_buffer[0..try temporary.dir.realPath(std.testing.io, &cwd_buffer)];
    var input = options(corpus.arguments);
    input.application_path = child_path;
    input.current_directory = cwd;
    input.environment = &.{ .{ .name = "TEXFLOW_ARGV_MARKER", .value = "explicit-only" }, .{ .name = "TEXFLOW_ARGV_CWD", .value = cwd } };
    var prepared = try argv.prepare(allocator, input);
    defer prepared.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 0), try runRawChild(&prepared));
    // Falsification: the child must catch altered content, not merely launch.
    prepared.command_line[prepared.command_line.len - 2] = 'y';
    try std.testing.expect((try runRawChild(&prepared)) != 0);
}

fn runRawChild(prepared: *argv.Prepared) !u32 {
    const windows = std.os.windows;
    const raw = struct {
        extern "kernel32" fn WaitForSingleObject(windows.HANDLE, u32) callconv(.winapi) u32;
        extern "kernel32" fn GetExitCodeProcess(windows.HANDLE, *u32) callconv(.winapi) windows.BOOL;
        extern "kernel32" fn TerminateProcess(windows.HANDLE, u32) callconv(.winapi) windows.BOOL;
    };
    var startup: windows.STARTUPINFOW = std.mem.zeroes(windows.STARTUPINFOW);
    startup.cb = @sizeOf(windows.STARTUPINFOW);
    var process: windows.PROCESS.INFORMATION = undefined;
    const created = windows.kernel32.CreateProcessW(
        prepared.application_name.ptr,
        prepared.command_line.ptr,
        null,
        null,
        .FALSE,
        .{ .create_unicode_environment = true, .create_no_window = true },
        prepared.environment.ptr,
        prepared.current_directory.ptr,
        &startup,
        &process,
    );
    if (!created.toBool()) return error.ChildCreationFailed;
    defer windows.CloseHandle(process.hThread);
    defer windows.CloseHandle(process.hProcess);
    if (raw.WaitForSingleObject(process.hProcess, 10_000) != 0) {
        if (!raw.TerminateProcess(process.hProcess, 1).toBool()) return error.ChildTerminationFailed;
        _ = raw.WaitForSingleObject(process.hProcess, 10_000);
        return error.ChildTimeout;
    }
    var exit_code: u32 = undefined;
    if (!raw.GetExitCodeProcess(process.hProcess, &exit_code).toBool()) return error.ChildExitUnavailable;
    return exit_code;
}
