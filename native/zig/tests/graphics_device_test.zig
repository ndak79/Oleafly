const builtin = @import("builtin");
const std = @import("std");
const graphics = @import("graphics");

test "flip-sequential descriptor is the conservative waitable baseline" {
    const descriptor = graphics.swapChainDescriptor(.flip_sequential);
    try std.testing.expectEqual(@as(u32, 0), descriptor.width);
    try std.testing.expectEqual(@as(u32, 0), descriptor.height);
    try std.testing.expectEqual(graphics.PixelFormat.bgra8_unorm, descriptor.format);
    try std.testing.expectEqual(@as(u32, 1), descriptor.sample_count);
    try std.testing.expectEqual(@as(u32, 0), descriptor.sample_quality);
    try std.testing.expectEqual(@as(u32, 0x20), descriptor.buffer_usage);
    try std.testing.expectEqual(@as(u32, 2), descriptor.buffer_count);
    try std.testing.expectEqual(graphics.Scaling.stretch, descriptor.scaling);
    try std.testing.expectEqual(graphics.SwapEffect.flip_sequential, descriptor.effect);
    try std.testing.expectEqual(graphics.AlphaMode.unspecified, descriptor.alpha_mode);
    try std.testing.expectEqual(graphics.swap_chain_flags.frame_latency_waitable_object, descriptor.flags);
    try std.testing.expectEqual(@as(u32, 1), graphics.max_frame_latency);
    try graphics.validateSwapChainDescriptor(descriptor);
}

test "flip-discard challenger is full-redraw but remains waitable" {
    const descriptor = graphics.swapChainDescriptor(.flip_discard);
    try std.testing.expectEqual(graphics.SwapEffect.flip_discard, descriptor.effect);
    try std.testing.expectEqual(graphics.swap_chain_flags.frame_latency_waitable_object, descriptor.flags);
    try graphics.validateSwapChainDescriptor(descriptor);
    try std.testing.expect(graphics.requiresFullRedraw(descriptor));
}

test "pinned zigwin32 graphics ABI matches the x64 SDK contract" {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    const api = graphics.bindings;
    try std.testing.expectEqual(@as(u32, 7), api.d3d11.D3D11_SDK_VERSION);
    try std.testing.expectEqual(@as(u32, 0x20), @as(u32, @bitCast(api.d3d11.D3D11_CREATE_DEVICE_BGRA_SUPPORT)));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(api.dxgi.DXGI_SWAP_CHAIN_DESC1));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(api.dxgi.DXGI_SWAP_CHAIN_DESC1, "Width"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(api.dxgi.DXGI_SWAP_CHAIN_DESC1, "SampleDesc"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(api.dxgi.DXGI_SWAP_CHAIN_DESC1, "BufferUsage"));
    try std.testing.expectEqual(@as(usize, 28), @offsetOf(api.dxgi.DXGI_SWAP_CHAIN_DESC1, "BufferCount"));
    try std.testing.expectEqual(@as(usize, 36), @offsetOf(api.dxgi.DXGI_SWAP_CHAIN_DESC1, "SwapEffect"));
    try std.testing.expectEqual(@as(usize, 44), @offsetOf(api.dxgi.DXGI_SWAP_CHAIN_DESC1, "Flags"));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(api.d3d11.ID3D11Device));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(api.d3d11.ID3D11DeviceContext));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(api.com.IUnknown));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(@TypeOf(api.d3d11.IID_ID3D11Device.*)));
    try std.testing.expectEqual(@as(u8, 0xdb), api.d3d11.IID_ID3D11Device.*.Bytes[0]);
    try std.testing.expect(@hasDecl(api.d3d11.ID3D11Device, "GetFeatureLevel"));
    try std.testing.expect(@hasField(api.dxgi.IDXGIFactory2.VTable, "CreateSwapChainForHwnd"));
    try std.testing.expect(@hasField(api.dxgi.IDXGISwapChain2.VTable, "SetMaximumFrameLatency"));
}

test "swap-chain validator rejects unsafe or incoherent metadata" {
    const baseline = graphics.swapChainDescriptor(.flip_sequential);
    const mutants = [_]graphics.SwapChainDescriptor{
        baseline.with(.{ .width = 1 }),
        baseline.with(.{ .height = 1 }),
        baseline.with(.{ .format = .rgba8_unorm }),
        baseline.with(.{ .sample_count = 4 }),
        baseline.with(.{ .sample_quality = 1 }),
        baseline.with(.{ .buffer_usage = 0 }),
        baseline.with(.{ .buffer_count = 1 }),
        baseline.with(.{ .scaling = .none }),
        baseline.with(.{ .effect = .flip_discard, .flags = 0 }),
        baseline.with(.{ .alpha_mode = .premultiplied }),
        baseline.with(.{ .flags = 0 }),
        baseline.with(.{ .flags = graphics.swap_chain_flags.frame_latency_waitable_object | 0x8000 }),
    };
    for (mutants) |mutant| {
        try std.testing.expectError(error.InvalidSwapChainDescriptor, graphics.validateSwapChainDescriptor(mutant));
    }
}

test "device admission rejects below-floor hardware and accepts the minimum" {
    try std.testing.expectEqual(@as(u32, 0xa000), graphics.minimum_feature_level);
    try std.testing.expect(!graphics.admitsFeatureLevel(@as(i32, @intCast(@intFromEnum(graphics.FeatureLevel.level_9_3)))));
    try std.testing.expect(graphics.admitsFeatureLevel(@as(i32, @intCast(@intFromEnum(graphics.FeatureLevel.level_10_0)))));
    try std.testing.expect(graphics.admitsFeatureLevel(@as(i32, @intCast(@intFromEnum(graphics.FeatureLevel.level_11_0)))));
}

test "device creation is a real hardware-or-WARP D3D11 admission" {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    var device = try graphics.Device.create();
    defer device.deinit();
    try std.testing.expect(device.path == .hardware or device.path == .warp);
    try std.testing.expect(device.feature_level >= @intFromEnum(graphics.FeatureLevel.level_10_0));
    try std.testing.expect(device.deviceHandle() != null);
    try std.testing.expect(device.contextHandle() != null);
}

test "device creation remains explicitly unsupported on non-Windows targets" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    try std.testing.expectError(error.UnsupportedTarget, graphics.Device.create());
}
