//! Fixture-only correlation runner. It never starts external tools.
const std = @import("std");
const events = @import("bench_events");
const presentmon = @import("bench_presentmon_csv");
const wpa = @import("bench_wpa_csv");

pub const Input = struct {
    payload: []const u8,
    presentmon_csv: []const u8,
    wpa_csv: []const u8,
    expected: struct { trial_id: [16]u8, process_id: u32, adapter_luid: u64 },
};
pub const Result = struct { presentmon_rows: usize, wpa_rows: usize, external_tools_executed: bool = false };

fn sameKey(present: presentmon.Row, event_row: wpa.Row) bool {
    return std.mem.eql(u8, &present.trial_id, &event_row.trial_id) and
        present.process_id == event_row.process_id and
        present.adapter_luid == event_row.adapter_luid and
        present.timestamp_qpc == event_row.timestamp_qpc;
}

fn payloadMatches(present: presentmon.Row, event_row: wpa.Row, event: anytype, encoded: []const u8) bool {
    return std.mem.eql(u8, &present.trial_id, &event.trial_id) and
        present.process_id == event.process_id and
        present.adapter_luid == event.adapter_luid and
        present.timestamp_qpc == event.qpc and
        std.mem.eql(u8, &event_row.trial_id, &event.trial_id) and
        event_row.process_id == event.process_id and
        event_row.adapter_luid == event.adapter_luid and
        event_row.timestamp_qpc == event.qpc and
        std.mem.eql(u8, &event_row.payload, encoded);
}

fn validateCorrelation(present: []const presentmon.Row, event_rows: []const wpa.Row) !void {
    if (present.len == 0 or event_rows.len == 0 or present.len != event_rows.len) return error.CorrelationMismatch;
    for (present) |present_row| {
        var matched = false;
        for (event_rows) |event_row| {
            if (sameKey(present_row, event_row)) {
                matched = true;
                break;
            }
        }
        if (!matched) return error.CorrelationMismatch;
    }
    for (event_rows) |event_row| {
        var matched = false;
        for (present) |present_row| {
            if (sameKey(present_row, event_row)) {
                matched = true;
                break;
            }
        }
        if (!matched) return error.CorrelationMismatch;
    }
}

pub fn validateFixture(input: Input) !Result {
    const event = try events.parse(input.payload);
    if (!std.mem.eql(u8, &event.trial_id, &input.expected.trial_id) or event.process_id != input.expected.process_id or event.adapter_luid != input.expected.adapter_luid) return error.PayloadMetadataMismatch;
    var present = try presentmon.parse(std.heap.page_allocator, input.presentmon_csv);
    defer present.deinit();
    try presentmon.validate(present.rows, .{ .trial_id = input.expected.trial_id, .process_id = input.expected.process_id, .adapter_luid = input.expected.adapter_luid });
    var wpa_table = try wpa.parse(std.heap.page_allocator, input.wpa_csv);
    defer wpa_table.deinit();
    try wpa.validate(wpa_table.rows, .{ .trial_id = input.expected.trial_id, .process_id = input.expected.process_id, .adapter_luid = input.expected.adapter_luid });
    try validateCorrelation(present.rows, wpa_table.rows);
    const encoded_event = event.encode() catch return error.PayloadMetadataMismatch;
    var payload_correlated = false;
    for (present.rows) |present_row| {
        for (wpa_table.rows) |event_row| {
            if (payloadMatches(present_row, event_row, event, encoded_event[0..])) {
                payload_correlated = true;
                break;
            }
        }
        if (payload_correlated) break;
    }
    if (!payload_correlated) return error.CorrelationMismatch;
    return .{ .presentmon_rows = present.rows.len, .wpa_rows = wpa_table.rows.len };
}
