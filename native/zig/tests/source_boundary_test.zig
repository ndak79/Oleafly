const std = @import("std");
const builtin = @import("builtin");
const source_boundary = @import("source_boundary");

const testing = std.testing;

test "direct generated import is rejected outside the facade" {
    try testing.expectError(
        error.DirectZigwin32Import,
        source_boundary.scanText(
            "native/zig/src/app/main.zig",
            "const z = @import(\"zigwin32\");",
        ),
    );
}

test "everything binding is rejected outside the facade" {
    try testing.expectError(
        error.EverythingImport,
        source_boundary.scanText(
            "native/zig/src/app/main.zig",
            "const z = @import(\"win32/everything.zig\");",
        ),
    );
}

test "escaped import paths are normalized before boundary checks" {
    try testing.expectError(
        error.DirectZigwin32Import,
        source_boundary.scanText(
            "native/zig/src/app/main.zig",
            "const z = @import(\"zig\\u{77}in32\");",
        ),
    );
    try testing.expectError(
        error.EverythingImport,
        source_boundary.scanText(
            "native/zig/src/app/main.zig",
            "const z = @import(\"win32\\u{2f}everything.zig\");",
        ),
    );
}

test "facade and cache contract exceptions are explicit" {
    try source_boundary.scanText(
        "native/zig/src/platform/windows/api.zig",
        "const z = @import(\"zigwin32\");",
    );
    try source_boundary.scanText(
        "native/zig/tests/zigwin32_cache_test.zig",
        "const z = @import(\"zigwin32\");",
    );
    try source_boundary.scanText(
        "native\\zig\\src\\platform\\windows\\api.zig",
        "const z = @import(\"zigwin32\\\\graphics\\\\dxgi\");",
    );
}

test "test-only exceptions do not widen the product graph" {
    try testing.expectError(
        error.DirectZigwin32Import,
        source_boundary.scanText(
            "native/zig/src/platform/windows/other.zig",
            "const z = @import(\"zigwin32\");",
        ),
    );
    try testing.expectError(
        error.DirectZigwin32Import,
        source_boundary.scanText(
            "native/zig/tests/other.zig",
            "const z = @import(\"zigwin32\");",
        ),
    );
}

test "legal relative and standard imports remain accepted" {
    try source_boundary.scanText(
        "native/zig/src/app/main.zig",
        "const state = @import(\"../app/state.zig\"); const std = @import(\"std\");",
    );
}

test "comments and ordinary strings are ignored" {
    try source_boundary.scanText(
        "native/zig/src/app/main.zig",
        "// @import(\"zigwin32\")\r\nconst text = \"@import(\\\\\"zigwin32\\\\\")\";\r\nconst std = @import(\"std\");",
    );
}

test "character literals do not start source strings" {
    try source_boundary.scanText(
        "native/zig/src/app/main.zig",
        "const quote = '\"'; const escaped = '\\\''; const z = @import(\"std\");",
    );
}

test "valid unicode string escapes are skipped lexically" {
    try source_boundary.scanText(
        "native/zig/src/app/main.zig",
        "const marker = \"\\u{2068}\\x41\"; const z = @import(\"std\");",
    );
}

test "invalid escapes in ordinary strings and chars fail closed" {
    try testing.expectError(
        error.MalformedSource,
        source_boundary.scanText(
            "native/zig/src/app/main.zig",
            "const hidden = \"bad\\0 @import(\\\"zigwin32\\\")\";",
        ),
    );
    try testing.expectError(
        error.MalformedSource,
        source_boundary.scanText(
            "native/zig/src/app/main.zig",
            "const hidden = '\\q'; const z = @import(\"std\");",
        ),
    );
    try testing.expectError(
        error.MalformedSource,
        source_boundary.scanText(
            "native/zig/src/app/main.zig",
            "const hidden = 'a @import(\"zigwin32\")';",
        ),
    );
}

test "control bytes in comments and multiline strings fail closed" {
    try testing.expectError(
        error.MalformedSource,
        source_boundary.scanText(
            "native/zig/src/app/main.zig",
            "// hidden\x01 @import(\"zigwin32\")\nconst z = @import(\"std\");",
        ),
    );
    try testing.expectError(
        error.MalformedSource,
        source_boundary.scanText(
            "native/zig/src/app/main.zig",
            "\\\\hidden\x01 @import(\"zigwin32\")\nconst z = @import(\"std\");",
        ),
    );
}

test "multiline string lines are skipped lexically" {
    try source_boundary.scanText(
        "native/zig/src/app/main.zig",
        "const text =\n\\\\@import(\"zigwin32\")\n; const z = @import(\"std\");",
    );
}

test "tree scan ignores generated directories and preserves byte-order violations" {
    const io = testing.io;
    var temporary = testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "src");
    try temporary.dir.createDirPath(io, ".zig-cache");
    try temporary.dir.writeFile(io, .{
        .sub_path = "src/a.zig",
        .data = "const z = @import(\"zigwin32\");",
    });
    try temporary.dir.writeFile(io, .{
        .sub_path = "src/z.zig",
        .data = "const z = @import(\"win32/everything.zig\");",
    });
    try temporary.dir.writeFile(io, .{
        .sub_path = ".zig-cache/ignored.zig",
        .data = "const z = @import(\"zigwin32\");",
    });
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try temporary.dir.realPath(io, &root_buffer)];
    try testing.expectError(
        error.DirectZigwin32Import,
        source_boundary.scanTree(testing.allocator, io, root),
    );
}

test "tree scan diagnostics preserve the first violating path" {
    const io = testing.io;
    var temporary = testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "src");
    try temporary.dir.writeFile(io, .{ .sub_path = "src/a.zig", .data = "const z = @import(\"zigwin32\");" });
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try temporary.dir.realPath(io, &root_buffer)];
    var diagnostic: ?source_boundary.Diagnostic = null;
    try testing.expectError(
        error.DirectZigwin32Import,
        source_boundary.scanTreeWithDiagnostics(testing.allocator, io, root, .{}, &diagnostic),
    );
    try testing.expect(diagnostic != null);
    if (diagnostic) |item| {
        defer testing.allocator.free(item.path);
        try testing.expectEqualStrings("src/a.zig", item.path);
        try testing.expectEqual(error.DirectZigwin32Import, item.err);
    }
}

test "tree violations are selected by byte-order path" {
    const io = testing.io;
    var temporary = testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "a_dir");
    try temporary.dir.writeFile(io, .{ .sub_path = "a.zig", .data = "const z = @import(\"zigwin32\");" });
    try temporary.dir.writeFile(io, .{ .sub_path = "a_dir/ok.zig", .data = "const z = @import(\"std\");" });
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try temporary.dir.realPath(io, &root_buffer)];
    var diagnostic: ?source_boundary.Diagnostic = null;
    try testing.expectError(
        error.DirectZigwin32Import,
        source_boundary.scanTreeWithDiagnostics(
            testing.allocator,
            io,
            root,
            .{ .max_depth = 0 },
            &diagnostic,
        ),
    );
    try testing.expect(diagnostic != null);
    const item = diagnostic.?;
    defer testing.allocator.free(item.path);
    try testing.expectEqualStrings("a.zig", item.path);
    try testing.expectEqual(error.DirectZigwin32Import, item.err);
}

test "tree scan enforces file aggregate and depth limits" {
    const io = testing.io;
    var temporary = testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "nested/one/two");
    try temporary.dir.writeFile(io, .{ .sub_path = "nested/one/two/deep.zig", .data = "123456789" });
    try temporary.dir.writeFile(io, .{ .sub_path = "a.zig", .data = "12345" });
    try temporary.dir.writeFile(io, .{ .sub_path = "b.zig", .data = "12345" });
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try temporary.dir.realPath(io, &root_buffer)];

    try testing.expectError(
        error.FileTooLarge,
        source_boundary.scanTreeWithLimits(testing.allocator, io, root, .{ .max_file_bytes = 8 }),
    );
    try testing.expectError(
        error.AggregateLimit,
        source_boundary.scanTreeWithLimits(testing.allocator, io, root, .{ .max_tree_bytes = 9 }),
    );
    try testing.expectError(
        error.DepthLimit,
        source_boundary.scanTreeWithLimits(testing.allocator, io, root, .{ .max_depth = 1 }),
    );
}

test "tree scan rejects symlink entries or records unavailable evidence" {
    const io = testing.io;
    var temporary = testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(io, .{ .sub_path = "target.zig", .data = "const z = @import(\"std\");" });
    temporary.dir.symLink(io, "target.zig", "link.zig", .{}) catch |err| switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.ReadOnlyFileSystem,
        error.FileSystem,
        error.SystemResources,
        error.DiskQuota,
        error.NoSpaceLeft,
        error.Unexpected,
        => {
            std.debug.print("SymlinkEvidenceUnavailable: {s}\n", .{@errorName(err)});
            return error.SkipZigTest;
        },
        else => return err,
    };
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try temporary.dir.realPath(io, &root_buffer)];
    try testing.expectError(
        error.SymlinkEntry,
        source_boundary.scanTree(testing.allocator, io, root),
    );
}

test "directory symlinks and reparse-backed ancestors fail closed" {
    const io = testing.io;
    var temporary = testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "target/child");
    try temporary.dir.writeFile(io, .{
        .sub_path = "target/child/ok.zig",
        .data = "const z = @import(\"std\");",
    });
    temporary.dir.symLink(io, "target", "link_dir", .{ .is_directory = true }) catch |err| {
        if (isSymlinkEvidenceUnavailable(err)) {
            std.debug.print("SymlinkEvidenceUnavailable: {s}\n", .{@errorName(err)});
            return error.SkipZigTest;
        }
        return err;
    };
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try temporary.dir.realPath(io, &root_buffer)];
    try testing.expectError(
        error.SymlinkEntry,
        source_boundary.scanTree(testing.allocator, io, root),
    );

    temporary.dir.symLink(io, "target", "redirect", .{ .is_directory = true }) catch |err| {
        if (isSymlinkEvidenceUnavailable(err)) {
            std.debug.print("SymlinkEvidenceUnavailable: {s}\n", .{@errorName(err)});
            return error.SkipZigTest;
        }
        return err;
    };
    var redirected_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const redirected = try std.fmt.bufPrint(
        &redirected_buffer,
        "{s}{c}redirect{c}child",
        .{ root, std.fs.path.sep, std.fs.path.sep },
    );
    var diagnostic: ?source_boundary.Diagnostic = null;
    try testing.expectError(
        error.ReparseAncestor,
        source_boundary.scanTreeWithDiagnostics(testing.allocator, io, redirected, .{}, &diagnostic),
    );
    try testing.expect(diagnostic != null);
    const item = diagnostic.?;
    defer testing.allocator.free(item.path);
    try testing.expect(std.mem.endsWith(u8, item.path, "redirect"));
    try testing.expectEqual(error.ReparseAncestor, item.err);
}

fn isSymlinkEvidenceUnavailable(err: anyerror) bool {
    return switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.ReadOnlyFileSystem,
        error.FileSystem,
        error.SystemResources,
        error.DiskQuota,
        error.NoSpaceLeft,
        error.Unexpected,
        => true,
        else => false,
    };
}

test "non-literal comptime imports fail closed" {
    try testing.expectError(
        error.NonLiteralImport,
        source_boundary.scanText("native/zig/src/app/main.zig", "const z = @import(name);"),
    );
    try testing.expectError(
        error.NonLiteralImport,
        source_boundary.scanText("native/zig/src/app/main.zig", "const z = @import(\"zig\" ++ \"win32\");"),
    );
    try testing.expectError(
        error.NonLiteralImport,
        source_boundary.scanText("native/zig/src/app/main.zig", "const z = @import;"),
    );
    try testing.expectError(
        error.MalformedSource,
        source_boundary.scanText(
            "native/zig/src/app/main.zig",
            "const z = @import(\x0b\"std\");",
        ),
    );
}

test "Windows generated import paths are case-insensitive" {
    if (builtin.os.tag != .windows) return;
    try testing.expectError(
        error.DirectZigwin32Import,
        source_boundary.scanText(
            "native/zig/src/app/main.zig",
            "const z = @import(\"ZIGWIN32/graphics/dxgi\");",
        ),
    );
    try testing.expectError(
        error.EverythingImport,
        source_boundary.scanText(
            "native/zig/src/app/main.zig",
            "const z = @import(\"WIN32/EVERYTHING.ZIG\");",
        ),
    );
}

test "tree scan includes case variants of the Zig suffix" {
    const io = testing.io;
    var temporary = testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.writeFile(io, .{
        .sub_path = "Upper.ZIG",
        .data = "const z = @import(\"zigwin32\");",
    });
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try temporary.dir.realPath(io, &root_buffer)];
    try testing.expectError(
        error.DirectZigwin32Import,
        source_boundary.scanTree(testing.allocator, io, root),
    );
}

test "malformed and invalid input fail closed" {
    try testing.expectError(
        error.MalformedSource,
        source_boundary.scanText("native/zig/src/app/main.zig", "/* unterminated"),
    );
    try testing.expectError(
        error.MalformedSource,
        source_boundary.scanText("native/zig/src/app/main.zig", "const x = \"unterminated"),
    );
    try testing.expectError(
        error.InvalidUtf8,
        source_boundary.scanText("native/zig/src/app/main.zig", &.{0xff}),
    );
    try testing.expectError(
        error.MalformedSource,
        source_boundary.scanText("native/zig/src/app/main.zig", &.{0x01}),
    );
    try testing.expectError(
        error.MalformedSource,
        source_boundary.scanText("native/zig/src/app/main.zig", "const z = @import(\"std\\0\");"),
    );
}
