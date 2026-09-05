const std = @import("std");
const telemetry = @import("windows_telemetry");

test "telemetry trial ids are strict lowercase hex" {
    const id = try telemetry.parseTrialId("00112233445566778899aabbccddeeff");
    try std.testing.expectEqual(@as(u8, 0x00), id[0]);
    try std.testing.expectEqual(@as(u8, 0xff), id[15]);
    try std.testing.expectError(error.InvalidTrialId, telemetry.parseTrialId("00112233445566778899AABBCCDDEEFF"));
    try std.testing.expectError(error.InvalidTrialId, telemetry.parseTrialId("00"));
}

test "telemetry encoding is fixed width and excludes content-bearing fields" {
    const event = telemetry.Event{
        .trial_id = try telemetry.parseTrialId("00112233445566778899aabbccddeeff"),
        .process_id = 42,
        .thread_id = 7,
        .qpc = 99,
        .adapter_luid = 123,
        .render_path = .warp,
        .width = 1280,
        .height = 720,
        .dirty_pixels = 1280 * 720,
        .version = 1,
    };
    const encoded = try event.encode();
    try std.testing.expectEqual(telemetry.encoded_size, encoded.len);
    try std.testing.expectEqual(@as(u8, 2), encoded[40]);
    try std.testing.expectEqual(@as(u8, 0), encoded[63]);
    const invalid = telemetry.Event{
        .trial_id = event.trial_id,
        .process_id = 42,
        .thread_id = 7,
        .qpc = 99,
        .adapter_luid = 123,
        .render_path = .warp,
        .width = 10,
        .height = 10,
        .dirty_pixels = 101,
        .version = 1,
    };
    try std.testing.expectError(error.InvalidDirtyPixels, invalid.validate());
}
