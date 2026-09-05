//! Deterministic semantic shell tree consumed by the native UIA adapter.
//!
//! This module deliberately contains no COM, HWND, renderer, or allocator
//! state. It is the single source of truth for names, roles, patterns, bounds,
//! and state transitions that the later server-side UIA provider must expose.
const layout = @import("app_layout");
const strings = @import("app_strings");
const theme = @import("app_theme");

pub const node_count: usize = 11;

pub const NodeId = enum(u8) {
    root,
    open_folder,
    project_pane,
    source_pane,
    pdf_pane,
    splitter,
    mode,
    compile,
    save,
    status,
    recovery,
};

pub const ControlType = enum(u8) {
    window,
    pane,
    document,
    button,
    separator,
    status,
    toggle,
    recovery,
};

pub const Pattern = enum(u8) {
    invoke = 1,
    toggle = 2,
    range_value = 4,
    text = 8,
};

pub const State = struct {
    enabled: bool = true,
    focused: bool = false,
    busy: bool = false,
    offscreen: bool = false,
    error_state: bool = false,
};

pub const Bounds = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,

    pub fn right(self: Bounds) u64 {
        return @as(u64, self.x) + self.width;
    }

    pub fn bottom(self: Bounds) u64 {
        return @as(u64, self.y) + self.height;
    }

    pub fn meetsPointerTarget(self: Bounds, touch_mode: bool) bool {
        const minimum = if (touch_mode) layout.touch_target_dip else layout.minimum_target_dip;
        return self.width >= minimum and self.height >= minimum;
    }
};

pub const Status = enum {
    ready,
    rebuilding,
    error_status,
};

pub const Node = struct {
    id: NodeId,
    parent: ?NodeId,
    control_type: ControlType,
    name: strings.Key,
    bounds: Bounds,
    patterns: u8,
    state: State,
    accelerator: ?[]const u8 = null,

    pub fn hasPattern(self: Node, pattern: Pattern) bool {
        return self.patterns & @intFromEnum(pattern) != 0;
    }

    pub fn interactive(self: Node) bool {
        const actions = @intFromEnum(Pattern.invoke) | @intFromEnum(Pattern.toggle) | @intFromEnum(Pattern.range_value);
        return self.patterns & actions != 0 and !self.state.offscreen;
    }
};

pub const Snapshot = struct {
    revision: u64,
    width_dip: u32,
    height_dip: u32,
    touch_mode: bool,
    theme_mode: theme.Theme,
    layout_state: layout.WindowLayout,
    focused: NodeId,
    status: Status,
    nodes: [node_count]Node,

    pub fn init(
        revision: u64,
        width_dip: u32,
        height_dip: u32,
        touch_mode: bool,
        theme_mode: theme.Theme,
        status: Status,
    ) !Snapshot {
        if (revision == 0) return error.InvalidRevision;
        if (width_dip == 0 or height_dip == 0) return error.InvalidBounds;

        const layout_state = layout.for_window(width_dip, height_dip, touch_mode);
        const focused: NodeId = if (layout_state.supported) .source_pane else .recovery;
        const control_height = if (touch_mode) layout.touch_target_dip else layout.compact_control_max_dip;
        const status_y = if (height_dip > layout.status_rail_dip)
            height_dip - layout.status_rail_dip
        else
            0;
        const content_y = control_height + layout.spacing_rhythm_dip;
        const content_height = if (height_dip > content_y + layout.status_rail_dip)
            height_dip - content_y - layout.status_rail_dip
        else
            1;

        var nodes: [node_count]Node = undefined;
        nodes[@intFromEnum(NodeId.root)] = .{
            .id = .root,
            .parent = null,
            .control_type = .window,
            .name = .project,
            .bounds = .{ .x = 0, .y = 0, .width = width_dip, .height = height_dip },
            .patterns = 0,
            .state = .{ .focused = false },
        };
        nodes[@intFromEnum(NodeId.open_folder)] = .{
            .id = .open_folder,
            .parent = .root,
            .control_type = .button,
            .name = .open_folder,
            .bounds = .{ .x = layout.spacing_rhythm_dip, .y = layout.spacing_rhythm_dip, .width = 120, .height = control_height },
            .patterns = @intFromEnum(Pattern.invoke),
            .state = .{},
            .accelerator = "Ctrl+O",
        };
        nodes[@intFromEnum(NodeId.project_pane)] = .{
            .id = .project_pane,
            .parent = .root,
            .control_type = .pane,
            .name = .project,
            .bounds = .{ .x = 0, .y = content_y, .width = if (layout_state.project_visible) layout.project_min_dip else 1, .height = content_height },
            .patterns = @intFromEnum(Pattern.text),
            .state = .{ .offscreen = !layout_state.project_visible },
        };
        const project_width = if (layout_state.project_visible) layout.project_min_dip else 0;
        const pane_area = if (width_dip > project_width) width_dip - project_width else 1;
        const allocation = layout.allocate_source_pdf(pane_area) orelse layout.SourcePdfAllocation{ .source_dip = pane_area, .pdf_dip = 1 };
        nodes[@intFromEnum(NodeId.source_pane)] = .{
            .id = .source_pane,
            .parent = .root,
            .control_type = .document,
            .name = .source,
            .bounds = .{ .x = project_width, .y = content_y, .width = allocation.source_dip, .height = content_height },
            .patterns = @intFromEnum(Pattern.text),
            .state = .{ .focused = focused == .source_pane },
        };
        nodes[@intFromEnum(NodeId.pdf_pane)] = .{
            .id = .pdf_pane,
            .parent = .root,
            .control_type = .document,
            .name = .pdf,
            .bounds = .{ .x = project_width + allocation.source_dip, .y = content_y, .width = allocation.pdf_dip, .height = content_height },
            .patterns = @intFromEnum(Pattern.text),
            .state = .{ .offscreen = !layout_state.pdf_visible },
        };
        const splitter_target = if (touch_mode) layout.touch_target_dip else layout.minimum_target_dip;
        const splitter_x = if (project_width + allocation.source_dip > splitter_target / 2)
            project_width + allocation.source_dip - splitter_target / 2
        else
            0;
        nodes[@intFromEnum(NodeId.splitter)] = .{
            .id = .splitter,
            .parent = .root,
            .control_type = .separator,
            .name = .splitter,
            .bounds = .{ .x = splitter_x, .y = content_y, .width = splitter_target, .height = content_height },
            .patterns = @intFromEnum(Pattern.range_value),
            .state = .{ .offscreen = !layout_state.pdf_visible },
        };
        nodes[@intFromEnum(NodeId.mode)] = .{
            .id = .mode,
            .parent = .root,
            .control_type = .toggle,
            .name = .mode,
            .bounds = .{ .x = if (width_dip > 248) width_dip - 248 else 8, .y = layout.spacing_rhythm_dip, .width = 72, .height = control_height },
            .patterns = @intFromEnum(Pattern.toggle),
            .state = .{},
            .accelerator = "Ctrl+Shift+M",
        };
        nodes[@intFromEnum(NodeId.compile)] = .{
            .id = .compile,
            .parent = .root,
            .control_type = .button,
            .name = .compile,
            .bounds = .{ .x = if (width_dip > 168) width_dip - 168 else 8, .y = layout.spacing_rhythm_dip, .width = 80, .height = control_height },
            .patterns = @intFromEnum(Pattern.invoke),
            .state = .{ .busy = status == .rebuilding },
            .accelerator = "F5",
        };
        nodes[@intFromEnum(NodeId.save)] = .{
            .id = .save,
            .parent = .root,
            .control_type = .button,
            .name = .save,
            .bounds = .{ .x = if (width_dip > 88) width_dip - 88 else 8, .y = layout.spacing_rhythm_dip, .width = 72, .height = control_height },
            .patterns = @intFromEnum(Pattern.invoke),
            .state = .{},
            .accelerator = "Ctrl+S",
        };
        nodes[@intFromEnum(NodeId.status)] = .{
            .id = .status,
            .parent = .root,
            .control_type = .status,
            .name = .status,
            .bounds = .{ .x = layout.spacing_rhythm_dip, .y = status_y, .width = if (status == .error_status or !layout_state.supported) (if (width_dip > 128) width_dip - 128 else width_dip) else if (width_dip > 16) width_dip - 16 else width_dip, .height = layout.status_rail_dip },
            .patterns = @intFromEnum(Pattern.text),
            .state = .{ .busy = status == .rebuilding, .error_state = status == .error_status },
        };
        nodes[@intFromEnum(NodeId.recovery)] = .{
            .id = .recovery,
            .parent = .root,
            .control_type = .recovery,
            .name = .recovery,
            .bounds = .{ .x = if (width_dip > 120) width_dip - 112 else 8, .y = status_y, .width = 96, .height = layout.status_rail_dip },
            .patterns = @intFromEnum(Pattern.invoke),
            .state = .{ .offscreen = layout_state.supported and status != .error_status, .error_state = status == .error_status },
            .accelerator = "Ctrl+R",
        };

        var snapshot = Snapshot{
            .revision = revision,
            .width_dip = width_dip,
            .height_dip = height_dip,
            .touch_mode = touch_mode,
            .theme_mode = theme_mode,
            .layout_state = layout_state,
            .focused = focused,
            .status = status,
            .nodes = nodes,
        };
        try snapshot.validate();
        return snapshot;
    }

    pub fn node(self: *const Snapshot, id: NodeId) *const Node {
        return &self.nodes[@intFromEnum(id)];
    }

    pub fn validate(self: *const Snapshot) !void {
        if (self.revision == 0 or self.width_dip == 0 or self.height_dip == 0) return error.InvalidSnapshot;
        if (self.node(.root).parent != null) return error.InvalidTree;
        for (self.nodes, 0..) |item, index| {
            if (@intFromEnum(item.id) != index) return error.InvalidNodeOrder;
            _ = try strings.lookup("en-US", item.name);
            if (item.bounds.right() > self.width_dip or item.bounds.bottom() > self.height_dip) {
                if (!item.state.offscreen) return error.BoundsOutOfWindow;
            }
            var cursor: ?NodeId = item.parent;
            var hops: usize = 0;
            while (cursor) |parent| {
                if (@intFromEnum(parent) >= node_count) return error.InvalidTree;
                if (parent == item.id) return error.Cycle;
                cursor = self.node(parent).parent;
                hops += 1;
                if (hops > node_count) return error.Cycle;
            }
            if (item.interactive() and !item.bounds.meetsPointerTarget(self.touch_mode)) return error.TargetTooSmall;
        }
        if (self.node(.source_pane).state.offscreen) return error.SourceUnavailable;
        if (self.focused == .recovery and !self.node(.recovery).interactive()) return error.FocusUnavailable;
        if (!theme.passes_contrast(theme.tokens(self.theme_mode))) return error.ThemeContrast;
    }
};
