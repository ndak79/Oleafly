const std = @import("std");
const builtin = @import("builtin");
const telemetry = @import("windows_telemetry");

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
