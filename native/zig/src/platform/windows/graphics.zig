//! Native graphics admission surface for the TExFlow UI.
//!
//! This device-admission module owns the real D3D11 device on Windows
//! (hardware first, WARP fallback) and its COM releases.  The separate
//! `presenter_native.zig` adapter binds the admitted HWND swap-chain
//! descriptor, waitable frame handle, back-buffer/RTV owner, and minimal clear
//! path; D2D/DWrite composition and device-loss recovery remain later slices.
const builtin = @import("builtin");
const api = @import("windows_api");

/// Tests and later native adapters consume only this curated facade, never the
/// generated package directly.
pub const bindings = api;

pub const max_frame_latency: u32 = 1;

pub const DevicePath = enum { hardware, warp };
pub const FeatureLevel = enum(u32) {
    level_9_3 = 0x9300,
    level_10_0 = 0xa000,
    level_10_1 = 0xa100,
    level_11_0 = 0xb000,
};

/// The native presenter needs at least the D3D10 feature contract for its
/// BGRA render-target and Direct2D interop path.  Lower feature levels are
/// deliberately rejected even when the runtime could create them.
pub const minimum_feature_level: u32 = @intFromEnum(FeatureLevel.level_10_0);

pub const PixelFormat = enum(u32) {
    rgba8_unorm = 28,
    bgra8_unorm = 87,
};

pub const Scaling = enum(u32) {
    stretch = 0,
    none = 1,
};

pub const SwapEffect = enum(u32) {
    flip_sequential = 3,
    flip_discard = 4,
};

pub const AlphaMode = enum(u32) {
    unspecified = 0,
    premultiplied = 1,
};

pub const swap_chain_flags = struct {
    pub const frame_latency_waitable_object: u32 = 0x40;
};

/// This is the small, ABI-neutral subset consumed by the presenter adapter.
/// Width/height zero intentionally means “size from the HWND”.
pub const SwapChainDescriptor = struct {
    width: u32,
    height: u32,
    format: PixelFormat,
    sample_count: u32,
    sample_quality: u32,
    buffer_usage: u32,
    buffer_count: u32,
    scaling: Scaling,
    effect: SwapEffect,
    alpha_mode: AlphaMode,
    flags: u32,

    pub const Patch = struct {
        width: ?u32 = null,
        height: ?u32 = null,
        format: ?PixelFormat = null,
        sample_count: ?u32 = null,
        sample_quality: ?u32 = null,
        buffer_usage: ?u32 = null,
        buffer_count: ?u32 = null,
        scaling: ?Scaling = null,
        effect: ?SwapEffect = null,
        alpha_mode: ?AlphaMode = null,
        flags: ?u32 = null,
    };

    pub fn with(self: SwapChainDescriptor, patch: Patch) SwapChainDescriptor {
        var value = self;
        if (patch.width) |field| value.width = field;
        if (patch.height) |field| value.height = field;
        if (patch.format) |field| value.format = field;
        if (patch.sample_count) |field| value.sample_count = field;
        if (patch.sample_quality) |field| value.sample_quality = field;
        if (patch.buffer_usage) |field| value.buffer_usage = field;
        if (patch.buffer_count) |field| value.buffer_count = field;
        if (patch.scaling) |field| value.scaling = field;
        if (patch.effect) |field| value.effect = field;
        if (patch.alpha_mode) |field| value.alpha_mode = field;
        if (patch.flags) |field| value.flags = field;
        return value;
    }
};

pub fn swapChainDescriptor(effect: SwapEffect) SwapChainDescriptor {
    return .{
        .width = 0,
        .height = 0,
        .format = .bgra8_unorm,
        .sample_count = 1,
        .sample_quality = 0,
        .buffer_usage = 0x20, // DXGI_USAGE_RENDER_TARGET_OUTPUT
        .buffer_count = 2,
        .scaling = .stretch,
        .effect = effect,
        .alpha_mode = .unspecified,
        // Both flip-model challengers participate in the same first/every-
        // frame pacing gate.  FLIP_DISCARD differs only in preservation
        // semantics, so it must remain waitable as well.
        .flags = swap_chain_flags.frame_latency_waitable_object,
    };
}

pub fn validateSwapChainDescriptor(descriptor: SwapChainDescriptor) error{InvalidSwapChainDescriptor}!void {
    if (descriptor.width != 0 or descriptor.height != 0) return error.InvalidSwapChainDescriptor;
    if (descriptor.format != .bgra8_unorm) return error.InvalidSwapChainDescriptor;
    if (descriptor.sample_count != 1 or descriptor.sample_quality != 0) return error.InvalidSwapChainDescriptor;
    if (descriptor.buffer_usage != 0x20 or descriptor.buffer_count != 2) return error.InvalidSwapChainDescriptor;
    if (descriptor.scaling != .stretch or descriptor.alpha_mode != .unspecified) return error.InvalidSwapChainDescriptor;
    if (descriptor.flags != swap_chain_flags.frame_latency_waitable_object) return error.InvalidSwapChainDescriptor;
}

pub fn requiresFullRedraw(descriptor: SwapChainDescriptor) bool {
    return descriptor.effect == .flip_discard;
}

/// Pure admission predicate used by the runtime path and its deterministic
/// below-floor test.  Keep this in the policy layer so a successful API call
/// cannot accidentally bypass the minimum by returning a lower level.
pub fn admitsFeatureLevel(value: i32) bool {
    return value >= @as(i32, @intCast(minimum_feature_level));
}

pub const Device = struct {
    path: DevicePath,
    feature_level: u32,
    device: ?*anyopaque,
    context: ?*anyopaque,

    pub fn create() !Device {
        if (builtin.os.tag != .windows) return error.UnsupportedTarget;
        return createWindows();
    }

    pub fn deviceHandle(self: *const Device) ?*anyopaque {
        return self.device;
    }

    pub fn contextHandle(self: *const Device) ?*anyopaque {
        return self.context;
    }

    pub fn deinit(self: *Device) void {
        if (builtin.os.tag != .windows) {
            self.device = null;
            self.context = null;
            return;
        }
        if (self.context) |handle| {
            const context: *api.d3d11.ID3D11DeviceContext = @ptrCast(@alignCast(handle));
            _ = context.IUnknown.Release();
            self.context = null;
        }
        if (self.device) |handle| {
            const device: *api.d3d11.ID3D11Device = @ptrCast(@alignCast(handle));
            _ = device.IUnknown.Release();
            self.device = null;
        }
    }
};

fn createWindows() !Device {
    const levels = [_]api.direct3d.D3D_FEATURE_LEVEL{
        .@"11_0",
        .@"10_1",
        .@"10_0",
    };
    const flags = api.d3d11.D3D11_CREATE_DEVICE_BGRA_SUPPORT;

    var device: ?*api.d3d11.ID3D11Device = null;
    var context: ?*api.d3d11.ID3D11DeviceContext = null;
    var chosen: api.direct3d.D3D_FEATURE_LEVEL = undefined;

    const hardware_result = api.d3d11_dll.D3D11CreateDevice(
        null,
        .HARDWARE,
        null,
        flags,
        levels[0..].ptr,
        levels.len,
        api.d3d11.D3D11_SDK_VERSION,
        @ptrCast(&device),
        &chosen,
        @ptrCast(&context),
    );
    if (!hardware_result.failed and device != null and context != null and
        admitsNativeFeatureLevel(chosen))
    {
        return .{
            .path = .hardware,
            .feature_level = @intCast(@intFromEnum(chosen)),
            .device = @ptrCast(device.?),
            .context = @ptrCast(context.?),
        };
    }
    releasePartial(&device, &context);

    const warp_result = api.d3d11_dll.D3D11CreateDevice(
        null,
        .WARP,
        null,
        flags,
        levels[0..].ptr,
        levels.len,
        api.d3d11.D3D11_SDK_VERSION,
        @ptrCast(&device),
        &chosen,
        @ptrCast(&context),
    );
    if (!warp_result.failed and device != null and context != null and
        admitsNativeFeatureLevel(chosen))
    {
        return .{
            .path = .warp,
            .feature_level = @intCast(@intFromEnum(chosen)),
            .device = @ptrCast(device.?),
            .context = @ptrCast(context.?),
        };
    }
    releasePartial(&device, &context);
    return error.DeviceCreationFailed;
}

fn admitsNativeFeatureLevel(level: api.direct3d.D3D_FEATURE_LEVEL) bool {
    return admitsFeatureLevel(@intFromEnum(level));
}

fn releasePartial(
    device: *?*api.d3d11.ID3D11Device,
    context: *?*api.d3d11.ID3D11DeviceContext,
) void {
    if (context.*) |value| {
        _ = value.IUnknown.Release();
        context.* = null;
    }
    if (device.*) |value| {
        _ = value.IUnknown.Release();
        device.* = null;
    }
}
