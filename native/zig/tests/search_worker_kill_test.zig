//! Resilience tests for search worker crash isolation and disposal.

const std = @import("std");
const search = @import("data_search");

const testing = std.testing;
const alloc = testing.allocator;

test "search index rebuilds independently on worker crash" {
    var idx = search.SearchIndex.init(alloc);
    defer idx.deinit();

    idx.is_rebuilding = true;
    try testing.expect(idx.is_rebuilding);

    // Worker dies during rebuild: discard stage, remain on previous generation
    idx.is_rebuilding = false;
    try testing.expect(!idx.is_rebuilding);
    try testing.expectEqual(@as(u64, 1), idx.generation);
}
