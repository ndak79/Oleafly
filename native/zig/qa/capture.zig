//! Capture-lane orchestration for T0.2c.
//!
//! A Harness must be armed before the caller records a mutation marker.  It
//! delegates pixels to DXGI Desktop Duplication and delegates PNG output to
//! WIC; this module only applies recorded physical-coordinate cropping and
//! digest bookkeeping.

const std = @import("std");
const contract = @import("capture_contract");
const dxgi = @import("capture_dxgi.zig");
const wic = @import("capture_wic.zig");

pub const Error = dxgi.Error || wic.Error || error{
    InvalidRequest,
    InvalidCrop,
    CropOutsideOutput,
    RotationUnverified,
    GenerationMismatch,
    CapabilityUnverified,
};

/// `crop` is an absolute desktop-physical rectangle, not a logical/DIP
/// rectangle.  The output bounds used to localize it come from DXGI.
pub const Request = struct {
    crop: contract.Rect,
    dpi: u16,
    marker_qpc: u64,
    deadline_qpc: u64,
    expected_generation: u64 = 1,
};

pub const Artifact = struct {
    allocator: std.mem.Allocator,
    metadata: contract.FrameMetadata,
    output: dxgi.OutputInfo,
    crop_layout: contract.PixelLayout,
    crop_pixels: []u8,
    png_bytes: []u8,
    full_output_digest: [32]u8,
    crop_digest: [32]u8,
    encoded_digest: [32]u8,
    generation: u64,

    pub fn deinit(self: *Artifact) void {
        self.allocator.free(self.crop_pixels);
        self.allocator.free(self.png_bytes);
        self.* = undefined;
    }
};

pub const Harness = struct {
    session: dxgi.Session,

    /// Opening the duplication session is the arming step.  Call it before
    /// any mutation marker is recorded.
    pub fn arm(allocator: std.mem.Allocator, output_index: u32) Error!Harness {
        return .{ .session = try dxgi.Session.open(allocator, output_index) };
    }

    pub fn deinit(self: *Harness) void {
        self.session.deinit();
    }

    pub fn outputInfo(self: *const Harness) dxgi.OutputInfo {
        return self.session.outputInfo();
    }

    pub fn generation(self: *const Harness) u64 {
        return self.session.generation;
    }

    pub fn recreate(self: *Harness) Error!void {
        try self.session.recreate();
    }

    pub fn captureAfter(self: *Harness, request: Request) Error!Artifact {
        try validateRequest(request);
        if (request.expected_generation == 0 or request.expected_generation != self.session.generation) {
            return error.GenerationMismatch;
        }

        var frame = try self.session.acquireAfter(.{
            .marker_qpc = request.marker_qpc,
            .deadline_qpc = request.deadline_qpc,
            .dpi = request.dpi,
        });
        defer frame.deinit();
        if (frame.generation != request.expected_generation) return error.GenerationMismatch;
        if (frame.metadata.rotation != 0) return error.RotationUnverified;

        const local_crop = try localizeCrop(request.crop, frame.output.desktop_bounds);
        contract.validate_crop(frame.metadata.layout, frame.metadata.rotation, local_crop, .physical) catch {
            return error.CropOutsideOutput;
        };

        const crop_width: u32 = @intCast(local_crop.right - local_crop.left);
        const crop_height: u32 = @intCast(local_crop.bottom - local_crop.top);
        const crop_stride = std.math.mul(u32, crop_width, 4) catch return error.InvalidCrop;
        const crop_layout = contract.PixelLayout{
            .width = crop_width,
            .height = crop_height,
            .stride = crop_stride,
            .channel_order = .bgra8,
        };
        const crop_bytes = crop_layout.byte_length() catch return error.InvalidCrop;
        const crop_pixels = try self.session.allocator.alloc(u8, crop_bytes);
        errdefer self.session.allocator.free(crop_pixels);
        const row_bytes = crop_layout.row_bytes() catch return error.InvalidCrop;
        for (0..crop_height) |row| {
            const row_index: usize = @intCast(row);
            const source_start = (@as(usize, @intCast(local_crop.top)) + row_index) *
                @as(usize, @intCast(frame.metadata.layout.stride)) +
                @as(usize, @intCast(local_crop.left)) * 4;
            const source = frame.pixels[source_start..][0..row_bytes];
            const destination = crop_pixels[row_index * @as(usize, @intCast(crop_layout.stride)) ..][0..row_bytes];
            @memcpy(destination, source);
        }

        var metadata = frame.metadata;
        metadata.crop = local_crop;
        metadata.crop_space = .physical;
        contract.validate_metadata(metadata) catch return error.CapabilityUnverified;

        const png = try wic.encodeRoundTrip(self.session.allocator, crop_layout, crop_pixels);
        return .{
            .allocator = self.session.allocator,
            .metadata = metadata,
            .output = frame.output,
            .crop_layout = crop_layout,
            .crop_pixels = crop_pixels,
            .png_bytes = png.bytes,
            .full_output_digest = contract.raw_digest(frame.pixels),
            .crop_digest = contract.raw_digest(crop_pixels),
            .encoded_digest = png.encoded_digest,
            .generation = frame.generation,
        };
    }
};

pub fn validateRequest(request: Request) Error!void {
    if (request.marker_qpc == 0 or request.deadline_qpc == 0 or request.marker_qpc >= request.deadline_qpc) {
        return error.InvalidRequest;
    }
    if (request.expected_generation == 0) return error.InvalidRequest;
    if (request.crop.right <= request.crop.left or request.crop.bottom <= request.crop.top) {
        return error.InvalidCrop;
    }
    _ = contract.dip_to_physical(1, request.dpi) catch return error.InvalidDpi;
}

fn localizeCrop(crop: contract.Rect, bounds: contract.Rect) Error!contract.Rect {
    const left = @as(i64, crop.left) - @as(i64, bounds.left);
    const top = @as(i64, crop.top) - @as(i64, bounds.top);
    const right = @as(i64, crop.right) - @as(i64, bounds.left);
    const bottom = @as(i64, crop.bottom) - @as(i64, bounds.top);
    return .{
        .left = std.math.cast(i32, left) orelse return error.InvalidCrop,
        .top = std.math.cast(i32, top) orelse return error.InvalidCrop,
        .right = std.math.cast(i32, right) orelse return error.InvalidCrop,
        .bottom = std.math.cast(i32, bottom) orelse return error.InvalidCrop,
    };
}

test "portable capture request validation is fail-closed" {
    const request = Request{
        .crop = .{ .left = 0, .top = 0, .right = 4, .bottom = 4 },
        .dpi = 96,
        .marker_qpc = 1,
        .deadline_qpc = 2,
    };
    try validateRequest(request);
}
