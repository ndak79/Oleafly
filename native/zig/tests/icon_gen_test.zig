//! Deterministic TExFlow source-mark and ICO contract tests.
const std = @import("std");
const icon = @import("texflow_icon");
const assets = @import("icon_assets");
const tracked_svg = assets.tracked_svg;

const expected_sizes = [_]u16{ 16, 24, 32, 48, 256 };

test "canonical geometry and SVG are stable" {
    try std.testing.expectEqualSlices(u16, &expected_sizes, &icon.sizes);
    try std.testing.expect(icon.canonical_svg.len > 100);
    try std.testing.expect(std.mem.indexOf(u8, icon.canonical_svg, "TExFlow") == null);
    try std.testing.expect(std.mem.indexOf(u8, icon.canonical_svg, "linearGradient") == null);
    try std.testing.expect(std.mem.indexOf(u8, icon.canonical_svg, "#4FD1C5") != null);
    try std.testing.expect(std.mem.indexOf(u8, icon.canonical_svg, "#10161C") != null);
    try std.testing.expect(std.mem.indexOf(u8, icon.canonical_svg, "#F4B860") != null);
    try std.testing.expectEqualStrings(tracked_svg, icon.canonical_svg);
    try std.testing.expectEqualStrings("1 ICON \"TExFlow.ico\"\n", icon.icon_resource_script);
}

test "SVG rendering is independent of allocator state" {
    const first = try icon.renderSvg(std.testing.allocator);
    defer std.testing.allocator.free(first);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const second = try icon.renderSvg(arena.allocator());
    try std.testing.expectEqualStrings(first, second);
}

test "ICO rendering is deterministic across independent allocators" {
    const first = try icon.renderIco(std.testing.allocator);
    defer std.testing.allocator.free(first);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const second = try icon.renderIco(arena.allocator());
    try std.testing.expectEqualSlices(u8, first, second);
}

test "ICO has exact five-entry directory and bounded images" {
    const ico = try icon.renderIco(std.testing.allocator);
    defer std.testing.allocator.free(ico);
    try icon.validateIco(ico);

    try std.testing.expect(ico.len > 6);
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, ico[0..2], .little));
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, ico[2..4], .little));
    try std.testing.expectEqual(@as(u16, expected_sizes.len), std.mem.readInt(u16, ico[4..6], .little));

    var previous_end: usize = 6 + expected_sizes.len * 16;
    for (expected_sizes, 0..) |size, index| {
        const entry = ico[6 + index * 16 ..][0..16];
        const width: u16 = if (entry[0] == 0) 256 else entry[0];
        const height: u16 = if (entry[1] == 0) 256 else entry[1];
        try std.testing.expectEqual(size, width);
        try std.testing.expectEqual(size, height);
        try std.testing.expectEqual(@as(u8, 0), entry[2]);
        try std.testing.expectEqual(@as(u8, 0), entry[3]);
        try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, entry[4..6], .little));
        try std.testing.expectEqual(@as(u16, 32), std.mem.readInt(u16, entry[6..8], .little));
        const bytes_in_res = std.mem.readInt(u32, entry[8..12], .little);
        const offset = std.mem.readInt(u32, entry[12..16], .little);
        try std.testing.expectEqual(previous_end, @as(usize, offset));
        const pixel_bytes = @as(u32, size) * @as(u32, size) * 4;
        const mask_stride = ((@as(u32, size) + 31) / 32) * 4;
        const expected_image_bytes = 40 + pixel_bytes + mask_stride * @as(u32, size);
        try std.testing.expectEqual(expected_image_bytes, bytes_in_res);
        try std.testing.expect(@as(usize, offset) + bytes_in_res <= ico.len);
        previous_end = @as(usize, offset) + bytes_in_res;

        const image = ico[offset..][0..bytes_in_res];
        try std.testing.expectEqual(@as(u32, 40), std.mem.readInt(u32, image[0..4], .little));
        try std.testing.expectEqual(@as(i32, size), std.mem.readInt(i32, image[4..8], .little));
        try std.testing.expectEqual(@as(i32, @as(i32, size) * 2), std.mem.readInt(i32, image[8..12], .little));
        try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, image[12..14], .little));
        try std.testing.expectEqual(@as(u16, 32), std.mem.readInt(u16, image[14..16], .little));
        try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, image[16..20], .little));
        try std.testing.expect(std.mem.indexOfScalar(u8, image[40..], 0xFF) != null);
    }
    try std.testing.expectEqual(ico.len, previous_end);
}

test "ICO validator rejects count, offset, dimension, truncation, and mask mutations" {
    const source = try icon.renderIco(std.testing.allocator);
    defer std.testing.allocator.free(source);

    var count_mutant = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(count_mutant);
    std.mem.writeInt(u16, count_mutant[4..6], 4, .little);
    try std.testing.expectError(error.InvalidIco, icon.validateIco(count_mutant));

    var offset_mutant = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(offset_mutant);
    std.mem.writeInt(u32, offset_mutant[6 + 12 ..][0..4], 7, .little);
    try std.testing.expectError(error.InvalidIco, icon.validateIco(offset_mutant));

    var dimension_mutant = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(dimension_mutant);
    dimension_mutant[6] = 15;
    try std.testing.expectError(error.InvalidIco, icon.validateIco(dimension_mutant));

    var length_mutant = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(length_mutant);
    std.mem.writeInt(u32, length_mutant[6 + 8 ..][0..4], 40, .little);
    try std.testing.expectError(error.InvalidIco, icon.validateIco(length_mutant));

    var dib_mutant = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(dib_mutant);
    const first_image = 6 + icon.sizes.len * 16;
    std.mem.writeInt(i32, dib_mutant[first_image + 4 ..][0..4], 15, .little);
    try std.testing.expectError(error.InvalidIco, icon.validateIco(dib_mutant));

    const truncated = source[0 .. source.len - 1];
    try std.testing.expectError(error.TruncatedIco, icon.validateIco(truncated));

    var mask_mutant = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(mask_mutant);
    const first_image_mask = first_image + 40 + 16 * 16 * 4;
    mask_mutant[first_image_mask] ^= 0x80;
    try std.testing.expectError(error.InvalidIco, icon.validateIco(mask_mutant));

    var alpha_mutant = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(alpha_mutant);
    var alpha_offset = first_image + 40 + 3;
    const alpha_end = first_image + 40 + 16 * 16 * 4;
    while (alpha_offset < alpha_end) : (alpha_offset += 4) alpha_mutant[alpha_offset] = 0;
    try std.testing.expectError(error.InvalidIco, icon.validateIco(alpha_mutant));
}

test "ICO rejects unsupported sizes" {
    try std.testing.expectError(error.InvalidSize, icon.renderRgba(std.testing.allocator, 15));
    try std.testing.expectError(error.InvalidSize, icon.renderRgba(std.testing.allocator, 64));
    try std.testing.expectError(error.InvalidSize, icon.renderRgba(std.testing.allocator, 0));
}

test "ICO emits transparent corners and visible mark pixels" {
    const pixels = try icon.renderRgba(std.testing.allocator, 16);
    defer std.testing.allocator.free(pixels);
    const corner = pixels[0..4];
    try std.testing.expectEqual(@as(u8, 0), corner[3]);
    var has_teal = false;
    var has_amber = false;
    for (0..16 * 16) |index| {
        const rgba = pixels[index * 4 ..][0..4];
        if (rgba[1] > rgba[0] and rgba[1] > rgba[2] and rgba[3] > 0) has_teal = true;
        if (rgba[0] > rgba[1] and rgba[1] > rgba[2] and rgba[3] > 0) has_amber = true;
    }
    try std.testing.expect(has_teal);
    try std.testing.expect(has_amber);
}

test "ICO AND mask mirrors transparent alpha with padded rows" {
    const ico = try icon.renderIco(std.testing.allocator);
    defer std.testing.allocator.free(ico);
    for (expected_sizes, 0..) |size, index| {
        const entry = ico[6 + index * 16 ..][0..16];
        const bytes_in_res = std.mem.readInt(u32, entry[8..12], .little);
        const offset = std.mem.readInt(u32, entry[12..16], .little);
        const image = ico[offset..][0..bytes_in_res];
        const dim: usize = size;
        const pixel_len = dim * dim * 4;
        const mask_stride = ((dim + 31) / 32) * 4;
        const mask = image[40 + pixel_len ..];
        var saw_transparent = false;
        for (0..dim) |row| {
            for (0..dim) |column| {
                const alpha = image[40 + row * dim * 4 + column * 4 + 3];
                const mask_bit: u8 = @as(u8, 0x80) >> @as(u3, @intCast(column % 8));
                const masked = (mask[row * mask_stride + column / 8] & mask_bit) != 0;
                try std.testing.expectEqual(alpha == 0, masked);
                saw_transparent = saw_transparent or alpha == 0;
            }
            for (dim..mask_stride * 8) |padding_bit| {
                const mask_bit: u8 = @as(u8, 0x80) >> @as(u3, @intCast(padding_bit % 8));
                try std.testing.expectEqual(@as(u8, 0), mask[row * mask_stride + padding_bit / 8] & mask_bit);
            }
        }
        try std.testing.expect(saw_transparent);
    }
}

fn exerciseIco(allocator: std.mem.Allocator) !void {
    const output = try icon.renderIco(allocator);
    defer allocator.free(output);
}

test "ICO generation releases every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseIco, .{});
}
