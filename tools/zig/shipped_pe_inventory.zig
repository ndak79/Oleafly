//! Bounded, offline inventory of real PE images in a release payload.
//!
//! This is an oracle for a caller-supplied payload root and authenticated role
//! manifest. It does not launch, load, download, sign, or otherwise admit a
//! product. The runtime path is deliberately Windows-only because the release
//! payload is a Windows image; Linux builds are compile-only and return
//! `error.WindowsRuntimeOnly` from `audit`.
const std = @import("std");
const builtin = @import("builtin");
const pe = @import("pe_audit");

pub const Role = enum { UI, PdfWorker, ScienceWorker };

pub const RoleSpec = struct {
    name: []const u8,
    image_path: []const u8,
    pe_policy: pe.Policy,
};

pub const Manifest = struct {
    roles: []const RoleSpec,
    /// Authentication is an out-of-band trust decision. The digest binds the
    /// exact role names, image paths, and PE policies that were authenticated.
    authenticated: bool = false,
    manifest_sha256: [32]u8 = [_]u8{0} ** 32,
};

pub const Limits = struct {
    max_depth: usize = 8,
    max_files: usize = 4096,
    max_file_bytes: u64 = 256 * 1024 * 1024,
    max_bytes: u64 = 512 * 1024 * 1024,
};

pub const Entry = struct {
    path: []u8,
    role: Role,
    bytes: u64,
    sha256: [32]u8,
};

pub const Result = struct {
    files: usize,
    bytes: u64,
    digest: [32]u8,
    entries: []Entry,

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        for (self.entries) |entry| allocator.free(entry.path);
        allocator.free(self.entries);
        self.* = undefined;
    }
};

const RoleCount = 3;

const ManifestState = struct {
    specs: [RoleCount]?*const RoleSpec = .{ null, null, null },
    paths: [RoleCount]?[]u8 = .{ null, null, null },

    fn deinit(self: *ManifestState, allocator: std.mem.Allocator) void {
        for (&self.paths) |*path| {
            if (path.*) |owned| allocator.free(owned);
            path.* = null;
        }
    }
};

const ScanState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    limits: Limits,
    manifest: *const ManifestState,
    entries: std.ArrayList(Entry) = .empty,
    total_bytes: u64 = 0,
    visited_entries: usize = 0,

    fn deinit(self: *ScanState) void {
        for (self.entries.items) |entry| self.allocator.free(entry.path);
        self.entries.deinit(self.allocator);
    }
};

pub const Error = error{
    InvalidManifest,
    UnauthenticatedManifest,
    ManifestDigestMismatch,
    MissingRole,
    DuplicateRole,
    UnexpectedRole,
    DuplicatePath,
    RolePathMismatch,
    InvalidPath,
    InvalidLimits,
    RootMustBeAbsolute,
    RootNotDirectory,
    DepthLimit,
    ReparsePoint,
    UnsupportedEntry,
    FileLimit,
    FileTooLarge,
    ByteLimit,
    FileChanged,
    ExtraImage,
    DuplicateImage,
    MissingImage,
    ImageRejected,
    WindowsRuntimeOnly,
};

/// Hashes the exact manifest representation with length-delimited fields.
/// The caller must obtain this value from the authenticated source; matching a
/// digest alone is not a signature or a product-shipping decision.
pub fn manifestDigest(roles: []const RoleSpec) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("texflow-shipped-pe-manifest-v1\x00");
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, @intCast(roles.len), .little);
    hasher.update(&count);
    for (roles) |role| {
        updateBytes(&hasher, role.name);
        updateBytes(&hasher, role.image_path);
        var scalar: [2]u8 = undefined;
        std.mem.writeInt(u16, &scalar, role.pe_policy.subsystem, .little);
        hasher.update(&scalar);
        updateBool(&hasher, role.pe_policy.require_cfg);
        std.mem.writeInt(u64, &count, @intCast(role.pe_policy.imports.len), .little);
        hasher.update(&count);
        for (role.pe_policy.imports) |rule| {
            updateBytes(&hasher, rule.dll);
            std.mem.writeInt(u64, &count, @intCast(rule.functions.len), .little);
            hasher.update(&count);
            for (rule.functions) |function| updateBytes(&hasher, function);
        }
        std.mem.writeInt(u64, &count, @intCast(role.pe_policy.forbidden_paths.len), .little);
        hasher.update(&count);
        for (role.pe_policy.forbidden_paths) |path| updateBytes(&hasher, path);
    }
    var result: [32]u8 = undefined;
    hasher.final(&result);
    return result;
}

/// Inventory real files under an absolute release payload root.
///
/// No process launch or network operation occurs here. The product's shipping
/// admission remains outside this oracle and must consume this result only via
/// an explicitly reviewed caller.
pub fn audit(
    allocator: std.mem.Allocator,
    io: std.Io,
    absolute_root: []const u8,
    manifest: Manifest,
    limits: Limits,
) !Result {
    if (comptime builtin.os.tag != .windows) return error.WindowsRuntimeOnly;
    if (!std.fs.path.isAbsolute(absolute_root)) return error.RootMustBeAbsolute;
    if (limits.max_files == 0 or limits.max_file_bytes == 0 or limits.max_bytes == 0) {
        return error.InvalidLimits;
    }

    var state = try validateManifest(allocator, manifest);
    defer state.deinit(allocator);

    var root = openRootNoFollow(io, absolute_root) catch |err| return mapRootError(err);
    defer root.close(io);
    if ((try root.stat(io)).kind != .directory) return error.RootNotDirectory;

    var scan = ScanState{
        .allocator = allocator,
        .io = io,
        .limits = limits,
        .manifest = &state,
    };
    defer scan.deinit();
    try scanDirectory(&scan, root, "", 0);
    if (scan.entries.items.len != RoleCount) return error.MissingImage;
    for (state.paths, 0..) |path, index| {
        if (path == null) return error.MissingRole;
        if (!hasRoleImage(scan.entries.items, @enumFromInt(index))) return error.MissingImage;
    }

    std.mem.sort(Entry, scan.entries.items, {}, lessEntry);
    const digest = inventoryDigest(scan.entries.items, scan.total_bytes);
    const entries = try scan.entries.toOwnedSlice(allocator);
    scan.entries = .empty;
    return .{
        .files = entries.len,
        .bytes = scan.total_bytes,
        .digest = digest,
        .entries = entries,
    };
}

fn validateManifest(allocator: std.mem.Allocator, manifest: Manifest) !ManifestState {
    if (!manifest.authenticated) return error.UnauthenticatedManifest;
    if (!std.mem.eql(u8, &manifest.manifest_sha256, &manifestDigest(manifest.roles))) {
        return error.ManifestDigestMismatch;
    }
    if (manifest.roles.len != RoleCount) return error.InvalidManifest;

    var state = ManifestState{};
    errdefer state.deinit(allocator);
    for (manifest.roles) |*spec| {
        const role = parseRole(spec.name) orelse return error.UnexpectedRole;
        const index = @intFromEnum(role);
        if (state.specs[index] != null) return error.DuplicateRole;
        const path = try canonicalPath(allocator, spec.image_path);
        if (!isImagePath(path)) {
            allocator.free(path);
            return error.InvalidManifest;
        }
        if (!std.mem.eql(u8, path, canonicalRolePath(role))) {
            allocator.free(path);
            return error.RolePathMismatch;
        }
        for (state.paths) |existing| {
            if (existing) |candidate| {
                if (std.mem.eql(u8, candidate, path)) {
                    allocator.free(path);
                    return error.DuplicatePath;
                }
            }
        }
        state.specs[index] = spec;
        state.paths[index] = path;
    }
    for (state.specs) |spec| if (spec == null) return error.MissingRole;
    return state;
}

fn scanDirectory(state: *ScanState, directory: std.Io.Dir, relative: []const u8, depth: usize) !void {
    if (depth > state.limits.max_depth) return error.DepthLimit;
    var iterator = directory.iterate();
    while (try iterator.next(state.io)) |entry| {
        state.visited_entries += 1;
        if (state.visited_entries > state.limits.max_files) return error.FileLimit;
        if (!validComponent(entry.name)) return error.InvalidPath;
        const child = try joinPath(state.allocator, relative, entry.name);
        defer state.allocator.free(child);
        switch (entry.kind) {
            .sym_link, .unknown => return error.ReparsePoint,
            .directory => {
                if (depth >= state.limits.max_depth) return error.DepthLimit;
                var nested = directory.openDir(state.io, entry.name, .{
                    .iterate = true,
                    .follow_symlinks = false,
                }) catch return error.ReparsePoint;
                defer nested.close(state.io);
                if ((try nested.stat(state.io)).kind != .directory) return error.ReparsePoint;
                try scanDirectory(state, nested, child, depth + 1);
            },
            .file => if (isImagePath(child)) try scanImage(state, directory, entry.name, child),
            else => return error.UnsupportedEntry,
        }
    }
}

fn scanImage(state: *ScanState, directory: std.Io.Dir, basename: []const u8, path: []const u8) !void {
    const role = findRole(state.manifest, path) orelse return error.ExtraImage;
    for (state.entries.items) |entry| if (std.mem.eql(u8, entry.path, path)) return error.DuplicateImage;

    var verified_file = directory.openFile(state.io, basename, .{
        .follow_symlinks = false,
        .allow_directory = false,
    }) catch return error.ReparsePoint;
    defer verified_file.close(state.io);
    const before = try verified_file.stat(state.io);
    if (before.kind != .file) return error.ReparsePoint;
    if (before.size > state.limits.max_file_bytes) return error.FileTooLarge;
    if (before.size > state.limits.max_bytes -| state.total_bytes) return error.ByteLimit;
    const size = std.math.cast(usize, before.size) orelse return error.FileTooLarge;
    // Read through the already-open no-follow handle. Zig 0.16 exposes these
    // Windows handles as asynchronous NT handles but reports the flag as
    // synchronous; correct the metadata and use the positional reader with a
    // concrete buffer, matching the safe no-follow pattern used elsewhere in
    // this repository. The second no-follow open below detects replacement
    // or reparse races before accepting the snapshot.
    var read_buffer: [16 * 1024]u8 = undefined;
    if (comptime builtin.os.tag == .windows) @field(verified_file, "flags").nonblocking = true;
    var reader = verified_file.reader(state.io, &read_buffer);
    const bytes = reader.interface.allocRemaining(state.allocator, .limited(size + 1)) catch |err| switch (err) {
        error.StreamTooLong, error.ReadFailed => return error.FileChanged,
        else => return err,
    };
    defer state.allocator.free(bytes);
    if (bytes.len != size) return error.FileChanged;
    const after = blk: {
        var after_file = directory.openFile(state.io, basename, .{
            .follow_symlinks = false,
            .allow_directory = false,
        }) catch return error.ReparsePoint;
        defer after_file.close(state.io);
        break :blk try after_file.stat(state.io);
    };
    if (after.kind != .file or after.size != before.size or after.inode != before.inode or after.mtime.nanoseconds != before.mtime.nanoseconds) return error.FileChanged;
    _ = pe.auditWithForbiddenDlls(
        bytes,
        state.manifest.specs[@intFromEnum(role)].?.pe_policy,
        forbiddenCrossRoleDlls(role),
    ) catch return error.ImageRejected;

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const owned_path = try state.allocator.dupe(u8, path);
    errdefer state.allocator.free(owned_path);
    try state.entries.append(state.allocator, .{
        .path = owned_path,
        .role = role,
        .bytes = before.size,
        .sha256 = digest,
    });
    state.total_bytes += before.size;
}

fn findRole(manifest: *const ManifestState, path: []const u8) ?Role {
    for (manifest.paths, 0..) |candidate, index| {
        if (candidate) |expected| if (std.mem.eql(u8, expected, path)) return @enumFromInt(index);
    }
    return null;
}

fn hasRoleImage(entries: []const Entry, role: Role) bool {
    for (entries) |entry| if (entry.role == role) return true;
    return false;
}

fn parseRole(name: []const u8) ?Role {
    if (std.mem.eql(u8, name, "UI")) return .UI;
    if (std.mem.eql(u8, name, "PdfWorker")) return .PdfWorker;
    if (std.mem.eql(u8, name, "ScienceWorker")) return .ScienceWorker;
    return null;
}

fn canonicalRolePath(role: Role) []const u8 {
    return switch (role) {
        .UI => "bin/texflow.exe",
        .PdfWorker => "bin/texflow.pdfworker.exe",
        .ScienceWorker => "bin/texflow.scienceworker.exe",
    };
}

/// These boundaries are intrinsic to the three-role architecture.  They are
/// not caller-supplied policy, so a permissive authenticated allow-list cannot
/// accidentally turn the UI, PDF worker, or science worker into a shared
/// loader boundary.
fn forbiddenCrossRoleDlls(role: Role) []const []const u8 {
    return switch (role) {
        .UI => &.{ "lexilla", "pdfium" },
        .PdfWorker => &.{ "lexilla", "scintilla" },
        .ScienceWorker => &.{ "lexilla", "scintilla", "pdfium" },
    };
}

fn canonicalPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0 or std.fs.path.isAbsolute(path)) return error.InvalidPath;
    var result = try allocator.alloc(u8, path.len);
    errdefer allocator.free(result);
    for (path, 0..) |byte, index| {
        if (byte == '\\') result[index] = '/' else result[index] = std.ascii.toLower(byte);
    }
    if (!validRelativePath(result)) return error.InvalidPath;
    return result;
}

fn joinPath(allocator: std.mem.Allocator, parent: []const u8, basename: []const u8) ![]u8 {
    const length = parent.len + @intFromBool(parent.len != 0) + basename.len;
    const result = try allocator.alloc(u8, length);
    if (parent.len == 0) {
        @memcpy(result, basename);
    } else {
        @memcpy(result[0..parent.len], parent);
        result[parent.len] = '/';
        @memcpy(result[parent.len + 1 ..], basename);
    }
    for (result) |*byte| byte.* = std.ascii.toLower(byte.*);
    return result;
}

fn validComponent(component: []const u8) bool {
    if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return false;
    for (component) |byte| {
        if (byte < 0x21 or byte > 0x7e or byte == ':' or byte == '"' or byte == '|' or
            byte == '*' or byte == '?' or byte == '<' or byte == '>') return false;
    }
    return true;
}

fn validRelativePath(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or path[path.len - 1] == '/') return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| if (!validComponent(part)) return false;
    return true;
}

fn isImagePath(path: []const u8) bool {
    const extension = std.fs.path.extension(path);
    return std.ascii.eqlIgnoreCase(extension, ".exe") or std.ascii.eqlIgnoreCase(extension, ".dll");
}

fn lessEntry(_: void, left: Entry, right: Entry) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}

fn inventoryDigest(entries: []const Entry, total_bytes: u64) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("texflow-shipped-pe-inventory-v1\x00");
    var scalar: [8]u8 = undefined;
    std.mem.writeInt(u64, &scalar, @intCast(entries.len), .little);
    hasher.update(&scalar);
    std.mem.writeInt(u64, &scalar, total_bytes, .little);
    hasher.update(&scalar);
    for (entries) |entry| {
        updateBytes(&hasher, entry.path);
        updateBytes(&hasher, @tagName(entry.role));
        std.mem.writeInt(u64, &scalar, entry.bytes, .little);
        hasher.update(&scalar);
        hasher.update(&entry.sha256);
    }
    var result: [32]u8 = undefined;
    hasher.final(&result);
    return result;
}

fn updateBytes(hasher: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, @intCast(bytes.len), .little);
    hasher.update(&length);
    hasher.update(bytes);
}

fn updateBool(hasher: *std.crypto.hash.sha2.Sha256, value: bool) void {
    hasher.update(&.{@intFromBool(value)});
}

fn mapRootError(err: anyerror) anyerror {
    return switch (err) {
        error.NotDir, error.FileNotFound => error.RootNotDirectory,
        error.SymLinkLoop,
        error.AccessDenied,
        error.PermissionDenied,
        error.Unexpected,
        => error.ReparsePoint,
        else => err,
    };
}

/// Open every root component with no-follow semantics. A single absolute
/// open can still follow an intermediate junction/reparse point on Windows;
/// walking from the drive/share root makes the root boundary explicit before
/// any recursive payload scan starts.
fn openRootNoFollow(io: std.Io, absolute_root: []const u8) !std.Io.Dir {
    if (comptime builtin.os.tag == .windows) {
        const parsed = std.fs.path.parsePathWindows(u8, absolute_root);
        switch (parsed.kind) {
            .drive_absolute, .unc_absolute => {
                var current = try std.Io.Dir.openDirAbsolute(io, parsed.root, .{
                    .iterate = true,
                    .follow_symlinks = false,
                });
                errdefer current.close(io);
                var index = parsed.root.len;
                while (index < absolute_root.len) {
                    while (index < absolute_root.len and std.fs.path.isSep(absolute_root[index])) index += 1;
                    if (index == absolute_root.len) break;
                    const start = index;
                    while (index < absolute_root.len and !std.fs.path.isSep(absolute_root[index])) index += 1;
                    const component = absolute_root[start..index];
                    if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return error.InvalidPath;
                    const next = current.openDir(io, component, .{
                        .iterate = true,
                        .follow_symlinks = false,
                    }) catch |err| switch (err) {
                        error.NotDir, error.FileNotFound => return err,
                        else => return error.ReparsePoint,
                    };
                    current.close(io);
                    current = next;
                }
                return current;
            },
            else => return error.InvalidPath,
        }
    } else {
        const parsed = std.fs.path.parsePathPosix(absolute_root);
        var current = try std.Io.Dir.openDirAbsolute(io, parsed.root, .{
            .iterate = true,
            .follow_symlinks = false,
        });
        errdefer current.close(io);
        var index = parsed.root.len;
        while (index < absolute_root.len) {
            while (index < absolute_root.len and std.fs.path.isSep(absolute_root[index])) index += 1;
            if (index == absolute_root.len) break;
            const start = index;
            while (index < absolute_root.len and !std.fs.path.isSep(absolute_root[index])) index += 1;
            const component = absolute_root[start..index];
            if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return error.InvalidPath;
            const next = current.openDir(io, component, .{
                .iterate = true,
                .follow_symlinks = false,
            }) catch |err| switch (err) {
                error.NotDir, error.FileNotFound => return err,
                else => return error.ReparsePoint,
            };
            current.close(io);
            current = next;
        }
        return current;
    }
}
