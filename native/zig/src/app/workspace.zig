const std = @import("std");
const builtin = @import("builtin");

pub const max_source_bytes: usize = 16 * 1024 * 1024;

pub const Kind = enum {
    tex,
    bib,
    style,
    class,
    tikz,
};

pub const Encoding = enum {
    utf8,
    utf8_bom,
};

pub const Inode = @TypeOf(@as(std.Io.File.Stat, undefined).inode);

pub const FileIdentity = struct {
    inode: Inode,
    size: u64,
    mtime: std.Io.Timestamp,

    pub fn eql(self: FileIdentity, other: FileIdentity) bool {
        return self.inode == other.inode and
            self.size == other.size and
            std.meta.eql(self.mtime, other.mtime);
    }
};

pub const SourceFile = struct {
    relative_path: []const u8,
    kind: Kind,
    byte_length: u64,
    sha256: [32]u8,
    encoding: Encoding,
    identity: FileIdentity,
};

pub const IssueReason = enum {
    unreadable,
    oversized,
    invalid_encoding,
    non_regular,
    reparse_point,
    hard_link,
    duplicate_canonical_path,
};

pub const InventoryIssue = struct {
    relative_path: []const u8,
    reason: IssueReason,
};

pub const RootStatus = enum {
    selected,
    needs_main_choice,
    no_candidate,
};

pub const RootReason = enum {
    explicit_project_config,
    magic_root_marker,
    single_candidate,
    include_root,
    ambiguous_candidates,
    no_candidates,
};

pub const RootDecision = struct {
    status: RootStatus,
    selected_index: ?usize = null,
    candidate_indices: []const usize,
    reason: RootReason,
};

const ScanResult = struct {
    files: std.ArrayList(SourceFile) = .empty,
    issues: std.ArrayList(InventoryIssue) = .empty,
    main_candidates: std.ArrayList(usize) = .empty,
    root_decision: RootDecision = .{
        .status = .no_candidate,
        .selected_index = null,
        .candidate_indices = &.{},
        .reason = .no_candidates,
    },

    fn deinit(self: *ScanResult, allocator: std.mem.Allocator) void {
        freeFiles(&self.files, allocator);
        freeIssues(&self.issues, allocator);
        self.main_candidates.deinit(allocator);
    }
};

pub const Workspace = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    root_path: [:0]u8,
    files_storage: std.ArrayList(SourceFile),
    issues_storage: std.ArrayList(InventoryIssue),
    main_candidates_storage: std.ArrayList(usize),
    root_decision_value: RootDecision,

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
            .issues_storage = scanned.issues,
            .main_candidates_storage = scanned.main_candidates,
            .root_decision_value = scanned.root_decision,
        };
    }

    pub fn deinit(self: *Workspace) void {
        freeFiles(&self.files_storage, self.allocator);
        freeIssues(&self.issues_storage, self.allocator);
        self.main_candidates_storage.deinit(self.allocator);
        self.allocator.free(self.root_path);
        self.* = undefined;
    }

    pub fn rescan(self: *Workspace) !void {
        var scanned = try scan(self.allocator, self.io, self.root_path);
        errdefer scanned.deinit(self.allocator);

        freeFiles(&self.files_storage, self.allocator);
        freeIssues(&self.issues_storage, self.allocator);
        self.main_candidates_storage.deinit(self.allocator);
        self.files_storage = scanned.files;
        self.issues_storage = scanned.issues;
        self.main_candidates_storage = scanned.main_candidates;
        self.root_decision_value = scanned.root_decision;
    }

    pub fn rootPath(self: *const Workspace) []const u8 {
        return self.root_path;
    }

    pub fn files(self: *const Workspace) []const SourceFile {
        return self.files_storage.items;
    }

    pub fn issues(self: *const Workspace) []const InventoryIssue {
        return self.issues_storage.items;
    }

    pub fn mainCandidates(self: *const Workspace) []const usize {
        return self.main_candidates_storage.items;
    }

    pub fn rootDecision(self: *const Workspace) RootDecision {
        return self.root_decision_value;
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

    var seen_inodes: std.ArrayList(Inode) = .empty;
    defer seen_inodes.deinit(allocator);

    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) {
            if (isIgnoredDirectory(entry.path)) walker.leave(io);
            continue;
        }
        if (entry.kind != .file and entry.kind != .sym_link and entry.kind != .unknown) continue;

        const kind = classify(entry.path) orelse continue;
        const relative_path = try normalizeRelativePath(allocator, entry.path);
        errdefer allocator.free(relative_path);

        var file = entry.dir.openFile(io, entry.basename, .{
            .mode = .read_only,
            .allow_directory = false,
            .follow_symlinks = false,
        }) catch |err| {
            const reason: IssueReason = switch (err) {
                error.AccessDenied, error.PermissionDenied => .unreadable,
                error.SymLinkLoop => .reparse_point,
                else => .unreadable,
            };
            try result.issues.append(allocator, .{
                .relative_path = relative_path,
                .reason = reason,
            });
            continue;
        };
        defer file.close(io);

        const stat = file.stat(io) catch {
            try result.issues.append(allocator, .{
                .relative_path = relative_path,
                .reason = .unreadable,
            });
            continue;
        };

        if (stat.kind == .sym_link or stat.kind == .unknown) {
            try result.issues.append(allocator, .{
                .relative_path = relative_path,
                .reason = .reparse_point,
            });
            continue;
        }
        if (stat.kind != .file) {
            try result.issues.append(allocator, .{
                .relative_path = relative_path,
                .reason = .non_regular,
            });
            continue;
        }
        if (stat.size > max_source_bytes) {
            try result.issues.append(allocator, .{
                .relative_path = relative_path,
                .reason = .oversized,
            });
            continue;
        }

        if (stat.inode != 0) {
            var is_duplicate = false;
            for (seen_inodes.items) |seen| {
                if (seen == stat.inode) {
                    is_duplicate = true;
                    break;
                }
            }
            if (is_duplicate) {
                try result.issues.append(allocator, .{
                    .relative_path = relative_path,
                    .reason = .hard_link,
                });
                continue;
            }
            try seen_inodes.append(allocator, stat.inode);
        }

        const size = @as(usize, @intCast(stat.size));
        const bytes = try allocator.alloc(u8, size);
        defer allocator.free(bytes);

        if (comptime builtin.os.tag == .windows) @field(file, "flags").nonblocking = true;
        var read_buffer: [16 * 1024]u8 = undefined;
        var reader = file.reader(io, &read_buffer);
        reader.interface.readSliceAll(bytes) catch {
            try result.issues.append(allocator, .{
                .relative_path = relative_path,
                .reason = .unreadable,
            });
            continue;
        };

        if (!std.unicode.utf8ValidateSlice(bytes)) {
            try result.issues.append(allocator, .{
                .relative_path = relative_path,
                .reason = .invalid_encoding,
            });
            continue;
        }

        const has_bom = bytes.len >= 3 and bytes[0] == 0xef and bytes[1] == 0xbb and bytes[2] == 0xbf;
        const encoding: Encoding = if (has_bom) .utf8_bom else .utf8;
        const digest = hash(bytes);

        try result.files.append(allocator, .{
            .relative_path = relative_path,
            .kind = kind,
            .byte_length = bytes.len,
            .sha256 = digest,
            .encoding = encoding,
            .identity = .{
                .inode = stat.inode,
                .size = stat.size,
                .mtime = stat.mtime,
            },
        });
    }

    std.mem.sort(SourceFile, result.files.items, {}, struct {
        fn lessThan(_: void, lhs: SourceFile, rhs: SourceFile) bool {
            return std.mem.lessThan(u8, lhs.relative_path, rhs.relative_path);
        }
    }.lessThan);

    std.mem.sort(InventoryIssue, result.issues.items, {}, struct {
        fn lessThan(_: void, lhs: InventoryIssue, rhs: InventoryIssue) bool {
            return std.mem.lessThan(u8, lhs.relative_path, rhs.relative_path);
        }
    }.lessThan);

    // Build candidates
    for (result.files.items, 0..) |file, index| {
        if (file.kind != .tex) continue;
        const bytes = root.readFileAlloc(io, file.relative_path, allocator, .limited(max_source_bytes)) catch continue;
        defer allocator.free(bytes);
        if (std.unicode.utf8ValidateSlice(bytes) and isMainCandidate(bytes)) {
            try result.main_candidates.append(allocator, index);
        }
    }

    // Determine root decision
    result.root_decision = try evaluateRootDecision(allocator, io, root, result.files.items, result.main_candidates.items);

    return result;
}

fn evaluateRootDecision(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
    files: []const SourceFile,
    candidates: []const usize,
) !RootDecision {
    // 1. Explicit project config: .texflow/project.toml
    if (root.readFileAlloc(io, ".texflow/project.toml", allocator, .limited(4096))) |cfg_bytes| {
        defer allocator.free(cfg_bytes);
        if (parseProjectTomlRoot(cfg_bytes)) |explicit_root| {
            for (files, 0..) |file, idx| {
                if (std.mem.eql(u8, file.relative_path, explicit_root) or
                    std.ascii.eqlIgnoreCase(file.relative_path, explicit_root))
                {
                    return .{
                        .status = .selected,
                        .selected_index = idx,
                        .candidate_indices = candidates,
                        .reason = .explicit_project_config,
                    };
                }
            }
        }
    } else |_| {}

    // 2. Magic root marker: % !TeX root = ...
    for (files) |file| {
        if (file.kind != .tex) continue;
        const bytes = root.readFileAlloc(io, file.relative_path, allocator, .limited(4096)) catch continue;
        defer allocator.free(bytes);
        if (parseMagicRoot(bytes)) |magic_target| {
            for (files, 0..) |f, idx| {
                if (std.mem.endsWith(u8, f.relative_path, magic_target) or
                    std.mem.eql(u8, f.relative_path, magic_target))
                {
                    return .{
                        .status = .selected,
                        .selected_index = idx,
                        .candidate_indices = candidates,
                        .reason = .magic_root_marker,
                    };
                }
            }
        }
    }

    // 3. Candidate evaluation
    if (candidates.len == 1) {
        return .{
            .status = .selected,
            .selected_index = candidates[0],
            .candidate_indices = candidates,
            .reason = .single_candidate,
        };
    } else if (candidates.len > 1) {
        return .{
            .status = .needs_main_choice,
            .selected_index = null,
            .candidate_indices = candidates,
            .reason = .ambiguous_candidates,
        };
    } else {
        return .{
            .status = .no_candidate,
            .selected_index = null,
            .candidate_indices = candidates,
            .reason = .no_candidates,
        };
    }
}

fn parseProjectTomlRoot(toml: []const u8) ?[]const u8 {
    var line_it = std.mem.splitScalar(u8, toml, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \r\t");
        if (std.mem.startsWith(u8, line, "root") or std.mem.startsWith(u8, line, "main")) {
            const eq_pos = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const val_part = std.mem.trim(u8, line[eq_pos + 1 ..], " \r\t");
            if (val_part.len >= 2 and val_part[0] == '"') {
                const end_quote = std.mem.indexOfScalar(u8, val_part[1..], '"') orelse continue;
                return val_part[1 .. end_quote + 1];
            }
        }
    }
    return null;
}

fn parseMagicRoot(bytes: []const u8) ?[]const u8 {
    var line_it = std.mem.splitScalar(u8, bytes, '\n');
    var lines_checked: usize = 0;
    while (line_it.next()) |raw_line| : (lines_checked += 1) {
        if (lines_checked > 20) break;
        const line = std.mem.trim(u8, raw_line, " \r\t");
        if (!std.mem.startsWith(u8, line, "%")) continue;
        const comment = std.mem.trim(u8, line[1..], " \t");
        if (std.mem.startsWith(u8, comment, "!") or std.mem.startsWith(u8, comment, " !")) {
            var rest = comment;
            if (std.mem.startsWith(u8, rest, " ")) rest = std.mem.trimStart(u8, rest, " ");
            if (rest.len > 0 and rest[0] == '!') rest = rest[1..];
            rest = std.mem.trimStart(u8, rest, " ");
            if (rest.len >= 3 and std.ascii.eqlIgnoreCase(rest[0..3], "tex")) {
                rest = std.mem.trimStart(u8, rest[3..], " ");
                if (rest.len >= 4 and std.ascii.eqlIgnoreCase(rest[0..4], "root")) {
                    rest = std.mem.trimStart(u8, rest[4..], " ");
                    if (rest.len > 0 and rest[0] == '=') {
                        const target = std.mem.trim(u8, rest[1..], " \r\t");
                        if (target.len > 0) return target;
                    }
                }
            }
        }
    }
    return null;
}

fn freeFiles(files: *std.ArrayList(SourceFile), allocator: std.mem.Allocator) void {
    for (files.items) |file| allocator.free(file.relative_path);
    files.deinit(allocator);
}

fn freeIssues(issues: *std.ArrayList(InventoryIssue), allocator: std.mem.Allocator) void {
    for (issues.items) |issue| allocator.free(issue.relative_path);
    issues.deinit(allocator);
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
        if (std.ascii.eqlIgnoreCase(component, ".git") or
            std.ascii.eqlIgnoreCase(component, "build") or
            std.ascii.eqlIgnoreCase(component, "out") or
            std.ascii.eqlIgnoreCase(component, "target") or
            std.ascii.eqlIgnoreCase(component, ".texflow") or
            std.ascii.eqlIgnoreCase(component, "zig-out") or
            std.ascii.eqlIgnoreCase(component, ".zig-cache")) return true;
        component_start = index + 1;
    }
    return false;
}

fn normalizeRelativePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const output = try allocator.alloc(u8, path.len);
    for (path, 0..) |character, index| output[index] = if (character == '\\') '/' else character;
    return output;
}
