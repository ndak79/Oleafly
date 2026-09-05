pub const tri_canvas_breakpoint_dip: u32 = 1180;
pub const dual_pane_breakpoint_dip: u32 = 880;
pub const supported_min_width_dip: u32 = 760;
pub const supported_min_height_dip: u32 = 520;

pub const spacing_rhythm_dip: u32 = 8;
pub const minimum_target_dip: u32 = 24;
pub const touch_target_dip: u32 = 44;
pub const compact_control_min_dip: u32 = 28;
pub const compact_control_max_dip: u32 = 32;
pub const visible_divider_dip: u32 = 6;
pub const status_rail_dip: u32 = 28;
pub const project_min_dip: u32 = 240;
pub const source_min_dip: u32 = 480;
pub const pdf_min_dip: u32 = 360;
pub const source_share_percent: u32 = 58;
pub const pdf_share_percent: u32 = 42;

comptime {
    if (source_share_percent + pdf_share_percent != 100) @compileError("source/PDF allocation must total 100%");
}

pub const Mode = enum {
    tri_canvas,
    dual_pane,
    focus_switcher,
    unsupported_reflow,
};

pub const LayoutMode = Mode;

pub const SourcePdfAllocation = struct {
    source_dip: u32,
    pdf_dip: u32,
};

/// Allocate the Source/PDF content area after fixed chrome has been removed.
/// The nominal 58/42 split is retained whenever both panes can satisfy their
/// minima; at narrow widths the split clamps instead of crushing either pane.
pub fn allocate_source_pdf(available_dip: u32) ?SourcePdfAllocation {
    const minimum_total = source_min_dip + pdf_min_dip;
    if (available_dip < minimum_total) return null;

    const desired_source: u32 = @intCast((@as(u64, available_dip) * source_share_percent) / 100);
    const max_source = available_dip - pdf_min_dip;
    const source = if (desired_source < source_min_dip)
        source_min_dip
    else if (desired_source > max_source)
        max_source
    else
        desired_source;
    return .{ .source_dip = source, .pdf_dip = available_dip - source };
}

pub const allocateSourcePdf = allocate_source_pdf;

pub const TriCanvasAllocation = struct {
    project_dip: u32,
    source_dip: u32,
    pdf_dip: u32,
};

/// Allocate the tri-canvas panes after subtracting fixed chrome (toolbar,
/// status rail, and dividers supplied by the native shell).
pub fn allocate_tri_canvas(total_width_dip: u32, fixed_chrome_dip: u32) ?TriCanvasAllocation {
    if (total_width_dip < fixed_chrome_dip) return null;
    const content = total_width_dip - fixed_chrome_dip;
    if (content < project_min_dip) return null;
    const panes = allocate_source_pdf(content - project_min_dip) orelse return null;
    return .{
        .project_dip = project_min_dip,
        .source_dip = panes.source_dip,
        .pdf_dip = panes.pdf_dip,
    };
}

pub const allocateTriCanvas = allocate_tri_canvas;

pub fn mode_for_width(width_dip: u32) Mode {
    if (width_dip > tri_canvas_breakpoint_dip) return .tri_canvas;
    if (width_dip >= dual_pane_breakpoint_dip) return .dual_pane;
    if (width_dip >= supported_min_width_dip) return .focus_switcher;
    return .unsupported_reflow;
}

pub const modeForWidth = mode_for_width;

pub fn is_supported(width_dip: u32, height_dip: u32) bool {
    return width_dip >= supported_min_width_dip and height_dip >= supported_min_height_dip;
}

pub const isSupported = is_supported;

pub const WindowLayout = struct {
    mode: Mode,
    width_dip: u32,
    height_dip: u32,
    supported: bool,
    project_visible: bool,
    project_flyout: bool,
    source_visible: bool,
    pdf_visible: bool,
    source_pdf_switcher: bool,
    spacing_dip: u32 = spacing_rhythm_dip,
    pointer_target_dip: u32,
};

pub fn for_window(width_dip: u32, height_dip: u32, touch_mode: bool) WindowLayout {
    const mode = mode_for_width(width_dip);
    return .{
        .mode = mode,
        .width_dip = width_dip,
        .height_dip = height_dip,
        .supported = is_supported(width_dip, height_dip),
        .project_visible = mode == .tri_canvas,
        .project_flyout = mode != .tri_canvas,
        .source_visible = true,
        .pdf_visible = mode != .focus_switcher and mode != .unsupported_reflow,
        .source_pdf_switcher = mode == .focus_switcher or mode == .unsupported_reflow,
        .pointer_target_dip = if (touch_mode) touch_target_dip else minimum_target_dip,
    };
}

pub const forWindow = for_window;

pub fn target_dip(touch_mode: bool) u32 {
    return if (touch_mode) touch_target_dip else minimum_target_dip;
}

pub const targetDip = target_dip;
