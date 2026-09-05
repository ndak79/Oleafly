const std = @import("std");
const sqlite = @import("sqlite");
const probe = @import("sqlite_probe");
const contract = @import("sqlite_contract");

// Independent acceptance values from the approved plan and locked 3.53.4
// sources. Do not derive these from the implementation's expected values.
const flags = [_][]const u8{
    "-DSQLITE_ENABLE_FTS5=1",               "-DSQLITE_THREADSAFE=1",                  "-DSQLITE_DEFAULT_MEMSTATUS=1",
    "-DSQLITE_OMIT_LOAD_EXTENSION=1",       "-DSQLITE_OMIT_SHARED_CACHE=1",           "-DSQLITE_OMIT_DEPRECATED=1",
    "-DSQLITE_DQS=0",                       "-DSQLITE_TRUSTED_SCHEMA=0",              "-DSQLITE_MAX_MMAP_SIZE=0",
    "-DSQLITE_TEMP_STORE=3",                "-DSQLITE_MAX_LENGTH=6291456",            "-DSQLITE_MAX_SQL_LENGTH=6291456",
    "-DSQLITE_MAX_ALLOCATION_SIZE=8388608", "-DSQLITE_PRINTF_PRECISION_LIMIT=100000",
};
const source_id = "2026-07-24 19:02:57 bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc";

test "exact source locks and the complete C compilation flag list" {
    if (comptime @hasDecl(sqlite, "Contract")) {
        try std.testing.expectEqualStrings("3.53.4", sqlite.Contract.version);
        try std.testing.expectEqualStrings(source_id, sqlite.Contract.source_id);
        try std.testing.expectEqual(@as(usize, 2), probe.source_locks.len);
        try std.testing.expectEqualStrings("sqlite3.c", probe.source_locks[0].name);
        try std.testing.expectEqual(@as(usize, 9_515_341), probe.source_locks[0].size);
        try std.testing.expectEqualStrings("b1dd5d74ec7f29055a6684fa06fb3c2f6821c87dd38f9a458dfd2e8a1db28189", probe.source_locks[0].sha256);
        try std.testing.expectEqualStrings("sqlite3.h", probe.source_locks[1].name);
        try std.testing.expectEqual(@as(usize, 690_838), probe.source_locks[1].size);
        try std.testing.expectEqualStrings("919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d", probe.source_locks[1].sha256);
        try std.testing.expectEqual(flags.len, contract.c_flags.len);
        for (flags, contract.c_flags) |expected, actual| try std.testing.expectEqualStrings(expected, actual);
        try std.testing.expectError(error.SourceSizeMismatch, probe.verifySource(probe.source_locks[0], "wrong"));
        var bad_hash = probe.source_locks[0];
        bad_hash.size = 5;
        try std.testing.expectError(error.SourceHashMismatch, probe.verifySource(bad_hash, "wrong"));
        inline for (.{ "@cImport", "@cInclude", "sqlite3_config", "SQLITE_CONFIG_PAGECACHE", "SQLITE_CONFIG_MALLOC", "SQLITE_CONFIG_PCACHE" }) |forbidden| {
            try std.testing.expect(std.mem.indexOf(u8, contract.wrapper_source, forbidden) == null);
        }
    } else return error.MissingSqliteContract;
}

test "runtime version source ID and thread safety come from the pinned amalgamation" {
    if (comptime @hasDecl(sqlite, "Contract")) {
        try std.testing.expectEqualStrings("3.53.4", std.mem.span(sqlite.sqlite3_libversion()));
        try std.testing.expectEqual(@as(c_int, 3_053_004), sqlite.sqlite3_libversion_number());
        try std.testing.expectEqualStrings(source_id, std.mem.span(sqlite.sqlite3_sourceid()));
        try std.testing.expectEqual(@as(c_int, 1), sqlite.sqlite3_threadsafe());
    } else return error.MissingSqliteContract;
}

test "snapshot reuse never opens a compiler-held verified source for writing" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var output = std.testing.tmpDir(.{});
    defer output.cleanup();
    const source_path = try std.Io.Dir.cwd().realPathFileAlloc(io, contract.source_root, allocator);
    defer allocator.free(source_path);
    var source = try std.Io.Dir.openDirAbsolute(io, source_path, .{});
    defer source.close(io);
    // Seed a complete published pair, then model a compiler that denies
    // FILE_SHARE_WRITE and FILE_SHARE_DELETE while reading sqlite3.c.
    for (probe.source_locks) |lock| {
        const bytes = try source.readFileAlloc(io, lock.name, allocator, .limited(lock.size + 1));
        defer allocator.free(bytes);
        try output.dir.writeFile(io, .{ .sub_path = lock.name, .data = bytes });
    }
    var output_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const output_path = output_path_buffer[0..try output.dir.realPath(io, &output_path_buffer)];
    const c_path = try std.fs.path.join(allocator, &.{ output_path, "sqlite3.c" });
    defer allocator.free(c_path);
    const c_path_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, c_path);
    defer allocator.free(c_path_w);
    const handle = SnapshotReader.CreateFileW(c_path_w, 0x80000000, 0x00000001, null, 3, 0, null);
    try std.testing.expect(handle != std.os.windows.INVALID_HANDLE_VALUE);
    defer std.os.windows.CloseHandle(handle);
    try probe.snapshot(allocator, io, source_path, output_path);
    for (probe.source_locks) |lock| {
        const bytes = try output.dir.readFileAlloc(io, lock.name, allocator, .limited(lock.size + 1));
        defer allocator.free(bytes);
        try probe.verifySource(lock, bytes);
    }
}

const SnapshotReader = struct {
    extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*const anyopaque, u32, u32, ?std.os.windows.HANDLE) callconv(.winapi) std.os.windows.HANDLE;
};

test "concurrent snapshot publishers expose one complete verified pair" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var output = std.testing.tmpDir(.{ .iterate = true });
    defer output.cleanup();
    const source_path = try std.Io.Dir.cwd().realPathFileAlloc(io, contract.source_root, allocator);
    defer allocator.free(source_path);
    var output_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const output_root = output_path_buffer[0..try output.dir.realPath(io, &output_path_buffer)];
    const final_path = try std.fs.path.join(allocator, &.{ output_root, "published" });
    defer allocator.free(final_path);
    var start: std.atomic.Value(bool) = .init(false);
    const Publisher = struct {
        io: std.Io,
        source: []const u8,
        output: []const u8,
        start: *std.atomic.Value(bool),
        failure: ?anyerror = null,

        fn run(self: *@This()) void {
            while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
            probe.snapshot(std.heap.page_allocator, self.io, self.source, self.output) catch |err| {
                self.failure = err;
            };
        }
    };
    var first = Publisher{ .io = io, .source = source_path, .output = final_path, .start = &start };
    var second = first;
    const first_thread = try std.Thread.spawn(.{}, Publisher.run, .{&first});
    const second_thread = std.Thread.spawn(.{}, Publisher.run, .{&second}) catch |err| {
        start.store(true, .release);
        first_thread.join();
        return err;
    };
    start.store(true, .release);
    first_thread.join();
    second_thread.join();
    if (first.failure) |err| return err;
    if (second.failure) |err| return err;
    var published = try output.dir.openDir(io, "published", .{});
    defer published.close(io);
    for (probe.source_locks) |lock| {
        const bytes = try published.readFileAlloc(io, lock.name, allocator, .limited(lock.size + 1));
        defer allocator.free(bytes);
        try probe.verifySource(lock, bytes);
    }
    var entries = output.dir.iterate();
    var count: usize = 0;
    while (try entries.next(io)) |entry| {
        try std.testing.expectEqualStrings("published", entry.name);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "an existing incomplete snapshot fails closed without being repaired" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var output = std.testing.tmpDir(.{});
    defer output.cleanup();
    try output.dir.writeFile(io, .{ .sub_path = "sqlite3.c", .data = "incomplete" });
    const source_path = try std.Io.Dir.cwd().realPathFileAlloc(io, contract.source_root, allocator);
    defer allocator.free(source_path);
    var output_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const output_path = output_path_buffer[0..try output.dir.realPath(io, &output_path_buffer)];
    try std.testing.expectError(error.SourceSizeMismatch, probe.snapshot(allocator, io, source_path, output_path));
    const retained = try output.dir.readFileAlloc(io, "sqlite3.c", allocator, .limited(64));
    defer allocator.free(retained);
    try std.testing.expectEqualStrings("incomplete", retained);
    try std.testing.expectError(error.FileNotFound, output.dir.openFile(io, "sqlite3.h", .{}));
}

test "all reported compile options and prohibited allocators are independently checked" {
    if (comptime @hasDecl(sqlite, "Contract")) {
        inline for (.{ "ENABLE_FTS5", "THREADSAFE=1", "OMIT_LOAD_EXTENSION", "OMIT_SHARED_CACHE", "OMIT_DEPRECATED", "DQS=0", "MAX_MMAP_SIZE=0", "TEMP_STORE=3", "MAX_LENGTH=6291456", "MAX_SQL_LENGTH=6291456", "SYSTEM_MALLOC" }) |option| {
            try std.testing.expectEqual(@as(c_int, 1), sqlite.sqlite3_compileoption_used(option));
            var index: c_int = 0;
            var found = false;
            while (sqlite.sqlite3_compileoption_get(index)) |entry| : (index += 1) {
                if (std.mem.eql(u8, std.mem.span(entry), option)) found = true;
            }
            try std.testing.expect(found);
        }
        // SQLite does not report DEFAULT_MEMSTATUS=1, TRUSTED_SCHEMA,
        // MAX_ALLOCATION_SIZE or PRINTF_PRECISION_LIMIT in compileoption_get.
        // The exact flag list and the behavioral tests cover those values.
        inline for (.{ "DEFAULT_MEMSTATUS=0", "ENABLE_MEMSYS3", "ENABLE_MEMSYS5", "MEMDEBUG", "WIN32_MALLOC", "OMIT_MEMORY_ALLOCATION", "OMIT_COMPILEOPTION_DIAGS", "OMIT_FTS5", "OMIT_WSD" }) |option| {
            try std.testing.expectEqual(@as(c_int, 0), sqlite.sqlite3_compileoption_used(option));
        }
        inline for (.{ "sqlite3_load_extension", "sqlite3_enable_load_extension", "sqlite3_auto_extension", "sqlite3_reset_auto_extension", "sqlite3_cancel_auto_extension", "sqlite3_enable_shared_cache", "sqlite3_aggregate_count", "sqlite3_expired", "sqlite3_transfer_bindings", "sqlite3_global_recover", "sqlite3_thread_cleanup", "sqlite3_memory_alarm", "sqlite3_soft_heap_limit", "sqlite3_trace", "sqlite3_profile", "sqlite3_config" }) |name| {
            try std.testing.expect(!@hasDecl(sqlite, name));
        }
    } else return error.MissingSqliteContract;
}

test "narrow ABI has exact integer widths opaque handles and C destructor convention" {
    if (comptime @hasDecl(sqlite, "Contract")) {
        const c = @cImport({
            @cInclude("sqlite3.h");
        });
        try std.testing.expect(sqlite.sqlite3_int64 == i64);
        try std.testing.expect(sqlite.sqlite3_uint64 == u64);
        try std.testing.expectEqual(@sizeOf(c.sqlite3_int64), @sizeOf(sqlite.sqlite3_int64));
        try std.testing.expectEqual(@alignOf(c.sqlite3_int64), @alignOf(sqlite.sqlite3_int64));
        try std.testing.expectEqual(@sizeOf(c.sqlite3_uint64), @sizeOf(sqlite.sqlite3_uint64));
        try std.testing.expectEqual(@as(usize, 4), @sizeOf(c_int));
        try std.testing.expect(@typeInfo(sqlite.sqlite3) == .@"opaque");
        try std.testing.expect(@typeInfo(sqlite.sqlite3_stmt) == .@"opaque");
        try std.testing.expect(sqlite.sqlite3 != sqlite.sqlite3_stmt);
        try std.testing.expectEqual(@sizeOf(?*c.sqlite3), @sizeOf(?*sqlite.sqlite3));
        try std.testing.expectEqual(@alignOf(?*c.sqlite3), @alignOf(?*sqlite.sqlite3));
        try std.testing.expectEqual(@sizeOf(?*c.sqlite3_stmt), @sizeOf(?*sqlite.sqlite3_stmt));
        try std.testing.expectEqual(@alignOf(?*c.sqlite3_stmt), @alignOf(?*sqlite.sqlite3_stmt));
        try std.testing.expect(sqlite.sqlite3_destructor_type == ?*const fn (?*anyopaque) callconv(.c) void);
        try std.testing.expect(sqlite.sqlite3_destructor_type == c.sqlite3_destructor_type);
        try std.testing.expectEqual(@as(usize, 8), @sizeOf(sqlite.sqlite3_destructor_type));
        try std.testing.expect(sqlite.SQLITE_STATIC == null);
        try std.testing.expectEqual(std.math.maxInt(usize), @intFromPtr(sqlite.SQLITE_TRANSIENT.?));
        try std.testing.expectEqual(c.SQLITE_OK, sqlite.SQLITE_OK);
        try std.testing.expectEqual(c.SQLITE_ROW, sqlite.SQLITE_ROW);
        try std.testing.expectEqual(c.SQLITE_DONE, sqlite.SQLITE_DONE);
        try std.testing.expectEqual(c.SQLITE_ERROR, sqlite.SQLITE_ERROR);
        try std.testing.expectEqual(c.SQLITE_NOMEM, sqlite.SQLITE_NOMEM);
        try std.testing.expectEqual(c.SQLITE_TOOBIG, sqlite.SQLITE_TOOBIG);
        try std.testing.expectEqual(c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_FULLMUTEX, sqlite.SQLITE_OPEN_READWRITE | sqlite.SQLITE_OPEN_CREATE | sqlite.SQLITE_OPEN_FULLMUTEX);
    } else return error.MissingSqliteContract;
}

test "static archive symbol audit rejects omitted APIs and malformed symbol tables" {
    const required = "sqlite3_libversion\x00sqlite3_sourceid\x00sqlite3_open_v2\x00sqlite3_hard_heap_limit64\x00sqlite3_auto_extension\x00sqlite3_reset_auto_extension\x00sqlite3_cancel_auto_extension\x00sqlite3_soft_heap_limit\x00";
    try probe.verifySymbols(required);
    try std.testing.expectError(error.MissingRequiredSqliteSymbol, probe.verifySymbols("other_library\x00"));
    const retained = [_][]const u8{ "sqlite3_auto_extension", "sqlite3_reset_auto_extension", "sqlite3_cancel_auto_extension", "sqlite3_soft_heap_limit" };
    try std.testing.expectEqual(retained.len, probe.retained_upstream_symbols.len);
    inline for (retained, probe.retained_upstream_symbols) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual);
        try std.testing.expect(!@hasDecl(sqlite, expected));
    }
    const forbidden = [_][]const u8{
        "sqlite3_load_extension",  "sqlite3_enable_load_extension", "sqlite3_enable_shared_cache",
        "sqlite3_aggregate_count", "sqlite3_expired",               "sqlite3_transfer_bindings",
        "sqlite3_global_recover",  "sqlite3_thread_cleanup",        "sqlite3_memory_alarm",
        "sqlite3_trace",           "sqlite3_profile",
    };
    try std.testing.expectEqual(forbidden.len, probe.prohibited_symbols.len);
    inline for (forbidden, probe.prohibited_symbols) |name, actual| {
        try std.testing.expectEqualStrings(name, actual);
        try std.testing.expectError(error.ProhibitedSqliteSymbol, probe.verifySymbols(required ++ name ++ "\x00"));
    }
    // Valid one-symbol COFF/GNU first linker member, then truncate/corrupt it.
    const names = "sqlite3_libversion\x00";
    const table_size = 8 + names.len;
    var archive: [68 + table_size]u8 = @splat(' ');
    @memcpy(archive[0..8], "!<arch>\n");
    archive[8] = '/';
    _ = try std.fmt.bufPrint(archive[56..66], "{d:<10}", .{table_size});
    @memcpy(archive[66..68], "`\n");
    std.mem.writeInt(u32, archive[68..72], 1, .big);
    std.mem.writeInt(u32, archive[72..76], 0, .big);
    @memcpy(archive[76..], names);
    try std.testing.expectEqualStrings(names, try probe.archiveSymbols(&archive));
    var padded: [archive.len + 1]u8 = undefined;
    @memcpy(padded[0..archive.len], &archive);
    padded[padded.len - 1] = 0;
    _ = try std.fmt.bufPrint(padded[56..66], "{d:<10}", .{table_size + 1});
    try std.testing.expectEqualStrings(names, try probe.archiveSymbols(&padded));
    padded[padded.len - 1] = '!';
    try std.testing.expectError(error.InvalidArchive, probe.archiveSymbols(&padded));
    try std.testing.expectError(error.InvalidArchive, probe.archiveSymbols(archive[0 .. archive.len - 1]));
    archive[archive.len - 1] = '!';
    try std.testing.expectError(error.InvalidArchive, probe.archiveSymbols(&archive));
    try std.testing.expectError(error.InvalidArchive, probe.archiveSymbols("not an archive"));
}

test "every exposed SQLite function preserves its independently transcribed C signature" {
    const D = sqlite.sqlite3;
    const S = sqlite.sqlite3_stmt;
    const Expected = struct {
        sqlite3_libversion: *const fn () callconv(.c) [*:0]const u8,
        sqlite3_libversion_number: *const fn () callconv(.c) c_int,
        sqlite3_sourceid: *const fn () callconv(.c) [*:0]const u8,
        sqlite3_threadsafe: *const fn () callconv(.c) c_int,
        sqlite3_compileoption_used: *const fn ([*:0]const u8) callconv(.c) c_int,
        sqlite3_compileoption_get: *const fn (c_int) callconv(.c) ?[*:0]const u8,
        sqlite3_open_v2: *const fn ([*:0]const u8, *?*D, c_int, ?[*:0]const u8) callconv(.c) c_int,
        sqlite3_close: *const fn (*D) callconv(.c) c_int,
        sqlite3_exec: *const fn (*D, [*:0]const u8, ?*const fn (?*anyopaque, c_int, ?[*]?[*:0]u8, [*]?[*:0]u8) callconv(.c) c_int, ?*anyopaque, ?*?[*:0]u8) callconv(.c) c_int,
        sqlite3_errmsg: *const fn (*D) callconv(.c) [*:0]const u8,
        sqlite3_prepare_v2: *const fn (*D, [*:0]const u8, c_int, *?*S, ?*?[*:0]const u8) callconv(.c) c_int,
        sqlite3_step: *const fn (*S) callconv(.c) c_int,
        sqlite3_finalize: *const fn (*S) callconv(.c) c_int,
        sqlite3_bind_int64: *const fn (*S, c_int, i64) callconv(.c) c_int,
        sqlite3_bind_text: *const fn (*S, c_int, [*]const u8, c_int, ?*const fn (?*anyopaque) callconv(.c) void) callconv(.c) c_int,
        sqlite3_column_int64: *const fn (*S, c_int) callconv(.c) i64,
        sqlite3_column_text: *const fn (*S, c_int) callconv(.c) ?[*:0]const u8,
        sqlite3_column_bytes: *const fn (*S, c_int) callconv(.c) c_int,
        sqlite3_limit: *const fn (*D, c_int, c_int) callconv(.c) c_int,
        sqlite3_memory_used: *const fn () callconv(.c) i64,
        sqlite3_memory_highwater: *const fn (c_int) callconv(.c) i64,
        sqlite3_soft_heap_limit64: *const fn (i64) callconv(.c) i64,
        sqlite3_hard_heap_limit64: *const fn (i64) callconv(.c) i64,
        sqlite3_malloc64: *const fn (u64) callconv(.c) ?*anyopaque,
        sqlite3_free: *const fn (?*anyopaque) callconv(.c) void,
    };
    inline for (@typeInfo(Expected).@"struct".fields) |field| {
        try std.testing.expect(field.type == @TypeOf(&@field(sqlite, field.name)));
    }
    // Any additional public C function must acquire a corresponding assertion.
    comptime var functions: usize = 0;
    inline for (@typeInfo(sqlite).@"struct".decls) |decl| {
        if (@typeInfo(@TypeOf(@field(sqlite, decl.name))) == .@"fn") functions += 1;
    }
    try std.testing.expectEqual(@typeInfo(Expected).@"struct".fields.len, functions);
}

fn openMemory() !*sqlite.sqlite3 {
    var db: ?*sqlite.sqlite3 = null;
    const status = sqlite.sqlite3_open_v2(":memory:", &db, sqlite.SQLITE_OPEN_READWRITE | sqlite.SQLITE_OPEN_CREATE | sqlite.SQLITE_OPEN_FULLMUTEX, null);
    errdefer if (db) |connection| {
        _ = sqlite.sqlite3_close(connection);
    };
    try std.testing.expectEqual(sqlite.SQLITE_OK, status);
    return db orelse error.MissingDatabase;
}

fn exec(db: *sqlite.sqlite3, sql: [:0]const u8) !void {
    const status = sqlite.sqlite3_exec(db, sql, null, null, null);
    if (status != sqlite.SQLITE_OK) std.debug.print("SQLite SQL failed: {s}\n", .{sqlite.sqlite3_errmsg(db)});
    try std.testing.expectEqual(sqlite.SQLITE_OK, status);
}

fn prepare(db: *sqlite.sqlite3, sql: [:0]const u8) !*sqlite.sqlite3_stmt {
    var statement: ?*sqlite.sqlite3_stmt = null;
    try std.testing.expectEqual(sqlite.SQLITE_OK, sqlite.sqlite3_prepare_v2(db, sql, -1, &statement, null));
    return statement orelse error.MissingStatement;
}

fn scalar(db: *sqlite.sqlite3, sql: [:0]const u8) !i64 {
    const statement = try prepare(db, sql);
    defer _ = sqlite.sqlite3_finalize(statement);
    try std.testing.expectEqual(sqlite.SQLITE_ROW, sqlite.sqlite3_step(statement));
    const value = sqlite.sqlite3_column_int64(statement, 0);
    try std.testing.expectEqual(sqlite.SQLITE_DONE, sqlite.sqlite3_step(statement));
    return value;
}

test "exec callback distinguishes an empty result null array from a SQL NULL element" {
    const NullableExecCallback = ?*const fn (?*anyopaque, c_int, ?[*]?[*:0]u8, [*]?[*:0]u8) callconv(.c) c_int;
    // Check the public contract before passing a callback that accepts the
    // NULL azVals supplied by SQLite's empty_result_callbacks mode.
    try std.testing.expect(sqlite.ExecCallback == NullableExecCallback);
    if (comptime sqlite.ExecCallback == NullableExecCallback) {
        const Observation = struct {
            calls: usize = 0,
            columns: c_int = 0,
            null_array: bool = false,
            null_element: bool = false,
            column_name_matches: bool = false,
            expected_column_name: []const u8,

            fn capture(context: ?*anyopaque, count: c_int, values: ?[*]?[*:0]u8, names: [*]?[*:0]u8) callconv(.c) c_int {
                const self: *@This() = @ptrCast(@alignCast(context orelse return 1));
                self.calls += 1;
                self.columns = count;
                self.null_array = values == null;
                // NULL array means no result row. A non-NULL array with a
                // NULL element means a result row containing SQL NULL.
                self.null_element = if (values) |items| count == 1 and items[0] == null else false;
                if (count == 1) {
                    if (names[0]) |name| self.column_name_matches = std.mem.eql(u8, std.mem.span(name), self.expected_column_name);
                }
                return 0;
            }
        };
        const db = try openMemory();
        defer _ = sqlite.sqlite3_close(db);
        try exec(db, "PRAGMA empty_result_callbacks=ON");
        var observation = Observation{ .expected_column_name = "1" };
        try std.testing.expectEqual(sqlite.SQLITE_OK, sqlite.sqlite3_exec(db, "SELECT 1 WHERE 0", Observation.capture, &observation, null));
        try std.testing.expectEqual(@as(usize, 1), observation.calls);
        try std.testing.expectEqual(@as(c_int, 1), observation.columns);
        try std.testing.expect(observation.null_array);
        try std.testing.expect(!observation.null_element);
        try std.testing.expect(observation.column_name_matches);

        observation = .{ .expected_column_name = "NULL" };
        try std.testing.expectEqual(sqlite.SQLITE_OK, sqlite.sqlite3_exec(db, "SELECT NULL", Observation.capture, &observation, null));
        try std.testing.expectEqual(@as(usize, 1), observation.calls);
        try std.testing.expectEqual(@as(c_int, 1), observation.columns);
        try std.testing.expect(!observation.null_array);
        try std.testing.expect(observation.null_element);
        try std.testing.expect(observation.column_name_matches);
    }
}

test "FTS5 unicode tokenization phrase matching and contentless delete known answers" {
    if (comptime @hasDecl(sqlite, "Contract")) {
        const db = try openMemory();
        defer std.testing.expectEqual(sqlite.SQLITE_OK, sqlite.sqlite3_close(db)) catch @panic("SQLite close failed");
        try exec(db, "CREATE VIRTUAL TABLE docs USING fts5(body, content='', contentless_delete=1, tokenize='unicode61 remove_diacritics 2')");
        try exec(db, "INSERT INTO docs(rowid,body) VALUES (1,'Café red green'),(2,'green blue'),(3,'red blue café')");
        try std.testing.expectEqual(@as(i64, 4), try scalar(db, "SELECT sum(rowid) FROM docs WHERE docs MATCH 'cafe'"));
        try std.testing.expectEqual(@as(i64, 1), try scalar(db, "SELECT rowid FROM docs WHERE docs MATCH '\"red green\"'"));
        try std.testing.expectEqual(@as(i64, 2), try scalar(db, "SELECT count(*) FROM docs WHERE docs MATCH 'bl*'"));
        try exec(db, "DELETE FROM docs WHERE rowid=1");
        try std.testing.expectEqual(@as(i64, 3), try scalar(db, "SELECT rowid FROM docs WHERE docs MATCH 'cafe'"));
        try std.testing.expectEqual(@as(i64, 0), try scalar(db, "SELECT count(*) FROM docs WHERE docs MATCH 'absent'"));
    } else return error.MissingSqliteContract;
}

var destructor_calls: usize = 0;
var destructor_pointer: ?*anyopaque = null;
fn destroyBoundText(pointer: ?*anyopaque) callconv(.c) void {
    destructor_calls += 1;
    destructor_pointer = pointer;
}

test "real C calls preserve signed int64 values and invoke the Zig text destructor once" {
    if (comptime @hasDecl(sqlite, "Contract")) {
        const db = try openMemory();
        defer _ = sqlite.sqlite3_close(db);
        const statement = try prepare(db, "SELECT ?1, ?2, ?3");
        var finalized = false;
        defer if (!finalized) {
            _ = sqlite.sqlite3_finalize(statement);
        };
        var text = [_]u8{ 'c', 'a', 'f', 0xc3, 0xa9 };
        var transient = [_]u8{ 'c', 'o', 'p', 'y' };
        destructor_calls = 0;
        destructor_pointer = null;
        try std.testing.expectEqual(sqlite.SQLITE_OK, sqlite.sqlite3_bind_int64(statement, 1, std.math.minInt(i64) + 1));
        try std.testing.expectEqual(sqlite.SQLITE_OK, sqlite.sqlite3_bind_text(statement, 2, &text, text.len, destroyBoundText));
        try std.testing.expectEqual(sqlite.SQLITE_OK, sqlite.sqlite3_bind_text(statement, 3, &transient, transient.len, sqlite.SQLITE_TRANSIENT));
        transient[0] = 'X';
        try std.testing.expectEqual(sqlite.SQLITE_ROW, sqlite.sqlite3_step(statement));
        try std.testing.expectEqual(std.math.minInt(i64) + 1, sqlite.sqlite3_column_int64(statement, 0));
        const bytes = sqlite.sqlite3_column_text(statement, 1) orelse return error.MissingColumnText;
        try std.testing.expectEqualStrings(&text, bytes[0..@intCast(sqlite.sqlite3_column_bytes(statement, 1))]);
        try std.testing.expectEqualStrings("copy", std.mem.span(sqlite.sqlite3_column_text(statement, 2).?));
        try std.testing.expectEqual(@as(usize, 0), destructor_calls);
        try std.testing.expectEqual(sqlite.SQLITE_OK, sqlite.sqlite3_finalize(statement));
        finalized = true;
        try std.testing.expectEqual(@as(usize, 1), destructor_calls);
        try std.testing.expect(destructor_pointer == @as(*anyopaque, @ptrCast(&text)));
    } else return error.MissingSqliteContract;
}

test "sealed defaults reject extension loading DQS oversized values and precision abuse" {
    if (comptime @hasDecl(sqlite, "Contract")) {
        const db = try openMemory();
        defer _ = sqlite.sqlite3_close(db);
        try std.testing.expectEqual(@as(i64, 0), try scalar(db, "PRAGMA trusted_schema"));
        try std.testing.expectEqual(@as(c_int, 6_291_456), sqlite.sqlite3_limit(db, 0, -1));
        try std.testing.expectEqual(@as(c_int, 6_291_456), sqlite.sqlite3_limit(db, 1, -1));
        try std.testing.expectEqual(@as(i64, 100_000), try scalar(db, "SELECT length(printf('%.*s',100001,replace(hex(zeroblob(50001)),'0','x')))"));
        try std.testing.expectEqual(@as(i64, 100_000), try scalar(db, "SELECT length(printf('%100001s','x'))"));
        var statement: ?*sqlite.sqlite3_stmt = null;
        try std.testing.expectEqual(sqlite.SQLITE_ERROR, sqlite.sqlite3_prepare_v2(db, "SELECT load_extension('not-a-library')", -1, &statement, null));
        try std.testing.expect(statement == null);
        try std.testing.expect(std.mem.indexOf(u8, std.mem.span(sqlite.sqlite3_errmsg(db)), "no such function: load_extension") != null);
        try std.testing.expectEqual(sqlite.SQLITE_ERROR, sqlite.sqlite3_prepare_v2(db, "SELECT \"not_a_column\"", -1, &statement, null));
        try std.testing.expect(statement == null);
        const large = try prepare(db, "SELECT zeroblob(6291457)");
        defer _ = sqlite.sqlite3_finalize(large);
        try std.testing.expectEqual(sqlite.SQLITE_TOOBIG, sqlite.sqlite3_step(large));
        try std.testing.expect(sqlite.sqlite3_malloc64(8_388_609) == null);
    } else return error.MissingSqliteContract;
}

test "default allocator and page cache are charged to the SQLite hard heap limit" {
    if (comptime @hasDecl(sqlite, "Contract")) {
        const old_limit = sqlite.sqlite3_hard_heap_limit64(-1);
        const old_soft = sqlite.sqlite3_soft_heap_limit64(-1);
        defer {
            _ = sqlite.sqlite3_hard_heap_limit64(old_limit);
            _ = sqlite.sqlite3_soft_heap_limit64(old_soft);
        }
        _ = sqlite.sqlite3_hard_heap_limit64(0);
        const db = try openMemory();
        defer _ = sqlite.sqlite3_close(db);
        try exec(db, "CREATE TABLE bytes(value BLOB)");
        const baseline = sqlite.sqlite3_memory_used();
        try std.testing.expect(baseline > 0);
        const allocation = sqlite.sqlite3_malloc64(4096) orelse return error.ExpectedAllocation;
        try std.testing.expect(sqlite.sqlite3_memory_used() >= baseline + 4096);
        sqlite.sqlite3_free(allocation);
        try std.testing.expectEqual(baseline, sqlite.sqlite3_memory_used());
        const limit = baseline + 256 * 1024;
        _ = sqlite.sqlite3_hard_heap_limit64(limit);
        try std.testing.expectEqual(limit, sqlite.sqlite3_hard_heap_limit64(-1));
        try std.testing.expect(sqlite.sqlite3_malloc64(512 * 1024) == null);
        try std.testing.expectEqual(sqlite.SQLITE_NOMEM, sqlite.sqlite3_exec(db, "INSERT INTO bytes VALUES(zeroblob(1048576))", null, null, null));
        try std.testing.expect(sqlite.sqlite3_memory_used() <= limit);
        try std.testing.expectEqual(@as(i64, 0), try scalar(db, "SELECT count(*) FROM bytes"));
        _ = sqlite.sqlite3_hard_heap_limit64(0);
        try exec(db, "INSERT INTO bytes VALUES(zeroblob(1048576))");
        try std.testing.expect(sqlite.sqlite3_memory_used() > baseline + 1024 * 1024);
        try std.testing.expect(sqlite.sqlite3_memory_highwater(0) >= sqlite.sqlite3_memory_used());
        try std.testing.expectEqual(@as(i64, 1), try scalar(db, "SELECT count(*) FROM bytes"));
    } else return error.MissingSqliteContract;
}
