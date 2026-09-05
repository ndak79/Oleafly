//! Canonical TExFlow source-to-evidence mark.
//!
//! The geometry is intentionally tiny and data-oriented: one source defines
//! the reviewable SVG and the software-rasterized ICO.  The rasterizer is
//! build-time/test-only output; the UI never allocates or paints from it.
const std = @import("std");

pub const sizes = [_]u16{ 16, 24, 32, 48, 256 };

pub const Point = struct {
    x: u16,
    y: u16,
};

pub const Segment = struct {
    from: Point,
    to: Point,
};

// Coordinates are in a 0..1024 fixed-point canvas.  These arrays are the
// single geometry source for both SVG and ICO output.
pub const paper_segments = [_]Segment{
    .{ .from = .{ .x = 286, .y = 180 }, .to = .{ .x = 740, .y = 180 } },
    .{ .from = .{ .x = 740, .y = 180 }, .to = .{ .x = 740, .y = 342 } },
    .{ .from = .{ .x = 286, .y = 180 }, .to = .{ .x = 286, .y = 844 } },
    .{ .from = .{ .x = 286, .y = 844 }, .to = .{ .x = 740, .y = 844 } },
    .{ .from = .{ .x = 740, .y = 844 }, .to = .{ .x = 740, .y = 682 } },
};

pub const flow_segments = [_]Segment{
    .{ .from = .{ .x = 176, .y = 654 }, .to = .{ .x = 302, .y = 528 } },
    .{ .from = .{ .x = 302, .y = 528 }, .to = .{ .x = 474, .y = 528 } },
    .{ .from = .{ .x = 474, .y = 528 }, .to = .{ .x = 596, .y = 406 } },
    .{ .from = .{ .x = 596, .y = 406 }, .to = .{ .x = 756, .y = 406 } },
};

pub const evidence_center = Point{ .x = 756, .y = 406 };

pub const background_hex = "#10161C";
pub const paper_hex = "#E8EFF5";
pub const flow_hex = "#4FD1C5";
pub const evidence_hex = "#F4B860";

pub const background_min: u16 = 64;
pub const background_max: u16 = 960;
pub const background_radius_svg: u16 = 144;
pub const paper_stroke_width: u16 = 48;
pub const flow_stroke_width: u16 = 70;
pub const evidence_radius_svg: u16 = 78;

// The tracked SVG is a generated artifact.  Its paths are formatted from the
// fixed-point segment arrays above so the reviewable geometry cannot drift
// between the human-readable source mark and the rasterized ICO.
pub const canonical_svg =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" ++
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\" role=\"img\">\n" ++
    std.fmt.comptimePrint(
        "  <rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" rx=\"{d}\" fill=\"{s}\"/>\n",
        .{ background_min, background_min, background_max - background_min, background_max - background_min, background_radius_svg, background_hex },
    ) ++
    std.fmt.comptimePrint(
        "  <path d=\"M {d} {d} L {d} {d} M {d} {d} L {d} {d} M {d} {d} L {d} {d} M {d} {d} L {d} {d} M {d} {d} L {d} {d}\" fill=\"none\" stroke=\"{s}\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"{d}\"/>\n",
        .{
            paper_segments[0].from.x,
            paper_segments[0].from.y,
            paper_segments[0].to.x,
            paper_segments[0].to.y,
            paper_segments[1].from.x,
            paper_segments[1].from.y,
            paper_segments[1].to.x,
            paper_segments[1].to.y,
            paper_segments[2].from.x,
            paper_segments[2].from.y,
            paper_segments[2].to.x,
            paper_segments[2].to.y,
            paper_segments[3].from.x,
            paper_segments[3].from.y,
            paper_segments[3].to.x,
            paper_segments[3].to.y,
            paper_segments[4].from.x,
            paper_segments[4].from.y,
            paper_segments[4].to.x,
            paper_segments[4].to.y,
            paper_hex,
            paper_stroke_width,
        },
    ) ++
    std.fmt.comptimePrint(
        "  <path d=\"M {d} {d} L {d} {d} M {d} {d} L {d} {d} M {d} {d} L {d} {d} M {d} {d} L {d} {d}\" fill=\"none\" stroke=\"{s}\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"{d}\"/>\n",
        .{
            flow_segments[0].from.x,
            flow_segments[0].from.y,
            flow_segments[0].to.x,
            flow_segments[0].to.y,
            flow_segments[1].from.x,
            flow_segments[1].from.y,
            flow_segments[1].to.x,
            flow_segments[1].to.y,
            flow_segments[2].from.x,
            flow_segments[2].from.y,
            flow_segments[2].to.x,
            flow_segments[2].to.y,
            flow_segments[3].from.x,
            flow_segments[3].from.y,
            flow_segments[3].to.x,
            flow_segments[3].to.y,
            flow_hex,
            flow_stroke_width,
        },
    ) ++
    std.fmt.comptimePrint(
        "  <circle cx=\"{d}\" cy=\"{d}\" r=\"{d}\" fill=\"{s}\"/>\n",
        .{ evidence_center.x, evidence_center.y, evidence_radius_svg, evidence_hex },
    ) ++
    "</svg>\n";

pub const icon_resource_script = "1 ICON \"TExFlow.ico\"\n";

const scale: i64 = 1024;
const supersample: i64 = 4;
const paper_radius: i64 = @as(i64, paper_stroke_width) / 2;
const flow_radius: i64 = @as(i64, flow_stroke_width) / 2;
const evidence_radius: i64 = evidence_radius_svg;
const background_radius: i64 = background_radius_svg;

fn parseHexColor(comptime value: []const u8) [4]u8 {
    if (value.len != 7 or value[0] != '#') @compileError("icon colors must be #RRGGBB");
    return .{
        (@as(u8, hexDigit(value[1])) << 4) | hexDigit(value[2]),
        (@as(u8, hexDigit(value[3])) << 4) | hexDigit(value[4]),
        (@as(u8, hexDigit(value[5])) << 4) | hexDigit(value[6]),
        0xFF,
    };
}

fn hexDigit(value: u8) u4 {
    return switch (value) {
        '0'...'9' => @intCast(value - '0'),
        'A'...'F' => @intCast(value - 'A' + 10),
        'a'...'f' => @intCast(value - 'a' + 10),
        else => @compileError("icon colors must use hexadecimal digits"),
    };
}

const background = parseHexColor(background_hex);
const paper = parseHexColor(paper_hex);
const flow = parseHexColor(flow_hex);
const evidence = parseHexColor(evidence_hex);

pub const Error = error{
    InvalidSize,
    SizeOverflow,
    InvalidIco,
    TruncatedIco,
};

pub fn renderSvg(allocator: std.mem.Allocator) ![]u8 {
    return allocator.dupe(u8, canonical_svg);
}

pub fn renderRgba(allocator: std.mem.Allocator, size: u16) ![]u8 {
    if (!isSupportedSize(size)) return error.InvalidSize;
    const dim: usize = size;
    const pixels_len = std.math.mul(usize, std.math.mul(usize, dim, dim) catch return error.SizeOverflow, 4) catch return error.SizeOverflow;
    var pixels = try allocator.alloc(u8, pixels_len);
    errdefer allocator.free(pixels);

    for (0..dim) |y| {
        for (0..dim) |x| {
            var color_sums = [3]u32{ 0, 0, 0 };
            var covered_samples: u32 = 0;
            for (0..@as(usize, @intCast(supersample))) |sy| {
                for (0..@as(usize, @intCast(supersample))) |sx| {
                    const sample = sampleColor(.{
                        .x = sampleCoordinate(x, sx, dim),
                        .y = sampleCoordinate(y, sy, dim),
                    });
                    if (sample[3] != 0) {
                        color_sums[0] += sample[0];
                        color_sums[1] += sample[1];
                        color_sums[2] += sample[2];
                        covered_samples += 1;
                    }
                }
            }
            const offset = (y * dim + x) * 4;
            if (covered_samples == 0) {
                @memset(pixels[offset..][0..4], 0);
            } else {
                pixels[offset + 0] = @intCast(color_sums[0] / covered_samples);
                pixels[offset + 1] = @intCast(color_sums[1] / covered_samples);
                pixels[offset + 2] = @intCast(color_sums[2] / covered_samples);
                pixels[offset + 3] = @intCast(covered_samples * 255 / 16);
            }
        }
    }
    return pixels;
}

pub fn renderIco(allocator: std.mem.Allocator) ![]u8 {
    const directory_len = 6 + sizes.len * 16;
    var total_len: usize = directory_len;
    for (sizes) |size| {
        const dim: usize = size;
        const pixel_len = std.math.mul(usize, std.math.mul(usize, dim, dim) catch return error.SizeOverflow, 4) catch return error.SizeOverflow;
        const mask_stride = std.math.mul(usize, (dim + 31) / 32, 4) catch return error.SizeOverflow;
        const mask_len = std.math.mul(usize, mask_stride, dim) catch return error.SizeOverflow;
        const image_len = std.math.add(usize, 40, std.math.add(usize, pixel_len, mask_len) catch return error.SizeOverflow) catch return error.SizeOverflow;
        total_len = std.math.add(usize, total_len, image_len) catch return error.SizeOverflow;
    }

    var ico = try allocator.alloc(u8, total_len);
    errdefer allocator.free(ico);
    @memset(ico, 0);
    std.mem.writeInt(u16, ico[0..2], 0, .little);
    std.mem.writeInt(u16, ico[2..4], 1, .little);
    std.mem.writeInt(u16, ico[4..6], @intCast(sizes.len), .little);

    var image_offset: usize = directory_len;
    for (sizes, 0..) |size, index| {
        const dim: usize = size;
        const pixels = try renderRgba(allocator, size);
        defer allocator.free(pixels);
        const pixel_len = std.math.mul(usize, std.math.mul(usize, dim, dim) catch return error.SizeOverflow, 4) catch return error.SizeOverflow;
        const mask_stride = std.math.mul(usize, (dim + 31) / 32, 4) catch return error.SizeOverflow;
        const mask_len = std.math.mul(usize, mask_stride, dim) catch return error.SizeOverflow;
        const bytes_in_res: usize = std.math.add(usize, 40, std.math.add(usize, pixel_len, mask_len) catch return error.SizeOverflow) catch return error.SizeOverflow;
        const entry = ico[6 + index * 16 ..][0..16];
        entry[0] = if (size == 256) 0 else @intCast(size);
        entry[1] = if (size == 256) 0 else @intCast(size);
        entry[2] = 0;
        entry[3] = 0;
        std.mem.writeInt(u16, entry[4..6], 1, .little);
        std.mem.writeInt(u16, entry[6..8], 32, .little);
        std.mem.writeInt(u32, entry[8..12], @intCast(bytes_in_res), .little);
        std.mem.writeInt(u32, entry[12..16], @intCast(image_offset), .little);

        const image = ico[image_offset..][0..bytes_in_res];
        std.mem.writeInt(u32, image[0..4], 40, .little);
        std.mem.writeInt(i32, image[4..8], @intCast(size), .little);
        std.mem.writeInt(i32, image[8..12], @intCast(@as(u32, size) * 2), .little);
        std.mem.writeInt(u16, image[12..14], 1, .little);
        std.mem.writeInt(u16, image[14..16], 32, .little);
        std.mem.writeInt(u32, image[16..20], 0, .little);
        std.mem.writeInt(u32, image[20..24], @intCast(pixel_len + mask_len), .little);
        std.mem.writeInt(i32, image[24..28], 2835, .little);
        std.mem.writeInt(i32, image[28..32], 2835, .little);
        std.mem.writeInt(u32, image[32..36], 0, .little);
        std.mem.writeInt(u32, image[36..40], 0, .little);

        for (0..dim) |row| {
            const source_row = (dim - row - 1) * dim * 4;
            const target_row = 40 + row * dim * 4;
            for (0..dim) |column| {
                const source = source_row + column * 4;
                const target = target_row + column * 4;
                image[target + 0] = pixels[source + 2];
                image[target + 1] = pixels[source + 1];
                image[target + 2] = pixels[source + 0];
                image[target + 3] = pixels[source + 3];
            }
        }
        for (0..dim) |row| {
            const source_row = (dim - row - 1) * dim * 4;
            const mask_row = 40 + pixel_len + row * mask_stride;
            for (0..dim) |column| {
                const alpha = pixels[source_row + column * 4 + 3];
                if (alpha == 0) {
                    const mask_bit: u8 = @as(u8, 0x80) >> @as(u3, @intCast(column % 8));
                    image[mask_row + column / 8] |= mask_bit;
                }
            }
        }
        image_offset += bytes_in_res;
    }
    return ico;
}

/// Validates the exact ICO contract emitted by `renderIco`.  Keeping this
/// parser allocation-free lets build and PE tests reject truncation, overlap,
/// stale dimensions, and alpha/AND-mask disagreement before resource compilation.
pub fn validateIco(bytes: []const u8) !void {
    if (bytes.len < 6) return error.TruncatedIco;
    if (std.mem.readInt(u16, bytes[0..2], .little) != 0 or
        std.mem.readInt(u16, bytes[2..4], .little) != 1 or
        std.mem.readInt(u16, bytes[4..6], .little) != sizes.len) return error.InvalidIco;
    const directory_len = 6 + sizes.len * 16;
    if (bytes.len < directory_len) return error.TruncatedIco;
    var image_offset: usize = directory_len;
    for (sizes, 0..) |size, index| {
        const entry_offset = 6 + index * 16;
        const entry = bytes[entry_offset..][0..16];
        const width: u16 = if (entry[0] == 0) 256 else entry[0];
        const height: u16 = if (entry[1] == 0) 256 else entry[1];
        if (width != size or height != size or entry[2] != 0 or entry[3] != 0 or
            std.mem.readInt(u16, entry[4..6], .little) != 1 or
            std.mem.readInt(u16, entry[6..8], .little) != 32) return error.InvalidIco;
        const bytes_in_res = std.mem.readInt(u32, entry[8..12], .little);
        const offset = std.mem.readInt(u32, entry[12..16], .little);
        const dim: usize = size;
        const pixel_len = std.math.mul(usize, std.math.mul(usize, dim, dim) catch return error.SizeOverflow, 4) catch return error.SizeOverflow;
        const mask_stride = std.math.mul(usize, (dim + 31) / 32, 4) catch return error.SizeOverflow;
        const mask_len = std.math.mul(usize, mask_stride, dim) catch return error.SizeOverflow;
        const image_len = std.math.add(usize, 40, std.math.add(usize, pixel_len, mask_len) catch return error.SizeOverflow) catch return error.SizeOverflow;
        if (@as(usize, offset) != image_offset or bytes_in_res != image_len) return error.InvalidIco;
        if (@as(usize, offset) > bytes.len or image_len > bytes.len - @as(usize, offset)) return error.TruncatedIco;
        const image = bytes[offset..][0..image_len];
        if (std.mem.readInt(u32, image[0..4], .little) != 40 or
            std.mem.readInt(i32, image[4..8], .little) != size or
            std.mem.readInt(i32, image[8..12], .little) != @as(i32, size) * 2 or
            std.mem.readInt(u16, image[12..14], .little) != 1 or
            std.mem.readInt(u16, image[14..16], .little) != 32 or
            std.mem.readInt(u32, image[16..20], .little) != 0 or
            std.mem.readInt(u32, image[20..24], .little) != pixel_len + mask_len) return error.InvalidIco;
        var has_opaque = false;
        var alpha_offset: usize = 40 + 3;
        const pixel_end = 40 + pixel_len;
        while (alpha_offset < pixel_end) : (alpha_offset += 4) {
            if (image[alpha_offset] != 0) has_opaque = true;
        }
        if (!has_opaque) return error.InvalidIco;
        const mask_start = 40 + pixel_len;
        for (0..dim) |row| {
            const mask_row = mask_start + row * mask_stride;
            const pixel_row = 40 + row * dim * 4;
            for (0..dim) |column| {
                const mask_bit: u8 = @as(u8, 0x80) >> @as(u3, @intCast(column % 8));
                const actual = (image[mask_row + column / 8] & mask_bit) != 0;
                const alpha = image[pixel_row + column * 4 + 3];
                if (actual != (alpha == 0)) return error.InvalidIco;
            }
            for (dim..mask_stride * 8) |padding_bit| {
                const mask_bit: u8 = @as(u8, 0x80) >> @as(u3, @intCast(padding_bit % 8));
                if ((image[mask_row + padding_bit / 8] & mask_bit) != 0) return error.InvalidIco;
            }
        }
        image_offset += image_len;
    }
    if (image_offset != bytes.len) return error.InvalidIco;
}

fn isSupportedSize(size: u16) bool {
    for (sizes) |candidate| if (candidate == size) return true;
    return false;
}

const SamplePoint = struct { x: i64, y: i64 };

fn sampleCoordinate(index: usize, sub_sample: usize, dimension: usize) i64 {
    const numerator = (@as(i64, @intCast(index)) * supersample + @as(i64, @intCast(sub_sample))) * scale + scale / (supersample * 2);
    return @divTrunc(numerator, @as(i64, @intCast(dimension)) * supersample);
}

fn sampleColor(point: SamplePoint) [4]u8 {
    var color = [4]u8{ 0, 0, 0, 0 };
    if (insideRoundedRect(point, background_radius)) color = background;
    if (strokeContains(point, &paper_segments, paper_radius)) color = paper;
    if (strokeContains(point, &flow_segments, flow_radius)) color = flow;
    if (insideCircle(point, evidence_center, evidence_radius)) color = evidence;
    return color;
}

fn insideRoundedRect(point: SamplePoint, radius: i64) bool {
    const minimum: i64 = background_min;
    const maximum: i64 = background_max;
    if (point.x < minimum or point.y < minimum or point.x > maximum or point.y > maximum) return false;
    if ((point.x >= minimum + radius and point.x <= maximum - radius) or
        (point.y >= minimum + radius and point.y <= maximum - radius)) return true;
    const cx = if (point.x < minimum + radius) minimum + radius else maximum - radius;
    const cy = if (point.y < minimum + radius) minimum + radius else maximum - radius;
    const dx = point.x - cx;
    const dy = point.y - cy;
    return dx * dx + dy * dy <= radius * radius;
}

fn strokeContains(point: SamplePoint, segments: []const Segment, radius: i64) bool {
    for (segments) |segment| if (nearSegment(point, segment, radius)) return true;
    return false;
}

fn nearSegment(point: SamplePoint, segment: Segment, radius: i64) bool {
    const ax: i64 = segment.from.x;
    const ay: i64 = segment.from.y;
    const bx: i64 = segment.to.x;
    const by: i64 = segment.to.y;
    const dx = bx - ax;
    const dy = by - ay;
    const px = point.x - ax;
    const py = point.y - ay;
    const length_squared = dx * dx + dy * dy;
    if (length_squared == 0) return px * px + py * py <= radius * radius;
    const projection = px * dx + py * dy;
    if (projection <= 0) return px * px + py * py <= radius * radius;
    const end_px = point.x - bx;
    const end_py = point.y - by;
    if (projection >= length_squared) return end_px * end_px + end_py * end_py <= radius * radius;
    const cross = px * dy - py * dx;
    return cross * cross <= radius * radius * length_squared;
}

fn insideCircle(point: SamplePoint, center: Point, radius: i64) bool {
    const dx = point.x - @as(i64, center.x);
    const dy = point.y - @as(i64, center.y);
    return dx * dx + dy * dy <= radius * radius;
}
