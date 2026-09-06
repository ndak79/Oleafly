const std = @import("std");
const builtin = @import("builtin");
const atomic_save = @import("atomic_save");

fn sha256(bytes: []const u8) [32]u8 {
    var result: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &result, .{});
    return result;
}

fn absoluteChild(
    allocator: std.mem.Allocator,
    io: std.Io,
    temp: *std.testing.TmpDir,
    name: []const u8,
) ![:0]u8 {
    return temp.dir.realPathFileAlloc(io, name, allocator);
}

fn expectNoSaveTemps(temp: *std.testing.TmpDir, io: std.Io) !void {
    var iterator = temp.dir.iterate();
    while (try iterator.next(io)) |entry| {
        try std.testing.expect(!std.mem.startsWith(u8, entry.name, atomic_save.temp_file_prefix));
    }
}

test "save replaces an existing file and returns a verified receipt" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.writeFile(io, .{ .sub_path = "main.tex", .data = "old bytes" });
    const target = try absoluteChild(allocator, io, &temp, "main.tex");
    defer allocator.free(target);

    var result = try atomic_save.save(allocator, io, target, sha256("old bytes"), "new bytes", 7);
    defer result.deinit();

    try std.testing.expectEqual(atomic_save.SaveStatus.replaced, result.status);
    try std.testing.expectEqual(sha256("new bytes"), result.target_hash);
    try std.testing.expectEqual(@as(u64, 7), result.revision);
    try std.testing.expect(result.recovery_path == null);
    const written = try temp.dir.readFileAlloc(io, "main.tex", allocator, .limited(128));
    defer allocator.free(written);
    try std.testing.expectEqualStrings("new bytes", written);
    try expectNoSaveTemps(&temp, io);
}

test "save rejects an external change before creating a temp file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.writeFile(io, .{ .sub_path = "main.tex", .data = "disk bytes" });
    const target = try absoluteChild(allocator, io, &temp, "main.tex");
    defer allocator.free(target);

    try std.testing.expectError(
        error.ExternalChange,
        atomic_save.save(allocator, io, target, sha256("saved base"), "editor bytes", 8),
    );
    const unchanged = try temp.dir.readFileAlloc(io, "main.tex", allocator, .limited(128));
    defer allocator.free(unchanged);
    try std.testing.expectEqualStrings("disk bytes", unchanged);
    try expectNoSaveTemps(&temp, io);
}

test "save rejects relative paths, dot segments, and missing targets" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try std.testing.expectError(
        error.RelativePath,
        atomic_save.save(allocator, io, "main.tex", sha256("old bytes"), "new bytes", 1),
    );

    const root = try temp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);
    const dotted = try std.fmt.allocPrint(allocator, "{s}{c}.{c}main.tex", .{ root, std.fs.path.sep, std.fs.path.sep });
    defer allocator.free(dotted);
    try std.testing.expectError(
        error.InvalidTargetPath,
        atomic_save.save(allocator, io, dotted, sha256("old bytes"), "new bytes", 2),
    );
    const root_name = std.fs.path.basename(root);
    const parented = try std.fmt.allocPrint(
        allocator,
        "{s}{c}..{c}{s}{c}main.tex",
        .{ root, std.fs.path.sep, std.fs.path.sep, root_name, std.fs.path.sep },
    );
    defer allocator.free(parented);
    try std.testing.expectError(
        error.InvalidTargetPath,
        atomic_save.save(allocator, io, parented, sha256("old bytes"), "new bytes", 3),
    );
    const missing = try std.Io.Dir.path.join(allocator, &.{ root, "missing.tex" });
    defer allocator.free(missing);
    try std.testing.expectError(
        error.TargetMissing,
        atomic_save.save(allocator, io, missing, sha256("old bytes"), "new bytes", 4),
    );
    try expectNoSaveTemps(&temp, io);
}

test "save refuses an intermediate symlink parent without creating temps" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.createDirPath(io, "real/child");
    try temp.dir.writeFile(io, .{ .sub_path = "real/child/main.tex", .data = "old bytes" });
    temp.dir.symLink(io, "real", "redirect", .{ .is_directory = true }) catch |err| switch (err) {
        error.AccessDenied, error.PermissionDenied, error.FileSystem => return error.SkipZigTest,
        else => return err,
    };

    const root = try temp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);
    const target = try std.Io.Dir.path.join(allocator, &.{ root, "redirect", "child", "main.tex" });
    defer allocator.free(target);
    try std.testing.expectError(
        error.ReparsePoint,
        atomic_save.save(allocator, io, target, sha256("old bytes"), "new bytes", 5),
    );
    try expectNoSaveTemps(&temp, io);
}

test "save rejects Windows ADS and device-name path components" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();
    try temp.dir.writeFile(io, .{ .sub_path = "main.tex", .data = "old bytes" });

    const root = try temp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);
    const ads = try std.fmt.allocPrint(allocator, "{s}\\main.tex:stream", .{root});
    defer allocator.free(ads);
    const device = try std.fmt.allocPrint(allocator, "{s}\\NUL.txt", .{root});
    defer allocator.free(device);
    const trailing = try std.fmt.allocPrint(allocator, "{s}\\safe. ", .{root});
    defer allocator.free(trailing);

    const paths = [_][]const u8{ ads, device, trailing };
    for (paths) |path| {
        try std.testing.expectError(
            error.InvalidTargetPath,
            atomic_save.save(allocator, io, path, sha256("old bytes"), "new bytes", 12),
        );
    }
    try expectNoSaveTemps(&temp, io);
}

test "save refuses a concurrently locked target before creating temps" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();
    try temp.dir.writeFile(io, .{ .sub_path = "main.tex", .data = "old bytes" });
    const target = try absoluteChild(allocator, io, &temp, "main.tex");
    defer allocator.free(target);

    var held = temp.dir.openFile(io, "main.tex", .{
        .mode = .read_only,
        .allow_directory = false,
        .follow_symlinks = false,
        .lock = .exclusive,
        .lock_nonblocking = true,
    }) catch |err| switch (err) {
        error.FileLocksUnsupported, error.PermissionDenied, error.AccessDenied => return error.SkipZigTest,
        else => return err,
    };
    defer held.close(io);
    try std.testing.expectError(
        error.ExternalChange,
        atomic_save.save(allocator, io, target, sha256("old bytes"), "new bytes", 13),
    );
    try expectNoSaveTemps(&temp, io);
}

test "save refuses a symlink target without following it" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.writeFile(io, .{ .sub_path = "real.tex", .data = "real bytes" });
    temp.dir.symLink(io, "real.tex", "alias.tex", .{}) catch |err| switch (err) {
        error.AccessDenied, error.PermissionDenied, error.FileSystem => return error.SkipZigTest,
        else => return err,
    };
    const root = try temp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);
    const target = try std.Io.Dir.path.join(allocator, &.{ root, "alias.tex" });
    defer allocator.free(target);

    try std.testing.expectError(
        error.ReparsePoint,
        atomic_save.save(allocator, io, target, sha256("real bytes"), "new bytes", 3),
    );
    try expectNoSaveTemps(&temp, io);
}

fn failRename(
    _: std.Io,
    _: std.Io.Dir,
    _: []const u8,
    _: []const u8,
) anyerror!void {
    return error.InjectedRenameFailure;
}

fn renameThenFail(
    io: std.Io,
    dir: std.Io.Dir,
    staged_name: []const u8,
    target_name: []const u8,
) !void {
    try std.Io.Dir.rename(dir, staged_name, dir, target_name, io);
    return error.InjectedRenameFailure;
}

fn renameThenTamper(
    io: std.Io,
    dir: std.Io.Dir,
    staged_name: []const u8,
    target_name: []const u8,
) !void {
    try std.Io.Dir.rename(dir, staged_name, dir, target_name, io);
    try dir.writeFile(io, .{ .sub_path = target_name, .data = "tampered bytes" });
}

test "replacement failure retains the staged bytes as a recovery copy" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.writeFile(io, .{ .sub_path = "main.tex", .data = "old bytes" });
    const target = try absoluteChild(allocator, io, &temp, "main.tex");
    defer allocator.free(target);

    var result = try atomic_save.saveWithHooks(
        allocator,
        io,
        target,
        sha256("old bytes"),
        "new bytes",
        9,
        .{ .rename = failRename },
    );
    defer result.deinit();

    try std.testing.expectEqual(atomic_save.SaveStatus.recovery_retained, result.status);
    try std.testing.expect(result.recovery_path != null);
    const recovery = try std.Io.Dir.cwd().readFileAlloc(io, result.recovery_path.?, allocator, .limited(128));
    defer allocator.free(recovery);
    try std.testing.expectEqualStrings("new bytes", recovery);
    const unchanged = try temp.dir.readFileAlloc(io, "main.tex", allocator, .limited(128));
    defer allocator.free(unchanged);
    try std.testing.expectEqualStrings("old bytes", unchanged);
}

test "rename error after consuming staged name still retains recovery bytes" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.writeFile(io, .{ .sub_path = "main.tex", .data = "old bytes" });
    const target = try absoluteChild(allocator, io, &temp, "main.tex");
    defer allocator.free(target);

    var result = try atomic_save.saveWithHooks(
        allocator,
        io,
        target,
        sha256("old bytes"),
        "new bytes",
        11,
        .{ .rename = renameThenFail },
    );
    defer result.deinit();

    try std.testing.expectEqual(atomic_save.SaveStatus.recovery_retained, result.status);
    const recovery = try std.Io.Dir.cwd().readFileAlloc(io, result.recovery_path.?, allocator, .limited(128));
    defer allocator.free(recovery);
    try std.testing.expectEqualStrings("new bytes", recovery);
    const replaced = try temp.dir.readFileAlloc(io, "main.tex", allocator, .limited(128));
    defer allocator.free(replaced);
    try std.testing.expectEqualStrings("new bytes", replaced);
}

test "post-replacement verification failure retains a recovery copy" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.writeFile(io, .{ .sub_path = "main.tex", .data = "old bytes" });
    const target = try absoluteChild(allocator, io, &temp, "main.tex");
    defer allocator.free(target);

    var result = try atomic_save.saveWithHooks(
        allocator,
        io,
        target,
        sha256("old bytes"),
        "new bytes",
        10,
        .{ .rename = renameThenTamper },
    );
    defer result.deinit();

    try std.testing.expectEqual(atomic_save.SaveStatus.recovery_retained, result.status);
    try std.testing.expect(result.recovery_path != null);
    const recovery = try std.Io.Dir.cwd().readFileAlloc(io, result.recovery_path.?, allocator, .limited(128));
    defer allocator.free(recovery);
    try std.testing.expectEqualStrings("new bytes", recovery);
    const tampered = try temp.dir.readFileAlloc(io, "main.tex", allocator, .limited(128));
    defer allocator.free(tampered);
    try std.testing.expectEqualStrings("tampered bytes", tampered);
}
