const std = @import("std");
const win32 = @import("zigwin32");

test "zigwin32 resolves from the verified build-cache export" {
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(win32.foundation.HANDLE));
}
