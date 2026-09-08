const std = @import("std");
const builtin = @import("builtin");
const authoring_session = @import("authoring_session");
const workspace = @import("workspace");
const editor_buffer = @import("editor_buffer");
const atomic_save = @import("atomic_save");

test "authoring session: open unambiguous folder attaches main, applies edits, and saves cleanly" {
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.writeFile(io, .{ .sub_path = "main.tex", .data = "\\documentclass{article}\n\\begin{document}\nHello world\n" });
    const root = try temp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var session = authoring_session.Session.init(std.testing.allocator, io);
    defer session.deinit();

    try session.openFolder(root);
    try std.testing.expectEqual(authoring_session.SessionState.active, session.state());
    const buf = session.getBuffer().?;
    try std.testing.expectEqual(editor_buffer.State.clean, buf.state());

    // Apply contiguous edit sequence 1
    try session.applyEdit(.{
        .sequence = 1,
        .start = 0,
        .deleted_len = 0,
        .inserted_text = "% header\n",
    });
    try std.testing.expectEqual(editor_buffer.State.dirty, buf.state());

    // Save and verify clean state
    var outcome = try session.save();
    defer outcome.deinit();
    try std.testing.expectEqual(authoring_session.SaveStatus.clean, outcome.status);
    try std.testing.expectEqual(editor_buffer.State.clean, buf.state());

    // Sequence mismatch marks buffer conflicted
    try std.testing.expectError(error.SequenceMismatch, session.applyEdit(.{
        .sequence = 99,
        .start = 0,
        .deleted_len = 0,
        .inserted_text = "error",
    }));
    try std.testing.expectEqual(authoring_session.SessionState.conflicted, session.state());
    try std.testing.expectEqual(editor_buffer.State.conflicted, buf.state());
}

test "authoring session: ambiguous main requires explicit attachment" {
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.writeFile(io, .{ .sub_path = "a.tex", .data = "\\documentclass{article}\n\\begin{document}\nA\n" });
    try temp.dir.writeFile(io, .{ .sub_path = "b.tex", .data = "\\documentclass{article}\n\\begin{document}\nB\n" });
    const root = try temp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var session = authoring_session.Session.init(std.testing.allocator, io);
    defer session.deinit();

    try session.openFolder(root);
    try std.testing.expectEqual(authoring_session.SessionState.needs_main_choice, session.state());

    try session.attachMain("b.tex");
    try std.testing.expectEqual(authoring_session.SessionState.active, session.state());
    try std.testing.expectEqualStrings("b.tex", session.active_rel_path.?);

    // Root escape path is rejected
    try std.testing.expectError(error.InvalidPath, session.attachMain("../outside.tex"));
}

test "authoring session: external change handling and refusal" {
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.writeFile(io, .{ .sub_path = "doc.tex", .data = "\\documentclass{article}\n\\begin{document}\nBase\n" });
    const root = try temp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var session = authoring_session.Session.init(std.testing.allocator, io);
    defer session.deinit();

    try session.openFolder(root);
    try std.testing.expectEqual(authoring_session.SessionState.active, session.state());

    // Apply edit to make buffer dirty
    try session.applyEdit(.{
        .sequence = 1,
        .start = 0,
        .deleted_len = 0,
        .inserted_text = "% edit\n",
    });

    // An external change arrives while buffer is dirty -> marks buffer conflicted!
    try session.handleExternalEvent(.file_changed, "doc.tex", null);
    try std.testing.expectEqual(authoring_session.SessionState.conflicted, session.state());

    // Saving a conflicted buffer is refused
    try std.testing.expectError(error.BufferConflicted, session.save());

    // File deleted event marks buffer missing
    try session.handleExternalEvent(.file_deleted, "doc.tex", null);
    try std.testing.expectEqual(authoring_session.SessionState.missing, session.state());
    try std.testing.expectError(error.BufferMissing, session.save());
}
