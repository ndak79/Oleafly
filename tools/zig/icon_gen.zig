//! Build-time TExFlow mark generator.  It emits only deterministic files into
//! the Zig cache; it never mutates tracked source files.
const std = @import("std");
const icon = @import("texflow_icon");

pub const ico_name = "TExFlow.ico";
pub const svg_name = "TExFlow-app-mark.svg";
pub const rc_name = "TExFlow-icon.rc";

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3 or !std.mem.eql(u8, args[1], "emit")) return error.InvalidArguments;
    const output = try std.Io.Dir.openDirAbsolute(init.io, args[2], .{});
    defer output.close(init.io);

    const ico = try icon.renderIco(init.gpa);
    defer init.gpa.free(ico);
    try icon.validateIco(ico);
    const svg = try icon.renderSvg(init.gpa);
    defer init.gpa.free(svg);

    try output.writeFile(init.io, .{ .sub_path = ico_name, .data = ico });
    try output.writeFile(init.io, .{ .sub_path = svg_name, .data = svg });
    try output.writeFile(init.io, .{ .sub_path = rc_name, .data = icon.icon_resource_script });
}

test "generator output names stay inside the resource contract" {
    try std.testing.expect(std.mem.eql(u8, ico_name, "TExFlow.ico"));
    try std.testing.expect(std.mem.eql(u8, svg_name, "TExFlow-app-mark.svg"));
    try std.testing.expect(std.mem.eql(u8, rc_name, "TExFlow-icon.rc"));
}
