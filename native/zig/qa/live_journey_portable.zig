//! Compile-only adapter for the Windows-only physical T0.2c QA client.
//! The selected non-Windows target must not link Windows desktop APIs.
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    _ = init;
    return error.UnsupportedPlatform;
}
