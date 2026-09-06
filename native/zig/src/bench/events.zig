//! Strict parser for the fixed 64-byte render telemetry payload.
const std = @import("std");
const telemetry = @import("windows_telemetry");

pub const ParseError = error{
    InvalidPayloadLength,
    NonZeroReserved,
    InvalidRenderPath,
    InvalidAdapter,
    InvalidPayload,
};

pub fn parse(bytes: []const u8) ParseError!telemetry.Event {
    if (bytes.len != telemetry.encoded_size) return error.InvalidPayloadLength;
    if (bytes[41] != 0 or bytes[42] != 0 or bytes[43] != 0) return error.NonZeroReserved;
    const path: telemetry.RenderPath = switch (bytes[40]) {
        1 => .hardware,
        2 => .warp,
        3 => .flip_sequential,
        4 => .flip_discard,
        else => return error.InvalidRenderPath,
    };
    const adapter = std.mem.readInt(u64, bytes[32..40], .little);
    if (adapter == 0) return error.InvalidAdapter;
    var trial_id: [16]u8 = undefined;
    @memcpy(&trial_id, bytes[0..16]);
    const event: telemetry.Event = .{
        .trial_id = trial_id,
        .process_id = std.mem.readInt(u32, bytes[16..20], .little),
        .thread_id = std.mem.readInt(u32, bytes[20..24], .little),
        .qpc = std.mem.readInt(u64, bytes[24..32], .little),
        .adapter_luid = adapter,
        .render_path = path,
        .width = std.mem.readInt(u32, bytes[44..48], .little),
        .height = std.mem.readInt(u32, bytes[48..52], .little),
        .dirty_pixels = std.mem.readInt(u64, bytes[52..60], .little),
        .version = std.mem.readInt(u32, bytes[60..64], .little),
    };
    event.validate() catch return error.InvalidPayload;
    return event;
}
