//! Deterministic event corpus for ledger verification and replay testing.

const std = @import("std");
const ledger = @import("../src/data/ledger.zig");

pub const test_project_uuid = [_]u8{0x01} ** 16;

pub const EventSpec = struct {
    event_uuid: [16]u8,
    kind: u16,
    recorded_utc_ms: i64,
    payload: []const u8,
};

pub const sample_events: [4]EventSpec = .{
    .{
        .event_uuid = [_]u8{0x10} ** 16,
        .kind = 1, // project_created
        .recorded_utc_ms = 1770000000000,
        .payload = "{\"action\":\"create_project\",\"title\":\"Quantum LaTeX\"}",
    },
    .{
        .event_uuid = [_]u8{0x20} ** 16,
        .kind = 2, // doc_attached
        .recorded_utc_ms = 1770000001000,
        .payload = "{\"action\":\"attach_document\",\"filename\":\"main.tex\"}",
    },
    .{
        .event_uuid = [_]u8{0x30} ** 16,
        .kind = 3, // field_updated
        .recorded_utc_ms = 1770000002000,
        .payload = "{\"action\":\"update_field\",\"field_id\":1,\"name\":\"title\"}",
    },
    .{
        .event_uuid = [_]u8{0x40} ** 16,
        .kind = 4, // snapshot_committed
        .recorded_utc_ms = 1770000003000,
        .payload = "{\"action\":\"commit_snapshot\",\"revision\":1}",
    },
};

test "event corpus is deterministic" {
    try std.testing.expectEqual(@as(usize, 4), sample_events.len);
}
