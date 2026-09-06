//! The only TExFlow-owned entry point for the pinned zigwin32 snapshot.  Keep
//! the generated package behind this narrow facade: product code never imports
//! the root package or `everything.zig` directly.  Non-Windows builds retain a
//! declaration-only surface so portable contracts can compile without a
//! Windows binding module.
const builtin = @import("builtin");

const bound = builtin.os.tag == .windows;
const zigwin32 = if (bound) @import("zigwin32") else struct {};

pub const d3d11 = if (bound) zigwin32.graphics.direct3d11 else struct {};
pub const direct3d = if (bound) zigwin32.graphics.direct3d else struct {};
pub const dxgi = if (bound) zigwin32.graphics.dxgi else struct {};
pub const direct2d = if (bound) zigwin32.graphics.direct2d else struct {};
pub const direct2d_common = if (bound) zigwin32.graphics.direct2d.common else struct {};
pub const direct_write = if (bound) zigwin32.graphics.direct_write else struct {};
pub const accessibility = if (bound) zigwin32.ui.accessibility else struct {};
pub const foundation = if (bound) zigwin32.foundation else struct {};
pub const com = if (bound) zigwin32.system.com else struct {};
pub const d3d11_dll = if (bound) zigwin32.d3d11 else struct {};
pub const dxgi_dll = if (bound) zigwin32.dxgi else struct {};
pub const d2d1_dll = if (bound) struct {
    pub const D2D1CreateDevice = zigwin32.d2d1.D2D1CreateDevice;
} else struct {};
pub const dwrite_dll = if (bound) struct {
    pub const DWriteCreateFactory = zigwin32.dwrite.DWriteCreateFactory;
} else struct {};
pub const ole32_dll = if (bound) struct {
    pub const CoCreateInstance = zigwin32.ole32.CoCreateInstance;
} else struct {};
pub const oleaut32_dll = if (bound) struct {
    pub const SysFreeString = zigwin32.oleaut32.SysFreeString;
} else struct {};
// Keep the composition thread-affinity probe separate from the presenter
// wait facade. Each native adapter gets only the one kernel32 symbol it
// needs, so adding Direct2D ownership checks does not widen presenter ABI.
pub const composition_kernel32 = if (bound) struct {
    pub const GetCurrentThreadId = zigwin32.kernel32.GetCurrentThreadId;
} else struct {};
// Keep the kernel32 surface declaration-level narrow: presenter_native only
// needs this one wait primitive, not the generated DLL namespace.
pub const kernel32 = if (bound) struct {
    pub const WaitForSingleObject = zigwin32.kernel32.WaitForSingleObject;
} else struct {};

pub const Namespace = enum {
    foundation,
    com,
    windows_and_messaging,
    keyboard_and_mouse,
    gdi,
    direct3d11,
    dxgi,
    dxgi_common,
    direct2d,
    direct2d_common,
    direct_write,
    dwm,
    imaging,
    security,
    threading,
    pipes,
    job_objects,
    etw,
    accessibility,
};

pub const namespace_allowlist: []const Namespace = &.{
    .foundation,
    .com,
    .windows_and_messaging,
    .keyboard_and_mouse,
    .gdi,
    .direct3d11,
    .dxgi,
    .dxgi_common,
    .direct2d,
    .direct2d_common,
    .direct_write,
    .dwm,
    .imaging,
    .security,
    .threading,
    .pipes,
    .job_objects,
    .etw,
    .accessibility,
};

pub fn sourcePath(namespace: Namespace) []const u8 {
    return switch (namespace) {
        .foundation => "win32/foundation.zig",
        .com => "win32/system/com.zig",
        .windows_and_messaging => "win32/ui/windows_and_messaging.zig",
        .keyboard_and_mouse => "win32/ui/input/keyboard_and_mouse.zig",
        .gdi => "win32/graphics/gdi.zig",
        .direct3d11 => "win32/graphics/direct3d11.zig",
        .dxgi => "win32/graphics/dxgi.zig",
        .dxgi_common => "win32/graphics/dxgi/common.zig",
        .direct2d => "win32/graphics/direct2d.zig",
        .direct2d_common => "win32/graphics/direct2d/common.zig",
        .direct_write => "win32/graphics/direct_write.zig",
        .dwm => "win32/graphics/dwm.zig",
        .imaging => "win32/graphics/imaging.zig",
        .security => "win32/security.zig",
        .threading => "win32/system/threading.zig",
        .pipes => "win32/system/pipes.zig",
        .job_objects => "win32/system/job_objects.zig",
        .etw => "win32/system/diagnostics/etw.zig",
        .accessibility => "win32/ui/accessibility.zig",
    };
}
