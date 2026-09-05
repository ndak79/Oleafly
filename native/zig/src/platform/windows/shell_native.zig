//! Narrow x64 Windows UI adapter. Declarations match the Win32 SDK's pointer,
//! DWORD/BOOL/HRESULT and callback ABI; no generated "everything" binding.
//! Entry-time DLL policy governs subsequent loads, not the OS's pre-entry image
//! loader. Resource and manifest identity are supplied by the product build;
//! this adapter owns only the first native render bridge, not worker, database
//! or network seams.
const std = @import("std");
const shell = @import("windows_shell");
const com = @import("windows_com");
const entry = @import("ui_entry");
const role = @import("app_role");
const graphics = @import("graphics");
const presenter = @import("presenter_native");

pub const HINSTANCE = *opaque {};
pub const HWND = *opaque {};
pub const WNDPROC = *const fn (HWND, u32, usize, isize) callconv(.winapi) isize;
pub const WNDCLASSEXW = extern struct {
    cbSize: u32,
    style: u32,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: HINSTANCE,
    hIcon: ?*anyopaque,
    hCursor: ?*anyopaque,
    hbrBackground: ?*anyopaque,
    lpszMenuName: ?[*:0]const u16,
    lpszClassName: [*:0]const u16,
    hIconSm: ?*anyopaque,
};
pub const MSG = extern struct {
    hwnd: ?HWND,
    message: u32,
    wParam: usize,
    lParam: isize,
    time: u32,
    pt: extern struct { x: i32, y: i32 },
};
pub const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};
pub const CREATESTRUCTW = extern struct {
    lpCreateParams: ?*anyopaque,
    hInstance: HINSTANCE,
    hMenu: ?*anyopaque,
    hwndParent: ?HWND,
    cy: i32,
    cx: i32,
    y: i32,
    x: i32,
    style: i32,
    lpszName: [*:0]const u16,
    lpszClass: [*:0]const u16,
    dwExStyle: u32,
};

pub const dll_search_flags: u32 = 0x800; // LOAD_LIBRARY_SEARCH_SYSTEM32
pub const window_style: u32 = 0xcf0000; // WS_OVERLAPPEDWINDOW, system caption
pub const dpi_pmv2: *anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -4))));
pub const frame_timer_id: usize = 1;
pub const frame_timer_period_ms: u32 = 16;
const wm_nccreate: u32 = 0x0081;
const wm_ncdestroy: u32 = 0x0082;
const wm_destroy: u32 = 0x0002;
const wm_size: u32 = 0x0005;
const wm_paint: u32 = 0x000f;
const wm_timer: u32 = 0x0113;
const size_minimized: usize = 1;
const gwlp_userdata: i32 = -21;
const class_name = std.unicode.utf8ToUtf16LeStringLiteral(role.ui_identity.machine_class);
const window_title = std.unicode.utf8ToUtf16LeStringLiteral(role.ui_identity.product_name);

pub fn renderOutcomeUsable(outcome: presenter.PresentOutcome) bool {
    return outcome == .presented or outcome == .occluded;
}

pub fn isPaintMessage(message: u32) bool {
    return message == wm_paint;
}

pub fn isResizeMessage(message: u32) bool {
    return message == wm_size;
}

pub fn isFrameTimerMessage(message: u32, timer_id: usize) bool {
    return message == wm_timer and timer_id == frame_timer_id;
}

const raw = struct {
    extern "kernel32" fn GetCommandLineW() callconv(.winapi) [*:0]const u16;
    extern "kernel32" fn LocalFree(?*anyopaque) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn SetDefaultDllDirectories(u32) callconv(.winapi) i32;
    extern "shell32" fn CommandLineToArgvW([*:0]const u16, *i32) callconv(.winapi) ?[*][*:0]u16;
    extern "bcrypt" fn BCryptGenRandom(?*anyopaque, [*]u8, u32, u32) callconv(.winapi) i32;
    extern "user32" fn SetProcessDpiAwarenessContext(*anyopaque) callconv(.winapi) i32;
    extern "user32" fn GetThreadDpiAwarenessContext() callconv(.winapi) ?*anyopaque;
    extern "user32" fn AreDpiAwarenessContextsEqual(?*anyopaque, ?*anyopaque) callconv(.winapi) i32;
    extern "user32" fn LoadCursorW(?HINSTANCE, [*:0]const u16) callconv(.winapi) ?*anyopaque;
    extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.winapi) u16;
    extern "user32" fn UnregisterClassW([*:0]const u16, HINSTANCE) callconv(.winapi) i32;
    extern "user32" fn CreateWindowExW(u32, [*:0]const u16, [*:0]const u16, u32, i32, i32, i32, i32, ?HWND, ?*anyopaque, HINSTANCE, ?*anyopaque) callconv(.winapi) ?HWND;
    extern "user32" fn ShowWindow(HWND, i32) callconv(.winapi) i32;
    extern "user32" fn SetTimer(HWND, usize, u32, ?*anyopaque) callconv(.winapi) usize;
    extern "user32" fn KillTimer(HWND, usize) callconv(.winapi) i32;
    extern "user32" fn SetWindowLongPtrW(HWND, i32, isize) callconv(.winapi) isize;
    extern "user32" fn GetWindowLongPtrW(HWND, i32) callconv(.winapi) isize;
    extern "user32" fn ValidateRect(HWND, ?*const RECT) callconv(.winapi) i32;
    extern "user32" fn IsWindow(HWND) callconv(.winapi) i32;
    extern "user32" fn DestroyWindow(HWND) callconv(.winapi) i32;
    extern "user32" fn GetClientRect(HWND, *RECT) callconv(.winapi) i32;
    extern "user32" fn GetMessageW(*MSG, ?HWND, u32, u32) callconv(.winapi) i32;
    extern "user32" fn TranslateMessage(*const MSG) callconv(.winapi) i32;
    extern "user32" fn DispatchMessageW(*const MSG) callconv(.winapi) isize;
    extern "user32" fn DefWindowProcW(HWND, u32, usize, isize) callconv(.winapi) isize;
    extern "user32" fn PostQuitMessage(i32) callconv(.winapi) void;
};

pub fn launch(instance: HINSTANCE, show: i32) shell.Result {
    var backend: Backend = .{ .instance = instance, .show = show };
    return runCommandLine(std.heap.page_allocator, raw.GetCommandLineW(), &backend);
}

/// The Windows API reports PMv2 as a special opaque context.  Keep the
/// acceptance rule pure so tests can falsify null/unknown/PMv1 paths without
/// loading user32: only a non-null context proven equal by the OS is accepted.
pub fn acceptPmv2Context(current: ?*anyopaque, equal_to_pmv2: bool) bool {
    return current != null and equal_to_pmv2;
}

/// Uses the complete OS command line, not a presumed wWinMain tail: Zig 0.16's
/// startup passes the PEB's full string. argv[0] is explicitly excluded.
/// The native parser owns one LocalFree block; shell.run owns temporary UTF-8.
/// https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-commandlinetoargvw
pub fn runCommandLine(allocator: std.mem.Allocator, command_line: [*:0]const u16, backend: anytype) shell.Result {
    const text = std.mem.span(command_line);
    if (text.len == 0 or text.len > 32766) return .{ .code = .command_line_failed };
    var codepoints = std.unicode.Utf16LeIterator.init(text);
    while (codepoints.nextCodepoint() catch return .{ .code = .command_line_failed }) |_| {}
    var count: i32 = 0;
    const parsed = raw.CommandLineToArgvW(command_line, &count) orelse return .{ .code = .command_line_failed };
    defer _ = raw.LocalFree(@ptrCast(parsed));
    if (count < 1 or parsed[0][0] == 0) return .{ .code = .command_line_failed };
    const arguments: [*]const [*:0]const u16 = @ptrCast(parsed);
    return shell.run(allocator, arguments[1..@intCast(count)], .{ .context = null, .fill = secureEntropy }, backend);
}

fn secureEntropy(_: ?*anyopaque, bytes: []u8) std.Io.RandomSecureError!void {
    // BCRYPT_USE_SYSTEM_PREFERRED_RNG requires a null provider. Admission asks
    // once for exactly 16 bytes; errors have no weak/random/clock fallback.
    // https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptgenrandom
    if (bytes.len != 16 or raw.BCryptGenRandom(null, bytes.ptr, 16, 2) != 0) return error.EntropyUnavailable;
}

pub const Backend = struct {
    instance: HINSTANCE,
    show: i32,
    window: ?HWND = null,
    graphics_device: ?graphics.Device = null,
    swap_chain: ?presenter.SwapChain = null,
    back_buffer: ?presenter.BackBuffer = null,
    frame_timer: usize = 0,
    message: MSG = undefined,

    pub const initial_clear_color: [4]f32 = .{ 0.035, 0.055, 0.09, 1.0 };

    pub fn restrictDllSearch(_: *Backend) bool {
        // No application/CWD/PATH/user-added directory is admitted in this slice.
        return raw.SetDefaultDllDirectories(dll_search_flags) != 0;
    }
    pub fn setDpiAwareness(_: *Backend) bool {
        // A PMv2 manifest establishes the process context before entry.  In
        // that case SetProcessDpiAwarenessContext may report access denied;
        // query the effective thread context and accept only exact PMv2.
        const before = raw.GetThreadDpiAwarenessContext();
        if (before) |context| {
            if (acceptPmv2Context(context, raw.AreDpiAwarenessContextsEqual(context, dpi_pmv2) != 0)) return true;
        } else return false;
        _ = raw.SetProcessDpiAwarenessContext(dpi_pmv2);
        const after = raw.GetThreadDpiAwarenessContext();
        if (after) |context| return acceptPmv2Context(context, raw.AreDpiAwarenessContextsEqual(context, dpi_pmv2) != 0);
        return false;
    }
    pub fn initializeCom(_: *Backend) bool {
        return com.initializeSta();
    }
    pub fn uninitializeCom(_: *Backend) void {
        com.uninitialize();
    }
    pub fn registerClass(self: *Backend) bool {
        const cursor = raw.LoadCursorW(null, @ptrFromInt(32512)) orelse return false; // IDC_ARROW, shared
        const window_class: WNDCLASSEXW = .{
            .cbSize = @sizeOf(WNDCLASSEXW),
            .style = 3, // CS_HREDRAW | CS_VREDRAW
            .lpfnWndProc = windowProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = self.instance,
            .hIcon = null,
            .hCursor = cursor,
            .hbrBackground = @ptrFromInt(6), // COLOR_WINDOW + 1; system-owned
            .lpszMenuName = null,
            .lpszClassName = class_name,
            .hIconSm = null,
        };
        return raw.RegisterClassExW(&window_class) != 0;
    }
    pub fn unregisterClass(self: *Backend) bool {
        return raw.UnregisterClassW(class_name, self.instance) != 0;
    }
    pub fn createWindow(self: *Backend) bool {
        const use_default = std.math.minInt(i32); // CW_USEDEFAULT
        self.window = raw.CreateWindowExW(0, class_name, window_title, window_style, use_default, use_default, 960, 640, null, null, self.instance, @ptrCast(self));
        if (self.window == null) return false;
        var device = graphics.Device.create() catch {
            // A visible window without a render device is not an admitted UI
            // state.  Tear it down immediately so callers cannot observe a
            // half-initialized shell or accidentally fall back to GDI.
            _ = raw.DestroyWindow(self.window.?);
            self.window = null;
            return false;
        };
        var swap_chain = presenter.create(&device, @ptrCast(self.window.?), .flip_discard) catch {
            device.deinit();
            _ = raw.DestroyWindow(self.window.?);
            self.window = null;
            return false;
        };
        const back_buffer = swap_chain.acquireBackBuffer(&device, 0) catch {
            swap_chain.deinit();
            device.deinit();
            _ = raw.DestroyWindow(self.window.?);
            self.window = null;
            return false;
        };
        self.graphics_device = device;
        self.swap_chain = swap_chain;
        self.back_buffer = back_buffer;
        if (!self.renderFrame()) {
            self.releaseFrameResources();
            _ = raw.DestroyWindow(self.window.?);
            self.window = null;
            return false;
        }
        return true;
    }

    /// The first-frame bridge is synchronous: a hidden window receives a
    /// complete clear + Present before it becomes visible, so the shell never
    /// exposes an uninitialized back buffer.
    pub fn renderFrame(self: *Backend) bool {
        const window = self.window orelse return false;
        var client: RECT = undefined;
        if (raw.GetClientRect(window, &client) == 0) return false;
        const width_i = client.right - client.left;
        const height_i = client.bottom - client.top;
        if (width_i <= 0 or height_i <= 0) return false;
        const width: u32 = @intCast(width_i);
        const height: u32 = @intCast(height_i);
        if (self.graphics_device) |*device| {
            if (self.swap_chain) |*swap_chain| {
                if (self.back_buffer) |*buffer| {
                    _ = swap_chain.renderClear(device, buffer, .{
                        .width = width,
                        .height = height,
                        .clear_color = Backend.initial_clear_color,
                    }) catch return false;
                    const outcome = swap_chain.presentAndRebind(device, buffer, .{}) catch return false;
                    return renderOutcomeUsable(outcome);
                }
            }
        }
        return false;
    }

    pub fn hasFrameResources(self: *const Backend) bool {
        return self.graphics_device != null and self.swap_chain != null and self.back_buffer != null;
    }

    pub fn tickFrame(self: *Backend) bool {
        if (self.swap_chain) |*swap_chain| {
            const wait = swap_chain.waitForFrame(0) catch return false;
            return switch (wait) {
                .signaled => self.renderFrame(),
                .timeout => true,
            };
        }
        return false;
    }

    pub fn resizeFrame(self: *Backend, width: u32, height: u32) bool {
        if (width == 0 or height == 0) return false;
        if (self.graphics_device) |*device| {
            if (self.swap_chain) |*swap_chain| {
                if (self.back_buffer) |*buffer| {
                    const outcome = swap_chain.resizeAndRebind(device, buffer, .{
                        .width = width,
                        .height = height,
                    }) catch return false;
                    return switch (outcome) {
                        .resized => self.renderFrame(),
                        .device_removed, .device_reset, .device_hung => false,
                    };
                }
            }
        }
        return false;
    }

    pub fn frameTimerActive(self: *const Backend) bool {
        return self.frame_timer != 0;
    }

    fn releaseFrameResources(self: *Backend) void {
        if (self.back_buffer) |*buffer| {
            buffer.deinit();
            self.back_buffer = null;
        }
        if (self.swap_chain) |*swap_chain| {
            swap_chain.deinit();
            self.swap_chain = null;
        }
        if (self.graphics_device) |*device| {
            device.deinit();
            self.graphics_device = null;
        }
    }

    pub fn destroyWindow(self: *Backend) bool {
        if (self.frame_timer != 0) {
            if (self.window) |window| _ = raw.KillTimer(window, frame_timer_id);
            self.frame_timer = 0;
        }
        self.releaseFrameResources();
        const window = self.window orelse return true;
        // DefWindowProc handles WM_CLOSE and may already have destroyed it.
        if (raw.IsWindow(window) != 0 and raw.DestroyWindow(window) == 0) return false;
        self.window = null;
        return true;
    }
    pub fn showWindow(self: *Backend) void {
        // ShowWindow's return reports previous visibility, not success/failure.
        _ = raw.ShowWindow(self.window.?, self.show);
        self.frame_timer = raw.SetTimer(self.window.?, frame_timer_id, frame_timer_period_ms, null);
    }
    pub fn getMessage(self: *Backend) i32 {
        // No HWND filter: WM_QUIT remains valid after the main HWND is gone.
        // The portable loop distinguishes -1 (error), 0 (quit), >0 (dispatch).
        return raw.GetMessageW(&self.message, null, 0, 0);
    }
    pub fn dispatchMessage(self: *Backend) void {
        _ = raw.TranslateMessage(&self.message);
        _ = raw.DispatchMessageW(&self.message);
    }
};

fn backendForWindow(window: HWND) ?*Backend {
    const stored = raw.GetWindowLongPtrW(window, gwlp_userdata);
    if (stored == 0) return null;
    return @ptrFromInt(@as(usize, @bitCast(stored)));
}

fn windowProc(window: HWND, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
    if (message == wm_nccreate) {
        if (lparam == 0) return 0;
        const create: *const CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
        const backend = create.lpCreateParams orelse return 0;
        _ = raw.SetWindowLongPtrW(window, gwlp_userdata, @as(isize, @bitCast(@intFromPtr(backend))));
        return 1;
    }
    if (message == wm_paint) {
        if (backendForWindow(window)) |backend| {
            _ = raw.ValidateRect(window, null);
            _ = backend.tickFrame();
            return 0;
        }
    }
    if (message == wm_size) {
        if (wparam != size_minimized) {
            if (backendForWindow(window)) |backend| {
                if (backend.hasFrameResources()) {
                    const size_bits: usize = @as(usize, @bitCast(lparam));
                    const width: u32 = @intCast(size_bits & 0xffff);
                    const height: u32 = @intCast((size_bits >> 16) & 0xffff);
                    if (width != 0 and height != 0) _ = backend.resizeFrame(width, height);
                    return 0;
                }
            }
        }
    }
    if (message == wm_timer and isFrameTimerMessage(message, wparam)) {
        if (backendForWindow(window)) |backend| {
            _ = backend.tickFrame();
            return 0;
        }
    }
    if (message == wm_destroy) {
        raw.PostQuitMessage(0);
        return 0;
    }
    if (message == wm_ncdestroy) {
        _ = raw.SetWindowLongPtrW(window, gwlp_userdata, 0);
    }
    return raw.DefWindowProcW(window, message, wparam, lparam);
}
