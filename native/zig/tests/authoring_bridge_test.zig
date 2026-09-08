const std = @import("std");
const authoring_bridge = @import("authoring_bridge");
const workspace_picker = @import("workspace_picker");
const workspace_watcher = @import("workspace_watcher");

test "authoring bridge: maps control IDs and executes open folder / save" {
    const io = std.testing.io;
    try std.testing.expectEqual(authoring_bridge.BridgeAction.open_folder, authoring_bridge.mapCommandId(100).?);
    try std.testing.expectEqual(authoring_bridge.BridgeAction.mode_change, authoring_bridge.mapCommandId(101).?);
    try std.testing.expectEqual(authoring_bridge.BridgeAction.compile_request, authoring_bridge.mapCommandId(102).?);
    try std.testing.expectEqual(authoring_bridge.BridgeAction.save, authoring_bridge.mapCommandId(103).?);
    try std.testing.expectEqual(authoring_bridge.BridgeAction.show_recovery, authoring_bridge.mapCommandId(104).?);
    try std.testing.expect(authoring_bridge.mapCommandId(999) == null);

    var temp = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temp.cleanup();

    try temp.dir.writeFile(io, .{ .sub_path = "main.tex", .data = "\\documentclass{article}\n\\begin{document}\nBridge test\n" });
    const root = try temp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var fake_picker = workspace_picker.FakePicker.init(root);

    var bridge = authoring_bridge.AuthoringBridge.init(std.testing.allocator, io);
    defer bridge.deinit();

    bridge.setPicker(fake_picker.picker());

    // Dispatch open_folder command ID (100)
    const handled_open = try bridge.dispatchCommandId(100);
    try std.testing.expect(handled_open);
    try std.testing.expect(bridge.takeFrameNeeded());
    try std.testing.expect(bridge.session.getBuffer() != null);

    // Apply edit to buffer
    try bridge.session.applyEdit(.{
        .sequence = 1,
        .start = 0,
        .deleted_len = 0,
        .inserted_text = "% edited\n",
    });

    // Dispatch save command ID (103)
    const handled_save = try bridge.dispatchCommandId(103);
    try std.testing.expect(handled_save);
    try std.testing.expect(bridge.takeFrameNeeded());

    // Dispatch compile command ID (102)
    const handled_compile = try bridge.dispatchCommandId(102);
    try std.testing.expect(handled_compile);
    try std.testing.expect(bridge.compile_requested);
}
