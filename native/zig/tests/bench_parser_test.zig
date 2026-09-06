const std = @import("std");
const telemetry = @import("windows_telemetry");
const events = @import("bench_events");
const presentmon = @import("bench_presentmon_csv");
const wpa = @import("bench_wpa_csv");
const runner = @import("bench_runner");

const trial_text = "00112233445566778899aabbccddeeff";

fn eventFor(qpc: u64, adapter: u64, process_id: u32) telemetry.Event {
    return .{
        .trial_id = telemetry.parseTrialId(trial_text) catch unreachable,
        .process_id = process_id,
        .thread_id = 7,
        .qpc = qpc,
        .adapter_luid = adapter,
        .render_path = .hardware,
        .width = 1920,
        .height = 1080,
        .dirty_pixels = 1920 * 1080,
        .version = 1,
    };
}

fn hexPayload(event: telemetry.Event) [telemetry.encoded_size * 2]u8 {
    const bytes = event.encode() catch unreachable;
    var output: [telemetry.encoded_size * 2]u8 = undefined;
    for (bytes, 0..) |byte, index| {
        const digits = "0123456789abcdef";
        output[index * 2] = digits[byte >> 4];
        output[index * 2 + 1] = digits[byte & 0x0f];
    }
    return output;
}

test "fixed telemetry parser accepts the exact payload and rejects structural mutations" {
    const encoded = try eventFor(100, 0x1234, 42).encode();
    const parsed = try events.parse(encoded[0..]);
    try std.testing.expectEqual(@as(u32, 42), parsed.process_id);
    try std.testing.expectEqual(@as(u64, 0x1234), parsed.adapter_luid);

    try std.testing.expectError(error.InvalidPayloadLength, events.parse(encoded[0 .. encoded.len - 1]));

    var reserved = encoded;
    reserved[41] = 1;
    try std.testing.expectError(error.NonZeroReserved, events.parse(reserved[0..]));

    var unknown_path = encoded;
    unknown_path[40] = 99;
    try std.testing.expectError(error.InvalidRenderPath, events.parse(unknown_path[0..]));

    var zero_adapter = encoded;
    @memset(zero_adapter[32..40], 0);
    try std.testing.expectError(error.InvalidAdapter, events.parse(zero_adapter[0..]));
}

test "PresentMon-like fixture parser accepts rows and freezes strict schema" {
    const csv =
        "TrialId,PID,AdapterLuid,TimestampQpc,Lane,MsAllInputToPhotonLatency,Displayed,Lost\n" ++
        trial_text ++ ",42,4660,100,editor,8.25,1,0\n" ++
        trial_text ++ ",42,4660,101,\"shell\",9.50,1,0\n";
    var table = try presentmon.parse(std.testing.allocator, csv);
    defer table.deinit();
    try std.testing.expectEqual(@as(usize, 2), table.rows.len);
    try presentmon.validate(table.rows, .{
        .trial_id = try telemetry.parseTrialId(trial_text),
        .process_id = 42,
        .adapter_luid = 4660,
    });
    try std.testing.expectEqual(@as(u64, 101), table.rows[1].timestamp_qpc);
}

test "PresentMon-like fixture parser rejects NA locale numbers and hostile headers" {
    const header = "TrialId,PID,AdapterLuid,TimestampQpc,Lane,MsAllInputToPhotonLatency,Displayed,Lost\n";
    try std.testing.expectError(error.BomNotAllowed, presentmon.parse(std.testing.allocator, "\xef\xbb\xbf" ++ header ++ trial_text ++ ",42,4660,100,editor,8.25,1,0\n"));
    try std.testing.expectError(error.NotAvailable, presentmon.parse(std.testing.allocator, header ++ trial_text ++ ",42,4660,100,editor,NA,1,0\n"));
    try std.testing.expectError(error.InvalidNumber, presentmon.parse(std.testing.allocator, header ++ trial_text ++ ",42,4660,100,editor,8,25,1,0\n"));
    try std.testing.expectError(error.InvalidNumber, presentmon.parse(std.testing.allocator, header ++ trial_text ++ ",42,4660,100,editor,inf,1,0\n"));
    try std.testing.expectError(error.InvalidNumber, presentmon.parse(std.testing.allocator, header ++ trial_text ++ ",42,4660,100,editor,-1.0,1,0\n"));
    try std.testing.expectError(error.InvalidTrialId, presentmon.parse(std.testing.allocator, header ++ "00000000000000000000000000000000,42,4660,100,editor,8.25,1,0\n"));
    try std.testing.expectError(error.DuplicateColumn, presentmon.parse(std.testing.allocator, "TrialId,PID,PID,TimestampQpc,Lane,MsAllInputToPhotonLatency,Displayed,Lost\n" ++ trial_text ++ ",42,4660,100,editor,8.25,1,0\n"));
    try std.testing.expectError(error.ReorderedColumn, presentmon.parse(std.testing.allocator, "TrialId,PID,TimestampQpc,AdapterLuid,Lane,MsAllInputToPhotonLatency,Displayed,Lost\n" ++ trial_text ++ ",42,100,4660,editor,8.25,1,0\n"));
    try std.testing.expectError(error.MalformedCsv, presentmon.parse(std.testing.allocator, header ++ trial_text ++ ",42,4660,100,\"editor,8.25,1,0\n"));
    try std.testing.expectError(error.MalformedCsv, presentmon.parse(std.testing.allocator, header ++ trial_text ++ ",42,4660,100,\"ed\"itor\",8.25,1,0\n"));
}

test "PresentMon-like validator rejects correlation, timestamp, and loss failures" {
    const header = "TrialId,PID,AdapterLuid,TimestampQpc,Lane,MsAllInputToPhotonLatency,Displayed,Lost\n";
    const csv = header ++ trial_text ++ ",42,4660,100,editor,8.25,1,0\n" ++ trial_text ++ ",42,4660,101,shell,9.50,1,0\n";
    var table = try presentmon.parse(std.testing.allocator, csv);
    defer table.deinit();
    const expected: presentmon.Expected = .{
        .trial_id = try telemetry.parseTrialId(trial_text),
        .process_id = 42,
        .adapter_luid = 4660,
    };

    var mixed_pid = table.rows;
    mixed_pid[1].process_id = 43;
    try std.testing.expectError(error.MixedProcess, presentmon.validate(mixed_pid, expected));
    table.rows[1].process_id = 42;

    var discontinuous = table.rows;
    discontinuous[1].timestamp_qpc = 100;
    try std.testing.expectError(error.TimestampDiscontinuity, presentmon.validate(discontinuous, expected));

    var lost = table.rows;
    lost[0].lost = true;
    try std.testing.expectError(error.LostSample, presentmon.validate(lost, expected));
}

test "WPA-like fixture parser validates payload, metadata, and loss" {
    const encoded = hexPayload(eventFor(100, 0x1234, 42));
    const csv =
        "TrialId,PID,AdapterLuid,TimestampQpc,Provider,EventName,PayloadHex,Lost\n" ++
        trial_text ++ ",42,4660,100,texflow,render," ++ &encoded ++ ",0\n";
    var table = try wpa.parse(std.testing.allocator, csv);
    defer table.deinit();
    try std.testing.expectEqual(@as(usize, 1), table.rows.len);
    try wpa.validate(table.rows, .{
        .trial_id = try telemetry.parseTrialId(trial_text),
        .process_id = 42,
        .adapter_luid = 4660,
    });

    var wrong_payload = table.rows;
    wrong_payload[0].payload[16] = 43;
    try std.testing.expectError(error.PayloadMetadataMismatch, wpa.validate(wrong_payload, .{
        .trial_id = try telemetry.parseTrialId(trial_text),
        .process_id = 42,
        .adapter_luid = 4660,
    }));
}

test "fixture runner is bounded to pure correlation and does not claim an external campaign" {
    const payload = eventFor(100, 0x1234, 42).encode() catch unreachable;
    const payload_hex = hexPayload(eventFor(100, 0x1234, 42));
    const presentmon_csv =
        "TrialId,PID,AdapterLuid,TimestampQpc,Lane,MsAllInputToPhotonLatency,Displayed,Lost\n" ++
        trial_text ++ ",42,4660,100,editor,8.25,1,0\n";
    const wpa_csv =
        "TrialId,PID,AdapterLuid,TimestampQpc,Provider,EventName,PayloadHex,Lost\n" ++
        trial_text ++ ",42,4660,100,texflow,render," ++ &payload_hex ++ ",0\n";
    const result = try runner.validateFixture(.{
        .payload = &payload,
        .presentmon_csv = presentmon_csv,
        .wpa_csv = wpa_csv,
        .expected = .{
            .trial_id = try telemetry.parseTrialId(trial_text),
            .process_id = 42,
            .adapter_luid = 4660,
        },
    });
    try std.testing.expectEqual(@as(usize, 1), result.presentmon_rows);
    try std.testing.expectEqual(@as(usize, 1), result.wpa_rows);
    try std.testing.expect(!result.external_tools_executed);

    const shifted_payload_hex = hexPayload(eventFor(101, 0x1234, 42));
    const shifted_wpa_csv =
        "TrialId,PID,AdapterLuid,TimestampQpc,Provider,EventName,PayloadHex,Lost\n" ++
        trial_text ++ ",42,4660,101,texflow,render," ++ &shifted_payload_hex ++ ",0\n";
    try std.testing.expectError(error.CorrelationMismatch, runner.validateFixture(.{
        .payload = &payload,
        .presentmon_csv = presentmon_csv,
        .wpa_csv = shifted_wpa_csv,
        .expected = .{
            .trial_id = try telemetry.parseTrialId(trial_text),
            .process_id = 42,
            .adapter_luid = 4660,
        },
    }));
}
