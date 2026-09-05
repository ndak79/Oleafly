const std = @import("std");

const FixtureZipEntry = struct {
    name: []const u8,
    data: []const u8,
};

pub fn makeStoredZip(
    allocator: std.mem.Allocator,
    entries: []const FixtureZipEntry,
) ![]u8 {
    if (entries.len > 8) return error.TooManyEntries;
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    var offsets: [8]u32 = undefined;
    for (entries, 0..) |entry, index| {
        offsets[index] = @intCast(output.written().len);
        const crc = std.hash.Crc32.hash(entry.data);
        try output.writer.writeInt(u32, 0x04034b50, .little);
        try output.writer.writeInt(u16, 20, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u32, crc, .little);
        try output.writer.writeInt(u32, @intCast(entry.data.len), .little);
        try output.writer.writeInt(u32, @intCast(entry.data.len), .little);
        try output.writer.writeInt(u16, @intCast(entry.name.len), .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeAll(entry.name);
        try output.writer.writeAll(entry.data);
    }
    const central_offset: u32 = @intCast(output.written().len);
    for (entries, 0..) |entry, index| {
        const crc = std.hash.Crc32.hash(entry.data);
        try output.writer.writeInt(u32, 0x02014b50, .little);
        try output.writer.writeInt(u16, 0x0314, .little);
        try output.writer.writeInt(u16, 20, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u32, crc, .little);
        try output.writer.writeInt(u32, @intCast(entry.data.len), .little);
        try output.writer.writeInt(u32, @intCast(entry.data.len), .little);
        try output.writer.writeInt(u16, @intCast(entry.name.len), .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u16, 0, .little);
        try output.writer.writeInt(u32, 0, .little);
        try output.writer.writeInt(u32, offsets[index], .little);
        try output.writer.writeAll(entry.name);
    }
    const central_size: u32 = @intCast(output.written().len - central_offset);
    try output.writer.writeInt(u32, 0x06054b50, .little);
    try output.writer.writeInt(u16, 0, .little);
    try output.writer.writeInt(u16, 0, .little);
    try output.writer.writeInt(u16, @intCast(entries.len), .little);
    try output.writer.writeInt(u16, @intCast(entries.len), .little);
    try output.writer.writeInt(u32, central_size, .little);
    try output.writer.writeInt(u32, central_offset, .little);
    try output.writer.writeInt(u16, 0, .little);
    return output.toOwnedSlice();
}
