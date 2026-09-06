const std = @import("std");
const deps = @import("deps");
const probe = @import("lexilla_probe");
const contract = @import("lexilla_contract");

test "Lexilla comparator contract is implemented and closed before product use" {
    try probe.verifyContract();
    try std.testing.expectEqualStrings(probe.artifact_name, contract.artifact_name);
    try std.testing.expectEqualStrings(probe.archive_sha256, contract.archive_sha256);
    try std.testing.expectEqualStrings(probe.license_spdx, contract.license_spdx);
    try std.testing.expectEqualStrings(probe.license_sha256, contract.license_sha256);
}

test "Lexilla source inventory names the reviewed static subset" {
    try probe.verifySourceList(contract.source_files);
    try std.testing.expectEqual(probe.sources.len, contract.source_files.len);
    try std.testing.expectEqual(probe.archive_member_names.len, contract.archive_member_names.len);
    for (probe.archive_member_names, contract.archive_member_names) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual);
    }
    try std.testing.expectEqual(probe.reviewed_fixtures.len, contract.fixtures.len);
    for (probe.reviewed_fixtures, contract.fixtures) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual);
    }
    try std.testing.expectEqualStrings("5.5.3", probe.version);
    try std.testing.expectEqualStrings("LicenseRef-Lexilla", probe.license_spdx);
    try std.testing.expectEqualStrings("lexilla-comparator-t0-2b-unshipped", probe.artifact_name);
}

test "Lexilla inventory and license mutations are rejected" {
    var duplicate = probe.sources;
    duplicate[0] = duplicate[1];
    try std.testing.expectError(error.SourceInventoryMismatch, probe.verifySourceList(&duplicate));
    try std.testing.expectError(error.SourceInventoryMismatch, probe.verifySourceList(probe.sources[1..]));
    var catalogue = probe.sources;
    catalogue[14] = "src/Lexilla.cxx";
    try std.testing.expectError(error.SourceInventoryMismatch, probe.verifySourceList(&catalogue));
    try std.testing.expectError(error.DigestMismatch, probe.verifyLicense("changed license"));
    try std.testing.expectError(error.DynamicArtifactRejected, probe.verifyArtifact(std.testing.allocator, std.testing.io, "fake-lexilla.dll"));
}

test "Lexilla lock identity is bound to the verified source snapshot" {
    var parsed = try deps.parseLockedManifest(std.testing.allocator);
    defer parsed.deinit();
    const artifact = deps.findArtifact(parsed.value, "lexilla") orelse return error.MissingLexillaLock;
    try probe.verifyLockedIdentity(artifact);

    var changed = artifact;
    changed.version = "5.5.4";
    try std.testing.expectError(error.LockIdentityMismatch, probe.verifyLockedIdentity(changed));
    changed = artifact;
    changed.archive_size_bytes = 1;
    try std.testing.expectError(error.LockIdentityMismatch, probe.verifyLockedIdentity(changed));
    changed = artifact;
    changed.archive_sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    try std.testing.expectError(error.LockIdentityMismatch, probe.verifyLockedIdentity(changed));
    changed = artifact;
    changed.license_spdx = "MIT";
    try std.testing.expectError(error.LockIdentityMismatch, probe.verifyLockedIdentity(changed));
}

test "Lexilla archive member audit rejects duplicates and unreviewed objects" {
    try probe.verifyMemberNames(&probe.archive_member_names);

    var duplicate = probe.archive_member_names;
    duplicate[0] = duplicate[1];
    try std.testing.expectError(error.ArchiveMemberMismatch, probe.verifyMemberNames(&duplicate));

    var extra: [probe.archive_member_names.len + 1][]const u8 = undefined;
    @memcpy(extra[0..probe.archive_member_names.len], &probe.archive_member_names);
    extra[probe.archive_member_names.len] = "Lexilla.obj";
    try std.testing.expectError(error.ArchiveMemberMismatch, probe.verifyMemberNames(&extra));
    try std.testing.expectError(error.CatalogueOrLoaderSymbolPresent, probe.verifyForbiddenSymbols("CatalogueModules"));
    try std.testing.expectError(error.EmptyComparatorArtifact, probe.verifyArtifactBytes(&.{}));
}

test "Lexilla long-name archive aliases fail closed" {
    try probe.verifyArchiveMemberPath(".zig-cache\\o\\0123456789abcdef0123456789abcdef\\Accessor.obj");
    try std.testing.expectError(error.ArchiveMemberNameMismatch, probe.verifyArchiveMemberPath("evil\\Accessor.obj"));
    try std.testing.expectError(error.ArchiveMemberNameMismatch, probe.verifyArchiveMemberPath(".zig-cache\\o\\short\\Accessor.obj"));
    try std.testing.expectError(
        error.ArchiveMemberNameMismatch,
        probe.verifyArchiveMemberPath("evil\\.zig-cache\\o\\0123456789abcdef0123456789abcdef\\Accessor.obj"),
    );
    try std.testing.expectError(
        error.ArchiveMemberNameMismatch,
        probe.verifyArchiveMemberPath("..\\.zig-cache\\o\\0123456789abcdef0123456789abcdef\\Accessor.obj"),
    );
}

test "Lexilla build is static and has no product install or worker edge" {
    const windows = @import("builtin").os.tag == .windows;
    try std.testing.expectEqual(windows, contract.library_created);
    if (windows) {
        try std.testing.expect(contract.library_reaches_snapshot);
        try std.testing.expect(contract.library_reaches_probe);
        try std.testing.expect(contract.library_reaches_source_root);
    }
    try std.testing.expect(!contract.install_reaches_library);
    try std.testing.expect(!contract.product_reaches_library);
    try std.testing.expect(!contract.worker_reaches_library);
    try std.testing.expect(!contract.install_reaches_snapshot);
    try std.testing.expect(!contract.product_reaches_snapshot);
    try std.testing.expect(!contract.worker_reaches_snapshot);
    try std.testing.expect(!contract.install_reaches_probe);
    try std.testing.expect(!contract.product_reaches_probe);
    try std.testing.expect(!contract.worker_reaches_probe);
    try std.testing.expect(!contract.install_reaches_source_root);
    try std.testing.expect(!contract.product_reaches_source_root);
    try std.testing.expect(!contract.worker_reaches_source_root);
    try std.testing.expect(!contract.install_reaches_loader);
    try std.testing.expect(!contract.product_reaches_loader);
    try std.testing.expect(!contract.worker_reaches_loader);
    if (@import("builtin").os.tag == .windows) {
        const shipping = try probe.auditShippingManifest(
            std.testing.allocator,
            std.testing.io,
            contract.shipping_manifest_path,
            contract.artifact_path,
        );
        try std.testing.expect(!shipping.member_present);
        try std.testing.expectEqual(@as(u64, 0), shipping.payload_bytes);
    }
    if (windows) {
        try std.testing.expectEqualStrings("lib", contract.artifact_kind);
        try std.testing.expectEqualStrings("static", contract.artifact_linkage);
    } else {
        try std.testing.expectEqualStrings("absent", contract.artifact_kind);
        try std.testing.expectEqualStrings("absent", contract.artifact_linkage);
    }
    const flags = probe.cxxFlags(@import("builtin").mode);
    try std.testing.expectEqual(flags.len, contract.cxx_flags.len);
    for (flags, contract.cxx_flags) |expected, actual| try std.testing.expectEqualStrings(expected, actual);
}

test "Lexilla archive identity fails closed before extraction" {
    try std.testing.expectError(error.SourceArchiveSizeMismatch, probe.verifyArchive("wrong"));
    const bytes = try std.testing.allocator.alloc(u8, 1_116_541);
    defer std.testing.allocator.free(bytes);
    @memset(bytes, 0);
    try std.testing.expectError(error.DigestMismatch, probe.verifyArchive(bytes));
}

test "Windows snapshot and archive contain only the reviewed comparator" {
    if (@import("builtin").os.tag != .windows) return;
    try std.testing.expect(contract.artifact_size_receipt.len > 0);
    try probe.verifySourceRoot(std.testing.allocator, std.testing.io, contract.source_root);
    const measured = try probe.verifyArtifact(std.testing.allocator, std.testing.io, contract.artifact_path);
    try std.testing.expect(measured > 0);
    try std.testing.expectEqual(@import("lexilla_size").artifact_size_bytes, measured);
    const receipt = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, contract.snapshot_receipt_path, std.testing.allocator, .limited(512));
    defer std.testing.allocator.free(receipt);
    try probe.verifyLockReceiptBytes(receipt);
}

fn appendArchiveObject(allocator: std.mem.Allocator, original: []const u8, name: []const u8) ![]u8 {
    const data = [_]u8{'x'};
    const prefix_padding = original.len & 1;
    const result = try allocator.alloc(u8, original.len + prefix_padding + 60 + data.len + 1);
    @memcpy(result[0..original.len], original);
    var offset = original.len;
    if (prefix_padding != 0) {
        result[offset] = 0;
        offset += 1;
    }
    const header = result[offset .. offset + 60];
    @memset(header, ' ');
    @memcpy(header[0..name.len], name);
    header[48] = '1';
    header[58] = '`';
    header[59] = '\n';
    @memcpy(result[offset + 60 .. offset + 61], &data);
    result[offset + 61] = 0;
    return result;
}

fn objectHeaderAt(bytes: []const u8, wanted: usize) !usize {
    var offset: usize = 8;
    var object_index: usize = 0;
    while (offset < bytes.len) {
        if (bytes.len - offset < 60) return error.MissingArchiveFixture;
        const header = bytes[offset .. offset + 60];
        const size = std.fmt.parseInt(usize, std.mem.trim(u8, header[48..58], " "), 10) catch return error.MissingArchiveFixture;
        const data_end = offset + 60 + size;
        if (data_end > bytes.len) return error.MissingArchiveFixture;
        const raw_name = std.mem.trim(u8, header[0..16], " ");
        if (!std.mem.eql(u8, raw_name, "/") and !std.mem.eql(u8, raw_name, "//")) {
            if (object_index == wanted) return offset;
            object_index += 1;
        }
        offset = data_end + (size & 1);
    }
    return error.MissingArchiveFixture;
}

fn removeArchiveMember(allocator: std.mem.Allocator, original: []const u8, wanted: []const u8) ![]u8 {
    var offset: usize = 8;
    while (offset < original.len) {
        if (original.len - offset < 60) return error.MissingArchiveFixture;
        const header = original[offset .. offset + 60];
        const size = std.fmt.parseInt(usize, std.mem.trim(u8, header[48..58], " "), 10) catch return error.MissingArchiveFixture;
        const member_end = offset + 60 + size + (size & 1);
        if (member_end > original.len) return error.MissingArchiveFixture;
        const raw_name = std.mem.trim(u8, header[0..16], " ");
        if (std.mem.eql(u8, raw_name, wanted)) {
            const result = try allocator.alloc(u8, original.len - (member_end - offset));
            @memcpy(result[0..offset], original[0..offset]);
            @memcpy(result[offset..], original[member_end..]);
            return result;
        }
        offset = member_end;
    }
    return error.MissingArchiveFixture;
}

test "Windows COFF archive parser rejects a real artifact with an extra object" {
    if (@import("builtin").os.tag != .windows) return;
    const original = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, contract.artifact_path, std.testing.allocator, .limited(64 * 1024 * 1024));
    defer std.testing.allocator.free(original);
    const mutated = try appendArchiveObject(std.testing.allocator, original, "Extra.obj/");
    defer std.testing.allocator.free(mutated);
    try std.testing.expectError(error.ArchiveMemberMismatch, probe.verifyCoffArchive(mutated));

    const missing = try std.testing.allocator.dupe(u8, original);
    defer std.testing.allocator.free(missing);
    const missing_header = missing[(try objectHeaderAt(missing, probe.archive_member_names.len - 1))..][0..60];
    @memset(missing_header[0..16], ' ');
    missing_header[0] = '/';
    var missing_rejected = false;
    probe.verifyCoffArchive(missing) catch |err| {
        missing_rejected = true;
        try std.testing.expect(err == error.ArchiveMemberMismatch or err == error.ArchiveFormatMismatch);
    };
    try std.testing.expect(missing_rejected);

    const duplicate = try std.testing.allocator.dupe(u8, original);
    defer std.testing.allocator.free(duplicate);
    const duplicate_header = duplicate[(try objectHeaderAt(duplicate, probe.archive_member_names.len - 1))..][0..60];
    @memset(duplicate_header[0..16], ' ');
    @memcpy(duplicate_header[0..11], "InList.obj/");
    try std.testing.expectError(error.ArchiveMemberMismatch, probe.verifyCoffArchive(duplicate));
}

test "Windows COFF archive requires the canonical special members" {
    if (@import("builtin").os.tag != .windows) return;
    const original = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, contract.artifact_path, std.testing.allocator, .limited(64 * 1024 * 1024));
    defer std.testing.allocator.free(original);
    const missing_linker = try removeArchiveMember(std.testing.allocator, original, "/");
    defer std.testing.allocator.free(missing_linker);
    try std.testing.expectError(error.ArchiveMemberMismatch, probe.verifyCoffArchive(missing_linker));
}

test "Windows shipping manifest audit rejects Lexilla payload mutations" {
    if (@import("builtin").os.tag != .windows) return;
    const allocator = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "valid-manifest.txt", .data = "lexilla-comparator-t0-2b-unshipped.lib\n" });
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = path_buffer[0..try temporary.dir.realPath(std.testing.io, &path_buffer)];
    const valid_path = try std.fs.path.join(allocator, &.{ root, "valid-manifest.txt" });
    defer allocator.free(valid_path);
    const valid = try probe.auditShippingManifest(allocator, std.testing.io, valid_path, contract.artifact_path);
    try std.testing.expect(valid.member_present);
    try std.testing.expect(valid.payload_bytes > 0);

    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "valid-manifest.txt", .data = "unexpected-lexilla.lib\n" });
    try std.testing.expectError(
        error.ShippingManifestMismatch,
        probe.auditShippingManifest(allocator, std.testing.io, valid_path, contract.artifact_path),
    );
}

test "Windows Lexilla snapshot rejects extra and modified members" {
    if (@import("builtin").os.tag != .windows) return;
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = path_buffer[0..try temporary.dir.realPath(io, &path_buffer)];
    const output = try std.fs.path.join(allocator, &.{ root, "snapshot" });
    defer allocator.free(output);

    try probe.snapshot(allocator, io, contract.archive_path, output);
    try probe.snapshot(allocator, io, contract.archive_path, output);
    const receipt_path = try std.fmt.allocPrint(allocator, "{s}.lock.json", .{output});
    defer allocator.free(receipt_path);
    const receipt = try std.Io.Dir.cwd().readFileAlloc(io, receipt_path, allocator, .limited(512));
    defer allocator.free(receipt);
    try probe.verifyLockReceiptBytes(receipt);
    var published = try temporary.dir.openDir(io, "snapshot", .{});
    defer published.close(io);
    try published.writeFile(io, .{ .sub_path = "unexpected.cxx", .data = "injected comparator source" });
    try std.testing.expectError(error.SourceSnapshotMismatch, probe.snapshot(allocator, io, contract.archive_path, output));
    try published.deleteFile(io, "unexpected.cxx");
    try published.writeFile(io, .{ .sub_path = "lexilla/lexlib/Accessor.cxx", .data = "modified" });
    try std.testing.expectError(error.SourceSnapshotMismatch, probe.snapshot(allocator, io, contract.archive_path, output));
}

test "Windows snapshot rejects a tampered lock identity receipt" {
    if (@import("builtin").os.tag != .windows) return;
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = path_buffer[0..try temporary.dir.realPath(io, &path_buffer)];
    const output = try std.fs.path.join(allocator, &.{ root, "snapshot" });
    defer allocator.free(output);
    try probe.snapshot(allocator, io, contract.archive_path, output);
    try temporary.dir.writeFile(io, .{ .sub_path = "snapshot.lock.json", .data = "tampered\n" });
    try std.testing.expectError(error.LockReceiptMismatch, probe.snapshot(allocator, io, contract.archive_path, output));
}
