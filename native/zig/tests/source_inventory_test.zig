const std = @import("std");
const probe = @import("scintilla_probe");
const contract = @import("scintilla_contract");

// Independent transcription of Scintilla 5.6.6 win32/scintilla.mak's
// COMPONENT_OBJS + SRC_OBJS. SHARED_OBJS and resources are DLL-only.
const expected_sources = [_][]const u8{
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

test "Scintilla static inventory is the complete pinned Win32 inventory" {
    if (comptime @hasDecl(probe, "sources")) {
        try std.testing.expectEqual(expected_sources.len, probe.sources.len);
        for (expected_sources, probe.sources) |expected, actual| try std.testing.expectEqualStrings(expected, actual);
        try std.testing.expectEqualStrings("5.6.6", probe.version);
        try std.testing.expectEqualStrings("b6b08598c68fac90990d010c1142494d707530602b5320753274d045c2b02189", probe.archive_sha256);
    } else return error.MissingScintillaInventory;
}

test "C++17 debug and release flags preserve upstream exception and RTTI support" {
    if (comptime @hasDecl(probe, "cxxFlags")) {
        inline for (.{ std.builtin.OptimizeMode.Debug, .ReleaseSafe, .ReleaseFast }) |mode| {
            const flags = probe.cxxFlags(mode);
            const expected = [_][]const u8{ "-std=c++17", "-Wall", "-Wextra", "-Wpedantic", if (mode == .Debug) "-DDEBUG" else "-DNDEBUG" };
            try std.testing.expectEqual(expected.len, flags.len);
            for (expected, flags) |want, actual| try std.testing.expectEqualStrings(want, actual);
        }
    } else return error.MissingScintillaFlags;
}

test "source contract rejects missing duplicate DLL and wrong-platform source paths" {
    if (comptime @hasDecl(probe, "verifySourceList")) {
        try probe.verifySourceList(&expected_sources);
        try std.testing.expectError(error.SourceInventoryMismatch, probe.verifySourceList(expected_sources[1..]));
        var changed = expected_sources;
        changed[3] = changed[0];
        try std.testing.expectError(error.SourceInventoryMismatch, probe.verifySourceList(&changed));
        changed = expected_sources;
        changed[38] = "win32/ScintillaDLL.cxx";
        try std.testing.expectError(error.SourceInventoryMismatch, probe.verifySourceList(&changed));
        changed[38] = "gtk/ScintillaGTK.cxx";
        try std.testing.expectError(error.SourceInventoryMismatch, probe.verifySourceList(&changed));
        changed[38] = "../ScintillaWin.cxx";
        try std.testing.expectError(error.SourceInventoryMismatch, probe.verifySourceList(&changed));
    } else return error.MissingScintillaInventoryValidator;
}

test "archive identity rejects altered bytes before extraction" {
    if (comptime @hasDecl(probe, "verifyArchive")) {
        try std.testing.expectError(error.SourceArchiveSizeMismatch, probe.verifyArchive("wrong"));
        const bytes = try std.testing.allocator.alloc(u8, 1_822_062);
        defer std.testing.allocator.free(bytes);
        @memset(bytes, 0);
        try std.testing.expectError(error.DigestMismatch, probe.verifyArchive(bytes));
    } else return error.MissingScintillaArchiveVerifier;
}

test "snapshot rejects nonabsolute inputs and outputs before touching files" {
    if (comptime @hasDecl(probe, "snapshot")) {
        try std.testing.expectError(error.SourceArchiveMustBeAbsolute, probe.snapshot(std.testing.allocator, std.testing.io, "archive.bin", "payload"));
        const absolute = if (@import("builtin").os.tag == .windows) "C:\\absent\\archive.bin" else "/absent/archive.bin";
        try std.testing.expectError(error.SourceSnapshotMustBeAbsolute, probe.snapshot(std.testing.allocator, std.testing.io, absolute, "payload"));
    } else return error.MissingScintillaSnapshot;
}

test "source snapshot is exact reusable and fails closed on corruption or extra files" {
    if (comptime @hasDecl(probe, "snapshot")) {
        const io = std.testing.io;
        const allocator = std.testing.allocator;
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const root = path_buffer[0..try temporary.dir.realPath(io, &path_buffer)];
        const output = try std.fs.path.join(allocator, &.{ root, "snapshot" });
        defer allocator.free(output);
        try probe.snapshot(allocator, io, contract.archive_path, output);
        try probe.snapshot(allocator, io, contract.archive_path, output);
        var published = try temporary.dir.openDir(io, "snapshot", .{});
        defer published.close(io);
        const version_bytes = try published.readFileAlloc(io, "scintilla/version.txt", allocator, .limited(32));
        defer allocator.free(version_bytes);
        try std.testing.expectEqualStrings("566", std.mem.trim(u8, version_bytes, "\r\n"));
        for (expected_sources) |path| {
            const full = try std.fs.path.join(allocator, &.{ "scintilla", path });
            defer allocator.free(full);
            const file = try published.openFile(io, full, .{});
            file.close(io);
        }
        try published.writeFile(io, .{ .sub_path = "unexpected.cxx", .data = "injected source" });
        try std.testing.expectError(error.SourceSnapshotMismatch, probe.snapshot(allocator, io, contract.archive_path, output));
        try published.deleteFile(io, "unexpected.cxx");
        try published.writeFile(io, .{ .sub_path = "scintilla/src/Editor.cxx", .data = "modified" });
        try std.testing.expectError(error.SourceSnapshotMismatch, probe.snapshot(allocator, io, contract.archive_path, output));
        const retained = try published.readFileAlloc(io, "scintilla/src/Editor.cxx", allocator, .limited(32));
        defer allocator.free(retained);
        try std.testing.expectEqualStrings("modified", retained);
    } else return error.MissingScintillaSnapshot;
}

test "build creates a Win32-only uninstalled static library with the verified inventory" {
    if (comptime @hasDecl(contract, "source_files")) {
        try std.testing.expectEqual(expected_sources.len, contract.source_files.len);
        for (expected_sources, contract.source_files) |expected, actual| try std.testing.expectEqualStrings(expected, actual);
        try std.testing.expectEqual(@import("builtin").os.tag == .windows, contract.library_created);
        try std.testing.expect(!contract.install_reaches_library);
        try std.testing.expect(!contract.product_reaches_library);
        if (contract.library_created) {
            try std.testing.expectEqualStrings("lib", contract.artifact_kind);
            try std.testing.expectEqualStrings("static", contract.artifact_linkage);
        }
        const expected_flags = probe.cxxFlags(@import("builtin").mode);
        try std.testing.expectEqual(expected_flags.len, contract.cxx_flags.len);
        for (expected_flags, contract.cxx_flags) |expected, actual| try std.testing.expectEqualStrings(expected, actual);
    } else return error.MissingScintillaBuildContract;
}

test "verified upstream make recipe independently names every static object once" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var source = try std.Io.Dir.cwd().openDir(io, contract.source_root, .{});
    defer source.close(io);
    const makefile = try source.readFileAlloc(io, "win32/scintilla.mak", allocator, .limited(32 * 1024));
    defer allocator.free(makefile);
    const start = std.mem.indexOf(u8, makefile, "SRC_OBJS=") orelse return error.MissingUpstreamStaticRecipe;
    const end = std.mem.indexOfPos(u8, makefile, start, "SHARED_OBJS =") orelse return error.MissingUpstreamStaticRecipe;
    const object_list = makefile[start..end];
    try std.testing.expectEqual(expected_sources.len, std.mem.count(u8, object_list, ".obj"));
    for (expected_sources) |path| {
        const base = std.fs.path.stem(path);
        const token = try std.fmt.allocPrint(allocator, "\\{s}.obj", .{base});
        defer allocator.free(token);
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, object_list, token));
    }
    try std.testing.expect(std.mem.indexOf(u8, makefile, "$(LIBSCI): $(COMPONENT_OBJS)") != null);
    try std.testing.expect(std.mem.indexOf(u8, makefile, "-EHsc -std:c++17 -utf-8") != null);
}

test "concurrent snapshot publishers expose a complete tree and leave no stage" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = buffer[0..try temporary.dir.realPath(io, &buffer)];
    const output = try std.fs.path.join(allocator, &.{ root, "snapshot" });
    defer allocator.free(output);
    var start: std.atomic.Value(bool) = .init(false);
    const Publisher = struct {
        io: std.Io,
        output: []const u8,
        start: *std.atomic.Value(bool),
        failure: ?anyerror = null,

        fn run(self: *@This()) void {
            while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
            probe.snapshot(std.heap.page_allocator, self.io, contract.archive_path, self.output) catch |err| {
                self.failure = err;
            };
        }
    };
    var first = Publisher{ .io = io, .output = output, .start = &start };
    var second = first;
    const first_thread = try std.Thread.spawn(.{}, Publisher.run, .{&first});
    const second_thread = std.Thread.spawn(.{}, Publisher.run, .{&second}) catch |err| {
        start.store(true, .release);
        first_thread.join();
        return err;
    };
    start.store(true, .release);
    first_thread.join();
    second_thread.join();
    if (first.failure) |err| return err;
    if (second.failure) |err| return err;
    try probe.snapshot(allocator, io, contract.archive_path, output);
    var entries = temporary.dir.iterate();
    try std.testing.expectEqualStrings("snapshot", (try entries.next(io)).?.name);
    try std.testing.expect(try entries.next(io) == null);
}
