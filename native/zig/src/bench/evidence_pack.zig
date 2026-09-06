//! Content-addressed fixture evidence pack helpers.
//! They verify copies and manifests locally; they do not claim durable
//! independent physical disks or a completed measurement campaign.
const std = @import("std");
const builtin = @import("builtin");

var next_temp_id = std.atomic.Value(u64).init(0);

const FileIdentity = struct {
    volume: u64,
    index: u64,
    links: u64,

    fn samePhysical(left: FileIdentity, right: FileIdentity) bool {
        return left.volume == right.volume and left.index == right.index;
    }
};

const windows_file_api = if (builtin.os.tag == .windows) struct {
    const ByHandleFileInformation = extern struct {
        file_attributes: u32,
        creation_time: extern struct { low: u32, high: u32 },
        last_access_time: extern struct { low: u32, high: u32 },
        last_write_time: extern struct { low: u32, high: u32 },
        volume_serial_number: u32,
        file_size_high: u32,
        file_size_low: u32,
        number_of_links: u32,
        file_index_high: u32,
        file_index_low: u32,
    };

    extern "kernel32" fn GetFileInformationByHandle(
        handle: std.os.windows.HANDLE,
        information: *ByHandleFileInformation,
    ) callconv(.winapi) std.os.windows.BOOL;
} else struct {};

pub const Input = struct { path: []const u8, bytes: []const u8 };
pub const Entry = struct { path: []u8, length: u64, digest: [32]u8 };
pub const Manifest = struct {
    allocator: std.mem.Allocator,
    entries: []Entry,
    digest: [32]u8,
    pub fn deinit(self: *Manifest) void {
        for (self.entries) |entry| self.allocator.free(entry.path);
        self.allocator.free(self.entries);
        self.* = undefined;
    }
};

fn validPath(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or path[0] == '\\' or std.mem.indexOfScalar(u8, path, '\\') != null) return false;
    if (std.mem.indexOfScalar(u8, path, ':') != null) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
        if (std.mem.indexOfScalar(u8, part, 0) != null or part[part.len - 1] == '.' or part[part.len - 1] == ' ') return false;
        // Evidence names are canonical portable ASCII. This avoids Windows
        // case-fold/normalization aliases that a byte-wise manifest cannot
        // distinguish safely.
        for (part) |byte| {
            if (byte < 0x21 or byte > 0x7e) return false;
            switch (byte) {
                '<', '>', '"', '|', '?', '*' => return false,
                else => {},
            }
        }
    }
    return true;
}

fn canonicalPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (!validPath(path)) return error.InvalidPath;
    const result = try allocator.dupe(u8, path);
    errdefer allocator.free(result);
    for (result) |*byte| byte.* = std.ascii.toLower(byte.*);
    var parts = std.mem.splitScalar(u8, result, '/');
    while (parts.next()) |part| {
        const stem = if (std.mem.indexOfScalar(u8, part, '.')) |dot| part[0..dot] else part;
        if (isReservedDeviceStem(stem)) return error.InvalidPath;
    }
    return result;
}

fn isReservedDeviceStem(stem: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(stem, "con") or std.ascii.eqlIgnoreCase(stem, "prn") or
        std.ascii.eqlIgnoreCase(stem, "aux") or std.ascii.eqlIgnoreCase(stem, "nul") or
        std.ascii.eqlIgnoreCase(stem, "conin$") or std.ascii.eqlIgnoreCase(stem, "conout$") or
        std.ascii.eqlIgnoreCase(stem, "clock$")) return true;
    if (stem.len == 4 and (std.ascii.eqlIgnoreCase(stem[0..3], "com") or std.ascii.eqlIgnoreCase(stem[0..3], "lpt"))) {
        return stem[3] >= '1' and stem[3] <= '9';
    }
    return false;
}

fn entryLess(_: void, a: Entry, b: Entry) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

pub fn manifestFromInputs(allocator: std.mem.Allocator, inputs: []const Input) !Manifest {
    var entries: std.ArrayList(Entry) = .empty;
    errdefer {
        for (entries.items) |entry| allocator.free(entry.path);
        entries.deinit(allocator);
    }
    for (inputs) |input| {
        const path = try canonicalPath(allocator, input.path);
        errdefer allocator.free(path);
        for (entries.items) |existing| {
            if (std.mem.eql(u8, existing.path, path)) return error.DuplicatePath;
        }
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(input.bytes, &digest, .{});
        try entries.append(allocator, .{ .path = path, .length = input.bytes.len, .digest = digest });
    }
    std.mem.sort(Entry, entries.items, {}, entryLess);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (entries.items) |entry| {
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, entry.length, .little);
        hasher.update(entry.path);
        hasher.update(&length);
        hasher.update(&entry.digest);
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return .{ .allocator = allocator, .entries = try entries.toOwnedSlice(allocator), .digest = digest };
}

fn parentPath(path: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, path, '/')) |index| path[0..index] else "";
}

fn basenamePath(path: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, path, '/')) |index| path[index + 1 ..] else path;
}

fn fileIdentity(io: std.Io, file: std.Io.File) !FileIdentity {
    const stat = try file.stat(io);
    if (comptime builtin.os.tag == .windows) {
        var information: windows_file_api.ByHandleFileInformation = undefined;
        if (!windows_file_api.GetFileInformationByHandle(@ptrCast(file.handle), &information).toBool()) return error.IdentityUnavailable;
        return .{
            .volume = information.volume_serial_number,
            .index = (@as(u64, information.file_index_high) << 32) | information.file_index_low,
            .links = information.number_of_links,
        };
    }
    return .{ .volume = 0, .index = @intCast(stat.inode), .links = @intCast(stat.nlink) };
}

fn dirIdentity(io: std.Io, dir: std.Io.Dir) !FileIdentity {
    const stat = try dir.stat(io);
    if (comptime builtin.os.tag == .windows) {
        var information: windows_file_api.ByHandleFileInformation = undefined;
        if (!windows_file_api.GetFileInformationByHandle(@ptrCast(dir.handle), &information).toBool()) return error.IdentityUnavailable;
        return .{
            .volume = information.volume_serial_number,
            .index = (@as(u64, information.file_index_high) << 32) | information.file_index_low,
            .links = information.number_of_links,
        };
    }
    return .{ .volume = 0, .index = @intCast(stat.inode), .links = @intCast(stat.nlink) };
}

fn openParentNoFollow(io: std.Io, root: std.Io.Dir, path: []const u8) !std.Io.Dir {
    var current = try root.openDir(io, ".", .{ .follow_symlinks = false });
    errdefer current.close(io);
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0) continue;
        var next = current.openDir(io, component, .{ .follow_symlinks = false }) catch |err| switch (err) {
            error.NotDir, error.SymLinkLoop => return error.ReparsePoint,
            else => return err,
        };
        const stat = next.stat(io) catch |err| {
            next.close(io);
            return err;
        };
        if (stat.kind != .directory) {
            next.close(io);
            return error.ReparsePoint;
        }
        current.close(io);
        current = next;
    }
    return current;
}

fn openOrCreateParentNoFollow(io: std.Io, root: std.Io.Dir, path: []const u8) !std.Io.Dir {
    var current = try root.openDir(io, ".", .{ .follow_symlinks = false });
    errdefer current.close(io);
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0) continue;
        current.createDir(io, component, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        var next = current.openDir(io, component, .{ .follow_symlinks = false }) catch |err| switch (err) {
            error.NotDir, error.SymLinkLoop => return error.ReparsePoint,
            else => return err,
        };
        const stat = next.stat(io) catch |err| {
            next.close(io);
            return err;
        };
        if (stat.kind != .directory) {
            next.close(io);
            return error.ReparsePoint;
        }
        current.close(io);
        current = next;
    }
    return current;
}

fn readAndDigest(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, entry: Entry) ![]u8 {
    const limit = if (entry.length == std.math.maxInt(u64)) return error.DigestMismatch else entry.length + 1;
    var parent = try openParentNoFollow(io, dir, parentPath(entry.path));
    defer parent.close(io);
    var file = parent.openFile(io, basenamePath(entry.path), .{
        .mode = .read_only,
        .allow_directory = false,
        .follow_symlinks = false,
    }) catch |err| return err;
    defer file.close(io);
    const stat = try file.stat(io);
    if (stat.kind != .file or stat.size > limit) return error.DigestMismatch;
    if (comptime builtin.os.tag == .windows) @field(file, "flags").nonblocking = true;
    var read_buffer: [16 * 1024]u8 = undefined;
    var file_reader = file.reader(io, &read_buffer);
    const bytes = file_reader.interface.allocRemainingAlignedSentinel(allocator, .limited(limit), .of(u8), null) catch |err| switch (err) {
        error.ReadFailed => return file_reader.err orelse error.DigestMismatch,
        error.StreamTooLong => return error.DigestMismatch,
        error.OutOfMemory => return error.OutOfMemory,
    };
    errdefer allocator.free(bytes);
    if (bytes.len != entry.length) {
        return error.DigestMismatch;
    }
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    if (!std.mem.eql(u8, &digest, &entry.digest)) {
        return error.DigestMismatch;
    }
    return bytes;
}

fn readDigestAndIdentity(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, entry: Entry) !FileIdentity {
    const limit = if (entry.length == std.math.maxInt(u64)) return error.DigestMismatch else entry.length + 1;
    var parent = try openParentNoFollow(io, dir, parentPath(entry.path));
    defer parent.close(io);
    var file = parent.openFile(io, basenamePath(entry.path), .{
        .mode = .read_only,
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch |err| return err;
    defer file.close(io);
    const before = try file.stat(io);
    if (before.kind != .file or before.size > limit) return error.DigestMismatch;
    const identity = try fileIdentity(io, file);
    // A durable evidence leaf must not have a hard-link alias. This catches
    // both two manifest entries naming one file and a hidden alias outside the
    // manifest before the copy is admitted as independent retention.
    if (identity.links != 1) return error.SameCopy;
    if (comptime builtin.os.tag == .windows) @field(file, "flags").nonblocking = true;
    var read_buffer: [16 * 1024]u8 = undefined;
    var file_reader = file.reader(io, &read_buffer);
    const bytes = file_reader.interface.allocRemainingAlignedSentinel(allocator, .limited(limit), .of(u8), null) catch |err| switch (err) {
        error.ReadFailed => return file_reader.err orelse error.FileChanged,
        error.StreamTooLong => return error.FileChanged,
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer allocator.free(bytes);
    if (bytes.len != entry.length) return error.FileChanged;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    if (!std.mem.eql(u8, &digest, &entry.digest)) return error.DigestMismatch;
    const after = try file.stat(io);
    if (after.kind != .file or after.size != before.size or after.inode != before.inode or
        after.nlink != before.nlink or after.mtime.nanoseconds != before.mtime.nanoseconds)
    {
        return error.FileChanged;
    }
    const final_identity = try fileIdentity(io, file);
    if (!identity.samePhysical(final_identity) or final_identity.links != identity.links) return error.FileChanged;
    return final_identity;
}

pub fn copyAndVerify(allocator: std.mem.Allocator, io: std.Io, source: std.Io.Dir, destination: std.Io.Dir, manifest: Manifest) !void {
    for (manifest.entries) |entry| {
        const bytes = try readAndDigest(allocator, io, source, entry);
        defer allocator.free(bytes);
        const parent = parentPath(entry.path);
        var destination_parent = try openOrCreateParentNoFollow(io, destination, parent);
        defer destination_parent.close(io);
        if (destination_parent.openFile(io, basenamePath(entry.path), .{
            .mode = .read_only,
            .allow_directory = true,
            .follow_symlinks = false,
            .resolve_beneath = true,
        })) |existing| {
            const stat = existing.stat(io) catch |err| {
                existing.close(io);
                return err;
            };
            if (stat.kind != .file) {
                existing.close(io);
                return error.ReparsePoint;
            }
            // Evidence leaves are immutable. Keep an already-valid copy and
            // reject a conflicting leaf instead of truncating it in place.
            const existing_bytes = readAndDigest(allocator, io, destination, entry) catch |err| {
                existing.close(io);
                return err;
            };
            existing.close(io);
            allocator.free(existing_bytes);
            continue;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
        const temp_name = try std.fmt.allocPrint(allocator, ".texflow-evidence-{x}.tmp", .{next_temp_id.fetchAdd(1, .monotonic)});
        defer allocator.free(temp_name);
        var temp = destination_parent.createFile(io, temp_name, .{
            .read = true,
            .exclusive = true,
            .resolve_beneath = true,
        }) catch |err| return err;
        var temp_open = true;
        defer if (temp_open) temp.close(io);
        var writer_buffer: [16 * 1024]u8 = undefined;
        var writer = temp.writerStreaming(io, &writer_buffer);
        try writer.interface.writeAll(bytes);
        try writer.interface.flush();
        try temp.sync(io);
        temp.close(io);
        temp_open = false;
        // Preserve the no-overwrite invariant across the check/create/commit
        // race: a concurrent writer that materializes the destination leaf
        // must make this commit fail, never replace that writer's artifact.
        std.Io.Dir.renamePreserve(destination_parent, temp_name, destination_parent, basenamePath(entry.path), io) catch |err| {
            destination_parent.deleteFile(io, temp_name) catch {};
            return err;
        };
    }
    try rehash(allocator, io, destination, manifest);
}

pub fn rehash(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, manifest: Manifest) !void {
    for (manifest.entries) |entry| {
        const bytes = try readAndDigest(allocator, io, dir, entry);
        allocator.free(bytes);
    }
}

pub fn verifyDurableCopies(allocator: std.mem.Allocator, io: std.Io, first: std.Io.Dir, second: std.Io.Dir, manifest: Manifest) !void {
    const first_identity = try dirIdentity(io, first);
    const second_identity = try dirIdentity(io, second);
    if (first_identity.samePhysical(second_identity)) return error.SameCopy;
    var first_files = try allocator.alloc(FileIdentity, manifest.entries.len);
    defer allocator.free(first_files);
    var second_files = try allocator.alloc(FileIdentity, manifest.entries.len);
    defer allocator.free(second_files);
    for (manifest.entries, 0..) |entry, index| {
        first_files[index] = try readDigestAndIdentity(allocator, io, first, entry);
        second_files[index] = try readDigestAndIdentity(allocator, io, second, entry);
        if (first_files[index].samePhysical(second_files[index])) return error.SameCopy;
        for (first_files[0..index]) |previous| {
            if (previous.samePhysical(first_files[index])) return error.SameCopy;
        }
        for (second_files[0..index]) |previous| {
            if (previous.samePhysical(second_files[index])) return error.SameCopy;
        }
    }
}
