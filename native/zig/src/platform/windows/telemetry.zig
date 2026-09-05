//! Fixed-schema render telemetry. No source text, paths, secrets, or paper
//! contents are representable in this payload.
const std = @import("std");

pub const encoded_size: usize = 64;

pub const RenderPath = enum(u8) {
    hardware = 1,
    warp = 2,
    flip_sequential = 3,
    flip_discard = 4,
};

pub const Event = struct {
    trial_id: [16]u8,
    process_id: u32,
    thread_id: u32,
    qpc: u64,
    adapter_luid: u64,
    render_path: RenderPath,
    width: u32,
    height: u32,
    dirty_pixels: u64,
    version: u32,

    pub fn validate(self: Event) !void {
        var nonzero = false;
        for (self.trial_id) |byte| nonzero = nonzero or byte != 0;
        if (!nonzero) return error.EmptyTrialId;
        if (self.process_id == 0 or self.thread_id == 0) return error.InvalidOwner;
        if (self.qpc == 0 or self.version == 0) return error.InvalidClockOrVersion;
        if (self.width == 0 or self.height == 0) return error.InvalidDimensions;
        const pixels = std.math.mul(u64, self.width, self.height) catch return error.InvalidDimensions;
        if (self.dirty_pixels > pixels) return error.InvalidDirtyPixels;
    }

    pub fn encode(self: Event) ![encoded_size]u8 {
        try self.validate();
        var output = [_]u8{0} ** encoded_size;
        var offset: usize = 0;
        @memcpy(output[offset .. offset + 16], &self.trial_id);
        offset += 16;
        std.mem.writeInt(u32, output[offset..][0..4], self.process_id, .little);
        offset += 4;
        std.mem.writeInt(u32, output[offset..][0..4], self.thread_id, .little);
        offset += 4;
        std.mem.writeInt(u64, output[offset..][0..8], self.qpc, .little);
        offset += 8;
        std.mem.writeInt(u64, output[offset..][0..8], self.adapter_luid, .little);
        offset += 8;
        output[offset] = @intFromEnum(self.render_path);
        offset += 1;
        offset += 3;
        std.mem.writeInt(u32, output[offset..][0..4], self.width, .little);
        offset += 4;
        std.mem.writeInt(u32, output[offset..][0..4], self.height, .little);
        offset += 4;
        std.mem.writeInt(u64, output[offset..][0..8], self.dirty_pixels, .little);
        offset += 8;
        std.mem.writeInt(u32, output[offset..][0..4], self.version, .little);
        return output;
    }
};

pub fn parseTrialId(text: []const u8) ![16]u8 {
    if (text.len != 32) return error.InvalidTrialId;
    var result: [16]u8 = undefined;
    for (0..16) |index| {
        const high = hexNibble(text[index * 2]) orelse return error.InvalidTrialId;
        const low = hexNibble(text[index * 2 + 1]) orelse return error.InvalidTrialId;
        result[index] = (high << 4) | low;
    }
    return result;
}

fn hexNibble(value: u8) ?u8 {
    return switch (value) {
        '0'...'9' => value - '0',
        'a'...'f' => value - 'a' + 10,
        else => null,
    };
}
