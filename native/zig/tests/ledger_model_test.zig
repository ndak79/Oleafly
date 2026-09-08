//! Unit and property tests for the canonical event ledger and hash chain.

const std = @import("std");
const ledger = @import("data_ledger");

const testing = std.testing;

test "genesis event has zero previous hash and sequence 1" {
    const project_uuid = [_]u8{0x55} ** 16;
    var l = ledger.Ledger.init(project_uuid);

    const event_uuid = [_]u8{0x01} ** 16;
    const payload = "{\"init\":\"test\"}";

    const event = try l.appendEvent(event_uuid, 1, 1000, payload);
    try testing.expectEqual(@as(u64, 1), event.sequence);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 32), &event.previous_hash);
    try testing.expectEqual(@as(u32, @intCast(payload.len)), event.payload_length);
    try testing.expectEqualSlices(u8, &event.computeHash(), &l.last_event_hash);
}

test "subsequent events chain previous hashes deterministically" {
    const project_uuid = [_]u8{0x55} ** 16;
    var l = ledger.Ledger.init(project_uuid);

    const e1 = try l.appendEvent([_]u8{0x01} ** 16, 1, 1000, "payload1");
    const e2 = try l.appendEvent([_]u8{0x02} ** 16, 2, 2000, "payload2");

    try testing.expectEqual(@as(u64, 2), e2.sequence);
    try testing.expectEqualSlices(u8, &e1.computeHash(), &e2.previous_hash);
    try testing.expect(!std.mem.eql(u8, &e1.computeHash(), &e2.computeHash()));
}

test "field reference null, empty, and content tags" {
    const null_ref = ledger.FieldReference.initNull(.title);
    try testing.expect(null_ref.is_null);
    try testing.expectEqual(@as(u32, 0), null_ref.byte_length);
    try testing.expectEqual(@as(usize, 0), null_ref.chunkCount());

    const empty_ref = ledger.FieldReference.initEmpty(.abstract);
    try testing.expect(!empty_ref.is_null);
    try testing.expectEqual(@as(u32, 0), empty_ref.byte_length);
    try testing.expectEqualSlices(u8, &ledger.empty_sha256, &empty_ref.content_sha256);

    const content = "This is a sample scientific abstract content.";
    const content_ref = ledger.FieldReference.initWithContent(.claim_text, content);
    try testing.expect(!content_ref.is_null);
    try testing.expectEqual(@as(u32, @intCast(content.len)), content_ref.byte_length);
    try testing.expectEqual(@as(usize, 1), content_ref.chunkCount());
}

test "chunk count calculates ceil of 256 KiB chunks" {
    var ref = ledger.FieldReference{
        .field_id = .evidence_text,
        .is_null = false,
        .byte_length = 256 * 1024, // exactly 1 chunk
        .content_sha256 = [_]u8{0} ** 32,
    };
    try testing.expectEqual(@as(usize, 1), ref.chunkCount());

    ref.byte_length = 256 * 1024 + 1; // 2 chunks
    try testing.expectEqual(@as(usize, 2), ref.chunkCount());

    ref.byte_length = 1024 * 1024; // 4 chunks (1 MiB max field size)
    try testing.expectEqual(@as(usize, 4), ref.chunkCount());
}
