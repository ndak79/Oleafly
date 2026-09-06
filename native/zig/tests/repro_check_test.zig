const std = @import("std");
const builtin = @import("builtin");
const repro = @import("repro_check");

test "repro preflight rejects incomplete or unsafe admission" {
    try repro.validateTarget("x86_64-windows-msvc");
    try std.testing.expectError(error.TargetNotAdmitted, repro.validateTarget("aarch64-windows-msvc"));
    try std.testing.expectError(error.ReproRootMustBeAbsolute, repro.validateReproRoot("relative-root"));
    try std.testing.expectError(error.ReproRootUnsafe, repro.validateReproRoot("C:\\temp root"));
    try std.testing.expectError(error.ReproRootUnsafe, repro.validateReproRoot("C:\\temp\\..\\other"));

    try repro.validatePreflight(.{
        .phase = .resolve,
        .allow_network = true,
        .runner_authorized = true,
        .root_disposable = true,
        .free_space_bytes = 100 * 1024 * 1024 * 1024,
        .physical_memory_bytes = 16 * 1024 * 1024 * 1024,
        .network_none_verified = true,
    });
    var bad = repro.Preflight{
        .phase = .reproduce,
        .allow_network = false,
        .runner_authorized = true,
        .root_disposable = true,
        .free_space_bytes = 100 * 1024 * 1024 * 1024,
        .physical_memory_bytes = 16 * 1024 * 1024 * 1024,
        .network_none_verified = true,
    };
    try std.testing.expectError(error.NetworkAuthorizationRequired, repro.validatePreflight(bad));
    bad.allow_network = true;
    bad.free_space_bytes = 99 * 1024 * 1024 * 1024;
    try std.testing.expectError(error.InsufficientReproDisk, repro.validatePreflight(bad));
    bad.free_space_bytes = 100 * 1024 * 1024 * 1024;
    bad.network_none_verified = false;
    try std.testing.expectError(error.NetworkIsolationUnverified, repro.validatePreflight(bad));

    bad.network_none_verified = true;
    bad.runner_authorized = false;
    try std.testing.expectError(error.RunnerNotAuthorized, repro.validatePreflight(bad));
    bad.runner_authorized = true;
    bad.root_disposable = false;
    try std.testing.expectError(error.DisposableRootRequired, repro.validatePreflight(bad));
    bad.root_disposable = true;
    bad.physical_memory_bytes = 15 * 1024 * 1024 * 1024;
    try std.testing.expectError(error.InsufficientReproMemory, repro.validatePreflight(bad));
}

test "network receipt is explicit and cannot be proxy-poisoned" {
    try repro.verifyNetworkReceipt(
        "network_mode=none\nfetch_bytes=0\nroute_count=0\nproxy=unset\nprocess_policy=zig-owned\n",
    );
    try std.testing.expectError(
        error.NetworkIsolationUnverified,
        repro.verifyNetworkReceipt("network_mode=loopback\nfetch_bytes=0\nroute_count=0\nproxy=poisoned\nprocess_policy=zig-owned\n"),
    );
    try std.testing.expectError(
        error.NetworkReceiptMismatch,
        repro.verifyNetworkReceipt("network_mode=none\nfetch_bytes=1\nroute_count=0\nproxy=unset\nprocess_policy=zig-owned\n"),
    );
    try std.testing.expectError(
        error.NetworkIsolationUnverified,
        repro.verifyNetworkReceipt("network_mode=unknown\nfetch_bytes=0\nroute_count=0\nproxy=unset\nprocess_policy=zig-owned\n"),
    );
    try std.testing.expectError(
        error.NetworkReceiptMismatch,
        repro.verifyNetworkReceipt("network_mode=none\nfetch_bytes=0\nroute_count=0\nproxy=unset\nprocess_policy=zig-owned\nextra=field\n"),
    );
}

test "required role inventory is exact for the Windows product payload" {
    const roles = [_][]const u8{
        "bin/TExFlow.exe",
        "bin/TExFlow.PdfWorker.exe",
        "bin/TExFlow.ScienceWorker.exe",
    };
    try repro.verifyRequiredRoles("x86_64-windows-msvc", &roles);
    try std.testing.expectError(error.MissingRequiredRole, repro.verifyRequiredRoles(
        "x86_64-windows-msvc",
        roles[0..2],
    ));
    const duplicate = [_][]const u8{
        "bin/TExFlow.exe",
        "bin/TExFlow.exe",
        "bin/TExFlow.PdfWorker.exe",
        "bin/TExFlow.ScienceWorker.exe",
    };
    try std.testing.expectError(error.UnexpectedRequiredRole, repro.verifyRequiredRoles(
        "x86_64-windows-msvc",
        &duplicate,
    ));
    try repro.verifyRequiredRoles("x86_64-linux-gnu", &.{});
    try std.testing.expectError(error.UnexpectedLinuxProduct, repro.verifyRequiredRoles(
        "x86_64-linux-gnu",
        &.{"bin/TExFlow"},
    ));
}

test "two payload roots compare by complete canonical directory digest" {
    const allocator = std.testing.allocator;
    var left_tmp = std.testing.tmpDir(.{});
    defer left_tmp.cleanup();
    var right_tmp = std.testing.tmpDir(.{});
    defer right_tmp.cleanup();
    try left_tmp.dir.createDir(std.testing.io, "bin", .default_dir);
    try right_tmp.dir.createDir(std.testing.io, "bin", .default_dir);
    try left_tmp.dir.writeFile(std.testing.io, .{ .sub_path = "bin/TExFlow.exe", .data = "same" });
    try right_tmp.dir.writeFile(std.testing.io, .{ .sub_path = "bin/TExFlow.exe", .data = "same" });
    var left_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    var right_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const left_path = left_path_buf[0..try left_tmp.dir.realPath(std.testing.io, &left_path_buf)];
    const right_path = right_path_buf[0..try right_tmp.dir.realPath(std.testing.io, &right_path_buf)];
    const equal = try repro.comparePayloadRoots(allocator, std.testing.io, left_path, right_path);
    try std.testing.expectEqual(equal.left.files, equal.right.files);
    try std.testing.expectEqual(equal.left.bytes, equal.right.bytes);
    try std.testing.expectEqual(equal.left.digest, equal.right.digest);
    try right_tmp.dir.writeFile(std.testing.io, .{ .sub_path = "changed.txt", .data = "changed" });
    try std.testing.expectError(error.PayloadManifestMismatch, repro.comparePayloadRoots(allocator, std.testing.io, left_path, right_path));
}

test "payload root comparison rejects absolute roots with dot segments" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "payload");

    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try temporary.dir.realPath(io, &root_buffer)];
    var dotted_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const dotted = try std.fmt.bufPrint(
        &dotted_buffer,
        "{s}{c}.{c}payload",
        .{ root, std.fs.path.sep, std.fs.path.sep },
    );
    try std.testing.expectError(
        error.ReproRootUnsafe,
        repro.comparePayloadRoots(allocator, io, dotted, root),
    );

    var parented_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const parented = try std.fmt.bufPrint(
        &parented_buffer,
        "{s}{c}..{c}{s}{c}payload",
        .{ root, std.fs.path.sep, std.fs.path.sep, std.fs.path.basename(root), std.fs.path.sep },
    );
    try std.testing.expectError(
        error.ReproRootUnsafe,
        repro.comparePayloadRoots(allocator, io, parented, root),
    );
}

test "payload root comparison rejects Windows rooted namespaces" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "payload");
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try temporary.dir.realPath(io, &root_buffer)];
    const parsed = std.fs.path.parsePathWindows(u8, root);
    if (parsed.kind != .drive_absolute) return error.SkipZigTest;

    // A rooted path has no explicit drive. It may resolve against ambient
    // drive state, so the payload boundary must refuse it before opening.
    var rooted_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const rooted = try std.fmt.bufPrint(&rooted_buffer, "{s}", .{root[2..]});
    try std.testing.expectError(
        error.ReproRootUnsafe,
        repro.comparePayloadRoots(allocator, io, rooted, root),
    );
}

test "payload root comparison rejects an intermediate symlink" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var left_tmp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer left_tmp.cleanup();
    var right_tmp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer right_tmp.cleanup();
    try left_tmp.dir.createDirPath(io, "target/child");
    try left_tmp.dir.writeFile(io, .{ .sub_path = "target/child/file.txt", .data = "same" });
    try right_tmp.dir.writeFile(io, .{ .sub_path = "file.txt", .data = "same" });
    left_tmp.dir.symLink(io, "target", "redirect", .{ .is_directory = true }) catch |err| {
        if (isSymlinkEvidenceUnavailable(err)) {
            std.debug.print("SymlinkEvidenceUnavailable: {s}\n", .{@errorName(err)});
            return error.SkipZigTest;
        }
        return err;
    };

    var left_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var right_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const left_path = left_path_buffer[0..try left_tmp.dir.realPath(io, &left_path_buffer)];
    const right_path = right_path_buffer[0..try right_tmp.dir.realPath(io, &right_path_buffer)];
    var redirected_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const redirected = try std.fmt.bufPrint(
        &redirected_buffer,
        "{s}{c}redirect{c}child",
        .{ left_path, std.fs.path.sep, std.fs.path.sep },
    );
    try std.testing.expectError(
        error.ReparsePoint,
        repro.comparePayloadRoots(allocator, io, redirected, right_path),
    );
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
