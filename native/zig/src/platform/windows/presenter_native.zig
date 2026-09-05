//! Minimal native DXGI binding for the admitted TExFlow HWND presenter.
//!
//! The policy/state machine lives in `presenter.zig`; this adapter owns only
//! the COM interfaces and the DXGI frame-latency handle. It deliberately
//! stops at the creation/lifetime boundary: no Present1/ResizeBuffers entry
//! point is exposed until a later slice owns render-target references,
//! wait-before-draw, rebind, HRESULT mapping, and device-loss recovery.
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
        .BufferCount = 2,
        .Scaling = .stretch,
        .SwapEffect = switch (effect) {
            .flip_sequential => .flip_sequential,
            .flip_discard => .flip_discard,
        },
        .AlphaMode = .unspecified,
        .Flags = graphics.swap_chain_flags.frame_latency_waitable_object,
    };
}

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
