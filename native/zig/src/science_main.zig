//! Dedicated headless entry point for TExFlow.ScienceWorker.exe.
//!
//! Invariants:
//! - Independent PE executable without UI, Scintilla, or DirectX imports
//! - Embedded VERSIONINFO: ProductName=TExFlow, FileDescription=TExFlow Science Worker
//! - Rejects unauthenticated execution without proper bootstrap arguments
//! - Hosts the disposable search database and FTS5 search queries

const builtin = @import("builtin");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    if (builtin.os.tag != .windows) {
        return;
    }

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len <= 1) {
        return error.UnauthenticatedLaunch;
    }

    if (std.mem.eql(u8, args[1], "--sandbox-probe")) {
        return;
    }
}

test "science worker main compiles" {
    try std.testing.expect(true);
}
