//! Offline host helper for the unshipped T0.2b SQLite contract.
//! Reads an explicit source directory, hashes the bytes it will copy, and
//! inspects the produced static archive. No fetch, shell, or library lookup.
const std = @import("std");

pub const SourceLock = struct { name: []const u8, size: usize, sha256: []const u8 };
pub const source_locks = [_]SourceLock{
    .{ .name = "sqlite3.c", .size = 9_515_341, .sha256 = "b1dd5d74ec7f29055a6684fa06fb3c2f6821c87dd38f9a458dfd2e8a1db28189" },
    .{ .name = "sqlite3.h", .size = 690_838, .sha256 = "919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d" },
};

// OMIT_LOAD_EXTENSION does not remove SQLite's static auto-extension registry;
// OMIT_DEPRECATED also leaves sqlite3_soft_heap_limit(int) unconditional.
// Those APIs are excluded from the Zig surface, but are not falsely claimed
// absent from the upstream library. This list is the actual omitted C surface.
pub const prohibited_symbols = [_][]const u8{
    "sqlite3_load_extension",  "sqlite3_enable_load_extension", "sqlite3_enable_shared_cache",
    "sqlite3_aggregate_count", "sqlite3_expired",               "sqlite3_transfer_bindings",
    "sqlite3_global_recover",  "sqlite3_thread_cleanup",        "sqlite3_memory_alarm",
    "sqlite3_trace",           "sqlite3_profile",
};
pub const retained_upstream_symbols = [_][]const u8{
    "sqlite3_auto_extension", "sqlite3_reset_auto_extension", "sqlite3_cancel_auto_extension", "sqlite3_soft_heap_limit",
};

pub fn verifySource(lock: SourceLock, bytes: []const u8) !void {
    if (bytes.len != lock.size) return error.SourceSizeMismatch;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const actual = std.fmt.bytesToHex(digest, .lower);
    if (!std.mem.eql(u8, &actual, lock.sha256)) return error.SourceHashMismatch;
}

pub fn snapshot(allocator: std.mem.Allocator, io: std.Io, root: []const u8, output: []const u8) !void {
    if (!std.fs.path.isAbsolute(root)) return error.SqliteSourceMustBeAbsolute;
    if (!std.fs.path.isAbsolute(output)) return error.SqliteSnapshotMustBeAbsolute;
    var source = try std.Io.Dir.openDirAbsolute(io, root, .{ .follow_symlinks = false });
    defer source.close(io);
    var bytes: [source_locks.len][]u8 = undefined;
    var loaded: usize = 0;
    defer for (bytes[0..loaded]) |item| allocator.free(item);
    for (source_locks, 0..) |lock, index| {
        bytes[index] = try source.readFileAlloc(io, lock.name, allocator, .limited(lock.size + 1));
        loaded += 1;
        try verifySource(lock, bytes[index]);
    }
    const parent_path = std.fs.path.dirname(output) orelse return error.InvalidSnapshotPath;
    const final_name = std.fs.path.basename(output);
    var parent = try std.Io.Dir.openDirAbsolute(io, parent_path, .{ .follow_symlinks = false });
    defer parent.close(io);
    // The public snapshot is immutable. In particular, a compiler may hold
    // either member without sharing write/delete access while another build
    // revalidates it. Never truncate, repair, or replace an existing snapshot.
    if (try verifyPublished(allocator, io, parent, final_name)) return;

    var stage_name_buffer: [64]u8 = undefined;
    const stage_name = try createStage(io, parent, &stage_name_buffer);
    // Only this successfully created, randomly named stage belongs to us.
    defer parent.deleteTree(io, stage_name) catch {};
    {
        var stage = try parent.openDir(io, stage_name, .{ .follow_symlinks = false });
        defer stage.close(io);
        for (source_locks, bytes) |lock, contents| {
            try stage.writeFile(io, .{ .sub_path = lock.name, .data = contents, .flags = .{ .exclusive = true } });
        }
    }
    // Close all child handles before the same-directory, no-replace rename.
    // Readers can observe only the entire verified pair. A concurrent winner
    // is accepted only after its entire published pair is independently hashed.
    parent.renamePreserve(stage_name, parent, final_name, io) catch |err| switch (err) {
        error.PathAlreadyExists, error.AccessDenied => {
            if (try verifyPublished(allocator, io, parent, final_name)) return;
            return err;
        },
        else => return err,
    };
}

fn verifyPublished(allocator: std.mem.Allocator, io: std.Io, parent: std.Io.Dir, name: []const u8) !bool {
    var published = parent.openDir(io, name, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer published.close(io);
    for (source_locks) |lock| {
        const bytes = try published.readFileAlloc(io, lock.name, allocator, .limited(lock.size + 1));
        defer allocator.free(bytes);
        try verifySource(lock, bytes);
    }
    return true;
}

fn createStage(io: std.Io, parent: std.Io.Dir, buffer: *[64]u8) ![]const u8 {
    for (0..8) |_| {
        var random: [16]u8 = undefined;
        io.random(&random);
        const hex = std.fmt.bytesToHex(random, .lower);
        const name = try std.fmt.bufPrint(buffer, ".sqlite-stage-{s}", .{hex});
        parent.createDir(io, name, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => continue,
            else => return err,
        };
        return name;
    }
    return error.StageNameCollision;
}

/// First linker member in both COFF and GNU archives: a big-endian u32
/// symbol count, that many big-endian offsets, then NUL-terminated names.
pub fn archiveSymbols(archive: []const u8) ![]const u8 {
    if (archive.len < 68 or !std.mem.eql(u8, archive[0..8], "!<arch>\n")) return error.InvalidArchive;
    if (!std.mem.eql(u8, std.mem.trim(u8, archive[8..24], " "), "/") or !std.mem.eql(u8, archive[66..68], "`\n")) return error.UnsupportedArchiveSymbolTable;
    const size = std.fmt.parseInt(usize, std.mem.trim(u8, archive[56..66], " "), 10) catch return error.InvalidArchive;
    if (size < 4 or size > archive.len - 68) return error.InvalidArchive;
    const table = archive[68..][0..size];
    const count = std.mem.readInt(u32, table[0..4], .big);
    if (count == 0 or count > (table.len - 4) / 4) return error.InvalidArchive;
    const names = table[4 + @as(usize, count) * 4 ..];
    var offset: usize = 0;
    for (0..count) |_| {
        const end = std.mem.indexOfScalarPos(u8, names, offset, 0) orelse return error.InvalidArchive;
        if (end == offset) return error.InvalidArchive;
        offset = end + 1;
    }
    // LLVM's GNU/MSVC writers may include one NUL byte in the symbol member
    // to make its size even. This is padding, not an additional empty symbol.
    if (offset != names.len and !(size % 2 == 0 and names.len - offset == 1 and names[offset] == 0)) return error.InvalidArchive;
    return names[0..offset];
}

pub fn verifySymbols(names: []const u8) !void {
    inline for (.{ "sqlite3_libversion", "sqlite3_sourceid", "sqlite3_open_v2", "sqlite3_hard_heap_limit64" }) |required| {
        if (!hasSymbol(names, required)) return error.MissingRequiredSqliteSymbol;
    }
    for (retained_upstream_symbols) |required| {
        if (!hasSymbol(names, required)) return error.MissingRetainedUpstreamSymbol;
    }
    for (prohibited_symbols) |forbidden| {
        if (hasSymbol(names, forbidden)) {
            return error.ProhibitedSqliteSymbol;
        }
    }
}

fn hasSymbol(names: []const u8, needle: []const u8) bool {
    var iter = std.mem.splitScalar(u8, names, 0);
    while (iter.next()) |name| if (std.mem.eql(u8, name, needle)) return true;
    return false;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 4 and std.mem.eql(u8, args[1], "snapshot")) {
        // Zig's run step creates the output envelope. Publish its payload as
        // one directory so concurrent invocations never share writable files.
        const output = try std.fs.path.join(init.arena.allocator(), &.{ args[3], "payload" });
        snapshot(init.gpa, init.io, args[2], output) catch |err| {
            std.debug.print("SQLite 3.53.4 source verification failed ({s}). Supply -Dsqlite-source=<absolute directory containing the locked sqlite3.c and sqlite3.h>; no fallback or fetch is permitted.\n", .{@errorName(err)});
            return err;
        };
    } else if (args.len == 3 and std.mem.eql(u8, args[1], "symbols")) {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], init.gpa, .limited(128 * 1024 * 1024));
        defer init.gpa.free(bytes);
        try verifySymbols(try archiveSymbols(bytes));
    } else return error.InvalidArguments;
}
