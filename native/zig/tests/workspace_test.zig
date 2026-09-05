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
