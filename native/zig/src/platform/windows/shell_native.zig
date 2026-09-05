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
const layout = @import("app_layout");
const strings = @import("app_strings");
const graphics = @import("graphics");
const presenter = @import("presenter_native");
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

pub const dll_search_flags: u32 = 0x800; // LOAD_LIBRARY_SEARCH_SYSTEM32
pub const window_style: u32 = 0xcf0000; // WS_OVERLAPPEDWINDOW, system caption
pub const dpi_pmv2: *anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -4))));
pub const frame_signal_message: u32 = 0x8001; // WM_APP + 1, private frame grant

/// The build selects the admitted baseline explicitly.  A discard build is a
/// reproducible challenger and is never chosen from adapter/runtime state.
pub fn configuredSwapEffect() graphics.SwapEffect {
    return if (presenter_config.use_discard) .flip_discard else .flip_sequential;
}
const wm_nccreate: u32 = 0x0081;
const wm_ncdestroy: u32 = 0x0082;
const wm_destroy: u32 = 0x0002;
const wm_size: u32 = 0x0005;
const wm_paint: u32 = 0x000f;
const wm_command: u32 = 0x0111;
const size_minimized: usize = 1;
const gwlp_userdata: i32 = -21;
const ws_child: u32 = 0x40000000;
const ws_visible: u32 = 0x10000000;
const ws_tabstop: u32 = 0x00010000;
const ws_group: u32 = 0x00020000;
const ws_ex_transparent: u32 = 0x00000020;
const bs_pushbutton: u32 = 0x00000000;
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
const class_name = std.unicode.utf8ToUtf16LeStringLiteral(role.ui_identity.machine_class);
const window_title = std.unicode.utf8ToUtf16LeStringLiteral(role.ui_identity.product_name);

pub fn renderOutcomeUsable(outcome: presenter.PresentOutcome) bool {
    return outcome == .presented or outcome == .occluded;
}

const FrameAttempt = enum {
    presented,
    occluded,
    device_lost,
    failed,
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
    extern "user32" fn SetWindowTextW(HWND, [*:0]const u16) callconv(.winapi) i32;
    extern "user32" fn ShowWindow(HWND, i32) callconv(.winapi) i32;
    extern "user32" fn MoveWindow(HWND, i32, i32, i32, i32, i32) callconv(.winapi) i32;
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
    compile_control: ?HWND = null,
    save_control: ?HWND = null,
    recovery_control: ?HWND = null,
    project_label: ?HWND = null,
    source_label: ?HWND = null,
    pdf_label: ?HWND = null,
    status_label: ?HWND = null,
    status_value: ?HWND = null,
    accelerators: ?*anyopaque = null,
    recovery_visible: bool = false,
    graphics_device: ?graphics.Device = null,
    swap_chain: ?presenter.SwapChain = null,
    back_buffer: ?presenter.BackBuffer = null,
    frame_pending: bool = false,
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
        self.compile_control = null;
        self.save_control = null;
        self.recovery_control = null;
        self.project_label = null;
        self.source_label = null;
        self.pdf_label = null;
        self.status_label = null;
        self.status_value = null;
        self.recovery_visible = false;
    }

    fn destroyShellControls(self: *Backend) void {
        const children = [_]?HWND{
            self.open_folder_control,
            self.mode_control,
            self.compile_control,
            self.save_control,
            self.recovery_control,
            self.project_label,
            self.source_label,
            self.pdf_label,
            self.status_label,
            self.status_value,
        };
        for (children) |child| {
            if (child) |window| {
                if (raw.IsWindow(window) != 0) _ = raw.DestroyWindow(window);
            }
        }
        self.forgetShellControls();
    }

    fn createShellControls(self: *Backend) bool {
        if (self.window == null) return false;
        self.destroyShellControls();

        const button_style = ws_child | ws_visible | ws_tabstop | bs_pushbutton;
        const first_button_style = button_style | ws_group;
        const hidden_button_style = ws_child | ws_tabstop | bs_pushbutton;
        const label_style = ws_child | ws_visible | ss_left;

        self.open_folder_control = self.createChild(button_class, open_folder_title, 0, first_button_style, control_id_open_folder) orelse return false;
        self.mode_control = self.createChild(button_class, mode_title, 0, button_style, control_id_mode) orelse {
            self.forgetShellControls();
            return false;
        };
        self.compile_control = self.createChild(button_class, compile_title, 0, button_style, control_id_compile) orelse {
            self.forgetShellControls();
            return false;
        };
        self.save_control = self.createChild(button_class, save_title, 0, button_style, control_id_save) orelse {
            self.forgetShellControls();
            return false;
        };
        self.recovery_control = self.createChild(button_class, recovery_title, 0, hidden_button_style, control_id_recovery) orelse {
            self.forgetShellControls();
            return false;
        };
        self.project_label = self.createChild(static_class, project_title, ws_ex_transparent, label_style, 105) orelse {
            self.forgetShellControls();
            return false;
        };
        self.source_label = self.createChild(static_class, source_title, ws_ex_transparent, label_style, 106) orelse {
            self.forgetShellControls();
            return false;
        };
        self.pdf_label = self.createChild(static_class, pdf_title, ws_ex_transparent, label_style, 107) orelse {
            self.forgetShellControls();
            return false;
        };
        self.status_label = self.createChild(static_class, status_title, ws_ex_transparent, label_style, 108) orelse {
            self.forgetShellControls();
            return false;
        };
        self.status_value = self.createChild(static_class, ready_title, ws_ex_transparent, label_style, 109) orelse {
            self.forgetShellControls();
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
            self.forgetShellControls();
            return false;
        };
        self.recovery_visible = false;
        if (!self.relayoutControls(960, 640)) {
            self.forgetShellControls();
            return false;
        }
        return true;
    }

    fn pixelsToDip(pixels: u32, dpi: u32) u32 {
        const effective_dpi = if (dpi == 0) 96 else dpi;
        const value = (@as(u64, pixels) * 96 + effective_dpi / 2) / effective_dpi;
        if (value > std.math.maxInt(u32)) return std.math.maxInt(u32);
        return @intCast(value);
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
        const width = pixelsToDip(width_px, dpi);
        const height = pixelsToDip(height_px, dpi);
        const view = layout.for_window(width, height, false);
        const gap = layout.spacing_rhythm_dip;
        const toolbar_y = gap;
        const toolbar_height = layout.compact_control_max_dip;
        const content_top = toolbar_y + toolbar_height + gap;
        const label_height = layout.minimum_target_dip;
        const status_height = layout.status_rail_dip;
        const label_y = if (height > status_height + gap + label_height)
            content_top
        else if (height > label_height + gap)
            height - status_height - gap - label_height
        else
            0;

        if (!self.moveChild(self.open_folder_control, gap, toolbar_y, 120, toolbar_height, true, dpi)) return false;
        if (!self.moveChild(self.mode_control, gap + 120 + gap, toolbar_y, 116, toolbar_height, true, dpi)) return false;
        if (!self.moveChild(self.compile_control, gap + 120 + gap + 116 + gap, toolbar_y, 84, toolbar_height, true, dpi)) return false;
        if (!self.moveChild(self.save_control, gap + 120 + gap + 116 + gap + 84 + gap, toolbar_y, 72, toolbar_height, true, dpi)) return false;
        var source_x = gap;
        const divider = layout.visible_divider_dip;
        var source_width = if (width > gap * 2 + divider) width - gap * 2 - divider else 1;
        var pdf_x: u32 = 0;
        var pdf_width: u32 = 1;
        if (view.mode == .tri_canvas) {
            const fixed_chrome = gap * 2 + divider * 2;
            if (layout.allocate_tri_canvas(width, fixed_chrome)) |tri| {
                source_x = std.math.add(u32, gap + tri.project_dip, divider) catch return false;
                source_width = tri.source_dip;
                const source_end = std.math.add(u32, source_x, source_width) catch return false;
                pdf_x = std.math.add(u32, source_end, divider) catch return false;
                pdf_width = tri.pdf_dip;
            }
        } else if (layout.allocate_source_pdf(source_width)) |panes| {
            source_width = panes.source_dip;
            const source_end = std.math.add(u32, source_x, source_width) catch return false;
            pdf_x = std.math.add(u32, source_end, divider) catch return false;
            pdf_width = panes.pdf_dip;
        }

        const label_width = @min(@as(u32, 104), @max(source_width, 1));
        const project_width = if (view.mode == .tri_canvas) @min(@as(u32, 104), layout.project_min_dip) else 1;
        if (!self.moveChild(self.project_label, gap, label_y, project_width, label_height, view.project_visible, dpi)) return false;
        if (!self.moveChild(self.source_label, source_x, label_y, label_width, label_height, view.source_visible, dpi)) return false;
        if (!self.moveChild(self.pdf_label, pdf_x, label_y, @min(@as(u32, 104), @max(pdf_width, 1)), label_height, view.pdf_visible, dpi)) return false;

        const status_y = if (height > status_height) height - status_height else 0;
        const recovery_width: u32 = 92;
        const recovery_x = if (width > recovery_width + gap) width - recovery_width - gap else gap;
        const status_value_x = gap + 56;
        const status_value_end = if (self.recovery_visible and recovery_x > status_value_x + gap)
            recovery_x - gap
        else if (width > gap)
            width - gap
        else
            status_value_x + 1;
        const status_value_width = if (status_value_end > status_value_x) status_value_end - status_value_x else 1;
        if (!self.moveChild(self.status_label, gap, status_y, 48, status_height, true, dpi)) return false;
        if (!self.moveChild(self.status_value, status_value_x, status_y, status_value_width, status_height, true, dpi)) return false;
        if (!self.moveChild(self.recovery_control, recovery_x, status_y, recovery_width, status_height, self.recovery_visible, dpi)) return false;
        return true;
    }

    pub fn hasShellControls(self: *const Backend) bool {
        return self.open_folder_control != null and self.mode_control != null and
            self.compile_control != null and self.save_control != null and
            self.recovery_control != null and self.project_label != null and
            self.source_label != null and self.pdf_label != null and
            self.status_label != null and self.status_value != null and
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
            _ = raw.DestroyWindow(self.window.?);
            self.window = null;
            return false;
        }
        if (!self.createShellControls()) {
            self.forgetShellControls();
            _ = raw.DestroyWindow(self.window.?);
            self.window = null;
            return false;
        }
        var device = graphics.Device.create() catch {
            // A visible window without a render device is not an admitted UI
            // state.  Tear it down immediately so callers cannot observe a
            // half-initialized shell or accidentally fall back to GDI.
            _ = raw.DestroyWindow(self.window.?);
            self.forgetShellControls();
            self.window = null;
            return false;
        };
        var swap_chain = presenter.create(&device, @ptrCast(self.window.?), configuredSwapEffect()) catch {
            device.deinit();
            _ = raw.DestroyWindow(self.window.?);
            self.forgetShellControls();
            self.window = null;
            return false;
        };
        const back_buffer = swap_chain.acquireBackBuffer(&device, 0) catch {
            swap_chain.deinit();
            device.deinit();
            _ = raw.DestroyWindow(self.window.?);
            self.forgetShellControls();
            self.window = null;
            return false;
        };
        self.graphics_device = device;
        self.swap_chain = swap_chain;
        self.back_buffer = back_buffer;
        if (!self.renderInitialFrame()) {
            self.releaseFrameResources();
            _ = raw.DestroyWindow(self.window.?);
            self.forgetShellControls();
            self.window = null;
            return false;
        }
        return true;
    }

    /// The first-frame bridge is synchronous: a hidden window receives a
    /// complete clear + Present before it becomes visible, so the shell never
    /// exposes an uninitialized back buffer.
    fn renderFrameOnce(self: *Backend) FrameAttempt {
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
                    _ = swap_chain.renderClear(device, buffer, .{
                        .width = width,
                        .height = height,
                        .clear_color = Backend.initial_clear_color,
                    }) catch return .failed;
                    const outcome = swap_chain.presentAndRebind(device, buffer, .{}) catch return .failed;
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

    pub fn renderFrame(self: *Backend) bool {
        // The DXGI frame-latency grant is part of every caller-requested
        // render. A bounded wait avoids a startup/rebind race where the grant
        // has not yet been published; the event-loop ticker remains
        // non-blocking when it is only polling an already-signaled handle.
        return self.waitAndRender(1_000, true);
    }

    fn renderInitialFrame(self: *Backend) bool {
        return self.waitAndRender(1_000, false);
    }

    fn waitAndRender(self: *Backend, timeout_ms: u32, recover: bool) bool {
        if (self.swap_chain) |*swap_chain| {
            switch (swap_chain.waitForFrame(timeout_ms) catch return false) {
                .signaled => {},
                // A caller asking for a frame must not treat a timeout as a
                // displayed frame: this path is used before first show and
                // after resource rebuilds.
                .timeout => return false,
            }
        } else return false;
        return switch (self.renderFrameOnce()) {
            .presented, .occluded => blk: {
                self.frame_pending = false;
                break :blk true;
            },
            .device_lost => if (recover) self.rebuildFrameResources() else false,
            .failed => false,
        };
    }

    pub fn hasFrameResources(self: *const Backend) bool {
        return self.graphics_device != null and self.swap_chain != null and self.back_buffer != null;
    }

    pub fn tickFrame(self: *Backend) bool {
        if (self.swap_chain) |*swap_chain| {
            switch (swap_chain.waitForFrame(0) catch return false) {
                .signaled => return self.renderFrameSignaled(),
                // A posted/requested tick may legitimately find no grant yet;
                // keep the message loop alive without rendering stale data.
                .timeout => return true,
            }
        }
        return false;
    }

    pub fn requestFrame(self: *Backend) void {
        self.frame_pending = true;
    }

    fn renderFrameSignaled(self: *Backend) bool {
        self.frame_pending = false;
        return switch (self.renderFrameOnce()) {
            .presented, .occluded => true,
            .device_lost => self.rebuildFrameResources(),
            .failed => false,
        };
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
        const window = self.window orelse return false;
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
            var device = graphics.Device.createWithPath(path) catch continue;
            var swap_chain = presenter.create(&device, @ptrCast(window), configuredSwapEffect()) catch {
                device.deinit();
                continue;
            };
            const back_buffer = swap_chain.acquireBackBuffer(&device, 0) catch {
                swap_chain.deinit();
                device.deinit();
                continue;
            };
            self.graphics_device = device;
            self.swap_chain = swap_chain;
            self.back_buffer = back_buffer;
            if (self.renderInitialFrame()) return true;
            self.releaseFrameResources();
        }
        return false;
    }

    fn releaseFrameResources(self: *Backend) void {
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
    }

    pub fn destroyWindow(self: *Backend) bool {
        self.frame_pending = false;
        self.destroyShellControls();
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
    }
    pub fn getMessage(self: *Backend) i32 {
        // When work is pending, wait atomically for either the DXGI grant or
        // input.  With no pending work we use the same blocking message path;
        // there is no polling/render timer.
        if (self.frame_pending) {
            if (self.swap_chain) |*swap_chain| {
                if (swap_chain.waitableHandle()) |handle| {
                    var handles = [_]?*anyopaque{handle};
                    const wait = raw.MsgWaitForMultipleObjectsEx(
                        1,
                        &handles,
                        std.math.maxInt(u32),
                        0x04ff, // QS_ALLINPUT
                        0x0004, // MWMO_INPUTAVAILABLE
                    );
                    if (wait == 0) {
                        self.message = .{ .hwnd = self.window, .message = frame_signal_message, .wParam = 0, .lParam = 0, .time = 0, .pt = .{ .x = 0, .y = 0 } };
                        return 1;
                    }
                    if (wait != 1) return -1;
                }
            }
        }
        // No HWND filter: WM_QUIT remains valid after the main HWND is gone.
        // The portable loop distinguishes -1 (error), 0 (quit), >0 (dispatch).
        return raw.GetMessageW(&self.message, null, 0, 0);
    }
    pub fn dispatchMessage(self: *Backend) void {
        if (isFrameSignalMessage(self.message.message)) {
            _ = self.renderFrameSignaled();
            return;
        }
        if (self.accelerators != null and raw.TranslateAcceleratorW(self.window.?, self.accelerators, &self.message) != 0) return;
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
            backend.requestFrame();
            return 0;
        }
    }
    if (message == wm_size) {
        if (wparam != size_minimized) {
            if (backendForWindow(window)) |backend| {
                const size_bits: usize = @as(usize, @bitCast(lparam));
                const width: u32 = @intCast(size_bits & 0xffff);
                const height: u32 = @intCast((size_bits >> 16) & 0xffff);
                if (backend.hasShellControls() and width != 0 and height != 0) _ = backend.relayoutControls(width, height);
                if (backend.hasFrameResources() and width != 0 and height != 0) _ = backend.resizeFrame(width, height);
                return 0;
            }
        }
    }
    if (message == wm_command) {
        if (backendForWindow(window)) |backend| {
            const command_id: u16 = @intCast(wparam & 0xffff);
            if (command_id >= control_id_open_folder and command_id <= control_id_recovery) {
                // The command bridge deliberately stays side-effect free in
                // this slice; future workspace actions consume the stable IDs.
                backend.requestFrame();
                return 0;
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
