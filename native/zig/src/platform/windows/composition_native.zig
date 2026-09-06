//! Direct2D/DirectWrite composition bridge for the TExFlow shell.
//!
//! The renderer is deliberately small and UI-thread owned.  It creates one
//! D2D device/context and one DWrite factory/format from the admitted D3D11
//! device, then wraps the current DXGI back-buffer surface for each frame.
//! The temporary bitmap/surface references never escape a draw call.
const builtin = @import("builtin");
const std = @import("std");
const api = @import("windows_api");
const graphics = @import("graphics");
const role = @import("app_role");
const layout = @import("app_layout");
const strings = @import("app_strings");

pub const max_extent: u32 = std.math.maxInt(i32);
pub const d2derr_recreate_target: u32 = 0x8899_000c;
pub const dxgi_error_device_hung: u32 = 0x887a_0006;
pub const dxgi_error_device_removed: u32 = 0x887a_0005;
pub const dxgi_error_device_reset: u32 = 0x887a_0007;
pub const dxgi_error_driver_internal_error: u32 = 0x887a_0020;

pub const TargetFormat = enum(u32) {
    rgba8_unorm = 28,
    bgra8_unorm = 87,
};

pub const AlphaMode = enum(u32) {
    unknown = 0,
    premultiplied = 1,
    ignore = 3,
};

pub const TargetProperties = struct {
    format: TargetFormat,
    alpha_mode: AlphaMode,
    dpi_x: f32,
    dpi_y: f32,
};

pub const DrawOutcome = enum {
    drawn,
    device_lost,
    failed,
};

/// The D2D target is addressed in device-independent pixels (DIPs).  The
/// shell's child controls use the same values, so this geometry is the one
/// shared source of truth for the painted chrome and native control bounds.
pub const Geometry = struct {
    width_dip: u32,
    height_dip: u32,
    toolbar_bottom_dip: u32,
    status_top_dip: u32,
    project_right_dip: u32,
    source_left_dip: u32,
    source_right_dip: u32,
    pdf_left_dip: u32,
    pdf_right_dip: u32,
    project_visible: bool,
    source_visible: bool,
    pdf_visible: bool,
};

pub const Error = error{
    UnsupportedTarget,
    InvalidDevice,
    InvalidResource,
    InvalidExtent,
    DxgiDeviceUnavailable,
    D2dDeviceCreationFailed,
    DeviceContextCreationFailed,
    TextFactoryCreationFailed,
    TextFormatCreationFailed,
    BrushCreationFailed,
    WrongThread,
    SurfaceUnavailable,
    TargetBitmapCreationFailed,
    EndDrawFailed,
    DeviceLost,
};

pub fn validateExtent(width: u32, height: u32) Error!void {
    if (width == 0 or height == 0 or width > max_extent or height > max_extent) {
        return error.InvalidExtent;
    }
}

pub fn targetProperties(dpi: u32) TargetProperties {
    const effective_dpi = if (dpi == 0) 96 else dpi;
    const value: f32 = @floatFromInt(effective_dpi);
    return .{
        .format = .bgra8_unorm,
        .alpha_mode = .premultiplied,
        .dpi_x = value,
        .dpi_y = value,
    };
}

/// Convert physical target pixels to the rounded DIP coordinates used by the
/// native shell.  Keeping this conversion in the composition bridge prevents
/// high-DPI frames from treating pixels as DIPs after SetDpi().
pub fn pixelsToDip(pixels: u32, dpi: u32) u32 {
    if (pixels == 0) return 0;
    const effective_dpi = if (dpi == 0) 96 else dpi;
    const value = (@as(u64, pixels) * 96 + effective_dpi / 2) / effective_dpi;
    if (value == 0) return 1;
    if (value > max_extent) return max_extent;
    return @intCast(value);
}

pub fn frameGeometry(width_px: u32, height_px: u32, dpi: u32) Error!Geometry {
    try validateExtent(width_px, height_px);
    return geometryForDip(pixelsToDip(width_px, dpi), pixelsToDip(height_px, dpi));
}

fn geometryForDip(width: u32, height: u32) Geometry {
    const view = layout.for_window(width, height, false);
    const gap = layout.spacing_rhythm_dip;
    const toolbar_bottom = @min(height, gap + layout.compact_control_max_dip + gap);
    const status_top = if (height > layout.status_rail_dip)
        height - layout.status_rail_dip
    else
        0;

    var project_right: u32 = 0;
    var source_left: u32 = @min(gap, width);
    // Dual/tri modes reserve a divider between Source and PDF. Focus and
    // unsupported reflow modes hide PDF, so Source receives the full content
    // width instead of inheriting a divider that has no visible pane on the
    // other side. Keep this value shared by the shell and painter to prevent
    // another layer from subtracting the left gap twice.
    const content_width = if (view.pdf_visible)
        if (width > gap * 2 + layout.visible_divider_dip)
            width - gap * 2 - layout.visible_divider_dip
        else
            0
    else if (width > gap * 2)
        width - gap * 2
    else
        0;
    var source_right: u32 = @min(width, source_left + content_width);
    var pdf_left: u32 = 0;
    var pdf_right: u32 = 1;
    const divider = layout.visible_divider_dip;

    if (view.mode == .tri_canvas) {
        const fixed_chrome = gap * 2 + divider * 2;
        if (layout.allocate_tri_canvas(width, fixed_chrome)) |tri| {
            project_right = gap + tri.project_dip;
            source_left = project_right + divider;
            source_right = source_left + tri.source_dip;
            pdf_left = source_right + divider;
            pdf_right = pdf_left + tri.pdf_dip;
        }
    } else if (view.pdf_visible) {
        if (layout.allocate_source_pdf(content_width)) |panes| {
            source_right = @min(width, source_left + panes.source_dip);
            pdf_left = source_right + divider;
            pdf_right = @min(width, pdf_left + panes.pdf_dip);
        }
    }

    return .{
        .width_dip = width,
        .height_dip = height,
        .toolbar_bottom_dip = toolbar_bottom,
        .status_top_dip = status_top,
        .project_right_dip = project_right,
        .source_left_dip = source_left,
        .source_right_dip = source_right,
        .pdf_left_dip = pdf_left,
        .pdf_right_dip = pdf_right,
        .project_visible = view.project_visible,
        .source_visible = view.source_visible,
        .pdf_visible = view.pdf_visible,
    };
}

pub fn mapEndDrawResult(hresult: u32) DrawOutcome {
    if (hresult == 0) return .drawn;
    if (isDeviceLostHresult(hresult)) return .device_lost;
    return .failed;
}

pub fn isDeviceLostHresult(hresult: u32) bool {
    return hresult == d2derr_recreate_target or
        hresult == dxgi_error_device_hung or
        hresult == dxgi_error_device_removed or
        hresult == dxgi_error_device_reset or
        hresult == dxgi_error_driver_internal_error;
}

pub const Renderer = struct {
    d2d_device: if (builtin.os.tag == .windows) ?*api.direct2d.ID2D1Device else ?*anyopaque = null,
    d2d_context: if (builtin.os.tag == .windows) ?*api.direct2d.ID2D1DeviceContext else ?*anyopaque = null,
    dwrite_factory: if (builtin.os.tag == .windows) ?*api.direct_write.IDWriteFactory else ?*anyopaque = null,
    text_format: if (builtin.os.tag == .windows) ?*api.direct_write.IDWriteTextFormat else ?*anyopaque = null,
    background_brush: if (builtin.os.tag == .windows) ?*api.direct2d.ID2D1SolidColorBrush else ?*anyopaque = null,
    pane_brush: if (builtin.os.tag == .windows) ?*api.direct2d.ID2D1SolidColorBrush else ?*anyopaque = null,
    divider_brush: if (builtin.os.tag == .windows) ?*api.direct2d.ID2D1SolidColorBrush else ?*anyopaque = null,
    accent_brush: if (builtin.os.tag == .windows) ?*api.direct2d.ID2D1SolidColorBrush else ?*anyopaque = null,
    text_brush: if (builtin.os.tag == .windows) ?*api.direct2d.ID2D1SolidColorBrush else ?*anyopaque = null,
    // Borrowed for GetDeviceRemovedReason only; graphics.Device remains the
    // owner and is retired after this renderer in the shell.
    d3d_device: if (builtin.os.tag == .windows) ?*api.d3d11.ID3D11Device else ?*anyopaque = null,
    owner_thread_id: u32 = 0,
    frame_count: u64 = 0,

    pub fn init(device: *const graphics.Device) Error!Renderer {
        if (builtin.os.tag != .windows) return error.UnsupportedTarget;
        return initWindows(device);
    }

    pub fn ready(self: *const Renderer) bool {
        return self.d2d_device != null and self.d2d_context != null and
            self.dwrite_factory != null and self.text_format != null and
            self.background_brush != null and self.pane_brush != null and
            self.divider_brush != null and self.accent_brush != null and
            self.text_brush != null;
    }

    pub fn frameCount(self: *const Renderer) u64 {
        return self.frame_count;
    }

    pub fn ownerThreadId(self: *const Renderer) u32 {
        return self.owner_thread_id;
    }

    /// Draw the current shell frame into an acquired D3D11 back-buffer
    /// resource.  The resource is borrowed for this call; no COM reference is
    /// retained after the temporary DXGI surface/bitmap are released.
    pub fn draw(self: *Renderer, resource: ?*anyopaque, width: u32, height: u32, dpi: u32) Error!void {
        if (builtin.os.tag != .windows) return error.UnsupportedTarget;
        if (self.owner_thread_id != api.composition_kernel32.GetCurrentThreadId()) return error.WrongThread;
        try validateExtent(width, height);
        if (!self.ready()) return error.InvalidDevice;
        const resource_handle = resource orelse return error.InvalidResource;
        const context = self.d2d_context orelse return error.InvalidDevice;
        const d3d_resource: *api.d3d11.ID3D11Resource = @ptrCast(@alignCast(resource_handle));

        var surface_raw: ?*anyopaque = null;
        const query_result = d3d_resource.IUnknown.QueryInterface(
            api.dxgi.IID_IDXGISurface,
            @ptrCast(&surface_raw),
        );
        if (query_result.failed) {
            if (surface_raw) |partial_surface_raw| {
                const partial_surface: *api.dxgi.IDXGISurface = @ptrCast(@alignCast(partial_surface_raw));
                _ = partial_surface.IUnknown.Release();
            }
            if (isDeviceLostHresult(@bitCast(query_result)) or deviceLost(self)) return error.DeviceLost;
            return error.SurfaceUnavailable;
        }
        if (surface_raw == null) return error.SurfaceUnavailable;
        const surface: *api.dxgi.IDXGISurface = @ptrCast(@alignCast(surface_raw.?));
        defer _ = surface.IUnknown.Release();

        const properties = targetProperties(dpi);
        const geometry = try frameGeometry(width, height, dpi);
        const bitmap_properties = api.direct2d.D2D1_BITMAP_PROPERTIES1{
            .pixelFormat = .{
                .format = @enumFromInt(@intFromEnum(properties.format)),
                .alphaMode = @enumFromInt(@intFromEnum(properties.alpha_mode)),
            },
            .dpiX = properties.dpi_x,
            .dpiY = properties.dpi_y,
            .bitmapOptions = .{ .TARGET = 1, .CANNOT_DRAW = 1 },
            .colorContext = null,
        };
        var bitmap: ?*api.direct2d.ID2D1Bitmap1 = null;
        const bitmap_result = context.CreateBitmapFromDxgiSurface(surface, &bitmap_properties, @ptrCast(&bitmap));
        if (bitmap_result.failed) {
            if (bitmap) |partial_bitmap| _ = partial_bitmap.IUnknown.Release();
            if (isDeviceLostHresult(@bitCast(bitmap_result)) or deviceLost(self)) return error.DeviceLost;
            return error.TargetBitmapCreationFailed;
        }
        if (bitmap == null) return error.TargetBitmapCreationFailed;
        defer _ = bitmap.?.IUnknown.Release();

        context.SetTarget(@ptrCast(bitmap.?));
        defer context.SetTarget(null);
        const render_target: *const api.direct2d.ID2D1RenderTarget = &context.ID2D1RenderTarget;
        render_target.SetDpi(properties.dpi_x, properties.dpi_y);
        render_target.BeginDraw();

        const width_f: f32 = @floatFromInt(geometry.width_dip);
        const height_f: f32 = @floatFromInt(geometry.height_dip);
        const toolbar_bottom: f32 = @floatFromInt(geometry.toolbar_bottom_dip);
        const status_top: f32 = @floatFromInt(geometry.status_top_dip);
        const project_right: f32 = @floatFromInt(geometry.project_right_dip);
        const source_left: f32 = @floatFromInt(geometry.source_left_dip);
        const source_right: f32 = @floatFromInt(geometry.source_right_dip);
        const pdf_left: f32 = @floatFromInt(geometry.pdf_left_dip);
        const pdf_right: f32 = @floatFromInt(geometry.pdf_right_dip);

        fill(render_target, .{ .left = 0, .top = 0, .right = width_f, .bottom = toolbar_bottom }, self.pane_brush.?);
        if (geometry.project_visible) {
            fill(render_target, .{ .left = 0, .top = toolbar_bottom, .right = project_right, .bottom = status_top }, self.pane_brush.?);
        }
        fill(render_target, .{ .left = source_left, .top = toolbar_bottom, .right = source_right, .bottom = status_top }, self.background_brush.?);
        if (geometry.pdf_visible) {
            fill(render_target, .{ .left = pdf_left, .top = toolbar_bottom, .right = pdf_right, .bottom = status_top }, self.pane_brush.?);
        }
        fill(render_target, .{ .left = 0, .top = status_top, .right = width_f, .bottom = height_f }, self.pane_brush.?);
        if (geometry.project_visible) {
            fill(render_target, .{ .left = source_left - 1.0, .top = toolbar_bottom, .right = source_left + 1.0, .bottom = status_top }, self.divider_brush.?);
        }
        if (geometry.pdf_visible) {
            fill(render_target, .{ .left = pdf_left - 1.0, .top = toolbar_bottom, .right = pdf_left + 1.0, .bottom = status_top }, self.divider_brush.?);
        }
        fill(render_target, .{ .left = 0, .top = toolbar_bottom - 1.0, .right = width_f, .bottom = toolbar_bottom + 1.0 }, self.accent_brush.?);

        const title = std.unicode.utf8ToUtf16LeStringLiteral(role.ui_identity.product_name);
        // Standard Win32 child controls are the authoritative accessible
        // source for Project/Source/PDF/Status/Ready and the toolbar labels.
        // Paint only the product mark in unused toolbar space; duplicating
        // those captions here would produce two visual/accessibility sources.
        // The native toolbar occupies x=12..440 DIPs. Keep the optional mark
        // strictly to its right; at compact/unsupported widths the rectangle
        // is empty instead of painting over an interactive child control.
        const title_left = if (width_f >= 640.0) @max(452.0, width_f - 180.0) else width_f;
        drawText(render_target, title, .{ .left = title_left, .top = 12.0, .right = width_f - 12.0, .bottom = 42.0 }, self.text_brush.?, self.text_format.?);

        const end_result = render_target.EndDraw(null, null);
        switch (mapEndDrawResult(@bitCast(end_result))) {
            .drawn => self.frame_count +%= 1,
            .device_lost => return error.DeviceLost,
            .failed => if (deviceLost(self)) return error.DeviceLost else return error.EndDrawFailed,
        }
    }

    pub fn deinit(self: *Renderer) void {
        if (builtin.os.tag != .windows) {
            self.clearPortable();
            return;
        }
        if (self.text_brush) |value| {
            _ = value.IUnknown.Release();
            self.text_brush = null;
        }
        if (self.accent_brush) |value| {
            _ = value.IUnknown.Release();
            self.accent_brush = null;
        }
        if (self.divider_brush) |value| {
            _ = value.IUnknown.Release();
            self.divider_brush = null;
        }
        if (self.pane_brush) |value| {
            _ = value.IUnknown.Release();
            self.pane_brush = null;
        }
        if (self.background_brush) |value| {
            _ = value.IUnknown.Release();
            self.background_brush = null;
        }
        if (self.text_format) |value| {
            _ = value.IUnknown.Release();
            self.text_format = null;
        }
        if (self.dwrite_factory) |value| {
            _ = value.IUnknown.Release();
            self.dwrite_factory = null;
        }
        if (self.d2d_context) |value| {
            _ = value.IUnknown.Release();
            self.d2d_context = null;
        }
        if (self.d2d_device) |value| {
            _ = value.IUnknown.Release();
            self.d2d_device = null;
        }
        self.d3d_device = null;
        self.owner_thread_id = 0;
        self.frame_count = 0;
    }

    fn clearPortable(self: *Renderer) void {
        self.d2d_device = null;
        self.d2d_context = null;
        self.dwrite_factory = null;
        self.text_format = null;
        self.background_brush = null;
        self.pane_brush = null;
        self.divider_brush = null;
        self.accent_brush = null;
        self.text_brush = null;
        self.d3d_device = null;
        self.owner_thread_id = 0;
        self.frame_count = 0;
    }
};

fn initWindows(device: *const graphics.Device) Error!Renderer {
    const device_handle = device.deviceHandle() orelse return error.InvalidDevice;
    const d3d_device: *api.d3d11.ID3D11Device = @ptrCast(@alignCast(device_handle));

    var dxgi_raw: ?*anyopaque = null;
    const query_result = d3d_device.IUnknown.QueryInterface(api.dxgi.IID_IDXGIDevice, @ptrCast(&dxgi_raw));
    if (query_result.failed or dxgi_raw == null) {
        if (dxgi_raw) |partial_dxgi_raw| {
            const partial_dxgi: *api.dxgi.IDXGIDevice = @ptrCast(@alignCast(partial_dxgi_raw));
            _ = partial_dxgi.IUnknown.Release();
        }
        return error.DxgiDeviceUnavailable;
    }
    const dxgi_device: *api.dxgi.IDXGIDevice = @ptrCast(@alignCast(dxgi_raw.?));
    defer _ = dxgi_device.IUnknown.Release();

    const creation_properties = api.direct2d.D2D1_CREATION_PROPERTIES{
        .threadingMode = api.direct2d.D2D1_THREADING_MODE.SINGLE_THREADED,
        .debugLevel = api.direct2d.D2D1_DEBUG_LEVEL.NONE,
        .options = api.direct2d.D2D1_DEVICE_CONTEXT_OPTIONS_NONE,
    };
    var d2d_device: ?*api.direct2d.ID2D1Device = null;
    const d2d_result = api.d2d1_dll.D2D1CreateDevice(dxgi_device, &creation_properties, @ptrCast(&d2d_device));
    if (d2d_result.failed or d2d_device == null) {
        if (d2d_device) |partial_d2d_device| _ = partial_d2d_device.IUnknown.Release();
        if (isDeviceLostHresult(@bitCast(d2d_result))) return error.DeviceLost;
        return error.D2dDeviceCreationFailed;
    }
    errdefer _ = d2d_device.?.IUnknown.Release();

    var d2d_context: ?*api.direct2d.ID2D1DeviceContext = null;
    const context_result = d2d_device.?.CreateDeviceContext(
        api.direct2d.D2D1_DEVICE_CONTEXT_OPTIONS_NONE,
        @ptrCast(&d2d_context),
    );
    if (context_result.failed or d2d_context == null) {
        if (d2d_context) |partial_d2d_context| _ = partial_d2d_context.IUnknown.Release();
        if (isDeviceLostHresult(@bitCast(context_result))) return error.DeviceLost;
        return error.DeviceContextCreationFailed;
    }
    errdefer _ = d2d_context.?.IUnknown.Release();

    var factory_raw: ?*anyopaque = null;
    const factory_result = api.dwrite_dll.DWriteCreateFactory(
        api.direct_write.DWRITE_FACTORY_TYPE.SHARED,
        api.direct_write.IID_IDWriteFactory,
        @ptrCast(&factory_raw),
    );
    if (factory_result.failed or factory_raw == null) {
        if (factory_raw) |partial_factory_raw| {
            const partial_factory: *api.direct_write.IDWriteFactory = @ptrCast(@alignCast(partial_factory_raw));
            _ = partial_factory.IUnknown.Release();
        }
        return error.TextFactoryCreationFailed;
    }
    const dwrite_factory: *api.direct_write.IDWriteFactory = @ptrCast(@alignCast(factory_raw.?));
    errdefer _ = dwrite_factory.IUnknown.Release();

    var text_format: ?*api.direct_write.IDWriteTextFormat = null;
    const font_family = std.unicode.utf8ToUtf16LeStringLiteral("Segoe UI");
    const locale_name = std.unicode.utf8ToUtf16LeStringLiteral(strings.english_locale);
    const format_result = dwrite_factory.CreateTextFormat(
        font_family,
        null,
        api.direct_write.DWRITE_FONT_WEIGHT.NORMAL,
        api.direct_write.DWRITE_FONT_STYLE.NORMAL,
        api.direct_write.DWRITE_FONT_STRETCH.NORMAL,
        14.0,
        locale_name,
        @ptrCast(&text_format),
    );
    if (format_result.failed or text_format == null) {
        if (text_format) |partial_text_format| _ = partial_text_format.IUnknown.Release();
        return error.TextFormatCreationFailed;
    }
    errdefer _ = text_format.?.IUnknown.Release();

    const render_target: *const api.direct2d.ID2D1RenderTarget = &d2d_context.?.ID2D1RenderTarget;
    var background_brush = try createBrush(render_target, .{ .r = 0.035, .g = 0.055, .b = 0.09, .a = 1.0 });
    errdefer _ = background_brush.IUnknown.Release();
    var pane_brush = try createBrush(render_target, .{ .r = 0.055, .g = 0.08, .b = 0.12, .a = 1.0 });
    errdefer _ = pane_brush.IUnknown.Release();
    var divider_brush = try createBrush(render_target, .{ .r = 0.16, .g = 0.25, .b = 0.35, .a = 1.0 });
    errdefer _ = divider_brush.IUnknown.Release();
    var accent_brush = try createBrush(render_target, .{ .r = 0.18, .g = 0.68, .b = 0.96, .a = 1.0 });
    errdefer _ = accent_brush.IUnknown.Release();
    var text_brush = try createBrush(render_target, .{ .r = 0.82, .g = 0.90, .b = 0.96, .a = 1.0 });
    errdefer _ = text_brush.IUnknown.Release();

    return .{
        .d2d_device = d2d_device,
        .d2d_context = d2d_context,
        .dwrite_factory = dwrite_factory,
        .text_format = text_format,
        .background_brush = background_brush,
        .pane_brush = pane_brush,
        .divider_brush = divider_brush,
        .accent_brush = accent_brush,
        .text_brush = text_brush,
        .d3d_device = d3d_device,
        .owner_thread_id = api.composition_kernel32.GetCurrentThreadId(),
    };
}

fn deviceLost(self: *const Renderer) bool {
    if (builtin.os.tag != .windows) return false;
    const device = self.d3d_device orelse return false;
    return isDeviceLostHresult(@bitCast(device.GetDeviceRemovedReason()));
}

fn createBrush(
    render_target: *const api.direct2d.ID2D1RenderTarget,
    color: api.direct2d_common.D2D_COLOR_F,
) Error!*api.direct2d.ID2D1SolidColorBrush {
    var brush: ?*api.direct2d.ID2D1SolidColorBrush = null;
    const result = render_target.CreateSolidColorBrush(&color, null, @ptrCast(&brush));
    if (result.failed or brush == null) {
        if (brush) |partial_brush| _ = partial_brush.IUnknown.Release();
        return error.BrushCreationFailed;
    }
    return brush.?;
}

fn fill(
    render_target: *const api.direct2d.ID2D1RenderTarget,
    rectangle: api.direct2d_common.D2D_RECT_F,
    brush: *api.direct2d.ID2D1SolidColorBrush,
) void {
    if (rectangle.right <= rectangle.left or rectangle.bottom <= rectangle.top) return;
    render_target.FillRectangle(&rectangle, @ptrCast(brush));
}

fn drawText(
    render_target: *const api.direct2d.ID2D1RenderTarget,
    text: [*:0]const u16,
    rectangle: api.direct2d_common.D2D_RECT_F,
    brush: *api.direct2d.ID2D1SolidColorBrush,
    format: *api.direct_write.IDWriteTextFormat,
) void {
    if (rectangle.right <= rectangle.left or rectangle.bottom <= rectangle.top) return;
    render_target.DrawText(
        text,
        @intCast(std.mem.span(text).len),
        format,
        &rectangle,
        @ptrCast(brush),
        api.direct2d.D2D1_DRAW_TEXT_OPTIONS_NONE,
        api.direct_write.DWRITE_MEASURING_MODE.NATURAL,
    );
}
