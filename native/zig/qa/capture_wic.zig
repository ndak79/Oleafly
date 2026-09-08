//! WIC PNG round-trip for pixels obtained from the DXGI QA lane.
//!
//! The encoder and decoder are both real Windows Imaging Component objects.
//! The non-Windows branch is declaration-only and never substitutes a fixture
//! or another image writer for the runtime proof path.

const builtin = @import("builtin");
const std = @import("std");
const contract = @import("capture_contract");
const com = @import("windows_com");

pub const Error = error{
    UnsupportedTarget,
    UnsupportedArchitecture,
    ComInitializationUnavailable,
    ImagingFactoryUnavailable,
    StreamUnavailable,
    EncoderUnavailable,
    FrameEncoderUnavailable,
    DecoderUnavailable,
    FrameDecoderUnavailable,
    FormatConverterUnavailable,
    EncodeFailed,
    DecodeFailed,
    InvalidInput,
    InvalidDimensions,
    SizeOverflow,
    ReadFailed,
    WriteFailed,
    DigestMismatch,
    OutOfMemory,
};

pub const Png = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    source_digest: [32]u8,
    encoded_digest: [32]u8,
    width: u32,
    height: u32,
    stride: u32,

    pub fn deinit(self: *Png) void {
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub fn validateInput(layout: contract.PixelLayout, pixels: []const u8) Error!void {
    contract.validate_pixels(layout, pixels) catch return error.InvalidInput;
}

pub fn encodeRoundTrip(
    allocator: std.mem.Allocator,
    layout: contract.PixelLayout,
    pixels: []const u8,
) Error!Png {
    try validateInput(layout, pixels);
    return windows.encodeRoundTrip(allocator, layout, pixels);
}

const windows = if (builtin.os.tag == .windows) struct {
    const api = @import("windows_api");

    extern "ole32" fn CreateStreamOnHGlobal(
        hGlobal: isize,
        delete_on_release: i32,
        stream: ?*?*api.com.IStream,
    ) callconv(.winapi) i32;

    fn failed(result: anytype) bool {
        return result.failed;
    }

    fn createStream() Error!*api.com.IStream {
        var stream: ?*api.com.IStream = null;
        const result = CreateStreamOnHGlobal(0, 1, @ptrCast(&stream));
        if (result < 0 or stream == null) return error.StreamUnavailable;
        return stream.?;
    }

    fn seekStart(stream: *api.com.IStream) Error!void {
        const position = api.foundation.LARGE_INTEGER{ .QuadPart = 0 };
        if (failed(stream.Seek(position, .SET, null))) return error.ReadFailed;
    }

    fn readStream(allocator: std.mem.Allocator, stream: *api.com.IStream) Error![]u8 {
        var stat = std.mem.zeroes(api.com.STATSTG);
        if (failed(stream.Stat(&stat, .NONAME))) return error.ReadFailed;
        const size_u64 = stat.cbSize.QuadPart;
        if (size_u64 == 0) return error.ReadFailed;
        const size = std.math.cast(usize, size_u64) orelse return error.SizeOverflow;
        const size_u32 = std.math.cast(u32, size_u64) orelse return error.SizeOverflow;
        const bytes = try allocator.alloc(u8, size);
        errdefer allocator.free(bytes);
        try seekStart(stream);

        const sequential: *api.com.ISequentialStream = @ptrCast(@alignCast(stream));
        var read: u32 = 0;
        const result = sequential.Read(@ptrCast(bytes.ptr), size_u32, &read);
        if (failed(result) or read != size_u32) return error.ReadFailed;
        return bytes;
    }

    fn writeStream(stream: *api.com.IStream, bytes: []const u8) Error!void {
        const size = std.math.cast(u32, bytes.len) orelse return error.SizeOverflow;
        const sequential: *api.com.ISequentialStream = @ptrCast(@alignCast(stream));
        var written: u32 = 0;
        const result = sequential.Write(@ptrCast(bytes.ptr), size, &written);
        if (failed(result) or written != size) return error.WriteFailed;
    }

    fn createFactory() Error!*api.imaging.IWICImagingFactory {
        var factory_raw: ?*anyopaque = null;
        const result = api.ole32_dll.CoCreateInstance(
            &api.imaging.CLSID_WICImagingFactory,
            null,
            api.com.CLSCTX_INPROC_SERVER,
            api.imaging.IID_IWICImagingFactory,
            @ptrCast(&factory_raw),
        );
        if (failed(result) or factory_raw == null) return error.ImagingFactoryUnavailable;
        return @ptrCast(@alignCast(factory_raw.?));
    }

    fn encode(
        allocator: std.mem.Allocator,
        factory: *api.imaging.IWICImagingFactory,
        layout: contract.PixelLayout,
        pixels: []const u8,
    ) Error![]u8 {
        const stream = try createStream();
        defer _ = stream.IUnknown.Release();

        var encoder: ?*api.imaging.IWICBitmapEncoder = null;
        const encoder_result = factory.CreateEncoder(&api.imaging.GUID_ContainerFormatPng, null, @ptrCast(&encoder));
        if (failed(encoder_result) or encoder == null) return error.EncoderUnavailable;
        defer _ = encoder.?.IUnknown.Release();

        if (failed(encoder.?.Initialize(stream, api.imaging.WICBitmapEncoderNoCache))) return error.EncodeFailed;

        var frame: ?*api.imaging.IWICBitmapFrameEncode = null;
        const frame_result = encoder.?.CreateNewFrame(@ptrCast(&frame), null);
        if (failed(frame_result) or frame == null) return error.FrameEncoderUnavailable;
        defer _ = frame.?.IUnknown.Release();

        if (failed(frame.?.Initialize(null))) return error.EncodeFailed;
        if (failed(frame.?.SetSize(layout.width, layout.height))) return error.EncodeFailed;
        if (failed(frame.?.SetResolution(96.0, 96.0))) return error.EncodeFailed;
        var pixel_format = api.imaging.GUID_WICPixelFormat32bppBGRA;
        if (failed(frame.?.SetPixelFormat(&pixel_format))) return error.EncodeFailed;
        if (failed(frame.?.WritePixels(
            layout.height,
            layout.stride,
            @intCast(pixels.len),
            @ptrCast(@constCast(pixels.ptr)),
        ))) return error.EncodeFailed;
        if (failed(frame.?.Commit())) return error.EncodeFailed;
        if (failed(encoder.?.Commit())) return error.EncodeFailed;

        return readStream(allocator, stream);
    }

    fn decodeAndCompare(
        allocator: std.mem.Allocator,
        factory: *api.imaging.IWICImagingFactory,
        encoded: []const u8,
        layout: contract.PixelLayout,
        pixels: []const u8,
    ) Error!void {
        const stream = try createStream();
        defer _ = stream.IUnknown.Release();
        try writeStream(stream, encoded);
        try seekStart(stream);

        var decoder: ?*api.imaging.IWICBitmapDecoder = null;
        const decoder_result = factory.CreateDecoderFromStream(
            stream,
            null,
            api.imaging.WICDecodeMetadataCacheOnLoad,
            @ptrCast(&decoder),
        );
        if (failed(decoder_result) or decoder == null) return error.DecoderUnavailable;
        defer _ = decoder.?.IUnknown.Release();

        var frame: ?*api.imaging.IWICBitmapFrameDecode = null;
        if (failed(decoder.?.GetFrame(0, @ptrCast(&frame))) or frame == null) {
            return error.FrameDecoderUnavailable;
        }
        defer _ = frame.?.IUnknown.Release();

        const source: *api.imaging.IWICBitmapSource = @ptrCast(@alignCast(frame.?));
        var converter: ?*api.imaging.IWICFormatConverter = null;
        const converter_result = factory.CreateFormatConverter(@ptrCast(&converter));
        if (failed(converter_result) or converter == null) return error.FormatConverterUnavailable;
        defer _ = converter.?.IUnknown.Release();

        var expected_format = api.imaging.GUID_WICPixelFormat32bppBGRA;
        if (failed(converter.?.Initialize(
            source,
            &expected_format,
            api.imaging.WICBitmapDitherTypeNone,
            null,
            0.0,
            api.imaging.WICBitmapPaletteTypeCustom,
        ))) return error.DecodeFailed;

        const converted: *api.imaging.IWICBitmapSource = @ptrCast(@alignCast(converter.?));
        var width: u32 = 0;
        var height: u32 = 0;
        if (failed(converted.GetSize(&width, &height)) or width != layout.width or height != layout.height) {
            return error.InvalidDimensions;
        }

        const decoded = try allocator.alloc(u8, layout.byte_length() catch return error.InvalidInput);
        defer allocator.free(decoded);
        if (failed(converted.CopyPixels(
            null,
            layout.stride,
            @intCast(decoded.len),
            @ptrCast(decoded.ptr),
        ))) return error.DecodeFailed;
        if (!std.mem.eql(u8, decoded, pixels)) return error.DigestMismatch;
    }

    fn encodeRoundTrip(
        allocator: std.mem.Allocator,
        layout: contract.PixelLayout,
        pixels: []const u8,
    ) Error!Png {
        if (builtin.cpu.arch != .x86_64) return error.UnsupportedArchitecture;
        if (!com.initializeSta()) return error.ComInitializationUnavailable;
        defer com.uninitialize();

        const factory = try createFactory();
        defer _ = factory.IUnknown.Release();

        const encoded = try encode(allocator, factory, layout, pixels);
        errdefer allocator.free(encoded);
        try decodeAndCompare(allocator, factory, encoded, layout, pixels);

        return .{
            .allocator = allocator,
            .bytes = encoded,
            .source_digest = contract.raw_digest(pixels),
            .encoded_digest = contract.encoded_digest(encoded),
            .width = layout.width,
            .height = layout.height,
            .stride = layout.stride,
        };
    }
} else struct {
    fn encodeRoundTrip(_: std.mem.Allocator, _: contract.PixelLayout, _: []const u8) Error!Png {
        return error.UnsupportedTarget;
    }
};

test "portable WIC surface validates bytes but does not encode off Windows" {
    const layout = contract.PixelLayout{ .width = 1, .height = 1, .stride = 4, .channel_order = .bgra8 };
    const pixels = [_]u8{ 1, 2, 3, 4 };
    try validateInput(layout, &pixels);
    if (builtin.os.tag != .windows) {
        try std.testing.expectError(error.UnsupportedTarget, encodeRoundTrip(std.testing.allocator, layout, &pixels));
    }
}
