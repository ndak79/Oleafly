const builtin = @import("builtin");
const std = @import("std");
const api = @import("windows_api");
const graphics = @import("graphics");
const native = @import("presenter_native");

const BackBufferStub = struct {
    get_calls: usize = 0,
    create_view_calls: usize = 0,
    release_calls: usize = 0,
    release_order: [2]native.testing.ReleaseKind = undefined,
    last_index: u32 = undefined,
    last_iid: ?*const anyopaque = null,
    last_resource: ?*anyopaque = null,
    released_handles: [2]*anyopaque = undefined,
    get_succeeds: bool = true,
    get_writes_output: bool = true,
    create_view_succeeds: bool = true,
    create_view_writes_output: bool = true,
    resource: ?*anyopaque = @ptrFromInt(0x1000),
    render_target_view: ?*anyopaque = @ptrFromInt(0x2000),

    fn getBuffer(
        context: ?*anyopaque,
        index: u32,
        iid: ?*const anyopaque,
        out_resource: *?*anyopaque,
    ) callconv(.c) bool {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.get_calls += 1;
        self.last_index = index;
        self.last_iid = iid;
        if (self.get_writes_output) out_resource.* = self.resource;
        return self.get_succeeds;
    }

    fn createRenderTargetView(
        context: ?*anyopaque,
        resource: ?*anyopaque,
        out_view: *?*anyopaque,
    ) callconv(.c) bool {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.create_view_calls += 1;
        self.last_resource = resource;
        if (self.create_view_writes_output) out_view.* = self.render_target_view;
        return self.create_view_succeeds;
    }

    fn release(
        context: ?*anyopaque,
        kind: native.testing.ReleaseKind,
        handle: *anyopaque,
    ) callconv(.c) void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.released_handles[self.release_calls] = handle;
        self.release_order[self.release_calls] = kind;
        self.release_calls += 1;
    }

    fn backend() native.testing.Backend {
        return .{
            .get_buffer = getBuffer,
            .create_render_target_view = createRenderTargetView,
            .release = release,
        };
    }
};

const PresentStub = struct {
    calls: usize = 0,
    last_sync_interval: u32 = undefined,
    last_present_flags: u32 = undefined,
    parameters_present: bool = false,
    dirty_rect: ?native.Rect = null,
    result: u32 = native.present_s_ok,

    fn present(
        context: ?*anyopaque,
        sync_interval: u32,
        present_flags: u32,
        parameters_present: bool,
        dirty_rect: ?*const native.Rect,
    ) callconv(.c) u32 {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.calls += 1;
        self.last_sync_interval = sync_interval;
        self.last_present_flags = present_flags;
        self.parameters_present = parameters_present;
        self.dirty_rect = if (dirty_rect) |rect| rect.* else null;
        return self.result;
    }
};

const RebindStub = struct {
    present_state: PresentStub = .{},
    release_calls: usize = 0,
    acquire_calls: usize = 0,
    unbind_calls: usize = 0,
    acquire_fails: bool = false,
    events: [4]u8 = undefined,

    fn release(
        context: ?*anyopaque,
        _: native.testing.ReleaseKind,
        _: *anyopaque,
    ) callconv(.c) void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.events[self.release_calls + self.acquire_calls] = 'r';
        self.release_calls += 1;
    }

    fn acquire(context: ?*anyopaque, index: u32) native.BackBufferError!native.BackBuffer {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.events[self.release_calls + self.acquire_calls] = 'a';
        self.acquire_calls += 1;
        if (self.acquire_fails) return error.BackBufferAcquisitionFailed;
        return .{
            .buffer_index = @intCast(index),
            .resource = @ptrFromInt(0x3000 + index * 0x100),
            .render_target_view = @ptrFromInt(0x4000 + index * 0x100),
        };
    }

    fn unbind(context: ?*anyopaque) callconv(.c) void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.unbind_calls += 1;
    }

    fn presentCall(
        context: ?*anyopaque,
        sync_interval: u32,
        present_flags: u32,
        parameters_present: bool,
        dirty_rect: ?*const native.Rect,
    ) callconv(.c) u32 {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        return PresentStub.present(
            @ptrCast(&self.present_state),
            sync_interval,
            present_flags,
            parameters_present,
            dirty_rect,
        );
    }

    fn backend() native.testing.PresentBackend {
        return .{
            .present = presentCall,
            .release = release,
            .acquire = acquire,
            .unbind = unbind,
        };
    }
};

const ResizeStub = struct {
    result: u32 = native.present_s_ok,
    resize_calls: usize = 0,
    last_width: u32 = undefined,
    last_height: u32 = undefined,
    release_calls: usize = 0,
    acquire_calls: usize = 0,
    unbind_calls: usize = 0,
    acquire_fails: bool = false,
    events: [5]u8 = undefined,

    fn resize(context: ?*anyopaque, width: u32, height: u32) callconv(.c) u32 {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.events[self.release_calls + self.resize_calls + self.acquire_calls + self.unbind_calls] = 'z';
        self.resize_calls += 1;
        self.last_width = width;
        self.last_height = height;
        return self.result;
    }

    fn unbind(context: ?*anyopaque) callconv(.c) void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.events[self.release_calls + self.resize_calls + self.acquire_calls + self.unbind_calls] = 'u';
        self.unbind_calls += 1;
    }

    fn release(
        context: ?*anyopaque,
        _: native.testing.ReleaseKind,
        _: *anyopaque,
    ) callconv(.c) void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.events[self.release_calls + self.resize_calls + self.acquire_calls + self.unbind_calls] = 'r';
        self.release_calls += 1;
    }

    fn acquire(context: ?*anyopaque, index: u32) native.BackBufferError!native.BackBuffer {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.events[self.release_calls + self.resize_calls + self.acquire_calls + self.unbind_calls] = 'a';
        self.acquire_calls += 1;
        if (self.acquire_fails) return error.BackBufferAcquisitionFailed;
        return .{
            .buffer_index = @intCast(index),
            .resource = @ptrFromInt(0x3000),
            .render_target_view = @ptrFromInt(0x4000),
        };
    }

    fn backend() native.testing.ResizeBackend {
        return .{
            .resize = resize,
            .release = release,
            .acquire = acquire,
            .unbind = unbind,
        };
    }
};

test "back-buffer owner is empty and deinit is idempotent" {
    var buffer = native.BackBuffer{};
    buffer.deinit();
    buffer.deinit();
    try std.testing.expect(buffer.resource == null);
    try std.testing.expect(buffer.render_target_view == null);
}

test "back-buffer acquisition rejects invalid inputs before backend calls" {
    var stub = BackBufferStub{};
    const context = @as(?*anyopaque, @ptrCast(&stub));
    const device_handle = @as(?*anyopaque, @ptrFromInt(0x3000));
    const chain_handle = @as(?*anyopaque, @ptrFromInt(0x4000));
    const iid = @as(?*const anyopaque, @ptrFromInt(0x5000));

    try std.testing.expectError(
        error.InvalidBackBufferIndex,
        native.testing.acquireBackBufferWith(null, chain_handle, 2, iid, BackBufferStub.backend(), context),
    );
    try std.testing.expectError(
        error.InvalidDevice,
        native.testing.acquireBackBufferWith(null, chain_handle, 0, iid, BackBufferStub.backend(), context),
    );
    try std.testing.expectError(
        error.InvalidSwapChain,
        native.testing.acquireBackBufferWith(device_handle, null, 0, iid, BackBufferStub.backend(), context),
    );
    try std.testing.expectEqual(@as(usize, 0), stub.get_calls);
    try std.testing.expectEqual(@as(usize, 0), stub.create_view_calls);
    try std.testing.expectEqual(@as(usize, 0), stub.release_calls);
}

test "back-buffer acquisition maps GetBuffer failure without creating a view" {
    var stub = BackBufferStub{
        .get_succeeds = false,
        .get_writes_output = false,
    };
    const context = @as(?*anyopaque, @ptrCast(&stub));
    const device_handle = @as(?*anyopaque, @ptrFromInt(0x3000));
    const chain_handle = @as(?*anyopaque, @ptrFromInt(0x4000));
    const iid = @as(?*const anyopaque, @ptrFromInt(0x5000));

    try std.testing.expectError(
        error.BackBufferAcquisitionFailed,
        native.testing.acquireBackBufferWith(device_handle, chain_handle, 0, iid, BackBufferStub.backend(), context),
    );
    try std.testing.expectEqual(@as(usize, 1), stub.get_calls);
    try std.testing.expectEqual(@as(u32, 0), stub.last_index);
    try std.testing.expectEqual(iid, stub.last_iid);
    try std.testing.expectEqual(@as(usize, 0), stub.create_view_calls);
    try std.testing.expectEqual(@as(usize, 0), stub.release_calls);
}

test "back-buffer acquisition releases partial resource when GetBuffer fails" {
    var stub = BackBufferStub{
        .get_succeeds = false,
        .get_writes_output = true,
    };
    const context = @as(?*anyopaque, @ptrCast(&stub));
    const device_handle = @as(?*anyopaque, @ptrFromInt(0x3000));
    const chain_handle = @as(?*anyopaque, @ptrFromInt(0x4000));
    const iid = @as(?*const anyopaque, @ptrFromInt(0x5000));

    try std.testing.expectError(
        error.BackBufferAcquisitionFailed,
        native.testing.acquireBackBufferWith(device_handle, chain_handle, 0, iid, BackBufferStub.backend(), context),
    );
    try std.testing.expectEqual(@as(usize, 1), stub.get_calls);
    try std.testing.expectEqual(@as(usize, 0), stub.create_view_calls);
    try std.testing.expectEqual(@as(usize, 1), stub.release_calls);
    try std.testing.expectEqual(native.testing.ReleaseKind.resource, stub.release_order[0]);
    try std.testing.expectEqual(stub.resource.?, stub.released_handles[0]);
}

test "back-buffer acquisition rejects null resource output after GetBuffer success" {
    var stub = BackBufferStub{
        .get_writes_output = false,
    };
    const context = @as(?*anyopaque, @ptrCast(&stub));
    const device_handle = @as(?*anyopaque, @ptrFromInt(0x3000));
    const chain_handle = @as(?*anyopaque, @ptrFromInt(0x4000));
    const iid = @as(?*const anyopaque, @ptrFromInt(0x5000));

    try std.testing.expectError(
        error.BackBufferAcquisitionFailed,
        native.testing.acquireBackBufferWith(device_handle, chain_handle, 0, iid, BackBufferStub.backend(), context),
    );
    try std.testing.expectEqual(@as(usize, 1), stub.get_calls);
    try std.testing.expectEqual(@as(usize, 0), stub.create_view_calls);
    try std.testing.expectEqual(@as(usize, 0), stub.release_calls);
}

test "back-buffer acquisition rejects null RTV output after successful creation" {
    var stub = BackBufferStub{
        .create_view_writes_output = false,
    };
    const context = @as(?*anyopaque, @ptrCast(&stub));
    const device_handle = @as(?*anyopaque, @ptrFromInt(0x3000));
    const chain_handle = @as(?*anyopaque, @ptrFromInt(0x4000));
    const iid = @as(?*const anyopaque, @ptrFromInt(0x5000));

    try std.testing.expectError(
        error.RenderTargetViewCreationFailed,
        native.testing.acquireBackBufferWith(device_handle, chain_handle, 0, iid, BackBufferStub.backend(), context),
    );
    try std.testing.expectEqual(@as(usize, 1), stub.get_calls);
    try std.testing.expectEqual(@as(usize, 1), stub.create_view_calls);
    try std.testing.expectEqual(stub.resource, stub.last_resource);
    try std.testing.expectEqual(@as(usize, 1), stub.release_calls);
    try std.testing.expectEqual(native.testing.ReleaseKind.resource, stub.release_order[0]);
    try std.testing.expectEqual(stub.resource.?, stub.released_handles[0]);
}

test "back-buffer acquisition releases resource when RTV creation fails without output" {
    var stub = BackBufferStub{
        .create_view_succeeds = false,
        .create_view_writes_output = false,
    };
    const context = @as(?*anyopaque, @ptrCast(&stub));
    const device_handle = @as(?*anyopaque, @ptrFromInt(0x3000));
    const chain_handle = @as(?*anyopaque, @ptrFromInt(0x4000));
    const iid = @as(?*const anyopaque, @ptrFromInt(0x5000));

    try std.testing.expectError(
        error.RenderTargetViewCreationFailed,
        native.testing.acquireBackBufferWith(device_handle, chain_handle, 0, iid, BackBufferStub.backend(), context),
    );
    try std.testing.expectEqual(@as(usize, 1), stub.get_calls);
    try std.testing.expectEqual(@as(usize, 1), stub.create_view_calls);
    try std.testing.expectEqual(stub.resource, stub.last_resource);
    try std.testing.expectEqual(@as(usize, 1), stub.release_calls);
    try std.testing.expectEqual(native.testing.ReleaseKind.resource, stub.release_order[0]);
    try std.testing.expectEqual(stub.resource.?, stub.released_handles[0]);
}

test "back-buffer acquisition releases partial interfaces when view creation fails" {
    var stub = BackBufferStub{
        .create_view_succeeds = false,
        .create_view_writes_output = true,
    };
    const context = @as(?*anyopaque, @ptrCast(&stub));
    const device_handle = @as(?*anyopaque, @ptrFromInt(0x3000));
    const chain_handle = @as(?*anyopaque, @ptrFromInt(0x4000));
    const iid = @as(?*const anyopaque, @ptrFromInt(0x5000));

    try std.testing.expectError(
        error.RenderTargetViewCreationFailed,
        native.testing.acquireBackBufferWith(device_handle, chain_handle, 0, iid, BackBufferStub.backend(), context),
    );
    try std.testing.expectEqual(@as(usize, 1), stub.get_calls);
    try std.testing.expectEqual(@as(usize, 1), stub.create_view_calls);
    try std.testing.expectEqual(stub.resource, stub.last_resource);
    try std.testing.expectEqual(@as(usize, 2), stub.release_calls);
    try std.testing.expectEqual(native.testing.ReleaseKind.render_target_view, stub.release_order[0]);
    try std.testing.expectEqual(native.testing.ReleaseKind.resource, stub.release_order[1]);
    try std.testing.expectEqual(stub.render_target_view.?, stub.released_handles[0]);
    try std.testing.expectEqual(stub.resource.?, stub.released_handles[1]);
}

test "back-buffer owner releases its view before resource and remains idempotent" {
    var stub = BackBufferStub{};
    const context = @as(?*anyopaque, @ptrCast(&stub));
    const device_handle = @as(?*anyopaque, @ptrFromInt(0x3000));
    const chain_handle = @as(?*anyopaque, @ptrFromInt(0x4000));
    const iid = @as(?*const anyopaque, @ptrFromInt(0x5000));

    var buffer = try native.testing.acquireBackBufferWith(
        device_handle,
        chain_handle,
        1,
        iid,
        BackBufferStub.backend(),
        context,
    );
    try std.testing.expect(buffer.resource != null);
    try std.testing.expect(buffer.render_target_view != null);
    try std.testing.expectEqual(stub.resource, stub.last_resource);

    native.testing.deinitBackBufferWith(&buffer, context, BackBufferStub.release);
    native.testing.deinitBackBufferWith(&buffer, context, BackBufferStub.release);

    try std.testing.expectEqual(@as(usize, 2), stub.release_calls);
    try std.testing.expectEqual(native.testing.ReleaseKind.render_target_view, stub.release_order[0]);
    try std.testing.expectEqual(native.testing.ReleaseKind.resource, stub.release_order[1]);
    try std.testing.expectEqual(stub.render_target_view.?, stub.released_handles[0]);
    try std.testing.expectEqual(stub.resource.?, stub.released_handles[1]);
    try std.testing.expect(buffer.resource == null);
    try std.testing.expect(buffer.render_target_view == null);
}

test "present mapping preserves success, occlusion, and device-loss classes" {
    try std.testing.expectEqual(native.PresentOutcome.presented, try native.mapPresentResult(native.present_s_ok));
    try std.testing.expectEqual(native.PresentOutcome.occluded, try native.mapPresentResult(native.dxgi_status_occluded));
    try std.testing.expectEqual(native.PresentOutcome.device_removed, try native.mapPresentResult(native.dxgi_error_device_removed));
    try std.testing.expectEqual(native.PresentOutcome.device_reset, try native.mapPresentResult(native.dxgi_error_device_reset));
    try std.testing.expectEqual(native.PresentOutcome.device_hung, try native.mapPresentResult(native.dxgi_error_device_hung));
    try std.testing.expectError(error.PresentFailed, native.mapPresentResult(0x887A0001));
}

test "resize mapping preserves success and device-loss classes" {
    try std.testing.expectEqual(native.ResizeOutcome.resized, try native.mapResizeResult(native.present_s_ok));
    try std.testing.expectEqual(native.ResizeOutcome.device_removed, try native.mapResizeResult(native.dxgi_error_device_removed));
    try std.testing.expectEqual(native.ResizeOutcome.device_reset, try native.mapResizeResult(native.dxgi_error_device_reset));
    try std.testing.expectEqual(native.ResizeOutcome.device_hung, try native.mapResizeResult(native.dxgi_error_device_hung));
    try std.testing.expectError(error.ResizeFailed, native.mapResizeResult(0x887A0001));
}

test "resize seam releases the old buffer before resizing and reacquires buffer zero" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var chain: native.SwapChain = .{ .effect = .flip_sequential, .swap_chain1 = @ptrFromInt(0x5000) };
    var buffer: native.BackBuffer = .{
        .buffer_index = 1,
        .resource = @ptrFromInt(0x1000),
        .render_target_view = @ptrFromInt(0x2000),
    };
    var stub = ResizeStub{};
    const context = @as(?*anyopaque, @ptrCast(&stub));
    const device_handle = @as(?*anyopaque, @ptrFromInt(0x3000));
    const chain_handle = @as(?*anyopaque, @ptrFromInt(0x4000));

    try std.testing.expectEqual(
        native.ResizeOutcome.resized,
        try native.testing.resizeAndRebindWith(
            &chain,
            device_handle,
            chain_handle,
            &buffer,
            .{ .width = 1280, .height = 720 },
            ResizeStub.backend(),
            context,
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), stub.resize_calls);
    try std.testing.expectEqual(@as(u32, 1280), stub.last_width);
    try std.testing.expectEqual(@as(u32, 720), stub.last_height);
    try std.testing.expectEqual(@as(usize, 2), stub.release_calls);
    try std.testing.expectEqual(@as(usize, 1), stub.acquire_calls);
    try std.testing.expectEqual(@as(usize, 1), stub.unbind_calls);
    try std.testing.expectEqual(@as(usize, 1), stub.unbind_calls);
    try std.testing.expectEqualSlices(u8, "urrza", stub.events[0..]);
    try std.testing.expectEqual(@as(u1, 0), buffer.buffer_index);
    try std.testing.expect(buffer.resource != null);
    try std.testing.expect(buffer.render_target_view != null);
}

test "resize device loss empties ownership and invalid inputs stop before callbacks" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var chain: native.SwapChain = .{ .effect = .flip_discard, .swap_chain1 = @ptrFromInt(0x5000) };
    var buffer: native.BackBuffer = .{
        .resource = @ptrFromInt(0x1000),
        .render_target_view = @ptrFromInt(0x2000),
    };
    var stub = ResizeStub{ .result = native.dxgi_error_device_removed };
    const context = @as(?*anyopaque, @ptrCast(&stub));
    const device_handle = @as(?*anyopaque, @ptrFromInt(0x3000));
    const chain_handle = @as(?*anyopaque, @ptrFromInt(0x4000));

    try std.testing.expectEqual(
        native.ResizeOutcome.device_removed,
        try native.testing.resizeAndRebindWith(
            &chain,
            device_handle,
            chain_handle,
            &buffer,
            .{},
            ResizeStub.backend(),
            context,
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), stub.resize_calls);
    try std.testing.expectEqual(@as(usize, 2), stub.release_calls);
    try std.testing.expectEqual(@as(usize, 0), stub.acquire_calls);
    try std.testing.expectEqual(@as(usize, 1), stub.unbind_calls);
    try std.testing.expectEqualSlices(u8, "urrz", stub.events[0..4]);
    try std.testing.expect(buffer.resource == null);
    try std.testing.expect(buffer.render_target_view == null);

    var invalid_buffer = native.BackBuffer{};
    try std.testing.expectError(
        error.InvalidDevice,
        native.testing.resizeAndRebindWith(
            &chain,
            null,
            chain_handle,
            &invalid_buffer,
            .{},
            ResizeStub.backend(),
            context,
        ),
    );
    try std.testing.expectError(
        error.InvalidSwapChain,
        native.testing.resizeAndRebindWith(
            &chain,
            device_handle,
            null,
            &invalid_buffer,
            .{},
            ResizeStub.backend(),
            context,
        ),
    );
    try std.testing.expectError(
        error.InvalidBackBuffer,
        native.testing.resizeAndRebindWith(
            &chain,
            device_handle,
            chain_handle,
            &invalid_buffer,
            .{},
            ResizeStub.backend(),
            context,
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), stub.resize_calls);
    try std.testing.expectEqual(@as(usize, 2), stub.release_calls);
    try std.testing.expectEqual(@as(usize, 0), stub.acquire_calls);
}

test "resize rebind failure leaves the owner empty after the new buffers exist" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var chain: native.SwapChain = .{ .effect = .flip_sequential, .swap_chain1 = @ptrFromInt(0x5000) };
    var buffer: native.BackBuffer = .{
        .resource = @ptrFromInt(0x1000),
        .render_target_view = @ptrFromInt(0x2000),
    };
    var stub = ResizeStub{ .acquire_fails = true };
    const context = @as(?*anyopaque, @ptrCast(&stub));

    try std.testing.expectError(
        error.RebindFailed,
        native.testing.resizeAndRebindWith(
            &chain,
            @ptrFromInt(0x3000),
            @ptrFromInt(0x4000),
            &buffer,
            .{},
            ResizeStub.backend(),
            context,
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), stub.unbind_calls);
    try std.testing.expectEqualSlices(u8, "urrza", stub.events[0..]);
    try std.testing.expect(buffer.resource == null);
    try std.testing.expect(buffer.render_target_view == null);
}

test "native resize rejects a device without an immediate context before callbacks" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var device = graphics.Device{
        .path = .hardware,
        .feature_level = graphics.minimum_feature_level,
        .device = @ptrFromInt(0x3000),
        .context = null,
    };
    var chain: native.SwapChain = .{ .effect = .flip_sequential, .swap_chain1 = @ptrFromInt(0x5000) };
    var buffer = native.BackBuffer{
        .resource = @ptrFromInt(0x1000),
        .render_target_view = @ptrFromInt(0x2000),
    };

    try std.testing.expectError(
        error.InvalidDeviceContext,
        chain.resizeAndRebind(&device, &buffer, .{}),
    );
    try std.testing.expect(buffer.resource != null);
    try std.testing.expect(buffer.render_target_view != null);
}

test "present seam always supplies non-null parameters and preserves dirty metadata" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var chain: native.SwapChain = .{ .effect = .flip_sequential, .swap_chain1 = @ptrFromInt(0x5000) };
    var stub = PresentStub{};
    const context = @as(?*anyopaque, @ptrCast(&stub));

    _ = try native.testing.present1With(
        &chain,
        .{ .sync_interval = 0, .present_flags = 0 },
        context,
        PresentStub.present,
    );
    try std.testing.expectEqual(@as(usize, 1), stub.calls);
    try std.testing.expect(stub.parameters_present);
    try std.testing.expect(stub.dirty_rect == null);

    const dirty = native.Rect{ .left = 2, .top = 3, .right = 20, .bottom = 30 };
    _ = try native.testing.present1With(
        &chain,
        .{ .sync_interval = 1, .present_flags = 0, .dirty_rect = dirty },
        context,
        PresentStub.present,
    );
    try std.testing.expectEqual(@as(usize, 2), stub.calls);
    try std.testing.expectEqual(@as(u32, 1), stub.last_sync_interval);
    try std.testing.expectEqual(dirty, stub.dirty_rect.?);
}

test "present seam rejects invalid requests before the callback" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var chain: native.SwapChain = .{ .effect = .flip_sequential, .swap_chain1 = @ptrFromInt(0x5000) };
    var stub = PresentStub{};
    const context = @as(?*anyopaque, @ptrCast(&stub));
    const invalid_rect = native.Rect{ .left = 5, .top = 5, .right = 5, .bottom = 4 };

    try std.testing.expectError(
        error.InvalidPresentRequest,
        native.testing.present1With(&chain, .{ .sync_interval = 5 }, context, PresentStub.present),
    );
    try std.testing.expectError(
        error.InvalidPresentRequest,
        native.testing.present1With(&chain, .{ .present_flags = 1 }, context, PresentStub.present),
    );
    try std.testing.expectError(
        error.InvalidPresentRequest,
        native.testing.present1With(&chain, .{ .dirty_rect = invalid_rect }, context, PresentStub.present),
    );
    try std.testing.expectEqual(@as(usize, 0), stub.calls);

    chain.effect = .flip_discard;
    try std.testing.expectError(
        error.PartialPresentUnsupported,
        native.testing.present1With(
            &chain,
            .{ .dirty_rect = .{ .left = 0, .top = 0, .right = 4, .bottom = 4 } },
            context,
            PresentStub.present,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), stub.calls);
}

test "present and rebind releases the old buffer before acquiring the next" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var chain: native.SwapChain = .{ .effect = .flip_sequential, .swap_chain1 = @ptrFromInt(0x7000) };
    var buffer = native.BackBuffer{
        .buffer_index = 0,
        .resource = @ptrFromInt(0x1000),
        .render_target_view = @ptrFromInt(0x2000),
    };
    var stub = RebindStub{};
    const context = @as(?*anyopaque, @ptrCast(&stub));
    const outcome = try native.testing.presentAndRebindWith(
        &chain,
        @ptrFromInt(0x6000),
        @ptrFromInt(0x7000),
        &buffer,
        .{},
        RebindStub.backend(),
        context,
    );
    try std.testing.expectEqual(native.PresentOutcome.presented, outcome);
    try std.testing.expectEqual(@as(usize, 1), stub.present_state.calls);
    try std.testing.expectEqual(@as(usize, 2), stub.release_calls);
    try std.testing.expectEqual(@as(usize, 1), stub.acquire_calls);
    try std.testing.expectEqual(@as(u8, 'r'), stub.events[0]);
    try std.testing.expectEqual(@as(u8, 'r'), stub.events[1]);
    try std.testing.expectEqual(@as(u8, 'a'), stub.events[2]);
    try std.testing.expectEqual(@as(u1, 0), buffer.buffer_index);
    try std.testing.expect(buffer.resource != null);
    try std.testing.expect(buffer.render_target_view != null);
}

test "present and rebind keeps ownership on occlusion and empties on rebind failure" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var chain: native.SwapChain = .{ .effect = .flip_sequential, .swap_chain1 = @ptrFromInt(0x7000) };
    var buffer = native.BackBuffer{
        .buffer_index = 0,
        .resource = @ptrFromInt(0x1000),
        .render_target_view = @ptrFromInt(0x2000),
    };
    var stub = RebindStub{ .present_state = .{ .result = native.dxgi_status_occluded } };
    const context = @as(?*anyopaque, @ptrCast(&stub));
    const outcome = try native.testing.presentAndRebindWith(
        &chain,
        @ptrFromInt(0x6000),
        @ptrFromInt(0x7000),
        &buffer,
        .{},
        RebindStub.backend(),
        context,
    );
    try std.testing.expectEqual(native.PresentOutcome.occluded, outcome);
    try std.testing.expectEqual(@as(usize, 0), stub.release_calls);
    try std.testing.expectEqual(@as(usize, 0), stub.unbind_calls);
    try std.testing.expect(buffer.resource != null);

    stub.present_state.result = native.present_s_ok;
    stub.acquire_fails = true;
    try std.testing.expectError(
        error.RebindFailed,
        native.testing.presentAndRebindWith(
            &chain,
            @ptrFromInt(0x6000),
            @ptrFromInt(0x7000),
            &buffer,
            .{},
            RebindStub.backend(),
            context,
        ),
    );
    try std.testing.expect(buffer.resource == null);
    try std.testing.expect(buffer.render_target_view == null);
    try std.testing.expectEqual(@as(usize, 1), stub.unbind_calls);
}

test "kernel32 facade exposes only the wait entry point" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    try std.testing.expect(@hasDecl(api.kernel32, "WaitForSingleObject"));
    try std.testing.expect(!@hasDecl(api.kernel32, "GetLastError"));
    try std.testing.expect(!@hasDecl(api.kernel32, "CreateEventW"));
    switch (@typeInfo(api.kernel32)) {
        .@"struct" => |info| {
            try std.testing.expectEqual(@as(usize, 1), info.decls.len);
            try std.testing.expectEqualStrings("WaitForSingleObject", info.decls[0].name);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "wait result constants match the curated Windows foundation values" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    try std.testing.expectEqual(
        @as(u32, @intFromEnum(api.foundation.WAIT_OBJECT_0)),
        native.wait_object_0,
    );
    try std.testing.expectEqual(
        @as(u32, @intFromEnum(api.foundation.WAIT_TIMEOUT)),
        native.wait_timeout,
    );
    try std.testing.expectEqual(
        @as(u32, @intFromEnum(api.foundation.WAIT_ABANDONED)),
        native.wait_abandoned,
    );
    try std.testing.expectEqual(
        @as(u32, @intFromEnum(api.foundation.WAIT_FAILED)),
        native.wait_failed,
    );
}

test "frame-latency wait mapping preserves each Win32 result class" {
    // WAIT_OBJECT_0 and WAIT_ABANDONED_0 are aliases for the same values as
    // NO_ERROR and WAIT_ABANDONED respectively in the curated facade.
    try std.testing.expectEqual(native.WaitOutcome.signaled, try native.mapWaitResult(native.wait_object_0));
    try std.testing.expectEqual(native.WaitOutcome.timeout, try native.mapWaitResult(native.wait_timeout));
    try std.testing.expectError(error.FrameLatencyWaitAbandoned, native.mapWaitResult(native.wait_abandoned));
    try std.testing.expectError(error.FrameLatencyWaitFailed, native.mapWaitResult(native.wait_failed));
    try std.testing.expectError(error.UnexpectedFrameLatencyWaitResult, native.mapWaitResult(1));
}

test "test-only wait seam invokes callback and maps each returned result" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const Stub = struct {
        calls: usize = 0,
        last_handle: std.os.windows.HANDLE = undefined,
        last_timeout_ms: u32 = undefined,

        fn wait(context: ?*anyopaque, handle: std.os.windows.HANDLE, timeout_ms: u32) callconv(.winapi) u32 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.calls += 1;
            self.last_handle = handle;
            self.last_timeout_ms = timeout_ms;
            return switch (self.calls) {
                1 => 258, // WAIT_TIMEOUT
                2 => 0, // WAIT_OBJECT_0
                else => 1, // Unknown, if an unexpected third call occurs.
            };
        }
    };

    var stub = Stub{};
    var chain: native.SwapChain = .{
        .effect = .flip_sequential,
        .waitable = @ptrFromInt(1),
    };
    const handle = chain.waitable.?;

    try std.testing.expectEqual(
        native.WaitOutcome.timeout,
        try native.testing.waitForFrameWith(&chain, 17, @ptrCast(&stub), Stub.wait),
    );
    try std.testing.expectEqual(
        native.WaitOutcome.signaled,
        try native.testing.waitForFrameWith(&chain, 23, @ptrCast(&stub), Stub.wait),
    );
    try std.testing.expectEqual(@as(usize, 2), stub.calls);
    try std.testing.expectEqual(handle, stub.last_handle);
    try std.testing.expectEqual(@as(u32, 23), stub.last_timeout_ms);

    const calls_after_valid_waits = stub.calls;
    chain.waitable = null;
    try std.testing.expectError(
        error.InvalidFrameLatencyHandle,
        native.testing.waitForFrameWith(&chain, 31, @ptrCast(&stub), Stub.wait),
    );
    try std.testing.expectEqual(calls_after_valid_waits, stub.calls);

    chain.waitable = std.os.windows.INVALID_HANDLE_VALUE;
    try std.testing.expectError(
        error.InvalidFrameLatencyHandle,
        native.testing.waitForFrameWith(&chain, 37, @ptrCast(&stub), Stub.wait),
    );
    try std.testing.expectEqual(calls_after_valid_waits, stub.calls);
}

test "native descriptor keeps the admitted two-buffer waitable contract" {
    const descriptor = native.nativeDescriptor(.flip_sequential);
    try std.testing.expectEqual(@as(u32, 0), descriptor.Width);
    try std.testing.expectEqual(@as(u32, 0), descriptor.Height);
    try std.testing.expectEqual(@as(u32, 2), descriptor.BufferCount);
    try std.testing.expectEqual(@as(u32, 1), descriptor.SampleDesc.Count);
    try std.testing.expectEqual(@as(u32, 0), descriptor.SampleDesc.Quality);
    try std.testing.expectEqual(@as(u32, graphics.swap_chain_flags.frame_latency_waitable_object), descriptor.Flags);
}

test "native descriptor keeps flip-discard as a full-redraw challenger" {
    const descriptor = native.nativeDescriptor(.flip_discard);
    try std.testing.expectEqual(@as(u32, 4), @as(u32, @intCast(@intFromEnum(descriptor.SwapEffect))));
    try std.testing.expectEqual(@as(u32, graphics.swap_chain_flags.frame_latency_waitable_object), descriptor.Flags);
}

test "native descriptor mirror preserves the DXGI ABI footprint" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    try std.testing.expectEqual(@sizeOf(api.dxgi.DXGI_SWAP_CHAIN_DESC1), @sizeOf(native.NativeDescriptor));
    try std.testing.expectEqual(@alignOf(api.dxgi.DXGI_SWAP_CHAIN_DESC1), @alignOf(native.NativeDescriptor));
    inline for (.{
        "Width",
        "Height",
        "Format",
        "Stereo",
        "SampleDesc",
        "BufferUsage",
        "BufferCount",
        "Scaling",
        "SwapEffect",
        "AlphaMode",
        "Flags",
    }) |field| {
        try std.testing.expectEqual(@offsetOf(api.dxgi.DXGI_SWAP_CHAIN_DESC1, field), @offsetOf(native.NativeDescriptor, field));
    }
}

test "pinned D3D11 back-buffer ABI exposes inherited GetBuffer and RTV creation" {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    try std.testing.expect(@hasField(api.dxgi.IDXGISwapChain.VTable, "GetBuffer"));
    try std.testing.expect(@hasField(api.d3d11.ID3D11Device.VTable, "CreateRenderTargetView"));
    try std.testing.expect(@hasDecl(api.d3d11, "IID_ID3D11Resource"));
    try std.testing.expect(@hasDecl(api.d3d11, "IID_ID3D11RenderTargetView"));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(api.d3d11.ID3D11Resource));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(api.d3d11.ID3D11RenderTargetView));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(@TypeOf(api.d3d11.IID_ID3D11Resource.*)));
    try std.testing.expectEqual(@as(u32, 0xdc8e63f3), api.d3d11.IID_ID3D11Resource.*.Ints.a);
}

test "native swap chain is unsupported outside Windows" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var chain: native.SwapChain = undefined;
    try std.testing.expectError(error.UnsupportedTarget, chain.waitForFrame(0));
    try std.testing.expectError(error.UnsupportedTarget, chain.acquireBackBuffer(null, 0));
}

test "native swap chain rejects missing device, chain, and invalid index" {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) return error.SkipZigTest;

    var chain: native.SwapChain = .{ .effect = .flip_sequential };
    try std.testing.expectError(error.InvalidBackBufferIndex, chain.acquireBackBuffer(null, 2));
    try std.testing.expectError(error.InvalidDevice, chain.acquireBackBuffer(null, 0));

    var invalid_device: graphics.Device = .{
        .path = .warp,
        .feature_level = @intFromEnum(graphics.FeatureLevel.level_11_0),
        .device = null,
        .context = null,
    };
    try std.testing.expectError(error.InvalidDevice, chain.acquireBackBuffer(&invalid_device, 0));

    var valid_handle_device: graphics.Device = .{
        .path = .warp,
        .feature_level = @intFromEnum(graphics.FeatureLevel.level_11_0),
        .device = @ptrFromInt(0x3000),
        .context = null,
    };
    try std.testing.expectError(error.InvalidSwapChain, chain.acquireBackBuffer(&valid_handle_device, 0));
}

const TestWindow = struct {
    hwnd: *anyopaque,
    instance: *anyopaque,
    registered_class_name: [*:0]const u16,

    const WNDPROC = *const fn (*anyopaque, u32, usize, isize) callconv(.winapi) isize;
    const WNDCLASSEXW = extern struct {
        cbSize: u32,
        style: u32,
        lpfnWndProc: WNDPROC,
        cbClsExtra: i32,
        cbWndExtra: i32,
        hInstance: *anyopaque,
        hIcon: ?*anyopaque,
        hCursor: ?*anyopaque,
        hbrBackground: ?*anyopaque,
        lpszMenuName: ?[*:0]const u16,
        lpszClassName: [*:0]const u16,
        hIconSm: ?*anyopaque,
    };

    const raw = struct {
        extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.winapi) ?*anyopaque;
        extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.winapi) u16;
        extern "user32" fn UnregisterClassW([*:0]const u16, *anyopaque) callconv(.winapi) i32;
        extern "user32" fn CreateWindowExW(u32, [*:0]const u16, [*:0]const u16, u32, i32, i32, i32, i32, ?*anyopaque, ?*anyopaque, *anyopaque, ?*anyopaque) callconv(.winapi) ?*anyopaque;
        extern "user32" fn DestroyWindow(*anyopaque) callconv(.winapi) i32;
        extern "user32" fn DefWindowProcW(*anyopaque, u32, usize, isize) callconv(.winapi) isize;
    };

    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("TExFlowPresenterNativeTest");

    fn proc(hwnd: *anyopaque, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
        return raw.DefWindowProcW(hwnd, message, wparam, lparam);
    }

    fn init() !TestWindow {
        const instance = raw.GetModuleHandleW(null) orelse return error.TestWindowUnavailable;
        const class: WNDCLASSEXW = .{
            .cbSize = @sizeOf(WNDCLASSEXW),
            .style = 0,
            .lpfnWndProc = proc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = instance,
            .hIcon = null,
            .hCursor = null,
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = class_name,
            .hIconSm = null,
        };
        if (raw.RegisterClassExW(&class) == 0) return error.TestWindowUnavailable;
        errdefer _ = raw.UnregisterClassW(class_name, instance);
        const hwnd = raw.CreateWindowExW(
            0,
            class_name,
            class_name,
            0xcf0000,
            0,
            0,
            64,
            64,
            null,
            null,
            instance,
            null,
        ) orelse return error.TestWindowUnavailable;
        return .{ .hwnd = hwnd, .instance = instance, .registered_class_name = class_name };
    }

    fn deinit(self: *TestWindow) void {
        _ = raw.DestroyWindow(self.hwnd);
        _ = raw.UnregisterClassW(self.registered_class_name, self.instance);
    }
};

test "native swap chain creates both waitable HWND effects and tears down idempotently" {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    var device = try graphics.Device.create();
    defer device.deinit();
    var window = try TestWindow.init();
    defer window.deinit();
    for ([_]graphics.SwapEffect{ .flip_sequential, .flip_discard }) |effect| {
        var chain = try native.create(&device, window.hwnd, effect);
        try std.testing.expect(chain.waitableHandle() != null);
        try std.testing.expectEqual(@as(u32, 1), chain.maximumFrameLatency());

        switch (try chain.waitForFrame(0)) {
            .signaled, .timeout => {},
        }

        chain.deinit();
        try std.testing.expectError(error.InvalidFrameLatencyHandle, chain.waitForFrame(0));
        chain.deinit();
    }
}

test "native swap chain acquires real back buffers and render-target views" {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    var device = try graphics.Device.create();
    defer device.deinit();
    var window = try TestWindow.init();
    defer window.deinit();
    for ([_]graphics.SwapEffect{ .flip_sequential, .flip_discard }) |effect| {
        var chain = try native.create(&device, window.hwnd, effect);
        defer chain.deinit();
        var buffer = try chain.acquireBackBuffer(&device, 0);
        try std.testing.expect(buffer.resource != null);
        try std.testing.expect(buffer.render_target_view != null);
        buffer.deinit();
        buffer.deinit();
        try std.testing.expect(buffer.resource == null);
        try std.testing.expect(buffer.render_target_view == null);

        if (chain.acquireBackBuffer(&device, 1)) |buffer_one| {
            var acquired = buffer_one;
            try std.testing.expect(acquired.resource != null);
            try std.testing.expect(acquired.render_target_view != null);
            acquired.deinit();
            acquired.deinit();
            try std.testing.expect(acquired.resource == null);
            try std.testing.expect(acquired.render_target_view == null);
        } else |err| switch (err) {
            error.BackBufferAcquisitionFailed, error.RenderTargetViewCreationFailed => {},
            else => return err,
        }
    }
}

test "native swap chain presents with non-null parameters and rebinds both effects" {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    var device = try graphics.Device.create();
    defer device.deinit();
    var window = try TestWindow.init();
    defer window.deinit();
    for ([_]graphics.SwapEffect{ .flip_sequential, .flip_discard }) |effect| {
        var chain = try native.create(&device, window.hwnd, effect);
        defer chain.deinit();
        var buffer = try chain.acquireBackBuffer(&device, 0);
        const outcome = try chain.presentAndRebind(&device, &buffer, .{});
        switch (outcome) {
            .presented => {
                try std.testing.expect(buffer.resource != null);
                try std.testing.expect(buffer.render_target_view != null);
                try std.testing.expectEqual(@as(u1, 0), buffer.buffer_index);
            },
            .occluded, .device_removed, .device_reset, .device_hung => {
                try std.testing.expect(buffer.resource != null);
                try std.testing.expect(buffer.render_target_view != null);
            },
        }
        buffer.deinit();
    }
}

test "native swap chain resizes and rebinds both effects" {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    var device = try graphics.Device.create();
    defer device.deinit();
    var window = try TestWindow.init();
    defer window.deinit();
    for ([_]graphics.SwapEffect{ .flip_sequential, .flip_discard }) |effect| {
        var chain = try native.create(&device, window.hwnd, effect);
        defer chain.deinit();
        var buffer = try chain.acquireBackBuffer(&device, 0);
        const outcome = try chain.resizeAndRebind(&device, &buffer, .{ .width = 64, .height = 64 });
        try std.testing.expectEqual(native.ResizeOutcome.resized, outcome);
        try std.testing.expect(buffer.resource != null);
        try std.testing.expect(buffer.render_target_view != null);
        try std.testing.expectEqual(@as(u1, 0), buffer.buffer_index);
        buffer.deinit();
    }
}
