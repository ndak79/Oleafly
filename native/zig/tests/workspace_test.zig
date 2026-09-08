const std = @import("std");
const builtin = @import("builtin");
const workspace = @import("workspace");

fn sha256(bytes: []const u8) [32]u8 {
    var result: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &result, .{});
    return result;
}

test "open folder inventories deterministic LaTeX sources without writing metadata" {
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();
    try temp.dir.createDirPath(io, "paper/sections");
    try temp.dir.createDirPath(io, ".git");
    try temp.dir.createDirPath(io, "build");
    try temp.dir.writeFile(io, .{ .sub_path = "paper/main.tex", .data = "\\documentclass{article}\n\\begin{document}\nmain\n" });
    try temp.dir.writeFile(io, .{ .sub_path = "paper/sections/intro.tex", .data = "\\section{Intro}\n" });
    try temp.dir.writeFile(io, .{ .sub_path = "paper/references.bib", .data = "@article{a, title={A}}\n" });
    try temp.dir.writeFile(io, .{ .sub_path = "paper/style.sty", .data = "\\ProvidesPackage{style}\n" });
    try temp.dir.writeFile(io, .{ .sub_path = "paper/class.cls", .data = "\\NeedsTeXFormat{LaTeX2e}\n" });
    try temp.dir.writeFile(io, .{ .sub_path = "paper/figure.tikz", .data = "\\draw (0,0)--(1,1);\n" });
    try temp.dir.writeFile(io, .{ .sub_path = ".git/hidden.tex", .data = "\\documentclass{article}\n" });
    try temp.dir.writeFile(io, .{ .sub_path = "build/generated.tex", .data = "\\documentclass{article}\n" });
    try temp.dir.writeFile(io, .{ .sub_path = "paper/blob.tex", .data = &[_]u8{ 0xff, 0xfe, 0x00 } });

    const root = try temp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var opened = try workspace.Workspace.open(std.testing.allocator, io, root);
    defer opened.deinit();

    try std.testing.expectEqualStrings(root, opened.rootPath());
    const files = opened.files();
    try std.testing.expectEqual(@as(usize, 6), files.len);
    const expected_paths = [_][]const u8{
        "paper/class.cls",
        "paper/figure.tikz",
        "paper/main.tex",
        "paper/references.bib",
        "paper/sections/intro.tex",
        "paper/style.sty",
    };
    for (files, expected_paths) |file, expected| try std.testing.expectEqualStrings(expected, file.relative_path);
    try std.testing.expectEqual(workspace.Kind.class, files[0].kind);
    try std.testing.expectEqual(workspace.Kind.tikz, files[1].kind);
    try std.testing.expectEqual(workspace.Kind.tex, files[2].kind);
    try std.testing.expectEqual(@as(u64, "@article{a, title={A}}\n".len), files[3].byte_length);
    try std.testing.expectEqual(sha256("\\documentclass{article}\n\\begin{document}\nmain\n"), files[2].sha256);
    try std.testing.expectEqual(@as(usize, 1), opened.mainCandidates().len);
    try std.testing.expectEqual(@as(usize, 2), opened.mainCandidates()[0]);
    try std.testing.expectError(error.FileNotFound, temp.dir.access(io, ".texflow", .{}));

    if (builtin.os.tag == .windows) {
        try std.testing.expect(std.fs.path.isAbsoluteWindows(opened.rootPath()));
    }
}

test "rescan observes new source files while preserving sorted order" {
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();
    try temp.dir.writeFile(io, .{ .sub_path = "main.tex", .data = "\\documentclass{article}\n" });
    const root = try temp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var opened = try workspace.Workspace.open(std.testing.allocator, io, root);
    defer opened.deinit();
    try std.testing.expectEqual(@as(usize, 1), opened.files().len);
    try temp.dir.writeFile(io, .{ .sub_path = "z.bib", .data = "@misc{x}\n" });
    try temp.dir.writeFile(io, .{ .sub_path = "a.sty", .data = "\\ProvidesPackage{a}\n" });
    try opened.rescan();
    try std.testing.expectEqual(@as(usize, 3), opened.files().len);
    try std.testing.expectEqualStrings("a.sty", opened.files()[0].relative_path);
    try std.testing.expectEqualStrings("main.tex", opened.files()[1].relative_path);
    try std.testing.expectEqualStrings("z.bib", opened.files()[2].relative_path);
}

test "inventory issues record unreadable, oversized, invalid encoding, and ignored case variations" {
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.createDirPath(io, ".GIT");
    try temp.dir.createDirPath(io, "Build");
    try temp.dir.createDirPath(io, "OUT");
    try temp.dir.createDirPath(io, "Target");
    try temp.dir.createDirPath(io, ".TexFlow");
    try temp.dir.writeFile(io, .{ .sub_path = ".GIT/hidden.tex", .data = "\\documentclass{article}\n" });
    try temp.dir.writeFile(io, .{ .sub_path = "Build/gen.tex", .data = "\\documentclass{article}\n" });
    try temp.dir.writeFile(io, .{ .sub_path = "OUT/gen2.tex", .data = "\\documentclass{article}\n" });
    try temp.dir.writeFile(io, .{ .sub_path = "Target/gen3.tex", .data = "\\documentclass{article}\n" });
    try temp.dir.writeFile(io, .{ .sub_path = ".TexFlow/conf.tex", .data = "\\documentclass{article}\n" });

    try temp.dir.writeFile(io, .{ .sub_path = "valid.tex", .data = "\\documentclass{article}\n\\begin{document}\nhello\n" });
    try temp.dir.writeFile(io, .{ .sub_path = "bad_utf8.tex", .data = &[_]u8{ 0xff, 0xfe, 0x00 } });

    const root = try temp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var opened = try workspace.Workspace.open(std.testing.allocator, io, root);
    defer opened.deinit();

    try std.testing.expectEqual(@as(usize, 1), opened.files().len);
    try std.testing.expectEqualStrings("valid.tex", opened.files()[0].relative_path);
    try std.testing.expectEqual(workspace.Encoding.utf8, opened.files()[0].encoding);

    const issues = opened.issues();
    try std.testing.expectEqual(@as(usize, 1), issues.len);
    try std.testing.expectEqualStrings("bad_utf8.tex", issues[0].relative_path);
    try std.testing.expectEqual(workspace.IssueReason.invalid_encoding, issues[0].reason);
}

test "BOM and CRLF are preserved without lossy normalization" {
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    const raw_bom_crlf = "\xef\xbb\xbf\\documentclass{article}\r\n\\begin{document}\r\nbody\r\n";
    try temp.dir.writeFile(io, .{ .sub_path = "bom_crlf.tex", .data = raw_bom_crlf });

    const root = try temp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var opened = try workspace.Workspace.open(std.testing.allocator, io, root);
    defer opened.deinit();

    try std.testing.expectEqual(@as(usize, 1), opened.files().len);
    const file = opened.files()[0];
    try std.testing.expectEqualStrings("bom_crlf.tex", file.relative_path);
    try std.testing.expectEqual(workspace.Encoding.utf8_bom, file.encoding);
    try std.testing.expectEqual(@as(u64, raw_bom_crlf.len), file.byte_length);
    try std.testing.expectEqual(sha256(raw_bom_crlf), file.sha256);
}

test "root decision selects explicit project config or magic root marker or detects tie" {
    const io = std.testing.io;
    {
        // Case A: Magic root marker % !TeX root = ...
        var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
        defer temp.cleanup();

        try temp.dir.writeFile(io, .{ .sub_path = "sub.tex", .data = "% !TeX root = main.tex\n\\section{Part}\n" });
        try temp.dir.writeFile(io, .{ .sub_path = "main.tex", .data = "\\documentclass{book}\n\\begin{document}\n\\include{sub}\n" });
        try temp.dir.writeFile(io, .{ .sub_path = "alt.tex", .data = "\\documentclass{article}\n\\begin{document}\nalt\n" });

        const root = try temp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
        defer std.testing.allocator.free(root);
        var opened = try workspace.Workspace.open(std.testing.allocator, io, root);
        defer opened.deinit();

        const decision = opened.rootDecision();
        try std.testing.expectEqual(workspace.RootStatus.selected, decision.status);
        try std.testing.expectEqual(workspace.RootReason.magic_root_marker, decision.reason);
        try std.testing.expect(decision.selected_index != null);
        try std.testing.expectEqualStrings("main.tex", opened.files()[decision.selected_index.?].relative_path);
    }
    {
        // Case B: Ambiguous tie between two independent main documents
        var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
        defer temp.cleanup();

        try temp.dir.writeFile(io, .{ .sub_path = "doc_a.tex", .data = "\\documentclass{article}\n\\begin{document}\nA\n" });
        try temp.dir.writeFile(io, .{ .sub_path = "doc_b.tex", .data = "\\documentclass{article}\n\\begin{document}\nB\n" });

        const root = try temp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
        defer std.testing.allocator.free(root);
        var opened = try workspace.Workspace.open(std.testing.allocator, io, root);
        defer opened.deinit();

        const decision = opened.rootDecision();
        try std.testing.expectEqual(workspace.RootStatus.needs_main_choice, decision.status);
        try std.testing.expectEqual(workspace.RootReason.ambiguous_candidates, decision.reason);
        try std.testing.expectEqual(@as(usize, 2), decision.candidate_indices.len);
        try std.testing.expectEqualStrings("doc_a.tex", opened.files()[decision.candidate_indices[0]].relative_path);
        try std.testing.expectEqualStrings("doc_b.tex", opened.files()[decision.candidate_indices[1]].relative_path);
    }
}
