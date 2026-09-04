const std = @import("std");

const HeaderAbiVersion = extern struct {
    major: u32,
    minor: u32,
    patch: u32,
};

extern fn oleafly_abi_get_version(out: ?*HeaderAbiVersion) callconv(.c) i32;
extern fn oleafly_abi_add(a: i64, b: i64) callconv(.c) i64;

test "fixed-width C ABI layout and calls" {
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(HeaderAbiVersion));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(HeaderAbiVersion));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(HeaderAbiVersion, "major"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(HeaderAbiVersion, "minor"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(HeaderAbiVersion, "patch"));
    try std.testing.expectEqual(@as(i64, 42), oleafly_abi_add(40, 2));
    try std.testing.expectEqual(@as(i64, -4), oleafly_abi_add(-7, 3));
    try std.testing.expectEqual(std.math.maxInt(i64), oleafly_abi_add(std.math.maxInt(i64) - 1, 1));
    try std.testing.expectEqual(std.math.minInt(i64), oleafly_abi_add(std.math.maxInt(i64), 1));

    var version: HeaderAbiVersion = undefined;
    try std.testing.expectEqual(@as(i32, 0), oleafly_abi_get_version(&version));
    try std.testing.expectEqual(@as(u32, 0), version.major);
    try std.testing.expectEqual(@as(u32, 1), version.minor);
    try std.testing.expectEqual(@as(u32, 0), version.patch);
    try std.testing.expectEqual(@as(i32, -1), oleafly_abi_get_version(null));
}
