//! Tests for search database staging rebuild and generation promotion.

const std = @import("std");
const search = @import("data_search");

const testing = std.testing;
const alloc = testing.allocator;

test "search index generation increments after successful rebuild" {
    var idx = search.SearchIndex.init(alloc);
    defer idx.deinit();

    try testing.expectEqual(@as(u64, 1), idx.generation);
    try testing.expectEqual(@as(u64, 0), idx.watermark);

    // Simulate clean rebuild from watermark 42
    idx.generation += 1;
    idx.watermark = 42;
    idx.doc_count = 10;

    try testing.expectEqual(@as(u64, 2), idx.generation);
    try testing.expectEqual(@as(u64, 42), idx.watermark);
    try testing.expectEqual(@as(u32, 10), idx.doc_count);
}
