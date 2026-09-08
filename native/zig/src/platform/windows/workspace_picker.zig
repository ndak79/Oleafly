const std = @import("std");
const builtin = @import("builtin");

pub const PickResult = struct {
    allocator: std.mem.Allocator,
    path: ?[:0]u8 = null,

    pub fn deinit(self: *PickResult) void {
        if (self.path) |p| self.allocator.free(p);
        self.path = null;
    }
};

pub const PickerFn = *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) anyerror!PickResult;

pub const WorkspacePicker = struct {
    ctx: *anyopaque,
    pick_fn: PickerFn,

    pub fn pick(self: WorkspacePicker, allocator: std.mem.Allocator) !PickResult {
        return self.pick_fn(self.ctx, allocator);
    }
};

pub const FakePicker = struct {
    next_path: ?[]const u8 = null,

    pub fn init(next_path: ?[]const u8) FakePicker {
        return .{ .next_path = next_path };
    }

    pub fn picker(self: *FakePicker) WorkspacePicker {
        return .{
            .ctx = self,
            .pick_fn = pickImpl,
        };
    }

    fn pickImpl(ctx: *anyopaque, allocator: std.mem.Allocator) anyerror!PickResult {
        const self: *FakePicker = @ptrCast(@alignCast(ctx));
        if (self.next_path) |p| {
            const copy = try allocator.dupeZ(u8, p);
            return .{ .allocator = allocator, .path = copy };
        }
        return .{ .allocator = allocator, .path = null };
    }
};
