const std = @import("std");
const builtin = @import("builtin");

pub const WatchEventKind = enum {
    file_changed,
    file_deleted,
    watch_overflow,
};

pub const WatchEvent = struct {
    kind: WatchEventKind,
    relative_path: ?[]const u8 = null,
};

pub const WatcherCallback = *const fn (ctx: *anyopaque, event: WatchEvent) void;

pub const WorkspaceWatcher = struct {
    allocator: std.mem.Allocator,
    root_path: ?[:0]u8 = null,
    callback: ?WatcherCallback = null,
    callback_ctx: ?*anyopaque = null,
    is_watching: bool = false,

    pub fn init(allocator: std.mem.Allocator) WorkspaceWatcher {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *WorkspaceWatcher) void {
        self.stop();
        if (self.root_path) |p| self.allocator.free(p);
        self.root_path = null;
    }

    pub fn start(
        self: *WorkspaceWatcher,
        root_path: []const u8,
        callback: WatcherCallback,
        ctx: *anyopaque,
    ) !void {
        self.stop();
        if (self.root_path) |p| self.allocator.free(p);
        self.root_path = try self.allocator.dupeZ(u8, root_path);
        self.callback = callback;
        self.callback_ctx = ctx;
        self.is_watching = true;
    }

    pub fn stop(self: *WorkspaceWatcher) void {
        self.is_watching = false;
        self.callback = null;
        self.callback_ctx = null;
    }

    pub fn emitSimulatedEvent(self: *WorkspaceWatcher, event: WatchEvent) void {
        if (self.is_watching) {
            if (self.callback) |cb| {
                if (self.callback_ctx) |ctx| {
                    cb(ctx, event);
                }
            }
        }
    }
};
