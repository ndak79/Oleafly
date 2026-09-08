//! Tests for the search view model, candidate row capping, and user notices.

const std = @import("std");
const search_view = @import("app_search_view");

const testing = std.testing;
const alloc = testing.allocator;

test "search notices match contract text exactly" {
    try testing.expect(std.mem.indexOf(u8, search_view.Notices.results_notice, "100 candidates") != null);
    try testing.expect(std.mem.indexOf(u8, search_view.Notices.empty, "not evidence of absence") != null);
    try testing.expectEqualStrings("Search index rebuilding", search_view.Notices.rebuilding);
    try testing.expectEqualStrings("Search index unavailable", search_view.Notices.unavailable);
}

test "search view enforces 100 results cap" {
    var view = search_view.SearchView.init(alloc);
    defer view.deinit();

    var i: usize = 0;
    while (i < 120) : (i += 1) {
        try view.addRow(
            [_]u8{@intCast(i % 256)} ** 16,
            "Sample Title",
            "Sample Snippet",
            1.5,
            null,
        );
    }

    // Must not exceed 100 display rows
    try testing.expectEqual(@as(usize, 100), view.rows.items.len);
}
