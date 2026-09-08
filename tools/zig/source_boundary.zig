//! T0.2b source import boundary contract.
const std = @import("std");
const builtin = @import("builtin");

pub const Error = error{
    DirectZigwin32Import,
    EverythingImport,
    NonLiteralImport,
    ImportTooLong,
    InvalidUtf8,
    MalformedSource,
    InvalidArguments,
    RelativeRoot,
    SymlinkEntry,
    ReparseAncestor,
    DepthLimit,
    EntryLimit,
    FileTooLarge,
    AggregateLimit,
    UnsupportedEntry,
};

pub const Report = struct {
    files_scanned: usize = 0,
    bytes_scanned: usize = 0,
};

pub const Diagnostic = struct {
    path: []u8,
    err: anyerror,
};

pub const Limits = struct {
    /// Maximum number of candidate source/violation entries retained during discovery.
    /// The guard runs before a relative path or file handle is retained.
    max_entries: usize = 4096,
    max_file_bytes: u64 = 16 * 1024 * 1024,
    max_tree_bytes: u64 = 256 * 1024 * 1024,
    max_depth: usize = 64,
};
const max_import_bytes: usize = 4096;
const facade_path = "native/zig/src/platform/windows/api.zig";
const cache_test_path = "native/zig/tests/zigwin32_cache_test.zig";

pub fn scanText(path: []const u8, source: []const u8) Error!void {
    if (!std.unicode.utf8ValidateSlice(source)) return error.InvalidUtf8;
    var index: usize = 0;
    while (index < source.len) {
        if (isInvalidSourceControl(source[index])) return error.MalformedSource;
        if (source[index] == '/' and index + 1 < source.len) {
            if (source[index + 1] == '/') {
                index += 2;
                while (index < source.len and source[index] != '\n') : (index += 1) {
                    if (isInvalidSourceControl(source[index])) return error.MalformedSource;
                }
                continue;
            }
            if (source[index + 1] == '*') {
                index = try skipBlockComment(source, index);
                continue;
            }
        }
        if (source[index] == '\\' and index + 1 < source.len and source[index + 1] == '\\') {
            index += 2;
            while (index < source.len and source[index] != '\n') : (index += 1) {
                if (isInvalidSourceControl(source[index])) return error.MalformedSource;
            }
            continue;
        }
        if (source[index] == '"') {
            index = try skipString(source, index);
            continue;
        }
        if (source[index] == '\'') {
            index = try skipCharLiteral(source, index);
            continue;
        }
        if (source[index] == '@' and startsToken(source[index..], "@import")) {
            const parsed = try parseImport(path, source, index);
            index = parsed;
            continue;
        }
        index += 1;
    }
}

fn isInvalidSourceControl(byte: u8) bool {
    return byte == 0 or byte == 0x7f or
        (byte < 0x20 and byte != ' ' and byte != '\n' and byte != '\t' and byte != '\r');
}

pub fn scanTree(allocator: std.mem.Allocator, io: std.Io, absolute_root: []const u8) !Report {
    return scanTreeWithLimits(allocator, io, absolute_root, .{});
}

pub fn scanTreeWithLimits(
    allocator: std.mem.Allocator,
    io: std.Io,
    absolute_root: []const u8,
    limits: Limits,
) !Report {
    return scanTreeInternal(allocator, io, absolute_root, limits, null);
}

pub fn scanTreeWithDiagnostics(
    allocator: std.mem.Allocator,
    io: std.Io,
    absolute_root: []const u8,
    limits: Limits,
    diagnostic: *?Diagnostic,
) !Report {
    diagnostic.* = null;
    return scanTreeInternal(allocator, io, absolute_root, limits, diagnostic);
}

fn scanTreeInternal(
    allocator: std.mem.Allocator,
    io: std.Io,
    absolute_root: []const u8,
    limits: Limits,
    diagnostic: ?*?Diagnostic,
) !Report {
    if (!std.fs.path.isAbsolute(absolute_root)) {
        recordDiagnostic(diagnostic, allocator, absolute_root, error.RelativeRoot);
        return error.RelativeRoot;
    }
    var root = openRootNoFollow(io, absolute_root, diagnostic, allocator) catch |raw_err| {
        recordDiagnostic(diagnostic, allocator, absolute_root, raw_err);
        return raw_err;
    };
    defer root.close(io);
    validateDirectory(root, io) catch |err| {
        recordDiagnostic(diagnostic, allocator, absolute_root, err);
        return err;
    };
    // Confirm every named ancestor after root acquisition as an additional
    // diagnostic guard; the component walk above already refused reparse
    // components. All child source files are opened relative to this stable
    // root handle.
    validateAncestors(io, absolute_root, diagnostic, allocator) catch |err| {
        recordDiagnostic(diagnostic, allocator, absolute_root, err);
        return err;
    };

    var state = TreeState{
        .allocator = allocator,
        .io = io,
        .root_path = absolute_root,
        .records = .empty,
        .bytes_scanned = 0,
        .limits = limits,
        .diagnostic = diagnostic,
    };
    defer state.deinit();
    collectEntries(&state, root, "", 0) catch |err| {
        recordDiagnostic(diagnostic, allocator, absolute_root, err);
        return err;
    };
    std.mem.sort(TreeRecord, state.records.items, {}, lessRecord);
    for (state.records.items) |*record| {
        if (record.err) |err| {
            state.record(record.path, err);
            return err;
        }
        var file = record.file orelse {
            state.record(record.path, error.UnsupportedEntry);
            return error.UnsupportedEntry;
        };
        record.file = null;
        defer file.close(io);
        const stat = file.stat(io) catch |err| {
            state.record(record.path, err);
            return err;
        };
        if (stat.kind == .sym_link) {
            state.record(record.path, error.SymlinkEntry);
            return error.SymlinkEntry;
        }
        if (stat.kind != .file) {
            state.record(record.path, error.UnsupportedEntry);
            return error.UnsupportedEntry;
        }
        if (stat.size > state.limits.max_file_bytes) {
            state.record(record.path, error.FileTooLarge);
            return error.FileTooLarge;
        }
        if (stat.size > state.limits.max_tree_bytes or state.bytes_scanned > state.limits.max_tree_bytes - stat.size) {
            state.record(record.path, error.AggregateLimit);
            return error.AggregateLimit;
        }
        const remaining = @as(usize, @intCast(state.limits.max_file_bytes - stat.size)) + 1;
        // A concrete buffer is required by Zig 0.16's threaded Windows reader;
        // an empty buffer can fall through to an invalid pending-overlapped
        // state for regular files. Keep the buffer bounded and stack-local.
        var read_buffer: [16 * 1024]u8 = undefined;
        if (builtin.os.tag == .windows) {
            // Zig 0.16.0 opens nofollow Windows handles asynchronously but
            // reports File.flags.nonblocking=false. Restore the actual handle
            // mode before using File.Reader; otherwise NtReadFile reaches its
            // synchronous PENDING-unreachable branch.
            @field(file, "flags").nonblocking = true;
        }
        var reader = file.reader(io, &read_buffer);
        const contents = reader.interface.allocRemaining(allocator, .limited(remaining)) catch |err| {
            const mapped: anyerror = switch (err) {
                error.StreamTooLong => error.FileTooLarge,
                error.OutOfMemory => error.OutOfMemory,
                error.ReadFailed => reader.err orelse error.InputOutput,
            };
            state.record(record.path, mapped);
            return mapped;
        };
        defer allocator.free(contents);
        if (contents.len > state.limits.max_tree_bytes or state.bytes_scanned > state.limits.max_tree_bytes - contents.len) {
            state.record(record.path, error.AggregateLimit);
            return error.AggregateLimit;
        }
        state.bytes_scanned += contents.len;
        scanText(record.path, contents) catch |err| {
            state.record(record.path, err);
            return err;
        };
    }
    return .{
        .files_scanned = state.records.items.len,
        .bytes_scanned = @intCast(state.bytes_scanned),
    };
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3 or !std.mem.eql(u8, args[1], "tree")) return error.InvalidArguments;
    var diagnostic: ?Diagnostic = null;
    const report = scanTreeWithDiagnostics(init.gpa, init.io, args[2], .{}, &diagnostic) catch |err| {
        if (diagnostic) |item| {
            std.debug.print("source-boundary failed path={s} error={s}\n", .{ item.path, @errorName(item.err) });
            init.gpa.free(item.path);
        } else {
            std.debug.print("source-boundary failed error={s}\n", .{@errorName(err)});
        }
        return err;
    };
    std.debug.print("source-boundary files={d} bytes={d}\n", .{ report.files_scanned, report.bytes_scanned });
}

const TreeState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    root_path: []const u8,
    records: std.ArrayList(TreeRecord),
    bytes_scanned: u64,
    limits: Limits,
    diagnostic: ?*?Diagnostic,

    fn deinit(self: *TreeState) void {
        for (self.records.items) |*entry| {
            if (entry.file) |*file| file.close(self.io);
            self.allocator.free(entry.path);
        }
        self.records.deinit(self.allocator);
    }

    fn record(self: *TreeState, path: []const u8, err: anyerror) void {
        recordDiagnostic(self.diagnostic, self.allocator, path, err);
    }

    fn appendViolation(self: *TreeState, path: []const u8, err: anyerror) !void {
        if (self.records.items.len >= self.limits.max_entries) return error.EntryLimit;
        const owned = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned);
        try self.records.append(self.allocator, .{ .path = owned, .err = err });
    }

    fn appendFile(self: *TreeState, path: []const u8, file: std.Io.File) !void {
        var handle = file;
        if (self.records.items.len >= self.limits.max_entries) {
            handle.close(self.io);
            return error.EntryLimit;
        }
        const owned = self.allocator.dupe(u8, path) catch |err| {
            handle.close(self.io);
            return err;
        };
        errdefer self.allocator.free(owned);
        self.records.append(self.allocator, .{ .path = owned, .file = handle }) catch |err| {
            handle.close(self.io);
            return err;
        };
    }
};

const TreeRecord = struct {
    path: []u8,
    file: ?std.Io.File = null,
    err: ?anyerror = null,
};

fn recordDiagnostic(slot: ?*?Diagnostic, allocator: std.mem.Allocator, path: []const u8, err: anyerror) void {
    const destination = slot orelse return;
    if (destination.* != null) return;
    const owned = allocator.dupe(u8, path) catch return;
    destination.* = .{ .path = owned, .err = err };
}

fn collectEntries(state: *TreeState, directory: std.Io.Dir, relative: []const u8, depth: usize) !void {
    if (depth > state.limits.max_depth) {
        try state.appendViolation(relative, error.DepthLimit);
        return;
    }
    var iterator = directory.iterate();
    while (true) {
        const maybe_entry = iterator.next(state.io) catch |err| {
            const error_path = if (relative.len == 0) state.root_path else relative;
            try state.appendViolation(error_path, err);
            return;
        };
        const entry = maybe_entry orelse break;
        if (shouldSkip(relative, entry.name)) continue;
        // Enforce the resource bound before allocating the child path or
        // opening a candidate file. Retained paths and handles stay bounded
        // even when the entries are empty or otherwise cheap to scan.
        if (entry.kind == .file and isZigSource(entry.name) and
            state.records.items.len >= state.limits.max_entries) return error.EntryLimit;
        const child = try joinRelative(state.allocator, relative, entry.name);
        defer state.allocator.free(child);
        if (entry.kind == .sym_link) {
            try state.appendViolation(child, error.SymlinkEntry);
            continue;
        }
        switch (entry.kind) {
            .directory => {
                if (depth == state.limits.max_depth) {
                    try state.appendViolation(child, error.DepthLimit);
                    continue;
                }
                var nested = directory.openDir(state.io, entry.name, .{
                    .iterate = true,
                    .follow_symlinks = false,
                }) catch |raw_err| {
                    const err = mapReparseOpenError(raw_err, true);
                    try state.appendViolation(child, err);
                    continue;
                };
                defer nested.close(state.io);
                validateDirectory(nested, state.io) catch |err| {
                    try state.appendViolation(child, err);
                    continue;
                };
                try collectEntries(state, nested, child, depth + 1);
            },
            .file => if (isZigSource(entry.name)) {
                var file = directory.openFile(state.io, entry.name, .{
                    .follow_symlinks = false,
                    .allow_directory = false,
                }) catch |raw_err| {
                    const err = mapReparseOpenError(raw_err, true);
                    try state.appendViolation(child, err);
                    continue;
                };
                const stat = file.stat(state.io) catch |err| {
                    file.close(state.io);
                    try state.appendViolation(child, err);
                    continue;
                };
                if (stat.kind == .sym_link) {
                    file.close(state.io);
                    try state.appendViolation(child, error.SymlinkEntry);
                    continue;
                }
                if (stat.kind != .file) {
                    file.close(state.io);
                    try state.appendViolation(child, error.UnsupportedEntry);
                    continue;
                }
                try state.appendFile(child, file);
            },
            .unknown => {
                try state.appendViolation(child, error.ReparseAncestor);
                continue;
            },
            else => {
                try state.appendViolation(child, error.UnsupportedEntry);
                continue;
            },
        }
    }
}

fn validateDirectory(directory: std.Io.Dir, io: std.Io) !void {
    return switch ((try directory.stat(io)).kind) {
        .directory => {},
        .sym_link, .unknown => error.ReparseAncestor,
        else => error.UnsupportedEntry,
    };
}

fn openRootNoFollow(
    io: std.Io,
    absolute_root: []const u8,
    diagnostic: ?*?Diagnostic,
    allocator: std.mem.Allocator,
) !std.Io.Dir {
    if (builtin.os.tag == .windows) {
        const parsed = std.fs.path.parsePathWindows(u8, absolute_root);
        switch (parsed.kind) {
            .drive_absolute, .unc_absolute => {
                var current = std.Io.Dir.openDirAbsolute(io, parsed.root, .{
                    .iterate = true,
                    .follow_symlinks = false,
                }) catch |raw_err| {
                    const err = mapReparseOpenError(raw_err, false);
                    recordDiagnostic(diagnostic, allocator, parsed.root, err);
                    return err;
                };
                errdefer current.close(io);
                var index = parsed.root.len;
                while (index < absolute_root.len) {
                    while (index < absolute_root.len and std.fs.path.isSep(absolute_root[index])) index += 1;
                    if (index == absolute_root.len) break;
                    const start = index;
                    while (index < absolute_root.len and !std.fs.path.isSep(absolute_root[index])) index += 1;
                    var next = current.openDir(io, absolute_root[start..index], .{
                        .iterate = true,
                        .follow_symlinks = false,
                    }) catch |raw_err| {
                        const err = mapReparseOpenError(raw_err, true);
                        recordDiagnostic(diagnostic, allocator, absolute_root[0..index], err);
                        return err;
                    };
                    validateDirectory(next, io) catch |err| {
                        next.close(io);
                        recordDiagnostic(diagnostic, allocator, absolute_root[0..index], err);
                        return err;
                    };
                    current.close(io);
                    current = next;
                }
                return current;
            },
            // Rooted and local-device namespaces do not expose a stable
            // volume/share component through this portable API. Refuse them
            // rather than falling back to a multi-component open that could
            // follow an intermediate reparse point.
            else => {
                recordDiagnostic(diagnostic, allocator, absolute_root, error.UnsupportedEntry);
                return error.UnsupportedEntry;
            },
        }
    } else {
        const parsed = std.fs.path.parsePathPosix(absolute_root);
        var current = std.Io.Dir.openDirAbsolute(io, parsed.root, .{
            .iterate = true,
            .follow_symlinks = false,
        }) catch |raw_err| {
            const err = mapReparseOpenError(raw_err, false);
            recordDiagnostic(diagnostic, allocator, parsed.root, err);
            return err;
        };
        errdefer current.close(io);
        var index = parsed.root.len;
        while (index < absolute_root.len) {
            while (index < absolute_root.len and std.fs.path.isSep(absolute_root[index])) index += 1;
            if (index == absolute_root.len) break;
            const start = index;
            while (index < absolute_root.len and !std.fs.path.isSep(absolute_root[index])) index += 1;
            const next = current.openDir(io, absolute_root[start..index], .{
                .iterate = true,
                .follow_symlinks = false,
            }) catch |raw_err| {
                const err = mapReparseOpenError(raw_err, true);
                recordDiagnostic(diagnostic, allocator, absolute_root[0..index], err);
                return err;
            };
            current.close(io);
            current = next;
        }
        return current;
    }
}

fn validateAncestors(
    io: std.Io,
    absolute_root: []const u8,
    diagnostic: ?*?Diagnostic,
    allocator: std.mem.Allocator,
) !void {
    var current = absolute_root;
    while (true) {
        var ancestor = std.Io.Dir.openDirAbsolute(io, current, .{
            .iterate = false,
            .follow_symlinks = false,
        }) catch |raw_err| {
            const err = mapReparseOpenError(raw_err, true);
            recordDiagnostic(diagnostic, allocator, current, err);
            return err;
        };
        defer ancestor.close(io);
        validateDirectory(ancestor, io) catch |err| {
            recordDiagnostic(diagnostic, allocator, current, err);
            return err;
        };
        const parent = std.fs.path.dirname(current) orelse break;
        if (parent.len == current.len) break;
        current = parent;
    }
}

fn mapReparseOpenError(err: anyerror, missing_is_reparse: bool) anyerror {
    return switch (err) {
        error.NotDir,
        error.SymLinkLoop,
        error.AccessDenied,
        error.PermissionDenied,
        error.Unexpected,
        => error.ReparseAncestor,
        error.FileNotFound => if (missing_is_reparse) error.ReparseAncestor else err,
        else => err,
    };
}

fn shouldSkip(relative: []const u8, name: []const u8) bool {
    if (skipName(name, ".git") or
        skipName(name, ".superpowers") or
        skipName(name, ".codegraph") or
        skipName(name, ".gitnexus") or
        skipName(name, ".agents") or
        (skipName(name, "node_modules") and
            (relative.len == 0 or isWorkspacePackage(relative))) or
        skipName(name, ".zig-cache") or
        skipName(name, "zig-cache") or
        skipName(name, "zig-out")) return true;
    if (skipName(relative, "tools/zig") and skipName(name, ".cache")) return true;
    return false;
}

/// pnpm materializes one dependency checkout beside each workspace package.
/// Those trees are generated inputs, while an arbitrary nested node_modules
/// directory remains product-owned and is scanned.  Restricting this exception
/// to the repository's `packages/<name>` shape keeps the scanner useful for
/// source fixtures and prevents a broad basename-based bypass.
fn isWorkspacePackage(relative: []const u8) bool {
    const prefix = "packages/";
    if (relative.len <= prefix.len or !skipName(relative[0 .. prefix.len - 1], "packages")) return false;
    return std.mem.indexOfScalar(u8, relative[prefix.len..], '/') == null;
}

fn skipName(actual: []const u8, expected: []const u8) bool {
    return if (builtin.os.tag == .windows)
        std.ascii.eqlIgnoreCase(actual, expected)
    else
        std.mem.eql(u8, actual, expected);
}

fn isZigSource(name: []const u8) bool {
    if (name.len < ".zig".len) return false;
    return std.ascii.eqlIgnoreCase(name[name.len - ".zig".len ..], ".zig");
}

fn joinRelative(allocator: std.mem.Allocator, parent: []const u8, name: []const u8) ![]u8 {
    if (parent.len == 0) return allocator.dupe(u8, name);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ parent, name });
}

fn lessRecord(_: void, left: TreeRecord, right: TreeRecord) bool {
    return std.mem.order(u8, left.path, right.path) == .lt;
}

fn startsToken(source: []const u8, token: []const u8) bool {
    if (!std.mem.startsWith(u8, source, token)) return false;
    if (source.len == token.len) return true;
    return !isIdentifierByte(source[token.len]);
}

fn isIdentifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '@';
}

fn skipTrivia(source: []const u8, start: usize) Error!usize {
    var index = start;
    while (index < source.len) {
        if (isInvalidSourceControl(source[index])) return error.MalformedSource;
        if (std.ascii.isWhitespace(source[index])) {
            index += 1;
            continue;
        }
        if (source[index] == '/' and index + 1 < source.len and source[index + 1] == '/') {
            index += 2;
            while (index < source.len and source[index] != '\n') : (index += 1) {
                if (isInvalidSourceControl(source[index])) return error.MalformedSource;
            }
            continue;
        }
        if (source[index] == '/' and index + 1 < source.len and source[index + 1] == '*') {
            index = try skipBlockComment(source, index);
            continue;
        }
        break;
    }
    return index;
}

fn skipBlockComment(source: []const u8, start: usize) Error!usize {
    var index = start + 2;
    var nesting: usize = 1;
    while (index < source.len) {
        if (isInvalidSourceControl(source[index])) return error.MalformedSource;
        if (source[index] == '/' and index + 1 < source.len and source[index + 1] == '*') {
            nesting += 1;
            index += 2;
        } else if (source[index] == '*' and index + 1 < source.len and source[index + 1] == '/') {
            nesting -= 1;
            index += 2;
            if (nesting == 0) return index;
        } else {
            index += 1;
        }
    }
    return error.MalformedSource;
}

const ParsedString = struct {
    end: usize,
    bytes: []const u8,
};

fn parseString(source: []const u8, start: usize, output: []u8) Error!ParsedString {
    if (source[start] != '"') return error.MalformedSource;
    var index = start + 1;
    var length: usize = 0;
    while (index < source.len) {
        const byte = source[index];
        if (byte == '"') return .{ .end = index + 1, .bytes = output[0..length] };
        if (isInvalidSourceControl(byte)) return error.MalformedSource;
        if (byte == '\n' or byte == '\r') return error.MalformedSource;
        if (byte == '\\') {
            index += 1;
            if (index >= source.len) return error.MalformedSource;
            const escaped = source[index];
            if (escaped == 'u') {
                index = try parseUnicodeEscape(source, index, output, &length);
                continue;
            }
            const value: u8 = switch (escaped) {
                '\\' => '\\',
                '"' => '"',
                '\'' => '\'',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                'x' => blk: {
                    if (index + 2 >= source.len) return error.MalformedSource;
                    const hi = std.fmt.charToDigit(source[index + 1], 16) catch return error.MalformedSource;
                    const lo = std.fmt.charToDigit(source[index + 2], 16) catch return error.MalformedSource;
                    index += 2;
                    break :blk @as(u8, @intCast(hi * 16 + lo));
                },
                else => return error.MalformedSource,
            };
            if (length == output.len) return error.ImportTooLong;
            output[length] = value;
            length += 1;
            index += 1;
            continue;
        }
        if (length == output.len) return error.ImportTooLong;
        output[length] = byte;
        length += 1;
        index += 1;
    }
    return error.MalformedSource;
}

fn parseUnicodeEscape(source: []const u8, escape_index: usize, output: []u8, length: *usize) Error!usize {
    if (escape_index + 1 >= source.len or source[escape_index + 1] != '{') return error.MalformedSource;
    var index = escape_index + 2;
    var codepoint: u21 = 0;
    var digits: usize = 0;
    while (index < source.len and source[index] != '}') : (index += 1) {
        if (digits == 6) return error.MalformedSource;
        const digit = std.fmt.charToDigit(source[index], 16) catch return error.MalformedSource;
        codepoint = std.math.mul(u21, codepoint, 16) catch return error.MalformedSource;
        codepoint = std.math.add(u21, codepoint, @intCast(digit)) catch return error.MalformedSource;
        digits += 1;
    }
    if (index >= source.len or digits == 0) return error.MalformedSource;
    var encoded: [4]u8 = undefined;
    const encoded_len = std.unicode.utf8Encode(codepoint, &encoded) catch return error.MalformedSource;
    if (output.len - length.* < encoded_len) return error.ImportTooLong;
    @memcpy(output[length.* .. length.* + encoded_len], encoded[0..encoded_len]);
    length.* += encoded_len;
    return index + 1;
}

fn skipString(source: []const u8, start: usize) Error!usize {
    if (source[start] != '"') return error.MalformedSource;
    var index = start + 1;
    while (index < source.len) {
        switch (source[index]) {
            '"' => return index + 1,
            '\\' => {
                index = try skipEscape(source, index);
            },
            '\n', '\r' => return error.MalformedSource,
            else => {
                if (isInvalidSourceControl(source[index])) return error.MalformedSource;
                index += 1;
            },
        }
    }
    return error.MalformedSource;
}

fn skipCharLiteral(source: []const u8, start: usize) Error!usize {
    var index = start + 1;
    if (index >= source.len or source[index] == '\'' or source[index] == '\n' or source[index] == '\r') {
        return error.MalformedSource;
    }
    if (source[index] == '\\') {
        index = try skipEscape(source, index);
    } else {
        if (isInvalidSourceControl(source[index])) return error.MalformedSource;
        const sequence_len = std.unicode.utf8ByteSequenceLength(source[index]) catch return error.MalformedSource;
        if (index + sequence_len > source.len) return error.MalformedSource;
        _ = switch (sequence_len) {
            1 => source[index],
            2 => std.unicode.utf8Decode2(source[index..][0..2].*),
            3 => std.unicode.utf8Decode3(source[index..][0..3].*),
            4 => std.unicode.utf8Decode4(source[index..][0..4].*),
            else => return error.MalformedSource,
        } catch return error.MalformedSource;
        index += sequence_len;
    }
    if (index >= source.len or source[index] != '\'') return error.MalformedSource;
    return index + 1;
}

fn skipEscape(source: []const u8, slash_index: usize) Error!usize {
    if (slash_index + 1 >= source.len) return error.MalformedSource;
    return switch (source[slash_index + 1]) {
        '\\', '"', '\'', 'n', 'r', 't' => slash_index + 2,
        'x' => blk: {
            if (slash_index + 3 >= source.len) return error.MalformedSource;
            _ = std.fmt.charToDigit(source[slash_index + 2], 16) catch return error.MalformedSource;
            _ = std.fmt.charToDigit(source[slash_index + 3], 16) catch return error.MalformedSource;
            break :blk slash_index + 4;
        },
        'u' => try skipUnicodeEscape(source, slash_index + 1),
        else => error.MalformedSource,
    };
}

fn skipUnicodeEscape(source: []const u8, escape_index: usize) Error!usize {
    if (escape_index + 1 >= source.len or source[escape_index + 1] != '{') return error.MalformedSource;
    var index = escape_index + 2;
    var codepoint: u21 = 0;
    var digits: usize = 0;
    while (index < source.len and source[index] != '}') : (index += 1) {
        if (digits == 6) return error.MalformedSource;
        const digit = std.fmt.charToDigit(source[index], 16) catch return error.MalformedSource;
        codepoint = std.math.mul(u21, codepoint, 16) catch return error.MalformedSource;
        codepoint = std.math.add(u21, codepoint, @intCast(digit)) catch return error.MalformedSource;
        digits += 1;
    }
    if (index >= source.len or digits == 0) return error.MalformedSource;
    var encoded: [4]u8 = undefined;
    _ = std.unicode.utf8Encode(codepoint, &encoded) catch return error.MalformedSource;
    return index + 1;
}

fn parseImport(path: []const u8, source: []const u8, start: usize) Error!usize {
    var index = try skipTrivia(source, start + "@import".len);
    if (index >= source.len or source[index] != '(') return error.NonLiteralImport;
    index = try skipTrivia(source, index + 1);
    if (index >= source.len or source[index] != '"') return error.NonLiteralImport;
    var decoded: [max_import_bytes]u8 = undefined;
    const parsed = try parseString(source, index, &decoded);
    index = try skipTrivia(source, parsed.end);
    if (index >= source.len or source[index] != ')') return error.NonLiteralImport;
    const normalized = decoded[0..parsed.bytes.len];
    for (normalized) |*byte| {
        if (byte.* == '\\') byte.* = '/';
    }
    if (normalized.len >= "everything.zig".len and
        pathEqualsForFilesystem(normalized[normalized.len - "everything.zig".len ..], "everything.zig") and
        (normalized.len == "everything.zig".len or normalized[normalized.len - "everything.zig".len - 1] == '/')) return error.EverythingImport;
    const allowed = isExceptionPath(path);
    if (!allowed and (pathEqualsForFilesystem(normalized, "zigwin32") or
        (normalized.len > "zigwin32/".len and
            pathEqualsForFilesystem(normalized[0.."zigwin32".len], "zigwin32") and
            normalized["zigwin32".len] == '/'))) return error.DirectZigwin32Import;
    return index + 1;
}

fn pathEqualsForFilesystem(actual: []const u8, expected: []const u8) bool {
    if (builtin.os.tag == .windows) return std.ascii.eqlIgnoreCase(actual, expected);
    return std.mem.eql(u8, actual, expected);
}

fn isExceptionPath(path: []const u8) bool {
    return pathEqualsNormalized(path, facade_path) or pathEqualsNormalized(path, cache_test_path);
}

fn pathEqualsNormalized(path: []const u8, expected: []const u8) bool {
    if (path.len != expected.len) return false;
    for (path, expected) |actual, wanted| {
        if ((if (actual == '\\') '/' else actual) != wanted) return false;
    }
    return true;
}
