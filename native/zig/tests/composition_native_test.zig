const builtin = @import("builtin");
const std = @import("std");
const composition = @import("composition_native");
const graphics = @import("graphics");
const layout = @import("app_layout");

fn wrongThreadDrawProbe(renderer: *composition.Renderer, observed: *bool) void {
    renderer.draw(null, 1, 1, 96) catch |err| {
        observed.* = err == error.WrongThread;
        return;
    };
}

test "composition extent and target contract are deterministic" {
    try composition.validateExtent(1, 1);
    try composition.validateExtent(std.math.maxInt(i32), 1);
    try std.testing.expectError(error.InvalidExtent, composition.validateExtent(0, 1));
    try std.testing.expectError(error.InvalidExtent, composition.validateExtent(1, 0));
    try std.testing.expectError(error.InvalidExtent, composition.validateExtent(@as(u32, @intCast(std.math.maxInt(i32))) + 1, 1));

    const properties = composition.targetProperties(144);
    try std.testing.expectEqual(composition.TargetFormat.bgra8_unorm, properties.format);
    try std.testing.expectEqual(composition.AlphaMode.premultiplied, properties.alpha_mode);
    try std.testing.expectEqual(@as(f32, 144.0), properties.dpi_x);
    try std.testing.expectEqual(@as(f32, 144.0), properties.dpi_y);
    try std.testing.expectEqual(composition.targetProperties(0), composition.targetProperties(96));
}

test "composition geometry uses shared DIP layout at every DPI" {
    const baseline = try composition.frameGeometry(960, 640, 96);
    try std.testing.expectEqual(@as(u32, 960), baseline.width_dip);
    try std.testing.expectEqual(@as(u32, 640), baseline.height_dip);
    try std.testing.expectEqual(@as(u32, 48), baseline.toolbar_bottom_dip);
    try std.testing.expectEqual(@as(u32, 612), baseline.status_top_dip);
    try std.testing.expect(baseline.source_left_dip < baseline.source_right_dip);
    try std.testing.expect(baseline.pdf_left_dip < baseline.pdf_right_dip);

    const high_dpi = try composition.frameGeometry(1440, 960, 144);
    try std.testing.expectEqual(@as(u32, 960), high_dpi.width_dip);
    try std.testing.expectEqual(@as(u32, 640), high_dpi.height_dip);
    try std.testing.expectEqual(baseline.toolbar_bottom_dip, high_dpi.toolbar_bottom_dip);
    try std.testing.expectEqual(baseline.status_top_dip, high_dpi.status_top_dip);
    try std.testing.expect(!high_dpi.project_visible);
    try std.testing.expect(high_dpi.pdf_visible);

    const dpi_125 = try composition.frameGeometry(1200, 800, 120);
    try std.testing.expectEqual(@as(u32, 960), dpi_125.width_dip);
    try std.testing.expectEqual(@as(u32, 640), dpi_125.height_dip);
    const dpi_200 = try composition.frameGeometry(1920, 1280, 192);
    try std.testing.expectEqual(@as(u32, 960), dpi_200.width_dip);
    try std.testing.expectEqual(@as(u32, 640), dpi_200.height_dip);

    const focus_96 = try composition.frameGeometry(760, 520, 96);
    try std.testing.expectEqual(@as(u32, 760), focus_96.width_dip);
    try std.testing.expect(!focus_96.project_visible);
    try std.testing.expect(!focus_96.pdf_visible);
    try std.testing.expectEqual(@as(u32, 752), focus_96.source_right_dip);
    const focus_144 = try composition.frameGeometry(1140, 780, 144);
    try std.testing.expectEqual(@as(u32, 760), focus_144.width_dip);
    try std.testing.expectEqual(focus_96.source_right_dip, focus_144.source_right_dip);

    const focus_boundary_96 = try composition.frameGeometry(879, 520, 96);
    try std.testing.expectEqual(@as(u32, 879), focus_boundary_96.width_dip);
    try std.testing.expect(!focus_boundary_96.pdf_visible);
    try std.testing.expectEqual(@as(u32, 871), focus_boundary_96.source_right_dip);
    const focus_boundary_144 = try composition.frameGeometry(1319, 780, 144);
    try std.testing.expectEqual(@as(u32, 879), focus_boundary_144.width_dip);
    try std.testing.expectEqual(focus_boundary_96.source_right_dip, focus_boundary_144.source_right_dip);

    const tri = try composition.frameGeometry(1920, 1080, 144);
    try std.testing.expectEqual(@as(u32, 1280), tri.width_dip);
    try std.testing.expect(tri.project_visible);
    try std.testing.expect(tri.pdf_visible);
    try std.testing.expectEqual(@as(u32, 248), tri.project_right_dip);
    try std.testing.expectEqual(@as(u32, 254), tri.source_left_dip);
    try std.testing.expect(tri.source_left_dip < tri.source_right_dip);
    try std.testing.expect(tri.source_right_dip < tri.pdf_left_dip);
    try std.testing.expect(tri.pdf_right_dip <= tri.width_dip);
    // Every responsive mode that shows PDF leaves exactly one outer rhythm
    // gap after the pane; shell relayout consumes these same boundaries.
    try std.testing.expectEqual(baseline.width_dip - layout.spacing_rhythm_dip, baseline.pdf_right_dip);
    try std.testing.expectEqual(tri.width_dip - layout.spacing_rhythm_dip, tri.pdf_right_dip);
}

test "composition geometry remains valid for tiny native clients" {
    const tiny = try composition.frameGeometry(1, 1, 192);
    try std.testing.expectEqual(@as(u32, 1), tiny.width_dip);
    try std.testing.expectEqual(@as(u32, 1), tiny.height_dip);
    try std.testing.expect(tiny.source_left_dip <= tiny.width_dip);
    try std.testing.expect(tiny.source_right_dip <= tiny.width_dip);
    try std.testing.expectEqual(composition.max_extent, composition.pixelsToDip(composition.max_extent, 1));
}

test "composition EndDraw mapping never presents a lost target" {
    try std.testing.expectEqual(composition.DrawOutcome.drawn, composition.mapEndDrawResult(0));
    try std.testing.expectEqual(composition.DrawOutcome.device_lost, composition.mapEndDrawResult(composition.d2derr_recreate_target));
    try std.testing.expect(composition.isDeviceLostHresult(composition.dxgi_error_device_hung));
    try std.testing.expect(composition.isDeviceLostHresult(composition.dxgi_error_device_removed));
    try std.testing.expect(composition.isDeviceLostHresult(composition.dxgi_error_device_reset));
    try std.testing.expect(composition.isDeviceLostHresult(composition.dxgi_error_driver_internal_error));
    try std.testing.expectEqual(composition.DrawOutcome.failed, composition.mapEndDrawResult(0x80004005));
}

test "renderer owns cached device-bound resources and remains unsupported off Windows" {
    try std.testing.expect(@hasField(composition.Renderer, "d2d_device"));
    try std.testing.expect(@hasField(composition.Renderer, "d2d_context"));
    try std.testing.expect(@hasField(composition.Renderer, "dwrite_factory"));
    try std.testing.expect(@hasField(composition.Renderer, "text_format"));
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var device = graphics.Device{
        .path = .hardware,
        .feature_level = graphics.minimum_feature_level,
        .device = null,
        .context = null,
    };
    try std.testing.expectError(error.UnsupportedTarget, composition.Renderer.init(&device));
}

test "real composition renderer initializes and tears down on Windows" {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    var device = try graphics.Device.createWithPath(.warp);
    defer device.deinit();
    var renderer = try composition.Renderer.init(&device);
    defer renderer.deinit();
    try std.testing.expect(renderer.ready());
    try std.testing.expectEqual(@as(u64, 0), renderer.frameCount());
    try std.testing.expect(renderer.ownerThreadId() != 0);
    // The shell test exercises the real swap-chain surface. This focused test
    // intentionally only proves the device-bound graph can be created safely.
}

test "composition renderer rejects calls from a non-owner thread" {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) return error.SkipZigTest;
    var device = try graphics.Device.createWithPath(.warp);
    defer device.deinit();
    var renderer = try composition.Renderer.init(&device);
    defer renderer.deinit();
    var observed = false;
    const worker = try std.Thread.spawn(.{}, wrongThreadDrawProbe, .{ &renderer, &observed });
    worker.join();
    try std.testing.expect(observed);
}
