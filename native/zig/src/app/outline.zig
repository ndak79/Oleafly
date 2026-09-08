const std = @import("std");
const workspace = @import("workspace");

pub const max_outline_depth: usize = 32;
pub const max_outline_files: usize = 1024;

pub const OutlineIssueKind = enum {
    unresolved,
    outside_root,
    cycle,
    depth_limit_exceeded,
    malformed_path,
    invalid_encoding,
};

pub const OutlineIssue = struct {
    referencing_file: []const u8,
    raw_reference: []const u8,
    kind: OutlineIssueKind,
};

pub const OutlineEntry = struct {
    parent_index: ?usize,
    relative_path: []const u8,
    label: []const u8,
    depth: usize,
    file_index: ?usize,
};

pub const OutlineGraph = struct {
    allocator: std.mem.Allocator,
    entries: []const OutlineEntry,
    issues: []const OutlineIssue,

    pub fn deinit(self: *OutlineGraph) void {
        for (self.entries) |entry| {
            self.allocator.free(entry.relative_path);
            self.allocator.free(entry.label);
        }
        self.allocator.free(self.entries);

        for (self.issues) |issue| {
            self.allocator.free(issue.referencing_file);
            self.allocator.free(issue.raw_reference);
        }
        self.allocator.free(self.issues);
        self.* = undefined;
    }
};

pub fn buildOutline(
    allocator: std.mem.Allocator,
    io: std.Io,
    ws: *const workspace.Workspace,
    root_relative_path: []const u8,
) !OutlineGraph {
    var entries: std.ArrayList(OutlineEntry) = .empty;
    errdefer {
        for (entries.items) |e| {
            allocator.free(e.relative_path);
            allocator.free(e.label);
        }
        entries.deinit(allocator);
    }

    var issues: std.ArrayList(OutlineIssue) = .empty;
    errdefer {
        for (issues.items) |iss| {
            allocator.free(iss.referencing_file);
            allocator.free(iss.raw_reference);
        }
        issues.deinit(allocator);
    }

    var root_file_idx: ?usize = null;
    for (ws.files(), 0..) |f, idx| {
        if (std.mem.eql(u8, f.relative_path, root_relative_path)) {
            root_file_idx = idx;
            break;
        }
    }

    const root_label = std.fs.path.basename(root_relative_path);
    try entries.append(allocator, .{
        .parent_index = null,
        .relative_path = try allocator.dupe(u8, root_relative_path),
        .label = try allocator.dupe(u8, root_label),
        .depth = 0,
        .file_index = root_file_idx,
    });

    var visited_chain: std.ArrayList([]const u8) = .empty;
    defer visited_chain.deinit(allocator);
    try visited_chain.append(allocator, root_relative_path);

    var root_dir = try std.Io.Dir.openDirAbsolute(io, ws.rootPath(), .{
        .iterate = false,
        .follow_symlinks = false,
    });
    defer root_dir.close(io);

    try traverseFile(
        allocator,
        io,
        ws,
        root_dir,
        root_relative_path,
        0,
        0,
        &visited_chain,
        &entries,
        &issues,
    );

    return .{
        .allocator = allocator,
        .entries = try entries.toOwnedSlice(allocator),
        .issues = try issues.toOwnedSlice(allocator),
    };
}

const RawReference = struct {
    target: []const u8,
    is_bib: bool,
};

fn traverseFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    ws: *const workspace.Workspace,
    root_dir: std.Io.Dir,
    current_rel_path: []const u8,
    current_entry_idx: usize,
    depth: usize,
    visited_chain: *std.ArrayList([]const u8),
    entries: *std.ArrayList(OutlineEntry),
    issues: *std.ArrayList(OutlineIssue),
) !void {
    if (depth >= max_outline_depth) return;
    if (entries.items.len >= max_outline_files) return;

    const file_bytes = root_dir.readFileAlloc(io, current_rel_path, allocator, .limited(workspace.max_source_bytes)) catch return;
    defer allocator.free(file_bytes);

    if (!std.unicode.utf8ValidateSlice(file_bytes)) {
        try issues.append(allocator, .{
            .referencing_file = try allocator.dupe(u8, current_rel_path),
            .raw_reference = try allocator.dupe(u8, ""),
            .kind = .invalid_encoding,
        });
        return;
    }

    var refs: std.ArrayList(RawReference) = .empty;
    defer {
        for (refs.items) |r| allocator.free(r.target);
        refs.deinit(allocator);
    }

    try parseLexicalReferences(allocator, file_bytes, &refs);

    for (refs.items) |ref| {
        const raw_target = ref.target;

        // Check outside root
        if (isOutsideRoot(current_rel_path, raw_target)) {
            try issues.append(allocator, .{
                .referencing_file = try allocator.dupe(u8, current_rel_path),
                .raw_reference = try allocator.dupe(u8, raw_target),
                .kind = .outside_root,
            });
            continue;
        }

        const resolved_rel_path = resolveRelativePath(allocator, current_rel_path, raw_target) catch {
            try issues.append(allocator, .{
                .referencing_file = try allocator.dupe(u8, current_rel_path),
                .raw_reference = try allocator.dupe(u8, raw_target),
                .kind = .malformed_path,
            });
            continue;
        };
        defer allocator.free(resolved_rel_path);

        // Find file in workspace inventory (with extension fallback if needed)
        const match = findInInventory(ws, resolved_rel_path, ref.is_bib);
        if (match == null) {
            try issues.append(allocator, .{
                .referencing_file = try allocator.dupe(u8, current_rel_path),
                .raw_reference = try allocator.dupe(u8, raw_target),
                .kind = .unresolved,
            });
            continue;
        }

        const target_file = match.?.file;
        const target_idx = match.?.index;

        // Check cycle
        var is_cycle = false;
        for (visited_chain.items) |v| {
            if (std.mem.eql(u8, v, target_file.relative_path)) {
                is_cycle = true;
                break;
            }
        }
        if (is_cycle) {
            try issues.append(allocator, .{
                .referencing_file = try allocator.dupe(u8, current_rel_path),
                .raw_reference = try allocator.dupe(u8, raw_target),
                .kind = .cycle,
            });
            continue;
        }

        if (depth + 1 >= max_outline_depth) {
            try issues.append(allocator, .{
                .referencing_file = try allocator.dupe(u8, current_rel_path),
                .raw_reference = try allocator.dupe(u8, raw_target),
                .kind = .depth_limit_exceeded,
            });
            continue;
        }

        const next_entry_idx = entries.items.len;
        const target_label = std.fs.path.basename(target_file.relative_path);
        try entries.append(allocator, .{
            .parent_index = current_entry_idx,
            .relative_path = try allocator.dupe(u8, target_file.relative_path),
            .label = try allocator.dupe(u8, target_label),
            .depth = depth + 1,
            .file_index = target_idx,
        });

        // Recurse if file is a tex file
        if (target_file.kind == .tex) {
            try visited_chain.append(allocator, target_file.relative_path);
            defer _ = visited_chain.pop();

            try traverseFile(
                allocator,
                io,
                ws,
                root_dir,
                target_file.relative_path,
                next_entry_idx,
                depth + 1,
                visited_chain,
                entries,
                issues,
            );
        }
    }
}

fn parseLexicalReferences(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    refs: *std.ArrayList(RawReference),
) !void {
    var i: usize = 0;
    while (i < bytes.len) {
        // Skip comments
        if (bytes[i] == '%') {
            // Check if escaped with odd number of backslashes
            var bs_count: usize = 0;
            var j = i;
            while (j > 0 and bytes[j - 1] == '\\') {
                bs_count += 1;
                j -= 1;
            }
            if (bs_count % 2 == 0) {
                // Real comment, skip to end of line
                while (i < bytes.len and bytes[i] != '\n') i += 1;
                continue;
            }
        }

        if (bytes[i] == '\\') {
            i += 1;
            const cmd_start = i;
            while (i < bytes.len and std.ascii.isAlphabetic(bytes[i])) i += 1;
            const cmd = bytes[cmd_start..i];

            var is_include = false;
            var is_bib = false;
            if (std.mem.eql(u8, cmd, "input") or
                std.mem.eql(u8, cmd, "include") or
                std.mem.eql(u8, cmd, "subfile"))
            {
                is_include = true;
            } else if (std.mem.eql(u8, cmd, "bibliography") or
                std.mem.eql(u8, cmd, "addbibresource"))
            {
                is_bib = true;
            }

            if (is_include or is_bib) {
                // Skip optional whitespace
                while (i < bytes.len and (bytes[i] == ' ' or bytes[i] == '\t' or bytes[i] == '\r' or bytes[i] == '\n')) i += 1;
                if (i < bytes.len and bytes[i] == '{') {
                    i += 1;
                    const arg_start = i;
                    while (i < bytes.len and bytes[i] != '}') i += 1;
                    if (i < bytes.len and bytes[i] == '}') {
                        const raw_arg = bytes[arg_start..i];
                        i += 1;

                        // Support comma separated list (for \bibliography)
                        var it = std.mem.splitScalar(u8, raw_arg, ',');
                        while (it.next()) |item| {
                            var trimmed = std.mem.trim(u8, item, " \r\t\n");
                            // Strip quotes if present
                            if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
                                trimmed = trimmed[1 .. trimmed.len - 1];
                            }
                            if (trimmed.len > 0) {
                                try refs.append(allocator, .{
                                    .target = try allocator.dupe(u8, trimmed),
                                    .is_bib = is_bib,
                                });
                            }
                        }
                    }
                }
            }
            continue;
        }

        i += 1;
    }
}

fn isOutsideRoot(current_rel: []const u8, target: []const u8) bool {
    _ = current_rel;
    if (std.mem.startsWith(u8, target, "../") or
        std.mem.startsWith(u8, target, "..\\") or
        std.mem.indexOf(u8, target, "/../") != null or
        std.mem.indexOf(u8, target, "\\..\\") != null)
    {
        return true;
    }
    if (std.fs.path.isAbsolute(target)) return true;
    return false;
}

fn resolveRelativePath(
    allocator: std.mem.Allocator,
    current_rel: []const u8,
    target: []const u8,
) ![]u8 {
    var norm_target = try allocator.alloc(u8, target.len);
    defer allocator.free(norm_target);
    for (target, 0..) |c, idx| {
        norm_target[idx] = if (c == '\\') '/' else c;
    }

    const dir = std.fs.path.dirname(current_rel);
    if (dir) |d| {
        var norm_dir = try allocator.alloc(u8, d.len);
        defer allocator.free(norm_dir);
        for (d, 0..) |c, idx| norm_dir[idx] = if (c == '\\') '/' else c;
        return std.fmt.allocPrint(allocator, "{s}/{s}", .{ norm_dir, norm_target });
    } else {
        return allocator.dupe(u8, norm_target);
    }
}

const InventoryMatch = struct {
    file: workspace.SourceFile,
    index: usize,
};

fn findInInventory(ws: *const workspace.Workspace, path: []const u8, is_bib: bool) ?InventoryMatch {
    // 1. Exact match
    for (ws.files(), 0..) |f, idx| {
        if (std.mem.eql(u8, f.relative_path, path)) {
            return .{ .file = f, .index = idx };
        }
    }

    // 2. Try with extension
    if (is_bib) {
        for (ws.files(), 0..) |f, idx| {
            if (f.kind == .bib and std.mem.startsWith(u8, f.relative_path, path) and
                std.mem.endsWith(u8, f.relative_path, ".bib"))
            {
                if (f.relative_path.len == path.len + 4) return .{ .file = f, .index = idx };
            }
        }
    } else {
        for (ws.files(), 0..) |f, idx| {
            if (f.kind == .tex and std.mem.startsWith(u8, f.relative_path, path) and
                std.mem.endsWith(u8, f.relative_path, ".tex"))
            {
                if (f.relative_path.len == path.len + 4) return .{ .file = f, .index = idx };
            }
        }
    }

    return null;
}
