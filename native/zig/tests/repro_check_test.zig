const std = @import("std");
const builtin = @import("builtin");
const repro = @import("repro_check");

test "repro preflight rejects incomplete or unsafe admission" {
    try repro.validateTarget("x86_64-windows-msvc");
    try std.testing.expectError(error.TargetNotAdmitted, repro.validateTarget("aarch64-windows-msvc"));
    try std.testing.expectError(error.ReproRootMustBeAbsolute, repro.validateReproRoot("relative-root"));
    try std.testing.expectError(error.ReproRootUnsafe, repro.validateReproRoot("C:\\temp root"));
    try std.testing.expectError(error.ReproRootUnsafe, repro.validateReproRoot("C:\\temp\\..\\other"));
    if (comptime builtin.os.tag == .windows) {
        try std.testing.expectError(error.ReproRootUnsafe, repro.validateReproRoot("\\\\server\\share"));
        try std.testing.expectError(error.ReproRootUnsafe, repro.validateReproRoot("\\rooted"));
    }

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
    const roles = [_][]const u8{"bin/TExFlow.exe"};
    try repro.verifyRequiredRoles("x86_64-windows-msvc", &roles);
    try std.testing.expectError(error.MissingRequiredRole, repro.verifyRequiredRoles(
        "x86_64-windows-msvc",
        roles[0..0],
    ));
    const duplicate = [_][]const u8{
        "bin/TExFlow.exe",
        "bin/TExFlow.exe",
    };
    try std.testing.expectError(error.UnexpectedRequiredRole, repro.verifyRequiredRoles(
        "x86_64-windows-msvc",
        &duplicate,
    ));
    try std.testing.expectError(error.UnexpectedRequiredRole, repro.verifyRequiredRoles(
        "x86_64-windows-msvc",
        &.{ "bin/TExFlow.exe", "bin/TExFlow.PdfWorker.exe" },
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
    const valid_entries = [_]repro.RoleManifestEntry{.{ .name = "UI", .path = "bin/TExFlow.exe" }};

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
    var left_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var right_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var inputs_root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var receipt_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var manifest_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var payload_manifest_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var legacy_receipt_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const left_path = try realPathForTest(left.dir, &left_path_buffer);
    const right_path = try realPathForTest(right.dir, &right_path_buffer);
    const inputs_path = try realPathForTest(inputs.dir, &inputs_root_buffer);
    const receipt_path = try std.fmt.bufPrint(
        &receipt_path_buffer,
        "{s}{c}network.receipt",
        .{ inputs_path, std.fs.path.sep },
    );
    const legacy_receipt_path = try std.fmt.bufPrint(
        &legacy_receipt_path_buffer,
        "{s}{c}legacy.receipt",
        .{ inputs_path, std.fs.path.sep },
    );
    try inputs.dir.writeFile(io, .{
        .sub_path = "legacy.receipt",
        .data = "network_mode=none\nfetch_bytes=0\nroute_count=0\nproxy=unset\nprocess_policy=zig-owned\n",
    });

    const fixture_digest = sha256("fixture");
    const payload_entries = [_]repro.PayloadManifestEntry{.{
        .path = "bin/TExFlow.exe",
        .size = "fixture".len,
        .digest = fixture_digest,
    }};

    var args = [_][]const u8{
        "repro-check",
        "compare",
        target,
        left_path,
        right_path,
        legacy_receipt_path,
        undefined,
        undefined,
    };
    const valid_manifest = try writeRoleManifest(&inputs, target, &valid_entries, true, &manifest_path_buffer);
    args[6] = valid_manifest;
    args[7] = try writePayloadManifest(
        &inputs,
        target,
        &payload_entries,
        &payload_manifest_path_buffer,
    );
    const comparison = try repro.run(allocator, io, &args);
    try std.testing.expectEqual(comparison.left.files, comparison.right.files);
    try std.testing.expectEqual(comparison.left.bytes, comparison.right.bytes);
    try std.testing.expectEqual(comparison.left.digest, comparison.right.digest);

    var test_left = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer test_left.cleanup();
    var test_right = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer test_right.cleanup();
    try test_left.dir.writeFile(io, .{ .sub_path = "texflow_abi.lib", .data = "abi" });
    try test_right.dir.writeFile(io, .{ .sub_path = "texflow_abi.lib", .data = "abi" });
    var test_left_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var test_right_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const test_left_path = try realPathForTest(test_left.dir, &test_left_path_buffer);
    const test_right_path = try realPathForTest(test_right.dir, &test_right_path_buffer);
    const payload_manifest_for_receipt = try std.Io.Dir.cwd().readFileAlloc(
        io,
        args[7],
        allocator,
        .limited(4 * 1024 * 1024),
    );
    defer allocator.free(payload_manifest_for_receipt);
    const binding = repro.ReproBinding{
        .target = target,
        .source_commit = "0123456789abcdef0123456789abcdef01234567",
        .source_set_sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        .dependency_lock_sha256 = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
        .build_identity = "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
        .remote_run_id = "12345",
        .remote_run_attempt = "1",
    };
    const product_for_receipt = try repro.comparePayloadRootsWithManifest(
        allocator,
        io,
        target,
        left_path,
        right_path,
        payload_manifest_for_receipt,
    );
    const test_for_receipt = try repro.compareTestArtifactRoots(
        allocator,
        io,
        target,
        test_left_path,
        test_right_path,
    );
    _ = try writeBoundNetworkReceipt(
        &inputs,
        binding,
        valid_manifest,
        args[7],
        product_for_receipt,
        test_for_receipt,
        &receipt_path_buffer,
    );
    args[5] = legacy_receipt_path;
    var combined_args = [_][]const u8{
        "repro-check",
        "compare-both",
        target,
        left_path,
        right_path,
        test_left_path,
        test_right_path,
        receipt_path,
        valid_manifest,
        args[7],
        binding.source_commit,
        binding.source_set_sha256,
        binding.dependency_lock_sha256,
        binding.build_identity,
        binding.remote_run_id,
        binding.remote_run_attempt,
    };
    const combined = try repro.run(allocator, io, &combined_args);
    try std.testing.expectEqual(comparison.left.digest, combined.left.digest);
    try std.testing.expectEqual(comparison.right.digest, combined.right.digest);
    var wrong_run = combined_args;
    wrong_run[14] = "12346";
    try std.testing.expectError(error.ReproEvidenceBindingMismatch, repro.run(allocator, io, &wrong_run));
    _ = try writeRoleManifest(&inputs, target, &valid_entries, false, &manifest_path_buffer);
    try std.testing.expectError(error.ReproEvidenceBindingMismatch, repro.run(allocator, io, &combined_args));
    _ = try writeRoleManifest(&inputs, target, &valid_entries, true, &manifest_path_buffer);
    try std.testing.expectError(
        error.ReproRootsOverlap,
        repro.run(allocator, io, &[_][]const u8{
            "repro-check",
            "compare-both",
            target,
            left_path,
            left_path,
            test_left_path,
            test_right_path,
            receipt_path,
            valid_manifest,
            args[7],
            binding.source_commit,
            binding.source_set_sha256,
            binding.dependency_lock_sha256,
            binding.build_identity,
            binding.remote_run_id,
            binding.remote_run_attempt,
        }),
    );

    args[6] = try writeRoleManifest(&inputs, target, &valid_entries, false, &manifest_path_buffer);
    try std.testing.expectError(error.UnauthenticatedRoleManifest, repro.run(allocator, io, &args));

    const missing = valid_entries[0..0];
    args[6] = try writeRoleManifest(&inputs, target, missing, true, &manifest_path_buffer);
    try std.testing.expectError(error.MissingRequiredRole, repro.run(allocator, io, &args));

    const duplicate = [_]repro.RoleManifestEntry{ valid_entries[0], valid_entries[0] };
    args[6] = try writeRoleManifest(&inputs, target, &duplicate, true, &manifest_path_buffer);
    try std.testing.expectError(error.UnexpectedRequiredRole, repro.run(allocator, io, &args));

    var wrong = valid_entries;
    wrong[0] = .{ .name = "Installer", .path = "bin/TExFlow.exe" };
    args[6] = try writeRoleManifest(&inputs, target, &wrong, true, &manifest_path_buffer);
    try std.testing.expectError(error.UnexpectedRequiredRole, repro.run(allocator, io, &args));

    args[6] = try writeRoleManifest(&inputs, target, &valid_entries, true, &manifest_path_buffer);
    try left.dir.writeFile(io, .{ .sub_path = "payload-extra.txt", .data = "extra" });
    try right.dir.writeFile(io, .{ .sub_path = "payload-extra.txt", .data = "extra" });
    try std.testing.expectError(error.PayloadManifestExtraMember, repro.run(allocator, io, &args));
    try left.dir.deleteFile(io, "payload-extra.txt");
    try right.dir.deleteFile(io, "payload-extra.txt");

    try right.dir.deleteFile(io, "bin/TExFlow.exe");
    try right.dir.deleteDir(io, "bin");
    try std.testing.expectError(error.PayloadManifestMissingMember, repro.run(allocator, io, &args));
    try right.dir.createDir(io, "bin", .default_dir);
    try right.dir.writeFile(io, .{ .sub_path = "bin/TExFlow.exe", .data = "fixture" });

    try right.dir.writeFile(io, .{ .sub_path = "bin/TExFlow.exe", .data = "changed" });
    try std.testing.expectError(error.PayloadManifestMemberMismatch, repro.run(allocator, io, &args));
    try right.dir.writeFile(io, .{ .sub_path = "bin/TExFlow.exe", .data = "fixture" });

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
    digest_only[5] = legacy_receipt_path;
    const digest_comparison = try repro.run(allocator, io, &digest_only);
    try std.testing.expectEqual(comparison.left.digest, digest_comparison.left.digest);
}

test "test artifact lane admits only the cache-only ABI archive" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var left_tmp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer left_tmp.cleanup();
    var right_tmp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer right_tmp.cleanup();
    var inputs_tmp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer inputs_tmp.cleanup();
    try left_tmp.dir.writeFile(io, .{ .sub_path = "texflow_abi.lib", .data = "abi" });
    try right_tmp.dir.writeFile(io, .{ .sub_path = "texflow_abi.lib", .data = "abi" });
    try inputs_tmp.dir.writeFile(io, .{
        .sub_path = "network.receipt",
        .data = "network_mode=none\nfetch_bytes=0\nroute_count=0\nproxy=unset\nprocess_policy=zig-owned\n",
    });

    var left_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var right_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var inputs_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var receipt_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const left_path = try realPathForTest(left_tmp.dir, &left_path_buffer);
    const right_path = try realPathForTest(right_tmp.dir, &right_path_buffer);
    const inputs_path = try realPathForTest(inputs_tmp.dir, &inputs_path_buffer);
    const receipt_path = try std.fmt.bufPrint(
        &receipt_path_buffer,
        "{s}{c}network.receipt",
        .{ inputs_path, std.fs.path.sep },
    );
    const args = [_][]const u8{
        "repro-check",
        "compare-test",
        "x86_64-windows-msvc",
        left_path,
        right_path,
        receipt_path,
    };
    const comparison = try repro.run(allocator, io, &args);
    try std.testing.expectEqual(comparison.left.digest, comparison.right.digest);

    try left_tmp.dir.writeFile(io, .{ .sub_path = "unexpected.dll", .data = "not-abi" });
    try std.testing.expectError(error.UnexpectedTestArtifactMember, repro.run(allocator, io, &args));
}

fn realPathForTest(dir: std.Io.Dir, buffer: []u8) ![]const u8 {
    const io = std.testing.io;
    const path_len = try dir.realPath(io, buffer);
    if (comptime builtin.os.tag != .windows) return buffer[0..path_len];
    if (std.fs.path.parsePathWindows(u8, buffer[0..path_len]).kind != .rooted) {
        return buffer[0..path_len];
    }

    // Zig's Windows handle canonicalizer can return a drive-rooted path on
    // this fixture filesystem. It is safe to qualify it for a test because
    // the current drive is obtained from the process itself; production
    // inputs remain required to carry an explicit local drive root.
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_len = try std.process.currentPath(io, &cwd_buffer);
    if (cwd_len < 2 or cwd_buffer[1] != ':') return error.SkipZigTest;
    if (path_len > buffer.len - 2) return error.NameTooLong;
    @memmove(buffer[2 .. path_len + 2], buffer[0..path_len]);
    buffer[0] = cwd_buffer[0];
    buffer[1] = ':';
    return buffer[0 .. path_len + 2];
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
    const root = try realPathForTest(tmp.dir, &root_buffer);
    return std.fmt.bufPrint(path_buffer, "{s}{c}roles.manifest", .{ root, std.fs.path.sep });
}

fn writePayloadManifest(
    tmp: *std.testing.TmpDir,
    target: []const u8,
    entries: []const repro.PayloadManifestEntry,
    path_buffer: []u8,
) ![]const u8 {
    var total: u64 = 0;
    for (entries) |entry| total += entry.size;
    const tree = repro.PayloadSummary{
        .files = @intCast(entries.len),
        .bytes = total,
        .digest = repro.payloadTreeDigest(entries),
    };
    var manifest: std.ArrayList(u8) = .empty;
    defer manifest.deinit(std.testing.allocator);
    try manifest.appendSlice(std.testing.allocator, "texflow-payload-manifest-v1\n");
    try manifest.appendSlice(std.testing.allocator, "authenticated=true\n");
    try manifest.print(std.testing.allocator, "target={s}\n", .{target});
    for (entries) |entry| {
        try manifest.print(std.testing.allocator, "member={s}|{d}|{s}\n", .{
            entry.path,
            entry.size,
            std.fmt.bytesToHex(entry.digest, .lower),
        });
    }
    try manifest.print(std.testing.allocator, "tree={d}|{d}|{s}\n", .{
        tree.files,
        tree.bytes,
        std.fmt.bytesToHex(tree.digest, .lower),
    });
    const digest = repro.payloadManifestDigest(target, entries, tree);
    try manifest.print(std.testing.allocator, "manifest_sha256={s}\n", .{std.fmt.bytesToHex(digest, .lower)});
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "payload.manifest", .data = manifest.items });

    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try realPathForTest(tmp.dir, &root_buffer);
    return std.fmt.bufPrint(path_buffer, "{s}{c}payload.manifest", .{ root, std.fs.path.sep });
}

fn appendBoundSummary(
    manifest: *std.ArrayList(u8),
    prefix: []const u8,
    summary: repro.PayloadSummary,
) !void {
    try manifest.print(std.testing.allocator, "{s}={d}|{d}|{s}\n", .{
        prefix,
        summary.files,
        summary.bytes,
        std.fmt.bytesToHex(summary.digest, .lower),
    });
}

fn writeBoundNetworkReceipt(
    tmp: *std.testing.TmpDir,
    binding: repro.ReproBinding,
    role_manifest_path: []const u8,
    payload_manifest_path: []const u8,
    product: repro.PayloadComparison,
    test_artifact: repro.PayloadComparison,
    path_buffer: []u8,
) ![]const u8 {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const role_bytes = try std.Io.Dir.cwd().readFileAlloc(io, role_manifest_path, allocator, .limited(16 * 1024));
    defer allocator.free(role_bytes);
    const payload_bytes = try std.Io.Dir.cwd().readFileAlloc(io, payload_manifest_path, allocator, .limited(4 * 1024 * 1024));
    defer allocator.free(payload_bytes);
    var role_hex = std.fmt.bytesToHex(sha256(role_bytes), .lower);
    var payload_hex = std.fmt.bytesToHex(sha256(payload_bytes), .lower);
    var manifest: std.ArrayList(u8) = .empty;
    defer manifest.deinit(allocator);
    try manifest.appendSlice(allocator, "texflow-repro-receipt-v2\n");
    try manifest.print(allocator, "target={s}\nsource_commit={s}\nsource_set_sha256={s}\ndependency_lock_sha256={s}\nbuild_identity={s}\nremote_run_id={s}\nremote_run_attempt={s}\nrole_manifest_sha256={s}\npayload_manifest_sha256={s}\n", .{
        binding.target,
        binding.source_commit,
        binding.source_set_sha256,
        binding.dependency_lock_sha256,
        binding.build_identity,
        binding.remote_run_id,
        binding.remote_run_attempt,
        &role_hex,
        &payload_hex,
    });
    try appendBoundSummary(&manifest, "product_left", product.left);
    try appendBoundSummary(&manifest, "product_right", product.right);
    try appendBoundSummary(&manifest, "test_left", test_artifact.left);
    try appendBoundSummary(&manifest, "test_right", test_artifact.right);
    try manifest.appendSlice(allocator, "network_mode=none\nfetch_bytes=0\nroute_count=0\nproxy=unset\nprocess_policy=zig-owned\n");
    var receipt_hex = std.fmt.bytesToHex(sha256(manifest.items), .lower);
    try manifest.print(allocator, "receipt_sha256={s}\n", .{&receipt_hex});
    try tmp.dir.writeFile(io, .{ .sub_path = "network.receipt", .data = manifest.items });
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try realPathForTest(tmp.dir, &root_buffer);
    return std.fmt.bufPrint(path_buffer, "{s}{c}network.receipt", .{ root, std.fs.path.sep });
}

fn sha256(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
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
    const left_path = try realPathForTest(left_tmp.dir, &left_path_buf);
    const right_path = try realPathForTest(right_tmp.dir, &right_path_buf);
    try std.testing.expectError(
        error.ReproRootsOverlap,
        repro.comparePayloadRoots(allocator, std.testing.io, left_path, left_path),
    );
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
    const root = try realPathForTest(temporary.dir, &root_buffer);
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
    const root = try realPathForTest(temporary.dir, &root_buffer);
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
    const left_path = try realPathForTest(left_tmp.dir, &left_path_buffer);
    const right_path = try realPathForTest(right_tmp.dir, &right_path_buffer);
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
