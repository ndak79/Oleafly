//! Minimal native DXGI binding for the admitted TExFlow HWND presenter.
//!
//! The policy/state machine lives in `presenter.zig`; this adapter owns only
//! the COM interfaces, DXGI frame-latency handle, and acquired back-buffer
//! resource/render-target-view pair, the bounded Present1/ResizeBuffers
//! ownership barriers, and a minimal full-frame D3D11 clear path. D2D/DirectWrite
//! composition remains deferred; frame retirement and shell-level device-loss
//! recovery are explicit seams in this layer.
//! Every Windows call is behind the curated `windows_api` facade, while
//! non-Windows builds retain a compile-only surface for the portable model
//! lane.
const builtin = @import("builtin");
const std = @import("std");
const api = @import("windows_api");
const graphics = @import("graphics");

pub const SampleDescription = extern struct {
    Count: u32,
    Quality: u32,
};

pub const Format = enum(u32) {
    bgra8_unorm = 87,
};

pub const Scaling = enum(u32) {
    stretch = 0,
};

pub const SwapEffect = enum(u32) {
    flip_sequential = 3,
    flip_discard = 4,
};

pub const AlphaMode = enum(u32) {
    unspecified = 0,
};

pub const WaitOutcome = enum {
    signaled,
    timeout,
};

pub const WaitError = error{
    FrameLatencyWaitAbandoned,
    FrameLatencyWaitFailed,
    InvalidFrameLatencyHandle,
    UnexpectedFrameLatencyWaitResult,
    UnsupportedTarget,
};

pub const BackBufferError = error{
    BackBufferAcquisitionFailed,
    InvalidBackBufferIndex,
    InvalidDevice,
    InvalidSwapChain,
    RenderTargetViewCreationFailed,
    UnsupportedTarget,
};

pub const RetireError = error{
    InvalidBackBuffer,
    InvalidDevice,
    InvalidDeviceContext,
    InvalidSwapChain,
    UnsupportedTarget,
};

pub const PresentError = error{
    InvalidBackBuffer,
    InvalidDevice,
    InvalidDeviceContext,
    InvalidPresentRequest,
    InvalidSwapChain,
    PartialPresentUnsupported,
    PresentFailed,
    RebindFailed,
    UnsupportedTarget,
};

pub const ResizeError = error{
    InvalidBackBuffer,
    InvalidDevice,
    InvalidDeviceContext,
    InvalidSwapChain,
    RebindFailed,
    ResizeFailed,
    UnsupportedTarget,
};

pub const RenderError = error{
    InvalidBackBuffer,
    InvalidDevice,
    InvalidDeviceContext,
    InvalidRenderRequest,
    InvalidSwapChain,
    RenderFailed,
    UnsupportedTarget,
};

pub const Rect = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

pub const PresentRequest = struct {
    sync_interval: u32 = 0,
    present_flags: u32 = 0,
    dirty_rect: ?Rect = null,
};

pub const PresentOutcome = enum {
    presented,
    occluded,
    device_removed,
    device_reset,
    device_hung,
};

pub const ResizeRequest = struct {
    /// A zero dimension delegates sizing to DXGI (the HWND's current client
    /// size), matching the descriptor admitted by this presenter.
    width: u32 = 0,
    height: u32 = 0,
};

pub const ResizeOutcome = enum {
    resized,
    device_removed,
    device_reset,
    device_hung,
};

pub const RenderRequest = struct {
    width: u32 = 0,
    height: u32 = 0,
    clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
};

pub const RenderOutcome = enum {
    cleared,
};

pub const wait_object_0: u32 = 0;
pub const wait_abandoned: u32 = 128;
pub const wait_timeout: u32 = 258;
pub const wait_failed: u32 = std.math.maxInt(u32);

pub const present_s_ok: u32 = 0;
pub const dxgi_status_occluded: u32 = 0x087A0001;
pub const dxgi_error_device_hung: u32 = 0x887A0006;
pub const dxgi_error_device_removed: u32 = 0x887A0005;
pub const dxgi_error_device_reset: u32 = 0x887A0007;
pub const max_present_sync_interval: u32 = 4;
pub const present_flags_none: u32 = 0;
const admitted_buffer_count: u32 = 2;

/// Convert a `WaitForSingleObject` result without hiding failure or unknown
/// status values as a timeout. `WAIT_ABANDONED` and `WAIT_ABANDONED_0` are
/// aliases with the same value for a single-object wait.
pub fn mapWaitResult(result: u32) WaitError!WaitOutcome {
    return switch (result) {
        wait_object_0 => .signaled, // WAIT_OBJECT_0
        wait_timeout => .timeout, // WAIT_TIMEOUT
        wait_abandoned => error.FrameLatencyWaitAbandoned, // WAIT_ABANDONED/_0
        wait_failed => error.FrameLatencyWaitFailed, // WAIT_FAILED
        else => error.UnexpectedFrameLatencyWaitResult,
    };
}

pub fn mapPresentResult(result: u32) PresentError!PresentOutcome {
    return switch (result) {
        present_s_ok => .presented,
        dxgi_status_occluded => .occluded,
        dxgi_error_device_removed => .device_removed,
        dxgi_error_device_reset => .device_reset,
        dxgi_error_device_hung => .device_hung,
        else => error.PresentFailed,
    };
}

pub fn mapResizeResult(result: u32) ResizeError!ResizeOutcome {
    return switch (result) {
        present_s_ok => .resized,
        dxgi_error_device_removed => .device_removed,
        dxgi_error_device_reset => .device_reset,
        dxgi_error_device_hung => .device_hung,
        else => error.ResizeFailed,
    };
}

const WaitFn = *const fn (?*anyopaque, std.os.windows.HANDLE, u32) callconv(.winapi) u32;

/// Portable mirror of the DXGI 1.2 descriptor.  It contains no pointers and
/// is converted to the generated zigwin32 type only at the Windows ABI edge.
pub const NativeDescriptor = extern struct {
    Width: u32,
    Height: u32,
    Format: Format,
    Stereo: u32,
    SampleDesc: SampleDescription,
    BufferUsage: u32,
    BufferCount: u32,
    Scaling: Scaling,
    SwapEffect: SwapEffect,
    AlphaMode: AlphaMode,
    Flags: u32,
};

pub fn nativeDescriptor(effect: graphics.SwapEffect) NativeDescriptor {
    return .{
        .Width = 0,
        .Height = 0,
        .Format = .bgra8_unorm,
        .Stereo = 0,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .BufferUsage = 0x20, // DXGI_USAGE_RENDER_TARGET_OUTPUT
        .BufferCount = admitted_buffer_count,
        .Scaling = .stretch,
        .SwapEffect = switch (effect) {
            .flip_sequential => .flip_sequential,
            .flip_discard => .flip_discard,
        },
        .AlphaMode = .unspecified,
        .Flags = graphics.swap_chain_flags.frame_latency_waitable_object,
    };
}

const BackBufferReleaseKind = enum(u8) {
    render_target_view,
    resource,
};

const BackBufferReleaseFn = *const fn (
    ?*anyopaque,
    BackBufferReleaseKind,
    *anyopaque,
) callconv(.c) void;

const BackBufferBackend = struct {
    get_buffer: *const fn (
        ?*anyopaque,
        u32,
        ?*const anyopaque,
        *?*anyopaque,
    ) callconv(.c) bool,
    create_render_target_view: *const fn (
        ?*anyopaque,
        ?*anyopaque,
        *?*anyopaque,
    ) callconv(.c) bool,
    release: BackBufferReleaseFn,
};

const PresentFn = *const fn (
    ?*anyopaque,
    u32,
    u32,
    bool,
    ?*const Rect,
) callconv(.c) u32;

const UnbindFn = *const fn (?*anyopaque) callconv(.c) void;

const PresentBackendImpl = struct {
    present: PresentFn,
    release: BackBufferReleaseFn,
    acquire: *const fn (?*anyopaque, u32) BackBufferError!BackBuffer,
    unbind: ?UnbindFn = null,
};

const ResizeFn = *const fn (?*anyopaque, u32, u32) callconv(.c) u32;

const ResizeBackendImpl = struct {
    resize: ResizeFn,
    release: BackBufferReleaseFn,
    acquire: *const fn (?*anyopaque, u32) BackBufferError!BackBuffer,
    unbind: ?UnbindFn = null,
};

const RenderFn = *const fn (
    ?*anyopaque,
    *anyopaque,
    *anyopaque,
    *const RenderRequest,
) callconv(.c) bool;

const RenderBackendImpl = struct {
    render: RenderFn,
};

const WindowsAcquireContext = struct {
    device_handle: *anyopaque,
    swap_chain_handle: *anyopaque,
    context_handle: ?*anyopaque = null,
};

/// Owns the two COM references returned by `SwapChain.acquireBackBuffer`.
/// This is a move-like value: copying it does not call `AddRef`, so only one
/// owner may call `deinit`. Call `deinit` before any future swap-chain resize
/// or rebuild that could invalidate its underlying back buffer.
pub const BackBuffer = struct {
    buffer_index: u1 = 0,
    resource: if (builtin.os.tag == .windows) ?*api.d3d11.ID3D11Resource else ?*anyopaque = null,
    render_target_view: if (builtin.os.tag == .windows) ?*api.d3d11.ID3D11RenderTargetView else ?*anyopaque = null,

    pub fn deinit(self: *BackBuffer) void {
        if (builtin.os.tag != .windows) {
            self.render_target_view = null;
            self.resource = null;
            return;
        }
        deinitBackBufferWithImpl(self, null, releaseBackBufferInterface);
    }

    fn complete(self: *const BackBuffer) bool {
        return self.resource != null and self.render_target_view != null;
    }
};

pub const SwapChain = struct {
    effect: graphics.SwapEffect,
    maximum_frame_latency: u32 = graphics.max_frame_latency,
    swap_chain1: if (builtin.os.tag == .windows) ?*api.dxgi.IDXGISwapChain1 else ?*anyopaque = null,
    swap_chain2: if (builtin.os.tag == .windows) ?*api.dxgi.IDXGISwapChain2 else ?*anyopaque = null,
    waitable: if (builtin.os.tag == .windows) ?std.os.windows.HANDLE else ?*anyopaque = null,

    pub fn waitableHandle(self: *const SwapChain) ?*anyopaque {
        if (builtin.os.tag != .windows) return null;
        return if (self.waitable) |handle| @ptrCast(handle) else null;
    }

    pub fn maximumFrameLatency(self: *const SwapChain) u32 {
        return self.maximum_frame_latency;
    }

    /// Wait for the DXGI frame-latency grant before rendering. The caller must
    /// use this before the first rendered frame and before every rendered
    /// frame; this primitive only waits and does not schedule frames.
    pub fn waitForFrame(self: *const SwapChain, timeout_ms: u32) WaitError!WaitOutcome {
        return waitForFrameWithImpl(self, timeout_ms, null, waitForSingleObject);
    }

    pub fn acquireBackBuffer(
        self: *const SwapChain,
        device: ?*const graphics.Device,
        buffer_index: u32,
    ) BackBufferError!BackBuffer {
        if (builtin.os.tag != .windows) return error.UnsupportedTarget;
        if (buffer_index >= 2) return error.InvalidBackBufferIndex;
        const device_value = device orelse return error.InvalidDevice;
        const device_handle = device_value.deviceHandle() orelse return error.InvalidDevice;
        const swap_chain = self.swap_chain1 orelse return error.InvalidSwapChain;
        return acquireBackBufferWindows(device_handle, swap_chain, buffer_index);
    }

    /// Retire an acquired owner before swap-chain/device destruction. The
    /// immediate context is explicitly unbound first because a render call may
    /// have left the RTV in the output-merger, including on device-loss paths
    /// where Present1 did not reach its normal unbind/rebind branch.
    pub fn retireBackBuffer(
        self: *const SwapChain,
        device: ?*const graphics.Device,
        buffer: *BackBuffer,
    ) RetireError!void {
        if (builtin.os.tag != .windows) return error.UnsupportedTarget;
        if (self.swap_chain1 == null) return error.InvalidSwapChain;
        if (!buffer.complete()) return error.InvalidBackBuffer;
        const device_value = device orelse return error.InvalidDevice;
        const device_handle = device_value.deviceHandle() orelse return error.InvalidDevice;
        const context_handle = device_value.contextHandle() orelse return error.InvalidDeviceContext;
        const swap_chain = self.swap_chain1 orelse return error.InvalidSwapChain;
        var context = WindowsAcquireContext{
            .device_handle = device_handle,
            .swap_chain_handle = @ptrCast(swap_chain),
            .context_handle = context_handle,
        };
        unbindRenderTargetWindows(@ptrCast(&context));
        buffer.deinit();
    }

    pub fn presentAndRebind(
        self: *const SwapChain,
        device: ?*const graphics.Device,
        buffer: *BackBuffer,
        request: PresentRequest,
    ) PresentError!PresentOutcome {
        if (builtin.os.tag != .windows) return error.UnsupportedTarget;
        const device_value = device orelse return error.InvalidDevice;
        const device_handle = device_value.deviceHandle() orelse return error.InvalidDevice;
        const context_handle = device_value.contextHandle() orelse return error.InvalidDeviceContext;
        const swap_chain = self.swap_chain1 orelse return error.InvalidSwapChain;
        var context = WindowsAcquireContext{
            .device_handle = device_handle,
            .swap_chain_handle = @ptrCast(swap_chain),
            .context_handle = context_handle,
        };
        return presentAndRebindWithImpl(
            self,
            device_handle,
            @ptrCast(swap_chain),
            buffer,
            request,
            .{
                .present = present1Windows,
                .release = releaseBackBufferInterface,
                .acquire = acquireBackBufferWindowsFromContext,
                .unbind = unbindRenderTargetWindows,
            },
            @ptrCast(&context),
        );
    }

    pub fn resizeAndRebind(
        self: *const SwapChain,
        device: ?*const graphics.Device,
        buffer: *BackBuffer,
        request: ResizeRequest,
    ) ResizeError!ResizeOutcome {
        if (builtin.os.tag != .windows) return error.UnsupportedTarget;
        const device_value = device orelse return error.InvalidDevice;
        const device_handle = device_value.deviceHandle() orelse return error.InvalidDevice;
        const context_handle = device_value.contextHandle() orelse return error.InvalidDeviceContext;
        const swap_chain = self.swap_chain1 orelse return error.InvalidSwapChain;
        var context = WindowsAcquireContext{
            .device_handle = device_handle,
            .swap_chain_handle = @ptrCast(swap_chain),
            .context_handle = context_handle,
        };
        return resizeAndRebindWithImpl(
            self,
            device_handle,
            @ptrCast(swap_chain),
            buffer,
            request,
            .{
                .resize = resizeBuffersWindows,
                .release = releaseBackBufferInterface,
                .acquire = acquireBackBufferWindowsFromContext,
                .unbind = unbindRenderTargetWindows,
            },
            @ptrCast(&context),
        );
    }

    pub fn renderClear(
        self: *const SwapChain,
        device: ?*const graphics.Device,
        buffer: *BackBuffer,
        request: RenderRequest,
    ) RenderError!RenderOutcome {
        if (builtin.os.tag != .windows) return error.UnsupportedTarget;
        if (self.swap_chain1 == null) return error.InvalidSwapChain;
        const device_value = device orelse return error.InvalidDevice;
        const device_handle = device_value.deviceHandle() orelse return error.InvalidDevice;
        const context_handle = device_value.contextHandle() orelse return error.InvalidDeviceContext;
        return renderClearWithImpl(
            device_handle,
            context_handle,
            buffer,
            request,
            .{ .render = renderClearWindows },
            null,
        );
    }

    pub fn deinit(self: *SwapChain) void {
        if (builtin.os.tag != .windows) {
            self.swap_chain1 = null;
            self.swap_chain2 = null;
            self.waitable = null;
            return;
        }
        if (self.waitable) |handle| {
            _ = std.os.windows.CloseHandle(handle);
            self.waitable = null;
        }
        if (self.swap_chain2) |chain| {
            _ = chain.IUnknown.Release();
            self.swap_chain2 = null;
        }
        if (self.swap_chain1) |chain| {
            _ = chain.IUnknown.Release();
            self.swap_chain1 = null;
        }
    }
};

fn waitForSingleObject(
    _: ?*anyopaque,
    handle: std.os.windows.HANDLE,
    timeout_ms: u32,
) callconv(.winapi) u32 {
    if (comptime builtin.os.tag != .windows) unreachable;
    return @intFromEnum(api.kernel32.WaitForSingleObject(handle, timeout_ms));
}

fn waitForFrameWithImpl(
    self: *const SwapChain,
    timeout_ms: u32,
    context: ?*anyopaque,
    wait_fn: WaitFn,
) WaitError!WaitOutcome {
    if (comptime builtin.os.tag != .windows) return error.UnsupportedTarget;
    const handle = self.waitable orelse return error.InvalidFrameLatencyHandle;
    if (handle == std.os.windows.INVALID_HANDLE_VALUE) return error.InvalidFrameLatencyHandle;
    return mapWaitResult(wait_fn(context, handle, timeout_ms));
}

fn validatePresentRequest(effect: graphics.SwapEffect, request: PresentRequest) PresentError!void {
    if (request.sync_interval > max_present_sync_interval or request.present_flags != present_flags_none) {
        return error.InvalidPresentRequest;
    }
    if (request.dirty_rect) |rect| {
        if (effect == .flip_discard) return error.PartialPresentUnsupported;
        if (rect.left >= rect.right or rect.top >= rect.bottom) return error.InvalidPresentRequest;
    }
}

fn present1WithImpl(
    self: *const SwapChain,
    request: PresentRequest,
    context: ?*anyopaque,
    present_fn: PresentFn,
) PresentError!PresentOutcome {
    if (comptime builtin.os.tag != .windows) return error.UnsupportedTarget;
    if (self.swap_chain1 == null) return error.InvalidSwapChain;
    try validatePresentRequest(switch (self.effect) {
        .flip_sequential => .flip_sequential,
        .flip_discard => .flip_discard,
    }, request);
    return mapPresentResult(present_fn(
        context,
        request.sync_interval,
        request.present_flags,
        true,
        if (request.dirty_rect) |*rect| rect else null,
    ));
}

fn presentAndRebindWithImpl(
    self: *const SwapChain,
    device_handle: ?*anyopaque,
    swap_chain_handle: ?*anyopaque,
    buffer: *BackBuffer,
    request: PresentRequest,
    backend: PresentBackendImpl,
    context: ?*anyopaque,
) PresentError!PresentOutcome {
    if (comptime builtin.os.tag != .windows) return error.UnsupportedTarget;
    if (device_handle == null) return error.InvalidDevice;
    if (swap_chain_handle == null) return error.InvalidSwapChain;
    if (!buffer.complete()) return error.InvalidBackBuffer;
    const outcome = try present1WithImpl(self, request, context, backend.present);
    if (outcome != .presented) return outcome;

    const next_index: u32 = 0;
    if (backend.unbind) |unbind| unbind(context);
    deinitBackBufferWithImpl(buffer, context, backend.release);
    const rebound = backend.acquire(context, next_index) catch {
        return error.RebindFailed;
    };
    buffer.* = rebound;
    return .presented;
}

fn resizeAndRebindWithImpl(
    self: *const SwapChain,
    device_handle: ?*anyopaque,
    swap_chain_handle: ?*anyopaque,
    buffer: *BackBuffer,
    request: ResizeRequest,
    backend: ResizeBackendImpl,
    context: ?*anyopaque,
) ResizeError!ResizeOutcome {
    if (comptime builtin.os.tag != .windows) return error.UnsupportedTarget;
    if (device_handle == null) return error.InvalidDevice;
    if (swap_chain_handle == null or self.swap_chain1 == null) return error.InvalidSwapChain;
    if (!buffer.complete()) return error.InvalidBackBuffer;

    // DXGI requires every reference to an old back buffer to be released
    // before ResizeBuffers.  The owner intentionally stays empty until the
    // new canonical buffer (index zero) has been acquired successfully.
    if (backend.unbind) |unbind| unbind(context);
    deinitBackBufferWithImpl(buffer, context, backend.release);
    const outcome = try mapResizeResult(backend.resize(context, request.width, request.height));
    if (outcome != .resized) return outcome;

    const rebound = backend.acquire(context, 0) catch {
        return error.RebindFailed;
    };
    buffer.* = rebound;
    return .resized;
}

fn renderClearWithImpl(
    device_handle: ?*anyopaque,
    context_handle: ?*anyopaque,
    buffer: *const BackBuffer,
    request: RenderRequest,
    backend: RenderBackendImpl,
    context: ?*anyopaque,
) RenderError!RenderOutcome {
    if (comptime builtin.os.tag != .windows) return error.UnsupportedTarget;
    if (device_handle == null) return error.InvalidDevice;
    if (context_handle == null) return error.InvalidDeviceContext;
    if (!buffer.complete()) return error.InvalidBackBuffer;
    if (request.width == 0 or request.height == 0) return error.InvalidRenderRequest;
    if (!backend.render(context, context_handle.?, @ptrCast(buffer.render_target_view.?), &request)) {
        return error.RenderFailed;
    }
    return .cleared;
}

fn deinitBackBufferWithImpl(
    self: *BackBuffer,
    context: ?*anyopaque,
    release_fn: BackBufferReleaseFn,
) void {
    if (self.render_target_view) |render_target_view| {
        release_fn(context, .render_target_view, @ptrCast(render_target_view));
        self.render_target_view = null;
    }
    if (self.resource) |resource| {
        release_fn(context, .resource, @ptrCast(resource));
        self.resource = null;
    }
}

fn releaseBackBufferInterface(
    _: ?*anyopaque,
    kind: BackBufferReleaseKind,
    handle: *anyopaque,
) callconv(.c) void {
    if (comptime builtin.os.tag != .windows) unreachable;
    switch (kind) {
        .render_target_view => {
            const render_target_view: *api.d3d11.ID3D11RenderTargetView = @ptrCast(@alignCast(handle));
            _ = render_target_view.IUnknown.Release();
        },
        .resource => {
            const resource: *api.d3d11.ID3D11Resource = @ptrCast(@alignCast(handle));
            _ = resource.IUnknown.Release();
        },
    }
}

fn unbindRenderTargetWindows(context: ?*anyopaque) callconv(.c) void {
    if (comptime builtin.os.tag != .windows) unreachable;
    const windows_context: *const WindowsAcquireContext = @ptrCast(@alignCast(context.?));
    const context_handle = windows_context.context_handle orelse unreachable;
    const immediate_context: *api.d3d11.ID3D11DeviceContext = @ptrCast(@alignCast(context_handle));
    immediate_context.OMSetRenderTargets(0, null, null);
}

fn acquireBackBufferWithImpl(
    device_handle: ?*anyopaque,
    swap_chain_handle: ?*anyopaque,
    buffer_index: u32,
    resource_iid: ?*const anyopaque,
    backend: BackBufferBackend,
    context: ?*anyopaque,
) BackBufferError!BackBuffer {
    if (buffer_index >= 2) return error.InvalidBackBufferIndex;
    if (device_handle == null) return error.InvalidDevice;
    if (swap_chain_handle == null) return error.InvalidSwapChain;

    var resource: ?*anyopaque = null;
    if (!backend.get_buffer(context, buffer_index, resource_iid, &resource) or resource == null) {
        if (resource) |partial_resource| backend.release(context, .resource, partial_resource);
        return error.BackBufferAcquisitionFailed;
    }

    var render_target_view: ?*anyopaque = null;
    if (!backend.create_render_target_view(context, resource, &render_target_view) or render_target_view == null) {
        if (render_target_view) |partial_view| backend.release(context, .render_target_view, partial_view);
        backend.release(context, .resource, resource.?);
        return error.RenderTargetViewCreationFailed;
    }

    return .{
        .buffer_index = @intCast(buffer_index),
        .resource = if (comptime builtin.os.tag == .windows)
            @ptrCast(@alignCast(resource.?))
        else
            resource,
        .render_target_view = if (comptime builtin.os.tag == .windows)
            @ptrCast(@alignCast(render_target_view.?))
        else
            render_target_view,
    };
}

fn getBufferWindows(
    context: ?*anyopaque,
    buffer_index: u32,
    resource_iid: ?*const anyopaque,
    out_resource: *?*anyopaque,
) callconv(.c) bool {
    if (comptime builtin.os.tag != .windows) unreachable;
    const windows_context: *const WindowsAcquireContext = @ptrCast(@alignCast(context.?));
    const swap_chain: *api.dxgi.IDXGISwapChain1 = @ptrCast(@alignCast(windows_context.swap_chain_handle));
    const Guid = @TypeOf(api.d3d11.IID_ID3D11Resource.*);
    const iid: ?*const Guid = if (resource_iid) |value| @ptrCast(@alignCast(value)) else null;
    var resource: ?*anyopaque = null;
    const result = swap_chain.IDXGISwapChain.GetBuffer(
        buffer_index,
        iid,
        @ptrCast(&resource),
    );
    out_resource.* = resource;
    return !result.failed and resource != null;
}

fn createRenderTargetViewWindows(
    context: ?*anyopaque,
    resource: ?*anyopaque,
    out_view: *?*anyopaque,
) callconv(.c) bool {
    if (comptime builtin.os.tag != .windows) unreachable;
    const windows_context: *const WindowsAcquireContext = @ptrCast(@alignCast(context.?));
    const device: *api.d3d11.ID3D11Device = @ptrCast(@alignCast(windows_context.device_handle));
    const resource_value: *api.d3d11.ID3D11Resource = @ptrCast(@alignCast(resource.?));
    var render_target_view: ?*api.d3d11.ID3D11RenderTargetView = null;
    const result = device.CreateRenderTargetView(resource_value, null, @ptrCast(&render_target_view));
    out_view.* = if (render_target_view) |view| @ptrCast(view) else null;
    return !result.failed and render_target_view != null;
}

fn present1Windows(
    context: ?*anyopaque,
    sync_interval: u32,
    present_flags: u32,
    parameters_present: bool,
    dirty_rect: ?*const Rect,
) callconv(.c) u32 {
    if (comptime builtin.os.tag != .windows) unreachable;
    if (!parameters_present) unreachable;
    const windows_context: *const WindowsAcquireContext = @ptrCast(@alignCast(context.?));
    const swap_chain: *api.dxgi.IDXGISwapChain1 = @ptrCast(@alignCast(windows_context.swap_chain_handle));
    var native_rect: api.foundation.RECT = undefined;
    const native_dirty_rect: ?*api.foundation.RECT = if (dirty_rect) |rect| blk: {
        native_rect = .{
            .left = rect.left,
            .top = rect.top,
            .right = rect.right,
            .bottom = rect.bottom,
        };
        break :blk &native_rect;
    } else null;
    var parameters = api.dxgi.DXGI_PRESENT_PARAMETERS{
        .DirtyRectsCount = if (native_dirty_rect == null) 0 else 1,
        .pDirtyRects = native_dirty_rect,
        .pScrollRect = null,
        .pScrollOffset = null,
    };
    return @bitCast(swap_chain.Present1(sync_interval, present_flags, &parameters));
}

fn resizeBuffersWindows(
    context: ?*anyopaque,
    width: u32,
    height: u32,
) callconv(.c) u32 {
    if (comptime builtin.os.tag != .windows) unreachable;
    const windows_context: *const WindowsAcquireContext = @ptrCast(@alignCast(context.?));
    const swap_chain: *api.dxgi.IDXGISwapChain1 = @ptrCast(@alignCast(windows_context.swap_chain_handle));
    const result: u32 = @bitCast(swap_chain.IDXGISwapChain.ResizeBuffers(
        admitted_buffer_count,
        width,
        height,
        api.dxgi.common.DXGI_FORMAT_UNKNOWN,
        graphics.swap_chain_flags.frame_latency_waitable_object,
    ));
    return result;
}

fn renderClearWindows(
    _: ?*anyopaque,
    context_handle: *anyopaque,
    render_target_view: *anyopaque,
    request: *const RenderRequest,
) callconv(.c) bool {
    if (comptime builtin.os.tag != .windows) unreachable;
    const immediate_context: *api.d3d11.ID3D11DeviceContext = @ptrCast(@alignCast(context_handle));
    const target_view: *api.d3d11.ID3D11RenderTargetView = @ptrCast(@alignCast(render_target_view));
    var target_view_array: ?*api.d3d11.ID3D11RenderTargetView = target_view;
    immediate_context.OMSetRenderTargets(1, @ptrCast(&target_view_array), null);
    const viewport = api.d3d11.D3D11_VIEWPORT{
        .TopLeftX = 0.0,
        .TopLeftY = 0.0,
        .Width = @floatFromInt(request.width),
        .Height = @floatFromInt(request.height),
        .MinDepth = 0.0,
        .MaxDepth = 1.0,
    };
    immediate_context.RSSetViewports(1, @ptrCast(&viewport));
    immediate_context.ClearRenderTargetView(target_view, &request.clear_color[0]);
    return true;
}

fn acquireBackBufferWindowsFromContext(
    context: ?*anyopaque,
    buffer_index: u32,
) BackBufferError!BackBuffer {
    if (comptime builtin.os.tag != .windows) return error.UnsupportedTarget;
    const windows_context: *const WindowsAcquireContext = @ptrCast(@alignCast(context.?));
    const swap_chain: *api.dxgi.IDXGISwapChain1 = @ptrCast(@alignCast(windows_context.swap_chain_handle));
    return acquireBackBufferWindows(windows_context.device_handle, swap_chain, buffer_index);
}

fn acquireBackBufferWindows(
    device_handle: *anyopaque,
    swap_chain: *api.dxgi.IDXGISwapChain1,
    buffer_index: u32,
) BackBufferError!BackBuffer {
    var windows_context = WindowsAcquireContext{
        .device_handle = device_handle,
        .swap_chain_handle = @ptrCast(swap_chain),
    };
    return acquireBackBufferWithImpl(
        device_handle,
        @ptrCast(swap_chain),
        buffer_index,
        @ptrCast(api.d3d11.IID_ID3D11Resource),
        .{
            .get_buffer = getBufferWindows,
            .create_render_target_view = createRenderTargetViewWindows,
            .release = releaseBackBufferInterface,
        },
        @ptrCast(&windows_context),
    );
}

/// Test-build-only access to wait, ownership, Present1, resize, and unbind
/// seams. Production callers use the corresponding `SwapChain` methods; this
/// export is an empty struct in non-test builds.
pub const testing = if (builtin.is_test) struct {
    pub const ReleaseKind = BackBufferReleaseKind;
    pub const Backend = BackBufferBackend;
    pub const PresentBackend = PresentBackendImpl;
    pub const ResizeBackend = ResizeBackendImpl;
    pub const RenderBackend = RenderBackendImpl;
    pub const acquireBackBufferWith = acquireBackBufferWithImpl;
    pub const deinitBackBufferWith = deinitBackBufferWithImpl;
    pub const present1With = present1WithImpl;
    pub const presentAndRebindWith = presentAndRebindWithImpl;
    pub const resizeAndRebindWith = resizeAndRebindWithImpl;
    pub const renderClearWith = renderClearWithImpl;
    pub const waitForFrameWith = waitForFrameWithImpl;
} else struct {};

pub fn create(device: ?*const graphics.Device, hwnd: ?*anyopaque, effect: graphics.SwapEffect) !SwapChain {
    if (builtin.os.tag != .windows) return error.UnsupportedTarget;
    const admitted = nativeDescriptor(effect);
    if (device == null or hwnd == null) return error.InvalidArgument;
    try graphics.validateSwapChainDescriptor(.{
        .width = admitted.Width,
        .height = admitted.Height,
        .format = .bgra8_unorm,
        .sample_count = admitted.SampleDesc.Count,
        .sample_quality = admitted.SampleDesc.Quality,
        .buffer_usage = admitted.BufferUsage,
        .buffer_count = admitted.BufferCount,
        .scaling = .stretch,
        .effect = effect,
        .alpha_mode = .unspecified,
        .flags = admitted.Flags,
    });
    return createWindows(device.?, hwnd.?, admitted, effect);
}

fn createWindows(
    device: *const graphics.Device,
    hwnd: *anyopaque,
    descriptor: NativeDescriptor,
    effect: graphics.SwapEffect,
) !SwapChain {
    const device_handle = device.deviceHandle() orelse return error.InvalidDevice;
    var factory_raw: ?*anyopaque = null;
    const factory_result = api.dxgi_dll.CreateDXGIFactory2(
        0,
        api.dxgi.IID_IDXGIFactory2,
        @ptrCast(&factory_raw),
    );
    if (factory_result.failed or factory_raw == null) return error.FactoryCreationFailed;
    const factory: *api.dxgi.IDXGIFactory2 = @ptrCast(@alignCast(factory_raw.?));
    defer _ = factory.IUnknown.Release();

    const native = toApiDescriptor(descriptor);
    var swap_chain1: ?*api.dxgi.IDXGISwapChain1 = null;
    const create_result = factory.CreateSwapChainForHwnd(
        @ptrCast(@alignCast(device_handle)),
        @ptrCast(hwnd),
        &native,
        null,
        null,
        @ptrCast(&swap_chain1),
    );
    if (create_result.failed or swap_chain1 == null) return error.SwapChainCreationFailed;
    errdefer _ = swap_chain1.?.IUnknown.Release();

    var swap_chain2_raw: ?*anyopaque = null;
    const query_result = swap_chain1.?.IUnknown.QueryInterface(
        api.dxgi.IID_IDXGISwapChain2,
        @ptrCast(&swap_chain2_raw),
    );
    if (query_result.failed or swap_chain2_raw == null) return error.SwapChainInterfaceUnavailable;
    const swap_chain2: *api.dxgi.IDXGISwapChain2 = @ptrCast(@alignCast(swap_chain2_raw.?));
    errdefer _ = swap_chain2.IUnknown.Release();

    if (swap_chain2.SetMaximumFrameLatency(graphics.max_frame_latency).failed) return error.FrameLatencyConfigurationFailed;
    var actual_frame_latency: u32 = 0;
    if (swap_chain2.GetMaximumFrameLatency(&actual_frame_latency).failed or
        actual_frame_latency != graphics.max_frame_latency)
    {
        return error.FrameLatencyConfigurationFailed;
    }
    const waitable = swap_chain2.GetFrameLatencyWaitableObject() orelse return error.FrameLatencyHandleUnavailable;

    return .{
        .effect = effect,
        .maximum_frame_latency = actual_frame_latency,
        .swap_chain1 = swap_chain1,
        .swap_chain2 = swap_chain2,
        .waitable = waitable,
    };
}

fn toApiDescriptor(descriptor: NativeDescriptor) api.dxgi.DXGI_SWAP_CHAIN_DESC1 {
    return .{
        .Width = descriptor.Width,
        .Height = descriptor.Height,
        .Format = @enumFromInt(@intFromEnum(descriptor.Format)),
        .Stereo = @intCast(descriptor.Stereo),
        .SampleDesc = .{
            .Count = descriptor.SampleDesc.Count,
            .Quality = descriptor.SampleDesc.Quality,
        },
        .BufferUsage = @bitCast(descriptor.BufferUsage),
        .BufferCount = descriptor.BufferCount,
        .Scaling = @enumFromInt(@intFromEnum(descriptor.Scaling)),
        .SwapEffect = @enumFromInt(@intFromEnum(descriptor.SwapEffect)),
        .AlphaMode = @enumFromInt(@intFromEnum(descriptor.AlphaMode)),
        .Flags = descriptor.Flags,
    };
}
