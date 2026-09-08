//! Independent Windows capture probe backed by DXGI Desktop Duplication 1.
//!
//! This file is intentionally not part of the product renderer.  It admits a
//! real output adapter, creates a D3D11 staging texture, and only returns
//! pixels after a post-marker Desktop Duplication frame has been acquired.
//! There is no synthetic or window-rendering fallback in this lane.

const builtin = @import("builtin");
const std = @import("std");
const contract = @import("capture_contract");

pub const Error = error{
    UnsupportedTarget,
    UnsupportedArchitecture,
    ClockUnavailable,
    FactoryUnavailable,
    AdapterUnavailable,
    AdapterEnumerationFailed,
    OutputUnavailable,
    OutputEnumerationFailed,
    OutputNotAttached,
    Output5Unavailable,
    DeviceCreationFailed,
    FeatureLevelUnsupported,
    DesktopDuplicationUnavailable,
    UnsupportedFormat,
    InvalidRotation,
    InvalidRequest,
    InvalidDpi,
    InvalidDimensions,
    InvalidFrame,
    StaleFrame,
    AccumulatedFrames,
    ProtectedContent,
    AcquireTimeout,
    DeadlineExceeded,
    AccessDenied,
    NotCurrentlyAvailable,
    SessionDisconnected,
    UnsupportedCapability,
    QueryInterfaceFailed,
    StagingTextureFailed,
    MapFailed,
    RowPitchTooSmall,
    InvalidPixelBytes,
    ReleaseFrameFailed,
    AccessLost,
    RecreationNotRequired,
    OutOfMemory,
};

pub const OutputInfo = struct {
    adapter_luid: u64,
    output_index: u32,
    desktop_bounds: contract.Rect,
    mode_width: u32,
    mode_height: u32,
    rotation: u16,
    format: Format,
};

pub const Format = enum {
    bgra8_unorm,
};

pub const AcquireRequest = struct {
    marker_qpc: u64,
    deadline_qpc: u64,
    dpi: u16,
};

pub const Frame = struct {
    allocator: std.mem.Allocator,
    pixels: []u8,
    metadata: contract.FrameMetadata,
    output: OutputInfo,
    generation: u64,

    pub fn deinit(self: *Frame) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }
};

/// A live Desktop Duplication session.  The handles are opaque at the public
/// boundary so non-Windows consumers can compile the declaration surface.
pub const Session = struct {
    allocator: std.mem.Allocator,
    output_index: u32,
    generation: u64 = 1,
    needs_recreation: bool = false,
    output: OutputInfo = undefined,
    factory: ?*anyopaque = null,
    adapter: ?*anyopaque = null,
    dxgi_output: ?*anyopaque = null,
    output5: ?*anyopaque = null,
    device: ?*anyopaque = null,
    context: ?*anyopaque = null,
    duplication: ?*anyopaque = null,

    pub fn open(allocator: std.mem.Allocator, output_index: u32) Error!Session {
        return windows.open(allocator, output_index);
    }

    pub fn deinit(self: *Session) void {
        windows.deinit(self);
    }

    pub fn outputInfo(self: *const Session) OutputInfo {
        return self.output;
    }

    pub fn acquireAfter(self: *Session, request: AcquireRequest) Error!Frame {
        return windows.acquireAfter(self, request);
    }

    /// Rebuild the duplication object after the API reports access loss.
    /// Recovery is deliberately explicit; a stale session cannot silently be
    /// reused for evidence.
    pub fn recreate(self: *Session) Error!void {
        return windows.recreate(self);
    }
};

const windows = if (builtin.os.tag == .windows) struct {
    const api = @import("windows_api");

    extern "kernel32" fn QueryPerformanceCounter(value: *i64) callconv(.winapi) i32;

    fn qpc() Error!u64 {
        var value: i64 = 0;
        if (QueryPerformanceCounter(&value) == 0 or value <= 0) return error.ClockUnavailable;
        return @intCast(value);
    }

    fn failed(result: anytype) bool {
        return result.failed;
    }

    fn release(raw: ?*anyopaque) void {
        if (raw) |value| {
            const unknown: *api.com.IUnknown = @ptrCast(@alignCast(value));
            _ = unknown.Release();
        }
    }

    fn releasePartial(
        device: *?*api.d3d11.ID3D11Device,
        context: *?*api.d3d11.ID3D11DeviceContext,
    ) void {
        if (context.*) |value| {
            _ = value.IUnknown.Release();
            context.* = null;
        }
        if (device.*) |value| {
            _ = value.IUnknown.Release();
            device.* = null;
        }
    }

    fn rotationDegrees(value: api.dxgi_common.DXGI_MODE_ROTATION) Error!u16 {
        return switch (value) {
            .IDENTITY => 0,
            .ROTATE90 => 90,
            .ROTATE180 => 180,
            .ROTATE270 => 270,
            else => error.InvalidRotation,
        };
    }

    fn mapDxgiError(result: anytype) Error {
        if (result == api.dxgi.DXGI_ERROR_ACCESS_LOST) return error.AccessLost;
        if (result == api.dxgi.DXGI_ERROR_ACCESS_DENIED) return error.AccessDenied;
        if (result == api.dxgi.DXGI_ERROR_NOT_CURRENTLY_AVAILABLE) return error.NotCurrentlyAvailable;
        if (result == api.dxgi.DXGI_ERROR_SESSION_DISCONNECTED) return error.SessionDisconnected;
        if (result == api.dxgi.DXGI_ERROR_UNSUPPORTED) return error.UnsupportedCapability;
        if (result == api.dxgi.DXGI_ERROR_WAIT_TIMEOUT) return error.AcquireTimeout;
        return error.DesktopDuplicationUnavailable;
    }

    fn open(allocator: std.mem.Allocator, target_output: u32) Error!Session {
        if (builtin.cpu.arch != .x86_64) return error.UnsupportedArchitecture;

        var factory_raw: *anyopaque = undefined;
        const factory_result = api.dxgi_dll.CreateDXGIFactory1(api.dxgi.IID_IDXGIFactory1, &factory_raw);
        if (failed(factory_result)) return error.FactoryUnavailable;

        var session = Session{
            .allocator = allocator,
            .output_index = target_output,
            .factory = factory_raw,
        };
        errdefer deinit(&session);

        const factory: *api.dxgi.IDXGIFactory1 = @ptrCast(@alignCast(factory_raw));
        var adapter_number: u32 = 0;
        var attached_output_number: u32 = 0;

        while (adapter_number < 64) : (adapter_number += 1) {
            var adapter: *api.dxgi.IDXGIAdapter1 = undefined;
            const adapter_result = factory.EnumAdapters1(adapter_number, &adapter);
            if (adapter_result == api.dxgi.DXGI_ERROR_NOT_FOUND) break;
            if (failed(adapter_result)) return error.AdapterEnumerationFailed;

            var selected_adapter = false;
            var output_number: u32 = 0;
            while (output_number < 64) : (output_number += 1) {
                var output: *api.dxgi.IDXGIOutput = undefined;
                const output_result = adapter.IDXGIAdapter.EnumOutputs(output_number, &output);
                if (output_result == api.dxgi.DXGI_ERROR_NOT_FOUND) break;
                if (failed(output_result)) {
                    _ = adapter.IUnknown.Release();
                    return error.OutputEnumerationFailed;
                }

                var output_desc: api.dxgi.DXGI_OUTPUT_DESC = undefined;
                const desc_result = output.GetDesc(&output_desc);
                if (failed(desc_result)) {
                    _ = output.IUnknown.Release();
                    _ = adapter.IUnknown.Release();
                    return error.OutputUnavailable;
                }

                if (output_desc.AttachedToDesktop == 0) {
                    _ = output.IUnknown.Release();
                    continue;
                }

                if (attached_output_number != target_output) {
                    attached_output_number += 1;
                    _ = output.IUnknown.Release();
                    continue;
                }

                var adapter_desc: api.dxgi.DXGI_ADAPTER_DESC1 = undefined;
                const adapter_desc_result = adapter.GetDesc1(&adapter_desc);
                if (failed(adapter_desc_result)) {
                    _ = output.IUnknown.Release();
                    _ = adapter.IUnknown.Release();
                    return error.AdapterUnavailable;
                }

                const output_rotation = rotationDegrees(output_desc.Rotation) catch {
                    _ = output.IUnknown.Release();
                    _ = adapter.IUnknown.Release();
                    return error.InvalidRotation;
                };

                session.adapter = @ptrCast(adapter);
                session.dxgi_output = @ptrCast(output);
                session.output = .{
                    .adapter_luid = @bitCast(adapter_desc.AdapterLuid),
                    .output_index = target_output,
                    .desktop_bounds = .{
                        .left = output_desc.DesktopCoordinates.left,
                        .top = output_desc.DesktopCoordinates.top,
                        .right = output_desc.DesktopCoordinates.right,
                        .bottom = output_desc.DesktopCoordinates.bottom,
                    },
                    .mode_width = 0,
                    .mode_height = 0,
                    .rotation = output_rotation,
                    .format = .bgra8_unorm,
                };
                selected_adapter = true;
                break;
            }

            if (selected_adapter) break;
            _ = adapter.IUnknown.Release();
        }

        if (session.adapter == null or session.dxgi_output == null) return error.OutputUnavailable;

        const adapter: *api.dxgi.IDXGIAdapter1 = @ptrCast(@alignCast(session.adapter.?));
        const output: *api.dxgi.IDXGIOutput = @ptrCast(@alignCast(session.dxgi_output.?));

        var device: ?*api.d3d11.ID3D11Device = null;
        var context: ?*api.d3d11.ID3D11DeviceContext = null;
        var chosen_level: api.direct3d.D3D_FEATURE_LEVEL = undefined;
        const levels = [_]api.direct3d.D3D_FEATURE_LEVEL{ .@"11_0", .@"10_1", .@"10_0" };
        const device_result = api.d3d11_dll.D3D11CreateDevice(
            @ptrCast(adapter),
            .UNKNOWN,
            null,
            api.d3d11.D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            levels[0..].ptr,
            levels.len,
            api.d3d11.D3D11_SDK_VERSION,
            @ptrCast(&device),
            &chosen_level,
            @ptrCast(&context),
        );
        if (failed(device_result) or device == null or context == null) {
            releasePartial(&device, &context);
            return error.DeviceCreationFailed;
        }
        if (@intFromEnum(chosen_level) < @intFromEnum(api.direct3d.D3D_FEATURE_LEVEL.@"10_0")) {
            releasePartial(&device, &context);
            return error.FeatureLevelUnsupported;
        }
        session.device = @ptrCast(device.?);
        session.context = @ptrCast(context.?);

        var output5_raw: ?*anyopaque = null;
        const output5_result = output.IUnknown.QueryInterface(api.dxgi.IID_IDXGIOutput5, @ptrCast(&output5_raw));
        if (failed(output5_result) or output5_raw == null) return error.Output5Unavailable;
        session.output5 = output5_raw;

        const output5: *api.dxgi.IDXGIOutput5 = @ptrCast(@alignCast(output5_raw.?));
        const supported_formats = [_]api.dxgi_common.DXGI_FORMAT{.B8G8R8A8_UNORM};
        var duplication: *api.dxgi.IDXGIOutputDuplication = undefined;
        const duplicate_result = output5.DuplicateOutput1(
            @ptrCast(device.?),
            0,
            supported_formats.len,
            supported_formats[0..].ptr,
            &duplication,
        );
        if (failed(duplicate_result)) return mapDxgiError(duplicate_result);
        session.duplication = @ptrCast(duplication);

        var duplication_desc: api.dxgi.DXGI_OUTDUPL_DESC = undefined;
        duplication.GetDesc(&duplication_desc);
        const rotation = try rotationDegrees(duplication_desc.Rotation);
        if (duplication_desc.ModeDesc.Format != .B8G8R8A8_UNORM) return error.UnsupportedFormat;
        if (duplication_desc.ModeDesc.Width == 0 or duplication_desc.ModeDesc.Height == 0) {
            return error.InvalidDimensions;
        }
        session.output.mode_width = duplication_desc.ModeDesc.Width;
        session.output.mode_height = duplication_desc.ModeDesc.Height;
        session.output.rotation = rotation;
        return session;
    }

    fn deinit(self: *Session) void {
        release(self.duplication);
        self.duplication = null;
        release(self.output5);
        self.output5 = null;
        release(self.dxgi_output);
        self.dxgi_output = null;
        release(self.context);
        self.context = null;
        release(self.device);
        self.device = null;
        release(self.factory);
        self.factory = null;
        release(self.adapter);
        self.adapter = null;
        self.needs_recreation = false;
    }

    fn checkDeadline(deadline_qpc: u64) Error!void {
        const now = try qpc();
        if (now >= deadline_qpc) return error.DeadlineExceeded;
    }

    fn releaseFrame(self: *Session, duplication: *api.dxgi.IDXGIOutputDuplication) Error!void {
        const result = duplication.ReleaseFrame();
        if (failed(result)) {
            const mapped = mapDxgiError(result);
            if (mapped == error.AccessLost) self.needs_recreation = true;
            return mapped;
        }
    }

    fn copyFrame(self: *Session, resource: *api.dxgi.IDXGIResource, info: *const api.dxgi.DXGI_OUTDUPL_FRAME_INFO, request: AcquireRequest) Error!Frame {
        const device: *api.d3d11.ID3D11Device = @ptrCast(@alignCast(self.device orelse return error.DeviceCreationFailed));
        const context: *api.d3d11.ID3D11DeviceContext = @ptrCast(@alignCast(self.context orelse return error.DeviceCreationFailed));

        var texture_raw: ?*anyopaque = null;
        const texture_result = resource.IUnknown.QueryInterface(api.d3d11.IID_ID3D11Texture2D, @ptrCast(&texture_raw));
        if (failed(texture_result) or texture_raw == null) return error.QueryInterfaceFailed;
        const texture: *api.d3d11.ID3D11Texture2D = @ptrCast(@alignCast(texture_raw.?));
        defer _ = texture.IUnknown.Release();

        var source_desc: api.d3d11.D3D11_TEXTURE2D_DESC = undefined;
        texture.GetDesc(&source_desc);
        if (source_desc.Format != .B8G8R8A8_UNORM or source_desc.Width == 0 or source_desc.Height == 0) {
            return error.UnsupportedFormat;
        }

        const layout = contract.PixelLayout{
            .width = source_desc.Width,
            .height = source_desc.Height,
            .stride = std.math.mul(u32, source_desc.Width, 4) catch return error.InvalidDimensions,
            .channel_order = .bgra8,
        };
        const byte_length = layout.byte_length() catch return error.InvalidDimensions;
        const pixels = try self.allocator.alloc(u8, byte_length);
        errdefer self.allocator.free(pixels);

        var staging: ?*api.d3d11.ID3D11Texture2D = null;
        var staging_desc = source_desc;
        staging_desc.MipLevels = 1;
        staging_desc.ArraySize = 1;
        staging_desc.Usage = .STAGING;
        staging_desc.BindFlags = .{};
        staging_desc.CPUAccessFlags = .{ .READ = 1 };
        staging_desc.MiscFlags = .{};
        staging_desc.SampleDesc = .{ .Count = 1, .Quality = 0 };
        const staging_result = device.CreateTexture2D(&staging_desc, null, @ptrCast(&staging));
        if (failed(staging_result) or staging == null) return error.StagingTextureFailed;
        defer _ = staging.?.IUnknown.Release();

        context.CopyResource(@ptrCast(staging.?), @ptrCast(texture));
        var mapped: api.d3d11.D3D11_MAPPED_SUBRESOURCE = undefined;
        const map_result = context.Map(@ptrCast(staging.?), 0, .READ, 0, &mapped);
        if (failed(map_result)) return error.MapFailed;
        defer context.Unmap(@ptrCast(staging.?), 0);

        const row_bytes = layout.row_bytes() catch return error.InvalidDimensions;
        if (mapped.RowPitch < row_bytes) return error.RowPitchTooSmall;
        const source = mapped.pData orelse return error.MapFailed;
        const source_bytes: [*]const u8 = @ptrCast(source);
        for (0..layout.height) |row| {
            const row_index: usize = @intCast(row);
            const destination = pixels[row_index * @as(usize, @intCast(layout.stride)) ..][0..row_bytes];
            const source_row = source_bytes + row_index * @as(usize, @intCast(mapped.RowPitch));
            @memcpy(destination, source_row[0..row_bytes]);
        }

        const last_present = info.LastPresentTime.QuadPart;
        if (last_present <= 0) return error.InvalidFrame;
        const last_present_qpc: u64 = @intCast(last_present);

        const crop = contract.Rect{ .left = 0, .top = 0, .right = @intCast(layout.width), .bottom = @intCast(layout.height) };
        const metadata = contract.FrameMetadata{
            .layout = layout,
            .rotation = self.output.rotation,
            .crop = crop,
            .crop_space = .physical,
            .dpi = request.dpi,
            .last_present_qpc = last_present_qpc,
            .accumulated_frames = info.AccumulatedFrames,
            .protected_content = info.ProtectedContentMaskedOut != 0,
        };
        contract.validate_metadata(metadata) catch return error.InvalidFrame;
        contract.validate_pixels(layout, pixels) catch return error.InvalidPixelBytes;
        const observed_qpc = try qpc();
        const outcome = contract.classify(.{
            .status = .acquired,
            .frame = metadata,
            .observed_qpc = observed_qpc,
            .deadline_qpc = request.deadline_qpc,
            .duplication_generation = self.generation,
        }, request.marker_qpc, self.generation) catch |err| return switch (err) {
            error.InvalidDeadline => error.DeadlineExceeded,
            else => error.InvalidFrame,
        };
        switch (outcome) {
            .accepted => {},
            .stale_qpc => return error.StaleFrame,
            .accumulated_frames => return error.AccumulatedFrames,
            .protected_content => return error.ProtectedContent,
            .timeout => return error.DeadlineExceeded,
            .access_lost => return error.AccessLost,
            .cancelled => return error.InvalidFrame,
        }
        return .{
            .allocator = self.allocator,
            .pixels = pixels,
            .metadata = metadata,
            .output = self.output,
            .generation = self.generation,
        };
    }

    fn acquireAfter(self: *Session, request: AcquireRequest) Error!Frame {
        if (request.marker_qpc == 0 or request.deadline_qpc == 0 or request.marker_qpc >= request.deadline_qpc) {
            return error.InvalidRequest;
        }
        _ = contract.dip_to_physical(1, request.dpi) catch return error.InvalidDpi;
        if (self.needs_recreation) return error.AccessLost;
        // Do not drain after the caller's marker: that would discard the very
        // post-marker update the capture is required to prove. Stale queued
        // frames are released and rejected one by one below.

        const duplication: *api.dxgi.IDXGIOutputDuplication = @ptrCast(@alignCast(self.duplication orelse return error.DesktopDuplicationUnavailable));
        while (true) {
            try checkDeadline(request.deadline_qpc);
            var info: api.dxgi.DXGI_OUTDUPL_FRAME_INFO = undefined;
            var resource: *api.dxgi.IDXGIResource = undefined;
            const result = duplication.AcquireNextFrame(50, &info, &resource);
            if (result == api.dxgi.DXGI_ERROR_WAIT_TIMEOUT) continue;
            if (failed(result)) {
                if (result == api.dxgi.DXGI_ERROR_ACCESS_LOST) self.needs_recreation = true;
                return mapDxgiError(result);
            }

            var released = false;
            defer {
                if (!released) _ = duplication.ReleaseFrame();
                _ = resource.IUnknown.Release();
            }
            var frame = copyFrame(self, resource, &info, request) catch |err| {
                released = true;
                try releaseFrame(self, duplication);
                if (err == error.AccessLost) self.needs_recreation = true;
                if (err == error.StaleFrame) continue;
                return err;
            };
            released = true;
            releaseFrame(self, duplication) catch |err| {
                frame.deinit();
                return err;
            };
            return frame;
        }
    }

    fn recreate(self: *Session) Error!void {
        if (!self.needs_recreation) return error.RecreationNotRequired;
        const next_generation = std.math.add(u64, self.generation, 1) catch return error.InvalidRequest;
        const allocator = self.allocator;
        const output_index = self.output_index;
        deinit(self);
        var fresh = try open(allocator, output_index);
        fresh.generation = next_generation;
        self.* = fresh;
    }
} else struct {
    fn open(_: std.mem.Allocator, _: u32) Error!Session {
        return error.UnsupportedTarget;
    }

    fn deinit(self: *Session) void {
        self.factory = null;
        self.adapter = null;
        self.dxgi_output = null;
        self.output5 = null;
        self.device = null;
        self.context = null;
        self.duplication = null;
    }

    fn acquireAfter(_: *Session, _: AcquireRequest) Error!Frame {
        return error.UnsupportedTarget;
    }

    fn recreate(_: *Session) Error!void {
        return error.UnsupportedTarget;
    }
};

test "portable surface rejects live capture without Windows" {
    if (builtin.os.tag != .windows) {
        try std.testing.expectError(error.UnsupportedTarget, Session.open(std.testing.allocator, 0));
    }
}
