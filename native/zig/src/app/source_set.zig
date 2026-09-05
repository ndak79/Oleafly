//! Canonical source-set v2 model. Callers provide already sorted, raw Git-style
//! paths, modes, content lengths and blob SHA-256 values. This module neither
//! enumerates Git/the filesystem nor reads content or verifies supplied blobs.
//! Unicode-17 NFD/full case folding detects portable path collisions, but never
//! changes the bytes hashed. No native APIs, controller, or capture integration.
const std = @import("std");
const unicode = @import("unicode");

pub const digest_bytes = 32;
pub const domain = "texflow:source-set:v2\x00";

pub const Entry = struct {
    path: []const u8,
    mode: []const u8,
    // This type excludes content lengths above the wire format's u64 maximum.
    content_length: u64,
    blob_sha256: [digest_bytes]u8,
};

/// SHA-256(domain || u64_le count || entries), where each entry is
/// u32_le path-byte-length || raw path || six-byte mode || u64_le content-length
/// || raw blob SHA-256. Entries are validated, never sorted or normalized.
/// The allocator owns only temporary collision keys; no allocation escapes.
/// Compose the result with build_identity.compute(result, lock_sha256) for the
/// unchanged, role-neutral v1 build identity.
pub fn digest(allocator: std.mem.Allocator, entries: []const Entry) ![digest_bytes]u8 {
    const count = std.math.cast(u64, entries.len) orelse return error.EntryCountOverflow;
    for (entries, 0..) |entry, index| {
        try validatePath(entry.path);
        if (!std.mem.eql(u8, entry.mode, "100644") and !std.mem.eql(u8, entry.mode, "100755")) {
            return error.InvalidMode;
        }
        if (index > 0) switch (std.mem.order(u8, entries[index - 1].path, entry.path)) {
            .lt => {},
            .eq => return error.DuplicatePath,
            .gt => return error.UnsortedPaths,
        };
    }

    var keys = std.StringHashMap(void).init(allocator);
    defer {
        var iterator = keys.keyIterator();
        while (iterator.next()) |key| allocator.free(key.*);
        keys.deinit();
    }

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(domain);
    var wide: [8]u8 = undefined;
    std.mem.writeInt(u64, &wide, count, .little);
    hasher.update(&wide);
    for (entries) |entry| {
        // Canonical equivalents share NFD; full folding also catches non-ASCII
        // case aliases. No arbitrary path expansion cap changes the format;
        // callers can bound resources using their injected allocator.
        const key = try unicode.foldNfd(allocator, entry.path, std.math.maxInt(usize));
        errdefer allocator.free(key);
        const inserted = try keys.getOrPut(key);
        if (inserted.found_existing) return error.PathCollision;

        var path_length: [4]u8 = undefined;
        std.mem.writeInt(u32, &path_length, @intCast(entry.path.len), .little);
        hasher.update(&path_length);
        hasher.update(entry.path);
        hasher.update(entry.mode);
        std.mem.writeInt(u64, &wide, entry.content_length, .little);
        hasher.update(&wide);
        hasher.update(&entry.blob_sha256);
    }
    // Complete the file map before checking directory prefixes: raw path order
    // does not imply folded order, so an aliased child may precede its file.
    // One lookup per slash avoids comparing every pair of entries. Prefixes
    // borrow the owned key only during lookup; no extra allocations escape.
    var paths = keys.keyIterator();
    while (paths.next()) |key| {
        const path = key.*;
        for (path, 0..) |byte, index| {
            if (byte == '/' and keys.contains(path[0..index])) return error.PathCollision;
        }
    }
    var result: [digest_bytes]u8 = undefined;
    hasher.final(&result);
    return result;
}

pub fn hex(value: [digest_bytes]u8) [digest_bytes * 2]u8 {
    return std.fmt.bytesToHex(value, .lower);
}

fn validatePath(path: []const u8) !void {
    if (path.len > std.math.maxInt(u32)) return error.PathLengthOverflow;
    if (path.len == 0 or path[0] == '/') return error.InvalidPath;
    const utf8 = std.unicode.Utf8View.init(path) catch return error.InvalidPath;
    var codepoints = utf8.iterator();
    while (codepoints.nextCodepoint()) |codepoint| {
        // Unicode Cc consists of C0, DEL and C1; reject all, not just ASCII NUL.
        if (codepoint < 0x20 or (codepoint >= 0x7f and codepoint <= 0x9f)) return error.InvalidPath;
    }
    for (path) |byte| switch (byte) {
        '\\', ':', '"', '*', '?', '<', '>', '|' => return error.InvalidPath,
        else => {},
    };
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) {
            return error.InvalidPath;
        }
        const last = component[component.len - 1];
        if (last == '.' or last == ' ' or isReservedDevice(component)) return error.InvalidPath;
    }
}

fn isReservedDevice(component: []const u8) bool {
    const extension = std.mem.indexOfScalar(u8, component, '.') orelse component.len;
    const stem = std.mem.trimEnd(u8, component[0..extension], " ");
    for ([_][]const u8{ "CON", "PRN", "AUX", "NUL", "CLOCK$", "CONIN$", "CONOUT$" }) |reserved| {
        if (std.ascii.eqlIgnoreCase(stem, reserved)) return true;
    }
    if (stem.len < 4 or (!std.ascii.eqlIgnoreCase(stem[0..3], "COM") and !std.ascii.eqlIgnoreCase(stem[0..3], "LPT"))) {
        return false;
    }
    if (stem.len == 4) return stem[3] >= '1' and stem[3] <= '9';
    // Windows also recognizes the ISO-8859-1 superscript device digits 1/2/3.
    return stem.len == 5 and stem[3] == 0xc2 and (stem[4] == 0xb9 or stem[4] == 0xb2 or stem[4] == 0xb3);
}
