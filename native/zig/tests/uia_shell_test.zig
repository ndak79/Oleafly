const std = @import("std");
const shell = @import("app_uia_shell");
const strings = @import("app_strings");
const theme = @import("app_theme");

test "shell snapshot exposes deterministic semantic tree" {
    const snapshot = try shell.Snapshot.init(7, 1280, 800, false, .light, .ready);
    try snapshot.validate();
    try std.testing.expectEqual(shell.NodeId.source_pane, snapshot.focused);
    try std.testing.expect(snapshot.node(.open_folder).hasPattern(.invoke));
    try std.testing.expect(snapshot.node(.splitter).hasPattern(.range_value));
    try std.testing.expect(snapshot.node(.mode).hasPattern(.toggle));
    try std.testing.expectEqualStrings("Open Folder", try strings.lookup("en-US", snapshot.node(.open_folder).name));
    try std.testing.expect(!snapshot.node(.recovery).interactive());
}

test "narrow and touch layouts keep deterministic accessibility targets" {
    const narrow = try shell.Snapshot.init(8, 720, 520, false, .dark, .error_status);
    try narrow.validate();
    try std.testing.expectEqual(shell.NodeId.recovery, narrow.focused);
    try std.testing.expect(narrow.node(.recovery).interactive());
    try std.testing.expect(narrow.node(.pdf_pane).state.offscreen);

    const touch = try shell.Snapshot.init(9, 1180, 760, true, .system, .rebuilding);
    try touch.validate();
    try std.testing.expect(touch.node(.compile).bounds.meetsPointerTarget(true));
    try std.testing.expect(touch.node(.save).bounds.meetsPointerTarget(true));
    try std.testing.expect(touch.node(.compile).state.busy);
}

test "shell rejects zero revisions and preserves resource/contrast contract" {
    try std.testing.expectError(error.InvalidRevision, shell.Snapshot.init(0, 960, 640, false, .light, .ready));
    const high_contrast = try shell.Snapshot.init(10, 960, 640, false, .high_contrast, .ready);
    try std.testing.expectEqual(theme.Theme.high_contrast, high_contrast.theme_mode);
    try std.testing.expectEqualStrings("Status", try strings.lookup("en-US", high_contrast.node(.status).name));
}
