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
    try std.testing.expectError(
        error.NetworkReceiptMismatch,
        repro.verifyNetworkReceipt("network_mode=none\nfetch_bytes=0\nroute_count=0\nproxy=unset\nprocess_policy=zig-owned\nnetwork_mode=none\n"),
    );
    try std.testing.expectError(
        error.NetworkReceiptMismatch,
        repro.verifyNetworkReceipt("network_mode=none\nroute_count=0\nfetch_bytes=0\nproxy=unset\nprocess_policy=zig-owned\n"),
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

test "compare entry point requires and validates an authenticated role manifest" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const target = "x86_64-windows-msvc";
    const valid_entries = [_]repro.RoleManifestEntry{
        .{ .name = "UI", .path = "bin/TExFlow.exe" },
        .{ .name = "PdfWorker", .path = "bin/TExFlow.PdfWorker.exe" },
        .{ .name = "ScienceWorker", .path = "bin/TExFlow.ScienceWorker.exe" },
    };

    var left = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer left.cleanup();
    var right = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer right.cleanup();
    var inputs = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer inputs.cleanup();
    try left.dir.createDir(io, "bin", .default_dir);
    try right.dir.createDir(io, "bin", .default_dir);
    for (valid_entries) |entry| {
        try left.dir.writeFile(io, .{ .sub_path = entry.path, .data = "fixture" });
        try right.dir.writeFile(io, .{ .sub_path = entry.path, .data = "fixture" });
    }
    try inputs.dir.writeFile(io, .{
        .sub_path = "network.receipt",
        .data = "network_mode=none\nfetch_bytes=0\nroute_count=0\nproxy=unset\nprocess_policy=zig-owned\n",
    });

    var left_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var right_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var inputs_root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var receipt_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var manifest_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const left_path = left_path_buffer[0..try left.dir.realPath(io, &left_path_buffer)];
    const right_path = right_path_buffer[0..try right.dir.realPath(io, &right_path_buffer)];
    const inputs_path = inputs_root_buffer[0..try inputs.dir.realPath(io, &inputs_root_buffer)];
    const receipt_path = try std.fmt.bufPrint(
        &receipt_path_buffer,
        "{s}{c}network.receipt",
        .{ inputs_path, std.fs.path.sep },
    );

    var args = [_][]const u8{
        "repro-check",
        "compare",
        target,
        left_path,
        right_path,
        receipt_path,
        undefined,
    };
    const valid_manifest = try writeRoleManifest(&inputs, target, &valid_entries, true, &manifest_path_buffer);
    args[6] = valid_manifest;
    const comparison = try repro.run(allocator, io, &args);
    try std.testing.expectEqual(comparison.left.files, comparison.right.files);
    try std.testing.expectEqual(comparison.left.bytes, comparison.right.bytes);
    try std.testing.expectEqual(comparison.left.digest, comparison.right.digest);

    args[6] = try writeRoleManifest(&inputs, target, &valid_entries, false, &manifest_path_buffer);
    try std.testing.expectError(error.UnauthenticatedRoleManifest, repro.run(allocator, io, &args));

    const missing = valid_entries[0..2];
    args[6] = try writeRoleManifest(&inputs, target, missing, true, &manifest_path_buffer);
    try std.testing.expectError(error.MissingRequiredRole, repro.run(allocator, io, &args));

    const duplicate = [_]repro.RoleManifestEntry{
        valid_entries[0],
        valid_entries[0],
        valid_entries[2],
    };
    args[6] = try writeRoleManifest(&inputs, target, &duplicate, true, &manifest_path_buffer);
    try std.testing.expectError(error.UnexpectedRequiredRole, repro.run(allocator, io, &args));

    var wrong = valid_entries;
    wrong[0] = .{ .name = "Installer", .path = "bin/TExFlow.exe" };
    args[6] = try writeRoleManifest(&inputs, target, &wrong, true, &manifest_path_buffer);
    try std.testing.expectError(error.UnexpectedRequiredRole, repro.run(allocator, io, &args));

    var ambiguous = [_][]const u8{
        "repro-check",
        "compare",
        target,
        left_path,
        right_path,
        receipt_path,
    };
    try std.testing.expectError(error.InvalidArguments, repro.run(allocator, io, &ambiguous));

    var digest_only = ambiguous;
    digest_only[1] = "compare-digest";
    const digest_comparison = try repro.run(allocator, io, &digest_only);
    try std.testing.expectEqual(comparison.left.digest, digest_comparison.left.digest);
}

fn writeRoleManifest(
    tmp: *std.testing.TmpDir,
    target: []const u8,
    entries: []const repro.RoleManifestEntry,
    authenticated: bool,
    path_buffer: []u8,
) ![]const u8 {
    var manifest: std.ArrayList(u8) = .empty;
    defer manifest.deinit(std.testing.allocator);
    try manifest.appendSlice(std.testing.allocator, "texflow-role-manifest-v1\n");
    try manifest.print(std.testing.allocator, "authenticated={s}\n", .{if (authenticated) "true" else "false"});
    try manifest.print(std.testing.allocator, "target={s}\n", .{target});
    for (entries) |entry| {
        try manifest.print(std.testing.allocator, "role={s}|{s}\n", .{ entry.name, entry.path });
    }
    const digest = repro.roleManifestDigest(target, entries);
    try manifest.print(std.testing.allocator, "manifest_sha256={s}\n", .{std.fmt.bytesToHex(digest, .lower)});
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "roles.manifest", .data = manifest.items });

    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(std.testing.io, &root_buffer)];
    return std.fmt.bufPrint(path_buffer, "{s}{c}roles.manifest", .{ root, std.fs.path.sep });
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
