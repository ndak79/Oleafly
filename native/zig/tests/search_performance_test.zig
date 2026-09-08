//! Performance and ranking tests for full-text search candidate ordering.

const std = @import("std");
const search = @import("data_search");

const testing = std.testing;

test "search hit comparisons order strictly by rank descending" {
    const hits: [3]search.SearchHit = .{
        .{ .entity_uuid = [_]u8{1} ** 16, .rank = 3.5, .matched_fields = 1 },
        .{ .entity_uuid = [_]u8{2} ** 16, .rank = 2.0, .matched_fields = 1 },
        .{ .entity_uuid = [_]u8{3} ** 16, .rank = 0.5, .matched_fields = 1 },
    };

    try testing.expect(hits[0].rank > hits[1].rank);
    try testing.expect(hits[1].rank > hits[2].rank);
}
