const std = @import("std");
const authoring_bridge = @import("authoring_bridge");
const workspace_picker = @import("workspace_picker");
const workspace = @import("workspace");
const editor_buffer = @import("editor_buffer");

test "authoring product journey: open folder -> edit -> save -> external change conflict" {
    const io = std.testing.io;
    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    const original_tex = "\\documentclass{article}\n\\begin{document}\nInitial content\n\\end{document}\n";
    try temp.dir.writeFile(io, .{ .sub_path = "main.tex", .data = original_tex });
    try temp.dir.writeFile(io, .{ .sub_path = "refs.bib", .data = "@misc{key, title={T}}\n" });

    const root = try temp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var fake_picker = workspace_picker.FakePicker.init(root);

    var bridge = authoring_bridge.AuthoringBridge.init(std.testing.allocator, io);
    defer bridge.deinit();
    bridge.setPicker(fake_picker.picker());

    // 1. Open Folder via command 100
    const opened = try bridge.dispatchCommandId(100);
    try std.testing.expect(opened);
    try std.testing.expect(bridge.takeFrameNeeded());

    // Verify session attached main.tex and state is active
    try std.testing.expect(bridge.session.getBuffer() != null);
    try std.testing.expectEqual(editor_buffer.State.clean, bridge.session.getBuffer().?.state());

    // 2. Edit through editor seam
    try bridge.session.applyEdit(.{
        .sequence = 1,
        .start = 0,
        .deleted_len = 0,
        .inserted_text = "% Added comment\n",
    });
    try std.testing.expectEqual(editor_buffer.State.dirty, bridge.session.getBuffer().?.state());

    // 3. Save via command 103
    const saved = try bridge.dispatchCommandId(103);
    try std.testing.expect(saved);
    try std.testing.expect(bridge.takeFrameNeeded());
    try std.testing.expectEqual(editor_buffer.State.clean, bridge.session.getBuffer().?.state());

    // Verify written file on disk contains the edit
    const disk_bytes = try temp.dir.readFileAlloc(io, "main.tex", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(disk_bytes);
    try std.testing.expect(std.mem.startsWith(u8, disk_bytes, "% Added comment\n"));

    // 4. Inject external edit to file on disk
    try temp.dir.writeFile(io, .{ .sub_path = "main.tex", .data = "% Out-of-band external edit\n" });

    // Make local buffer dirty
    try bridge.session.applyEdit(.{
        .sequence = 2,
        .start = 0,
        .deleted_len = 0,
        .inserted_text = "% Second local edit\n",
    });

    // 5. Attempt to save -> atomic save precondition detects external change and refuses overwrite!
    const save_res = bridge.dispatchCommandId(103);
    _ = save_res catch {};
    try std.testing.expectEqual(authoring_bridge.authoring_session.SessionState.conflicted, bridge.session.state());

    // Verify external file on disk was NOT overwritten
    const final_disk = try temp.dir.readFileAlloc(io, "main.tex", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(final_disk);
    try std.testing.expectEqualStrings("% Out-of-band external edit\n", final_disk);
}
