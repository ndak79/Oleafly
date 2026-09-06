//! Deterministic, Zig-owned gates for an offline reproducibility run.
//!
//! This module deliberately stops at preflight, receipt validation, and
//! canonical payload comparison.  It does not launch a compiler, fetch a
//! dependency, or claim that the sealed reconstruction runner exists.  Keeping
//! those boundaries explicit makes this tool safe to use as a prerequisite for
//! the later PDFium/reconstruction work.
const std = @import("std");
const deps = @import("deps");

pub const Target = enum {
    windows_x64,
    linux_x64,
};

pub const Phase = enum {
    resolve,
    reproduce,
};

pub const Preflight = struct {
    phase: Phase,
    /// This is an explicit authorization bit, not a request to enable the
    /// network.  A sealed reproduction still requires a separate receipt that
    /// proves the effective network mode is `none`.
    allow_network: bool,
    runner_authorized: bool,
    root_disposable: bool,
    free_space_bytes: u64,
    physical_memory_bytes: u64,
    network_none_verified: bool,
};

pub const PayloadSummary = struct {
    files: u32,
    bytes: u64,
    digest: [32]u8,
};

pub const PayloadComparison = struct {
    left: PayloadSummary,
    right: PayloadSummary,
};

pub const minimum_repro_disk_bytes: u64 = 100 * 1024 * 1024 * 1024;
pub const minimum_repro_memory_bytes: u64 = 16 * 1024 * 1024 * 1024;
const maximum_payload_bytes: u64 = 8 * 1024 * 1024 * 1024;

const canonical_network_receipt =
    "network_mode=none\n" ++
    "fetch_bytes=0\n" ++
    "route_count=0\n" ++
    "proxy=unset\n" ++
    "process_policy=zig-owned\n";

pub fn validateTarget(target: []const u8) !void {
    if (std.mem.eql(u8, target, "x86_64-windows-msvc") or
        std.mem.eql(u8, target, "x86_64-linux-gnu"))
    {
        return;
    }
    return error.TargetNotAdmitted;
}

pub fn validateReproRoot(path: []const u8) !void {
    return validateAbsolutePath(path, true);
}

fn validatePayloadRootPath(path: []const u8) !void {
    // Payload roots may live below ordinary Windows user profiles such as
    // `C:\\Users\\Researcher Name`; whitespace is safe when no shell is ever
    // invoked.  Keep the component, control-byte, and traversal checks shared
    // with the stricter disposable-runner root policy.
    return validateAbsolutePath(path, false);
}

fn validateAbsolutePath(path: []const u8, reject_whitespace: bool) !void {
    if (path.len == 0 or path.len > 4096 or !std.unicode.utf8ValidateSlice(path)) {
        return error.ReproRootUnsafe;
    }
    if (!std.Io.Dir.path.isAbsolute(path)) return error.ReproRootMustBeAbsolute;
    if (path[path.len - 1] == '/' or path[path.len - 1] == '\\') {
        return error.ReproRootUnsafe;
    }

    const has_drive_prefix = path.len >= 2 and
        ((path[0] >= 'a' and path[0] <= 'z') or (path[0] >= 'A' and path[0] <= 'Z')) and
        path[1] == ':';
    var component_start: usize = if (has_drive_prefix) 2 else 0;
    var index: usize = 0;
    while (index < path.len) : (index += 1) {
        const byte = path[index];
        if (byte < 0x20 or byte == 0x7f or (reject_whitespace and byte == ' ') or byte == '\t' or
            byte == '"' or byte == '*' or byte == '?' or byte == '<' or
            byte == '>' or byte == '|' or byte == ';' or byte == '&')
        {
            return error.ReproRootUnsafe;
        }
        if (byte == ':' and !(has_drive_prefix and index == 1)) {
            return error.ReproRootUnsafe;
        }
        if (byte != '/' and byte != '\\') continue;
        if (index > component_start) {
            const component = path[component_start..index];
            if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) {
                return error.ReproRootUnsafe;
            }
        }
        component_start = index + 1;
    }
    if (component_start >= path.len or
        std.mem.eql(u8, path[component_start..], ".") or
        std.mem.eql(u8, path[component_start..], ".."))
    {
        return error.ReproRootUnsafe;
    }
}

pub fn validatePreflight(preflight: Preflight) !void {
    // The caller must explicitly authorize the runner policy even when the
    // effective reproduction receipt later proves that networking is disabled.
    if (!preflight.allow_network) return error.NetworkAuthorizationRequired;
    if (!preflight.runner_authorized) return error.RunnerNotAuthorized;
    if (!preflight.root_disposable) return error.DisposableRootRequired;
    if (preflight.free_space_bytes < minimum_repro_disk_bytes) {
        return error.InsufficientReproDisk;
    }
    if (preflight.physical_memory_bytes < minimum_repro_memory_bytes) {
        return error.InsufficientReproMemory;
    }
    switch (preflight.phase) {
        .resolve => {},
        .reproduce => {
            if (!preflight.network_none_verified) return error.NetworkIsolationUnverified;
        },
    }
}

pub fn verifyNetworkReceipt(bytes: []const u8) !void {
    if (std.mem.eql(u8, bytes, canonical_network_receipt)) return;

    // Surface isolation failures distinctly from ordinary formatting/content
    // mismatches.  This prevents a proxy or route from being hidden by a
    // generic parser error.
    const network_mode = findLineValue(bytes, "network_mode=") orelse
        return error.NetworkReceiptMismatch;
    if (!std.mem.eql(u8, network_mode, "none")) {
        return error.NetworkIsolationUnverified;
    }
    const proxy = findLineValue(bytes, "proxy=") orelse
        return error.NetworkReceiptMismatch;
    if (!std.mem.eql(u8, proxy, "unset")) return error.NetworkIsolationUnverified;
    const route_count = findLineValue(bytes, "route_count=") orelse
        return error.NetworkReceiptMismatch;
    if (!std.mem.eql(u8, route_count, "0")) return error.NetworkIsolationUnverified;
    const fetch_bytes = findLineValue(bytes, "fetch_bytes=") orelse
        return error.NetworkReceiptMismatch;
    if (!std.mem.eql(u8, fetch_bytes, "0")) return error.NetworkReceiptMismatch;
    const process_policy = findLineValue(bytes, "process_policy=") orelse
        return error.NetworkReceiptMismatch;
    if (!std.mem.eql(u8, process_policy, "zig-owned")) {
        return error.NetworkIsolationUnverified;
    }
    return error.NetworkReceiptMismatch;
}

fn findLineValue(bytes: []const u8, prefix: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, prefix)) return line[prefix.len..];
    }
    return null;
}

pub fn verifyRequiredRoles(target: []const u8, paths: []const []const u8) !void {
    if (std.mem.eql(u8, target, "x86_64-linux-gnu")) {
        for (paths) |path| {
            if (std.mem.endsWith(u8, path, ".exe") or
                std.mem.startsWith(u8, path, "bin/TExFlow"))
            {
                return error.UnexpectedLinuxProduct;
            }
        }
        return;
    }
    try validateTarget(target);
    const required = [_][]const u8{
        "bin/TExFlow.exe",
        "bin/TExFlow.PdfWorker.exe",
        "bin/TExFlow.ScienceWorker.exe",
    };
    if (paths.len > required.len) return error.UnexpectedRequiredRole;
    for (required) |role| {
        var found = false;
        for (paths) |path| {
            if (std.mem.eql(u8, role, path)) {
                if (found) return error.UnexpectedRequiredRole;
                found = true;
            }
        }
        if (!found) return error.MissingRequiredRole;
    }
    if (paths.len != required.len) return error.MissingRequiredRole;
}

pub fn comparePayloadRoots(
    allocator: std.mem.Allocator,
    io: std.Io,
    left_path: []const u8,
    right_path: []const u8,
) !PayloadComparison {
    var left_root = openPayloadRoot(io, left_path) catch |err| return err;
    defer left_root.close(io);
    var right_root = openPayloadRoot(io, right_path) catch |err| return err;
    defer right_root.close(io);

    const left = try deps.hashMaterializedDirectory(allocator, io, left_root, maximum_payload_bytes);
    const right = try deps.hashMaterializedDirectory(allocator, io, right_root, maximum_payload_bytes);
    const comparison = PayloadComparison{
        .left = .{ .files = left.files, .bytes = left.bytes, .digest = left.digest },
        .right = .{ .files = right.files, .bytes = right.bytes, .digest = right.digest },
    };
    if (comparison.left.files != comparison.right.files or
        comparison.left.bytes != comparison.right.bytes or
        !std.mem.eql(u8, &comparison.left.digest, &comparison.right.digest))
    {
        return error.PayloadManifestMismatch;
    }
    return comparison;
}

fn openPayloadRoot(io: std.Io, path: []const u8) !std.Io.Dir {
    try validatePayloadRootPath(path);
    var root = std.Io.Dir.openDirAbsolute(io, path, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.NotDir, error.FileNotFound => return error.RootNotDirectory,
        else => |e| return e,
    };
    errdefer root.close(io);
    if ((try root.stat(io)).kind != .directory) return error.RootNotDirectory;
    return root;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 6 or !std.mem.eql(u8, args[1], "compare")) return error.InvalidArguments;
    try validateTarget(args[2]);
    try validatePayloadRootPath(args[3]);
    try validatePayloadRootPath(args[4]);
    const receipt = try std.Io.Dir.cwd().readFileAlloc(init.io, args[5], init.gpa, .limited(1024));
    defer init.gpa.free(receipt);
    try verifyNetworkReceipt(receipt);
    const comparison = try comparePayloadRoots(init.gpa, init.io, args[3], args[4]);
    std.debug.print(
        "repro-check target={s} files={d} bytes={d} digest={x}\n",
        .{ args[2], comparison.left.files, comparison.left.bytes, comparison.left.digest },
    );
}
