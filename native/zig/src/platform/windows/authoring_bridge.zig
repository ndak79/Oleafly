const std = @import("std");
const workspace = @import("workspace");
const editor_buffer = @import("editor_buffer");
const atomic_save = @import("atomic_save");
pub const authoring_session = @import("authoring_session");
const workspace_picker = @import("workspace_picker");
const workspace_watcher = @import("workspace_watcher");

pub const BridgeAction = enum {
    open_folder,
    mode_change,
    compile_request,
    save,
    show_recovery,
};

pub fn mapCommandId(command_id: u16) ?BridgeAction {
    return switch (command_id) {
        100 => .open_folder,
        101 => .mode_change,
        102 => .compile_request,
        103 => .save,
        104 => .show_recovery,
        else => null,
    };
}

pub const AuthoringBridge = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    session: authoring_session.Session,
    picker: ?workspace_picker.WorkspacePicker = null,
    watcher: workspace_watcher.WorkspaceWatcher,
    compile_requested: bool = false,
    recovery_visible: bool = false,
    frame_needed: bool = false,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) AuthoringBridge {
        return .{
            .allocator = allocator,
            .io = io,
            .session = authoring_session.Session.init(allocator, io),
            .watcher = workspace_watcher.WorkspaceWatcher.init(allocator),
        };
    }

    pub fn deinit(self: *AuthoringBridge) void {
        self.watcher.deinit();
        self.session.deinit();
        self.* = undefined;
    }

    pub fn setPicker(self: *AuthoringBridge, picker: workspace_picker.WorkspacePicker) void {
        self.picker = picker;
    }

    pub fn dispatchCommandId(self: *AuthoringBridge, id: u16) !bool {
        const action = mapCommandId(id) orelse return false;
        try self.dispatchAction(action);
        return true;
    }

    pub fn dispatchAction(self: *AuthoringBridge, action: BridgeAction) !void {
        switch (action) {
            .open_folder => {
                if (self.picker) |p| {
                    var pick_res = try p.pick(self.allocator);
                    defer pick_res.deinit();
                    if (pick_res.path) |folder_path| {
                        try self.session.openFolder(folder_path);
                        try self.watcher.start(folder_path, onWatchEvent, self);
                        self.frame_needed = true;
                    }
                }
            },
            .mode_change => {
                self.frame_needed = true;
            },
            .compile_request => {
                self.compile_requested = true;
                self.frame_needed = true;
            },
            .save => {
                if (self.session.getBuffer() != null) {
                    var outcome = try self.session.save();
                    defer outcome.deinit();
                    if (outcome.status == .recovery_retained) {
                        self.recovery_visible = true;
                    }
                    self.frame_needed = true;
                }
            },
            .show_recovery => {
                self.recovery_visible = true;
                self.frame_needed = true;
            },
        }
    }

    fn onWatchEvent(ctx: *anyopaque, event: workspace_watcher.WatchEvent) void {
        const self: *AuthoringBridge = @ptrCast(@alignCast(ctx));
        const change: authoring_session.ExternalChange = switch (event.kind) {
            .file_changed => .file_changed,
            .file_deleted => .file_deleted,
            .watch_overflow => .watch_overflow,
        };
        self.session.handleExternalEvent(change, event.relative_path, null) catch {};
        self.frame_needed = true;
    }

    pub fn takeFrameNeeded(self: *AuthoringBridge) bool {
        const needed = self.frame_needed;
        self.frame_needed = false;
        return needed;
    }
};
