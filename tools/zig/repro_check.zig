//! Deterministic, Zig-owned gates for an offline reproducibility run.
//!
//! This module deliberately stops at preflight, receipt validation, and
//! canonical payload comparison.  It does not launch a compiler, fetch a
//! dependency, or claim that the sealed reconstruction runner exists.  Keeping
//! those boundaries explicit makes this tool safe to use as a prerequisite for
//! the later PDFium/reconstruction work.
const std = @import("std");
const builtin = @import("builtin");
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

pub const RoleManifestEntry = struct {
    name: []const u8,
    path: []const u8,
};

pub const minimum_repro_disk_bytes: u64 = 100 * 1024 * 1024 * 1024;
pub const minimum_repro_memory_bytes: u64 = 16 * 1024 * 1024 * 1024;
const maximum_payload_bytes: u64 = 8 * 1024 * 1024 * 1024;
const maximum_role_manifest_bytes: usize = 16 * 1024;
const maximum_role_manifest_entries = 8;
const role_manifest_header = "texflow-role-manifest-v1";

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

    // Parse exactly five ordered records. A first-match lookup would let a
    // duplicate key hide a later conflicting value, which is unsafe for an
    // isolation receipt. Surface policy failures distinctly from malformed
    // structure while rejecting duplicates, reordering, and extra records.
    const expected = [_][]const u8{
        "network_mode=",
        "fetch_bytes=",
        "route_count=",
        "proxy=",
        "process_policy=",
    };
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    for (expected, 0..) |prefix, index| {
        const line = lines.next() orelse return error.NetworkReceiptMismatch;
        if (!std.mem.startsWith(u8, line, prefix)) return error.NetworkReceiptMismatch;
        const value = line[prefix.len..];
        switch (index) {
            0 => if (!std.mem.eql(u8, value, "none")) return error.NetworkIsolationUnverified,
            1 => if (!std.mem.eql(u8, value, "0")) return error.NetworkReceiptMismatch,
            2 => if (!std.mem.eql(u8, value, "0")) return error.NetworkIsolationUnverified,
            3 => if (!std.mem.eql(u8, value, "unset")) return error.NetworkIsolationUnverified,
            4 => if (!std.mem.eql(u8, value, "zig-owned")) return error.NetworkIsolationUnverified,
            else => unreachable,
        }
    }
    if (lines.next() != null) return error.NetworkReceiptMismatch;
    return error.NetworkReceiptMismatch;
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

/// Hashes the target and exact role/name/path sequence carried by a role
/// manifest. The digest binds the authenticated caller's input; it is not a
/// signature and does not make a runtime or product-shipping claim.
pub fn roleManifestDigest(target: []const u8, entries: []const RoleManifestEntry) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("texflow-repro-role-manifest-v1\x00");
    updateRoleManifestBytes(&hasher, target);
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, @intCast(entries.len), .little);
    hasher.update(&count);
    for (entries) |entry| {
        updateRoleManifestBytes(&hasher, entry.name);
        updateRoleManifestBytes(&hasher, entry.path);
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

/// Validate the small, authenticated role manifest consumed by the CLI.
///
/// The caller that produces the manifest remains responsible for the
/// out-of-band authentication decision. This parser requires that assertion,
/// binds the exact target and role entries to the supplied digest, and then
/// applies the same exact path policy as `verifyRequiredRoles`. It deliberately
/// does not inspect PE bytes or claim worker/PDFium/runtime admission.
pub fn verifyRoleManifest(target: []const u8, bytes: []const u8) !void {
    try validateTarget(target);
    if (bytes.len == 0 or bytes.len > maximum_role_manifest_bytes or
        !std.unicode.utf8ValidateSlice(bytes) or std.mem.indexOfScalar(u8, bytes, 0) != null)
    {
        return error.InvalidRoleManifest;
    }

    // The generated manifest is LF-delimited and may have one final LF. A
    // second trailing LF is a blank record and must remain invalid.
    const content = if (bytes[bytes.len - 1] == '\n') bytes[0 .. bytes.len - 1] else bytes;
    if (content.len == 0 or std.mem.indexOfScalar(u8, content, '\r') != null) {
        return error.InvalidRoleManifest;
    }
    var lines = std.mem.splitScalar(u8, content, '\n');
    if (!std.mem.eql(u8, lines.next() orelse return error.InvalidRoleManifest, role_manifest_header)) {
        return error.InvalidRoleManifest;
    }
    const authenticated = lines.next() orelse return error.InvalidRoleManifest;
    if (!std.mem.eql(u8, authenticated, "authenticated=true")) {
        if (std.mem.eql(u8, authenticated, "authenticated=false")) {
            return error.UnauthenticatedRoleManifest;
        }
        return error.InvalidRoleManifest;
    }
    const target_line = lines.next() orelse return error.InvalidRoleManifest;
    if (!std.mem.startsWith(u8, target_line, "target=") or
        !std.mem.eql(u8, target_line["target=".len..], target))
    {
        return error.RoleManifestTargetMismatch;
    }

    var entries: [maximum_role_manifest_entries]RoleManifestEntry = undefined;
    var entry_count: usize = 0;
    var digest_hex: ?[]const u8 = null;
    while (lines.next()) |line| {
        if (line.len == 0) return error.InvalidRoleManifest;
        if (std.mem.startsWith(u8, line, "role=")) {
            if (digest_hex != null or entry_count == entries.len) {
                return error.UnexpectedRequiredRole;
            }
            const value = line["role=".len..];
            const separator = std.mem.indexOfScalar(u8, value, '|') orelse
                return error.InvalidRoleManifest;
            const name = value[0..separator];
            const path = value[separator + 1 ..];
            if (name.len == 0 or path.len == 0 or std.mem.indexOfScalar(u8, path, '|') != null) {
                return error.InvalidRoleManifest;
            }
            try validateRolePath(path);
            entries[entry_count] = .{ .name = name, .path = path };
            entry_count += 1;
        } else if (std.mem.startsWith(u8, line, "manifest_sha256=")) {
            if (digest_hex != null) return error.InvalidRoleManifest;
            digest_hex = line["manifest_sha256=".len..];
        } else {
            return error.InvalidRoleManifest;
        }
    }

    const supplied_hex = digest_hex orelse return error.InvalidRoleManifest;
    if (!isLowerHexDigest(supplied_hex)) return error.InvalidRoleManifest;
    var supplied_digest: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&supplied_digest, supplied_hex) catch return error.InvalidRoleManifest;
    const parsed_entries = entries[0..entry_count];
    if (!std.mem.eql(u8, &supplied_digest, &roleManifestDigest(target, parsed_entries))) {
        return error.RoleManifestDigestMismatch;
    }

    var paths: [maximum_role_manifest_entries][]const u8 = undefined;
    for (parsed_entries, 0..) |entry, index| {
        const expected_path = expectedRolePath(entry.name) orelse return error.UnexpectedRequiredRole;
        if (!std.mem.eql(u8, entry.path, expected_path)) return error.UnexpectedRequiredRole;
        paths[index] = entry.path;
    }
    try verifyRequiredRoles(target, paths[0..entry_count]);
}

fn updateRoleManifestBytes(hasher: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, @intCast(bytes.len), .little);
    hasher.update(&length);
    hasher.update(bytes);
}

fn expectedRolePath(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "UI")) return "bin/TExFlow.exe";
    if (std.mem.eql(u8, name, "PdfWorker")) return "bin/TExFlow.PdfWorker.exe";
    if (std.mem.eql(u8, name, "ScienceWorker")) return "bin/TExFlow.ScienceWorker.exe";
    return null;
}

fn validateRolePath(path: []const u8) !void {
    if (path.len == 0 or path[0] == '/' or path[0] == '\\' or
        std.mem.indexOfScalar(u8, path, '\\') != null or
        std.mem.indexOfScalar(u8, path, ':') != null) return error.InvalidRoleManifest;
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) {
            return error.InvalidRoleManifest;
        }
    }
}

fn isLowerHexDigest(value: []const u8) bool {
    if (value.len != 64) return false;
    for (value) |byte| {
        if (!((byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f'))) return false;
    }
    return true;
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
    var root = openPayloadRootNoFollow(io, path) catch |err| switch (err) {
        error.NotDir, error.FileNotFound => return error.RootNotDirectory,
        else => |e| return e,
    };
    errdefer root.close(io);
    if ((try root.stat(io)).kind != .directory) return error.RootNotDirectory;
    return root;
}

/// Open every root component with no-follow semantics. A single absolute
/// open can still follow an intermediate junction/reparse point on Windows;
/// walking from the drive/share or POSIX root makes the payload boundary
/// explicit before recursive hashing starts.
fn openPayloadRootNoFollow(io: std.Io, absolute_root: []const u8) !std.Io.Dir {
    if (comptime builtin.os.tag == .windows) {
        const parsed = std.fs.path.parsePathWindows(u8, absolute_root);
        switch (parsed.kind) {
            .drive_absolute, .unc_absolute => {
                var current = std.Io.Dir.openDirAbsolute(io, parsed.root, .{
                    .iterate = true,
                    .follow_symlinks = false,
                }) catch |err| switch (err) {
                    error.NotDir, error.FileNotFound => return err,
                    else => return error.ReparsePoint,
                };
                errdefer current.close(io);
                try validatePayloadDirectory(current, io);
                var index = parsed.root.len;
                while (index < absolute_root.len) {
                    while (index < absolute_root.len and std.fs.path.isSep(absolute_root[index])) index += 1;
                    if (index == absolute_root.len) break;
                    const start = index;
                    while (index < absolute_root.len and !std.fs.path.isSep(absolute_root[index])) index += 1;
                    const component = absolute_root[start..index];
                    if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) {
                        return error.ReproRootUnsafe;
                    }
                    var next = current.openDir(io, component, .{
                        .iterate = true,
                        .follow_symlinks = false,
                    }) catch |err| switch (err) {
                        error.NotDir, error.FileNotFound => return err,
                        else => return error.ReparsePoint,
                    };
                    validatePayloadDirectory(next, io) catch |err| {
                        next.close(io);
                        return err;
                    };
                    current.close(io);
                    current = next;
                }
                return current;
            },
            else => return error.ReproRootUnsafe,
        }
    } else {
        const parsed = std.fs.path.parsePathPosix(absolute_root);
        var current = std.Io.Dir.openDirAbsolute(io, parsed.root, .{
            .iterate = true,
            .follow_symlinks = false,
        }) catch |err| switch (err) {
            error.NotDir, error.FileNotFound => return err,
            else => return error.ReparsePoint,
        };
        errdefer current.close(io);
        try validatePayloadDirectory(current, io);
        var index = parsed.root.len;
        while (index < absolute_root.len) {
            while (index < absolute_root.len and std.fs.path.isSep(absolute_root[index])) index += 1;
            if (index == absolute_root.len) break;
            const start = index;
            while (index < absolute_root.len and !std.fs.path.isSep(absolute_root[index])) index += 1;
            const component = absolute_root[start..index];
            if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) {
                return error.ReproRootUnsafe;
            }
            var next = current.openDir(io, component, .{
                .iterate = true,
                .follow_symlinks = false,
            }) catch |err| switch (err) {
                error.NotDir, error.FileNotFound => return err,
                else => return error.ReparsePoint,
            };
            validatePayloadDirectory(next, io) catch |err| {
                next.close(io);
                return err;
            };
            current.close(io);
            current = next;
        }
        return current;
    }
}

fn validatePayloadDirectory(directory: std.Io.Dir, io: std.Io) !void {
    return switch ((try directory.stat(io)).kind) {
        .directory => {},
        .sym_link, .unknown => error.ReparsePoint,
        else => error.RootNotDirectory,
    };
}

fn validateManifestPath(path: []const u8) !void {
    if (path.len == 0 or path.len > 4096 or std.mem.indexOfScalar(u8, path, 0) != null or !std.unicode.utf8ValidateSlice(path)) {
        return error.RoleManifestPathUnsafe;
    }
    if (std.Io.Dir.path.isAbsolute(path)) {
        validateAbsolutePath(path, false) catch return error.RoleManifestPathUnsafe;
        return;
    }
    var components = std.mem.splitAny(u8, path, "/\\");
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..") or
            std.mem.indexOfAny(u8, component, ":\"*?<>|;&") != null) return error.RoleManifestPathUnsafe;
    }
}

fn readRoleManifest(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    try validateManifestPath(path);
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(maximum_role_manifest_bytes));
}

/// Explicit command-line entry point used by `main`.  `compare` requires the
/// role manifest; `compare-digest` is the intentionally weaker, digest-only
/// mode for Linux/test artifacts and cannot be mistaken for product admission.
pub fn run(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !PayloadComparison {
    const digest_only = args.len == 6 and std.mem.eql(u8, args[1], "compare-digest");
    const product_compare = args.len == 7 and std.mem.eql(u8, args[1], "compare");
    if (!digest_only and !product_compare) return error.InvalidArguments;

    const target = args[2];
    try validateTarget(target);
    try validatePayloadRootPath(args[3]);
    try validatePayloadRootPath(args[4]);
    try validateManifestPath(args[5]);
    const receipt = try std.Io.Dir.cwd().readFileAlloc(io, args[5], allocator, .limited(1024));
    defer allocator.free(receipt);
    try verifyNetworkReceipt(receipt);

    if (product_compare) {
        const manifest = try readRoleManifest(allocator, io, args[6]);
        defer allocator.free(manifest);
        try verifyRoleManifest(target, manifest);
    }
    return comparePayloadRoots(allocator, io, args[3], args[4]);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const comparison = try run(init.gpa, init.io, args);
    std.debug.print(
        "repro-check target={s} files={d} bytes={d} digest={x}\n",
        .{ args[2], comparison.left.files, comparison.left.bytes, comparison.left.digest },
    );
}
