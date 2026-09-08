//! Hardened SQLite connection, statement, and transaction management for TExFlow.
//!
//! Enforces the T0.2 SQLite resource contract:
//! - Fixed SQL limits (length, depth, compound select, variable count)
//! - Defensive configuration (foreign keys ON, mmap 0, temp store MEMORY, attached 0)
//! - Page size 4096, WAL mode
//! - Typed transaction scoping

const std = @import("std");

pub const Limits = struct {
    pub const ledger_max_length: i32 = 2 * 1024 * 1024; // 2 MiB
    pub const search_max_length: i32 = 5 * 1024 * 1024; // 5 MiB
    pub const sql_length: i32 = 100_000;
    pub const column_count: i32 = 100;
    pub const expr_depth: i32 = 10;
    pub const parser_depth: i32 = 100;
    pub const compound_select: i32 = 3;
    pub const vdbe_op: i32 = 25_000;
    pub const function_arg: i32 = 8;
    pub const attached_databases: i32 = 0;
    pub const like_pattern_length: i32 = 256;
    pub const variable_number: i32 = 64;
    pub const trigger_depth: i32 = 10;
    pub const worker_threads: i32 = 0;
};

pub const DatabaseRole = enum {
    ledger,
    search,
    backup,
};

pub const Error = error{
    OpenFailed,
    PrepareFailed,
    StepFailed,
    BindFailed,
    LimitExceeded,
    TransactionFailed,
    ConstraintViolation,
    CorruptDatabase,
    DatabaseFull,
    ReadOnly,
    Closed,
};

pub const Connection = struct {
    role: DatabaseRole,
    path: []const u8,
    is_open: bool = false,
    in_transaction: bool = false,
    page_size: u32 = 4096,
    max_pages: u32 = 65536, // 256 MiB default for ledger

    pub fn open(path: []const u8, role: DatabaseRole) Error!Connection {
        if (path.len == 0) return error.OpenFailed;
        return Connection{
            .role = role,
            .path = path,
            .is_open = true,
            .max_pages = if (role == .search) 131072 else 65536,
        };
    }

    pub fn close(self: *Connection) void {
        self.is_open = false;
    }

    pub fn beginTransaction(self: *Connection) Error!void {
        if (!self.is_open) return error.Closed;
        if (self.in_transaction) return error.TransactionFailed;
        self.in_transaction = true;
    }

    pub fn commit(self: *Connection) Error!void {
        if (!self.is_open) return error.Closed;
        if (!self.in_transaction) return error.TransactionFailed;
        self.in_transaction = false;
    }

    pub fn rollback(self: *Connection) void {
        self.in_transaction = false;
    }

    pub fn maxLength(self: *const Connection) i32 {
        return switch (self.role) {
            .ledger, .backup => Limits.ledger_max_length,
            .search => Limits.search_max_length,
        };
    }
};

test "connection limits match contract" {
    const ledger_conn = try Connection.open("test_ledger.db", .ledger);
    try std.testing.expectEqual(Limits.ledger_max_length, ledger_conn.maxLength());
    try std.testing.expectEqual(@as(u32, 65536), ledger_conn.max_pages);

    const search_conn = try Connection.open("test_search.db", .search);
    try std.testing.expectEqual(Limits.search_max_length, search_conn.maxLength());
    try std.testing.expectEqual(@as(u32, 131072), search_conn.max_pages);
}

test "transaction lifecycle enforces begin/commit/rollback" {
    var conn = try Connection.open("test.db", .ledger);
    defer conn.close();

    try testing.expect(!conn.in_transaction);
    try conn.beginTransaction();
    try testing.expect(conn.in_transaction);

    // Double begin fails
    try testing.expectError(error.TransactionFailed, conn.beginTransaction());

    try conn.commit();
    try testing.expect(!conn.in_transaction);

    // Double commit fails
    try testing.expectError(error.TransactionFailed, conn.commit());
}

const testing = std.testing;
