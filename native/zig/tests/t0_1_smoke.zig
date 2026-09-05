const std = @import("std");
const contract = @import("smoke_contract");

// This replaces the console smoke intent inside the Zig test runner only.
// No product entry point or installed executable depends on this function.
fn writeSmoke(writer: *std.Io.Writer) !void {
    try writer.writeAll("TExFlow toolchain ok");
}

test "portable toolchain smoke writes the exact TExFlow known answer" {
    var buffer: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try writeSmoke(&writer);
    try std.testing.expectEqualStrings("TExFlow toolchain ok", writer.buffered());
}

test "toolchain smoke is test-only and excluded from the install graph" {
    try std.testing.expect(!contract.install_reaches_smoke);
    try std.testing.expect(!contract.product_reaches_smoke);
}
