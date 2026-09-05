const builtin = @import("builtin");
const std = @import("std");
const api = @import("windows_api");
const graphics = @import("graphics");
const native = @import("presenter_native");

test "frame-latency wait mapping preserves each Win32 result class" {
    // WAIT_OBJECT_0 and WAIT_ABANDONED_0 are aliases for the same values as
    // NO_ERROR and WAIT_ABANDONED respectively in the curated facade.
    try std.testing.expectEqual(native.WaitOutcome.signaled, try native.mapWaitResult(0));
    try std.testing.expectEqual(native.WaitOutcome.timeout, try native.mapWaitResult(258));
    try std.testing.expectError(error.FrameLatencyWaitAbandoned, native.mapWaitResult(128));
    try std.testing.expectError(error.FrameLatencyWaitFailed, native.mapWaitResult(std.math.maxInt(u32)));
    try std.testing.expectError(error.UnexpectedFrameLatencyWaitResult, native.mapWaitResult(1));
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

test "native swap chain is unsupported outside Windows" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var chain: native.SwapChain = undefined;
    try std.testing.expectError(error.UnsupportedTarget, chain.waitForFrame(0));
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
