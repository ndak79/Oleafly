//! Offline Scintilla 5.6.6 source and static build contract probe.
const std = @import("std");
const deps = @import("deps");

pub const version = "5.6.6";
pub const archive_sha256 = "b6b08598c68fac90990d010c1142494d707530602b5320753274d045c2b02189";

// win32/scintilla.mak: SRC_OBJS plus COMPONENT_OBJS, never SHARED_OBJS.
pub const sources = [_][]const u8{
    "src/AutoComplete.cxx",  "src/CallTip.cxx",          "src/CaseConvert.cxx",          "src/CaseFolder.cxx",
    "src/CellBuffer.cxx",    "src/ChangeHistory.cxx",    "src/CharacterCategoryMap.cxx", "src/CharacterType.cxx",
    "src/CharClassify.cxx",  "src/ContractionState.cxx", "src/DBCS.cxx",                 "src/Decoration.cxx",
    "src/Document.cxx",      "src/EditModel.cxx",        "src/Editor.cxx",               "src/EditView.cxx",
    "src/Geometry.cxx",      "src/Indicator.cxx",        "src/KeyMap.cxx",               "src/LineMarker.cxx",
    "src/MarginView.cxx",    "src/PerLine.cxx",          "src/PositionCache.cxx",        "src/RESearch.cxx",
    "src/RunStyles.cxx",     "src/Selection.cxx",        "src/Style.cxx",                "src/UndoHistory.cxx",
    "src/UniConversion.cxx", "src/UniqueString.cxx",     "src/ViewStyle.cxx",            "src/XPM.cxx",
    "win32/HanjaDic.cxx",    "win32/PlatWin.cxx",        "win32/ListBox.cxx",            "win32/SurfaceGDI.cxx",
    "win32/SurfaceD2D.cxx",  "src/ScintillaBase.cxx",    "win32/ScintillaWin.cxx",
};

// Upstream win32/makefile's CLANG=1 warnings and language mode. Zig owns
// optimization/debug code generation. Keep the default exception/RTTI/regex
// support: upstream catches exceptions and uses C++ regex; no local shim.
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

pub fn verifyArchive(bytes: []const u8) !void {
    if (bytes.len != 1_822_062) return error.SourceArchiveSizeMismatch;
    try deps.verifySha256(bytes, archive_sha256);
}

/// The locked archive is the authority, never a cache receipt or extracted
/// tree. Rehash every invocation and publish the entire verified tree once.
pub fn snapshot(allocator: std.mem.Allocator, io: std.Io, archive_path: []const u8, output: []const u8) !void {
    if (!std.fs.path.isAbsolute(archive_path)) return error.SourceArchiveMustBeAbsolute;
    if (!std.fs.path.isAbsolute(output)) return error.SourceSnapshotMustBeAbsolute;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, archive_path, allocator, .limited(1_822_063));
    defer allocator.free(bytes);
    try verifyArchive(bytes);
    const manifest = try deps.parseLockedManifest(allocator);
    defer manifest.deinit();
    const artifact = deps.findArtifact(manifest.value, "scintilla") orelse return error.MissingScintillaLock;
    const expected = try deps.materializeArtifact(allocator, io, artifact, bytes, null, deps.asciiCollisionFold);
    const parent_path = std.fs.path.dirname(output) orelse return error.InvalidSnapshotPath;
    var parent = try std.Io.Dir.openDirAbsolute(io, parent_path, .{ .follow_symlinks = false });
    defer parent.close(io);
    const name = std.fs.path.basename(output);
    if (try verifyPublished(allocator, io, parent, name, expected)) return;
    var random: [16]u8 = undefined;
    io.random(&random);
    const hex = std.fmt.bytesToHex(random, .lower);
    var stage_buffer: [64]u8 = undefined;
    const stage_name = try std.fmt.bufPrint(&stage_buffer, ".scintilla-stage-{s}", .{hex});
    try parent.createDir(io, stage_name, .default_dir);
    defer parent.deleteTree(io, stage_name) catch {};
    {
        var stage = try parent.openDir(io, stage_name, .{ .iterate = true, .follow_symlinks = false });
        defer stage.close(io);
        _ = try deps.materializeArtifact(allocator, io, artifact, bytes, stage, deps.asciiCollisionFold);
        try verifyTree(allocator, io, stage, expected);
    }
    // No existing public source is opened for write, including when a compiler
    // holds it without write/delete sharing. A concurrent winner is rehashed.
    parent.renamePreserve(stage_name, parent, name, io) catch |err| switch (err) {
        error.PathAlreadyExists, error.AccessDenied => {
            if (try verifyPublished(allocator, io, parent, name, expected)) return;
            return err;
        },
        else => return err,
    };
}

fn verifyPublished(allocator: std.mem.Allocator, io: std.Io, parent: std.Io.Dir, name: []const u8, expected: deps.MaterializedArchive) !bool {
    var published = parent.openDir(io, name, .{ .iterate = true, .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer published.close(io);
    try verifyTree(allocator, io, published, expected);
    return true;
}

fn verifyTree(allocator: std.mem.Allocator, io: std.Io, directory: std.Io.Dir, expected: deps.MaterializedArchive) !void {
    const actual = try deps.hashMaterializedDirectory(allocator, io, directory, 16 * 1024 * 1024);
    if (actual.files != expected.payload_files or actual.bytes != expected.payload_bytes or
        !std.mem.eql(u8, &actual.digest, &expected.payload_sha256)) return error.SourceSnapshotMismatch;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4 or !std.mem.eql(u8, args[1], "snapshot")) return error.InvalidArguments;
    const output = try std.fs.path.join(init.arena.allocator(), &.{ args[3], "payload" });
    snapshot(init.gpa, init.io, args[2], output) catch |err| {
        std.debug.print("Scintilla 5.6.6 offline source contract failed ({s}); -Dscintilla-archive must name the exact locked archive. No fallback or fetch.\n", .{@errorName(err)});
        return err;
    };
}
