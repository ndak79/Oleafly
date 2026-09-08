//! Narrow x64 Windows UI adapter. Declarations match the Win32 SDK's pointer,
//! DWORD/BOOL/HRESULT and callback ABI; no generated "everything" binding.
//! Entry-time DLL policy governs subsequent loads, not the OS's pre-entry image
//! loader. Resource and manifest identity are supplied by the product build;
//! this adapter owns the first native render bridge and shell chrome, not
//! worker, database, or network seams.
const std = @import("std");
const shell = @import("windows_shell");
const com = @import("windows_com");
const entry = @import("ui_entry");
const role = @import("app_role");
const build_identity = @import("app_build_identity");
const build_identity_config = @import("build_identity_config");
const layout = @import("app_layout");
const uia_shell = @import("app_uia_shell");
const strings = @import("app_strings");
const telemetry = @import("windows_telemetry");
const graphics = @import("graphics");
const composition = @import("composition_native");
const presenter = @import("presenter_native");
const qos = @import("windows_qos");
const presenter_config = @import("presenter_config");

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
pub const ACCEL = extern struct {
    fVirt: u8,
    key: u16,
    cmd: u16,
};
const SCROLLINFO = extern struct {
    cbSize: u32,
    fMask: u32,
    nMin: i32,
    nMax: i32,
    nPage: u32,
    nPos: i32,
    nTrackPos: i32,
};

pub const dll_search_flags: u32 = 0x800; // LOAD_LIBRARY_SEARCH_SYSTEM32
pub const window_style: u32 = 0xcf0000; // WS_OVERLAPPEDWINDOW, system caption
pub const dpi_pmv2: *anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -4))));
pub const frame_signal_message: u32 = 0x8001; // WM_APP + 1, private frame grant
pub const icon_resource_id: usize = 1;

/// The build selects the admitted baseline explicitly.  A discard build is a
/// reproducible challenger and is never chosen from adapter/runtime state.
pub fn configuredSwapEffect() graphics.SwapEffect {
    return if (presenter_config.use_discard) .flip_discard else .flip_sequential;
}

/// Build the only Present1 metadata the native shell is allowed to emit.  A
/// full redraw or an unproven back-buffer history intentionally carries zero
/// dirty rectangles; once both the tracked scene and target buffer are
/// coherent, the complete client region is the exact updated region.
pub fn presentRequestForState(
    effect: graphics.SwapEffect,
    full_redraw: bool,
    history_valid: bool,
    width: u32,
    height: u32,
) presenter.PresentRequest {
    if (effect == .flip_discard or full_redraw or !history_valid or width == 0 or height == 0) return .{};
    return .{ .dirty_rect = .{ .left = 0, .top = 0, .right = @intCast(width), .bottom = @intCast(height) } };
}
const wm_nccreate: u32 = 0x0081;
const wm_ncdestroy: u32 = 0x0082;
const wm_destroy: u32 = 0x0002;
pub const wm_activate: u32 = 0x0006;
pub const wm_size: u32 = 0x0005;
pub const wm_paint: u32 = 0x000f;
pub const wm_showwindow: u32 = 0x0018;
pub const wm_activateapp: u32 = 0x001c;
pub const wm_ncaactivate: u32 = 0x0086;
pub const wm_displaychange: u32 = 0x007e;
pub const wm_powerbroadcast: u32 = 0x0218;
pub const wm_dpi_changed: u32 = 0x02e0;
const wm_command: u32 = 0x0111;
const wm_vscroll: u32 = 0x0115;
pub const size_minimized: usize = 1;
pub const pbt_apmresumecritical: usize = 0x0006;
pub const pbt_apmresumesuspend: usize = 0x0007;
pub const pbt_apmresumeautomatic: usize = 0x0012;
const gwlp_userdata: i32 = -21;
const ws_child: u32 = 0x40000000;
const ws_visible: u32 = 0x10000000;
const ws_tabstop: u32 = 0x00010000;
const ws_group: u32 = 0x00020000;
const ws_ex_transparent: u32 = 0x00000020;
pub const swp_nozorder: u32 = 0x0004;
pub const swp_noactivate: u32 = 0x0010;
const bs_pushbutton: u32 = 0x00000000;
const bs_autocheckbox: u32 = 0x00000003;
const bm_setcheck: u32 = 0x00f1;
const sbs_vert: u32 = 0x00000001;
const sb_ctl: i32 = 2;
const sif_all: u32 = 0x000f;
const ss_left: u32 = 0x00000000;
const sw_hide: i32 = 0;
const sw_show: i32 = 5;
const fvirt_key: u8 = 0x01;
const fvirt_control: u8 = 0x08;
const fvirt_shift: u8 = 0x04;
const vk_b: u16 = 0x42;
const vk_m: u16 = 0x4d;
const vk_o: u16 = 0x4f;
const vk_r: u16 = 0x52;
const vk_s: u16 = 0x53;
const control_id_open_folder: u16 = 100;
const control_id_mode: u16 = 101;
const control_id_compile: u16 = 102;
const control_id_save: u16 = 103;
const control_id_recovery: u16 = 104;
const button_class = std.unicode.utf8ToUtf16LeStringLiteral("BUTTON");
const static_class = std.unicode.utf8ToUtf16LeStringLiteral("STATIC");
const scrollbar_class = std.unicode.utf8ToUtf16LeStringLiteral("SCROLLBAR");
const open_folder_title = std.unicode.utf8ToUtf16LeStringLiteral(strings.literal(.open_folder));
const mode_title = std.unicode.utf8ToUtf16LeStringLiteral(strings.literal(.mode));
const compile_title = std.unicode.utf8ToUtf16LeStringLiteral(strings.literal(.compile));
const save_title = std.unicode.utf8ToUtf16LeStringLiteral(strings.literal(.save));
const recovery_title = std.unicode.utf8ToUtf16LeStringLiteral(strings.literal(.recovery));
const project_title = std.unicode.utf8ToUtf16LeStringLiteral(strings.literal(.project));
const source_title = std.unicode.utf8ToUtf16LeStringLiteral(strings.literal(.source));
const pdf_title = std.unicode.utf8ToUtf16LeStringLiteral(strings.literal(.pdf));
const status_title = std.unicode.utf8ToUtf16LeStringLiteral(strings.literal(.status));
const ready_title = std.unicode.utf8ToUtf16LeStringLiteral(strings.literal(.ready));
const splitter_title = std.unicode.utf8ToUtf16LeStringLiteral(strings.literal(.splitter));
const class_name = std.unicode.utf8ToUtf16LeStringLiteral(role.ui_identity.machine_class);
const window_title = std.unicode.utf8ToUtf16LeStringLiteral(role.ui_identity.product_name);

/// The message-level seam is intentionally smaller than the later native
/// capture/UIA campaign.  It records only what the shell can learn from the
/// Win32 queue and DXGI Present result; it never claims that a window is
/// physically visible on a display or that a DPI change was externally
/// captured.
pub const WindowMessageKind = enum {
    other,
    paint,
    resize,
    minimized,
    dpi_changed,
    shown,
    hidden,
    activated,
    deactivated,
    display_changed,
    resumed,
};

pub const DpiChange = struct {
    x: u16,
    y: u16,
};

pub const FrameFailure = enum {
    wait_abandoned,
    wait_failed,
    invalid_wait_handle,
    unexpected_wait_result,
    unsupported_wait,
    device_lost,
    render_failed,
    rebuild_failed,
    missing_frame_resources,
    dpi_suggested_rect_invalid,
    dpi_suggested_rect_failed,
};

pub const wait_object_0: u32 = presenter.wait_object_0;
pub const wait_abandoned: u32 = presenter.wait_abandoned;
pub const wait_failed: u32 = presenter.wait_failed;

/// `MsgWaitForMultipleObjectsEx` returns the same abandoned/failed sentinels
/// as the frame-latency wait. Keep those outcomes distinct at the shell edge;
/// the caller decides whether the complete frame graph can be rebuilt.
pub fn classifyMessageWaitFailure(result: u32) FrameFailure {
    return switch (result) {
        wait_abandoned => .wait_abandoned,
        wait_failed => .wait_failed,
        else => .unexpected_wait_result,
    };
}

pub const FrameLifecycleState = enum {
    ready,
    occluded,
    terminal,
};

/// The native wait primitive already distinguishes these errors; keep that
/// distinction at the shell boundary instead of turning every error into a
/// false-y render result.
pub fn classifyWaitFailure(failure: presenter.WaitError) FrameFailure {
    return switch (failure) {
        error.FrameLatencyWaitAbandoned => .wait_abandoned,
        error.FrameLatencyWaitFailed => .wait_failed,
        error.InvalidFrameLatencyHandle => .invalid_wait_handle,
        error.UnexpectedFrameLatencyWaitResult => .unexpected_wait_result,
        error.UnsupportedTarget => .unsupported_wait,
    };
}

/// Small state holder shared by the native render paths and their deterministic
/// fault-injection tests. A failed operation never consumes an already queued
/// frame; recoverable callers explicitly requeue the work while the failure is
/// exposed as terminal until a successful frame completes.
pub const FrameLifecycle = struct {
    state: FrameLifecycleState = .ready,
    failure: ?FrameFailure = null,
    pending: bool = false,

    pub fn request(self: *FrameLifecycle) void {
        self.pending = true;
    }

    pub fn cancel(self: *FrameLifecycle) void {
        self.pending = false;
    }

    pub fn complete(self: *FrameLifecycle, occluded: bool) void {
        self.state = if (occluded) .occluded else .ready;
        self.failure = null;
        self.pending = false;
    }

    pub fn fail(self: *FrameLifecycle, failure: FrameFailure, requeue: bool) void {
        self.state = .terminal;
        self.failure = failure;
        self.pending = requeue;
    }
};

pub const DpiRectOutcome = enum {
    not_supplied,
    invalid,
    applied,
    failed,
};

pub const SetWindowRectFn = *const fn (?*anyopaque, HWND, RECT) callconv(.winapi) bool;

/// Decode the OS-owned WM_DPICHANGED rectangle only for the duration of the
/// message callback. The caller must not retain the returned value's pointer;
/// this function returns a value copy instead.
pub fn dpiSuggestedRect(lparam: isize) ?RECT {
    if (lparam == 0) return null;
    const address: usize = @bitCast(lparam);
    return @as(*const RECT, @ptrFromInt(address)).*;
}

/// Apply the suggested outer-window rectangle through an injected setter. The
/// setter seam keeps malformed rectangles and SetWindowPos failures visible to
/// shell tests without requiring a live desktop or mutating a real HWND.
pub fn applySuggestedDpiRect(
    window: ?HWND,
    suggested: ?RECT,
    context: ?*anyopaque,
    set_rect: SetWindowRectFn,
) DpiRectOutcome {
    const window_value = window orelse return .invalid;
    const rect = suggested orelse return .not_supplied;
    const width: i64 = @as(i64, rect.right) - @as(i64, rect.left);
    const height: i64 = @as(i64, rect.bottom) - @as(i64, rect.top);
    const max_extent: i64 = std.math.maxInt(i32);
    if (width <= 0 or height <= 0 or width > max_extent or height > max_extent) return .invalid;
    if (!set_rect(context, window_value, rect)) return .failed;
    return .applied;
}

/// A failed DestroyWindow is retryable while IsWindow still confirms the
/// handle. Only success or confirmed invalidation may discard the HWND.
pub fn windowAfterDestroy(window: ?HWND, destroy_succeeded: bool, still_valid: bool) ?HWND {
    const value = window orelse return null;
    if (destroy_succeeded or !still_valid) return null;
    return value;
}

pub const Visibility = enum { visible, occluded, minimized };

pub const WindowStateEvent = union(enum) {
    paint,
    resize,
    minimized,
    dpi_changed: DpiChange,
    shown,
    hidden,
    activated,
    deactivated,
    display_changed,
    resumed,
    occluded,
};

/// Logical shell state used to gate native Present calls.  It mirrors the
/// presenter's visibility vocabulary while retaining activation separately:
/// an inactive window is not automatically occluded, and an occluded window
/// is not declared visible until an OS/DXGI event gives the shell a reason to
/// retry.  Every transition invalidates the two-buffer history so the next
/// admitted frame is a full redraw.
pub const NativeWindowState = struct {
    visibility: Visibility = .visible,
    hidden: bool = false,
    active: bool = true,
    dpi: DpiChange = .{ .x = 96, .y = 96 },
    display_epoch: u32 = 0,
    needs_full_redraw: bool = true,

    pub fn canRender(self: *const NativeWindowState) bool {
        return !self.hidden and self.visibility == .visible;
    }

    pub fn apply(self: *NativeWindowState, event: WindowStateEvent) bool {
        var request_frame = true;
        switch (event) {
            .paint => {
                // WM_PAINT is an OS visibility hint after DXGI reported
                // occlusion.  It may retry a covered window once it becomes
                // invalidated, but never overrides an explicit hidden or
                // minimized state and never creates a timer-driven wake.
                if (!self.hidden and self.visibility == .occluded) self.visibility = .visible;
                self.invalidate();
            },
            .resize => {
                if (!self.hidden and self.visibility == .minimized) self.visibility = .visible;
                self.invalidate();
            },
            .minimized => {
                self.visibility = .minimized;
                self.invalidate();
            },
            .dpi_changed => |dpi| {
                self.dpi = dpi;
                self.invalidate();
            },
            .shown => {
                self.hidden = false;
                if (self.visibility != .minimized) self.visibility = .visible;
                self.invalidate();
            },
            .hidden => {
                self.hidden = true;
                if (self.visibility != .minimized) self.visibility = .occluded;
                self.invalidate();
            },
            .activated => {
                self.active = true;
                if (!self.hidden and self.visibility == .occluded) self.visibility = .visible;
                self.invalidate();
            },
            .deactivated => {
                self.active = false;
                request_frame = false;
            },
            .display_changed => {
                self.display_epoch +%= 1;
                self.invalidate();
            },
            .resumed => {
                if (!self.hidden and self.visibility != .minimized) self.visibility = .visible;
                self.invalidate();
            },
            .occluded => {
                if (!self.hidden and self.visibility != .minimized) self.visibility = .occluded;
                self.invalidate();
            },
        }
        return self.canRender() and request_frame;
    }

    pub fn invalidate(self: *NativeWindowState) void {
        self.needs_full_redraw = true;
    }

    pub fn framePresented(self: *NativeWindowState) void {
        self.needs_full_redraw = false;
    }
};

pub fn dpiFromWParam(wparam: usize) ?DpiChange {
    const x: u16 = @intCast(wparam & 0xffff);
    const y: u16 = @intCast((wparam >> 16) & 0xffff);
    if (x == 0 or y == 0) return null;
    return .{ .x = x, .y = y };
}

pub fn classifyWindowMessage(message: u32, wparam: usize) WindowMessageKind {
    return switch (message) {
        wm_paint => .paint,
        wm_size => if (wparam == size_minimized) .minimized else .resize,
        wm_dpi_changed => .dpi_changed,
        wm_showwindow => if (wparam != 0) .shown else .hidden,
        wm_activateapp => if (wparam != 0) .activated else .deactivated,
        wm_activate => if ((wparam & 0xffff) != 0) .activated else .deactivated,
        wm_ncaactivate => if (wparam != 0) .activated else .deactivated,
        wm_displaychange => .display_changed,
        wm_powerbroadcast => switch (wparam) {
            pbt_apmresumecritical, pbt_apmresumesuspend, pbt_apmresumeautomatic => .resumed,
            else => .other,
        },
        else => .other,
    };
}

pub fn renderOutcomeUsable(outcome: presenter.PresentOutcome) bool {
    return outcome == .presented or outcome == .occluded;
}

const FrameAttempt = enum {
    presented,
    occluded,
    device_lost,
    failed,
};

/// A complete device-dependent frame graph. The candidate is only moved into
/// Backend after every D3D11, DXGI, back-buffer, and D2D/DWrite step succeeds;
/// this makes hardware-to-WARP fallback cover composition initialization too.
const FrameResources = struct {
    device: graphics.Device,
    swap_chain: presenter.SwapChain,
    back_buffer: presenter.BackBuffer,
    composition_renderer: composition.Renderer,
};

fn createFrameResources(window: HWND, path: graphics.DevicePath) !FrameResources {
    var device = try graphics.Device.createWithPath(path);
    errdefer device.deinit();
    var swap_chain = try presenter.create(&device, @ptrCast(window), configuredSwapEffect());
    errdefer swap_chain.deinit();
    var back_buffer = try swap_chain.acquireBackBuffer(&device, 0);
    errdefer {
        _ = swap_chain.retireBackBuffer(&device, &back_buffer) catch back_buffer.deinit();
    }
    const composition_renderer = try composition.Renderer.init(&device);
    return .{
        .device = device,
        .swap_chain = swap_chain,
        .back_buffer = back_buffer,
        .composition_renderer = composition_renderer,
    };
}

pub const TelemetryState = enum {
    disabled,
    registered,
    registration_failed,
    write_failed,
    teardown_failed,
};

pub fn isPaintMessage(message: u32) bool {
    return message == wm_paint;
}

pub fn isResizeMessage(message: u32) bool {
    return message == wm_size;
}

pub fn isFrameSignalMessage(message: u32) bool {
    return message == frame_signal_message;
}

const raw = struct {
    extern "kernel32" fn GetCommandLineW() callconv(.winapi) [*:0]const u16;
    extern "kernel32" fn LocalFree(?*anyopaque) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
    extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) u32;
    extern "kernel32" fn QueryPerformanceCounter(*i64) callconv(.winapi) i32;
    extern "kernel32" fn SetDefaultDllDirectories(u32) callconv(.winapi) i32;
    extern "shell32" fn CommandLineToArgvW([*:0]const u16, *i32) callconv(.winapi) ?[*][*:0]u16;
    extern "bcrypt" fn BCryptGenRandom(?*anyopaque, [*]u8, u32, u32) callconv(.winapi) i32;
    extern "user32" fn SetProcessDpiAwarenessContext(*anyopaque) callconv(.winapi) i32;
    extern "user32" fn GetThreadDpiAwarenessContext() callconv(.winapi) ?*anyopaque;
    extern "user32" fn AreDpiAwarenessContextsEqual(?*anyopaque, ?*anyopaque) callconv(.winapi) i32;
    extern "user32" fn LoadCursorW(?HINSTANCE, [*:0]const u16) callconv(.winapi) ?*anyopaque;
    // The second argument is either a string resource or an integer resource
    // identifier.  Keep it opaque so the ID-1 resource does not acquire a
    // bogus UTF-16 alignment requirement.
    extern "user32" fn LoadIconW(?HINSTANCE, ?*anyopaque) callconv(.winapi) ?*anyopaque;
    extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.winapi) u16;
    extern "user32" fn UnregisterClassW([*:0]const u16, HINSTANCE) callconv(.winapi) i32;
    extern "user32" fn CreateWindowExW(u32, [*:0]const u16, [*:0]const u16, u32, i32, i32, i32, i32, ?HWND, ?*anyopaque, HINSTANCE, ?*anyopaque) callconv(.winapi) ?HWND;
    extern "user32" fn SetWindowTextW(HWND, [*:0]const u16) callconv(.winapi) i32;
    extern "user32" fn SendMessageW(HWND, u32, usize, isize) callconv(.winapi) isize;
    extern "user32" fn ShowWindow(HWND, i32) callconv(.winapi) i32;
    extern "user32" fn MoveWindow(HWND, i32, i32, i32, i32, i32) callconv(.winapi) i32;
    extern "user32" fn SetScrollInfo(HWND, i32, *const SCROLLINFO, i32) callconv(.winapi) i32;
    extern "user32" fn SetWindowPos(HWND, ?HWND, i32, i32, i32, i32, u32) callconv(.winapi) i32;
    extern "user32" fn GetDpiForWindow(HWND) callconv(.winapi) u32;
    extern "user32" fn CreateAcceleratorTableW([*]const ACCEL, i32) callconv(.winapi) ?*anyopaque;
    extern "user32" fn DestroyAcceleratorTable(?*anyopaque) callconv(.winapi) i32;
    extern "user32" fn TranslateAcceleratorW(HWND, ?*anyopaque, *const MSG) callconv(.winapi) i32;
    extern "user32" fn SetWindowLongPtrW(HWND, i32, isize) callconv(.winapi) isize;
    extern "user32" fn GetWindowLongPtrW(HWND, i32) callconv(.winapi) isize;
    extern "user32" fn ValidateRect(HWND, ?*const RECT) callconv(.winapi) i32;
    extern "user32" fn IsWindow(HWND) callconv(.winapi) i32;
    extern "user32" fn DestroyWindow(HWND) callconv(.winapi) i32;
    extern "user32" fn GetClientRect(HWND, *RECT) callconv(.winapi) i32;
    extern "user32" fn MsgWaitForMultipleObjectsEx(u32, [*]const ?*anyopaque, u32, u32, u32) callconv(.winapi) u32;
    extern "user32" fn GetMessageW(*MSG, ?HWND, u32, u32) callconv(.winapi) i32;
    extern "user32" fn TranslateMessage(*const MSG) callconv(.winapi) i32;
    extern "user32" fn DispatchMessageW(*const MSG) callconv(.winapi) isize;
    extern "user32" fn DefWindowProcW(HWND, u32, usize, isize) callconv(.winapi) isize;
    extern "user32" fn PostQuitMessage(i32) callconv(.winapi) void;
};

fn setSuggestedWindowRect(_: ?*anyopaque, window: HWND, rect: RECT) callconv(.winapi) bool {
    return raw.SetWindowPos(
        window,
        null,
        rect.left,
        rect.top,
        rect.right - rect.left,
        rect.bottom - rect.top,
        swp_nozorder | swp_noactivate,
    ) != 0;
}

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
    open_folder_control: ?HWND = null,
    mode_control: ?HWND = null,
    mode_checked: bool = false,
    compile_control: ?HWND = null,
    save_control: ?HWND = null,
    recovery_control: ?HWND = null,
    project_label: ?HWND = null,
    source_label: ?HWND = null,
    pdf_label: ?HWND = null,
    status_label: ?HWND = null,
    status_value: ?HWND = null,
    splitter_control: ?HWND = null,
    accelerators: ?*anyopaque = null,
    recovery_visible: bool = false,
    trace_trial: [16]u8 = [_]u8{0} ** 16,
    telemetry_provider: ?telemetry.Provider = null,
    graphics_device: ?graphics.Device = null,
    swap_chain: ?presenter.SwapChain = null,
    back_buffer: ?presenter.BackBuffer = null,
    composition_renderer: ?composition.Renderer = null,
    buffer_history_valid: [2]bool = .{ false, false },
    frame_lifecycle: FrameLifecycle = .{},
    window_state: NativeWindowState = .{},
    telemetry_state: TelemetryState = .disabled,
    telemetry_error: ?telemetry.ProviderError = null,
    telemetry_event_count: u32 = 0,
    qos_state: qos.State = .{},
    semantic_revision: u64 = 0,
    semantic_snapshot: ?uia_shell.Snapshot = null,
    message: MSG = undefined,

    pub const initial_clear_color: [4]f32 = .{ 0.035, 0.055, 0.09, 1.0 };

    pub fn restrictDllSearch(_: *Backend) bool {
        // No application/CWD/PATH/user-added directory is admitted in this slice.
        return raw.SetDefaultDllDirectories(dll_search_flags) != 0;
    }
    pub fn verifyBuildIdentity(_: *Backend) bool {
        if (!build_identity_config.authoritative) return false;
        return build_identity.isValid(
            build_identity_config.source_set_sha256,
            build_identity_config.dependency_lock_sha256,
            build_identity_config.build_identity,
        );
    }
    pub fn buildIdentityAuthoritative(_: *Backend) bool {
        return build_identity_config.authoritative;
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
    pub fn setTraceTrial(self: *Backend, trial: [16]u8) void {
        // A provider owns the correlation identity for its whole registration
        // lifetime. Ignore late mutation instead of emitting mixed-trial data.
        if (self.telemetry_provider != null) return;
        self.trace_trial = trial;
        self.telemetry_state = .disabled;
        self.telemetry_error = null;
        self.telemetry_event_count = 0;
    }
    pub fn startTelemetry(self: *Backend) void {
        if (self.telemetry_provider != null) return;
        self.telemetry_error = null;
        self.telemetry_event_count = 0;
        const provider = telemetry.Provider.register(self.trace_trial) catch |err| {
            // ETW is diagnostic-only: startup remains non-blocking, but the
            // typed state/error make registration failure observable to QA and
            // future diagnostics rather than silently disabling tracing.
            self.telemetry_state = .registration_failed;
            self.telemetry_error = err;
            return;
        };
        self.telemetry_provider = provider;
        self.telemetry_state = .registered;
        // Registration happens before window creation. The first actual
        // displayed frame is emitted by presentFrame after its QPC is known.
    }
    pub fn telemetryState(self: *const Backend) TelemetryState {
        return self.telemetry_state;
    }
    pub fn telemetryError(self: *const Backend) ?telemetry.ProviderError {
        return self.telemetry_error;
    }
    pub fn telemetryRegistered(self: *const Backend) bool {
        return self.telemetry_provider != null and self.telemetry_provider.?.isRegistered();
    }
    pub fn telemetryEventCount(self: *const Backend) u32 {
        return self.telemetry_event_count;
    }
    pub fn telemetryTrialId(self: *const Backend) [16]u8 {
        return self.trace_trial;
    }

    pub fn modeChecked(self: *const Backend) bool {
        return self.mode_checked;
    }

    pub fn windowState(self: *const Backend) NativeWindowState {
        return self.window_state;
    }

    pub fn frameState(self: *const Backend) FrameLifecycleState {
        return self.frame_lifecycle.state;
    }

    pub fn frameFailure(self: *const Backend) ?FrameFailure {
        return self.frame_lifecycle.failure;
    }

    pub fn framePending(self: *const Backend) bool {
        return self.frame_lifecycle.pending;
    }

    fn failFrame(self: *Backend, failure: FrameFailure, requeue: bool) void {
        self.frame_lifecycle.fail(failure, requeue);
    }

    fn completeFrame(self: *Backend, occluded: bool) void {
        self.frame_lifecycle.complete(occluded);
    }

    fn applyWindowStateEvent(self: *Backend, event: WindowStateEvent) void {
        const request_frame = self.window_state.apply(event);
        self.buffer_history_valid = .{ false, false };
        self.updateQosScope();
        if (request_frame) self.requestFrame();
    }

    fn updateQosScope(self: *Backend) void {
        if (self.window_state.canRender() and self.window_state.active) {
            self.qos_state.leaveBackground();
        } else {
            self.qos_state.enterBackground();
        }
    }

    fn refreshShellLayout(self: *Backend) void {
        const window = self.window orelse return;
        var client: RECT = undefined;
        if (raw.GetClientRect(window, &client) == 0) return;
        const width_i = client.right - client.left;
        const height_i = client.bottom - client.top;
        if (width_i <= 0 or height_i <= 0) return;
        if (self.hasShellControls()) _ = self.relayoutControls(@intCast(width_i), @intCast(height_i));
        self.requestFrame();
    }

    fn handleDpiChanged(self: *Backend, wparam: usize, lparam: isize) void {
        const dpi = dpiFromWParam(wparam) orelse return;
        self.applyWindowStateEvent(.{ .dpi_changed = dpi });
        const window = self.window orelse return;

        // PMv2 supplies an outer-window rectangle in lParam. The shell owns
        // this HWND, so apply the value copy during this callback; the pointer
        // is never retained past the message dispatch.
        switch (applySuggestedDpiRect(window, dpiSuggestedRect(lparam), null, setSuggestedWindowRect)) {
            .applied, .not_supplied => {},
            .invalid => self.failFrame(.dpi_suggested_rect_invalid, true),
            .failed => self.failFrame(.dpi_suggested_rect_failed, true),
        }
        self.refreshShellLayout();
        if (self.window_state.canRender() and self.hasFrameResources()) {
            var client: RECT = undefined;
            if (raw.GetClientRect(window, &client) != 0) {
                const width_i = client.right - client.left;
                const height_i = client.bottom - client.top;
                if (width_i > 0 and height_i > 0) _ = self.resizeFrame(@intCast(width_i), @intCast(height_i));
            }
        }
    }

    pub fn registerClass(self: *Backend) bool {
        const cursor = raw.LoadCursorW(null, @ptrFromInt(32512)) orelse return false; // IDC_ARROW, shared
        // The product resource generator emits the group/icon pair at ID 1.
        // Loading it from this module instance makes the same identity visible
        // in the title bar, task switcher, and shell chrome; no ambient/default
        // icon is substituted for a product build.
        const icon = raw.LoadIconW(self.instance, @ptrFromInt(icon_resource_id)) orelse return false;
        const window_class: WNDCLASSEXW = .{
            .cbSize = @sizeOf(WNDCLASSEXW),
            .style = 3, // CS_HREDRAW | CS_VREDRAW
            .lpfnWndProc = windowProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = self.instance,
            .hIcon = icon,
            .hCursor = cursor,
            .hbrBackground = @ptrFromInt(6), // COLOR_WINDOW + 1; system-owned
            .lpszMenuName = null,
            .lpszClassName = class_name,
            .hIconSm = icon,
        };
        return raw.RegisterClassExW(&window_class) != 0;
    }
    pub fn unregisterClass(self: *Backend) bool {
        return raw.UnregisterClassW(class_name, self.instance) != 0;
    }

    fn createChild(self: *Backend, class: [*:0]const u16, title: [*:0]const u16, ex_style: u32, style: u32, id: u16) ?HWND {
        const parent = self.window orelse return null;
        return raw.CreateWindowExW(
            ex_style,
            class,
            title,
            style,
            0,
            0,
            1,
            1,
            parent,
            @ptrFromInt(@as(usize, id)),
            self.instance,
            null,
        );
    }

    fn forgetShellControls(self: *Backend) void {
        if (self.accelerators) |accelerators| {
            _ = raw.DestroyAcceleratorTable(accelerators);
            self.accelerators = null;
        }
        self.open_folder_control = null;
        self.mode_control = null;
        self.mode_checked = false;
        self.compile_control = null;
        self.save_control = null;
        self.recovery_control = null;
        self.project_label = null;
        self.source_label = null;
        self.pdf_label = null;
        self.status_label = null;
        self.status_value = null;
        self.splitter_control = null;
        self.recovery_visible = false;
        self.semantic_snapshot = null;
    }

    fn destroyShellControls(self: *Backend) void {
        const children = [_]*?HWND{
            &self.open_folder_control,
            &self.mode_control,
            &self.compile_control,
            &self.save_control,
            &self.recovery_control,
            &self.project_label,
            &self.source_label,
            &self.pdf_label,
            &self.status_label,
            &self.status_value,
            &self.splitter_control,
        };
        for (children) |child| {
            const window = child.* orelse continue;
            if (raw.IsWindow(window) == 0 or raw.DestroyWindow(window) != 0 or raw.IsWindow(window) == 0) {
                child.* = null;
            }
        }
        if (self.accelerators) |accelerators| {
            if (raw.DestroyAcceleratorTable(accelerators) != 0) self.accelerators = null;
        }
        if (!self.hasAnyShellControls()) self.recovery_visible = false;
    }

    fn teardownWindowAfterFailure(self: *Backend) void {
        self.destroyShellControls();
        const window = self.window orelse return;
        if (raw.IsWindow(window) == 0) {
            self.forgetShellControls();
            self.window = null;
            return;
        }
        const destroyed = raw.DestroyWindow(window) != 0;
        if (destroyed) {
            self.forgetShellControls();
            self.window = null;
        } else {
            self.window = windowAfterDestroy(window, false, raw.IsWindow(window) != 0);
        }
    }

    fn createShellControls(self: *Backend) bool {
        if (self.window == null) return false;
        self.destroyShellControls();
        if (self.hasAnyShellControls()) return false;

        const button_style = ws_child | ws_visible | ws_tabstop | bs_pushbutton;
        const first_button_style = button_style | ws_group;
        const hidden_button_style = ws_child | ws_tabstop | bs_pushbutton;
        const label_style = ws_child | ws_visible | ss_left;

        self.open_folder_control = self.createChild(button_class, open_folder_title, 0, first_button_style, control_id_open_folder) orelse return false;
        const mode_style = ws_child | ws_visible | ws_tabstop | bs_autocheckbox;
        self.mode_control = self.createChild(button_class, mode_title, 0, mode_style, control_id_mode) orelse {
            self.destroyShellControls();
            return false;
        };
        self.compile_control = self.createChild(button_class, compile_title, 0, button_style, control_id_compile) orelse {
            self.destroyShellControls();
            return false;
        };
        self.save_control = self.createChild(button_class, save_title, 0, button_style, control_id_save) orelse {
            self.destroyShellControls();
            return false;
        };
        self.recovery_control = self.createChild(button_class, recovery_title, 0, hidden_button_style, control_id_recovery) orelse {
            self.destroyShellControls();
            return false;
        };
        self.project_label = self.createChild(static_class, project_title, ws_ex_transparent, label_style, 105) orelse {
            self.destroyShellControls();
            return false;
        };
        self.source_label = self.createChild(static_class, source_title, ws_ex_transparent, label_style, 106) orelse {
            self.destroyShellControls();
            return false;
        };
        self.pdf_label = self.createChild(static_class, pdf_title, ws_ex_transparent, label_style, 107) orelse {
            self.destroyShellControls();
            return false;
        };
        self.status_label = self.createChild(static_class, status_title, ws_ex_transparent, label_style, 108) orelse {
            self.destroyShellControls();
            return false;
        };
        self.status_value = self.createChild(static_class, ready_title, ws_ex_transparent, label_style, 109) orelse {
            self.destroyShellControls();
            return false;
        };
        self.splitter_control = self.createChild(
            scrollbar_class,
            splitter_title,
            0,
            ws_child | ws_visible | ws_tabstop | sbs_vert,
            110,
        ) orelse {
            self.destroyShellControls();
            return false;
        };

        const accelerators = [_]ACCEL{
            .{ .fVirt = fvirt_key | fvirt_control, .key = vk_o, .cmd = control_id_open_folder },
            .{ .fVirt = fvirt_key | fvirt_control, .key = vk_m, .cmd = control_id_mode },
            .{ .fVirt = fvirt_key | fvirt_control, .key = vk_b, .cmd = control_id_compile },
            .{ .fVirt = fvirt_key | fvirt_control, .key = vk_r, .cmd = control_id_recovery },
            .{ .fVirt = fvirt_key | fvirt_control | fvirt_shift, .key = vk_r, .cmd = control_id_recovery },
            .{ .fVirt = fvirt_key | fvirt_control, .key = vk_s, .cmd = control_id_save },
        };
        self.accelerators = raw.CreateAcceleratorTableW(&accelerators, @intCast(accelerators.len)) orelse {
            self.destroyShellControls();
            return false;
        };
        self.recovery_visible = false;
        var client: RECT = undefined;
        if (raw.GetClientRect(self.window.?, &client) == 0 or client.right <= client.left or client.bottom <= client.top) {
            self.destroyShellControls();
            return false;
        }
        if (!self.relayoutControls(@intCast(client.right - client.left), @intCast(client.bottom - client.top))) {
            self.destroyShellControls();
            return false;
        }
        return true;
    }

    fn pixelsToDip(pixels: u32, dpi: u32) u32 {
        return composition.pixelsToDip(pixels, dpi);
    }

    fn dipToPixels(dip: u32, dpi: u32) ?i32 {
        const effective_dpi = if (dpi == 0) 96 else dpi;
        const value = (@as(u64, dip) * effective_dpi + 48) / 96;
        if (value == 0 or value > std.math.maxInt(i32)) return null;
        return @intCast(value);
    }

    fn moveChild(_: *Backend, child: ?HWND, x: u32, y: u32, width: u32, height: u32, visible: bool, dpi: u32) bool {
        const window = child orelse return true;
        const px_x = dipToPixels(x, dpi) orelse return false;
        const px_y = dipToPixels(y, dpi) orelse return false;
        const px_width = dipToPixels(@max(width, 1), dpi) orelse return false;
        const px_height = dipToPixels(@max(height, 1), dpi) orelse return false;
        if (raw.MoveWindow(window, px_x, px_y, px_width, px_height, 1) == 0) return false;
        _ = raw.ShowWindow(window, if (visible) sw_show else sw_hide);
        return true;
    }

    /// Lay out only compact native affordances.  Coordinates are expressed in
    /// shared DIP tokens and converted once at the PMv2 window's current DPI;
    /// the D3D surface remains the large unobscured background.
    pub fn relayoutControls(self: *Backend, width_px: u32, height_px: u32) bool {
        const window = self.window orelse return false;
        const dpi = raw.GetDpiForWindow(window);
        const geometry = composition.frameGeometry(width_px, height_px, dpi) catch return false;
        const width = geometry.width_dip;
        const height = geometry.height_dip;
        const gap = layout.spacing_rhythm_dip;
        const toolbar_y = @min(gap, @max(height, 1) - 1);
        const toolbar_height = layout.compact_control_max_dip;
        const content_top = geometry.toolbar_bottom_dip;
        const label_height = @min(layout.minimum_target_dip, @max(height, 1));
        const status_height = @min(layout.status_rail_dip, @max(height, 1));
        const content_visible = geometry.project_visible or geometry.source_visible or geometry.pdf_visible;
        const label_y = if (height > status_height + gap + label_height)
            content_top
        else if (height > label_height + gap)
            height - status_height - gap - label_height
        else
            0;

        if (!self.moveChild(self.open_folder_control, gap, toolbar_y, 120, toolbar_height, content_visible, dpi)) return false;
        if (!self.moveChild(self.mode_control, gap + 120 + gap, toolbar_y, 116, toolbar_height, content_visible, dpi)) return false;
        if (!self.moveChild(self.compile_control, gap + 120 + gap + 116 + gap, toolbar_y, 84, toolbar_height, content_visible, dpi)) return false;
        if (!self.moveChild(self.save_control, gap + 120 + gap + 116 + gap + 84 + gap, toolbar_y, 72, toolbar_height, content_visible, dpi)) return false;
        const source_x = geometry.source_left_dip;
        const source_width = geometry.source_right_dip -| geometry.source_left_dip;
        const pdf_x = geometry.pdf_left_dip;
        const pdf_width = geometry.pdf_right_dip -| geometry.pdf_left_dip;
        const label_width = @min(@as(u32, 104), @max(source_width, 1));
        const project_width = if (geometry.project_visible)
            @min(@as(u32, 104), @max(geometry.project_right_dip -| gap, 1))
        else
            1;
        if (!self.moveChild(self.project_label, gap, label_y, project_width, label_height, geometry.project_visible, dpi)) return false;
        if (!self.moveChild(self.source_label, source_x, label_y, label_width, label_height, geometry.source_visible, dpi)) return false;
        if (!self.moveChild(self.pdf_label, pdf_x, label_y, @min(@as(u32, 104), @max(pdf_width, 1)), label_height, geometry.pdf_visible, dpi)) return false;

        const status_y = geometry.status_top_dip;
        const splitter_target = layout.minimum_target_dip;
        const splitter_x = if (geometry.source_right_dip > splitter_target / 2)
            geometry.source_right_dip - splitter_target / 2
        else
            0;
        const splitter_height = if (status_y > content_top + gap)
            status_y - content_top - gap
        else
            1;
        if (!self.moveChild(
            self.splitter_control,
            splitter_x,
            content_top,
            splitter_target,
            splitter_height,
            geometry.source_visible and geometry.pdf_visible,
            dpi,
        )) return false;
        if (self.splitter_control) |splitter| {
            const info: SCROLLINFO = .{
                .cbSize = @intCast(@sizeOf(SCROLLINFO)),
                .fMask = sif_all,
                .nMin = 0,
                .nMax = 100,
                .nPage = 1,
                .nPos = 50,
                .nTrackPos = 50,
            };
            if (raw.SetScrollInfo(splitter, sb_ctl, &info, 1) == 0) return false;
        }
        const recovery_width = @min(@as(u32, 92), @max(width, 1));
        const recovery_x = if (width > recovery_width + gap)
            width - recovery_width - gap
        else if (width > recovery_width)
            width - recovery_width
        else
            0;
        const status_x = @min(gap, @max(width, 1) - 1);
        const status_value_x = if (width > gap + 56) gap + 56 else status_x;
        const show_recovery = self.recovery_visible or !content_visible;
        const status_value_end = if (show_recovery and recovery_x > status_value_x + gap)
            recovery_x - gap
        else if (width > gap)
            width - gap
        else
            status_value_x + 1;
        const status_value_width = if (status_value_end > status_value_x) status_value_end - status_value_x else 1;
        if (!self.moveChild(self.status_label, status_x, status_y, @min(@as(u32, 48), @max(width, 1)), status_height, true, dpi)) return false;
        if (!self.moveChild(self.status_value, status_value_x, status_y, status_value_width, status_height, true, dpi)) return false;
        if (!self.moveChild(self.recovery_control, recovery_x, status_y, recovery_width, status_height, show_recovery, dpi)) return false;
        const revision = if (self.semantic_revision == std.math.maxInt(u64)) 1 else self.semantic_revision + 1;
        var snapshot = uia_shell.Snapshot.init(
            revision,
            width,
            height,
            false,
            .system,
            if (self.recovery_visible) .error_status else .ready,
        ) catch return false;
        snapshot.nodes[@intFromEnum(uia_shell.NodeId.mode)].state.checked = self.mode_checked;
        self.semantic_snapshot = snapshot;
        self.semantic_revision = revision;
        return true;
    }

    pub fn semanticSnapshot(self: *const Backend) ?uia_shell.Snapshot {
        return self.semantic_snapshot;
    }

    fn updateSemanticMode(self: *Backend) void {
        const current = self.semantic_snapshot orelse return;
        const revision = if (self.semantic_revision == std.math.maxInt(u64)) 1 else self.semantic_revision + 1;
        var snapshot = current;
        snapshot.revision = revision;
        snapshot.nodes[@intFromEnum(uia_shell.NodeId.mode)].state.checked = self.mode_checked;
        self.semantic_snapshot = snapshot;
        self.semantic_revision = revision;
    }

    pub fn hasShellControls(self: *const Backend) bool {
        return self.open_folder_control != null and self.mode_control != null and
            self.compile_control != null and self.save_control != null and
            self.recovery_control != null and self.project_label != null and
            self.source_label != null and self.pdf_label != null and
            self.status_label != null and self.status_value != null and
            self.splitter_control != null and
            self.accelerators != null;
    }

    fn hasAnyShellControls(self: *const Backend) bool {
        return self.open_folder_control != null or self.mode_control != null or
            self.compile_control != null or self.save_control != null or
            self.recovery_control != null or self.project_label != null or
            self.source_label != null or self.pdf_label != null or
            self.status_label != null or self.status_value != null or
            self.splitter_control != null or
            self.accelerators != null;
    }

    pub fn setRecoveryVisible(self: *Backend, visible: bool) bool {
        self.recovery_visible = visible;
        const window = self.window orelse return false;
        var client: RECT = undefined;
        if (raw.GetClientRect(window, &client) == 0) return false;
        return self.relayoutControls(@intCast(@max(client.right - client.left, 0)), @intCast(@max(client.bottom - client.top, 0)));
    }

    pub fn createWindow(self: *Backend) bool {
        const use_default = std.math.minInt(i32); // CW_USEDEFAULT
        self.window = raw.CreateWindowExW(0, class_name, window_title, window_style, use_default, use_default, 960, 640, null, null, self.instance, @ptrCast(self));
        if (self.window == null) return false;
        // Keep the caption identity explicit after creation.  This avoids a
        // host-specific CreateWindowEx caption quirk while preserving the
        // system-owned title bar and standard caption buttons.
        if (raw.SetWindowTextW(self.window.?, window_title) == 0) {
            self.teardownWindowAfterFailure();
            return false;
        }
        if (!self.createShellControls()) {
            self.teardownWindowAfterFailure();
            return false;
        }
        const paths = [_]graphics.DevicePath{ .hardware, .warp };
        for (paths) |path| {
            const candidate = createFrameResources(self.window.?, path) catch continue;
            self.graphics_device = candidate.device;
            self.swap_chain = candidate.swap_chain;
            self.back_buffer = candidate.back_buffer;
            self.composition_renderer = candidate.composition_renderer;
            if (self.renderInitialFrame()) return true;
            self.releaseFrameResources();
        }
        // A visible window without a complete render graph is not an admitted
        // UI state. Tear it down immediately rather than falling back to GDI.
        self.teardownWindowAfterFailure();
        return false;
    }

    /// The first-frame bridge is synchronous: a hidden window receives a
    /// complete clear + Present before it becomes visible, so the shell never
    /// exposes an uninitialized back buffer.
    fn renderFrameOnce(self: *Backend) FrameAttempt {
        self.qos_state.enterForeground();
        defer self.qos_state.leaveForeground();
        if (!self.window_state.canRender()) return .occluded;
        const window = self.window orelse return .failed;
        var client: RECT = undefined;
        if (raw.GetClientRect(window, &client) == 0) return .failed;
        const width_i = client.right - client.left;
        const height_i = client.bottom - client.top;
        if (width_i <= 0 or height_i <= 0) return .failed;
        const width: u32 = @intCast(width_i);
        const height: u32 = @intCast(height_i);
        if (self.graphics_device) |*device| {
            if (self.swap_chain) |*swap_chain| {
                if (self.back_buffer) |*buffer| {
                    const presented_index = buffer.buffer_index;
                    _ = swap_chain.renderClear(device, buffer, .{
                        .width = width,
                        .height = height,
                        .clear_color = Backend.initial_clear_color,
                    }) catch {
                        return .failed;
                    };
                    const renderer = if (self.composition_renderer) |*value| value else {
                        return .failed;
                    };
                    const resource = buffer.resource orelse {
                        return .failed;
                    };
                    renderer.draw(@ptrCast(resource), width, height, raw.GetDpiForWindow(window)) catch |err| return switch (err) {
                        error.DeviceLost => .device_lost,
                        else => .failed,
                    };
                    const present_request = presentRequestForState(
                        configuredSwapEffect(),
                        self.window_state.needs_full_redraw,
                        self.buffer_history_valid[presented_index],
                        width,
                        height,
                    );
                    const outcome = swap_chain.presentAndRebind(device, buffer, present_request) catch |err| return switch (err) {
                        // A successful Present1 followed by a failed buffer
                        // reacquisition leaves the owner empty.  Treat that
                        // same as device loss so the caller rebuilds the
                        // complete device-dependent graph instead of
                        // repeatedly attempting to render without a target.
                        error.RebindFailed,
                        error.NextBackBufferIndexUnavailable,
                        error.InvalidBackBufferIndex,
                        => .device_lost,
                        else => .failed,
                    };
                    if (outcome == .presented or outcome == .occluded) self.emitRenderTelemetry(width, height);
                    switch (outcome) {
                        .presented => {
                            self.buffer_history_valid[presented_index] = true;
                            self.window_state.framePresented();
                        },
                        .occluded => _ = self.window_state.apply(.occluded),
                        .device_removed, .device_reset, .device_hung => self.window_state.invalidate(),
                    }
                    return switch (outcome) {
                        .presented => .presented,
                        .occluded => .occluded,
                        .device_removed, .device_reset, .device_hung => .device_lost,
                    };
                }
            }
        }
        return .failed;
    }

    fn emitRenderTelemetry(self: *Backend, width: u32, height: u32) void {
        const provider = &(self.telemetry_provider orelse return);
        var qpc: i64 = 0;
        if (raw.QueryPerformanceCounter(&qpc) == 0 or qpc <= 0) return;
        const pixels = std.math.mul(u64, width, height) catch return;
        const render_path: telemetry.RenderPath = if (self.graphics_device) |device|
            if (device.path == .warp) .warp else .hardware
        else
            .hardware;
        provider.write(.{
            .trial_id = self.trace_trial,
            .process_id = raw.GetCurrentProcessId(),
            .thread_id = raw.GetCurrentThreadId(),
            .qpc = @intCast(qpc),
            .adapter_luid = if (self.graphics_device) |device| device.adapter_luid else 0,
            .render_path = render_path,
            .width = width,
            .height = height,
            .dirty_pixels = pixels,
            .version = 1,
        }) catch |err| {
            self.telemetry_state = .write_failed;
            self.telemetry_error = err;
            return;
        };
        self.telemetry_event_count +%= 1;
    }

    fn emitTelemetrySnapshot(self: *Backend) void {
        const window = self.window orelse return;
        var client: RECT = undefined;
        if (raw.GetClientRect(window, &client) == 0) return;
        const width_i = client.right - client.left;
        const height_i = client.bottom - client.top;
        if (width_i <= 0 or height_i <= 0) return;
        self.emitRenderTelemetry(@intCast(width_i), @intCast(height_i));
    }

    pub fn renderFrame(self: *Backend) bool {
        self.requestFrame();
        // The DXGI frame-latency grant is part of every caller-requested
        // render. A bounded wait avoids a startup/rebind race where the grant
        // has not yet been published; the event-loop ticker remains
        // non-blocking when it is only polling an already-signaled handle.
        return self.waitAndRender(1_000, true);
    }

    fn renderInitialFrame(self: *Backend) bool {
        return self.waitAndRender(1_000, false);
    }

    fn handleWaitFailure(self: *Backend, failure: presenter.WaitError, recover: bool) bool {
        self.failFrame(classifyWaitFailure(failure), recover);
        if (!recover) return false;
        return self.rebuildFrameResources();
    }

    fn waitAndRender(self: *Backend, timeout_ms: u32, recover: bool) bool {
        if (!self.window_state.canRender()) return false;
        if (self.swap_chain) |*swap_chain| {
            switch (swap_chain.waitForFrame(timeout_ms) catch |failure| {
                return self.handleWaitFailure(failure, recover);
            }) {
                .signaled => {},
                // A caller asking for a frame must not treat a timeout as a
                // displayed frame: this path is used before first show and
                // after resource rebuilds.
                .timeout => return false,
            }
        } else {
            self.failFrame(.missing_frame_resources, recover);
            if (recover) return self.rebuildFrameResources();
            return false;
        }
        return switch (self.renderFrameOnce()) {
            .presented => blk: {
                self.completeFrame(false);
                break :blk true;
            },
            .occluded => blk: {
                self.completeFrame(true);
                break :blk true;
            },
            .device_lost => blk: {
                self.failFrame(.device_lost, recover);
                break :blk if (recover) self.rebuildFrameResources() else false;
            },
            .failed => blk: {
                self.failFrame(.render_failed, recover);
                break :blk false;
            },
        };
    }

    pub fn hasFrameResources(self: *const Backend) bool {
        return self.graphics_device != null and self.swap_chain != null and self.back_buffer != null;
    }

    pub fn compositionReady(self: *const Backend) bool {
        return if (self.composition_renderer) |renderer| renderer.ready() else false;
    }

    pub fn compositionFrameCount(self: *const Backend) u64 {
        return if (self.composition_renderer) |renderer| renderer.frameCount() else 0;
    }

    pub fn actualSwapChainDescriptor(self: *const Backend) !presenter.NativeDescriptor {
        const swap_chain = self.swap_chain orelse return error.InvalidSwapChain;
        return swap_chain.actualDescriptor();
    }

    pub fn tickFrame(self: *Backend) bool {
        if (!self.window_state.canRender()) return false;
        if (self.swap_chain) |*swap_chain| {
            switch (swap_chain.waitForFrame(0) catch |failure| return self.handleWaitFailure(failure, true)) {
                .signaled => return self.renderFrameSignaled(),
                // A posted/requested tick may legitimately find no grant yet;
                // keep the message loop alive without rendering stale data.
                .timeout => return true,
            }
        }
        self.failFrame(.missing_frame_resources, true);
        return self.rebuildFrameResources();
    }

    pub fn requestFrame(self: *Backend) void {
        self.frame_lifecycle.request();
    }

    fn renderFrameSignaled(self: *Backend) bool {
        if (!self.window_state.canRender()) return false;
        return switch (self.renderFrameOnce()) {
            .presented => blk: {
                self.completeFrame(false);
                break :blk true;
            },
            .occluded => blk: {
                self.completeFrame(true);
                break :blk true;
            },
            .device_lost => blk: {
                self.failFrame(.device_lost, true);
                break :blk self.rebuildFrameResources();
            },
            .failed => blk: {
                self.failFrame(.render_failed, true);
                break :blk false;
            },
        };
    }

    pub fn resizeFrame(self: *Backend, width: u32, height: u32) bool {
        if (width == 0 or height == 0) return false;
        if (self.graphics_device) |*device| {
            if (self.swap_chain) |*swap_chain| {
                if (self.back_buffer) |*buffer| {
                    // ResizeBuffers invalidates every reference to the old
                    // swap-chain surface. Retire the D2D/DWrite graph first,
                    // then recreate it against the same admitted device only
                    // after the new canonical back buffer has been acquired.
                    if (self.composition_renderer) |*renderer| {
                        renderer.deinit();
                        self.composition_renderer = null;
                    }
                    const outcome = swap_chain.resizeAndRebind(device, buffer, .{
                        .width = width,
                        .height = height,
                    }) catch {
                        // resizeAndRebind releases the old owner before
                        // calling ResizeBuffers. Any failure leaves the
                        // composition graph retired and may leave the slot
                        // empty, so recover the complete device-dependent
                        // graph instead of leaving a visible shell that can
                        // never render again.
                        return self.rebuildFrameResources();
                    };
                    return switch (outcome) {
                        .resized => blk: {
                            // ResizeBuffers creates new contents for both
                            // sequential targets.  The old history is not a
                            // valid dirty-rect baseline for either target.
                            self.buffer_history_valid = .{ false, false };
                            self.window_state.invalidate();
                            const renderer = composition.Renderer.init(device) catch {
                                break :blk self.rebuildFrameResources();
                            };
                            self.composition_renderer = renderer;
                            break :blk self.renderFrame();
                        },
                        .device_removed, .device_reset, .device_hung => self.rebuildFrameResources(),
                    };
                }
            }
        }
        return false;
    }

    /// Retained as a compatibility probe for old QA callers.  Rendering is
    /// now event-driven and owns no periodic timer.
    pub fn frameTimerActive(_: *const Backend) bool {
        return false;
    }

    /// Retire the current native frame owner and recreate the device, swap
    /// chain, and canonical buffer. Hardware is preferred when it was the
    /// previous path; WARP is admitted as the deterministic fallback.
    pub fn rebuildFrameResources(self: *Backend) bool {
        self.requestFrame();
        const window = self.window orelse {
            self.failFrame(.rebuild_failed, true);
            return false;
        };
        const preferred_path = if (self.graphics_device) |device| device.path else .hardware;
        self.releaseFrameResources();

        var paths = [_]graphics.DevicePath{ .hardware, .warp };
        var path_count: usize = paths.len;
        if (preferred_path == .warp) {
            paths[0] = .warp;
            path_count = 1;
        } else {
            paths[0] = preferred_path;
        }

        for (paths[0..path_count]) |path| {
            const candidate = createFrameResources(window, path) catch continue;
            self.graphics_device = candidate.device;
            self.swap_chain = candidate.swap_chain;
            self.back_buffer = candidate.back_buffer;
            self.composition_renderer = candidate.composition_renderer;
            if (self.renderInitialFrame()) return true;
            self.releaseFrameResources();
        }
        self.failFrame(.rebuild_failed, true);
        return false;
    }

    fn releaseFrameResources(self: *Backend) void {
        // D2D/DWrite resources reference the current DXGI device/surface and
        // must be retired before the back buffer or D3D11 device is released.
        if (self.composition_renderer) |*renderer| {
            renderer.deinit();
            self.composition_renderer = null;
        }
        if (self.back_buffer) |*buffer| {
            if (self.swap_chain) |*swap_chain| {
                if (self.graphics_device) |*device| {
                    _ = swap_chain.retireBackBuffer(device, buffer) catch buffer.deinit();
                } else buffer.deinit();
            } else buffer.deinit();
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
        self.buffer_history_valid = .{ false, false };
    }

    pub fn destroyWindow(self: *Backend) bool {
        var ok = true;
        self.frame_lifecycle.cancel();
        self.qos_state.deinit();
        self.destroyShellControls();
        self.releaseFrameResources();
        if (self.telemetry_provider) |*provider| {
            provider.tryDeinit() catch |err| {
                // Keep the provider handle for a subsequent retry. Reporting a
                // cleanup failure is safer than claiming release while the OS
                // still owns the registration.
                self.telemetry_state = .teardown_failed;
                self.telemetry_error = err;
                ok = false;
            };
            if (!provider.isRegistered()) {
                self.telemetry_provider = null;
                if (ok) {
                    self.telemetry_state = .disabled;
                    self.telemetry_error = null;
                }
            }
        }
        const window = self.window orelse return ok;
        // DefWindowProc handles WM_CLOSE and may already have destroyed it.
        if (raw.IsWindow(window) == 0) {
            self.forgetShellControls();
            self.window = null;
            return ok;
        }
        const destroyed = raw.DestroyWindow(window) != 0;
        if (!destroyed) ok = false;
        if (destroyed) {
            self.forgetShellControls();
            self.window = null;
        } else {
            self.window = windowAfterDestroy(window, false, raw.IsWindow(window) != 0);
        }
        return ok;
    }
    pub fn showWindow(self: *Backend) void {
        // ShowWindow's return reports previous visibility, not success/failure.
        _ = raw.ShowWindow(self.window.?, self.show);
    }
    pub fn getMessage(self: *Backend) i32 {
        // When work is pending, wait atomically for either the DXGI grant or
        // input.  With no pending work we use the same blocking message path;
        // there is no polling/render timer.
        if (self.frame_lifecycle.pending and self.window_state.canRender()) {
            if (self.swap_chain) |*swap_chain| {
                const handle = swap_chain.waitableHandle() orelse {
                    self.failFrame(.invalid_wait_handle, true);
                    return if (self.rebuildFrameResources()) raw.GetMessageW(&self.message, null, 0, 0) else -1;
                };
                var handles = [_]?*anyopaque{handle};
                const wait = raw.MsgWaitForMultipleObjectsEx(
                    1,
                    &handles,
                    std.math.maxInt(u32),
                    0x04ff, // QS_ALLINPUT
                    0x0004, // MWMO_INPUTAVAILABLE
                );
                if (wait == wait_object_0) {
                    self.message = .{ .hwnd = self.window, .message = frame_signal_message, .wParam = 0, .lParam = 0, .time = 0, .pt = .{ .x = 0, .y = 0 } };
                    return 1;
                }
                if (wait != 1) {
                    self.failFrame(classifyMessageWaitFailure(wait), true);
                    return if (self.rebuildFrameResources()) raw.GetMessageW(&self.message, null, 0, 0) else -1;
                }
            }
        }
        // No HWND filter: WM_QUIT remains valid after the main HWND is gone.
        // The portable loop distinguishes -1 (error), 0 (quit), >0 (dispatch).
        return raw.GetMessageW(&self.message, null, 0, 0);
    }
    pub fn dispatchMessage(self: *Backend) void {
        const latency_sensitive = isFrameSignalMessage(self.message.message) or
            isLatencySensitiveMessage(self.message.message);
        if (latency_sensitive) self.qos_state.enterForeground();
        defer if (latency_sensitive) self.qos_state.leaveForeground();
        if (isFrameSignalMessage(self.message.message)) {
            _ = self.renderFrameSignaled();
            return;
        }
        if (self.accelerators != null and raw.TranslateAcceleratorW(self.window.?, self.accelerators, &self.message) != 0) return;
        _ = raw.TranslateMessage(&self.message);
        _ = raw.DispatchMessageW(&self.message);
    }
};

fn isLatencySensitiveMessage(message: u32) bool {
    return switch (message) {
        0x0100...0x0109, // keyboard and character input
        0x0200...0x020e, // pointer input
        wm_size,
        wm_dpi_changed,
        wm_vscroll,
        => true,
        else => false,
    };
}

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
    if (backendForWindow(window)) |backend| {
        switch (classifyWindowMessage(message, wparam)) {
            .paint => {
                _ = raw.ValidateRect(window, null);
                backend.applyWindowStateEvent(.paint);
                return 0;
            },
            .minimized => {
                backend.applyWindowStateEvent(.minimized);
                return 0;
            },
            .resize => {
                const size_bits: usize = @as(usize, @bitCast(lparam));
                const width: u32 = @intCast(size_bits & 0xffff);
                const height: u32 = @intCast((size_bits >> 16) & 0xffff);
                backend.applyWindowStateEvent(.resize);
                if (width != 0 and height != 0) {
                    if (backend.hasShellControls()) _ = backend.relayoutControls(width, height);
                    if (backend.window_state.canRender() and backend.hasFrameResources()) _ = backend.resizeFrame(width, height);
                }
                return 0;
            },
            .dpi_changed => {
                backend.handleDpiChanged(wparam, lparam);
                return 0;
            },
            .shown => {
                backend.applyWindowStateEvent(.shown);
                backend.refreshShellLayout();
                return raw.DefWindowProcW(window, message, wparam, lparam);
            },
            .hidden => {
                backend.applyWindowStateEvent(.hidden);
                return raw.DefWindowProcW(window, message, wparam, lparam);
            },
            .activated => {
                backend.applyWindowStateEvent(.activated);
                return raw.DefWindowProcW(window, message, wparam, lparam);
            },
            .deactivated => {
                backend.applyWindowStateEvent(.deactivated);
                return raw.DefWindowProcW(window, message, wparam, lparam);
            },
            .display_changed => {
                backend.applyWindowStateEvent(.display_changed);
                backend.refreshShellLayout();
                return raw.DefWindowProcW(window, message, wparam, lparam);
            },
            .resumed => {
                backend.applyWindowStateEvent(.resumed);
                backend.refreshShellLayout();
                return 1;
            },
            .other => {},
        }
    }
    if (message == wm_command) {
        if (backendForWindow(window)) |backend| {
            const command_id: u16 = @intCast(wparam & 0xffff);
            if (command_id == control_id_mode) {
                backend.mode_checked = !backend.mode_checked;
                if (backend.mode_control) |mode| {
                    _ = raw.SendMessageW(mode, bm_setcheck, if (backend.mode_checked) 1 else 0, 0);
                }
                backend.updateSemanticMode();
                backend.requestFrame();
                return 0;
            }
            if (command_id >= control_id_open_folder and command_id <= control_id_recovery) {
                // The command bridge deliberately stays side-effect free in
                // this slice; future workspace actions consume the stable IDs.
                backend.requestFrame();
                return 0;
            }
        }
    }
    if (message == wm_vscroll) {
        if (backendForWindow(window)) |backend| {
            if (backend.splitter_control) |splitter| {
                if (lparam != 0 and @as(usize, @bitCast(lparam)) == @intFromPtr(splitter)) {
                    backend.requestFrame();
                }
            }
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
