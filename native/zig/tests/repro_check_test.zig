const std = @import("std");
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
