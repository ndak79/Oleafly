//! Tests for PDF tile dimensions, strides, byte budgets, and request encoding.

const std = @import("std");
const protocol = @import("pdf_protocol");

const testing = std.testing;

test "tile constants match 1 MiB 512x512 BGRx contract" {
    try testing.expectEqual(@as(u32, 512), protocol.tile_dim);
    try testing.expectEqual(@as(u32, 4), protocol.bytes_per_pixel);
    try testing.expectEqual(@as(u32, 2048), protocol.tile_stride);
    try testing.expectEqual(@as(usize, 1024 * 1024), protocol.tile_byte_size);
    try testing.expectEqual(@as(usize, 128 * 1024 * 1024), protocol.max_document_size);
    try testing.expectEqual(@as(usize, 4), protocol.max_tile_sections);
}

test "error response serialization and message retrieval" {
    const msg = "page index 99 out of range";
    const err_resp = protocol.ErrorResponse.init(.page_out_of_range, 12345, msg);

    try testing.expectEqual(@intFromEnum(protocol.ErrorCode.page_out_of_range), err_resp.code);
    try testing.expectEqual(@as(u64, 12345), err_resp.doc_id);
    try testing.expectEqualStrings(msg, err_resp.getMessage());
}

test "render tile request struct layout assertions" {
    const req = protocol.RenderTileRequest{
        .doc_id = 1,
        .page_index = 0,
        .slot = 2,
        .generation = 10,
        .dpi = 150.0,
        .x_pt = 0.0,
        .y_pt = 0.0,
        .width_pt = 512.0,
        .height_pt = 512.0,
    };
    try testing.expectEqual(@as(u32, 2), req.slot);
    try testing.expectEqual(@as(u64, 10), req.generation);
}
