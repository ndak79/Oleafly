const std = @import("std");
const theme = @import("app_theme");
const layout = @import("app_layout");

test "semantic theme tokens retain the locked hex values" {
    const light = theme.tokens(.light);
    try std.testing.expectEqual(@as(u32, 0xeef3f6), light.shell.hex());
    try std.testing.expectEqual(@as(u32, 0xffffff), light.pane.hex());
    try std.testing.expectEqual(@as(u32, 0x16212b), light.primary_text.hex());
    try std.testing.expectEqual(@as(u32, 0x52616d), light.muted_text.hex());
    try std.testing.expectEqual(@as(u32, 0x778793), light.divider.hex());
    try std.testing.expectEqual(@as(u32, 0x006c67), light.accent.hex());
    try std.testing.expectEqual(@as(u32, 0x7a4800), light.warning.hex());
    try std.testing.expectEqual(@as(u32, 0xb42335), light.error_color.hex());
    try std.testing.expectEqual(@as(u32, 0xfbfcfe), light.paper.hex());
    try std.testing.expectEqual(@as(u32, 0x16212b), light.ink.hex());
    try std.testing.expectEqual(@as(u32, 0x5e43a6), light.syntax_math.hex());
    try std.testing.expectEqual(@as(u32, 0x005ea8), light.syntax_link.hex());
    try std.testing.expectEqual(@as(u32, 0x52616d), light.syntax_comment.hex());
    try std.testing.expectEqual(@as(u32, 2), light.focus_ring_width_dip);
    try std.testing.expect(theme.passes_contrast(light));

    const dark = theme.tokens(.dark);
    try std.testing.expectEqual(@as(u32, 0x10161c), dark.shell.hex());
    try std.testing.expectEqual(@as(u32, 0x151d24), dark.pane.hex());
    try std.testing.expectEqual(@as(u32, 0xe8eff5), dark.primary_text.hex());
    try std.testing.expectEqual(@as(u32, 0xaab7c2), dark.muted_text.hex());
    try std.testing.expectEqual(@as(u32, 0x607384), dark.divider.hex());
    try std.testing.expectEqual(@as(u32, 0x4fd1c5), dark.accent.hex());
    try std.testing.expectEqual(@as(u32, 0xf4b860), dark.warning.hex());
    try std.testing.expectEqual(@as(u32, 0xff7a85), dark.error_color.hex());
    try std.testing.expectEqual(@as(u32, 0xfbfcfe), dark.paper.hex());
    try std.testing.expectEqual(@as(u32, 0x16212b), dark.ink.hex());
    try std.testing.expectEqual(@as(u32, 0xb7a6ff), dark.syntax_math.hex());
    try std.testing.expectEqual(@as(u32, 0x7cc4ff), dark.syntax_link.hex());
    try std.testing.expectEqual(@as(u32, 0x90a0ac), dark.syntax_comment.hex());
    try std.testing.expect(theme.passes_contrast(dark));
    var failing = dark;
    failing.accent = failing.pane;
    try std.testing.expect(!theme.passes_contrast(failing));
    failing = dark;
    failing.syntax_comment = failing.pane;
    try std.testing.expect(!theme.passes_contrast(failing));
    try std.testing.expect(theme.tokens(.high_contrast).uses_system_colors);
}

test "responsive layout uses exact boundary widths and minimums" {
    try std.testing.expectEqual(layout.Mode.tri_canvas, layout.modeForWidth(1_181));
    try std.testing.expectEqual(layout.Mode.dual_pane, layout.modeForWidth(1_180));
    try std.testing.expectEqual(layout.Mode.dual_pane, layout.modeForWidth(880));
    try std.testing.expectEqual(layout.Mode.focus_switcher, layout.modeForWidth(879));
    try std.testing.expectEqual(layout.Mode.focus_switcher, layout.modeForWidth(760));
    try std.testing.expectEqual(layout.Mode.unsupported_reflow, layout.modeForWidth(759));
    try std.testing.expect(layout.is_supported(760, 520));
    try std.testing.expect(!layout.is_supported(759, 520));
    try std.testing.expect(!layout.is_supported(760, 519));
    try std.testing.expectEqual(@as(u32, 8), layout.spacing_rhythm_dip);
    try std.testing.expectEqual(@as(u32, 24), layout.minimum_target_dip);
    try std.testing.expectEqual(@as(u32, 44), layout.touch_target_dip);
    try std.testing.expectEqual(@as(u32, 58), layout.source_share_percent);
    try std.testing.expectEqual(@as(u32, 42), layout.pdf_share_percent);
    try std.testing.expectEqual(@as(u32, 100), layout.source_share_percent + layout.pdf_share_percent);
}

test "source and PDF allocations preserve minima and nominal ratio" {
    const minimum = layout.allocate_source_pdf(layout.source_min_dip + layout.pdf_min_dip) orelse return error.MissingAllocation;
    try std.testing.expectEqual(layout.source_min_dip, minimum.source_dip);
    try std.testing.expectEqual(layout.pdf_min_dip, minimum.pdf_dip);
    try std.testing.expectEqual(@as(?layout.SourcePdfAllocation, null), layout.allocate_source_pdf(839));

    const nominal = layout.allocate_source_pdf(1_000) orelse return error.MissingAllocation;
    try std.testing.expectEqual(@as(u32, 580), nominal.source_dip);
    try std.testing.expectEqual(@as(u32, 420), nominal.pdf_dip);

    const tri = layout.allocate_tri_canvas(2_000, 100) orelse return error.MissingAllocation;
    try std.testing.expectEqual(layout.project_min_dip, tri.project_dip);
    try std.testing.expectEqual(@as(u32, 962), tri.source_dip);
    try std.testing.expectEqual(@as(u32, 698), tri.pdf_dip);
    try std.testing.expectEqual(@as(?layout.TriCanvasAllocation, null), layout.allocate_tri_canvas(1_000, 100));
}
