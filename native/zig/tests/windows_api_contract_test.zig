const builtin = @import("builtin");
const std = @import("std");
const api = @import("windows_api");

extern fn texflow_sdk_dxgi_output5_duplicate_output1_slot() callconv(.c) u32;
extern fn texflow_sdk_dxgi_output_duplication_size() callconv(.c) u32;
extern fn texflow_sdk_wic_factory_create_encoder_slot() callconv(.c) u32;
extern fn texflow_sdk_wic_encoder_initialize_slot() callconv(.c) u32;
extern fn texflow_sdk_dxgi_format_b8g8r8a8_unorm() callconv(.c) u32;
extern fn texflow_sdk_dwm_extended_frame_bounds() callconv(.c) u32;
extern fn texflow_sdk_iid_idxgioutput5_data1() callconv(.c) u32;
extern fn texflow_sdk_iid_idxgioutput5_data2() callconv(.c) u32;
extern fn texflow_sdk_iid_idxgioutput5_data3() callconv(.c) u32;
extern fn texflow_sdk_iid_idxgioutput5_data4() callconv(.c) u32;
extern fn texflow_sdk_iid_idxgioutput5_data4_hi() callconv(.c) u32;
extern fn texflow_sdk_iid_wic_factory_data1() callconv(.c) u32;
extern fn texflow_sdk_iid_wic_factory_data2() callconv(.c) u32;
extern fn texflow_sdk_iid_wic_factory_data3() callconv(.c) u32;
extern fn texflow_sdk_iid_wic_factory_data4() callconv(.c) u32;
extern fn texflow_sdk_iid_wic_factory_data4_hi() callconv(.c) u32;
extern fn texflow_sdk_png_guid_data1() callconv(.c) u32;
extern fn texflow_sdk_png_guid_data2() callconv(.c) u32;
extern fn texflow_sdk_png_guid_data3() callconv(.c) u32;
extern fn texflow_sdk_png_guid_data4() callconv(.c) u32;
extern fn texflow_sdk_png_guid_data4_hi() callconv(.c) u32;
extern fn texflow_sdk_bgra_guid_data1() callconv(.c) u32;
extern fn texflow_sdk_bgra_guid_data2() callconv(.c) u32;
extern fn texflow_sdk_bgra_guid_data3() callconv(.c) u32;
extern fn texflow_sdk_bgra_guid_data4() callconv(.c) u32;
extern fn texflow_sdk_bgra_guid_data4_hi() callconv(.c) u32;
extern fn texflow_sdk_d3d11_sdk_version() callconv(.c) u32;
extern fn texflow_sdk_d3d11_bgra_support_flag() callconv(.c) u32;
extern fn texflow_sdk_d3d11_device_size() callconv(.c) u32;
extern fn texflow_sdk_d3d11_device_create_buffer_slot() callconv(.c) u32;
extern fn texflow_sdk_iid_d3d11_device_data1() callconv(.c) u32;
extern fn texflow_sdk_iid_d3d11_device_data2() callconv(.c) u32;
extern fn texflow_sdk_iid_d3d11_device_data3() callconv(.c) u32;
extern fn texflow_sdk_iid_d3d11_device_data4() callconv(.c) u32;
extern fn texflow_sdk_iid_d3d11_device_data4_hi() callconv(.c) u32;

fn packGuidData4(data4: [8]u8) [2]u32 {
    return .{
        @as(u32, data4[0]) | (@as(u32, data4[1]) << 8) | (@as(u32, data4[2]) << 16) | (@as(u32, data4[3]) << 24),
        @as(u32, data4[4]) | (@as(u32, data4[5]) << 8) | (@as(u32, data4[6]) << 16) | (@as(u32, data4[7]) << 24),
    };
}

test "Windows SDK facade aliases and C ABI probe" {
    if (comptime builtin.os.tag != .windows) return;
    if (comptime !@hasDecl(api, "dxgi_common") or
        !@hasDecl(api, "dwm") or
        !@hasDecl(api, "dwmapi") or
        !@hasDecl(api, "imaging") or
        !@hasDecl(api, "d3d11")) return error.MissingWindowsApiAlias;

    const dxgi = api.dxgi;
    const common = api.dxgi_common;
    const imaging = api.imaging;
    const dwm = api.dwm;
    const d3d11 = api.d3d11;
    if (comptime !@hasDecl(d3d11, "ID3D11Device") or !@hasDecl(d3d11, "D3D11_SDK_VERSION")) return error.MissingWindowsApiAlias;
    const hresult = @TypeOf(api.dxgi.DXGI_ERROR_INVALID_CALL);
    const guid = @TypeOf(imaging.GUID_ContainerFormatPng);

    try std.testing.expectEqual(@as(usize, 8), @sizeOf(dxgi.IDXGIOutput5));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(dxgi.IDXGIOutputDuplication));
    try std.testing.expectEqual(@as(usize, 26 * @sizeOf(usize)), @offsetOf(dxgi.IDXGIOutput5.VTable, "DuplicateOutput1"));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(imaging.IWICImagingFactory));
    try std.testing.expectEqual(@as(usize, 8 * @sizeOf(usize)), @offsetOf(imaging.IWICImagingFactory.VTable, "CreateEncoder"));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(imaging.IWICBitmapEncoder));
    try std.testing.expectEqual(@as(usize, 3 * @sizeOf(usize)), @offsetOf(imaging.IWICBitmapEncoder.VTable, "Initialize"));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(d3d11.ID3D11Device));
    try std.testing.expectEqual(@as(usize, 3 * @sizeOf(usize)), @offsetOf(d3d11.ID3D11Device.VTable, "CreateBuffer"));

    const duplicate_output1_fn = fn (
        *const dxgi.IDXGIOutput5,
        ?*api.com.IUnknown,
        u32,
        u32,
        [*]const common.DXGI_FORMAT,
        **dxgi.IDXGIOutputDuplication,
    ) callconv(.winapi) hresult;
    try std.testing.expect(@FieldType(dxgi.IDXGIOutput5.VTable, "DuplicateOutput1") == *const duplicate_output1_fn);
    const duplicate_output1 = @typeInfo(@typeInfo(@FieldType(dxgi.IDXGIOutput5.VTable, "DuplicateOutput1")).pointer.child).@"fn";
    try std.testing.expect(duplicate_output1.calling_convention.eql(std.builtin.CallingConvention.winapi));
    try std.testing.expectEqual(@as(usize, 6), duplicate_output1.params.len);
    const create_encoder_fn = fn (
        *const imaging.IWICImagingFactory,
        ?*const guid,
        ?*const guid,
        ?*?*imaging.IWICBitmapEncoder,
    ) callconv(.winapi) hresult;
    try std.testing.expect(@FieldType(imaging.IWICImagingFactory.VTable, "CreateEncoder") == *const create_encoder_fn);
    const create_encoder = @typeInfo(@typeInfo(@FieldType(imaging.IWICImagingFactory.VTable, "CreateEncoder")).pointer.child).@"fn";
    try std.testing.expect(create_encoder.calling_convention.eql(std.builtin.CallingConvention.winapi));
    try std.testing.expectEqual(@as(usize, 4), create_encoder.params.len);
    const encoder_initialize_fn = fn (
        *const imaging.IWICBitmapEncoder,
        ?*api.com.IStream,
        imaging.WICBitmapEncoderCacheOption,
    ) callconv(.winapi) hresult;
    try std.testing.expect(@FieldType(imaging.IWICBitmapEncoder.VTable, "Initialize") == *const encoder_initialize_fn);
    const encoder_initialize = @typeInfo(@typeInfo(@FieldType(imaging.IWICBitmapEncoder.VTable, "Initialize")).pointer.child).@"fn";
    try std.testing.expect(encoder_initialize.calling_convention.eql(std.builtin.CallingConvention.winapi));
    try std.testing.expectEqual(@as(usize, 3), encoder_initialize.params.len);

    try std.testing.expectEqual(texflow_sdk_dxgi_output5_duplicate_output1_slot(), @as(u32, 26));
    try std.testing.expectEqual(texflow_sdk_dxgi_output_duplication_size(), @as(u32, 8));
    try std.testing.expectEqual(texflow_sdk_wic_factory_create_encoder_slot(), @as(u32, 8));
    try std.testing.expectEqual(texflow_sdk_wic_encoder_initialize_slot(), @as(u32, 3));
    try std.testing.expectEqual(texflow_sdk_dxgi_format_b8g8r8a8_unorm(), @intFromEnum(common.DXGI_FORMAT_B8G8R8A8_UNORM));
    try std.testing.expectEqual(texflow_sdk_dwm_extended_frame_bounds(), @intFromEnum(dwm.DWMWA_EXTENDED_FRAME_BOUNDS));

    const output_iid = dxgi.IID_IDXGIOutput5.*.Ints;
    const output_iid_data4 = packGuidData4(output_iid.d);
    try std.testing.expectEqual(texflow_sdk_iid_idxgioutput5_data1(), output_iid.a);
    try std.testing.expectEqual(texflow_sdk_iid_idxgioutput5_data2(), output_iid.b);
    try std.testing.expectEqual(texflow_sdk_iid_idxgioutput5_data3(), output_iid.c);
    try std.testing.expectEqual(texflow_sdk_iid_idxgioutput5_data4(), output_iid_data4[0]);
    try std.testing.expectEqual(texflow_sdk_iid_idxgioutput5_data4_hi(), output_iid_data4[1]);

    const factory_iid = imaging.IID_IWICImagingFactory.*.Ints;
    const factory_iid_data4 = packGuidData4(factory_iid.d);
    try std.testing.expectEqual(texflow_sdk_iid_wic_factory_data1(), factory_iid.a);
    try std.testing.expectEqual(texflow_sdk_iid_wic_factory_data2(), factory_iid.b);
    try std.testing.expectEqual(texflow_sdk_iid_wic_factory_data3(), factory_iid.c);
    try std.testing.expectEqual(texflow_sdk_iid_wic_factory_data4(), factory_iid_data4[0]);
    try std.testing.expectEqual(texflow_sdk_iid_wic_factory_data4_hi(), factory_iid_data4[1]);

    const png = imaging.GUID_ContainerFormatPng.Ints;
    const png_data4 = packGuidData4(png.d);
    try std.testing.expectEqual(texflow_sdk_png_guid_data1(), png.a);
    try std.testing.expectEqual(texflow_sdk_png_guid_data2(), png.b);
    try std.testing.expectEqual(texflow_sdk_png_guid_data3(), png.c);
    try std.testing.expectEqual(texflow_sdk_png_guid_data4(), png_data4[0]);
    try std.testing.expectEqual(texflow_sdk_png_guid_data4_hi(), png_data4[1]);

    const bgra = imaging.GUID_WICPixelFormat32bppBGRA.Ints;
    const bgra_data4 = packGuidData4(bgra.d);
    try std.testing.expectEqual(texflow_sdk_bgra_guid_data1(), bgra.a);
    try std.testing.expectEqual(texflow_sdk_bgra_guid_data2(), bgra.b);
    try std.testing.expectEqual(texflow_sdk_bgra_guid_data3(), bgra.c);
    try std.testing.expectEqual(texflow_sdk_bgra_guid_data4(), bgra_data4[0]);
    try std.testing.expectEqual(texflow_sdk_bgra_guid_data4_hi(), bgra_data4[1]);

    try std.testing.expectEqual(texflow_sdk_d3d11_sdk_version(), d3d11.D3D11_SDK_VERSION);
    try std.testing.expectEqual(texflow_sdk_d3d11_bgra_support_flag(), @as(u32, @bitCast(d3d11.D3D11_CREATE_DEVICE_BGRA_SUPPORT)));
    try std.testing.expectEqual(texflow_sdk_d3d11_device_size(), @as(u32, @sizeOf(d3d11.ID3D11Device)));
    try std.testing.expectEqual(texflow_sdk_d3d11_device_create_buffer_slot(), @as(u32, @offsetOf(d3d11.ID3D11Device.VTable, "CreateBuffer") / @sizeOf(usize)));

    const device_iid = d3d11.IID_ID3D11Device.*.Ints;
    const device_iid_data4 = packGuidData4(device_iid.d);
    try std.testing.expectEqual(texflow_sdk_iid_d3d11_device_data1(), device_iid.a);
    try std.testing.expectEqual(texflow_sdk_iid_d3d11_device_data2(), device_iid.b);
    try std.testing.expectEqual(texflow_sdk_iid_d3d11_device_data3(), device_iid.c);
    try std.testing.expectEqual(texflow_sdk_iid_d3d11_device_data4(), device_iid_data4[0]);
    try std.testing.expectEqual(texflow_sdk_iid_d3d11_device_data4_hi(), device_iid_data4[1]);
}

test "DWM facade retains the Windows calling convention" {
    if (comptime builtin.os.tag != .windows) return;
    if (comptime !@hasDecl(api, "dwmapi")) return error.MissingWindowsApiAlias;
    const DwmGetWindowAttribute = fn (
        ?api.foundation.HWND,
        api.dwm.DWMWINDOWATTRIBUTE,
        ?*anyopaque,
        u32,
    ) callconv(.winapi) @TypeOf(api.dxgi.DXGI_ERROR_INVALID_CALL);
    try std.testing.expect(@TypeOf(api.dwmapi.DwmGetWindowAttribute) == DwmGetWindowAttribute);
}
