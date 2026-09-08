//! Contract tests for accessible PDF document and page tree representation.

const std = @import("std");
const uia = @import("pdf_uia");

const testing = std.testing;
const alloc = testing.allocator;

test "accessible document initialization and page retrieval" {
    const doc = try uia.AccessibleDocument.init(alloc, 101, 5);
    defer doc.deinit();

    try testing.expectEqual(@as(u64, 101), doc.doc_id);
    try testing.expectEqual(@as(u32, 5), doc.page_count);

    const p0 = doc.getPage(0).?;
    try testing.expectEqual(@as(u32, 0), p0.page_index);
    try testing.expectEqual(@as(f32, 612.0), p0.width_pt);
    try testing.expectEqual(@as(f32, 792.0), p0.height_pt);

    // Out of range page returns null
    try testing.expect(doc.getPage(5) == null);
}

test "accessible page bounds and text runs" {
    const doc = try uia.AccessibleDocument.init(alloc, 102, 1);
    defer doc.deinit();

    const p = doc.getPage(0).?;
    try testing.expectEqual(@as(usize, 0), p.text_runs.len);
    try testing.expectEqual(@as(usize, 0), p.links.len);
}
