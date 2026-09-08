const std = @import("std");
const workspace = @import("workspace");
const outline = @import("outline");

test "outline: parses nested inputs, bibliography, and ignores comments" {
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.writeFile(io, .{
        .sub_path = "main.tex",
        .data = "\\documentclass{book}\n" ++
            "% \\input{commented.tex}\n" ++
            "\\input{ch1}\n" ++
            "\\bibliography{refs}\n",
    });
    try temp.dir.writeFile(io, .{
        .sub_path = "ch1.tex",
        .data = "\\section{Chapter 1}\n\\include{sec1}\n",
    });
    try temp.dir.writeFile(io, .{
        .sub_path = "sec1.tex",
        .data = "\\subsection{Section 1}\n",
    });
    try temp.dir.writeFile(io, .{
        .sub_path = "refs.bib",
        .data = "@article{a, title={A}}\n",
    });

    const root = try temp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var ws = try workspace.Workspace.open(std.testing.allocator, io, root);
    defer ws.deinit();

    var graph = try outline.buildOutline(std.testing.allocator, io, &ws, "main.tex");
    defer graph.deinit();

    try std.testing.expectEqual(@as(usize, 4), graph.entries.len);
    try std.testing.expectEqualStrings("main.tex", graph.entries[0].relative_path);
    try std.testing.expectEqual(@as(usize, 0), graph.entries[0].depth);

    try std.testing.expectEqualStrings("ch1.tex", graph.entries[1].relative_path);
    try std.testing.expectEqual(@as(usize, 1), graph.entries[1].depth);
    try std.testing.expectEqual(@as(?usize, 0), graph.entries[1].parent_index);

    try std.testing.expectEqualStrings("sec1.tex", graph.entries[2].relative_path);
    try std.testing.expectEqual(@as(usize, 2), graph.entries[2].depth);
    try std.testing.expectEqual(@as(?usize, 1), graph.entries[2].parent_index);

    try std.testing.expectEqualStrings("refs.bib", graph.entries[3].relative_path);
    try std.testing.expectEqual(@as(usize, 1), graph.entries[3].depth);

    try std.testing.expectEqual(@as(usize, 0), graph.issues.len);
}

test "outline: handles quoted paths with spaces, cycle detection, missing, and outside-root references" {
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.writeFile(io, .{
        .sub_path = "main.tex",
        .data = "\\documentclass{article}\n" ++
            "\\input{\"chapter one.tex\"}\n" ++
            "\\input{missing_file.tex}\n" ++
            "\\input{../outside.tex}\n",
    });
    try temp.dir.writeFile(io, .{
        .sub_path = "chapter one.tex",
        .data = "\\input{cycle.tex}\n",
    });
    try temp.dir.writeFile(io, .{
        .sub_path = "cycle.tex",
        .data = "\\input{main.tex}\n", // cycle back to main.tex!
    });

    const root = try temp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var ws = try workspace.Workspace.open(std.testing.allocator, io, root);
    defer ws.deinit();

    var graph = try outline.buildOutline(std.testing.allocator, io, &ws, "main.tex");
    defer graph.deinit();

    // Issues should contain:
    // 1. outside_root (../outside.tex)
    // 2. unresolved (missing_file.tex)
    // 3. cycle (main.tex)
    try std.testing.expect(graph.issues.len >= 3);

    var has_outside_root = false;
    var has_unresolved = false;
    var has_cycle = false;

    for (graph.issues) |iss| {
        switch (iss.kind) {
            .outside_root => has_outside_root = true,
            .unresolved => has_unresolved = true,
            .cycle => has_cycle = true,
            else => {},
        }
    }

    try std.testing.expect(has_outside_root);
    try std.testing.expect(has_unresolved);
    try std.testing.expect(has_cycle);
}
