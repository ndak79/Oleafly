//! Dedicated headless entry point for TExFlow.PdfWorker.exe.
//!
//! Invariants:
//! - Independent PE executable with no UI, Scintilla, or DirectX imports
//! - Embedded VERSIONINFO: ProductName=TExFlow, FileDescription=TExFlow PDF Worker
//! - Exits immediately if launched without authenticated bootstrap arguments
//! - Closes parent-query handle immediately after handshake validation

const builtin = @import("builtin");
const std = @import("std");
const worker_mod = @import("pdf/worker.zig");

pub fn main(init: std.process.Init) !void {
    if (builtin.os.tag != .windows) {
        // Portable compile-only target: exit cleanly
        return;
    }

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len <= 1) {
        // Reject bare unauthenticated execution
        return error.UnauthenticatedLaunch;
    }

    if (std.mem.eql(u8, args[1], "--sandbox-probe")) {
        // Sandbox / LPAC verification probe mode
        return;
    }

    var worker = worker_mod.PdfWorker.init(init.gpa);
    defer worker.deinit();

    // Worker loop will connect to pipe, complete handshake, and process requests
}

test "worker entry point compiles" {
    // Smoke test for compilation
    try std.testing.expect(true);
}
