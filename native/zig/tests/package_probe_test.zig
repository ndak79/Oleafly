const std = @import("std");
const probe = @import("package_probe");
const contract = @import("package_probe_contract");
const testing = std.testing;
const allocator = testing.allocator;

test "source package includes the offline package oracle" {
    try testing.expect(std.mem.indexOf(u8, contract.zon, "\"tools/zig/package_probe.zig\"") != null);
}

test "empty fixture has exactly two end blocks and a valid gzip roundtrip" {
    if (comptime !@hasDecl(probe, "reproduce")) return error.MissingPackageProbe;
    var result = try probe.reproduce(allocator, &.{});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(usize, 1024), result.tar.len);
    try testing.expect(std.mem.allEqual(u8, result.tar, 0));
    try testing.expectEqual(@as(usize, 0), result.receipt.file_count);
    try testing.expectEqual(@as(usize, 0), result.receipt.payload_bytes);
    try probe.verifyRoundTrip(allocator, &.{}, result.gzip);
}

test "ustar bytes normalize metadata without changing exact payload" {
    if (comptime !@hasDecl(probe, "generate")) return error.MissingPackageProbe;
    const files = [_]probe.File{.{ .path = "a", .bytes = "hello", .source_mode = 0o777, .source_uid = 42, .source_gid = 73, .source_mtime = 999, .source_uname = "alice", .source_gname = "staff" }};
    var result = try probe.generate(allocator, &files);
    defer result.deinit(allocator);
    var expected = [_]u8{0} ** 2048;
    expected[0] = 'a';
    @memcpy(expected[100..108], "0000644\x00");
    @memcpy(expected[108..116], "0000000\x00");
    @memcpy(expected[116..124], "0000000\x00");
    @memcpy(expected[124..136], "00000000005\x00");
    @memcpy(expected[136..148], "00000000000\x00");
    @memcpy(expected[148..156], "006103\x00 ");
    expected[156] = '0';
    @memcpy(expected[257..263], "ustar\x00");
    @memcpy(expected[263..265], "00");
    @memcpy(expected[512..517], "hello");
    try testing.expectEqualSlices(u8, &expected, result.tar);
    try testing.expectEqualSlices(u8, &.{ 0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3 }, result.gzip[0..10]);
    const plain = [_]probe.File{.{ .path = "a", .bytes = "hello" }};
    var normalized = try probe.generate(allocator, &plain);
    defer normalized.deinit(allocator);
    try testing.expectEqualSlices(u8, result.tar, normalized.tar);
    try testing.expectEqualSlices(u8, result.gzip, normalized.gzip);
    try testing.expectEqualSlices(u8, result.inventory, normalized.inventory);
}

test "unsigned UTF8 ordinal sorting preserves names and inventory" {
    if (comptime !@hasDecl(probe, "generate")) return error.MissingPackageProbe;
    const files = [_]probe.File{
        .{ .path = "漢", .bytes = "3" },
        .{ .path = "z", .bytes = "1" },
        .{ .path = "é", .bytes = "2" },
        .{ .path = "A", .bytes = "0" },
    };
    var result = try probe.generate(allocator, &files);
    defer result.deinit(allocator);
    try expectTarFiles(result.tar, &.{ "A", "z", "é", "漢" }, &.{ "0", "1", "2", "3" });
    const ordered = [_]probe.File{ files[3], files[1], files[2], files[0] };
    var other = try probe.generate(allocator, &ordered);
    defer other.deinit(allocator);
    try testing.expectEqualSlices(u8, result.inventory, other.inventory);
    try testing.expectEqualSlices(u8, result.tar, other.tar);
    try testing.expectEqualSlices(u8, result.gzip, other.gzip);
}

test "unsafe or invalid UTF8 paths are rejected without renaming" {
    if (comptime !@hasDecl(probe, "generate")) return error.MissingPackageProbe;
    for ([_][]const u8{ "", "/a", "//host/a", "C:/a", "C:a", "a\\b", ".", "..", "./a", "a/../b", "a/./b", "a//b", "a/", "a\x00b", "\xff", "\xc0\xaf", "a\nb", "a:", "a?b", "a*b", "a ", "a.", "NUL", "con.txt", "LPT1" }) |path| {
        try testing.expectError(error.UnsafePath, probe.generate(allocator, &.{.{ .path = path, .bytes = "" }}));
    }
}

test "ustar name and prefix byte boundaries allow only representable paths" {
    if (comptime !@hasDecl(probe, "generate")) return error.MissingPackageProbe;
    const short = "n" ** 100;
    const longest = "p" ** 155 ++ "/" ++ "n" ** 100;
    var result = try probe.generate(allocator, &.{ .{ .path = short, .bytes = "" }, .{ .path = longest, .bytes = "x" } });
    defer result.deinit(allocator);
    try expectTarFiles(result.tar, &.{ short, longest }, &.{ "", "x" });
    for ([_][]const u8{ "n" ** 101, "p" ** 156 ++ "/" ++ "n" ** 100, "p/" ++ "é" ** 51 }) |path| {
        try testing.expectError(error.UnrepresentablePath, probe.generate(allocator, &.{.{ .path = path, .bytes = "" }}));
    }
}

test "Windows device aliases include superscripts extensions and nested components" {
    const digits = [_][]const u8{ "1", "9", "¹", "²", "³" };
    for ([_][]const u8{ "COM", "com", "LPT", "lPt" }) |prefix| {
        for (digits) |digit| {
            for ([_][]const u8{ "", ".dll", " .log", "/file" }) |suffix| {
                const path = try std.mem.concat(allocator, u8, &.{ "nested/", prefix, digit, suffix });
                defer allocator.free(path);
                try expectRejectedFiles(error.UnsafePath, &.{.{ .path = path, .bytes = "" }});
            }
        }
    }
    for ([_][]const u8{ "CON", "prn.txt", "AUX .log", "NUL", "CONIN$", "conout$.log" }) |path| {
        try expectRejectedFiles(error.UnsafePath, &.{.{ .path = path, .bytes = "" }});
    }
    // Similar but non-device components must retain their exact spelling.
    var result = try probe.generate(allocator, &.{ .{ .path = "COM10", .bytes = "" }, .{ .path = "LPT¹x.txt", .bytes = "" } });
    defer result.deinit(allocator);
    try expectTarFiles(result.tar, &.{ "COM10", "LPT¹x.txt" }, &.{ "", "" });
}

test "Windows ASCII case aliases collide at files and directory components" {
    const pairs = [_][2][]const u8{
        .{ "A", "a" },         .{ "Dir/A", "dir/a" },
        .{ "Bin/a", "bin/b" }, .{ "root/Sub/a", "root/sub/b" },
    };
    for (pairs) |paths| {
        try expectRejectedFiles(error.WindowsPathCollision, &.{ .{ .path = paths[0], .bytes = "x" }, .{ .path = paths[1], .bytes = "y" } });
        try expectRejectedFiles(error.WindowsPathCollision, &.{ .{ .path = paths[1], .bytes = "y" }, .{ .path = paths[0], .bytes = "x" } });
    }
    // The intervening byte-sorted entry must not hide a folded collision.
    try expectRejectedFiles(error.WindowsPathCollision, &.{ .{ .path = "A", .bytes = "" }, .{ .path = "Z", .bytes = "" }, .{ .path = "a", .bytes = "" } });
    var result = try probe.generate(allocator, &.{ .{ .path = "shared/Z", .bytes = "" }, .{ .path = "shared/a", .bytes = "" } });
    defer result.deinit(allocator);
    try expectTarFiles(result.tar, &.{ "shared/Z", "shared/a" }, &.{ "", "" });
}

test "Windows folded ancestor conflicts cannot coexist with regular files" {
    for ([_][2][]const u8{ .{ "A", "a/b" }, .{ "a", "A/b" }, .{ "Root/A", "root/a/b" } }) |paths| {
        try expectRejectedFiles(error.PathConflict, &.{ .{ .path = paths[0], .bytes = "" }, .{ .path = paths[1], .bytes = "" } });
        try expectRejectedFiles(error.PathConflict, &.{ .{ .path = paths[1], .bytes = "" }, .{ .path = paths[0], .bytes = "" } });
    }
    try expectRejectedFiles(error.PathConflict, &.{ .{ .path = "A", .bytes = "" }, .{ .path = "a-b", .bytes = "" }, .{ .path = "a/b", .bytes = "" } });
}

test "Windows Unicode case collisions include length changing uppercase mappings" {
    for ([_][2][]const u8{ .{ "é", "É" }, .{ "ɐ", "Ɐ" }, .{ "É/a", "é/b" }, .{ "root/Ɐ/a", "root/ɐ/b" } }) |paths| {
        try expectRejectedFiles(error.WindowsPathCollision, &.{ .{ .path = paths[0], .bytes = "" }, .{ .path = paths[1], .bytes = "" } });
        try expectRejectedFiles(error.WindowsPathCollision, &.{ .{ .path = paths[1], .bytes = "" }, .{ .path = paths[0], .bytes = "" } });
    }
    for ([_][2][]const u8{ .{ "É", "é/a" }, .{ "ɐ", "Ɐ/a" }, .{ "Ɐ", "ɐ/a" } }) |paths| {
        try expectRejectedFiles(error.PathConflict, &.{ .{ .path = paths[0], .bytes = "" }, .{ .path = paths[1], .bytes = "" } });
    }
}

test "nonregular inputs duplicate paths and file directory conflicts fail" {
    if (comptime !@hasDecl(probe, "generate")) return error.MissingPackageProbe;
    inline for (.{ .directory, .symlink, .hardlink, .device, .fifo, .socket }) |kind| {
        try testing.expectError(error.NonRegularFile, probe.generate(allocator, &.{.{ .path = "a", .bytes = "", .kind = kind }}));
    }
    try testing.expectError(error.DuplicatePath, probe.generate(allocator, &.{ .{ .path = "a", .bytes = "x" }, .{ .path = "a", .bytes = "y" } }));
    try testing.expectError(error.PathConflict, probe.generate(allocator, &.{ .{ .path = "a", .bytes = "" }, .{ .path = "a/b", .bytes = "" } }));
    try testing.expectError(error.PathConflict, probe.generate(allocator, &.{ .{ .path = "a", .bytes = "" }, .{ .path = "a-b", .bytes = "" }, .{ .path = "a/b", .bytes = "" } }));
}

test "receipt hashes bind every path exact byte and count" {
    if (comptime !@hasDecl(probe, "generate")) return error.MissingPackageProbe;
    var result = try probe.generate(allocator, &.{.{ .path = "a", .bytes = "hello" }});
    defer result.deinit(allocator);
    try testing.expectEqual(@as(usize, 1), result.receipt.file_count);
    try testing.expectEqual(@as(usize, 5), result.receipt.payload_bytes);
    try testing.expectEqual(result.inventory.len, result.receipt.inventory_bytes);
    try testing.expectEqual(result.tar.len, result.receipt.tar_bytes);
    try testing.expectEqual(result.gzip.len, result.receipt.gzip_bytes);
    try testing.expectEqual(hash(result.inventory), result.receipt.inventory_sha256);
    try testing.expectEqual(hash(result.tar), result.receipt.tar_sha256);
    try testing.expectEqual(hash(result.gzip), result.receipt.gzip_sha256);
    // Literal framing is independent of the writer: domain + LE counts/lengths
    // + exact UTF8 path + original byte count + file SHA-256.
    const expected = "texflow-package-inventory-v1\x00" ++ "\x01\x00\x00\x00\x00\x00\x00\x00" ++ "\x01\x00\x00\x00\x00\x00\x00\x00" ++ "a" ++ "\x05\x00\x00\x00\x00\x00\x00\x00";
    try testing.expectEqualSlices(u8, expected, result.inventory[0..expected.len]);
    try testing.expectEqualSlices(u8, &hash("hello"), result.inventory[expected.len..]);
    for ([_]probe.File{ .{ .path = "a", .bytes = "jello" }, .{ .path = "b", .bytes = "hello" } }) |file| {
        var changed = try probe.generate(allocator, &.{file});
        defer changed.deinit(allocator);
        try testing.expect(!std.mem.eql(u8, &result.receipt.inventory_sha256, &changed.receipt.inventory_sha256));
        try testing.expect(!std.mem.eql(u8, &result.receipt.tar_sha256, &changed.receipt.tar_sha256));
        try testing.expect(!std.mem.eql(u8, &result.receipt.gzip_sha256, &changed.receipt.gzip_sha256));
    }
}

test "independent roots own their bytes and regeneration compares complete outputs" {
    if (comptime !@hasDecl(probe, "reproduce")) return error.MissingPackageProbe;
    var path = [_]u8{'a'};
    var payload = [_]u8{ 0, 1, 255, 0 };
    var result = try probe.reproduce(allocator, &.{.{ .path = &path, .bytes = &payload }});
    defer result.deinit(allocator);
    path[0] = 'b';
    payload[0] = 4;
    try expectTarFiles(result.tar, &.{"a"}, &.{&.{ 0, 1, 255, 0 }});
    try probe.verifyRoundTrip(allocator, &.{.{ .path = "a", .bytes = &.{ 0, 1, 255, 0 } }}, result.gzip);
}

test "tar validator detects mutations extensions padding and end marker changes" {
    if (comptime !@hasDecl(probe, "validateTar")) return error.MissingPackageProbe;
    const files = [_]probe.File{.{ .path = "a", .bytes = "hello" }};
    var result = try probe.generate(allocator, &files);
    defer result.deinit(allocator);
    try probe.validateTar(allocator, &files, result.tar);
    for ([_]usize{ 0, 100, 108, 116, 124, 136, 148, 156, 157, 257, 263, 265, 297, 329, 337, 345, 500, 512, 517, 1024, 2047 }) |offset| {
        result.tar[offset] ^= 1;
        try testing.expectError(error.InvalidTar, probe.validateTar(allocator, &files, result.tar));
        result.tar[offset] ^= 1;
    }
    for ([_]u8{ 'x', 'g', 'L', 'K', '1', '2', '5' }) |kind| {
        result.tar[156] = kind;
        try testing.expectError(error.InvalidTar, probe.validateTar(allocator, &files, result.tar));
    }
    result.tar[156] = '0';
    try testing.expectError(error.InvalidTar, probe.validateTar(allocator, &files, result.tar[0..1536]));
    const trailing = try std.mem.concat(allocator, u8, &.{ result.tar, &([_]u8{0} ** 512) });
    defer allocator.free(trailing);
    try testing.expectError(error.InvalidTar, probe.validateTar(allocator, &files, trailing));
}

test "gzip oracle rejects corrupt header body checksum size truncation and concatenation" {
    if (comptime !@hasDecl(probe, "verifyRoundTrip")) return error.MissingPackageProbe;
    const files = [_]probe.File{.{ .path = "a", .bytes = "hello" }};
    var result = try probe.generate(allocator, &files);
    defer result.deinit(allocator);
    for ([_]usize{ 0, 2, 3, 4, 8, 9, 10, result.gzip.len - 8, result.gzip.len - 4 }) |offset| {
        result.gzip[offset] ^= 1;
        try testing.expectError(error.InvalidGzip, probe.verifyRoundTrip(allocator, &files, result.gzip));
        result.gzip[offset] ^= 1;
    }
    for (0..result.gzip.len) |length| {
        try testing.expectError(error.InvalidGzip, probe.verifyRoundTrip(allocator, &files, result.gzip[0..length]));
    }
    const concat = try std.mem.concat(allocator, u8, &.{ result.gzip, result.gzip });
    defer allocator.free(concat);
    try testing.expectError(error.InvalidGzip, probe.verifyRoundTrip(allocator, &files, concat));
    const trailing = try std.mem.concat(allocator, u8, &.{ result.gzip, "\x00" });
    defer allocator.free(trailing);
    try testing.expectError(error.InvalidGzip, probe.verifyRoundTrip(allocator, &files, trailing));
}

test "valid gzip with wrong or malformed tar cannot satisfy the payload manifest" {
    if (comptime !@hasDecl(probe, "verifyRoundTrip")) return error.MissingPackageProbe;
    const files = [_]probe.File{.{ .path = "a", .bytes = "hello" }};
    var result = try probe.generate(allocator, &files);
    defer result.deinit(allocator);
    try testing.expectError(error.InvalidTar, probe.verifyRoundTrip(allocator, &.{.{ .path = "a", .bytes = "jello" }}, result.gzip));
    result.tar[156] = 'L';
    const compressed = try gzipFixture(allocator, result.tar, .level_9);
    defer allocator.free(compressed);
    try testing.expectError(error.InvalidTar, probe.verifyRoundTrip(allocator, &files, compressed));
}

test "binary payload crosses block and deflate windows without loss" {
    if (comptime !@hasDecl(probe, "reproduce")) return error.MissingPackageProbe;
    const bytes = try allocator.alloc(u8, 150_003);
    defer allocator.free(bytes);
    var random = std.Random.DefaultPrng.init(0x7420);
    random.random().bytes(bytes);
    var result = try probe.reproduce(allocator, &.{.{ .path = "bin/runtime.dll", .bytes = bytes }});
    defer result.deinit(allocator);
    try expectTarFiles(result.tar, &.{"bin/runtime.dll"}, &.{bytes});
    try testing.expectEqual(bytes.len, result.receipt.payload_bytes);
}

test "valid alternate gzip encoding cannot replace the fixed level 9 oracle" {
    if (comptime !@hasDecl(probe, "verifyRoundTrip")) return error.MissingPackageProbe;
    const bytes = try allocator.alloc(u8, 100_000);
    defer allocator.free(bytes);
    var random = std.Random.DefaultPrng.init(0x19b9);
    random.random().bytes(bytes);
    for (bytes) |*byte| byte.* %= 17;
    @memcpy(bytes[60_000..90_000], bytes[0..30_000]);
    const files = [_]probe.File{.{ .path = "fixture.bin", .bytes = bytes }};
    var result = try probe.generate(allocator, &files);
    defer result.deinit(allocator);
    const alternate = try gzipFixture(allocator, result.tar, .level_1);
    defer allocator.free(alternate);
    try testing.expect(!std.mem.eql(u8, result.gzip, alternate));
    try testing.expectError(error.InvalidGzip, probe.verifyRoundTrip(allocator, &files, alternate));
}

test "oversized gzip output and omitted or additional manifest members fail" {
    if (comptime !@hasDecl(probe, "verifyRoundTrip")) return error.MissingPackageProbe;
    const files = [_]probe.File{.{ .path = "a", .bytes = "hello" }};
    var result = try probe.generate(allocator, &files);
    defer result.deinit(allocator);
    try testing.expectError(error.InvalidGzip, probe.verifyRoundTrip(allocator, &.{}, result.gzip));
    try testing.expectError(error.InvalidTar, probe.verifyRoundTrip(allocator, &.{ files[0], .{ .path = "b", .bytes = "" } }, result.gzip));
    const extra = try std.mem.concat(allocator, u8, &.{ result.tar, "\x00" });
    defer allocator.free(extra);
    const compressed = try gzipFixture(allocator, extra, .level_9);
    defer allocator.free(compressed);
    try testing.expectError(error.InvalidGzip, probe.verifyRoundTrip(allocator, &files, compressed));
}

test "allocation failures release every allocation through successful reproduction" {
    if (comptime !@hasDecl(probe, "reproduce")) return error.MissingPackageProbe;
    try testing.checkAllAllocationFailures(allocator, allocationExercise, .{});
}

fn allocationExercise(a: std.mem.Allocator) !void {
    var result = try probe.reproduce(a, &.{ .{ .path = "a", .bytes = "hello" }, .{ .path = "nested/b", .bytes = "world" } });
    defer result.deinit(a);
    try probe.validateTar(a, &.{ .{ .path = "a", .bytes = "hello" }, .{ .path = "nested/b", .bytes = "world" } }, result.tar);
}

// Unlike expectError on an owned Result, this also cleans up an unexpected
// success so a RED acceptance failure does not introduce test-only leaks.
fn expectRejectedFiles(expected: anyerror, files: []const probe.File) !void {
    var result = probe.generate(allocator, files) catch |err| {
        try testing.expectEqual(expected, err);
        return;
    };
    defer result.deinit(allocator);
    return error.ExpectedPackageRejection;
}

fn hash(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

fn expectTarFiles(tar: []const u8, names: []const []const u8, payloads: []const []const u8) !void {
    var reader = std.Io.Reader.fixed(tar);
    var name_buffer: [257]u8 = undefined;
    var link_buffer: [257]u8 = undefined;
    var iterator = std.tar.Iterator.init(&reader, .{ .file_name_buffer = &name_buffer, .link_name_buffer = &link_buffer });
    for (names, payloads) |name, payload| {
        const entry = (try iterator.next()) orelse return error.MissingTarEntry;
        try testing.expectEqualStrings(name, entry.name);
        try testing.expectEqual(std.tar.FileKind.file, entry.kind);
        try testing.expectEqual(@as(u32, 0o644), entry.mode);
        try testing.expectEqual(payload.len, entry.size);
        var actual = std.Io.Writer.Allocating.init(allocator);
        defer actual.deinit();
        try iterator.streamRemaining(entry, &actual.writer);
        try testing.expectEqualSlices(u8, payload, actual.written());
    }
    try testing.expectEqual(@as(?std.tar.Iterator.File, null), try iterator.next());
}

fn gzipFixture(a: std.mem.Allocator, bytes: []const u8, options: std.compress.flate.Compress.Options) ![]u8 {
    var output = try std.Io.Writer.Allocating.initCapacity(a, 4096);
    defer output.deinit();
    var history: [std.compress.flate.max_window_len * 2]u8 = undefined;
    var compressor = try std.compress.flate.Compress.init(&output.writer, &history, .gzip, options);
    try compressor.writer.writeAll(bytes);
    try compressor.finish();
    return output.toOwnedSlice();
}
