//! Offline Lexilla 5.5.3 source and comparator contract probe.
const std = @import("std");
const deps = @import("deps");

pub const version = "5.5.3";
pub const archive_sha256 = "4d9e64263c337034a06f9c67f330c605764cac02aee83c06f6c21f9527a71628";
pub const license_spdx = "LicenseRef-Lexilla";
pub const license_sha256 = "ac32743bd464c837e481beae20df65a9207f84d3ff1912f6003000343e9c753d";
pub const artifact_name = "lexilla-comparator-t0-2b-unshipped";

// Lexilla's static make recipe keeps the reusable lexlib objects and only the
// three reviewed LaTeX/BibTeX lexers. The catalogue/loader source is not part
// of this test-only comparator.
pub const sources = [_][]const u8{
    "lexlib/Accessor.cxx",
    "lexlib/CharacterCategory.cxx",
    "lexlib/CharacterSet.cxx",
    "lexlib/DefaultLexer.cxx",
    "lexlib/InList.cxx",
    "lexlib/LexAccessor.cxx",
    "lexlib/LexerBase.cxx",
    "lexlib/LexerModule.cxx",
    "lexlib/LexerSimple.cxx",
    "lexlib/PropSetSimple.cxx",
    "lexlib/StyleContext.cxx",
    "lexlib/WordList.cxx",
    "lexers/LexBibTeX.cxx",
    "lexers/LexLaTeX.cxx",
    "lexers/LexTeX.cxx",
};

pub const archive_member_names = [_][]const u8{
    "Accessor.obj",
    "CharacterCategory.obj",
    "CharacterSet.obj",
    "DefaultLexer.obj",
    "InList.obj",
    "LexAccessor.obj",
    "LexerBase.obj",
    "LexerModule.obj",
    "LexerSimple.obj",
    "PropSetSimple.obj",
    "StyleContext.obj",
    "WordList.obj",
    "LexBibTeX.obj",
    "LexLaTeX.obj",
    "LexTeX.obj",
};

pub const reviewed_fixtures = [_][]const u8{
    "latex/minimal-document.tex",
    "bibtex/minimal-entry.bib",
};

pub fn cxxFlags(comptime mode: std.builtin.OptimizeMode) []const []const u8 {
    return &.{ "-std=c++17", "-Wall", "-Wextra", "-Wpedantic", if (mode == .Debug) "-DDEBUG" else "-DNDEBUG" };
}

pub fn verifySourceList(actual: []const []const u8) !void {
    if (actual.len != sources.len) return error.SourceInventoryMismatch;
    for (sources) |expected| {
        var count: usize = 0;
        for (actual) |path| {
            if (std.mem.eql(u8, path, expected)) count += 1;
        }
        if (count != 1) return error.SourceInventoryMismatch;
    }
}

pub fn verifyLockedIdentity(artifact: deps.Artifact) !void {
    const size = artifact.archive_size_bytes orelse return error.LockIdentityMismatch;
    const digest = artifact.archive_sha256 orelse return error.LockIdentityMismatch;
    if (!std.mem.eql(u8, artifact.version, version) or
        !std.mem.eql(u8, artifact.license_spdx, license_spdx) or
        size != 1_116_541 or
        !std.mem.eql(u8, digest, archive_sha256) or
        artifact.integrity != .byte_archive or
        artifact.archive_format != .tar_gzip or
        !std.mem.eql(u8, artifact.archive_root, "lexilla/")) return error.LockIdentityMismatch;
}

fn lockReceiptBytes(buffer: []u8, artifact: deps.Artifact) ![]const u8 {
    const size = artifact.archive_size_bytes orelse return error.LockIdentityMismatch;
    const digest = artifact.archive_sha256 orelse return error.LockIdentityMismatch;
    return std.fmt.bufPrint(
        buffer,
        "artifact_id={s}\nversion={s}\nlicense_spdx={s}\narchive_size_bytes={d}\narchive_sha256={s}\nlicense_sha256={s}\n",
        .{ artifact.id, artifact.version, artifact.license_spdx, size, digest, license_sha256 },
    ) catch error.LockReceiptTooLarge;
}

pub fn verifyLockReceiptBytes(bytes: []const u8) !void {
    var expected: [512]u8 = undefined;
    const actual = try std.fmt.bufPrint(
        &expected,
        "artifact_id=lexilla\nversion={s}\nlicense_spdx={s}\narchive_size_bytes=1116541\narchive_sha256={s}\nlicense_sha256={s}\n",
        .{ version, license_spdx, archive_sha256, license_sha256 },
    );
    if (!std.mem.eql(u8, bytes, actual)) return error.LockReceiptMismatch;
}

pub fn verifyMemberNames(actual: []const []const u8) !void {
    if (actual.len != archive_member_names.len) return error.ArchiveMemberMismatch;
    for (actual, 0..) |name, index| {
        for (actual[0..index]) |previous| {
            if (std.mem.eql(u8, name, previous)) return error.ArchiveMemberMismatch;
        }
        var expected = false;
        for (archive_member_names) |reviewed| {
            if (std.mem.eql(u8, name, reviewed)) {
                expected = true;
                break;
            }
        }
        if (!expected) return error.ArchiveMemberMismatch;
    }
}

pub fn verifyArchive(bytes: []const u8) !void {
    if (bytes.len != 1_116_541) return error.SourceArchiveSizeMismatch;
    try deps.verifySha256(bytes, archive_sha256);
}

pub fn verifyLicense(bytes: []const u8) !void {
    try deps.verifySha256(bytes, license_sha256);
}

fn parseArchiveSize(field: []const u8) !usize {
    return std.fmt.parseInt(usize, std.mem.trim(u8, field, " "), 10) catch error.ArchiveFormatMismatch;
}

fn isArchivePathSeparator(byte: u8) bool {
    return byte == '/' or byte == '\\';
}

fn verifyLongMemberPath(name: []const u8) !void {
    // Zig's MSVC archive writer emits exactly this relative shape. Requiring
    // the root and segment count prevents a long-name alias from smuggling an
    // extra prefix, traversal segment, or nested cache directory before the
    // basename is normalized.
    var segments: [4][]const u8 = undefined;
    var segment_count: usize = 0;
    var segment_start: usize = 0;
    for (name, 0..) |byte, index| {
        if (!isArchivePathSeparator(byte)) continue;
        if (index == segment_start or segment_count == segments.len) return error.ArchiveMemberNameMismatch;
        segments[segment_count] = name[segment_start..index];
        segment_count += 1;
        segment_start = index + 1;
    }
    if (segment_start >= name.len or segment_count == segments.len) return error.ArchiveMemberNameMismatch;
    segments[segment_count] = name[segment_start..];
    segment_count += 1;
    if (segment_count != segments.len or !std.mem.eql(u8, segments[0], ".zig-cache") or
        !std.mem.eql(u8, segments[1], "o")) return error.ArchiveMemberNameMismatch;

    const hash = segments[2];
    if (hash.len != 32) return error.ArchiveMemberNameMismatch;
    for (hash) |byte| {
        if (!std.ascii.isHex(byte)) return error.ArchiveMemberNameMismatch;
    }
    if (!std.mem.endsWith(u8, segments[3], ".obj")) return error.ArchiveMemberNameMismatch;
}

pub fn verifyArchiveMemberPath(name: []const u8) !void {
    try verifyLongMemberPath(name);
}

fn resolveArchiveMemberName(raw: []const u8, longnames: []const u8) ![]const u8 {
    if (std.mem.eql(u8, raw, "/") or std.mem.eql(u8, raw, "//")) return "";
    if (raw.len > 0 and raw[0] == '/') {
        const index = std.fmt.parseInt(usize, raw[1..], 10) catch return error.ArchiveMemberNameMismatch;
        if (index >= longnames.len) return error.ArchiveMemberNameMismatch;
        const tail = longnames[index..];
        var end: usize = 0;
        while (end < tail.len and tail[end] != 0 and
            !(end + 1 < tail.len and tail[end] == '/' and tail[end + 1] == '\n')) : (end += 1)
        {}
        if (end == 0 or end >= tail.len) return error.ArchiveMemberNameMismatch;
        try verifyLongMemberPath(tail[0..end]);
        return archiveMemberBasename(tail[0..end]);
    }
    var name = raw;
    if (name.len > 0 and name[name.len - 1] == '/') name = name[0 .. name.len - 1];
    for (name) |byte| {
        if (isArchivePathSeparator(byte)) return error.ArchiveMemberNameMismatch;
    }
    return archiveMemberBasename(name);
}

fn archiveMemberBasename(name: []const u8) []const u8 {
    var start: usize = 0;
    for (name, 0..) |byte, index| {
        if (byte == '/' or byte == '\\') start = index + 1;
    }
    return name[start..];
}

pub fn verifyCoffArchive(bytes: []const u8) !void {
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..8], "!<arch>\n")) return error.ArchiveFormatMismatch;
    var longnames: []const u8 = "";
    var actual: [archive_member_names.len][]const u8 = undefined;
    var count: usize = 0;
    var linker_member_count: usize = 0;
    var longname_member_count: usize = 0;
    var offset: usize = 8;
    while (offset < bytes.len) {
        if (bytes.len - offset < 60) return error.ArchiveFormatMismatch;
        const header = bytes[offset .. offset + 60];
        if (!std.mem.eql(u8, header[58..60], "`\n")) return error.ArchiveFormatMismatch;
        const size = try parseArchiveSize(header[48..58]);
        const data_start = offset + 60;
        if (size > bytes.len - data_start) return error.ArchiveFormatMismatch;
        const data_end = data_start + size;
        const raw_name = std.mem.trim(u8, header[0..16], " ");
        if (std.mem.eql(u8, raw_name, "//")) {
            longname_member_count += 1;
            if (longname_member_count > 1) return error.ArchiveFormatMismatch;
            longnames = bytes[data_start..data_end];
        } else if (std.mem.eql(u8, raw_name, "/")) {
            linker_member_count += 1;
            if (linker_member_count > 2) return error.ArchiveFormatMismatch;
        } else {
            if (count == actual.len) return error.ArchiveMemberMismatch;
            actual[count] = try resolveArchiveMemberName(raw_name, longnames);
            count += 1;
        }
        offset = data_end + (size & 1);
    }
    if (linker_member_count != 2 or longname_member_count != 1 or count != archive_member_names.len) {
        return error.ArchiveMemberMismatch;
    }
    try verifyMemberNames(actual[0..count]);
}

pub fn verifySourceRoot(allocator: std.mem.Allocator, io: std.Io, source_root: []const u8) !void {
    if (source_root.len == 0) return error.InvalidSnapshotPath;
    var root = try std.Io.Dir.cwd().openDir(io, source_root, .{ .iterate = true, .follow_symlinks = false });
    defer root.close(io);

    const version_bytes = try root.readFileAlloc(io, "version.txt", allocator, .limited(32));
    defer allocator.free(version_bytes);
    if (!std.mem.eql(u8, std.mem.trim(u8, version_bytes, "\r\n"), "553")) return error.SourceVersionMismatch;

    const license_bytes = try root.readFileAlloc(io, "License.txt", allocator, .limited(16 * 1024));
    defer allocator.free(license_bytes);
    try verifyLicense(license_bytes);

    for (sources) |path| {
        var file = try root.openFile(io, path, .{ .follow_symlinks = false, .resolve_beneath = true });
        file.close(io);
    }
}

pub fn verifyArtifact(allocator: std.mem.Allocator, io: std.Io, artifact_path: []const u8) !u64 {
    if (artifact_path.len == 0) return error.InvalidArtifactPath;
    if (!std.mem.eql(u8, std.fs.path.extension(artifact_path), ".lib")) return error.DynamicArtifactRejected;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, artifact_path, allocator, .limited(64 * 1024 * 1024));
    defer allocator.free(bytes);
    return verifyArtifactBytes(bytes);
}

pub fn verifyArtifactBytes(bytes: []const u8) !u64 {
    if (bytes.len == 0) return error.EmptyComparatorArtifact;

    // Parse the emitted COFF archive itself rather than trusting the build
    // source list or a substring search. This rejects extra, duplicate, and
    // long-name object members as well as missing reviewed objects.
    try verifyCoffArchive(bytes);
    try verifyForbiddenSymbols(bytes);
    std.debug.print("Lexilla comparator measured archive bytes={d}\n", .{bytes.len});
    return bytes.len;
}

pub const ShippingAudit = struct {
    member_present: bool,
    payload_bytes: u64,
};

pub fn auditShippingManifest(
    allocator: std.mem.Allocator,
    io: std.Io,
    manifest_path: []const u8,
    artifact_path: []const u8,
) !ShippingAudit {
    if (manifest_path.len == 0) return error.InvalidShippingManifestPath;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(64 * 1024));
    defer allocator.free(bytes);
    const expected_member = artifact_name ++ ".lib";
    var member_present = false;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (!std.mem.eql(u8, line, expected_member) or member_present) return error.ShippingManifestMismatch;
        member_present = true;
    }
    if (!member_present) {
        std.debug.print("Lexilla shipping manifest member=false payload bytes=0\n", .{});
        return .{ .member_present = false, .payload_bytes = 0 };
    }
    if (artifact_path.len == 0) return error.ShippingManifestMismatch;
    const payload_bytes = try verifyArtifact(allocator, io, artifact_path);
    std.debug.print("Lexilla shipping manifest member=true payload bytes={d}\n", .{payload_bytes});
    return .{ .member_present = true, .payload_bytes = payload_bytes };
}

pub fn verifyForbiddenSymbols(bytes: []const u8) !void {
    for ([_][]const u8{
        ".dll",
        ".so",
        ".dylib",
        "Lexilla.cxx",
        "LexillaVersion",
        "CatalogueModules",
        "LexerCatalogue",
        "LoadLexerLibrary",
        "LexillaLoader",
        "GetLexerCount",
        "GetLexerName",
        "GetLexerFactory",
        "CreateLexer",
        "AddLexerModule",
        "catalogueLexilla",
        "LexillaAccess",
    }) |banned| {
        if (std.mem.indexOf(u8, bytes, banned) != null) return error.CatalogueOrLoaderSymbolPresent;
    }
}

pub fn verifyContract() !void {
    try verifySourceList(&sources);
}

/// Materialize only from the locked archive bytes. Existing verified trees are
/// reused after a complete rehash; publication is staged and rename-based.
pub fn snapshot(allocator: std.mem.Allocator, io: std.Io, archive_path: []const u8, output: []const u8) !void {
    if (!std.fs.path.isAbsolute(archive_path)) return error.SourceArchiveMustBeAbsolute;
    if (!std.fs.path.isAbsolute(output)) return error.SourceSnapshotMustBeAbsolute;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, archive_path, allocator, .limited(1_116_542));
    defer allocator.free(bytes);
    try verifyArchive(bytes);
    const manifest = try deps.parseLockedManifest(allocator);
    defer manifest.deinit();
    const artifact = deps.findArtifact(manifest.value, "lexilla") orelse return error.MissingLexillaLock;
    try verifyLockedIdentity(artifact);
    const expected = try deps.materializeArtifact(allocator, io, artifact, bytes, null, deps.asciiCollisionFold);
    const parent_path = std.fs.path.dirname(output) orelse return error.InvalidSnapshotPath;
    var parent = try std.Io.Dir.openDirAbsolute(io, parent_path, .{ .follow_symlinks = false });
    defer parent.close(io);
    const name = std.fs.path.basename(output);
    if (try verifyPublished(allocator, io, parent, name, expected, artifact)) return;

    var random: [16]u8 = undefined;
    io.random(&random);
    const hex = std.fmt.bytesToHex(random, .lower);
    var stage_buffer: [64]u8 = undefined;
    const stage_name = try std.fmt.bufPrint(&stage_buffer, ".lexilla-stage-{s}", .{hex});
    try parent.createDir(io, stage_name, .default_dir);
    defer parent.deleteTree(io, stage_name) catch {};
    {
        var stage = try parent.openDir(io, stage_name, .{ .iterate = true, .follow_symlinks = false });
        defer stage.close(io);
        _ = try deps.materializeArtifact(allocator, io, artifact, bytes, stage, deps.asciiCollisionFold);
        try verifyTree(allocator, io, stage, expected);
    }
    parent.renamePreserve(stage_name, parent, name, io) catch |err| switch (err) {
        error.PathAlreadyExists, error.AccessDenied => {
            if (try verifyPublished(allocator, io, parent, name, expected, artifact)) return;
            return err;
        },
        else => return err,
    };
    try writeLockReceipt(io, parent, name, artifact);
}

fn verifyPublished(
    allocator: std.mem.Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    name: []const u8,
    expected: deps.MaterializedArchive,
    artifact: deps.Artifact,
) !bool {
    var published = parent.openDir(io, name, .{ .iterate = true, .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer published.close(io);
    try verifyTree(allocator, io, published, expected);
    const receipt_name = try std.fmt.allocPrint(allocator, "{s}.lock.json", .{name});
    defer allocator.free(receipt_name);
    const receipt = parent.readFileAlloc(io, receipt_name, allocator, .limited(512)) catch |err| switch (err) {
        error.FileNotFound => {
            try writeLockReceipt(io, parent, name, artifact);
            return true;
        },
        else => return err,
    };
    defer allocator.free(receipt);
    try verifyLockReceiptBytes(receipt);
    return true;
}

fn writeLockReceipt(io: std.Io, parent: std.Io.Dir, name: []const u8, artifact: deps.Artifact) !void {
    var receipt_name: [256]u8 = undefined;
    const receipt_path = try std.fmt.bufPrint(&receipt_name, "{s}.lock.json", .{name});
    var receipt_bytes: [512]u8 = undefined;
    const bytes = try lockReceiptBytes(&receipt_bytes, artifact);
    try parent.writeFile(io, .{ .sub_path = receipt_path, .data = bytes });
}

fn verifyTree(allocator: std.mem.Allocator, io: std.Io, directory: std.Io.Dir, expected: deps.MaterializedArchive) !void {
    const actual = try deps.hashMaterializedDirectory(allocator, io, directory, 64 * 1024 * 1024);
    if (actual.files != expected.payload_files or actual.bytes != expected.payload_bytes or
        !std.mem.eql(u8, &actual.digest, &expected.payload_sha256)) return error.SourceSnapshotMismatch;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4 or !std.mem.eql(u8, args[1], "snapshot")) return error.InvalidArguments;
    const output = try std.fs.path.join(init.arena.allocator(), &.{ args[3], "payload" });
    snapshot(init.gpa, init.io, args[2], output) catch |err| {
        std.debug.print("Lexilla 5.5.3 offline source contract failed ({s}); -Dlexilla-archive must name the exact locked archive. No fallback or fetch.\n", .{@errorName(err)});
        return err;
    };
}
