const std = @import("std");
const contract = @import("abi_contract");

const HeaderAbiVersion = extern struct {
    major: u32,
    minor: u32,
    patch: u32,
};

extern fn texflow_abi_get_version(out: ?*HeaderAbiVersion) callconv(.c) i32;
extern fn texflow_abi_add(a: i64, b: i64) callconv(.c) i64;

test "fixed-width C ABI layout and calls" {
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(HeaderAbiVersion));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(HeaderAbiVersion));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(HeaderAbiVersion, "major"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(HeaderAbiVersion, "minor"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(HeaderAbiVersion, "patch"));
    try std.testing.expectEqual(@as(i64, 42), texflow_abi_add(40, 2));
    try std.testing.expectEqual(@as(i64, -4), texflow_abi_add(-7, 3));
    try std.testing.expectEqual(std.math.maxInt(i64), texflow_abi_add(std.math.maxInt(i64) - 1, 1));
    try std.testing.expectEqual(std.math.minInt(i64), texflow_abi_add(std.math.maxInt(i64), 1));

    var version: HeaderAbiVersion = undefined;
    try std.testing.expectEqual(@as(i32, 0), texflow_abi_get_version(&version));
    try std.testing.expectEqual(@as(u32, 0), version.major);
    try std.testing.expectEqual(@as(u32, 1), version.minor);
    try std.testing.expectEqual(@as(u32, 0), version.patch);
    try std.testing.expectEqual(@as(i32, -1), texflow_abi_get_version(null));
}

test "ABI library stays in the test cache and cannot enter the product install graph" {
    try std.testing.expectEqualStrings("texflow_abi", contract.library_name);
    try std.testing.expect(!contract.install_reaches_library);
    try std.testing.expect(!contract.product_reaches_library);
}

test "compiled archive and header directory have no compatibility ABI namespace" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const archive = try std.Io.Dir.cwd().readFileAlloc(io, contract.library_path, allocator, .limited(4 * 1024 * 1024));
    defer allocator.free(archive);
    // The archive's symbol table must contain both linked entry points and
    // cannot retain compatibility exports under the historical prefix.
    try std.testing.expect(std.mem.indexOf(u8, archive, "texflow_abi_get_version") != null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "texflow_abi_add") != null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "oleafly_abi_") == null);
    var headers = try std.Io.Dir.cwd().openDir(io, contract.header_root, .{});
    defer headers.close(io);
    const header = try headers.openFile(io, "texflow_abi.h", .{});
    defer header.close(io);
    try std.testing.expectError(error.FileNotFound, headers.openFile(io, "oleafly_abi.h", .{}));
}
