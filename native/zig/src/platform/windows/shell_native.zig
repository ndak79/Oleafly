//! Narrow x64 Windows UI adapter. Declarations match the Win32 SDK's pointer,
//! DWORD/BOOL/HRESULT and callback ABI; no generated "everything" binding.
//! Entry-time DLL policy governs subsequent loads, not the OS's pre-entry image
//! loader. Resource and manifest identity are supplied by the product build;
//! this adapter owns no renderer, worker, database or network seams.
const std = @import("std");
const shell = @import("windows_shell");
const com = @import("windows_com");
const entry = @import("ui_entry");
const role = @import("app_role");
const graphics = @import("graphics");

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

pub const dll_search_flags: u32 = 0x800; // LOAD_LIBRARY_SEARCH_SYSTEM32
pub const window_style: u32 = 0xcf0000; // WS_OVERLAPPEDWINDOW, system caption
pub const dpi_pmv2: *anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -4))));
const class_name = std.unicode.utf8ToUtf16LeStringLiteral(role.ui_identity.machine_class);
const window_title = std.unicode.utf8ToUtf16LeStringLiteral(role.ui_identity.product_name);

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
    extern "user32" fn IsWindow(HWND) callconv(.winapi) i32;
    extern "user32" fn DestroyWindow(HWND) callconv(.winapi) i32;
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
    message: MSG = undefined,

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
        self.window = raw.CreateWindowExW(0, class_name, window_title, window_style, use_default, use_default, 960, 640, null, null, self.instance, null);
        if (self.window == null) return false;
        self.graphics_device = graphics.Device.create() catch {
            // A visible window without a render device is not an admitted UI
            // state.  Tear it down immediately so callers cannot observe a
            // half-initialized shell or accidentally fall back to GDI.
            _ = raw.DestroyWindow(self.window.?);
            self.window = null;
            return false;
        };
        return true;
    }
    pub fn destroyWindow(self: *Backend) bool {
        if (self.graphics_device) |*device| {
            device.deinit();
            self.graphics_device = null;
        }
        const window = self.window orelse return true;
        // DefWindowProc handles WM_CLOSE and may already have destroyed it.
        if (raw.IsWindow(window) != 0 and raw.DestroyWindow(window) == 0) return false;
        self.window = null;
        return true;
    }
    pub fn showWindow(self: *Backend) void {
        // ShowWindow's return reports previous visibility, not success/failure.
        _ = raw.ShowWindow(self.window.?, self.show);
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

fn windowProc(window: HWND, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
    if (message == 0x2) { // WM_DESTROY
        raw.PostQuitMessage(0);
        return 0;
    }
    return raw.DefWindowProcW(window, message, wparam, lparam);
}
