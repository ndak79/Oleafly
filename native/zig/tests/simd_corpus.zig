const std = @import("std");

const Lane = @Vector(4, u32);

test "SIMD lane arithmetic known answers" {
    const values: Lane = .{ 1, 2, 3, 4 };
    const factors: Lane = .{ 5, 6, 7, 8 };
    const actual = values * factors + @as(Lane, @splat(9));
    const expected: Lane = .{ 14, 21, 30, 41 };
    try std.testing.expect(@reduce(.And, actual == expected));
    try std.testing.expectEqual(@as(u32, 106), @reduce(.Add, actual));
}

test "SIMD comptime and runtime answers agree" {
    const values: Lane = .{ 10, 20, 30, 40 };
    const actual = values + @as(Lane, @splat(2));
    const expected: Lane = .{ 12, 22, 32, 42 };
    const comptime_actual = comptime values + @as(Lane, @splat(2));
    try std.testing.expect(@reduce(.And, actual == expected));
    try std.testing.expect(@reduce(.And, comptime_actual == expected));
}
