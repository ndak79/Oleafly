const std = @import("std");

pub const Theme = enum {
    system,
    light,
    dark,
    high_contrast,
};

pub const ThemeMode = Theme;

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn from_hex(value: u32) Color {
        return .{
            .r = @truncate(value >> 16),
            .g = @truncate(value >> 8),
            .b = @truncate(value),
        };
    }

    pub const fromHex = from_hex;

    pub fn hex(self: Color) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | self.b;
    }
};

pub const Tokens = struct {
    /// Window chrome/background surfaces.  These are intentionally separate
    /// from `paper`/`ink`, which describe the always-opaque PDF canvas.
    shell: Color,
    pane: Color,
    primary_text: Color,
    accent: Color,
    warning: Color,
    error_color: Color,
    verified: Color,
    paper: Color,
    ink: Color,
    muted_text: Color,
    divider: Color,
    /// Compatibility alias for callers that used the pre-contract name.
    border: Color,
    focus: Color,
    syntax_math: Color,
    syntax_link: Color,
    syntax_comment: Color,
    focus_ring_width_dip: u32,
    uses_system_colors: bool,
};

pub fn tokens(theme: Theme) Tokens {
    return switch (theme) {
        // System is resolved by the native host in a later shell slice.  The
        // light baseline is deterministic for this portable model.
        .system, .light => .{
            .shell = Color.from_hex(0xeef3f6),
            .pane = Color.from_hex(0xffffff),
            .primary_text = Color.from_hex(0x16212b),
            .accent = Color.from_hex(0x006c67),
            .warning = Color.from_hex(0x7a4800),
            .error_color = Color.from_hex(0xb42335),
            .verified = Color.from_hex(0x067647),
            .paper = Color.from_hex(0xfbfcfe),
            .ink = Color.from_hex(0x16212b),
            .muted_text = Color.from_hex(0x52616d),
            .divider = Color.from_hex(0x778793),
            .border = Color.from_hex(0x778793),
            .focus = Color.from_hex(0x006c67),
            .syntax_math = Color.from_hex(0x5e43a6),
            .syntax_link = Color.from_hex(0x005ea8),
            .syntax_comment = Color.from_hex(0x52616d),
            .focus_ring_width_dip = 2,
            .uses_system_colors = false,
        },
        .dark => .{
            .shell = Color.from_hex(0x10161c),
            .pane = Color.from_hex(0x151d24),
            .primary_text = Color.from_hex(0xe8eff5),
            .accent = Color.from_hex(0x4fd1c5),
            .warning = Color.from_hex(0xf4b860),
            .error_color = Color.from_hex(0xff7a85),
            .verified = Color.from_hex(0x32d583),
            .paper = Color.from_hex(0xfbfcfe),
            .ink = Color.from_hex(0x16212b),
            .muted_text = Color.from_hex(0xaab7c2),
            .divider = Color.from_hex(0x607384),
            .border = Color.from_hex(0x607384),
            .focus = Color.from_hex(0x4fd1c5),
            .syntax_math = Color.from_hex(0xb7a6ff),
            .syntax_link = Color.from_hex(0x7cc4ff),
            .syntax_comment = Color.from_hex(0x90a0ac),
            .focus_ring_width_dip = 2,
            .uses_system_colors = false,
        },
        .high_contrast => .{
            // These are symbolic fallbacks only; a Windows host substitutes
            // COLOR_* system values before painting.
            .shell = Color.from_hex(0x000000),
            .pane = Color.from_hex(0x000000),
            .primary_text = Color.from_hex(0xffffff),
            .accent = Color.from_hex(0xffff00),
            .warning = Color.from_hex(0xffff00),
            .error_color = Color.from_hex(0xff8080),
            .verified = Color.from_hex(0x00ff00),
            .paper = Color.from_hex(0x000000),
            .ink = Color.from_hex(0xffffff),
            .muted_text = Color.from_hex(0xffffff),
            .divider = Color.from_hex(0xffffff),
            .border = Color.from_hex(0xffffff),
            .focus = Color.from_hex(0xffff00),
            .syntax_math = Color.from_hex(0xffffff),
            .syntax_link = Color.from_hex(0xffff00),
            .syntax_comment = Color.from_hex(0xffffff),
            .focus_ring_width_dip = 2,
            .uses_system_colors = true,
        },
    };
}

pub const palette = tokens;

fn linear_channel(value: u8) f64 {
    const encoded = @as(f64, @floatFromInt(value)) / 255.0;
    return if (encoded <= 0.04045) encoded / 12.92 else std.math.pow(f64, (encoded + 0.055) / 1.055, 2.4);
}

fn luminance(color: Color) f64 {
    return 0.2126 * linear_channel(color.r) + 0.7152 * linear_channel(color.g) + 0.0722 * linear_channel(color.b);
}

pub fn contrast_ratio(first: Color, second: Color) f64 {
    const first_luminance = luminance(first);
    const second_luminance = luminance(second);
    const lighter = @max(first_luminance, second_luminance);
    const darker = @min(first_luminance, second_luminance);
    return (lighter + 0.05) / (darker + 0.05);
}

pub const contrastRatio = contrast_ratio;

/// Check the portable palette's foreground/background, boundary, and focus
/// pairs against the WCAG floors. High contrast is supplied by the OS and is
/// intentionally excluded from this custom-token audit.
pub fn passes_contrast(value: Tokens) bool {
    if (value.uses_system_colors) return true;
    // Normal text is held to the WCAG 4.5:1 floor.  Structural and semantic
    // marks are non-body UI text and use the 3:1 floor.  Check each semantic
    // foreground against the pane it is painted on, and keep the PDF pair
    // independent so dark chrome never turns the document canvas dark.
    const body_ok = contrast_ratio(value.primary_text, value.pane) >= 4.5 and
        contrast_ratio(value.muted_text, value.pane) >= 4.5 and
        contrast_ratio(value.primary_text, value.shell) >= 4.5 and
        contrast_ratio(value.muted_text, value.shell) >= 4.5;
    const ui_marks_ok = contrast_ratio(value.divider, value.pane) >= 3.0 and
        contrast_ratio(value.accent, value.pane) >= 3.0 and
        contrast_ratio(value.warning, value.pane) >= 3.0 and
        contrast_ratio(value.error_color, value.pane) >= 3.0 and
        contrast_ratio(value.verified, value.pane) >= 3.0 and
        contrast_ratio(value.focus, value.pane) >= 3.0 and
        contrast_ratio(value.syntax_math, value.pane) >= 4.5 and
        contrast_ratio(value.syntax_link, value.pane) >= 4.5 and
        contrast_ratio(value.syntax_comment, value.pane) >= 4.5 and
        contrast_ratio(value.divider, value.shell) >= 3.0 and
        contrast_ratio(value.accent, value.shell) >= 3.0 and
        contrast_ratio(value.warning, value.shell) >= 3.0 and
        contrast_ratio(value.error_color, value.shell) >= 3.0 and
        contrast_ratio(value.verified, value.shell) >= 3.0 and
        contrast_ratio(value.focus, value.shell) >= 3.0 and
        contrast_ratio(value.syntax_math, value.shell) >= 4.5 and
        contrast_ratio(value.syntax_link, value.shell) >= 4.5 and
        contrast_ratio(value.syntax_comment, value.shell) >= 4.5;
    return body_ok and ui_marks_ok and contrast_ratio(value.ink, value.paper) >= 4.5;
}

pub const passesContrast = passes_contrast;
