const std = @import("std");
const builtin = @import("builtin");
const telemetry = @import("windows_telemetry");

const FakeState = struct {
    register_status: u32 = 0,
    write_status: u32 = 0,
    unregister_failures: u32 = 0,
    register_calls: u32 = 0,
    write_calls: u32 = 0,
    unregister_calls: u32 = 0,
    last_handle: u64 = 0,
    last_size: u32 = 0,
    last_count: u32 = 0,
};

var fake_state: FakeState = .{};

fn fakeEventRegister(_: *const telemetry.Guid, _: ?*anyopaque, _: ?*anyopaque, handle: *u64) callconv(.winapi) u32 {
    fake_state.register_calls += 1;
    if (fake_state.register_status != 0) return fake_state.register_status;
    handle.* = 0x5445_5846;
    return 0;
}

fn fakeEventWrite(handle: u64, _: *const telemetry.EventDescriptor, count: u32, data: *const telemetry.EventDataDescriptor) callconv(.winapi) u32 {
    fake_state.write_calls += 1;
    fake_state.last_handle = handle;
    fake_state.last_count = count;
    fake_state.last_size = data.Size;
    return fake_state.write_status;
}

fn fakeEventUnregister(handle: u64) callconv(.winapi) u32 {
    fake_state.unregister_calls += 1;
    fake_state.last_handle = handle;
    if (fake_state.unregister_failures != 0) {
        fake_state.unregister_failures -= 1;
        return 1;
    }
    return 0;
}

fn fakeAbi() telemetry.Abi {
    return .{
        .event_register = fakeEventRegister,
        .event_unregister = fakeEventUnregister,
        .event_write = fakeEventWrite,
    };
}

test "native ETW provider writes the fixed render payload" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const trial = try telemetry.parseTrialId("00112233445566778899aabbccddeeff");
    var provider = try telemetry.Provider.register(trial);
    defer provider.deinit();
    try std.testing.expect(provider.isRegistered());
    try provider.write(.{
        .trial_id = [_]u8{0} ** 16,
        .process_id = 42,
        .thread_id = 7,
        .qpc = 99,
        .adapter_luid = 123,
        .render_path = .hardware,
        .width = 1280,
        .height = 720,
        .dirty_pixels = 1280 * 720,
        .version = 1,
    });
    try provider.unregister();
    try std.testing.expect(!provider.isRegistered());
    try std.testing.expectError(error.NotRegistered, provider.unregister());
}

test "provider rejects a sentinel trial identity before registration" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    try std.testing.expectError(error.InvalidTrialId, telemetry.Provider.register([_]u8{0} ** 16));
}

test "ETW ABI structures retain the Windows wire sizes" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(telemetry.Guid));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(telemetry.EventDescriptor));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(telemetry.EventDataDescriptor));
    try std.testing.expectEqual(@as(u16, 1), telemetry.render_event_descriptor.Id);
    try std.testing.expectEqual(@as(u8, 1), telemetry.render_event_descriptor.Version);
}

test "provider teardown preserves a failed handle and retries unregister" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    fake_state = .{ .unregister_failures = 1 };
    const trial = try telemetry.parseTrialId("00112233445566778899aabbccddeeff");
    var provider = try telemetry.Provider.registerWithAbi(trial, fakeAbi());
    try std.testing.expectError(error.UnregisterFailed, provider.tryDeinit());
    try std.testing.expect(provider.isRegistered());
    try std.testing.expectEqual(@as(u32, 1), fake_state.unregister_calls);
    try provider.tryDeinit();
    try std.testing.expect(!provider.isRegistered());
    try std.testing.expectEqual(@as(u32, 2), fake_state.unregister_calls);
}

test "provider surfaces injected registration and write failures" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const trial = try telemetry.parseTrialId("00112233445566778899aabbccddeeff");
    fake_state = .{ .register_status = 1 };
    try std.testing.expectError(error.RegisterFailed, telemetry.Provider.registerWithAbi(trial, fakeAbi()));
    fake_state = .{ .write_status = 1 };
    var provider = try telemetry.Provider.registerWithAbi(trial, fakeAbi());
    defer provider.deinit();
    try std.testing.expectError(error.WriteFailed, provider.write(.{
        .trial_id = trial,
        .process_id = 42,
        .thread_id = 7,
        .qpc = 99,
        .adapter_luid = 123,
        .render_path = .hardware,
        .width = 1280,
        .height = 720,
        .dirty_pixels = 1280 * 720,
        .version = 1,
    }));
    try std.testing.expectEqual(@as(u32, 1), fake_state.write_calls);
    try std.testing.expectEqual(@as(u32, 1), fake_state.last_count);
    try std.testing.expectEqual(@as(u32, telemetry.encoded_size), fake_state.last_size);
}
