const std = @import("std");
const deps = @import("deps");
const unicode = @import("unicode");
const unicode_data = @import("unicode_data");
const ucd_contract = @import("ucd_contract");

const ucd_root = ucd_contract.root;

test "Unicode 17 tables are bounded and identify their source" {
    try std.testing.expectEqualStrings("17.0.0", unicode.unicode_version);
    try std.testing.expectEqual(@as(comptime_int, 57), unicode.uax15_revision);
    try std.testing.expectEqual(@as(comptime_int, 47), unicode.uax29_revision);
    try std.testing.expect(unicode.table_bytes <= 512 * 1024);
    try std.testing.expectEqualStrings(
        "2066d1909b2ea93916ce092da1c0ee4808ea3ef8407c94b4f14f5b7eb263d28e",
        unicode_data.source_archive_sha256,
    );
}

test "NFD and full default case folding preserve accents" {
    const vietnamese = try unicode.normalizeNfd(std.testing.allocator, "Ắ", 64);
    defer std.testing.allocator.free(vietnamese);
    try std.testing.expectEqualStrings("A\u{0306}\u{0301}", vietnamese);

    const folded = try unicode.foldNfd(std.testing.allocator, "Straße", 64);
    defer std.testing.allocator.free(folded);
    try std.testing.expectEqualStrings("strasse", folded);

    const accent = try unicode.foldNfd(std.testing.allocator, "É", 64);
    defer std.testing.allocator.free(accent);
    try std.testing.expectEqualStrings("e\u{0301}", accent);
    try std.testing.expectError(
        error.InvalidUtf8,
        unicode.normalizeNfd(std.testing.allocator, "\xff", 64),
    );
}

test "grapheme and word boundaries cover human-facing clusters" {
    const emoji = "👩‍🔬";
    const graphemes = try unicode.graphemeBoundaries(std.testing.allocator, emoji, 16);
    defer std.testing.allocator.free(graphemes);
    try std.testing.expectEqualSlices(usize, &.{ 0, emoji.len }, graphemes);

    const word = "can't";
    const words = try unicode.wordBoundaries(std.testing.allocator, word, 16);
    defer std.testing.allocator.free(words);
    try std.testing.expectEqualSlices(usize, &.{ 0, word.len }, words);
}

test "boundary helpers expose a strict scalar work cap" {
    const graphemes = try unicode.graphemeBoundaries(std.testing.allocator, "a", 1);
    defer std.testing.allocator.free(graphemes);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, graphemes);
    try std.testing.expectError(
        error.UnicodeScalarLimitExceeded,
        unicode.graphemeBoundaries(std.testing.allocator, "ab", 1),
    );

    const words = try unicode.wordBoundaries(std.testing.allocator, "a", 1);
    defer std.testing.allocator.free(words);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, words);
    try std.testing.expectError(
        error.UnicodeScalarLimitExceeded,
        unicode.wordBoundaries(std.testing.allocator, "ab", 1),
    );
}

fn checkAllAllocationFailuresAndOnePast(comptime exercise: anytype) !usize {
    var counting = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try exercise(counting.allocator());
    const allocation_count = counting.alloc_index;
    try std.testing.expect(allocation_count > 0);
    try std.testing.expectEqual(counting.allocated_bytes, counting.freed_bytes);

    var one_past = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = allocation_count,
    });
    try exercise(one_past.allocator());
    try std.testing.expect(!one_past.has_induced_failure);
    try std.testing.expectEqual(allocation_count, one_past.alloc_index);
    try std.testing.expectEqual(one_past.allocated_bytes, one_past.freed_bytes);

    try std.testing.checkAllAllocationFailures(std.testing.allocator, exercise, .{});
    return allocation_count;
}

fn exerciseNormalizeNfd(allocator: std.mem.Allocator) anyerror!void {
    const output = try unicode.normalizeNfd(allocator, "Ắ", 64);
    defer allocator.free(output);
    try std.testing.expectEqualStrings("A\u{0306}\u{0301}", output);
}

fn exerciseFoldNfd(allocator: std.mem.Allocator) anyerror!void {
    const output = try unicode.foldNfd(allocator, "Straße", 64);
    defer allocator.free(output);
    try std.testing.expectEqualStrings("strasse", output);
}

fn exerciseDecodeScalars(allocator: std.mem.Allocator) anyerror!void {
    const output = try unicode.decodeScalars(allocator, "A", 1);
    defer allocator.free(output);
    try std.testing.expectEqualSlices(u21, &.{@as(u21, 'A')}, output);
}

fn exerciseGraphemeBoundaries(allocator: std.mem.Allocator) anyerror!void {
    const input = "👩‍🔬";
    const output = try unicode.graphemeBoundaries(allocator, input, 16);
    defer allocator.free(output);
    try std.testing.expectEqualSlices(usize, &.{ 0, input.len }, output);
}

fn exerciseWordBoundaries(allocator: std.mem.Allocator) anyerror!void {
    const input = "can't";
    const output = try unicode.wordBoundaries(allocator, input, 16);
    defer allocator.free(output);
    try std.testing.expectEqualSlices(usize, &.{ 0, input.len }, output);
}

test "Unicode runtime APIs release every allocation through and one past success" {
    const counts = [_]usize{
        try checkAllAllocationFailuresAndOnePast(exerciseNormalizeNfd),
        try checkAllAllocationFailuresAndOnePast(exerciseFoldNfd),
        try checkAllAllocationFailuresAndOnePast(exerciseDecodeScalars),
        try checkAllAllocationFailuresAndOnePast(exerciseGraphemeBoundaries),
        try checkAllAllocationFailuresAndOnePast(exerciseWordBoundaries),
    };
    try std.testing.expectEqualSlices(usize, &.{ 4, 6, 2, 4, 4 }, &counts);
}

test "all official Unicode 17 normalization vectors satisfy the NFD profile" {
    const bytes = try readUcd(
        "NormalizationTest.txt",
        2_827_429,
        "5019ffd530751a741900c849c0e010332f142a3612234639bd200b82138a87db",
    );
    defer std.testing.allocator.free(bytes);
    var vector_count: usize = 0;
    var line_number: usize = 0;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        line_number += 1;
        const line = contentBeforeComment(raw_line);
        if (line.len == 0 or line[0] == '@') continue;
        var columns: [5][]const u8 = undefined;
        var it = std.mem.splitScalar(u8, line, ';');
        for (&columns) |*column| {
            column.* = std.mem.trim(u8, it.next() orelse return error.InvalidNormalizationVector, " \t");
        }
        const source_1 = try sequenceToUtf8(columns[0]);
        defer std.testing.allocator.free(source_1);
        const source_2 = try sequenceToUtf8(columns[1]);
        defer std.testing.allocator.free(source_2);
        const nfd_1 = try sequenceToUtf8(columns[2]);
        defer std.testing.allocator.free(nfd_1);
        const source_4 = try sequenceToUtf8(columns[3]);
        defer std.testing.allocator.free(source_4);
        const nfd_2 = try sequenceToUtf8(columns[4]);
        defer std.testing.allocator.free(nfd_2);
        try expectNfd(line_number, source_1, nfd_1);
        try expectNfd(line_number, source_2, nfd_1);
        try expectNfd(line_number, nfd_1, nfd_1);
        try expectNfd(line_number, source_4, nfd_2);
        try expectNfd(line_number, nfd_2, nfd_2);
        vector_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 20_034), vector_count);
}

test "all official Unicode 17 grapheme vectors pass UAX 29 revision 47" {
    try runBreakConformance(
        "auxiliary/GraphemeBreakTest.txt",
        126_570,
        "e2d134d2c52919bace503ebb6a551c1855fe1a1faec18478c78fff254a1793ec",
        766,
        unicode.isGraphemeBoundary,
    );
}

test "all official Unicode 17 word vectors pass UAX 29 revision 47" {
    try runBreakConformance(
        "auxiliary/WordBreakTest.txt",
        322_136,
        "1de23a75f37904abc7d206239ee8d34f8fdf0fb4ab32a7174dfbabbde25419b2",
        1_944,
        unicode.isWordBoundary,
    );
}

fn readUcd(relative: []const u8, expected_size: usize, expected_sha256: []const u8) ![]u8 {
    const path = try std.fs.path.join(std.testing.allocator, &.{ ucd_root, relative });
    defer std.testing.allocator.free(path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        path,
        std.testing.allocator,
        .limited(expected_size + 1),
    );
    verifyUcdBytes(bytes, expected_size, expected_sha256) catch |err| {
        std.testing.allocator.free(bytes);
        return err;
    };
    return bytes;
}

fn verifyUcdBytes(bytes: []const u8, expected_size: usize, expected_sha256: []const u8) !void {
    if (bytes.len != expected_size) return error.UnicodeMemberSizeMismatch;
    try deps.verifySha256(bytes, expected_sha256);
}

test "Unicode member digest rejects a same-size byte change" {
    const original = "locked Unicode member";
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(original, &digest, .{});
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    var changed = original.*;
    changed[0] ^= 1;
    try std.testing.expectError(
        error.DigestMismatch,
        verifyUcdBytes(&changed, original.len, &digest_hex),
    );
}

fn contentBeforeComment(raw_line: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, raw_line, '#') orelse raw_line.len;
    return std.mem.trim(u8, raw_line[0..end], " \t\r");
}

fn sequenceToUtf8(sequence: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(std.testing.allocator);
    var codepoints = std.mem.tokenizeAny(u8, sequence, " \t");
    while (codepoints.next()) |raw_codepoint| {
        const codepoint = std.fmt.parseInt(u21, raw_codepoint, 16) catch
            return error.InvalidNormalizationVector;
        var encoded: [4]u8 = undefined;
        const length = std.unicode.utf8Encode(codepoint, &encoded) catch
            return error.InvalidNormalizationVector;
        try output.appendSlice(std.testing.allocator, encoded[0..length]);
    }
    return output.toOwnedSlice(std.testing.allocator);
}

fn expectNfd(line_number: usize, input: []const u8, expected: []const u8) !void {
    const actual = try unicode.normalizeNfd(std.testing.allocator, input, 4 * 1024);
    defer std.testing.allocator.free(actual);
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("normalization mismatch at official line {d}\n", .{line_number});
        return error.NormalizationConformanceMismatch;
    }
}

fn runBreakConformance(
    relative: []const u8,
    expected_size: usize,
    expected_sha256: []const u8,
    expected_vectors: usize,
    is_boundary: *const fn ([]const u21, usize) bool,
) !void {
    const bytes = try readUcd(relative, expected_size, expected_sha256);
    defer std.testing.allocator.free(bytes);
    var vector_count: usize = 0;
    var line_number: usize = 0;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        line_number += 1;
        const line = contentBeforeComment(raw_line);
        if (line.len == 0 or line[0] == '@') continue;
        var codepoints: std.ArrayList(u21) = .empty;
        defer codepoints.deinit(std.testing.allocator);
        var expected: std.ArrayList(bool) = .empty;
        defer expected.deinit(std.testing.allocator);
        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        var expect_marker = true;
        while (tokens.next()) |token| {
            if (expect_marker) {
                if (std.mem.eql(u8, token, "÷")) {
                    try expected.append(std.testing.allocator, true);
                } else if (std.mem.eql(u8, token, "×")) {
                    try expected.append(std.testing.allocator, false);
                } else return error.InvalidBreakVector;
            } else {
                try codepoints.append(
                    std.testing.allocator,
                    std.fmt.parseInt(u21, token, 16) catch return error.InvalidBreakVector,
                );
            }
            expect_marker = !expect_marker;
        }
        if (expect_marker or expected.items.len != codepoints.items.len + 1) {
            return error.InvalidBreakVector;
        }
        for (expected.items, 0..) |expected_boundary, index| {
            const actual = is_boundary(codepoints.items, index);
            if (actual != expected_boundary) {
                std.debug.print(
                    "break mismatch in {s} at official line {d}, boundary {d}: expected {}, got {}\n",
                    .{ relative, line_number, index, expected_boundary, actual },
                );
                return error.BreakConformanceMismatch;
            }
        }
        vector_count += 1;
    }
    try std.testing.expectEqual(expected_vectors, vector_count);
}
