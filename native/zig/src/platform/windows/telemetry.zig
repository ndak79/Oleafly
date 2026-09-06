//! Fixed-schema render telemetry. No source text, paths, secrets, or paper
//! contents are representable in this payload.
const builtin = @import("builtin");
const std = @import("std");

pub const encoded_size: usize = 64;

pub const RenderPath = enum(u8) {
    hardware = 1,
    warp = 2,
    flip_sequential = 3,
    flip_discard = 4,
};

pub const Event = struct {
    trial_id: [16]u8,
    process_id: u32,
    thread_id: u32,
    qpc: u64,
    adapter_luid: u64,
    render_path: RenderPath,
    width: u32,
    height: u32,
    dirty_pixels: u64,
    version: u32,

    pub fn validate(self: Event) !void {
        var nonzero = false;
        for (self.trial_id) |byte| nonzero = nonzero or byte != 0;
        if (!nonzero) return error.EmptyTrialId;
        if (self.process_id == 0 or self.thread_id == 0) return error.InvalidOwner;
        if (self.qpc == 0 or self.version == 0) return error.InvalidClockOrVersion;
        if (self.width == 0 or self.height == 0) return error.InvalidDimensions;
        const pixels = std.math.mul(u64, self.width, self.height) catch return error.InvalidDimensions;
        if (self.dirty_pixels > pixels) return error.InvalidDirtyPixels;
    }

    pub fn encode(self: Event) ![encoded_size]u8 {
        try self.validate();
        var output = [_]u8{0} ** encoded_size;
        var offset: usize = 0;
        @memcpy(output[offset .. offset + 16], &self.trial_id);
        offset += 16;
        std.mem.writeInt(u32, output[offset..][0..4], self.process_id, .little);
        offset += 4;
        std.mem.writeInt(u32, output[offset..][0..4], self.thread_id, .little);
        offset += 4;
        std.mem.writeInt(u64, output[offset..][0..8], self.qpc, .little);
        offset += 8;
        std.mem.writeInt(u64, output[offset..][0..8], self.adapter_luid, .little);
        offset += 8;
        output[offset] = @intFromEnum(self.render_path);
        offset += 1;
        offset += 3;
        std.mem.writeInt(u32, output[offset..][0..4], self.width, .little);
        offset += 4;
        std.mem.writeInt(u32, output[offset..][0..4], self.height, .little);
        offset += 4;
        std.mem.writeInt(u64, output[offset..][0..8], self.dirty_pixels, .little);
        offset += 8;
        std.mem.writeInt(u32, output[offset..][0..4], self.version, .little);
        return output;
    }
};

pub fn parseTrialId(text: []const u8) ![16]u8 {
    if (text.len != 32) return error.InvalidTrialId;
    var result: [16]u8 = undefined;
    for (0..16) |index| {
        const high = hexNibble(text[index * 2]) orelse return error.InvalidTrialId;
        const low = hexNibble(text[index * 2 + 1]) orelse return error.InvalidTrialId;
        result[index] = (high << 4) | low;
    }
    if (!hasNonZeroByte(result[0..])) return error.InvalidTrialId;
    return result;
}

/// Narrow classic ETW ABI.  The payload is deliberately one opaque fixed-size
/// field so a provider manifest cannot reinterpret or accidentally expose
/// content-bearing members.  The UI shell registers this provider only after
/// DLL-search admission; disabled ETW remains a cheap EventWrite status path.
pub const Guid = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

pub const EventDescriptor = extern struct {
    Id: u16,
    Version: u8,
    Channel: u8,
    Level: u8,
    Opcode: u8,
    Task: u16,
    Keyword: u64,
};

pub const EventDataDescriptor = extern struct {
    Ptr: u64,
    Size: u32,
    Reserved: u32,
};

pub const provider_guid = Guid{
    .Data1 = 0x6f4e1f2a,
    .Data2 = 0x6c53,
    .Data3 = 0x4d91,
    .Data4 = .{ 0x9a, 0x8d, 0x7e, 0x6b, 0x5c, 0x4a, 0x3f, 0x21 },
};

pub const render_event_descriptor = EventDescriptor{
    .Id = 1,
    .Version = 1,
    .Channel = 0,
    .Level = 4, // TRACE_LEVEL_INFORMATION
    .Opcode = 0,
    .Task = 1,
    .Keyword = 1,
};

const raw = struct {
    extern "advapi32" fn EventRegister(*const Guid, ?*anyopaque, ?*anyopaque, *u64) callconv(.winapi) u32;
    extern "advapi32" fn EventUnregister(u64) callconv(.winapi) u32;
    extern "advapi32" fn EventWrite(u64, *const EventDescriptor, u32, *const EventDataDescriptor) callconv(.winapi) u32;
};

/// The provider keeps the ABI behind a tiny function table so native tests can
/// deterministically exercise registration/write/unregister failures without
/// patching advapi32 or relying on an ETW session being active. Production
/// callers always use `Provider.register`, which supplies the real functions.
pub const Abi = struct {
    event_register: *const fn (*const Guid, ?*anyopaque, ?*anyopaque, *u64) callconv(.winapi) u32,
    event_unregister: *const fn (u64) callconv(.winapi) u32,
    event_write: *const fn (u64, *const EventDescriptor, u32, *const EventDataDescriptor) callconv(.winapi) u32,
};

fn productionAbi() Abi {
    return .{
        .event_register = raw.EventRegister,
        .event_unregister = raw.EventUnregister,
        .event_write = raw.EventWrite,
    };
}

pub const ProviderError = error{
    UnsupportedTarget,
    InvalidTrialId,
    RegisterFailed,
    WriteFailed,
    NotRegistered,
    UnregisterFailed,
};

pub const Provider = struct {
    handle: ?u64 = null,
    trial_id: [16]u8 = [_]u8{0} ** 16,
    abi: Abi = productionAbi(),

    pub fn register(trial_id: [16]u8) ProviderError!Provider {
        return registerWithAbi(trial_id, productionAbi());
    }

    /// Deterministic ABI seam used by native tests. It does not add a second
    /// runtime path: the product entry point above remains the only production
    /// constructor and still binds directly to advapi32.
    pub fn registerWithAbi(trial_id: [16]u8, abi: Abi) ProviderError!Provider {
        if (comptime builtin.os.tag != .windows) return error.UnsupportedTarget;
        if (!hasNonZeroByte(trial_id[0..])) return error.InvalidTrialId;
        var handle: u64 = 0;
        if (abi.event_register(&provider_guid, null, null, &handle) != 0 or handle == 0) {
            return error.RegisterFailed;
        }
        return .{ .handle = handle, .trial_id = trial_id, .abi = abi };
    }

    pub fn write(self: *const Provider, event: Event) ProviderError!void {
        if (comptime builtin.os.tag != .windows) return error.UnsupportedTarget;
        const handle = self.handle orelse return error.NotRegistered;
        var enriched = event;
        enriched.trial_id = self.trial_id;
        const encoded = enriched.encode() catch return error.WriteFailed;
        const data = EventDataDescriptor{
            .Ptr = @intCast(@intFromPtr(encoded[0..].ptr)),
            .Size = @intCast(encoded.len),
            .Reserved = 0,
        };
        if (self.abi.event_write(handle, &render_event_descriptor, 1, &data) != 0) return error.WriteFailed;
    }

    pub fn unregister(self: *Provider) ProviderError!void {
        if (comptime builtin.os.tag != .windows) return error.UnsupportedTarget;
        const handle = self.handle orelse return error.NotRegistered;
        if (self.abi.event_unregister(handle) != 0) return error.UnregisterFailed;
        self.handle = null;
    }

    /// Teardown path with an observable error. A failed unregister leaves the
    /// handle intact, making a later call a real retry rather than a no-op.
    pub fn tryDeinit(self: *Provider) ProviderError!void {
        if (comptime builtin.os.tag != .windows) {
            self.handle = null;
            return;
        }
        if (self.handle != null) try self.unregister();
    }

    pub fn deinit(self: *Provider) void {
        // Best-effort callers retain the same retryable state as explicit
        // teardown; shell-owned paths use tryDeinit to surface the failure.
        _ = self.tryDeinit() catch {};
    }

    pub fn isRegistered(self: *const Provider) bool {
        return self.handle != null;
    }
};

fn hasNonZeroByte(bytes: []const u8) bool {
    for (bytes) |byte| if (byte != 0) return true;
    return false;
}

fn hexNibble(value: u8) ?u8 {
    return switch (value) {
        '0'...'9' => value - '0',
        'a'...'f' => value - 'a' + 10,
        else => null,
    };
}
