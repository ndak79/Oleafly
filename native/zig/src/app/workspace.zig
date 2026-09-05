const std = @import("std");

pub const max_source_bytes: usize = 16 * 1024 * 1024;

pub const Kind = enum {
    tex,
    bib,
    style,
    class,
    tikz,
};

pub const SourceFile = struct {
    relative_path: []const u8,
    kind: Kind,
    byte_length: u64,
    sha256: [32]u8,
};

const ScanResult = struct {
    files: std.ArrayList(SourceFile) = .empty,
    main_candidates: std.ArrayList(usize) = .empty,

    fn deinit(self: *ScanResult, allocator: std.mem.Allocator) void {
        freeFiles(&self.files, allocator);
        self.main_candidates.deinit(allocator);
    }
};

pub const Workspace = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    root_path: [:0]u8,
    files_storage: std.ArrayList(SourceFile),
    main_candidates_storage: std.ArrayList(usize),

    pub fn open(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Workspace {
        const root_path = try std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator);
        errdefer allocator.free(root_path);

        var root = try std.Io.Dir.openDirAbsolute(io, root_path, .{
            .iterate = true,
            .follow_symlinks = false,
        });
        root.close(io);

        var scanned = try scan(allocator, io, root_path);
        errdefer scanned.deinit(allocator);
        return .{
            .allocator = allocator,
            .io = io,
            .root_path = root_path,
            .files_storage = scanned.files,
            .main_candidates_storage = scanned.main_candidates,
        };
    }

    pub fn deinit(self: *Workspace) void {
        freeFiles(&self.files_storage, self.allocator);
        self.main_candidates_storage.deinit(self.allocator);
        self.allocator.free(self.root_path);
        self.* = undefined;
    }

    pub fn rescan(self: *Workspace) !void {
        var scanned = try scan(self.allocator, self.io, self.root_path);
        errdefer scanned.deinit(self.allocator);

        freeFiles(&self.files_storage, self.allocator);
        self.main_candidates_storage.deinit(self.allocator);
        self.files_storage = scanned.files;
        self.main_candidates_storage = scanned.main_candidates;
    }

    pub fn rootPath(self: *const Workspace) []const u8 {
        return self.root_path;
    }

    pub fn files(self: *const Workspace) []const SourceFile {
        return self.files_storage.items;
    }

    pub fn mainCandidates(self: *const Workspace) []const usize {
        return self.main_candidates_storage.items;
    }
};

fn scan(allocator: std.mem.Allocator, io: std.Io, root_path: []const u8) !ScanResult {
    var result: ScanResult = .{};
    errdefer result.deinit(allocator);

    var root = try std.Io.Dir.openDirAbsolute(io, root_path, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer root.close(io);

    var walker = try root.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) {
            if (isIgnoredDirectory(entry.path)) walker.leave(io);
            continue;
        }
        if (entry.kind != .file) continue;

        const kind = classify(entry.path) orelse continue;
        const bytes = entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(max_source_bytes)) catch continue;
        defer allocator.free(bytes);
        if (!std.unicode.utf8ValidateSlice(bytes)) continue;

        const is_main_candidate = kind == .tex and isMainCandidate(bytes);
        const digest = hash(bytes);
        {
            const relative_path = try normalizeRelativePath(allocator, entry.path);
            errdefer allocator.free(relative_path);
            try result.files.append(allocator, .{
                .relative_path = relative_path,
                .kind = kind,
                .byte_length = bytes.len,
                .sha256 = digest,
            });
            if (is_main_candidate) {
                // Candidate indices are rebuilt after deterministic sorting.
            }
        }
    }

    std.mem.sort(SourceFile, result.files.items, {}, struct {
        fn lessThan(_: void, lhs: SourceFile, rhs: SourceFile) bool {
            return std.mem.lessThan(u8, lhs.relative_path, rhs.relative_path);
        }
    }.lessThan);

    // Re-read only sorted .tex files to build stable candidate indices. This
    // keeps SourceFile a compact immutable inventory record and avoids exposing
    // scanner-only state in the public model.
    for (result.files.items, 0..) |file, index| {
        if (file.kind != .tex) continue;
        const bytes = root.readFileAlloc(io, file.relative_path, allocator, .limited(max_source_bytes)) catch continue;
        defer allocator.free(bytes);
        if (std.unicode.utf8ValidateSlice(bytes) and isMainCandidate(bytes)) {
            try result.main_candidates.append(allocator, index);
        }
    }

    return result;
}

fn freeFiles(files: *std.ArrayList(SourceFile), allocator: std.mem.Allocator) void {
    for (files.items) |file| allocator.free(file.relative_path);
    files.deinit(allocator);
}

fn hash(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

fn classify(path: []const u8) ?Kind {
    const dot = std.mem.lastIndexOfScalar(u8, path, '.') orelse return null;
    const slash = @max(
        std.mem.lastIndexOfScalar(u8, path, '/') orelse 0,
        std.mem.lastIndexOfScalar(u8, path, '\\') orelse 0,
    );
    if (dot <= slash or dot + 1 >= path.len) return null;
    const extension = path[dot + 1 ..];
    if (std.ascii.eqlIgnoreCase(extension, "tex")) return .tex;
    if (std.ascii.eqlIgnoreCase(extension, "bib")) return .bib;
    if (std.ascii.eqlIgnoreCase(extension, "sty")) return .style;
    if (std.ascii.eqlIgnoreCase(extension, "cls")) return .class;
    if (std.ascii.eqlIgnoreCase(extension, "tikz")) return .tikz;
    return null;
}

fn isMainCandidate(bytes: []const u8) bool {
    return std.mem.indexOf(u8, bytes, "\\documentclass") != null or
        std.mem.indexOf(u8, bytes, "\\begin{document}") != null;
}

fn isIgnoredDirectory(path: []const u8) bool {
    var component_start: usize = 0;
    var index: usize = 0;
    while (index <= path.len) : (index += 1) {
        if (index != path.len and path[index] != '/' and path[index] != '\\') continue;
        const component = path[component_start..index];
        if (std.mem.eql(u8, component, ".git") or
            std.mem.eql(u8, component, "build") or
            std.mem.eql(u8, component, "out") or
            std.mem.eql(u8, component, "target") or
            std.mem.eql(u8, component, ".texflow") or
            std.mem.eql(u8, component, "zig-out") or
            std.mem.eql(u8, component, ".zig-cache")) return true;
        component_start = index + 1;
    }
    return false;
}

fn normalizeRelativePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const output = try allocator.alloc(u8, path.len);
    for (path, 0..) |character, index| output[index] = if (character == '\\') '/' else character;
    return output;
}
