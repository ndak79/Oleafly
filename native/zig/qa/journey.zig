//! Independent Windows journey primitives for the T0.2c QA lane.
//!
//! This module is deliberately small: it discovers a visible top-level window
//! for a known process, validates its physical bounds/DPI, probes the UIA root,
//! and sends keyboard input through SendInput.  It does not inspect or invent
//! pixels.  A QPC marker is evidence only for ordering; visible-state proof
//! still requires a successful post-marker DXGI capture.

const builtin = @import("builtin");
const std = @import("std");
const contract = @import("capture_contract");
const com = @import("windows_com");

pub const Error = error{
    UnsupportedTarget,
    UnsupportedArchitecture,
    ClockUnavailable,
    InvalidProcess,
    InvalidWindow,
    WindowNotVisible,
    ProcessMismatch,
    DwmBoundsUnavailable,
    InvalidDpi,
    InputUnavailable,
    InputFailed,
    UiAutomationUnavailable,
    AutomationElementUnavailable,
    UiAutomationActionUnavailable,
    UiAutomationStateDidNotChange,
    InvalidMarker,
    StaleDisplayedFrame,
};

/// A native HWND represented as an integer so the public surface is portable.
pub const WindowTarget = struct {
    hwnd: usize,
    process_id: u32,
};

pub const WindowInfo = struct {
    hwnd: usize,
    process_id: u32,
    bounds: contract.Rect,
    dpi: u16,
};

pub const Marker = struct {
    sequence: u64,
    qpc: u64,
};

pub const UiAutomationSummary = struct {
    elements: u32 = 0,
    buttons: u32 = 0,
    text: u32 = 0,
    invoke_patterns: u32 = 0,
    toggle_patterns: u32 = 0,
    range_value_patterns: u32 = 0,
    keyboard_focusable: u32 = 0,
    focused: u32 = 0,
    offscreen: u32 = 0,
    open_folder: bool = false,
    mode: bool = false,
    mode_on: bool = false,
    mode_off: bool = false,
    compile: bool = false,
    save: bool = false,
    project: bool = false,
    source: bool = false,
    pdf: bool = false,
    splitter: bool = false,
    status: bool = false,
    ready: bool = false,
};

pub const KeyStroke = struct {
    virtual_key: u16,
    key_up: bool = false,
    extended: bool = false,
};

pub fn qpc() Error!u64 {
    return windows.qpc();
}

pub fn qpcFrequency() Error!u64 {
    return windows.qpcFrequency();
}

pub fn findWindowForProcess(process_id: u32) Error!WindowInfo {
    if (process_id == 0) return error.InvalidProcess;
    return windows.findWindowForProcess(process_id);
}

pub fn inspectWindow(target: WindowTarget) Error!WindowInfo {
    if (target.hwnd == 0 or target.process_id == 0) return error.InvalidWindow;
    return windows.inspectWindow(target);
}

pub fn sendKey(window: WindowInfo, stroke: KeyStroke) Error!void {
    if (stroke.virtual_key == 0) return error.InputFailed;
    const current = try inspectWindow(.{ .hwnd = window.hwnd, .process_id = window.process_id });
    if (current.process_id != window.process_id) return error.ProcessMismatch;
    return windows.sendKey(current, stroke);
}

/// Record a QPC marker after the caller has armed capture and immediately
/// before its state mutation.  This marker is never a substitute for pixels.
pub fn mark(sequence: u64) Error!Marker {
    if (sequence == 0) return error.InvalidMarker;
    return .{ .sequence = sequence, .qpc = try qpc() };
}

/// Accept a displayed-frame timestamp only when it is strictly newer than the
/// mutation marker.  The timestamp must come from DXGI frame metadata, not a
/// fixture or a timer recorded after the input call.
pub fn requirePostMarker(marker: Marker, displayed_qpc: u64) Error!void {
    if (marker.sequence == 0 or marker.qpc == 0 or displayed_qpc == 0) return error.InvalidMarker;
    if (displayed_qpc <= marker.qpc) return error.StaleDisplayedFrame;
}

/// Probe the UI Automation root associated with the exact HWND.  This is a
/// capability check only; callers must enumerate/assert the required tree
/// separately before treating a journey as complete.
pub fn probeUiAutomation(window: WindowInfo) Error!void {
    const current = try inspectWindow(.{ .hwnd = window.hwnd, .process_id = window.process_id });
    if (current.process_id != window.process_id) return error.ProcessMismatch;
    return windows.probeUiAutomation(current);
}

pub fn enumerateUiAutomation(window: WindowInfo) Error!UiAutomationSummary {
    const current = try inspectWindow(.{ .hwnd = window.hwnd, .process_id = window.process_id });
    if (current.process_id != window.process_id) return error.ProcessMismatch;
    return windows.enumerateUiAutomation(current);
}

/// Invoke one named standard control from a separately compiled QA process.
/// The name is matched inside the product PID's UIA subtree, so a coincident
/// control from another process cannot satisfy the action proof.
pub fn invokeUiAutomation(window: WindowInfo, name: []const u8) Error!void {
    if (name.len == 0) return error.UiAutomationActionUnavailable;
    const current = try inspectWindow(.{ .hwnd = window.hwnd, .process_id = window.process_id });
    if (current.process_id != window.process_id) return error.ProcessMismatch;
    return windows.invokeUiAutomation(current, name);
}

/// Toggle one named standard control from a separately compiled QA process.
/// The action is issued through UIA's TogglePattern, so a later state read can
/// prove that the UI mutation, rather than a synthetic keyboard shortcut,
/// caused the change.
pub fn toggleUiAutomation(window: WindowInfo, name: []const u8) Error!void {
    if (name.len == 0) return error.UiAutomationActionUnavailable;
    const current = try inspectWindow(.{ .hwnd = window.hwnd, .process_id = window.process_id });
    if (current.process_id != window.process_id) return error.ProcessMismatch;
    return windows.toggleUiAutomation(current, name);
}

const windows = if (builtin.os.tag == .windows) struct {
    const api = @import("windows_api");

    const EnumWindowsProc = *const fn (?api.foundation.HWND, isize) callconv(.winapi) i32;

    extern "user32" fn EnumWindows(callback: EnumWindowsProc, lparam: isize) callconv(.winapi) i32;
    extern "user32" fn IsWindowVisible(hwnd: api.foundation.HWND) callconv(.winapi) i32;
    extern "user32" fn GetWindowThreadProcessId(hwnd: api.foundation.HWND, process_id: *u32) callconv(.winapi) u32;
    extern "user32" fn GetDpiForWindow(hwnd: api.foundation.HWND) callconv(.winapi) u32;
    extern "user32" fn SetForegroundWindow(hwnd: api.foundation.HWND) callconv(.winapi) i32;
    extern "user32" fn SendInput(count: u32, inputs: *const RawInput, size: i32) callconv(.winapi) u32;
    extern "kernel32" fn QueryPerformanceCounter(value: *i64) callconv(.winapi) i32;
    extern "kernel32" fn QueryPerformanceFrequency(value: *i64) callconv(.winapi) i32;

    const KEYBOARD_INPUT: u32 = 1;
    const KEYEVENTF_EXTENDEDKEY: u32 = 0x0001;
    const KEYEVENTF_KEYUP: u32 = 0x0002;

    // INPUT is intentionally declared locally because the TExFlow Windows
    // facade does not expose the broad keyboard_and_mouse namespace.
    const RawKeybdInput = extern struct {
        wVk: u16,
        wScan: u16,
        dwFlags: u32,
        time: u32,
        dwExtraInfo: usize,
    };

    const RawInput = extern struct {
        input_type: u32,
        data: extern union {
            keyboard: RawKeybdInput,
            padding: [32]u8,
        },
    };

    const FindContext = struct {
        process_id: u32,
        hwnd: ?api.foundation.HWND = null,
    };

    fn failed(result: anytype) bool {
        return result.failed;
    }

    fn hwndFromInt(value: usize) api.foundation.HWND {
        return @ptrFromInt(value);
    }

    fn hwndToInt(value: api.foundation.HWND) usize {
        return @intFromPtr(value);
    }

    fn qpc() Error!u64 {
        if (builtin.cpu.arch != .x86_64) return error.UnsupportedArchitecture;
        var value: i64 = 0;
        if (QueryPerformanceCounter(&value) == 0 or value <= 0) return error.ClockUnavailable;
        return @intCast(value);
    }

    fn qpcFrequency() Error!u64 {
        if (builtin.cpu.arch != .x86_64) return error.UnsupportedArchitecture;
        var value: i64 = 0;
        if (QueryPerformanceFrequency(&value) == 0 or value <= 0) return error.ClockUnavailable;
        return @intCast(value);
    }

    fn enumWindow(hwnd: ?api.foundation.HWND, raw_lparam: isize) callconv(.winapi) i32 {
        const context: *FindContext = @ptrFromInt(@as(usize, @bitCast(raw_lparam)));
        const candidate = hwnd orelse return 1;
        if (context.hwnd != null or IsWindowVisible(candidate) == 0) return 1;

        var process_id: u32 = 0;
        if (GetWindowThreadProcessId(candidate, &process_id) == 0) return 1;
        if (process_id != context.process_id) return 1;

        context.hwnd = candidate;
        return 0;
    }

    fn findWindowForProcess(process_id: u32) Error!WindowInfo {
        if (builtin.cpu.arch != .x86_64) return error.UnsupportedArchitecture;
        var context = FindContext{ .process_id = process_id };
        const lparam: isize = @bitCast(@intFromPtr(&context));
        _ = EnumWindows(enumWindow, lparam);
        const hwnd = context.hwnd orelse return error.InvalidWindow;
        return @This().inspectWindow(.{ .hwnd = hwndToInt(hwnd), .process_id = process_id });
    }

    fn inspectWindow(target: WindowTarget) Error!WindowInfo {
        if (builtin.cpu.arch != .x86_64) return error.UnsupportedArchitecture;
        if (target.hwnd == 0 or target.process_id == 0) return error.InvalidWindow;
        const hwnd = hwndFromInt(target.hwnd);
        if (IsWindowVisible(hwnd) == 0) return error.WindowNotVisible;

        var process_id: u32 = 0;
        if (GetWindowThreadProcessId(hwnd, &process_id) == 0) return error.InvalidWindow;
        if (process_id != target.process_id) return error.ProcessMismatch;

        var rect: api.foundation.RECT = undefined;
        const dwm_result = api.dwmapi.DwmGetWindowAttribute(
            hwnd,
            api.dwm.DWMWA_EXTENDED_FRAME_BOUNDS,
            @ptrCast(&rect),
            @intCast(@sizeOf(api.foundation.RECT)),
        );
        if (failed(dwm_result)) return error.DwmBoundsUnavailable;
        if (rect.right <= rect.left or rect.bottom <= rect.top) return error.DwmBoundsUnavailable;

        const dpi_raw = GetDpiForWindow(hwnd);
        const dpi = std.math.cast(u16, dpi_raw) orelse return error.InvalidDpi;
        if (dpi == 0) return error.InvalidDpi;
        _ = contract.dip_to_physical(1, dpi) catch return error.InvalidDpi;

        return .{
            .hwnd = target.hwnd,
            .process_id = process_id,
            .bounds = .{
                .left = rect.left,
                .top = rect.top,
                .right = rect.right,
                .bottom = rect.bottom,
            },
            .dpi = dpi,
        };
    }

    fn sendKey(window: WindowInfo, stroke: KeyStroke) Error!void {
        const hwnd = hwndFromInt(window.hwnd);
        if (SetForegroundWindow(hwnd) == 0) return error.InputUnavailable;

        var flags: u32 = 0;
        if (stroke.extended) flags |= KEYEVENTF_EXTENDEDKEY;
        if (stroke.key_up) flags |= KEYEVENTF_KEYUP;

        const input = RawInput{
            .input_type = KEYBOARD_INPUT,
            .data = .{ .keyboard = .{
                .wVk = stroke.virtual_key,
                .wScan = 0,
                .dwFlags = flags,
                .time = 0,
                .dwExtraInfo = 0,
            } },
        };
        if (SendInput(1, &input, @intCast(@sizeOf(RawInput))) != 1) return error.InputFailed;
    }

    fn probeUiAutomation(window: WindowInfo) Error!void {
        if (!com.initializeSta()) return error.UiAutomationUnavailable;
        defer com.uninitialize();

        var automation_raw: ?*anyopaque = null;
        const automation_result = api.ole32_dll.CoCreateInstance(
            api.accessibility.CLSID_CUIAutomation,
            null,
            api.com.CLSCTX_INPROC_SERVER,
            api.accessibility.IID_IUIAutomation,
            @ptrCast(&automation_raw),
        );
        if (failed(automation_result) or automation_raw == null) return error.UiAutomationUnavailable;

        const automation: *api.accessibility.IUIAutomation = @ptrCast(@alignCast(automation_raw.?));
        defer _ = automation.IUnknown.Release();

        var element: ?*api.accessibility.IUIAutomationElement = null;
        const element_result = automation.ElementFromHandle(
            hwndFromInt(window.hwnd),
            @ptrCast(&element),
        );
        if (failed(element_result) or element == null) return error.AutomationElementUnavailable;
        _ = element.?.IUnknown.Release();
    }

    fn freeUiaString(value: ?*u16) void {
        if (value) |string| api.oleaut32_dll.SysFreeString(string);
    }

    fn uiaStringEquals(value: ?*u16, expected: []const u8) bool {
        const string = value orelse return false;
        const units = std.mem.span(@as([*:0]const u16, @ptrCast(string)));
        if (units.len != expected.len) return false;
        for (units, expected) |unit, byte| if (unit != byte) return false;
        return true;
    }

    fn hasPattern(element: *api.accessibility.IUIAutomationElement, pattern_id: api.accessibility.UIA_PATTERN_ID) bool {
        var pattern: ?*api.com.IUnknown = null;
        const result = element.GetCurrentPattern(pattern_id, @ptrCast(&pattern));
        if (result.failed or pattern == null) return false;
        _ = pattern.?.Release();
        return true;
    }

    fn currentToggleState(element: *api.accessibility.IUIAutomationElement) ?api.accessibility.ToggleState {
        var pattern: ?*api.com.IUnknown = null;
        const result = element.GetCurrentPattern(api.accessibility.UIA_PATTERN_ID.TogglePatternId, @ptrCast(&pattern));
        if (result.failed or pattern == null) return null;
        defer _ = pattern.?.Release();
        const toggle: *api.accessibility.IUIAutomationTogglePattern = @ptrCast(@alignCast(pattern.?));
        var state: api.accessibility.ToggleState = undefined;
        if (toggle.get_CurrentToggleState(&state).failed) return null;
        return state;
    }

    fn enumerateUiAutomation(window: WindowInfo) Error!UiAutomationSummary {
        if (!com.initializeSta()) return error.UiAutomationUnavailable;
        defer com.uninitialize();

        var automation_raw: ?*anyopaque = null;
        const automation_result = api.ole32_dll.CoCreateInstance(
            api.accessibility.CLSID_CUIAutomation,
            null,
            api.com.CLSCTX_INPROC_SERVER,
            api.accessibility.IID_IUIAutomation,
            @ptrCast(&automation_raw),
        );
        if (automation_result.failed or automation_raw == null) return error.UiAutomationUnavailable;
        const automation: *api.accessibility.IUIAutomation = @ptrCast(@alignCast(automation_raw.?));
        defer _ = automation.IUnknown.Release();

        var root: ?*api.accessibility.IUIAutomationElement = null;
        if (automation.ElementFromHandle(
            @ptrFromInt(window.hwnd),
            @ptrCast(&root),
        ).failed or root == null) return error.AutomationElementUnavailable;
        defer _ = root.?.IUnknown.Release();

        var root_pid: i32 = 0;
        if (root.?.get_CurrentProcessId(&root_pid).failed or root_pid != @as(i32, @intCast(window.process_id))) {
            return error.ProcessMismatch;
        }

        var condition: ?*api.accessibility.IUIAutomationCondition = null;
        if (automation.CreateTrueCondition(@ptrCast(&condition)).failed or condition == null) {
            return error.UiAutomationUnavailable;
        }
        defer _ = condition.?.IUnknown.Release();

        var elements: ?*api.accessibility.IUIAutomationElementArray = null;
        if (root.?.FindAll(api.accessibility.TreeScope_Descendants, condition, @ptrCast(&elements)).failed or elements == null) {
            return error.UiAutomationUnavailable;
        }
        defer _ = elements.?.IUnknown.Release();

        var length: i32 = 0;
        if (elements.?.get_Length(&length).failed or length < 0) return error.UiAutomationUnavailable;
        var summary = UiAutomationSummary{};
        for (0..@intCast(length)) |index| {
            var element: ?*api.accessibility.IUIAutomationElement = null;
            if (elements.?.GetElement(@intCast(index), @ptrCast(&element)).failed or element == null) {
                return error.AutomationElementUnavailable;
            }
            defer _ = element.?.IUnknown.Release();

            var process_id: i32 = 0;
            var control_type: api.accessibility.UIA_CONTROLTYPE_ID = undefined;
            var enabled: i32 = 0;
            var offscreen: i32 = 0;
            var bounds: api.foundation.RECT = undefined;
            if (element.?.get_CurrentProcessId(&process_id).failed or
                element.?.get_CurrentControlType(&control_type).failed or
                element.?.get_CurrentIsEnabled(&enabled).failed or
                element.?.get_CurrentIsOffscreen(&offscreen).failed or
                element.?.get_CurrentBoundingRectangle(&bounds).failed)
            {
                return error.UiAutomationUnavailable;
            }
            if (process_id != @as(i32, @intCast(window.process_id))) return error.ProcessMismatch;
            if (offscreen != 0) {
                summary.offscreen += 1;
            } else if (bounds.right <= bounds.left or bounds.bottom <= bounds.top) {
                return error.InvalidWindow;
            }
            if (enabled == 0 and offscreen == 0) return error.UiAutomationUnavailable;

            var name: ?*u16 = null;
            defer freeUiaString(name);
            if (element.?.get_CurrentName(&name).failed) return error.UiAutomationUnavailable;
            summary.elements += 1;
            switch (control_type) {
                api.accessibility.UIA_ButtonControlTypeId => {
                    summary.buttons += 1;
                    if (hasPattern(element.?, api.accessibility.UIA_PATTERN_ID.InvokePatternId)) summary.invoke_patterns += 1;
                },
                api.accessibility.UIA_CheckBoxControlTypeId => {
                    summary.buttons += 1;
                    if (hasPattern(element.?, api.accessibility.UIA_PATTERN_ID.TogglePatternId)) summary.toggle_patterns += 1;
                },
                api.accessibility.UIA_SliderControlTypeId, api.accessibility.UIA_SeparatorControlTypeId, api.accessibility.UIA_ScrollBarControlTypeId => {
                    if (hasPattern(element.?, api.accessibility.UIA_PATTERN_ID.RangeValuePatternId)) summary.range_value_patterns += 1;
                },
                api.accessibility.UIA_TextControlTypeId => summary.text += 1,
                else => {},
            }

            var keyboard_focusable: i32 = 0;
            if (element.?.get_CurrentIsKeyboardFocusable(&keyboard_focusable).failed) return error.UiAutomationUnavailable;
            if (keyboard_focusable != 0) summary.keyboard_focusable += 1;
            var focused: i32 = 0;
            if (element.?.get_CurrentHasKeyboardFocus(&focused).failed) return error.UiAutomationUnavailable;
            if (focused != 0) summary.focused += 1;

            summary.open_folder = summary.open_folder or uiaStringEquals(name, "Open Folder");
            summary.mode = summary.mode or uiaStringEquals(name, "Render mode");
            if (uiaStringEquals(name, "Render mode")) {
                if (currentToggleState(element.?)) |state| switch (state) {
                    .On => summary.mode_on = true,
                    .Off => summary.mode_off = true,
                    else => {},
                };
            }
            summary.compile = summary.compile or uiaStringEquals(name, "Compile");
            summary.save = summary.save or uiaStringEquals(name, "Save");
            summary.project = summary.project or uiaStringEquals(name, "Project");
            summary.source = summary.source or uiaStringEquals(name, "Source");
            summary.pdf = summary.pdf or uiaStringEquals(name, "PDF");
            summary.splitter = summary.splitter or uiaStringEquals(name, "Resize panes");
            summary.status = summary.status or uiaStringEquals(name, "Status");
            summary.ready = summary.ready or uiaStringEquals(name, "Ready");
        }
        return summary;
    }

    fn invokeUiAutomation(window: WindowInfo, expected_name: []const u8) Error!void {
        if (!com.initializeSta()) return error.UiAutomationUnavailable;
        defer com.uninitialize();

        var automation_raw: ?*anyopaque = null;
        const automation_result = api.ole32_dll.CoCreateInstance(
            api.accessibility.CLSID_CUIAutomation,
            null,
            api.com.CLSCTX_INPROC_SERVER,
            api.accessibility.IID_IUIAutomation,
            @ptrCast(&automation_raw),
        );
        if (failed(automation_result) or automation_raw == null) return error.UiAutomationUnavailable;
        const automation: *api.accessibility.IUIAutomation = @ptrCast(@alignCast(automation_raw.?));
        defer _ = automation.IUnknown.Release();

        var root: ?*api.accessibility.IUIAutomationElement = null;
        if (automation.ElementFromHandle(hwndFromInt(window.hwnd), @ptrCast(&root)).failed or root == null) {
            return error.AutomationElementUnavailable;
        }
        defer _ = root.?.IUnknown.Release();

        var condition: ?*api.accessibility.IUIAutomationCondition = null;
        if (automation.CreateTrueCondition(@ptrCast(&condition)).failed or condition == null) {
            return error.UiAutomationUnavailable;
        }
        defer _ = condition.?.IUnknown.Release();

        var elements: ?*api.accessibility.IUIAutomationElementArray = null;
        if (root.?.FindAll(api.accessibility.TreeScope_Descendants, condition, @ptrCast(&elements)).failed or elements == null) {
            return error.UiAutomationUnavailable;
        }
        defer _ = elements.?.IUnknown.Release();

        var length: i32 = 0;
        if (elements.?.get_Length(&length).failed or length < 0) return error.UiAutomationUnavailable;
        for (0..@intCast(length)) |index| {
            var element: ?*api.accessibility.IUIAutomationElement = null;
            if (elements.?.GetElement(@intCast(index), @ptrCast(&element)).failed or element == null) {
                return error.AutomationElementUnavailable;
            }
            defer _ = element.?.IUnknown.Release();

            var name: ?*u16 = null;
            defer freeUiaString(name);
            if (element.?.get_CurrentName(&name).failed or !uiaStringEquals(name, expected_name)) continue;

            var pattern: ?*api.com.IUnknown = null;
            const pattern_result = element.?.GetCurrentPattern(
                api.accessibility.UIA_PATTERN_ID.InvokePatternId,
                @ptrCast(&pattern),
            );
            if (pattern_result.failed or pattern == null) return error.UiAutomationActionUnavailable;
            defer _ = pattern.?.Release();
            const invoke: *api.accessibility.IUIAutomationInvokePattern = @ptrCast(@alignCast(pattern.?));
            if (invoke.Invoke().failed) return error.UiAutomationActionUnavailable;
            return;
        }
        return error.UiAutomationActionUnavailable;
    }

    fn toggleUiAutomation(window: WindowInfo, expected_name: []const u8) Error!void {
        if (!com.initializeSta()) return error.UiAutomationUnavailable;
        defer com.uninitialize();

        var automation_raw: ?*anyopaque = null;
        const automation_result = api.ole32_dll.CoCreateInstance(
            api.accessibility.CLSID_CUIAutomation,
            null,
            api.com.CLSCTX_INPROC_SERVER,
            api.accessibility.IID_IUIAutomation,
            @ptrCast(&automation_raw),
        );
        if (failed(automation_result) or automation_raw == null) return error.UiAutomationUnavailable;
        const automation: *api.accessibility.IUIAutomation = @ptrCast(@alignCast(automation_raw.?));
        defer _ = automation.IUnknown.Release();

        var root: ?*api.accessibility.IUIAutomationElement = null;
        if (automation.ElementFromHandle(hwndFromInt(window.hwnd), @ptrCast(&root)).failed or root == null) {
            return error.AutomationElementUnavailable;
        }
        defer _ = root.?.IUnknown.Release();

        var condition: ?*api.accessibility.IUIAutomationCondition = null;
        if (automation.CreateTrueCondition(@ptrCast(&condition)).failed or condition == null) {
            return error.UiAutomationUnavailable;
        }
        defer _ = condition.?.IUnknown.Release();

        var elements: ?*api.accessibility.IUIAutomationElementArray = null;
        if (root.?.FindAll(api.accessibility.TreeScope_Descendants, condition, @ptrCast(&elements)).failed or elements == null) {
            return error.UiAutomationUnavailable;
        }
        defer _ = elements.?.IUnknown.Release();

        var length: i32 = 0;
        if (elements.?.get_Length(&length).failed or length < 0) return error.UiAutomationUnavailable;
        for (0..@intCast(length)) |index| {
            var element: ?*api.accessibility.IUIAutomationElement = null;
            if (elements.?.GetElement(@intCast(index), @ptrCast(&element)).failed or element == null) {
                return error.AutomationElementUnavailable;
            }
            defer _ = element.?.IUnknown.Release();

            var process_id: i32 = 0;
            if (element.?.get_CurrentProcessId(&process_id).failed or process_id != @as(i32, @intCast(window.process_id))) {
                return error.ProcessMismatch;
            }
            var name: ?*u16 = null;
            defer freeUiaString(name);
            if (element.?.get_CurrentName(&name).failed or !uiaStringEquals(name, expected_name)) continue;

            var pattern: ?*api.com.IUnknown = null;
            const pattern_result = element.?.GetCurrentPattern(
                api.accessibility.UIA_PATTERN_ID.TogglePatternId,
                @ptrCast(&pattern),
            );
            if (pattern_result.failed or pattern == null) return error.UiAutomationActionUnavailable;
            defer _ = pattern.?.Release();
            const toggle: *api.accessibility.IUIAutomationTogglePattern = @ptrCast(@alignCast(pattern.?));
            if (toggle.Toggle().failed) return error.UiAutomationActionUnavailable;
            return;
        }
        return error.UiAutomationActionUnavailable;
    }
} else struct {
    fn qpc() Error!u64 {
        return error.UnsupportedTarget;
    }

    fn qpcFrequency() Error!u64 {
        return error.UnsupportedTarget;
    }

    fn findWindowForProcess(_: u32) Error!WindowInfo {
        return error.UnsupportedTarget;
    }

    fn inspectWindow(_: WindowTarget) Error!WindowInfo {
        return error.UnsupportedTarget;
    }

    fn sendKey(_: WindowInfo, _: KeyStroke) Error!void {
        return error.UnsupportedTarget;
    }

    fn probeUiAutomation(_: WindowInfo) Error!void {
        return error.UnsupportedTarget;
    }

    fn enumerateUiAutomation(_: WindowInfo) Error!UiAutomationSummary {
        return error.UnsupportedTarget;
    }

    fn invokeUiAutomation(_: WindowInfo, _: []const u8) Error!void {
        return error.UnsupportedTarget;
    }

    fn toggleUiAutomation(_: WindowInfo, _: []const u8) Error!void {
        return error.UnsupportedTarget;
    }
};

test "portable journey marker rejects stale display timestamps" {
    try std.testing.expectError(
        error.StaleDisplayedFrame,
        requirePostMarker(.{ .sequence = 1, .qpc = 10 }, 10),
    );
    try std.testing.expectError(
        error.InvalidMarker,
        requirePostMarker(.{ .sequence = 0, .qpc = 10 }, 11),
    );
}
