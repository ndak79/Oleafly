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
const source_unicode = @import("source_unicode.zig");

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

pub const PayloadManifestEntry = struct {
    path: []const u8,
    size: u64,
    digest: [32]u8,
};

pub const minimum_repro_disk_bytes: u64 = 100 * 1024 * 1024 * 1024;
pub const minimum_repro_memory_bytes: u64 = 16 * 1024 * 1024 * 1024;
const maximum_payload_bytes: u64 = 8 * 1024 * 1024 * 1024;
const maximum_role_manifest_bytes: usize = 16 * 1024;
const maximum_role_manifest_entries = 8;
const maximum_payload_manifest_bytes: usize = 4 * 1024 * 1024;
const maximum_payload_manifest_entries = 65_536;
const role_manifest_header = "texflow-role-manifest-v1";
const payload_manifest_header = "texflow-payload-manifest-v1";

const canonical_network_receipt =
    "network_mode=none\n" ++
    "fetch_bytes=0\n" ++
    "route_count=0\n" ++
    "proxy=unset\n" ++
    "process_policy=zig-owned\n";

const bound_network_receipt_header = "texflow-repro-receipt-v2";

/// Values supplied by the build graph from the exact checked-out commit and
/// the current GitHub run. The combined lane accepts no unbound receipt.
pub const ReproBinding = struct {
    target: []const u8,
    source_commit: []const u8,
    source_set_sha256: []const u8,
    dependency_lock_sha256: []const u8,
    build_identity: []const u8,
    remote_run_id: []const u8,
    remote_run_attempt: []const u8,
};

pub const BoundNetworkReceipt = struct {
    target: []const u8,
    source_commit: []const u8,
    source_set_sha256: [32]u8,
    dependency_lock_sha256: [32]u8,
    build_identity: [32]u8,
    remote_run_id: []const u8,
    remote_run_attempt: []const u8,
    role_manifest_sha256: [32]u8,
    payload_manifest_sha256: [32]u8,
    product_left: PayloadSummary,
    product_right: PayloadSummary,
    test_left: PayloadSummary,
    test_right: PayloadSummary,
};

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
    if (comptime builtin.os.tag == .windows) {
        // Reproduction payloads and manifests must stay on a local volume;
        // rooted, drive-relative, device, and UNC paths could resolve through
        // ambient state or a network share and invalidate the no-network gate.
        if (std.fs.path.parsePathWindows(u8, path).kind != .drive_absolute) {
            return error.ReproRootUnsafe;
        }
    }
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
            if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..") or
                hasReservedWindowsDevice(component) or
                component[component.len - 1] == ' ' or component[component.len - 1] == '.')
            {
                return error.ReproRootUnsafe;
            }
        }
        component_start = index + 1;
    }
    if (component_start >= path.len or
        std.mem.eql(u8, path[component_start..], ".") or
        std.mem.eql(u8, path[component_start..], "..") or
        hasReservedWindowsDevice(path[component_start..]) or
        path[path.len - 1] == ' ' or path[path.len - 1] == '.')
    {
        return error.ReproRootUnsafe;
    }
}

/// Return a conservative comparison key for a payload root. The filesystem
/// walk still opens every component with no-follow semantics; this key only
/// closes the evidence shortcut where two labels name the same root (or one
/// root is nested below the other) through separator/case/Unicode aliases.
fn canonicalPayloadRootKey(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var normalized: std.ArrayList(u8) = .empty;
    defer normalized.deinit(allocator);
    var previous_separator = false;
    for (path) |byte| {
        if (byte == '/' or byte == '\\') {
            if (previous_separator) continue;
            try normalized.append(allocator, '/');
            previous_separator = true;
        } else {
            try normalized.append(allocator, byte);
            previous_separator = false;
        }
    }
    return source_unicode.foldNfd(allocator, normalized.items, 64 * 1024);
}

fn rootKeysOverlap(left: []const u8, right: []const u8) bool {
    const shorter = if (left.len <= right.len) left else right;
    const longer = if (left.len <= right.len) right else left;
    return std.mem.eql(u8, left, right) or
        (std.mem.startsWith(u8, longer, shorter) and
            longer.len > shorter.len and longer[shorter.len] == '/');
}

fn requireDisjointPayloadRoots(allocator: std.mem.Allocator, roots: []const []const u8) !void {
    var keys: std.ArrayList([]u8) = .empty;
    defer {
        for (keys.items) |key| allocator.free(key);
        keys.deinit(allocator);
    }
    for (roots) |path| {
        try validatePayloadRootPath(path);
        const key = try canonicalPayloadRootKey(allocator, path);
        keys.append(allocator, key) catch |err| {
            allocator.free(key);
            return err;
        };
    }
    for (keys.items, 0..) |left, index| {
        for (keys.items[index + 1 ..]) |right| {
            if (rootKeysOverlap(left, right)) return error.ReproRootsOverlap;
        }
    }
}

/// Lexical aliases are not enough on filesystems with junctions, bind mounts,
/// or other non-lexical aliases. Open every root through the no-follow walker
/// and compare the filesystem identity of the opened directory itself.
fn requireDistinctPayloadRootObjects(io: std.Io, paths: []const []const u8) !void {
    if (paths.len > 4) return error.TooManyReproRoots;
    var roots: [4]std.Io.Dir = undefined;
    var root_count: usize = 0;
    defer for (roots[0..root_count]) |*root| root.close(io);

    for (paths) |path| {
        roots[root_count] = try openPayloadRoot(io, path);
        root_count += 1;
    }

    var identities: [4]std.Io.File.INode = undefined;
    for (roots[0..root_count], 0..) |root, index| {
        const stat = try root.stat(io);
        if (stat.inode == 0) return error.RootIdentityUnavailable;
        identities[index] = stat.inode;
        for (identities[0..index]) |identity| {
            if (identity == stat.inode) return error.ReproRootsOverlap;
        }
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
        if (paths.len != 0) return error.UnexpectedLinuxProduct;
        return;
    }
    try validateTarget(target);
    // T0.2c ships only the UI executable. Worker role names remain reserved
    // for the later worker tasks and must not be admitted prematurely.
    const required = [_][]const u8{"bin/TExFlow.exe"};
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

/// Hash the exact regular-file records in canonical path order.  This is the
/// same record format used by the materialized-tree walker in `deps`.
pub fn payloadTreeDigest(entries: []const PayloadManifestEntry) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var size_buffer: [32]u8 = undefined;
    for (entries) |entry| {
        hasher.update(entry.path);
        hasher.update("\t");
        const size_text = std.fmt.bufPrint(&size_buffer, "{d}", .{entry.size}) catch unreachable;
        hasher.update(size_text);
        hasher.update("\t");
        const digest_hex = std.fmt.bytesToHex(entry.digest, .lower);
        hasher.update(&digest_hex);
        hasher.update("\n");
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

/// Hashes the authenticated, complete payload manifest, including the
/// materialized-tree summary.  The parser requires entries to be sorted before
/// this digest is accepted, so a caller cannot reorder equivalent records.
pub fn payloadManifestDigest(
    target: []const u8,
    entries: []const PayloadManifestEntry,
    tree: PayloadSummary,
) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("texflow-payload-manifest-v1\x00");
    updateRoleManifestBytes(&hasher, target);
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, @intCast(entries.len), .little);
    hasher.update(&count);
    for (entries) |entry| {
        updateRoleManifestBytes(&hasher, entry.path);
        var size: [8]u8 = undefined;
        std.mem.writeInt(u64, &size, entry.size, .little);
        hasher.update(&size);
        hasher.update(&entry.digest);
    }
    var files: [4]u8 = undefined;
    std.mem.writeInt(u32, &files, tree.files, .little);
    hasher.update(&files);
    std.mem.writeInt(u64, &count, tree.bytes, .little);
    hasher.update(&count);
    hasher.update(&tree.digest);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

const ParsedPayloadManifest = struct {
    entries: std.ArrayList(PayloadManifestEntry),
    tree: PayloadSummary,

    fn deinit(self: *ParsedPayloadManifest, allocator: std.mem.Allocator) void {
        self.entries.deinit(allocator);
    }
};

fn parsePayloadManifest(
    allocator: std.mem.Allocator,
    target: []const u8,
    bytes: []const u8,
) !ParsedPayloadManifest {
    try validateTarget(target);
    if (bytes.len == 0 or bytes.len > maximum_payload_manifest_bytes or
        !std.unicode.utf8ValidateSlice(bytes) or std.mem.indexOfScalar(u8, bytes, 0) != null)
    {
        return error.InvalidPayloadManifest;
    }
    const content = if (bytes[bytes.len - 1] == '\n') bytes[0 .. bytes.len - 1] else bytes;
    if (content.len == 0 or std.mem.indexOfScalar(u8, content, '\r') != null) {
        return error.InvalidPayloadManifest;
    }

    var lines = std.mem.splitScalar(u8, content, '\n');
    if (!std.mem.eql(u8, lines.next() orelse return error.InvalidPayloadManifest, payload_manifest_header)) {
        return error.InvalidPayloadManifest;
    }
    const authenticated = lines.next() orelse return error.InvalidPayloadManifest;
    if (!std.mem.eql(u8, authenticated, "authenticated=true")) {
        if (std.mem.eql(u8, authenticated, "authenticated=false")) {
            return error.UnauthenticatedPayloadManifest;
        }
        return error.InvalidPayloadManifest;
    }
    const target_line = lines.next() orelse return error.InvalidPayloadManifest;
    if (!std.mem.startsWith(u8, target_line, "target=") or
        !std.mem.eql(u8, target_line["target=".len..], target))
    {
        return error.PayloadManifestTargetMismatch;
    }

    var parsed = ParsedPayloadManifest{
        .entries = .empty,
        .tree = undefined,
    };
    errdefer parsed.deinit(allocator);
    var tree_seen = false;
    var digest_hex: ?[]const u8 = null;
    while (lines.next()) |line| {
        if (line.len == 0) return error.InvalidPayloadManifest;
        if (std.mem.startsWith(u8, line, "member=")) {
            if (tree_seen or digest_hex != null or parsed.entries.items.len == maximum_payload_manifest_entries) {
                return error.InvalidPayloadManifest;
            }
            const value = line["member=".len..];
            const first = std.mem.indexOfScalar(u8, value, '|') orelse
                return error.InvalidPayloadManifest;
            const rest = value[first + 1 ..];
            const second_relative = std.mem.indexOfScalar(u8, rest, '|') orelse
                return error.InvalidPayloadManifest;
            const second = first + 1 + second_relative;
            if (std.mem.indexOfScalar(u8, rest[second_relative + 1 ..], '|') != null) {
                return error.InvalidPayloadManifest;
            }
            const path = value[0..first];
            deps.validateArchivePath(path) catch return error.InvalidPayloadManifest;
            if (parsed.entries.items.len != 0 and
                std.mem.order(u8, parsed.entries.items[parsed.entries.items.len - 1].path, path) != .lt)
            {
                return error.InvalidPayloadManifest;
            }
            const size = parseDecimal(u64, value[first + 1 .. second]) catch
                return error.InvalidPayloadManifest;
            const digest_text = value[second + 1 ..];
            if (!isLowerHexDigest(digest_text)) return error.InvalidPayloadManifest;
            var digest: [32]u8 = undefined;
            _ = std.fmt.hexToBytes(&digest, digest_text) catch return error.InvalidPayloadManifest;
            try parsed.entries.append(allocator, .{ .path = path, .size = size, .digest = digest });
        } else if (std.mem.startsWith(u8, line, "tree=")) {
            if (tree_seen or digest_hex != null) return error.InvalidPayloadManifest;
            const value = line["tree=".len..];
            const first = std.mem.indexOfScalar(u8, value, '|') orelse
                return error.InvalidPayloadManifest;
            const rest = value[first + 1 ..];
            const second_relative = std.mem.indexOfScalar(u8, rest, '|') orelse
                return error.InvalidPayloadManifest;
            const second = first + 1 + second_relative;
            if (std.mem.indexOfScalar(u8, rest[second_relative + 1 ..], '|') != null) {
                return error.InvalidPayloadManifest;
            }
            const files = parseDecimal(u32, value[0..first]) catch
                return error.InvalidPayloadManifest;
            const bytes_value = parseDecimal(u64, value[first + 1 .. second]) catch
                return error.InvalidPayloadManifest;
            const digest_text = value[second + 1 ..];
            if (!isLowerHexDigest(digest_text)) return error.InvalidPayloadManifest;
            var digest: [32]u8 = undefined;
            _ = std.fmt.hexToBytes(&digest, digest_text) catch return error.InvalidPayloadManifest;
            parsed.tree = .{ .files = files, .bytes = bytes_value, .digest = digest };
            tree_seen = true;
        } else if (std.mem.startsWith(u8, line, "manifest_sha256=")) {
            if (!tree_seen or digest_hex != null) return error.InvalidPayloadManifest;
            digest_hex = line["manifest_sha256=".len..];
        } else {
            return error.InvalidPayloadManifest;
        }
    }
    const supplied_hex = digest_hex orelse return error.InvalidPayloadManifest;
    if (!tree_seen or !isLowerHexDigest(supplied_hex)) return error.InvalidPayloadManifest;
    if (parsed.tree.files != parsed.entries.items.len) return error.InvalidPayloadManifest;
    var total: u64 = 0;
    for (parsed.entries.items) |entry| {
        total = std.math.add(u64, total, entry.size) catch return error.InvalidPayloadManifest;
    }
    if (total != parsed.tree.bytes or total > maximum_payload_bytes or
        !std.mem.eql(u8, &parsed.tree.digest, &payloadTreeDigest(parsed.entries.items)))
    {
        return error.InvalidPayloadManifest;
    }
    var registry = deps.PathRegistry.initWithFold(allocator, source_unicode.foldNfd);
    defer registry.deinit();
    for (parsed.entries.items) |entry| {
        registry.add(entry.path) catch return error.PayloadManifestPathCollision;
    }
    try verifyPayloadMembers(target, parsed.entries.items);
    var supplied_digest: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&supplied_digest, supplied_hex) catch return error.InvalidPayloadManifest;
    if (!std.mem.eql(u8, &supplied_digest, &payloadManifestDigest(target, parsed.entries.items, parsed.tree))) {
        return error.PayloadManifestDigestMismatch;
    }
    return parsed;
}

pub fn verifyPayloadManifest(target: []const u8, bytes: []const u8) !void {
    var parsed = try parsePayloadManifest(std.heap.page_allocator, target, bytes);
    parsed.deinit(std.heap.page_allocator);
}

fn parseDecimal(comptime T: type, bytes: []const u8) !T {
    if (bytes.len == 0 or (bytes.len > 1 and bytes[0] == '0')) return error.InvalidDecimal;
    for (bytes) |byte| if (byte < '0' or byte > '9') return error.InvalidDecimal;
    return std.fmt.parseUnsigned(T, bytes, 10);
}

fn verifyPayloadMembers(target: []const u8, entries: []const PayloadManifestEntry) !void {
    if (std.mem.eql(u8, target, "x86_64-linux-gnu")) {
        if (entries.len != 0) return error.UnexpectedLinuxProduct;
        return;
    }
    const required = [_][]const u8{"bin/TExFlow.exe"};
    for (required) |path| {
        var found = false;
        for (entries) |entry| {
            if (std.mem.eql(u8, entry.path, path)) {
                found = true;
                break;
            }
        }
        if (!found) return error.MissingRequiredRole;
    }
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

fn parseLowerDigest(value: []const u8) ![32]u8 {
    if (!isLowerHexDigest(value)) return error.BoundReceiptInvalid;
    var digest: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&digest, value) catch return error.BoundReceiptInvalid;
    return digest;
}

fn hashBytes(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

fn validatePositiveDecimal(value: []const u8) !void {
    const parsed = parseDecimal(u64, value) catch return error.BoundReceiptInvalid;
    if (parsed == 0) return error.BoundReceiptInvalid;
}

fn parseBoundSummary(value: []const u8) !PayloadSummary {
    const first = std.mem.indexOfScalar(u8, value, '|') orelse return error.BoundReceiptInvalid;
    const rest = value[first + 1 ..];
    const second_relative = std.mem.indexOfScalar(u8, rest, '|') orelse return error.BoundReceiptInvalid;
    const second = first + 1 + second_relative;
    if (std.mem.indexOfScalar(u8, rest[second_relative + 1 ..], '|') != null) {
        return error.BoundReceiptInvalid;
    }
    const files = parseDecimal(u32, value[0..first]) catch return error.BoundReceiptInvalid;
    const bytes = parseDecimal(u64, value[first + 1 .. second]) catch return error.BoundReceiptInvalid;
    const digest = try parseLowerDigest(value[second + 1 ..]);
    return .{ .files = files, .bytes = bytes, .digest = digest };
}

fn samePayloadSummary(left: PayloadSummary, right: PayloadSummary) bool {
    return left.files == right.files and left.bytes == right.bytes and
        std.mem.eql(u8, &left.digest, &right.digest);
}

fn validateReproBinding(binding: ReproBinding) !void {
    try validateTarget(binding.target);
    if (binding.source_commit.len != 40) return error.BoundReceiptInvalid;
    for (binding.source_commit) |byte| {
        if (!((byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f'))) {
            return error.BoundReceiptInvalid;
        }
    }
    for ([_][]const u8{
        binding.source_set_sha256,
        binding.dependency_lock_sha256,
        binding.build_identity,
    }) |digest| {
        if (!isLowerHexDigest(digest)) return error.BoundReceiptInvalid;
    }
    try validatePositiveDecimal(binding.remote_run_id);
    try validatePositiveDecimal(binding.remote_run_attempt);
}

/// Validate the strict receipt consumed by `compare-both`. It binds the raw
/// manifest bytes and the exact source/run identity to the five network policy
/// fields. The network fields remain evidence supplied by the qualified
/// runner; this function does not pretend that a text file can observe host
/// networking by itself.
pub fn verifyBoundNetworkReceipt(
    bytes: []const u8,
    binding: ReproBinding,
    role_manifest_bytes: []const u8,
    payload_manifest_bytes: []const u8,
) !BoundNetworkReceipt {
    try validateReproBinding(binding);
    if (bytes.len == 0 or bytes.len > maximum_role_manifest_bytes or
        bytes[bytes.len - 1] != '\n' or !std.unicode.utf8ValidateSlice(bytes) or
        std.mem.indexOfScalar(u8, bytes, 0) != null or
        std.mem.indexOfScalar(u8, bytes, '\r') != null)
    {
        return error.BoundReceiptInvalid;
    }

    const content = bytes[0 .. bytes.len - 1];
    var lines = std.mem.splitScalar(u8, content, '\n');
    if (!std.mem.eql(u8, lines.next() orelse return error.BoundReceiptInvalid, bound_network_receipt_header)) {
        return error.BoundReceiptInvalid;
    }
    const prefixes = [_][]const u8{
        "target=",
        "source_commit=",
        "source_set_sha256=",
        "dependency_lock_sha256=",
        "build_identity=",
        "remote_run_id=",
        "remote_run_attempt=",
        "role_manifest_sha256=",
        "payload_manifest_sha256=",
        "product_left=",
        "product_right=",
        "test_left=",
        "test_right=",
        "network_mode=",
        "fetch_bytes=",
        "route_count=",
        "proxy=",
        "process_policy=",
        "receipt_sha256=",
    };
    var values: [prefixes.len][]const u8 = undefined;
    for (prefixes, 0..) |prefix, index| {
        const line = lines.next() orelse return error.BoundReceiptInvalid;
        if (!std.mem.startsWith(u8, line, prefix)) return error.BoundReceiptInvalid;
        values[index] = line[prefix.len..];
        if (values[index].len == 0) return error.BoundReceiptInvalid;
    }
    if (lines.next() != null) return error.BoundReceiptInvalid;

    if (!std.mem.eql(u8, values[0], binding.target) or
        !std.mem.eql(u8, values[1], binding.source_commit) or
        !std.mem.eql(u8, values[2], binding.source_set_sha256) or
        !std.mem.eql(u8, values[3], binding.dependency_lock_sha256) or
        !std.mem.eql(u8, values[4], binding.build_identity) or
        !std.mem.eql(u8, values[5], binding.remote_run_id) or
        !std.mem.eql(u8, values[6], binding.remote_run_attempt))
    {
        return error.ReproEvidenceBindingMismatch;
    }
    try validatePositiveDecimal(values[5]);
    try validatePositiveDecimal(values[6]);

    if (!std.mem.eql(u8, values[13], "none")) return error.NetworkIsolationUnverified;
    if (!std.mem.eql(u8, values[14], "0") or !std.mem.eql(u8, values[15], "0") or
        !std.mem.eql(u8, values[16], "unset") or !std.mem.eql(u8, values[17], "zig-owned"))
    {
        return error.NetworkReceiptMismatch;
    }

    const receipt_digest = try parseLowerDigest(values[18]);
    const prefix_end = (std.mem.lastIndexOfScalar(u8, content, '\n') orelse
        return error.BoundReceiptInvalid) + 1;
    if (!std.mem.eql(u8, &receipt_digest, &hashBytes(bytes[0..prefix_end]))) {
        return error.BoundReceiptDigestMismatch;
    }

    const parsed = BoundNetworkReceipt{
        .target = values[0],
        .source_commit = values[1],
        .source_set_sha256 = try parseLowerDigest(values[2]),
        .dependency_lock_sha256 = try parseLowerDigest(values[3]),
        .build_identity = try parseLowerDigest(values[4]),
        .remote_run_id = values[5],
        .remote_run_attempt = values[6],
        .role_manifest_sha256 = try parseLowerDigest(values[7]),
        .payload_manifest_sha256 = try parseLowerDigest(values[8]),
        .product_left = try parseBoundSummary(values[9]),
        .product_right = try parseBoundSummary(values[10]),
        .test_left = try parseBoundSummary(values[11]),
        .test_right = try parseBoundSummary(values[12]),
    };
    if (!std.mem.eql(u8, &parsed.role_manifest_sha256, &hashBytes(role_manifest_bytes)) or
        !std.mem.eql(u8, &parsed.payload_manifest_sha256, &hashBytes(payload_manifest_bytes)))
    {
        return error.ReproEvidenceBindingMismatch;
    }
    return parsed;
}

pub fn verifyBoundNetworkReceiptSummaries(
    receipt: BoundNetworkReceipt,
    product: PayloadComparison,
    test_artifact: PayloadComparison,
) !void {
    if (!samePayloadSummary(receipt.product_left, product.left) or
        !samePayloadSummary(receipt.product_right, product.right) or
        !samePayloadSummary(receipt.test_left, test_artifact.left) or
        !samePayloadSummary(receipt.test_right, test_artifact.right))
    {
        return error.ReproEvidenceBindingMismatch;
    }
}

pub fn comparePayloadRoots(
    allocator: std.mem.Allocator,
    io: std.Io,
    left_path: []const u8,
    right_path: []const u8,
) !PayloadComparison {
    try requireDisjointPayloadRoots(allocator, &.{ left_path, right_path });
    try requireDistinctPayloadRootObjects(io, &.{ left_path, right_path });
    var left_root = openPayloadRoot(io, left_path) catch |err| return err;
    defer left_root.close(io);
    var right_root = openPayloadRoot(io, right_path) catch |err| return err;
    defer right_root.close(io);

    const left = try deps.hashMaterializedDirectoryWithFold(
        allocator,
        io,
        left_root,
        maximum_payload_bytes,
        source_unicode.foldNfd,
    );
    const right = try deps.hashMaterializedDirectoryWithFold(
        allocator,
        io,
        right_root,
        maximum_payload_bytes,
        source_unicode.foldNfd,
    );
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

fn expectedTestArtifactPath(target: []const u8) []const u8 {
    return if (std.mem.eql(u8, target, "x86_64-windows-msvc"))
        "texflow_abi.lib"
    else
        "libtexflow_abi.a";
}

const TestArtifactVerifier = struct {
    target: []const u8,
    seen: bool,
};

fn visitTestArtifactRecord(context: *anyopaque, record: deps.MaterializedFileRecord) anyerror!void {
    const verifier: *TestArtifactVerifier = @ptrCast(@alignCast(context));
    if (verifier.seen or !std.mem.eql(u8, record.path, expectedTestArtifactPath(verifier.target))) {
        return error.UnexpectedTestArtifactMember;
    }
    verifier.seen = true;
}

/// Compare the cache-only ABI artifact separately from the installed product
/// payload. A single exact archive member is admitted; product files or a
/// broad cache directory cannot masquerade as this test-only lane.
pub fn compareTestArtifactRoots(
    allocator: std.mem.Allocator,
    io: std.Io,
    target: []const u8,
    left_path: []const u8,
    right_path: []const u8,
) !PayloadComparison {
    try validateTarget(target);
    try requireDisjointPayloadRoots(allocator, &.{ left_path, right_path });
    try requireDistinctPayloadRootObjects(io, &.{ left_path, right_path });
    var left_root = try openPayloadRoot(io, left_path);
    defer left_root.close(io);
    var right_root = try openPayloadRoot(io, right_path);
    defer right_root.close(io);

    var left_verifier = TestArtifactVerifier{ .target = target, .seen = false };
    const left = try deps.hashMaterializedDirectoryWithFoldAndVisitor(
        allocator,
        io,
        left_root,
        maximum_payload_bytes,
        source_unicode.foldNfd,
        visitTestArtifactRecord,
        @ptrCast(&left_verifier),
    );
    if (!left_verifier.seen or left.files != 1) return error.MissingTestArtifact;

    var right_verifier = TestArtifactVerifier{ .target = target, .seen = false };
    const right = try deps.hashMaterializedDirectoryWithFoldAndVisitor(
        allocator,
        io,
        right_root,
        maximum_payload_bytes,
        source_unicode.foldNfd,
        visitTestArtifactRecord,
        @ptrCast(&right_verifier),
    );
    if (!right_verifier.seen or right.files != 1) return error.MissingTestArtifact;

    const comparison = PayloadComparison{
        .left = .{ .files = left.files, .bytes = left.bytes, .digest = left.digest },
        .right = .{ .files = right.files, .bytes = right.bytes, .digest = right.digest },
    };
    if (comparison.left.bytes != comparison.right.bytes or
        !std.mem.eql(u8, &comparison.left.digest, &comparison.right.digest))
    {
        return error.TestArtifactMismatch;
    }
    return comparison;
}

pub fn comparePayloadRootsWithManifest(
    allocator: std.mem.Allocator,
    io: std.Io,
    target: []const u8,
    left_path: []const u8,
    right_path: []const u8,
    manifest_bytes: []const u8,
) !PayloadComparison {
    try requireDisjointPayloadRoots(allocator, &.{ left_path, right_path });
    try requireDistinctPayloadRootObjects(io, &.{ left_path, right_path });
    var manifest = try parsePayloadManifest(allocator, target, manifest_bytes);
    defer manifest.deinit(allocator);

    var left_root = openPayloadRoot(io, left_path) catch |err| return err;
    defer left_root.close(io);
    var right_root = openPayloadRoot(io, right_path) catch |err| return err;
    defer right_root.close(io);

    const left = try hashPayloadRootAgainstManifest(allocator, io, left_root, manifest.entries.items, manifest.tree);
    const right = try hashPayloadRootAgainstManifest(allocator, io, right_root, manifest.entries.items, manifest.tree);
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

const PayloadRootVerifier = struct {
    expected: []const PayloadManifestEntry,
    seen: []bool,
    by_path: std.StringHashMap(usize),
};

fn visitPayloadRecord(context: *anyopaque, record: deps.MaterializedFileRecord) anyerror!void {
    const verifier: *PayloadRootVerifier = @ptrCast(@alignCast(context));
    const index = verifier.by_path.get(record.path) orelse return error.PayloadManifestExtraMember;
    if (verifier.seen[index]) return error.PayloadManifestDuplicateMember;
    const expected = verifier.expected[index];
    if (record.size != expected.size or !std.mem.eql(u8, &record.digest, &expected.digest)) {
        return error.PayloadManifestMemberMismatch;
    }
    verifier.seen[index] = true;
}

fn hashPayloadRootAgainstManifest(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
    expected: []const PayloadManifestEntry,
    tree: PayloadSummary,
) !deps.MaterializedDirectorySummary {
    var by_path = std.StringHashMap(usize).init(allocator);
    defer by_path.deinit();
    for (expected, 0..) |entry, index| {
        try by_path.put(entry.path, index);
    }
    const seen = try allocator.alloc(bool, expected.len);
    defer allocator.free(seen);
    @memset(seen, false);
    var verifier = PayloadRootVerifier{
        .expected = expected,
        .seen = seen,
        .by_path = by_path,
    };
    const actual = try deps.hashMaterializedDirectoryWithFoldAndVisitor(
        allocator,
        io,
        root,
        maximum_payload_bytes,
        source_unicode.foldNfd,
        visitPayloadRecord,
        @ptrCast(&verifier),
    );
    for (seen) |was_seen| if (!was_seen) return error.PayloadManifestMissingMember;
    if (actual.files != tree.files or actual.bytes != tree.bytes or
        !std.mem.eql(u8, &actual.digest, &tree.digest))
    {
        return error.PayloadManifestMismatch;
    }
    return actual;
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
            .drive_absolute => {
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
    if (!std.Io.Dir.path.isAbsolute(path)) return error.RoleManifestPathUnsafe;
    validateAbsolutePath(path, false) catch return error.RoleManifestPathUnsafe;
    const has_drive_prefix = path.len >= 2 and
        ((path[0] >= 'a' and path[0] <= 'z') or (path[0] >= 'A' and path[0] <= 'Z')) and
        path[1] == ':';
    var component_start: usize = if (has_drive_prefix) 2 else 0;
    var index: usize = component_start;
    while (index <= path.len) : (index += 1) {
        if (index != path.len and !std.fs.path.isSep(path[index])) continue;
        if (index > component_start) {
            const component = path[component_start..index];
            if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..") or
                std.mem.indexOfAny(u8, component, ":\"*?<>|;&") != null or
                hasReservedWindowsDevice(component) or
                component[component.len - 1] == ' ' or component[component.len - 1] == '.')
            {
                return error.RoleManifestPathUnsafe;
            }
        }
        component_start = index + 1;
    }
}

fn hasReservedWindowsDevice(component: []const u8) bool {
    var end = component.len;
    while (end != 0 and (component[end - 1] == ' ' or component[end - 1] == '.')) end -= 1;
    if (end == 0) return true;
    const stem_end = std.mem.indexOfScalar(u8, component[0..end], '.') orelse end;
    const stem = component[0..stem_end];
    return std.ascii.eqlIgnoreCase(stem, "con") or
        std.ascii.eqlIgnoreCase(stem, "prn") or
        std.ascii.eqlIgnoreCase(stem, "aux") or
        std.ascii.eqlIgnoreCase(stem, "nul") or
        (stem.len == 4 and std.ascii.eqlIgnoreCase(stem[0..3], "com") and stem[3] >= '1' and stem[3] <= '9') or
        (stem.len == 4 and std.ascii.eqlIgnoreCase(stem[0..3], "lpt") and stem[3] >= '1' and stem[3] <= '9');
}

fn openManifestParentNoFollow(io: std.Io, path: []const u8) !std.Io.Dir {
    try validateManifestPath(path);
    const parent_path = std.fs.path.dirname(path) orelse return error.RoleManifestPathUnsafe;
    return openPayloadRootNoFollow(io, parent_path);
}

fn readManifestFileAlloc(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    maximum_bytes: usize,
) ![]u8 {
    var parent = try openManifestParentNoFollow(io, path);
    defer parent.close(io);
    const basename = std.fs.path.basename(path);
    var identity = try parent.openFile(io, basename, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    });
    defer identity.close(io);
    const before = try identity.stat(io);
    if (before.kind != .file) return error.RoleManifestPathUnsafe;
    var file = try parent.openFile(io, basename, .{
        .allow_directory = false,
        .follow_symlinks = true,
        .resolve_beneath = true,
    });
    defer file.close(io);
    const opened = try file.stat(io);
    if (opened.kind != .file or opened.inode != before.inode or opened.size != before.size) {
        return error.RoleManifestPathUnsafe;
    }
    var reader_buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(io, &reader_buffer);
    const result = reader.interface.allocRemaining(allocator, .limited(maximum_bytes)) catch |err| switch (err) {
        error.ReadFailed => return reader.err orelse error.ReadFailed,
        else => return err,
    };
    const after = try file.stat(io);
    if (after.kind != .file or after.inode != before.inode or after.size != before.size or result.len != before.size) {
        allocator.free(result);
        return error.RoleManifestPathUnsafe;
    }
    return result;
}

/// Explicit command-line entry point used by `main`.  `compare` requires both
/// the authenticated role manifest and the complete payload manifest;
/// `compare-test` is the exact cache-only ABI lane; and `compare-both` runs
/// both lanes in one process after checking all four roots are disjoint and
/// binding the receipt to the exact source/run/manifests.
/// `compare-digest` remains the intentionally weaker compatibility mode and
/// cannot be mistaken for product admission.
pub fn run(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !PayloadComparison {
    const digest_only = args.len == 6 and std.mem.eql(u8, args[1], "compare-digest");
    const test_compare = args.len == 6 and std.mem.eql(u8, args[1], "compare-test");
    const product_compare = args.len == 8 and std.mem.eql(u8, args[1], "compare");
    const combined_compare = args.len == 16 and std.mem.eql(u8, args[1], "compare-both");
    if (!digest_only and !test_compare and !product_compare and !combined_compare) return error.InvalidArguments;

    const target = args[2];
    try validateTarget(target);
    if ((std.mem.eql(u8, target, "x86_64-windows-msvc") and builtin.os.tag != .windows) or
        (std.mem.eql(u8, target, "x86_64-linux-gnu") and builtin.os.tag != .linux))
    {
        return error.ReproHostTargetMismatch;
    }
    try validatePayloadRootPath(args[3]);
    try validatePayloadRootPath(args[4]);
    if (combined_compare) {
        try validatePayloadRootPath(args[5]);
        try validatePayloadRootPath(args[6]);
        try requireDisjointPayloadRoots(allocator, args[3..7]);
        try requireDistinctPayloadRootObjects(io, args[3..7]);
    }
    const receipt_index: usize = if (combined_compare) 7 else 5;
    try validateManifestPath(args[receipt_index]);
    const receipt = try readManifestFileAlloc(allocator, io, args[receipt_index], maximum_role_manifest_bytes);
    defer allocator.free(receipt);
    if (!combined_compare) try verifyNetworkReceipt(receipt);

    if (test_compare) return compareTestArtifactRoots(allocator, io, target, args[3], args[4]);

    if (combined_compare) {
        const manifest = try readManifestFileAlloc(allocator, io, args[8], maximum_role_manifest_bytes);
        defer allocator.free(manifest);
        const payload_manifest = try readManifestFileAlloc(allocator, io, args[9], maximum_payload_manifest_bytes);
        defer allocator.free(payload_manifest);
        const bound_receipt = try verifyBoundNetworkReceipt(receipt, .{
            .target = args[2],
            .source_commit = args[10],
            .source_set_sha256 = args[11],
            .dependency_lock_sha256 = args[12],
            .build_identity = args[13],
            .remote_run_id = args[14],
            .remote_run_attempt = args[15],
        }, manifest, payload_manifest);
        try verifyRoleManifest(target, manifest);
        const product = try comparePayloadRootsWithManifest(
            allocator,
            io,
            target,
            args[3],
            args[4],
            payload_manifest,
        );
        const test_artifact = try compareTestArtifactRoots(allocator, io, target, args[5], args[6]);
        try verifyBoundNetworkReceiptSummaries(bound_receipt, product, test_artifact);
        return product;
    }

    if (product_compare) {
        const manifest = try readManifestFileAlloc(allocator, io, args[6], maximum_role_manifest_bytes);
        defer allocator.free(manifest);
        try verifyRoleManifest(target, manifest);
        const payload_manifest = try readManifestFileAlloc(allocator, io, args[7], maximum_payload_manifest_bytes);
        defer allocator.free(payload_manifest);
        return comparePayloadRootsWithManifest(
            allocator,
            io,
            target,
            args[3],
            args[4],
            payload_manifest,
        );
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
