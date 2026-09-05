//! Declarative inventory for the future verified zigwin32 adapter. No binding
//! package, loader, COM activation, or runtime behavior is admitted by this file.
//! SDK ABI/layout/vtable/GUID probes and the content-hash gate remain separate
//! T0.2b obligations before namespaces can become actual imported bindings.
pub const Namespace = enum {
    foundation,
    com,
    windows_and_messaging,
    keyboard_and_mouse,
    gdi,
    direct3d11,
    dxgi,
    dxgi_common,
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
