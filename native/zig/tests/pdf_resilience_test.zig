//! Resilience tests for PDF open error handling, digest validation, and tile rendering.

const std = @import("std");
const worker_mod = @import("pdf_worker");
const protocol = @import("pdf_protocol");
const pdf_corpus = @import("pdf_corpus");

const testing = std.testing;
const alloc = testing.allocator;

test "worker handles open valid minimal PDF" {
    var worker = worker_mod.PdfWorker.init(alloc);
    defer worker.deinit();

    const resp = try worker.handleOpenDoc(
        1,
        pdf_corpus.valid_minimal_pdf,
        pdf_corpus.valid_pdf_sha256,
    );
    try testing.expectEqual(@as(u64, 1), resp.doc_id);
    try testing.expectEqual(@as(u32, 1), resp.page_count);
}

test "worker rejects open with corrupted digest" {
    var worker = worker_mod.PdfWorker.init(alloc);
    defer worker.deinit();

    const bogus_digest = [_]u8{0xFF} ** 32;
    try testing.expectError(
        error.DigestMismatch,
        worker.handleOpenDoc(1, pdf_corpus.valid_minimal_pdf, bogus_digest),
    );
}

test "worker renders tile with valid dimensions and produces digest" {
    var worker = worker_mod.PdfWorker.init(alloc);
    defer worker.deinit();

    _ = try worker.handleOpenDoc(
        1,
        pdf_corpus.valid_minimal_pdf,
        pdf_corpus.valid_pdf_sha256,
    );

    var pixel_buffer: [protocol.tile_byte_size]u8 = undefined;
    const req = protocol.RenderTileRequest{
        .doc_id = 1,
        .page_index = 0,
        .slot = 0,
        .generation = 1,
        .dpi = 150.0,
        .x_pt = 0.0,
        .y_pt = 0.0,
        .width_pt = 512.0,
        .height_pt = 512.0,
    };

    const tile_resp = try worker.handleRenderTile(req, &pixel_buffer);
    try testing.expectEqual(@as(u64, 1), tile_resp.doc_id);
    try testing.expectEqual(protocol.tile_dim, tile_resp.width_px);
    try testing.expectEqual(protocol.tile_dim, tile_resp.height_px);
    try testing.expectEqual(protocol.tile_stride, tile_resp.stride);
}
