//! Narrow Zig-owned SQLite 3.53.4 C ABI for the isolated T0.2b probe.
//! No product integration, connection policy, alternate allocator, or loader.

pub const Contract = struct {
    pub const version = "3.53.4";
    pub const version_number = 3_053_004;
    pub const source_id = "2026-07-24 19:02:57 bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc";
    pub const c_flags: []const []const u8 = &.{
        "-DSQLITE_ENABLE_FTS5=1",
        "-DSQLITE_THREADSAFE=1",
        "-DSQLITE_DEFAULT_MEMSTATUS=1",
        "-DSQLITE_OMIT_LOAD_EXTENSION=1",
        "-DSQLITE_OMIT_SHARED_CACHE=1",
        "-DSQLITE_OMIT_DEPRECATED=1",
        "-DSQLITE_DQS=0",
        "-DSQLITE_TRUSTED_SCHEMA=0",
        "-DSQLITE_MAX_MMAP_SIZE=0",
        "-DSQLITE_TEMP_STORE=3",
        "-DSQLITE_MAX_LENGTH=6291456",
        // 3.53.4 requires MAX_SQL_LENGTH <= MAX_LENGTH at compile time.
        "-DSQLITE_MAX_SQL_LENGTH=6291456",
        "-DSQLITE_MAX_ALLOCATION_SIZE=8388608",
        "-DSQLITE_PRINTF_PRECISION_LIMIT=100000",
    };
};

pub const sqlite3 = opaque {};
pub const sqlite3_stmt = opaque {};
pub const sqlite3_int64 = i64;
pub const sqlite3_uint64 = u64;
pub const sqlite3_destructor_type = ?*const fn (?*anyopaque) callconv(.c) void;
// empty_result_callbacks may report column names with no result-value array.
pub const ExecCallback = ?*const fn (?*anyopaque, c_int, ?[*]?[*:0]u8, [*]?[*:0]u8) callconv(.c) c_int;
pub const SQLITE_STATIC: sqlite3_destructor_type = null;
pub const SQLITE_TRANSIENT: sqlite3_destructor_type = @ptrFromInt(~@as(usize, 0));
pub const SQLITE_OK: c_int = 0;
pub const SQLITE_ERROR: c_int = 1;
pub const SQLITE_NOMEM: c_int = 7;
pub const SQLITE_TOOBIG: c_int = 18;
pub const SQLITE_ROW: c_int = 100;
pub const SQLITE_DONE: c_int = 101;
pub const SQLITE_OPEN_READWRITE: c_int = 0x00000002;
pub const SQLITE_OPEN_CREATE: c_int = 0x00000004;
pub const SQLITE_OPEN_FULLMUTEX: c_int = 0x00010000;

pub extern fn sqlite3_libversion() callconv(.c) [*:0]const u8;
pub extern fn sqlite3_libversion_number() callconv(.c) c_int;
pub extern fn sqlite3_sourceid() callconv(.c) [*:0]const u8;
pub extern fn sqlite3_threadsafe() callconv(.c) c_int;
pub extern fn sqlite3_compileoption_used([*:0]const u8) callconv(.c) c_int;
pub extern fn sqlite3_compileoption_get(c_int) callconv(.c) ?[*:0]const u8;
pub extern fn sqlite3_open_v2([*:0]const u8, *?*sqlite3, c_int, ?[*:0]const u8) callconv(.c) c_int;
pub extern fn sqlite3_close(*sqlite3) callconv(.c) c_int;
pub extern fn sqlite3_exec(*sqlite3, [*:0]const u8, ExecCallback, ?*anyopaque, ?*?[*:0]u8) callconv(.c) c_int;
pub extern fn sqlite3_errmsg(*sqlite3) callconv(.c) [*:0]const u8;
pub extern fn sqlite3_prepare_v2(*sqlite3, [*:0]const u8, c_int, *?*sqlite3_stmt, ?*?[*:0]const u8) callconv(.c) c_int;
pub extern fn sqlite3_step(*sqlite3_stmt) callconv(.c) c_int;
pub extern fn sqlite3_finalize(*sqlite3_stmt) callconv(.c) c_int;
pub extern fn sqlite3_bind_int64(*sqlite3_stmt, c_int, sqlite3_int64) callconv(.c) c_int;
pub extern fn sqlite3_bind_text(*sqlite3_stmt, c_int, [*]const u8, c_int, sqlite3_destructor_type) callconv(.c) c_int;
pub extern fn sqlite3_column_int64(*sqlite3_stmt, c_int) callconv(.c) sqlite3_int64;
pub extern fn sqlite3_column_text(*sqlite3_stmt, c_int) callconv(.c) ?[*:0]const u8;
pub extern fn sqlite3_column_bytes(*sqlite3_stmt, c_int) callconv(.c) c_int;
pub extern fn sqlite3_limit(*sqlite3, c_int, c_int) callconv(.c) c_int;
pub extern fn sqlite3_memory_used() callconv(.c) sqlite3_int64;
pub extern fn sqlite3_memory_highwater(c_int) callconv(.c) sqlite3_int64;
pub extern fn sqlite3_soft_heap_limit64(sqlite3_int64) callconv(.c) sqlite3_int64;
pub extern fn sqlite3_hard_heap_limit64(sqlite3_int64) callconv(.c) sqlite3_int64;
pub extern fn sqlite3_malloc64(sqlite3_uint64) callconv(.c) ?*anyopaque;
pub extern fn sqlite3_free(?*anyopaque) callconv(.c) void;
