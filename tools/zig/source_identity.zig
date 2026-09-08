//! Zig-owned source identity collector for the native product build.
//!
//! The index is the authority: checkout filters, line-ending conversion, and
//! working-tree bytes never enter the digest. A dirty developer checkout still
//! produces a deterministic identity for diagnostics, but marks it
//! non-authoritative so the product entry gate cannot admit it.
const std = @import("std");
const builtin = @import("builtin");
const source_unicode = @import("source_unicode.zig");

comptime {
    if (!std.mem.eql(u8, source_unicode.unicode_version, "17.0.0")) {
        @compileError("source identity Unicode collision oracle must be Unicode 17.0.0");
    }
    const source_data = @import("source_unicode_data.zig");
    if (!std.mem.eql(u8, source_data.source_archive_sha256, "2066d1909b2ea93916ce092da1c0ee4808ea3ef8407c94b4f14f5b7eb263d28e")) {
        @compileError("source identity Unicode data is not the locked UCD 17.0.0 export");
    }
}

const source_domain = "texflow:source-set:v2\x00";
const build_domain = "texflow:build:v1\x00";
const max_index_output = 64 * 1024 * 1024;
const max_blob_output = 256 * 1024 * 1024;
const evidence_prefix = "docs/superpowers/evidence/";

const Entry = struct {
    path: []u8,
    mode: [6]u8,
    oid: [40]u8,
    content_length_known: bool,
    content_length: u64,
    blob_sha256: [32]u8,
};

const Identity = struct {
    source_set_sha256: [32]u8,
    dependency_lock_sha256: [32]u8,
    build_identity: [32]u8,
    git_executable_sha256: [32]u8,
    git_version: []u8,
    authoritative: bool,
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    try validateArguments(args);
    const repo = try option(args, "--repo");
    const git = try option(args, "--git");
    const identity = try collect(init.gpa, init.io, repo, git, try optionalOption(args, "--commit"));
    defer init.gpa.free(identity.git_version);
    var source_hex = std.fmt.bytesToHex(identity.source_set_sha256, .lower);
    var lock_hex = std.fmt.bytesToHex(identity.dependency_lock_sha256, .lower);
    var build_hex = std.fmt.bytesToHex(identity.build_identity, .lower);
    var git_hex = std.fmt.bytesToHex(identity.git_executable_sha256, .lower);
    var buffer: [512]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    try stdout.interface.print(
        "source_set_sha256={s}\ndependency_lock_sha256={s}\nbuild_identity={s}\ngit_executable_sha256={s}\ngit_version={s}\nauthoritative={s}\n",
        .{ &source_hex, &lock_hex, &build_hex, &git_hex, identity.git_version, if (identity.authoritative) "true" else "false" },
    );
    try stdout.interface.flush();
}

fn validateArguments(args: []const []const u8) !void {
    if (args.len < 3 or (args.len - 1) % 2 != 0) return error.InvalidArguments;
    var index: usize = 1;
    while (index < args.len) : (index += 2) {
        if (!std.mem.eql(u8, args[index], "--repo") and
            !std.mem.eql(u8, args[index], "--git") and
            !std.mem.eql(u8, args[index], "--commit")) return error.InvalidArguments;
    }
}

fn option(args: []const []const u8, name: []const u8) ![]const u8 {
    return (try optionalOption(args, name)) orelse error.InvalidArguments;
}

fn optionalOption(args: []const []const u8, name: []const u8) !?[]const u8 {
    if (args.len < 3 or (args.len - 1) % 2 != 0) return error.InvalidArguments;
    var result: ?[]const u8 = null;
    var index: usize = 1;
    while (index < args.len) : (index += 2) {
        if (!std.mem.startsWith(u8, args[index], "--") or args[index + 1].len == 0) return error.InvalidArguments;
        if (std.mem.eql(u8, args[index], name)) {
            if (result != null) return error.DuplicateOption;
            result = args[index + 1];
        }
    }
    return result;
}

fn collect(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo: []const u8,
    git: []const u8,
    commit: ?[]const u8,
) !Identity {
    try validateAbsolutePath(repo);
    try validateAbsolutePath(git);

    var environment = std.process.Environ.Map.init(allocator);
    defer environment.deinit();
    try environment.put("GIT_CONFIG_NOSYSTEM", "1");
    try environment.put("GIT_CONFIG_GLOBAL", if (builtin.os.tag == .windows) "NUL" else "/dev/null");
    try environment.put("GIT_CONFIG_SYSTEM", if (builtin.os.tag == .windows) "NUL" else "/dev/null");
    try environment.put("GIT_ATTR_NOSYSTEM", "1");
    try environment.put("GIT_NO_REPLACE_OBJECTS", "1");
    try environment.put("GIT_OPTIONAL_LOCKS", "0");
    try environment.put("GIT_TERMINAL_PROMPT", "0");
    try environment.put("GIT_PAGER", "cat");
    try environment.put("GIT_EDITOR", "true");
    try environment.put("GIT_SEQUENCE_EDITOR", "true");
    try environment.put("LC_ALL", "C");

    const git_version_output = try runGit(allocator, io, &environment, repo, git, &.{"--version"});
    defer allocator.free(git_version_output.stdout);
    defer allocator.free(git_version_output.stderr);
    const git_version_text = std.mem.trim(u8, git_version_output.stdout, " \t\r\n");
    if (!std.mem.startsWith(u8, git_version_text, "git version ") or git_version_text.len == "git version ".len) {
        return error.InvalidGitVersion;
    }
    for (git_version_text) |byte| {
        if (byte < 0x20 or byte == 0x7f) return error.InvalidGitVersion;
    }
    const git_version = try allocator.dupe(u8, git_version_text);
    errdefer allocator.free(git_version);
    const git_executable_sha256 = try hashAbsoluteFile(io, git);

    const object_format = try runGit(allocator, io, &environment, repo, git, &.{ "rev-parse", "--show-object-format" });
    defer allocator.free(object_format.stdout);
    defer allocator.free(object_format.stderr);
    if (!std.mem.eql(u8, std.mem.trimEnd(u8, object_format.stdout, "\r\n"), "sha1")) {
        return error.UnsupportedGitObjectFormat;
    }

    var index_file: ?std.Io.File = null;
    defer if (index_file) |*file| {
        file.unlock(io);
        file.close(io);
    };
    if (commit) |value| {
        try validateCommit(value);
        const commit_ref = try std.fmt.allocPrint(allocator, "{s}^{{commit}}", .{value});
        defer allocator.free(commit_ref);
        const verify = try runGit(allocator, io, &environment, repo, git, &.{ "cat-file", "-e", commit_ref });
        allocator.free(verify.stdout);
        allocator.free(verify.stderr);
        const head = try runGit(allocator, io, &environment, repo, git, &.{ "rev-parse", "--verify", "HEAD^{commit}" });
        defer allocator.free(head.stdout);
        defer allocator.free(head.stderr);
        if (!std.mem.eql(u8, std.mem.trimEnd(u8, head.stdout, "\r\n"), value)) return error.CommitNotHead;
        const status = try runGit(allocator, io, &environment, repo, git, &.{ "status", "--porcelain=v1", "--untracked-files=all", "--ignore-submodules=all", "--no-renames", "-z" });
        defer allocator.free(status.stdout);
        defer allocator.free(status.stderr);
        if (status.stdout.len != 0) return error.WorktreeDirty;
    } else {
        const index_name = try runGit(allocator, io, &environment, repo, git, &.{ "rev-parse", "--path-format=absolute", "--git-path", "index" });
        defer allocator.free(index_name.stdout);
        defer allocator.free(index_name.stderr);
        const index_path = try absoluteIndexPath(allocator, repo, std.mem.trimEnd(u8, index_name.stdout, "\r\n"));
        defer allocator.free(index_path);
        index_file = try std.Io.Dir.openFileAbsolute(io, index_path, .{});
        try index_file.?.lock(io, .shared);
    }

    const first_listing = if (commit) |value|
        try runGit(allocator, io, &environment, repo, git, &.{ "ls-tree", "-r", "--full-tree", "--long", "-z", value })
    else
        try runGit(allocator, io, &environment, repo, git, &.{ "ls-files", "--cached", "--stage", "--full-name", "-z" });
    defer allocator.free(first_listing.stdout);
    defer allocator.free(first_listing.stderr);
    var entries: std.ArrayList(Entry) = .empty;
    defer {
        for (entries.items) |entry| allocator.free(entry.path);
        entries.deinit(allocator);
    }
    if (commit != null) {
        try parseTreeListing(allocator, first_listing.stdout, &entries);
    } else {
        try parseListing(allocator, first_listing.stdout, &entries);
    }
    try validateCanonicalPaths(allocator, entries.items);

    const second_listing = if (commit) |value|
        try runGit(allocator, io, &environment, repo, git, &.{ "ls-tree", "-r", "--full-tree", "--long", "-z", value })
    else
        try runGit(allocator, io, &environment, repo, git, &.{ "ls-files", "--cached", "--stage", "--full-name", "-z" });
    defer allocator.free(second_listing.stdout);
    defer allocator.free(second_listing.stderr);
    if (!std.mem.eql(u8, first_listing.stdout, second_listing.stdout)) return error.IndexChanged;

    try populateBlobDigests(allocator, io, &environment, repo, git, &entries);
    if (commit != null) try verifyBuildInputWorktree(io, repo, entries.items);

    const source_set_sha256 = hashSourceSet(entries.items);
    const dependency_lock_sha256 = dependencyLockDigest(entries.items) orelse return error.DependencyLockMissing;
    const build_identity = composeBuildIdentity(source_set_sha256, dependency_lock_sha256);

    var clean = true;
    if (commit == null) {
        const status = try runGit(allocator, io, &environment, repo, git, &.{ "status", "--porcelain=v1", "--untracked-files=all", "--ignore-submodules=all", "--no-renames", "-z" });
        defer allocator.free(status.stdout);
        defer allocator.free(status.stderr);
        clean = status.stdout.len == 0;
    }
    return .{
        .source_set_sha256 = source_set_sha256,
        .dependency_lock_sha256 = dependency_lock_sha256,
        .build_identity = build_identity,
        .git_executable_sha256 = git_executable_sha256,
        .git_version = git_version,
        .authoritative = commit != null or clean,
    };
}

const GitOutput = struct { stdout: []u8, stderr: []u8 };

fn hashAbsoluteFile(io: std.Io, path: []const u8) ![32]u8 {
    // Keep a no-follow identity handle even though the readable Windows
    // handle may need normal reparse resolution for Git-for-Windows
    // launchers. Bind both handles by file identity and size before and
    // after the read, so a path swap fails closed.
    var identity = std.Io.Dir.openFileAbsolute(io, path, .{
        .allow_directory = false,
        // Git for Windows is commonly exposed through a launcher path under
        // `Git\\cmd`; the standard library's Windows no-follow handle is
        // not readable on every supported filesystem. Hash the exact
        // resolved executable path selected by the caller, while the Git
        // command itself remains an absolute argv entry.
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch return error.GitExecutableUnreadable;
    defer identity.close(io);
    const before = identity.stat(io) catch return error.GitExecutableUnreadable;
    if (before.kind != .file or before.size == 0 or before.size > max_blob_output) {
        return error.GitExecutableUnreadable;
    }
    var file = std.Io.Dir.openFileAbsolute(io, path, .{
        .allow_directory = false,
        .follow_symlinks = true,
        .resolve_beneath = true,
    }) catch return error.GitExecutableUnreadable;
    defer file.close(io);
    const opened = file.stat(io) catch return error.GitExecutableUnreadable;
    if (opened.kind != .file or opened.inode != before.inode or opened.size != before.size) {
        return error.GitExecutableChanged;
    }
    var reader_buffer: [16 * 1024]u8 = undefined;
    var chunk: [64 * 1024]u8 = undefined;
    var reader = file.reader(io, &reader_buffer);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var bytes: u64 = 0;
    while (true) {
        const count = reader.interface.readSliceShort(&chunk) catch return error.GitExecutableUnreadable;
        if (count == 0) break;
        bytes = std.math.add(u64, bytes, count) catch return error.GitExecutableUnreadable;
        if (bytes > max_blob_output) return error.GitExecutableUnreadable;
        hasher.update(chunk[0..count]);
    }
    const after = file.stat(io) catch return error.GitExecutableUnreadable;
    if (after.kind != .file or after.inode != before.inode or after.size != before.size or bytes != before.size) {
        return error.GitExecutableChanged;
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn runGit(
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    repo: []const u8,
    git: []const u8,
    args: []const []const u8,
) !GitOutput {
    var argv: [16][]const u8 = undefined;
    if (args.len + 1 > argv.len) return error.InvalidArguments;
    argv[0] = git;
    @memcpy(argv[1 .. args.len + 1], args);
    const result = try std.process.run(allocator, io, .{
        .argv = argv[0 .. args.len + 1],
        .cwd = .{ .path = repo },
        .environ_map = environment,
        .stdout_limit = .limited(max_index_output),
        .stderr_limit = .limited(64 * 1024),
        .timeout = .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(30) } },
    });
    if (result.term != .exited or result.term.exited != 0) {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
        return error.GitCommandFailed;
    }
    return .{ .stdout = result.stdout, .stderr = result.stderr };
}

fn validateCommit(commit: []const u8) !void {
    if (!isLowerHex(commit, 40)) return error.InvalidCommit;
}

fn parseTreeListing(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    entries: *std.ArrayList(Entry),
) !void {
    var cursor: usize = 0;
    var previous: ?[]const u8 = null;
    while (cursor < bytes.len) {
        const terminator = std.mem.indexOfScalarPos(u8, bytes, cursor, 0) orelse return error.MalformedTreeListing;
        const record = bytes[cursor..terminator];
        cursor = terminator + 1;
        const tab = std.mem.indexOfScalar(u8, record, '\t') orelse return error.MalformedTreeListing;
        const header = record[0..tab];
        const path = record[tab + 1 ..];
        var fields = std.mem.tokenizeScalar(u8, header, ' ');
        const mode_text = fields.next() orelse return error.MalformedTreeListing;
        const kind = fields.next() orelse return error.MalformedTreeListing;
        const oid_text = fields.next() orelse return error.MalformedTreeListing;
        const size_text = fields.next() orelse return error.MalformedTreeListing;
        if (fields.next() != null or !std.mem.eql(u8, kind, "blob") or
            mode_text.len != 6 or !std.mem.eql(u8, mode_text, "100644") and
            !std.mem.eql(u8, mode_text, "100755") or !isLowerHex(oid_text, 40))
        {
            return error.UnsupportedTreeEntry;
        }
        const content_length = std.fmt.parseUnsigned(u64, size_text, 10) catch return error.MalformedTreeListing;
        try validatePath(path);
        if (std.mem.startsWith(u8, path, evidence_prefix)) continue;
        if (previous) |old| if (std.mem.order(u8, old, path) != .lt) return error.UnsortedTree;
        const owned_path = try allocator.dupe(u8, path);
        errdefer allocator.free(owned_path);
        var entry = Entry{
            .path = owned_path,
            .mode = undefined,
            .oid = undefined,
            .content_length_known = true,
            .content_length = content_length,
            .blob_sha256 = undefined,
        };
        @memcpy(&entry.mode, mode_text);
        @memcpy(&entry.oid, oid_text);
        try entries.append(allocator, entry);
        previous = entries.items[entries.items.len - 1].path;
    }
    if (entries.items.len == 0) return error.EmptySourceSet;
}

fn validateCanonicalPaths(allocator: std.mem.Allocator, entries: []const Entry) !void {
    var keys = std.StringHashMap(void).init(allocator);
    defer {
        var iterator = keys.keyIterator();
        while (iterator.next()) |key| allocator.free(key.*);
        keys.deinit();
    }

    for (entries) |entry| {
        const key = try canonicalPathKey(allocator, entry.path);
        errdefer allocator.free(key);
        if ((try keys.getOrPut(key)).found_existing) return error.PathCollision;
    }
    var iterator = keys.keyIterator();
    while (iterator.next()) |key| {
        for (key.*, 0..) |byte, index| {
            if (byte == '/' and keys.contains(key.*[0..index])) return error.PathCollision;
        }
    }
}

fn canonicalPathKey(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return source_unicode.foldNfd(allocator, path, std.math.maxInt(usize));
}

fn parseListing(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    entries: *std.ArrayList(Entry),
) !void {
    var cursor: usize = 0;
    var previous: ?[]const u8 = null;
    while (cursor < bytes.len) {
        const terminator = std.mem.indexOfScalarPos(u8, bytes, cursor, 0) orelse return error.MalformedIndexListing;
        const record = bytes[cursor..terminator];
        cursor = terminator + 1;
        const tab = std.mem.indexOfScalar(u8, record, '\t') orelse return error.MalformedIndexListing;
        const header = record[0..tab];
        const path = record[tab + 1 ..];
        var fields = std.mem.splitScalar(u8, header, ' ');
        const mode_text = fields.next() orelse return error.MalformedIndexListing;
        const oid_text = fields.next() orelse return error.MalformedIndexListing;
        const stage_text = fields.next() orelse return error.MalformedIndexListing;
        if (fields.next() != null or mode_text.len != 6 or oid_text.len != 40 or !std.mem.eql(u8, stage_text, "0")) {
            return error.MalformedIndexListing;
        }
        if ((!std.mem.eql(u8, mode_text, "100644") and !std.mem.eql(u8, mode_text, "100755")) or !isLowerHex(oid_text, 40)) {
            return error.UnsupportedIndexEntry;
        }
        try validatePath(path);
        if (std.mem.startsWith(u8, path, evidence_prefix)) continue;
        if (previous) |old| if (std.mem.order(u8, old, path) != .lt) return error.UnsortedIndex;
        const owned_path = try allocator.dupe(u8, path);
        errdefer allocator.free(owned_path);
        var entry = Entry{
            .path = owned_path,
            .mode = undefined,
            .oid = undefined,
            .content_length_known = false,
            .content_length = 0,
            .blob_sha256 = undefined,
        };
        @memcpy(&entry.mode, mode_text);
        @memcpy(&entry.oid, oid_text);
        try entries.append(allocator, entry);
        previous = entries.items[entries.items.len - 1].path;
    }
    if (entries.items.len == 0) return error.EmptySourceSet;
}

fn populateBlobDigests(
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    repo: []const u8,
    git: []const u8,
    entries: *std.ArrayList(Entry),
) !void {
    var child = try std.process.spawn(io, .{
        .argv = &.{ git, "cat-file", "--batch" },
        .cwd = .{ .path = repo },
        .environ_map = environment,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .ignore,
        .create_no_window = true,
    });
    defer child.kill(io);

    var stdout = child.stdout.?;
    var reader_buffer: [16 * 1024]u8 = undefined;
    var reader = stdout.readerStreaming(io, &reader_buffer);

    for (entries.items) |*entry| {
        try child.stdin.?.writeStreamingAll(io, &entry.oid);
        try child.stdin.?.writeStreamingAll(io, "\n");
        const line = try reader.interface.takeDelimiterInclusive('\n');
        if (line.len == 0) return error.MalformedBatchOutput;
        const header = line[0 .. line.len - 1];
        var fields = std.mem.splitScalar(u8, header, ' ');
        const oid_text = fields.next() orelse return error.MalformedBatchOutput;
        const kind = fields.next() orelse return error.MalformedBatchOutput;
        const size_text = fields.next() orelse return error.MalformedBatchOutput;
        if (fields.next() != null or !std.mem.eql(u8, oid_text, &entry.oid) or !std.mem.eql(u8, kind, "blob")) {
            return error.MalformedBatchOutput;
        }
        const size = std.fmt.parseInt(usize, size_text, 10) catch return error.MalformedBatchOutput;
        if (size > max_blob_output) return error.BlobTooLarge;
        if (entry.content_length_known and entry.content_length != size) return error.BlobLengthMismatch;
        const blob = try allocator.alloc(u8, size);
        defer allocator.free(blob);
        if (blob.len != 0) try reader.interface.readSliceAll(blob);
        var terminator: [1]u8 = undefined;
        try reader.interface.readSliceAll(&terminator);
        if (terminator[0] != '\n') return error.MalformedBatchOutput;
        entry.content_length = size;
        std.crypto.hash.sha2.Sha256.hash(blob, &entry.blob_sha256, .{});
        var sha1 = std.crypto.hash.Sha1.init(.{});
        var header_bytes: [64]u8 = undefined;
        const header_len = std.fmt.bufPrint(&header_bytes, "blob {d}\x00", .{size}) catch return error.BlobTooLarge;
        sha1.update(header_len);
        sha1.update(blob);
        var oid: [20]u8 = undefined;
        sha1.final(&oid);
        const computed_oid = std.fmt.bytesToHex(oid, .lower);
        if (!std.mem.eql(u8, &computed_oid, &entry.oid)) return error.BlobIdentityMismatch;
    }

    child.stdin.?.close(io);
    child.stdin = null;

    const term = try child.wait(io);
    if (term != .exited or term.exited != 0) return error.GitCommandFailed;
}

fn isBuildInputPath(path: []const u8) bool {
    return std.mem.eql(u8, path, "build.zig") or
        std.mem.eql(u8, path, "build.zig.zon") or
        std.mem.startsWith(u8, path, "native/zig/") or
        std.mem.startsWith(u8, path, "tools/zig/") or
        std.mem.eql(u8, path, "docs/assets/texflow-app-mark.svg");
}

fn verifyBuildInputWorktree(
    io: std.Io,
    repo: []const u8,
    entries: []const Entry,
) !void {
    var root = try std.Io.Dir.openDirAbsolute(io, repo, .{ .follow_symlinks = false });
    defer root.close(io);
    var reader_buffer: [16 * 1024]u8 = undefined;
    var chunk: [64 * 1024]u8 = undefined;
    for (entries) |entry| {
        if (!isBuildInputPath(entry.path)) continue;
        var file = root.openFile(io, entry.path, .{
            .follow_symlinks = false,
            .resolve_beneath = true,
        }) catch return error.WorktreeFileMismatch;
        const stat = file.stat(io) catch {
            file.close(io);
            return error.WorktreeFileMismatch;
        };
        if (stat.kind != .file or stat.size != entry.content_length) {
            file.close(io);
            return error.WorktreeFileMismatch;
        }
        var reader = file.readerStreaming(io, &reader_buffer);
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        var bytes: u64 = 0;
        while (true) {
            const count = reader.interface.readSliceShort(&chunk) catch {
                file.close(io);
                return error.WorktreeFileMismatch;
            };
            if (count == 0) break;
            bytes = std.math.add(u64, bytes, count) catch {
                file.close(io);
                return error.WorktreeFileMismatch;
            };
            hasher.update(chunk[0..count]);
        }
        if (bytes != entry.content_length) {
            file.close(io);
            return error.WorktreeFileMismatch;
        }
        var digest: [32]u8 = undefined;
        hasher.final(&digest);
        file.close(io);
        if (!std.mem.eql(u8, &digest, &entry.blob_sha256)) return error.WorktreeFileMismatch;
    }
}

fn hashSourceSet(entries: []const Entry) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(source_domain);
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, entries.len, .little);
    hasher.update(&count);
    for (entries) |entry| {
        var path_length: [4]u8 = undefined;
        std.mem.writeInt(u32, &path_length, @intCast(entry.path.len), .little);
        hasher.update(&path_length);
        hasher.update(entry.path);
        hasher.update(&entry.mode);
        var content_length: [8]u8 = undefined;
        std.mem.writeInt(u64, &content_length, entry.content_length, .little);
        hasher.update(&content_length);
        hasher.update(&entry.blob_sha256);
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn dependencyLockDigest(entries: []const Entry) ?[32]u8 {
    for (entries) |entry| if (std.mem.eql(u8, entry.path, "tools/zig/native-deps.json")) return entry.blob_sha256;
    return null;
}

fn composeBuildIdentity(source: [32]u8, lock: [32]u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(build_domain);
    hasher.update(&source);
    hasher.update(&lock);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn absoluteIndexPath(allocator: std.mem.Allocator, repo: []const u8, value: []const u8) ![]u8 {
    if (std.Io.Dir.path.isAbsolute(value)) return allocator.dupe(u8, value);
    return std.fs.path.join(allocator, &.{ repo, value });
}

fn validateAbsolutePath(path: []const u8) !void {
    if (path.len == 0 or !std.Io.Dir.path.isAbsolute(path) or path[path.len - 1] == '/' or path[path.len - 1] == '\\') {
        return error.UnsafePath;
    }
    if (!std.unicode.utf8ValidateSlice(path)) return error.UnsafePath;
}

fn validatePath(path: []const u8) !void {
    if (path.len == 0 or path[0] == '/' or !std.unicode.utf8ValidateSlice(path)) return error.UnsafeSourcePath;
    var utf8 = std.unicode.Utf8View.init(path) catch return error.UnsafeSourcePath;
    var codepoints = utf8.iterator();
    while (codepoints.nextCodepoint()) |codepoint| {
        if (codepoint < 0x20 or (codepoint >= 0x7f and codepoint <= 0x9f)) return error.UnsafeSourcePath;
    }
    for (path) |byte| switch (byte) {
        '\\', ':', '"', '*', '?', '<', '>', '|' => return error.UnsafeSourcePath,
        else => {},
    };
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return error.UnsafeSourcePath;
        const last = component[component.len - 1];
        if (last == '.' or last == ' ' or isReservedDevice(component)) return error.UnsafeSourcePath;
    }
}

fn isReservedDevice(component: []const u8) bool {
    const extension = std.mem.indexOfScalar(u8, component, '.') orelse component.len;
    const stem = std.mem.trimEnd(u8, component[0..extension], " ");
    for ([_][]const u8{ "CON", "PRN", "AUX", "NUL", "CLOCK$", "CONIN$", "CONOUT$" }) |reserved| {
        if (std.ascii.eqlIgnoreCase(stem, reserved)) return true;
    }
    if (stem.len < 4 or (!std.ascii.eqlIgnoreCase(stem[0..3], "COM") and
        !std.ascii.eqlIgnoreCase(stem[0..3], "LPT"))) return false;
    if (stem.len == 4) return stem[3] >= '1' and stem[3] <= '9';
    return stem.len == 5 and stem[3] == 0xc2 and (stem[4] == 0xb9 or stem[4] == 0xb2 or stem[4] == 0xb3);
}

fn isLowerHex(value: []const u8, expected_len: usize) bool {
    if (value.len != expected_len) return false;
    for (value) |byte| if (!((byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f'))) return false;
    return true;
}

test "source identity folds Unicode-17 canonical aliases" {
    const composed = try canonicalPathKey(std.testing.allocator, "caf\u{e9}/Straße.tex");
    defer std.testing.allocator.free(composed);
    const decomposed = try canonicalPathKey(std.testing.allocator, "cafe\u{301}/STRASSE.TEX");
    defer std.testing.allocator.free(decomposed);
    try std.testing.expectEqualStrings(composed, decomposed);
}
