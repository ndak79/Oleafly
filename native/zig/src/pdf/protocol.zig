//! Typed PDF protocol messages, tile geometry, and serialization.
//!
//! Tile transfer constraints:
//! - Decoded tile size: exactly 512x512 pixels
//! - Pixel format: opaque 32-bit BGRx (4 bytes/pixel)
//! - Stride: 512 * 4 = 2,048 bytes
//! - Tile byte size: exactly 1 MiB (1,048,576 bytes)
//! - Max document input size: 128 MiB
//! - Max live tile transfer sections: 4

const std = @import("std");

pub const tile_dim: u32 = 512;
pub const bytes_per_pixel: u32 = 4;
pub const tile_stride: u32 = tile_dim * bytes_per_pixel; // 2048 bytes
pub const tile_byte_size: usize = tile_stride * tile_dim; // 1,048,576 bytes (1 MiB)
pub const max_document_size: usize = 128 * 1024 * 1024; // 128 MiB
pub const max_tile_sections: usize = 4;

pub const ErrorCode = enum(u32) {
    none = 0,
    file_corrupt = 1,
    password_required = 2,
    page_out_of_range = 3,
    render_failed = 4,
    canceled = 5,
    out_of_memory = 6,
    unsupported_feature = 7,
};

pub const OpenDocRequest = extern struct {
    doc_id: u64,
    bytes_sha256: [32]u8,
    doc_bytes_len: u32,
};

pub const DocOpenedResponse = extern struct {
    doc_id: u64,
    page_count: u32,
    flags: u32,
};

pub const RenderTileRequest = extern struct {
    doc_id: u64,
    page_index: u32,
    slot: u32,
    generation: u64,
    dpi: f32,
    x_pt: f32,
    y_pt: f32,
    width_pt: f32,
    height_pt: f32,
};

pub const TileReadyResponse = extern struct {
    doc_id: u64,
    page_index: u32,
    slot: u32,
    generation: u64,
    stride: u32 = tile_stride,
    width_px: u32 = tile_dim,
    height_px: u32 = tile_dim,
    reserved: u32 = 0,
    tile_sha256: [32]u8,
};

pub const GetTextRequest = extern struct {
    doc_id: u64,
    page_index: u32,
    start_char: u32,
    count: u32,
};

pub const TextResultResponse = extern struct {
    doc_id: u64,
    page_index: u32,
    char_count: u32,
    text_len: u32,
};

pub const CancelRequest = extern struct {
    doc_id: u64,
    target_request_id: u64,
};

pub const ErrorResponse = extern struct {
    code: u32,
    doc_id: u64,
    desc_len: u8,
    desc: [63]u8,

    pub fn init(code: ErrorCode, doc_id: u64, message: []const u8) ErrorResponse {
        var r = ErrorResponse{
            .code = @intFromEnum(code),
            .doc_id = doc_id,
            .desc_len = 0,
            .desc = [_]u8{0} ** 63,
        };
        const copy_len = @min(message.len, 63);
        @memcpy(r.desc[0..copy_len], message[0..copy_len]);
        r.desc_len = @intCast(copy_len);
        return r;
    }

    pub fn getMessage(self: *const ErrorResponse) []const u8 {
        return self.desc[0..self.desc_len];
    }
};

comptime {
    std.debug.assert(@sizeOf(RenderTileRequest) == 48);
    std.debug.assert(@sizeOf(TileReadyResponse) == 72);
}
