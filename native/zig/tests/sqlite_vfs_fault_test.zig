//! Contract tests for SQLite limits, defensive config, and fault boundaries.

const std = @import("std");
const sqlite = @import("data_sqlite");

const testing = std.testing;

test "sqlite limits match T0.2 contract constants" {
    try testing.expectEqual(@as(i32, 2 * 1024 * 1024), sqlite.Limits.ledger_max_length);
    try testing.expectEqual(@as(i32, 5 * 1024 * 1024), sqlite.Limits.search_max_length);
    try testing.expectEqual(@as(i32, 100_000), sqlite.Limits.sql_length);
    try testing.expectEqual(@as(i32, 100), sqlite.Limits.column_count);
    try testing.expectEqual(@as(i32, 10), sqlite.Limits.expr_depth);
    try testing.expectEqual(@as(i32, 3), sqlite.Limits.compound_select);
    try testing.expectEqual(@as(i32, 25_000), sqlite.Limits.vdbe_op);
    try testing.expectEqual(@as(i32, 0), sqlite.Limits.attached_databases);
    try testing.expectEqual(@as(i32, 64), sqlite.Limits.variable_number);
    try testing.expectEqual(@as(i32, 0), sqlite.Limits.worker_threads);
}

test "connection handles path and open state cleanly" {
    var conn = try sqlite.Connection.open("ledger.db", .ledger);
    defer conn.close();

    try testing.expect(conn.is_open);
    try testing.expectEqualStrings("ledger.db", conn.path);
    try testing.expectEqual(sqlite.DatabaseRole.ledger, conn.role);
}
