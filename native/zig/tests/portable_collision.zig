const std = @import("std");

/// Hermetic collision fold for archive-parser tests. It intentionally covers
/// only the independent hand-written vectors in archive_security_test; the
/// complete Unicode 17 implementation and corpus remain gated by
/// `zig build unicode-audit`.
pub fn foldNfd(
    allocator: std.mem.Allocator,
    input: []const u8,
    max_output_bytes: usize,
) ![]u8 {
    if (!std.unicode.utf8ValidateSlice(input)) return error.InvalidUtf8;
    var normalized: std.ArrayList(u21) = .empty;
    errdefer normalized.deinit(allocator);
    var view = std.unicode.Utf8View.initUnchecked(input);
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |codepoint| {
        if (codepoint == 0x00e9) {
            try appendScalar(allocator, &normalized, 'e', max_output_bytes);
            try appendScalar(allocator, &normalized, 0x0301, max_output_bytes);
        } else {
            try appendScalar(allocator, &normalized, codepoint, max_output_bytes);
        }
    }
    // Match the ownership boundary in production normalizeNfd: allocation
    // campaigns must exercise the shrink/ownership transfer as well as the
    // working list growth.
    const normalized_owned = try normalized.toOwnedSlice(allocator);
    defer allocator.free(normalized_owned);

    var folded: std.ArrayList(u21) = .empty;
    defer folded.deinit(allocator);
    for (normalized_owned) |codepoint| switch (codepoint) {
        0x00df => {
            try appendScalar(allocator, &folded, 's', max_output_bytes);
            try appendScalar(allocator, &folded, 's', max_output_bytes);
        },
        0x212a => try appendScalar(allocator, &folded, 'k', max_output_bytes),
        else => try appendScalar(
            allocator,
            &folded,
            if (codepoint <= 0x7f) std.ascii.toLower(@intCast(codepoint)) else codepoint,
            max_output_bytes,
        ),
    };

    var renormalized: std.ArrayList(u21) = .empty;
    defer renormalized.deinit(allocator);
    try renormalized.appendSlice(allocator, folded.items);
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    for (renormalized.items) |codepoint| {
        var encoded: [4]u8 = undefined;
        const length = std.unicode.utf8Encode(codepoint, &encoded) catch
            return error.InvalidScalar;
        if (length > max_output_bytes -| output.items.len) {
            return error.UnicodeOutputLimitExceeded;
        }
        try output.appendSlice(allocator, encoded[0..length]);
    }
    return output.toOwnedSlice(allocator);
}

fn appendScalar(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u21),
    codepoint: u21,
    max_output_bytes: usize,
) !void {
    if (output.items.len >= max_output_bytes) return error.UnicodeOutputLimitExceeded;
    try output.append(allocator, codepoint);
}

test "portable archive fold covers every hermetic collision vector" {
    const cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "Paper.TXT", .expected = "paper.txt" },
        .{ .input = "caf\u{00e9}", .expected = "cafe\u{0301}" },
        .{ .input = "Stra\u{00df}e", .expected = "strasse" },
        .{ .input = "\u{212a}elvin", .expected = "kelvin" },
    };
    for (cases) |case| {
        const actual = try foldNfd(std.testing.allocator, case.input, 64);
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualStrings(case.expected, actual);
    }
}
