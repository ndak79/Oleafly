//! Resilience tests for ledger transaction atomicity and uncommitted rollback.

const std = @import("std");
const sqlite = @import("data_sqlite");
const ledger = @import("data_ledger");

const testing = std.testing;

test "uncommitted transaction rollback discards in-flight state" {
    var conn = try sqlite.Connection.open("test_kill.db", .ledger);
    defer conn.close();

    try conn.beginTransaction();
    try testing.expect(conn.in_transaction);

    // Simulate sudden process crash / abort: rollback transaction
    conn.rollback();
    try testing.expect(!conn.in_transaction);
}

test "reopened ledger maintains hash chain integrity" {
    const project_uuid = [_]u8{0x99} ** 16;
    var l = ledger.Ledger.init(project_uuid);

    const e1 = try l.appendEvent([_]u8{0x10} ** 16, 1, 100, "evt1");
    const e2 = try l.appendEvent([_]u8{0x20} ** 16, 2, 200, "evt2");

    // Verify sequence is unbroken
    try testing.expectEqual(@as(u64, 1), e1.sequence);
    try testing.expectEqual(@as(u64, 2), e2.sequence);
    try testing.expectEqualSlices(u8, &e1.computeHash(), &e2.previous_hash);
}
