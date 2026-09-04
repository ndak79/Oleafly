const std = @import("std");

const Case = struct {
    input: []const u8,
    expected: u64,
};

const cases = [_]Case{
    .{ .input = "", .expected = 14695981039346656037 },
    .{ .input = "a", .expected = 12638187200555641996 },
    .{ .input = "abc", .expected = 16654208175385433931 },
    .{ .input = "Oleafly", .expected = 2268825733032138785 },
    .{ .input = &[_]u8{ 0x00, 0xff }, .expected = 590474061099445088 },
};

fn fnv1a64(bytes: []const u8) u64 {
    var hash: u64 = 14695981039346656037;
    for (bytes) |byte| {
        hash ^= @as(u64, byte);
        hash *%= 1099511628211;
    }
    return hash;
}

test "FNV-1a 64 known answers" {
    for (cases) |case| {
        try std.testing.expectEqual(case.expected, fnv1a64(case.input));
    }
}

test "comptime and runtime answers agree" {
    inline for (cases) |case| {
        const compile_value = comptime fnv1a64(case.input);
        try std.testing.expectEqual(compile_value, fnv1a64(case.input));
    }
}

test "integer overflow is represented explicitly" {
    const result = @addWithOverflow(@as(u8, 255), @as(u8, 1));
    try std.testing.expectEqual(@as(u8, 0), result[0]);
    try std.testing.expectEqual(@as(u1, 1), result[1]);
}
