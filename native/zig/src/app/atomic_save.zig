const std = @import("std");
const builtin = @import("builtin");

pub const ContentHash = [32]u8;

pub const SaveStatus = enum {
    replaced,
    recovery_retained,
};

pub const RenameHook = *const fn (
    io: std.Io,
    directory: std.Io.Dir,
    staged_name: []const u8,
    target_name: []const u8,
) anyerror!void;

pub const SaveHooks = struct {
    /// Test-only replacement hook. The normal save path always uses
    /// std.Io.Dir.rename directly.
    rename: ?RenameHook = null,
};

pub const SaveResult = struct {
    allocator: std.mem.Allocator,
    status: SaveStatus,
    target_hash: ContentHash,
    revision: u64,
    recovery_path: ?[]u8 = null,

    pub fn deinit(self: *SaveResult) void {
        if (self.recovery_path) |path| self.allocator.free(path);
        self.recovery_path = null;
    }
};

pub const temp_file_prefix = ".texflow-save-";

var next_temp_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

const TempFile = struct {
    allocator: std.mem.Allocator,
    path: []u8,
    file: std.Io.File,
    open: bool = true,
    exists: bool = true,
    retained: bool = false,

    fn close(self: *TempFile, io: std.Io) void {
        if (self.open) {
            self.file.close(io);
            self.open = false;
        }
    }

    fn transferRecovery(self: *TempFile, io: std.Io) []u8 {
        self.close(io);
        self.retained = true;
        return self.path;
    }

    fn cleanup(self: *TempFile, directory: std.Io.Dir, io: std.Io) void {
        self.close(io);
        if (!self.retained) {
            if (self.exists) directory.deleteFile(io, std.Io.Dir.path.basename(self.path)) catch {};
            self.allocator.free(self.path);
        }
    }
};

/// Atomically replace an existing workspace file after verifying its saved
/// base. The caller owns workspace authorization: `target_path` must already
/// be an absolute path selected from the caller's validated workspace model;
/// this boundary deliberately does not infer a workspace root from a string.
pub fn save(
    allocator: std.mem.Allocator,
    io: std.Io,
    target_path: []const u8,
    expected_saved_hash: ContentHash,
    bytes: []const u8,
    revision: u64,
) !SaveResult {
    return saveWithHooks(allocator, io, target_path, expected_saved_hash, bytes, revision, .{});
}

pub fn saveWithHooks(
    allocator: std.mem.Allocator,
    io: std.Io,
    target_path: []const u8,
    expected_saved_hash: ContentHash,
    bytes: []const u8,
    revision: u64,
    hooks: SaveHooks,
) !SaveResult {
    const canonical_target = try canonicalAbsolutePath(allocator, target_path);
    defer allocator.free(canonical_target);

    const parent_path = std.Io.Dir.path.dirname(canonical_target) orelse return error.InvalidTargetPath;
    const target_name = std.Io.Dir.path.basename(canonical_target);
    if (target_name.len == 0) return error.InvalidTargetPath;

    var directory = openParentNoFollow(io, parent_path) catch |err| return mapDirectoryError(err);
    defer directory.close(io);

    // Serialize all saves that honor this boundary. The guard remains held
    // through the final compare and replacement rename, closing the
    // preflight-to-rename race instead of merely detecting it afterwards.
    var target_guard = directory.openFile(io, target_name, .{
        .mode = .read_only,
        .allow_directory = false,
        .follow_symlinks = false,
        .lock = .exclusive,
        .lock_nonblocking = true,
    }) catch |err| switch (err) {
        error.WouldBlock => return error.ExternalChange,
        else => return mapTargetError(err),
    };
    defer {
        target_guard.unlock(io);
        target_guard.close(io);
    }
    const guard_stat = target_guard.stat(io) catch |err| return mapTargetError(err);
    try validateTargetKind(guard_stat.kind);

    // This is the complete precondition phase. No staging name is created
    // until the target has been opened without following a reparse point and
    // its bytes match the editor's saved base.
    const observed_hash = try readTargetHashFromHandle(directory, io, target_name, &target_guard);
    if (!std.mem.eql(u8, &observed_hash, &expected_saved_hash)) return error.ExternalChange;
    const staged_hash = hashBytes(bytes);

    var staged = try createTempFile(allocator, directory, parent_path, io, revision);
    defer staged.cleanup(directory, io);

    stageBytes(&staged, io, bytes) catch {
        return recoveryResult(&staged, io, observed_hash, revision);
    };

    // Keep one synced copy until post-replacement verification completes.
    // This makes a verification failure recoverable even though the primary
    // staging name is consumed by the replacement rename.
    var backup = createTempFile(allocator, directory, parent_path, io, revision) catch {
        return recoveryResult(&staged, io, observed_hash, revision);
    };
    defer backup.cleanup(directory, io);
    stageBytes(&backup, io, bytes) catch {
        return recoveryResult(&staged, io, observed_hash, revision);
    };

    const before_rename = directory.statFile(io, target_name, .{ .follow_symlinks = false }) catch {
        return recoveryResult(&backup, io, observed_hash, revision);
    };
    validateTargetKind(before_rename.kind) catch {
        return recoveryResult(&backup, io, observed_hash, revision);
    };
    if (!sameTargetState(guard_stat, before_rename)) {
        return recoveryResult(&backup, io, observed_hash, revision);
    }

    const staged_name = std.Io.Dir.path.basename(staged.path);
    const rename_result = if (hooks.rename) |rename_hook|
        rename_hook(io, directory, staged_name, target_name)
    else
        std.Io.Dir.rename(directory, staged_name, directory, target_name, io);
    if (rename_result) |_| {
        staged.exists = false;
    } else |_| {
        // Keep the independently synced backup as the recovery artifact. A
        // filesystem or test hook can report an error after consuming the
        // staged name; the backup remains present in either case.
        return recoveryResult(&backup, io, observed_hash, revision);
    }

    const verified_hash = readTargetHash(directory, io, target_name) catch {
        return recoveryResult(&backup, io, observed_hash, revision);
    };
    if (!std.mem.eql(u8, &verified_hash, &staged_hash)) {
        return recoveryResult(&backup, io, verified_hash, revision);
    }

    backup.close(io);
    backup.exists = true;
    deleteTempFile(&backup, directory, io) catch {
        return recoveryResult(&backup, io, verified_hash, revision);
    };
    return .{
        .allocator = allocator,
        .status = .replaced,
        .target_hash = verified_hash,
        .revision = revision,
    };
}

fn canonicalAbsolutePath(allocator: std.mem.Allocator, target_path: []const u8) ![]u8 {
    if (target_path.len == 0) return error.InvalidTargetPath;
    if (!std.Io.Dir.path.isAbsolute(target_path)) return error.RelativePath;
    try validateAbsolutePath(target_path);
    return std.Io.Dir.path.resolve(allocator, &.{target_path});
}

fn validateAbsolutePath(path: []const u8) !void {
    if (path.len == 0 or !std.unicode.utf8ValidateSlice(path)) return error.InvalidTargetPath;

    const root_len = if (comptime builtin.os.tag == .windows) blk: {
        const parsed = std.fs.path.parsePathWindows(u8, path);
        switch (parsed.kind) {
            .drive_absolute, .unc_absolute => break :blk parsed.root.len,
            else => return error.InvalidTargetPath,
        }
    } else blk: {
        const parsed = std.fs.path.parsePathPosix(path);
        if (parsed.root.len == 0) return error.InvalidTargetPath;
        break :blk parsed.root.len;
    };

    var index = root_len;
    while (index < path.len) {
        while (index < path.len and std.fs.path.isSep(path[index])) index += 1;
        if (index == path.len) break;
        const start = index;
        while (index < path.len and !std.fs.path.isSep(path[index])) index += 1;
        if (!validPathComponent(path[start..index])) return error.InvalidTargetPath;
    }
}

fn validPathComponent(component: []const u8) bool {
    if (component.len == 0 or
        std.mem.eql(u8, component, ".") or
        std.mem.eql(u8, component, "..")) return false;
    for (component) |byte| {
        if (byte == 0 or byte < 0x20 or byte == 0x7f) return false;
    }
    if (comptime builtin.os.tag == .windows) {
        for (component) |byte| {
            if (byte == ':' or byte == '"' or byte == '*' or byte == '?' or
                byte == '<' or byte == '>' or byte == '|') return false;
        }
        if (component[component.len - 1] == '.' or component[component.len - 1] == ' ') return false;
        if (isWindowsDeviceName(component)) return false;
    }
    return true;
}

fn isWindowsDeviceName(component: []const u8) bool {
    var stem = component;
    if (std.mem.indexOfScalar(u8, stem, '.')) |dot| stem = stem[0..dot];
    if (std.ascii.eqlIgnoreCase(stem, "CON") or
        std.ascii.eqlIgnoreCase(stem, "PRN") or
        std.ascii.eqlIgnoreCase(stem, "AUX") or
        std.ascii.eqlIgnoreCase(stem, "NUL") or
        std.ascii.eqlIgnoreCase(stem, "CONIN$") or
        std.ascii.eqlIgnoreCase(stem, "CONOUT$")) return true;
    if (stem.len == 4 and
        (std.ascii.eqlIgnoreCase(stem[0..3], "COM") or std.ascii.eqlIgnoreCase(stem[0..3], "LPT")) and
        stem[3] >= '0' and stem[3] <= '9') return true;
    return false;
}

/// Open the target's parent one component at a time. Opening the complete
/// parent path in one call can follow an intermediate junction/reparse point
/// on Windows even when the final open is no-follow.
fn openParentNoFollow(io: std.Io, absolute_parent: []const u8) !std.Io.Dir {
    if (comptime builtin.os.tag == .windows) {
        const parsed = std.fs.path.parsePathWindows(u8, absolute_parent);
        switch (parsed.kind) {
            .drive_absolute, .unc_absolute => {
                var current = try std.Io.Dir.openDirAbsolute(io, parsed.root, .{
                    .iterate = false,
                    .follow_symlinks = false,
                });
                errdefer current.close(io);
                try validateParentDirectory(current, io);
                var index = parsed.root.len;
                while (index < absolute_parent.len) {
                    while (index < absolute_parent.len and std.fs.path.isSep(absolute_parent[index])) index += 1;
                    if (index == absolute_parent.len) break;
                    const start = index;
                    while (index < absolute_parent.len and !std.fs.path.isSep(absolute_parent[index])) index += 1;
                    const component = absolute_parent[start..index];
                    if (!validPathComponent(component)) return error.InvalidTargetPath;
                    var next = current.openDir(io, component, .{
                        .iterate = false,
                        .follow_symlinks = false,
                    }) catch |err| return mapDirectoryError(err);
                    validateParentDirectory(next, io) catch |err| {
                        next.close(io);
                        return err;
                    };
                    current.close(io);
                    current = next;
                }
                return current;
            },
            else => return error.InvalidTargetPath,
        }
    } else {
        const parsed = std.fs.path.parsePathPosix(absolute_parent);
        if (parsed.root.len == 0) return error.InvalidTargetPath;
        var current = try std.Io.Dir.openDirAbsolute(io, parsed.root, .{
            .iterate = false,
            .follow_symlinks = false,
        });
        errdefer current.close(io);
        try validateParentDirectory(current, io);
        var index = parsed.root.len;
        while (index < absolute_parent.len) {
            while (index < absolute_parent.len and std.fs.path.isSep(absolute_parent[index])) index += 1;
            if (index == absolute_parent.len) break;
            const start = index;
            while (index < absolute_parent.len and !std.fs.path.isSep(absolute_parent[index])) index += 1;
            const component = absolute_parent[start..index];
            if (!validPathComponent(component)) return error.InvalidTargetPath;
            var next = current.openDir(io, component, .{
                .iterate = false,
                .follow_symlinks = false,
            }) catch |err| return mapDirectoryError(err);
            validateParentDirectory(next, io) catch |err| {
                next.close(io);
                return err;
            };
            current.close(io);
            current = next;
        }
        return current;
    }
}

fn validateParentDirectory(directory: std.Io.Dir, io: std.Io) !void {
    return switch ((try directory.stat(io)).kind) {
        .directory => {},
        .sym_link, .unknown => error.ReparsePoint,
        else => error.TargetMissing,
    };
}

fn mapDirectoryError(err: anyerror) anyerror {
    return switch (err) {
        error.FileNotFound, error.NotDir => error.TargetMissing,
        error.SymLinkLoop,
        error.AccessDenied,
        error.PermissionDenied,
        error.Unexpected,
        => error.ReparsePoint,
        else => err,
    };
}

fn mapTargetError(err: anyerror) anyerror {
    return switch (err) {
        error.FileNotFound => error.TargetMissing,
        error.NotDir => error.TargetNotRegular,
        error.SymLinkLoop,
        error.AccessDenied,
        error.PermissionDenied,
        error.Unexpected,
        => error.ReparsePoint,
        else => err,
    };
}

fn validateTargetKind(kind: std.Io.File.Kind) !void {
    switch (kind) {
        .sym_link, .unknown => return error.ReparsePoint,
        .file => {},
        else => return error.TargetNotRegular,
    }
}

fn sameTargetState(left: std.Io.File.Stat, right: std.Io.File.Stat) bool {
    return left.kind == right.kind and
        left.inode == right.inode and
        left.size == right.size and
        std.meta.eql(left.mtime, right.mtime) and
        std.meta.eql(left.ctime, right.ctime);
}

fn readTargetHash(
    directory: std.Io.Dir,
    io: std.Io,
    target_name: []const u8,
) !ContentHash {
    // Read through one already-open no-follow handle. This pins the identity
    // used for the hash and prevents a symlink/reparse target from being
    // substituted between an identity check and the data read.
    var target = directory.openFile(io, target_name, .{
        .mode = .read_only,
        .allow_directory = false,
        .follow_symlinks = false,
    }) catch |err| return mapTargetError(err);
    defer target.close(io);

    return readTargetHashFromHandle(directory, io, target_name, &target);
}

fn readTargetHashFromHandle(
    directory: std.Io.Dir,
    io: std.Io,
    target_name: []const u8,
    target: *std.Io.File,
) !ContentHash {
    const before = target.stat(io) catch |err| return mapTargetError(err);
    try validateTargetKind(before.kind);
    const size = std.math.cast(usize, before.size) orelse return error.TargetTooLarge;

    // Zig 0.16 opens no-follow Windows handles asynchronously but reports
    // the flag as synchronous. Restore the actual handle mode before using
    // File.Reader, matching the repository's pinned no-follow readers.
    var read_buffer: [16 * 1024]u8 = undefined;
    if (comptime builtin.os.tag == .windows) @field(target.*, "flags").nonblocking = true;
    var reader = target.reader(io, &read_buffer);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var remaining = size;
    while (remaining != 0) {
        const count = @min(remaining, read_buffer.len);
        reader.interface.readSliceAll(read_buffer[0..count]) catch |err| switch (err) {
            error.EndOfStream, error.ReadFailed => return error.ExternalChange,
        };
        hasher.update(read_buffer[0..count]);
        remaining -= count;
    }

    var digest: ContentHash = undefined;
    hasher.final(&digest);

    // A replacement, append, truncate, or same-path reparse substitution
    // during the read invalidates the precondition even though the open handle
    // itself remains pinned to the original inode.
    const final_stat = directory.statFile(io, target_name, .{ .follow_symlinks = false }) catch |err| {
        return mapTargetError(err);
    };
    try validateTargetKind(final_stat.kind);
    if (final_stat.inode != before.inode or
        final_stat.size != before.size or
        !std.meta.eql(final_stat.mtime, before.mtime) or
        !std.meta.eql(final_stat.ctime, before.ctime))
    {
        return error.ExternalChange;
    }
    return digest;
}

fn hashBytes(bytes: []const u8) ContentHash {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(bytes);
    var result: ContentHash = undefined;
    hasher.final(&result);
    return result;
}

fn createTempFile(
    allocator: std.mem.Allocator,
    directory: std.Io.Dir,
    parent_path: []const u8,
    io: std.Io,
    revision: u64,
) !TempFile {
    var attempt: usize = 0;
    while (attempt < 128) : (attempt += 1) {
        const id = next_temp_id.fetchAdd(1, .monotonic);
        const name = try std.fmt.allocPrint(allocator, "{s}{x}-{x}.tmp", .{ temp_file_prefix, revision, id });
        defer allocator.free(name);
        const path = std.Io.Dir.path.join(allocator, &.{ parent_path, name }) catch |err| return err;
        const file = directory.createFile(io, std.Io.Dir.path.basename(path), .{
            .read = true,
            .truncate = false,
            .exclusive = true,
        }) catch |err| switch (err) {
            error.PathAlreadyExists => {
                allocator.free(path);
                continue;
            },
            else => {
                allocator.free(path);
                return err;
            },
        };
        return .{
            .allocator = allocator,
            .path = path,
            .file = file,
        };
    }
    return error.TempNameExhausted;
}

fn stageBytes(temp: *TempFile, io: std.Io, bytes: []const u8) !void {
    try temp.file.writeStreamingAll(io, bytes);
    try temp.file.sync(io);
    temp.close(io);
}

fn recoveryResult(
    temp: *TempFile,
    io: std.Io,
    target_hash: ContentHash,
    revision: u64,
) SaveResult {
    const path = temp.transferRecovery(io);
    return .{
        .allocator = temp.allocator,
        .status = .recovery_retained,
        .target_hash = target_hash,
        .revision = revision,
        .recovery_path = path,
    };
}

fn deleteTempFile(self: *TempFile, directory: std.Io.Dir, io: std.Io) !void {
    if (!self.exists) return;
    try directory.deleteFile(io, std.Io.Dir.path.basename(self.path));
    self.exists = false;
}

test {
    _ = SaveResult;
}
