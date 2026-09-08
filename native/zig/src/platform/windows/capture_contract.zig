//! Pure capture-contract fixtures for the native Windows QA lane.
//!
//! This module deliberately owns no DXGI, DWM, WIC, HWND, or process handles.
//! It validates the data boundary that a future Desktop Duplication adapter
//! must satisfy, so malformed frames fail before any pixel is treated as
//! authoritative visible output.

const std = @import("std");

pub const Error = error{
    InvalidDimensions,
    InvalidStride,
    InvalidChannelOrder,
    InvalidPixelBytes,
    InvalidRotation,
    InvalidCrop,
    CropOutOfBounds,
    VirtualizedCrop,
    InvalidDpi,
    MissingFrame,
    InvalidDeadline,
    AccessLost,
    StaleGeneration,
    RecreationNotRequired,
    InvalidFixture,
    DigestMismatch,
    InvalidStatus,
    InvalidMetadata,
};

pub const ChannelOrder = enum { bgra8, rgba8 };
pub const CropSpace = enum { physical, logical };
pub const Extent = struct { width: u32, height: u32 };
pub const Rect = struct { left: i32, top: i32, right: i32, bottom: i32 };

pub const PixelLayout = struct {
    width: u32,
    height: u32,
    stride: u32,
    channel_order: ChannelOrder,

    pub fn row_bytes(self: PixelLayout) Error!u32 {
        if (self.width == 0 or self.height == 0) return error.InvalidDimensions;
        if (self.channel_order != .bgra8) return error.InvalidChannelOrder;
        const bytes = std.math.mul(u32, self.width, 4) catch return error.InvalidStride;
        if (self.stride < bytes or self.stride % 4 != 0) return error.InvalidStride;
        return bytes;
    }

    pub fn validate(self: PixelLayout) Error!void {
        _ = try self.row_bytes();
        _ = std.math.mul(usize, self.stride, self.height) catch return error.InvalidStride;
    }

    pub fn byte_length(self: PixelLayout) Error!usize {
        try self.validate();
        return std.math.mul(usize, self.stride, self.height) catch error.InvalidStride;
    }
};

pub const FrameMetadata = struct {
    layout: PixelLayout,
    rotation: u16,
    crop: Rect,
    crop_space: CropSpace,
    dpi: u16,
    last_present_qpc: u64,
    accumulated_frames: u32,
    protected_content: bool,
};

pub fn rotated_extent(layout: PixelLayout, rotation: u16) Error!Extent {
    try layout.validate();
    return switch (rotation) {
        0, 180 => .{ .width = layout.width, .height = layout.height },
        90, 270 => .{ .width = layout.height, .height = layout.width },
        else => error.InvalidRotation,
    };
}

pub fn validate_crop(layout: PixelLayout, rotation: u16, crop: Rect, space: CropSpace) Error!void {
    if (space == .logical) return error.VirtualizedCrop;
    const extent = try rotated_extent(layout, rotation);
    if (crop.left < 0 or crop.top < 0 or crop.right <= crop.left or crop.bottom <= crop.top) return error.InvalidCrop;
    if (@as(u64, @intCast(crop.right)) > extent.width or @as(u64, @intCast(crop.bottom)) > extent.height) {
        return error.CropOutOfBounds;
    }
}

pub fn dip_to_physical(dip: u32, dpi: u16) Error!u32 {
    switch (dpi) {
        96, 120, 144, 192 => {},
        else => return error.InvalidDpi,
    }
    const scaled = std.math.mul(u64, dip, dpi) catch return error.InvalidDpi;
    const rounded = std.math.add(u64, scaled, 48) catch return error.InvalidDpi;
    return std.math.cast(u32, rounded / 96) orelse error.InvalidDpi;
}

pub fn validate_metadata(metadata: FrameMetadata) Error!void {
    try metadata.layout.validate();
    if (metadata.last_present_qpc == 0) return error.InvalidMetadata;
    _ = try rotated_extent(metadata.layout, metadata.rotation);
    try validate_crop(metadata.layout, metadata.rotation, metadata.crop, metadata.crop_space);
    _ = try dip_to_physical(1, metadata.dpi);
}

pub fn validate_pixels(layout: PixelLayout, pixels: []const u8) Error!void {
    const expected = try layout.byte_length();
    if (pixels.len != expected) return error.InvalidPixelBytes;
}

pub fn known_pixel(x: u32, y: u32) [4]u8 {
    return .{
        @truncate(17 *% (x +% 1)),
        @truncate(53 *% (y +% 1) +% 1),
        @truncate(37 +% 71 *% x +% 72 *% y),
        255,
    };
}

pub fn make_known_pixels(allocator: std.mem.Allocator, layout: PixelLayout) ![]u8 {
    try layout.validate();
    const pixels = try allocator.alloc(u8, try layout.byte_length());
    errdefer allocator.free(pixels);
    @memset(pixels, 0xcd);
    for (0..layout.height) |y| {
        const row = pixels[y * layout.stride ..][0..layout.stride];
        for (0..layout.width) |x| {
            const value = known_pixel(@intCast(x), @intCast(y));
            const offset = x * 4;
            @memcpy(row[offset .. offset + 4], &value);
        }
    }
    return pixels;
}

pub fn raw_digest(pixels: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(pixels, &digest, .{});
    return digest;
}

const fixture_magic = "TExFlowCaptureFixture\x00";

fn append_int(list: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime T: type, value: T) !void {
    var buffer: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &buffer, value, .little);
    try list.appendSlice(allocator, buffer[0..]);
}

fn read_int(comptime T: type, bytes: []const u8, cursor: *usize) Error!T {
    if (bytes.len -| cursor.* < @sizeOf(T)) return error.InvalidFixture;
    const value = std.mem.readInt(T, bytes[cursor.*..][0..@sizeOf(T)], .little);
    cursor.* += @sizeOf(T);
    return value;
}

fn append_bytes(list: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: []const u8) !void {
    try list.appendSlice(allocator, bytes);
}

pub fn encode_fixture(allocator: std.mem.Allocator, metadata: FrameMetadata, pixels: []const u8) ![]u8 {
    try validate_metadata(metadata);
    try validate_pixels(metadata.layout, pixels);
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try append_bytes(&list, allocator, fixture_magic);
    try append_int(&list, allocator, u32, metadata.layout.width);
    try append_int(&list, allocator, u32, metadata.layout.height);
    try append_int(&list, allocator, u32, metadata.layout.stride);
    try append_int(&list, allocator, u8, @intFromEnum(metadata.layout.channel_order));
    try append_int(&list, allocator, u16, metadata.rotation);
    try append_int(&list, allocator, i32, metadata.crop.left);
    try append_int(&list, allocator, i32, metadata.crop.top);
    try append_int(&list, allocator, i32, metadata.crop.right);
    try append_int(&list, allocator, i32, metadata.crop.bottom);
    try append_int(&list, allocator, u8, @intFromEnum(metadata.crop_space));
    try append_int(&list, allocator, u16, metadata.dpi);
    try append_int(&list, allocator, u64, metadata.last_present_qpc);
    try append_int(&list, allocator, u32, metadata.accumulated_frames);
    try append_int(&list, allocator, u8, @intFromBool(metadata.protected_content));
    try append_int(&list, allocator, u64, pixels.len);
    try append_bytes(&list, allocator, pixels);
    const pixels_digest = raw_digest(pixels);
    try append_bytes(&list, allocator, &pixels_digest);
    var envelope: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(list.items, &envelope, .{});
    try append_bytes(&list, allocator, &envelope);
    return list.toOwnedSlice(allocator);
}

pub const DecodedFixture = struct {
    allocator: std.mem.Allocator,
    metadata: FrameMetadata,
    pixels: []u8,
    raw_digest: [32]u8,

    pub fn deinit(self: *DecodedFixture) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }
};

pub fn decode_fixture(allocator: std.mem.Allocator, bytes: []const u8) !DecodedFixture {
    const minimum = fixture_magic.len + 4 + 4 + 4 + 1 + 2 + 16 + 1 + 2 + 8 + 4 + 1 + 8 + 32 + 32;
    if (bytes.len < minimum) return error.InvalidFixture;
    if (!std.mem.eql(u8, bytes[0..fixture_magic.len], fixture_magic)) return error.InvalidFixture;

    var cursor: usize = fixture_magic.len;
    const width = try read_int(u32, bytes, &cursor);
    const height = try read_int(u32, bytes, &cursor);
    const stride = try read_int(u32, bytes, &cursor);
    const channel_value = try read_int(u8, bytes, &cursor);
    const rotation = try read_int(u16, bytes, &cursor);
    const crop = Rect{
        .left = try read_int(i32, bytes, &cursor),
        .top = try read_int(i32, bytes, &cursor),
        .right = try read_int(i32, bytes, &cursor),
        .bottom = try read_int(i32, bytes, &cursor),
    };
    const crop_space_value = try read_int(u8, bytes, &cursor);
    const dpi = try read_int(u16, bytes, &cursor);
    const qpc = try read_int(u64, bytes, &cursor);
    const accumulated = try read_int(u32, bytes, &cursor);
    const protected_value = try read_int(u8, bytes, &cursor);
    const pixel_len = try read_int(u64, bytes, &cursor);
    const channel_order: ChannelOrder = switch (channel_value) {
        0 => .bgra8,
        1 => .rgba8,
        else => return error.InvalidFixture,
    };
    const crop_space: CropSpace = switch (crop_space_value) {
        0 => .physical,
        1 => .logical,
        else => return error.InvalidFixture,
    };
    if (protected_value > 1) return error.InvalidFixture;
    const layout = PixelLayout{ .width = width, .height = height, .stride = stride, .channel_order = channel_order };
    const metadata = FrameMetadata{
        .layout = layout,
        .rotation = rotation,
        .crop = crop,
        .crop_space = crop_space,
        .dpi = dpi,
        .last_present_qpc = qpc,
        .accumulated_frames = accumulated,
        .protected_content = protected_value != 0,
    };
    const pixel_len_usize = std.math.cast(usize, pixel_len) orelse return error.InvalidFixture;
    const payload_end = std.math.add(usize, cursor, pixel_len_usize) catch return error.InvalidFixture;
    const expected_end = std.math.add(usize, payload_end, 32 + 32) catch return error.InvalidFixture;
    if (expected_end != bytes.len) return error.InvalidFixture;
    const envelope_start = bytes.len - 32;
    var expected_envelope: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes[0..envelope_start], &expected_envelope, .{});
    if (!std.mem.eql(u8, &expected_envelope, bytes[envelope_start..])) return error.DigestMismatch;
    try validate_metadata(metadata);
    if (pixel_len_usize != try layout.byte_length()) return error.InvalidFixture;
    const pixels = try allocator.dupe(u8, bytes[cursor .. cursor + pixel_len_usize]);
    errdefer allocator.free(pixels);
    cursor += pixel_len_usize;
    var stored_raw: [32]u8 = undefined;
    @memcpy(&stored_raw, bytes[cursor .. cursor + 32]);
    const computed_raw = raw_digest(pixels);
    if (!std.mem.eql(u8, &stored_raw, &computed_raw)) return error.DigestMismatch;
    return .{ .allocator = allocator, .metadata = metadata, .pixels = pixels, .raw_digest = stored_raw };
}

pub fn encoded_digest(bytes: []const u8) [32]u8 {
    return raw_digest(bytes);
}

pub const AcquireStatus = enum { acquired, cancelled, access_lost, timeout };
pub const CaptureAttempt = struct {
    status: AcquireStatus,
    frame: ?FrameMetadata = null,
    observed_qpc: ?u64 = null,
    deadline_qpc: ?u64 = null,
    duplication_generation: ?u64 = null,
};

pub const StaleQpc = struct { frame_qpc: u64, marker_qpc: u64 };
pub const Timeout = struct { deadline_qpc: u64, observed_qpc: u64 };
pub const Ready = struct { remaining_qpc: u64 };
pub const CaptureOutcome = union(enum) {
    accepted,
    stale_qpc: StaleQpc,
    accumulated_frames: u32,
    protected_content,
    cancelled,
    timeout: Timeout,
    access_lost,
};

pub fn classify(attempt: CaptureAttempt, marker_qpc: u64, expected_generation: u64) Error!CaptureOutcome {
    if (expected_generation == 0) return error.InvalidStatus;
    return switch (attempt.status) {
        .cancelled => .cancelled,
        .access_lost => .access_lost,
        .timeout => blk: {
            const deadline_qpc = attempt.deadline_qpc orelse return error.InvalidDeadline;
            const observed_qpc = attempt.observed_qpc orelse return error.InvalidDeadline;
            if (deadline_qpc == 0 or observed_qpc == 0 or observed_qpc < deadline_qpc) return error.InvalidDeadline;
            break :blk .{ .timeout = .{ .deadline_qpc = deadline_qpc, .observed_qpc = observed_qpc } };
        },
        .acquired => blk: {
            const deadline_qpc = attempt.deadline_qpc orelse return error.InvalidDeadline;
            const observed_qpc = attempt.observed_qpc orelse return error.InvalidDeadline;
            if (deadline_qpc == 0 or observed_qpc == 0 or observed_qpc >= deadline_qpc) return error.InvalidDeadline;
            if (marker_qpc == 0) return error.InvalidMetadata;
            const frame = attempt.frame orelse return error.MissingFrame;
            const generation = attempt.duplication_generation orelse return error.StaleGeneration;
            if (generation != expected_generation) return error.StaleGeneration;
            try validate_metadata(frame);
            if (frame.last_present_qpc <= marker_qpc) break :blk .{ .stale_qpc = .{ .frame_qpc = frame.last_present_qpc, .marker_qpc = marker_qpc } };
            // DXGI reports one accumulated frame for a normal desktop update. Only
            // a backlog greater than one means the capture missed intermediate frames.
            if (frame.accumulated_frames > 1) break :blk .{ .accumulated_frames = frame.accumulated_frames };
            if (frame.protected_content) break :blk .protected_content;
            break :blk .accepted;
        },
    };
}

pub const WaitOutcome = union(enum) { ready: Ready, timeout: Timeout };

pub fn finite_wait(observed_qpc: u64, deadline_qpc: u64) Error!WaitOutcome {
    if (deadline_qpc == 0 or observed_qpc == 0 or observed_qpc > deadline_qpc) return error.InvalidDeadline;
    if (observed_qpc == deadline_qpc) return .{ .timeout = .{ .deadline_qpc = deadline_qpc, .observed_qpc = observed_qpc } };
    return .{ .ready = .{ .remaining_qpc = deadline_qpc - observed_qpc } };
}

pub const DuplicationSession = struct {
    generation: u64 = 1,
    needs_recreation: bool = false,

    pub fn init() DuplicationSession {
        return .{};
    }

    pub fn mark_access_lost(self: *DuplicationSession) void {
        self.needs_recreation = true;
    }

    pub fn require_generation(self: *const DuplicationSession, generation: u64) Error!void {
        if (self.needs_recreation) return error.AccessLost;
        if (generation != self.generation) return error.StaleGeneration;
    }

    pub fn recreate_after_access_loss(self: *DuplicationSession) Error!u64 {
        if (!self.needs_recreation) return error.RecreationNotRequired;
        self.generation = std.math.add(u64, self.generation, 1) catch return error.InvalidStatus;
        self.needs_recreation = false;
        return self.generation;
    }
};
