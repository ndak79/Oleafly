const std = @import("std");
const evidence = @import("bench_evidence_pack");

test "content-addressed manifest is independent of input order and changes on bytes" {
    const inputs = [_]evidence.Input{
        .{ .path = "raw/wpa.csv", .bytes = "wpa" },
        .{ .path = "raw/presentmon.csv", .bytes = "present" },
    };
    var first = try evidence.manifestFromInputs(std.testing.allocator, &inputs);
    defer first.deinit();
    const swapped = [_]evidence.Input{ inputs[1], inputs[0] };
    var second = try evidence.manifestFromInputs(std.testing.allocator, &swapped);
    defer second.deinit();
    try std.testing.expectEqual(first.digest, second.digest);

    const changed = [_]evidence.Input{
        .{ .path = "raw/wpa.csv", .bytes = "tampered" },
        .{ .path = "raw/presentmon.csv", .bytes = "present" },
    };
    var different = try evidence.manifestFromInputs(std.testing.allocator, &changed);
    defer different.deinit();
    try std.testing.expect(!std.mem.eql(u8, &first.digest, &different.digest));
}

test "evidence copy is rehashed and rejects tampering, truncation, and unsafe paths" {
    const inputs = [_]evidence.Input{
        .{ .path = "raw/nested/sample.csv", .bytes = "fixture" },
    };
    var manifest = try evidence.manifestFromInputs(std.testing.allocator, &inputs);
    defer manifest.deinit();
    var source = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer source.cleanup();
    var destination = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer destination.cleanup();
    try source.dir.createDirPath(std.testing.io, "raw/nested");
    try source.dir.writeFile(std.testing.io, .{ .sub_path = "raw/nested/sample.csv", .data = "fixture" });
    try evidence.copyAndVerify(std.testing.allocator, std.testing.io, source.dir, destination.dir, manifest);
    try evidence.rehash(std.testing.allocator, std.testing.io, destination.dir, manifest);

    try destination.dir.writeFile(std.testing.io, .{ .sub_path = "raw/nested/sample.csv", .data = "tampered" });
    try std.testing.expectError(error.DigestMismatch, evidence.rehash(std.testing.allocator, std.testing.io, destination.dir, manifest));

    try std.testing.expectError(error.InvalidPath, evidence.manifestFromInputs(std.testing.allocator, &.{.{ .path = "../secret", .bytes = "x" }}));
    try std.testing.expectError(error.InvalidPath, evidence.manifestFromInputs(std.testing.allocator, &.{.{ .path = "C:/secret", .bytes = "x" }}));
    try std.testing.expectError(error.DuplicatePath, evidence.manifestFromInputs(std.testing.allocator, &.{
        .{ .path = "raw/sample.bin", .bytes = "x" },
        .{ .path = "raw/sample.bin", .bytes = "y" },
    }));
    try std.testing.expectError(error.DuplicatePath, evidence.manifestFromInputs(std.testing.allocator, &.{
        .{ .path = "raw/SAMPLE.bin", .bytes = "x" },
        .{ .path = "raw/sample.BIN", .bytes = "x" },
    }));
    try std.testing.expectError(error.InvalidPath, evidence.manifestFromInputs(std.testing.allocator, &.{.{ .path = "raw/é.bin", .bytes = "x" }}));
    try std.testing.expectError(error.InvalidPath, evidence.manifestFromInputs(std.testing.allocator, &.{.{ .path = "raw/CON.txt", .bytes = "x" }}));
    try std.testing.expectError(error.InvalidPath, evidence.manifestFromInputs(std.testing.allocator, &.{.{ .path = "raw/COM1.txt", .bytes = "x" }}));
    try std.testing.expectError(error.InvalidPath, evidence.manifestFromInputs(std.testing.allocator, &.{.{ .path = "raw/unsafe?.bin", .bytes = "x" }}));
}

test "evidence copy refuses to overwrite an existing conflicting leaf" {
    const inputs = [_]evidence.Input{.{ .path = "raw/sample.bin", .bytes = "fixture" }};
    var manifest = try evidence.manifestFromInputs(std.testing.allocator, &inputs);
    defer manifest.deinit();
    var source = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer source.cleanup();
    var destination = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer destination.cleanup();
    try source.dir.createDirPath(std.testing.io, "raw");
    try destination.dir.createDirPath(std.testing.io, "raw");
    try source.dir.writeFile(std.testing.io, .{ .sub_path = "raw/sample.bin", .data = "fixture" });
    try destination.dir.writeFile(std.testing.io, .{ .sub_path = "raw/sample.bin", .data = "conflict" });
    try std.testing.expectError(error.DigestMismatch, evidence.copyAndVerify(std.testing.allocator, std.testing.io, source.dir, destination.dir, manifest));
    const preserved = try destination.dir.readFileAlloc(std.testing.io, "raw/sample.bin", std.testing.allocator, .limited(128));
    defer std.testing.allocator.free(preserved);
    try std.testing.expectEqualStrings("conflict", preserved);
}

test "evidence retention requires two independently rehashed authorized copies" {
    const inputs = [_]evidence.Input{.{ .path = "raw/sample.bin", .bytes = "fixture" }};
    var manifest = try evidence.manifestFromInputs(std.testing.allocator, &inputs);
    defer manifest.deinit();
    var one = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer one.cleanup();
    var two = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer two.cleanup();
    try one.dir.createDirPath(std.testing.io, "raw");
    try two.dir.createDirPath(std.testing.io, "raw");
    try one.dir.writeFile(std.testing.io, .{ .sub_path = "raw/sample.bin", .data = "fixture" });
    try two.dir.writeFile(std.testing.io, .{ .sub_path = "raw/sample.bin", .data = "fixture" });
    try evidence.verifyDurableCopies(std.testing.allocator, std.testing.io, one.dir, two.dir, manifest);
    try std.testing.expectError(error.SameCopy, evidence.verifyDurableCopies(std.testing.allocator, std.testing.io, one.dir, one.dir, manifest));
    try two.dir.writeFile(std.testing.io, .{ .sub_path = "raw/sample.bin", .data = "changed" });
    try std.testing.expectError(error.DigestMismatch, evidence.verifyDurableCopies(std.testing.allocator, std.testing.io, one.dir, two.dir, manifest));
}

test "evidence retention rejects hard-linked aliases" {
    const inputs = [_]evidence.Input{.{ .path = "raw/sample.bin", .bytes = "fixture" }};
    var manifest = try evidence.manifestFromInputs(std.testing.allocator, &inputs);
    defer manifest.deinit();
    var one = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer one.cleanup();
    var two = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer two.cleanup();
    try one.dir.createDirPath(std.testing.io, "raw");
    try two.dir.createDirPath(std.testing.io, "raw");
    try one.dir.writeFile(std.testing.io, .{ .sub_path = "raw/sample.bin", .data = "fixture" });
    try two.dir.writeFile(std.testing.io, .{ .sub_path = "raw/sample.bin", .data = "fixture" });
    std.Io.Dir.hardLink(one.dir, "raw/sample.bin", one.dir, "raw/alias.bin", std.testing.io, .{}) catch |err| switch (err) {
        error.AccessDenied, error.PermissionDenied, error.OperationUnsupported => return error.SkipZigTest,
        else => return err,
    };
    try std.testing.expectError(error.SameCopy, evidence.verifyDurableCopies(std.testing.allocator, std.testing.io, one.dir, two.dir, manifest));
}

test "evidence copy rejects intermediate symlink/reparse parents" {
    const inputs = [_]evidence.Input{.{ .path = "raw-link/sample.bin", .bytes = "fixture" }};
    var manifest = try evidence.manifestFromInputs(std.testing.allocator, &inputs);
    defer manifest.deinit();
    var source = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer source.cleanup();
    var destination = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer destination.cleanup();
    try source.dir.createDirPath(std.testing.io, "raw/real");
    try source.dir.writeFile(std.testing.io, .{ .sub_path = "raw/real/sample.bin", .data = "fixture" });
    source.dir.symLink(std.testing.io, "raw/real", "raw-link", .{ .is_directory = true }) catch |err| switch (err) {
        error.AccessDenied, error.PermissionDenied, error.FileSystem => return error.SkipZigTest,
        else => return err,
    };
    try std.testing.expectError(error.ReparsePoint, evidence.copyAndVerify(
        std.testing.allocator,
        std.testing.io,
        source.dir,
        destination.dir,
        manifest,
    ));
}
