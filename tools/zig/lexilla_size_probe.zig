//! Emit a typed Zig receipt for the compiled Lexilla comparator archive.
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.InvalidArguments;
    const artifact_path = args[1];
    const output_path = args[2];

    const artifact = try std.Io.Dir.cwd().openFile(init.io, artifact_path, .{});
    defer artifact.close(init.io);
    const size = (try artifact.stat(init.io)).size;
    var source: [96]u8 = undefined;
    const bytes = try std.fmt.bufPrint(&source, "pub const artifact_size_bytes: u64 = {d};\n", .{size});
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = output_path, .data = bytes });
}
