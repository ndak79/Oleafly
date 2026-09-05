const std = @import("std");
const builtin = @import("builtin");
const deps = @import("deps");
const deps_fetch = @import("deps_fetch");
const fixture_options = @import("fixture_options");

const sentinel_name = ".texflow-deps-fixture-root";
const sentinel_prefix = "texflow-deps-fixture-v1:";
const fixture_v1 = "fixture dependency payload version one\n";
const fixture_v1_sha256 = "d87a1a2c28b4acfabf164c0bb987e8750fa85a717047d6328457dd85be3553bd";

test "fixture worker rejects missing and mismatched root nonces" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
    var nonce_bytes: [16]u8 = undefined;
    io.random(&nonce_bytes);
    const nonce = std.fmt.bytesToHex(nonce_bytes, .lower);
    try writeSentinel(io, tmp.dir, &nonce);

    var wrong_nonce = [_]u8{'0'} ** 32;
    if (std.mem.eql(u8, &wrong_nonce, &nonce)) wrong_nonce[0] = '1';
    var wrong = try runWorker(std.testing.allocator, io, &.{
        fixture_options.worker_path,
        "fetch-v1",
        root,
        "none",
        &wrong_nonce,
    });
    defer wrong.deinit(std.testing.allocator);
    try expectFailureContaining(wrong, "UnsafeFixtureRoot");

    var missing = try runWorker(std.testing.allocator, io, &.{
        fixture_options.worker_path,
        "fetch-v1",
        root,
        "none",
    });
    defer missing.deinit(std.testing.allocator);
    try expectFailureContaining(missing, "UnsafeFixtureRoot");
    try std.testing.expectEqual(@as(usize, 0), try generationCount(io, tmp.dir));
}

test "two fetch processes serialize and the waiter reuses the published cache" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
    var nonce_bytes: [16]u8 = undefined;
    io.random(&nonce_bytes);
    const nonce = std.fmt.bytesToHex(nonce_bytes, .lower);
    try writeSentinel(io, tmp.dir, &nonce);

    var first = try spawnWorker(io, root, &nonce, "fetch-v1", "lock");
    defer first.kill(io);
    try expectMarkerWithin(io, &first, "LOCK_ACQUIRED\n", 10_000);

    var second = try spawnWorker(io, root, &nonce, "contend-fetch-no-source-v1", "none");
    defer second.kill(io);
    try expectMarkerWithin(io, &second, "CONTENDED\n", 10_000);

    try first.stdin.?.writeStreamingAll(io, "x");
    try expectSuccessfulTerm(try waitChildWithin(io, &first, 10_000));
    try expectSuccessfulTerm(try waitChildWithin(io, &second, 10_000));
    try std.testing.expectEqual(@as(usize, 1), try generationCount(io, tmp.dir));
}

test "publication keeps children immutable after pins close and before rename" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
    const nonce = [_]u8{'b'} ** 32;
    try writeSentinel(io, tmp.dir, &nonce);
    var child = try spawnWorker(io, root, &nonce, "fetch-v1", "stage_pins_released");
    defer child.kill(io);
    try expectMarkerWithin(io, &child, "STAGE_PINS_RELEASED\n", 10_000);

    var stage_name: ?[]u8 = null;
    defer if (stage_name) |name| std.testing.allocator.free(name);
    var entries = tmp.dir.iterate();
    while (try entries.next(io)) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".stage-")) {
            try std.testing.expect(stage_name == null);
            stage_name = try std.testing.allocator.dupe(u8, entry.name);
        }
    }
    var stage = try tmp.dir.openDir(io, stage_name orelse return error.MissingStage, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer stage.close(io);
    inline for (.{ "archive.bin", ".complete.json", "payload/PresentMon-2.5.1-x64.exe" }) |path| {
        if (stage.openFile(io, path, .{ .mode = .read_write, .follow_symlinks = false })) |file| {
            file.close(io);
            return error.PublicationAllowedChildWriter;
        } else |err| try std.testing.expectEqual(error.AccessDenied, err);
    }
    try std.testing.expectError(error.AccessDenied, stage.createFile(io, "unexpected", .{ .exclusive = true }));
    try std.testing.expectError(error.AccessDenied, stage.createFile(io, "payload/unexpected", .{ .exclusive = true }));
    try std.testing.expectError(error.AccessDenied, stage.deleteFile(io, "archive.bin"));
    try std.testing.expectError(error.AccessDenied, stage.deleteFile(io, "payload/PresentMon-2.5.1-x64.exe"));
    try child.stdin.?.writeStreamingAll(io, "x");
    try expectSuccessfulTerm(try waitChildWithin(io, &child, 10_000));
    try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "audit-v1");
    try std.testing.expectEqual(@as(usize, 1), try generationCount(io, tmp.dir));
}

test "bootstrap reconciles corrupt selected and retained generations before read-only export audit" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    inline for (.{ "seed-selected-payload-tamper-v1", "seed-inactive-payload-tamper-v1" }) |seed| {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();
        var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
        const nonce = [_]u8{'c'} ** 32;
        try writeSentinel(io, tmp.dir, &nonce);
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, seed);
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "bootstrap-v1");
        const before = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(before);
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "audit-v1");
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "bootstrap-no-source-v1");
        const after = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(after);
        try std.testing.expectEqualStrings(before, after);
    }
}

test "bootstrap preserves unsafe retained ACLs and reparse points without repair" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    inline for (.{ "seed-inactive-payload-acl-v1", "seed-inactive-payload-reparse-v1" }) |seed| {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();
        var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
        const nonce = [_]u8{'d'} ** 32;
        try writeSentinel(io, tmp.dir, &nonce);
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, seed);
        const before = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(before);
        var result = try runWorkerCommand(std.testing.allocator, io, root, &nonce, "bootstrap-no-source-v1", "none");
        defer result.deinit(std.testing.allocator);
        try expectFailure(result);
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, "SourceUnexpected") == null);
        const after = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(after);
        try std.testing.expectEqualStrings(before, after);
    }
}

test "an already-valid fetch and successful audit perform no cache writes" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
    var nonce_bytes: [16]u8 = undefined;
    io.random(&nonce_bytes);
    const nonce = std.fmt.bytesToHex(nonce_bytes, .lower);
    try writeSentinel(io, tmp.dir, &nonce);

    try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "fetch-v1");
    const before_fetch = try snapshotCache(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(before_fetch);
    try runWorkerExpectSuccess(
        std.testing.allocator,
        io,
        root,
        &nonce,
        "fetch-no-source-v1",
    );
    const after_fetch = try snapshotCache(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(after_fetch);
    try std.testing.expectEqualStrings(before_fetch, after_fetch);

    const before_audit = try snapshotCache(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(before_audit);
    try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "audit-v1");
    const after_audit = try snapshotCache(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(after_audit);
    try std.testing.expectEqualStrings(before_audit, after_audit);
}

test "seed fixture creates a valid sealed generation with no scratch entries" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
    const nonce = [_]u8{'e'} ** 32;
    try writeSentinel(io, tmp.dir, &nonce);
    try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "seed-valid-v1");
    try std.testing.expectEqual(@as(usize, 2), try generationCount(io, tmp.dir));
    var entries = tmp.dir.iterate();
    while (try entries.next(io)) |entry| {
        try std.testing.expect(std.mem.eql(u8, entry.name, sentinel_name) or
            std.mem.eql(u8, entry.name, ".lock") or
            std.mem.eql(u8, entry.name, deps.cache_v2_directory));
    }
    const before = try snapshotCache(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(before);
    try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "audit-v1");
    try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "fetch-no-source-v1");
    const after = try snapshotCache(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualStrings(before, after);
}

test "read-only audit emits one sanitized remediation for missing and tampered cache" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    inline for (.{ false, true }) |tampered| {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();
        var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
        const nonce = [_]u8{if (tampered) 'd' else 'c'} ** 32;
        try writeSentinel(io, tmp.dir, &nonce);
        if (tampered) {
            try runWorkerExpectSuccess(
                std.testing.allocator,
                io,
                root,
                &nonce,
                "seed-selected-payload-tamper-v1",
            );
        }
        const before = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(before);
        var audit = try runWorkerCommand(
            std.testing.allocator,
            io,
            root,
            &nonce,
            "audit-v1",
            "none",
        );
        defer audit.deinit(std.testing.allocator);
        try expectRemediation(audit, &nonce);
        const after = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(after);
        try std.testing.expectEqualStrings(before, after);
    }
}

fn expectRemediation(result: OwnedRunResult, sentinel: []const u8) !void {
    try expectFailure(result);
    const command = "zig build deps-fetch --summary all";
    const count = std.mem.count(u8, result.stdout, command) +
        std.mem.count(u8, result.stderr, command);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, sentinel) == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, sentinel) == null);
}

test "tamper is rejected read-only and fetch repairs through a new generation" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
    var nonce_bytes: [16]u8 = undefined;
    io.random(&nonce_bytes);
    const nonce = std.fmt.bytesToHex(nonce_bytes, .lower);
    try writeSentinel(io, tmp.dir, &nonce);

    try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "fetch-v1");
    try runWorkerExpectSuccess(
        std.testing.allocator,
        io,
        root,
        &nonce,
        "seed-selected-payload-tamper-v1",
    );
    const original_generation = try currentGeneration(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(original_generation);
    const before_audit = try snapshotCache(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(before_audit);

    var audit = try runWorkerCommand(
        std.testing.allocator,
        io,
        root,
        &nonce,
        "audit-v1",
        "none",
    );
    defer audit.deinit(std.testing.allocator);
    try expectFailure(audit);
    const after_audit = try snapshotCache(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(after_audit);
    try std.testing.expectEqualStrings(before_audit, after_audit);

    try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "fetch-v1");
    const repaired_generation = try currentGeneration(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(repaired_generation);
    try std.testing.expect(!std.mem.eql(u8, original_generation, repaired_generation));
    // The corrupt selected generation is quarantined only by exclusive repair;
    // the first valid v1 checkpoint remains as the rollback generation. The
    // read-only audit above remains byte/tree preserving.
    try std.testing.expectEqual(@as(usize, 2), try generationCount(io, tmp.dir));
    var quarantine = try tmp.dir.openDir(io, ".v2/presentmon/quarantine", .{ .iterate = true, .follow_symlinks = false });
    defer quarantine.close(io);
    var preserved = try quarantine.openDir(io, original_generation, .{ .iterate = true, .follow_symlinks = false });
    const preserved_payload = try preserved.readFileAlloc(io, "payload/PresentMon-2.5.1-x64.exe", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(preserved_payload);
    var expected_tamper = fixture_v1.*;
    expected_tamper[0] ^= 1;
    try std.testing.expectEqualStrings(&expected_tamper, preserved_payload);
    preserved.close(io);
    var sidecar_buffer: [64]u8 = undefined;
    const sidecar = try std.fmt.bufPrint(&sidecar_buffer, "{s}.json", .{original_generation});
    const evidence = try quarantine.readFileAlloc(io, sidecar, std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(evidence);
    try std.testing.expect(std.mem.indexOf(u8, evidence, "archive_sha256") != null);
    const after_repair = try snapshotCache(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(after_repair);
    try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "audit-v1");
    try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "fetch-no-source-v1");
    const after_reuse = try snapshotCache(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(after_reuse);
    try std.testing.expectEqualStrings(after_repair, after_reuse);
}

test "quarantine interruption is read-only rejected then reconciled without a source" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    inline for (.{ "quarantine", "quarantine_evidence" }) |pause| {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();
        var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
        const nonce = [_]u8{'b'} ** 32;
        try writeSentinel(io, tmp.dir, &nonce);
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "seed-selected-payload-tamper-v1");
        var child = try spawnWorker(io, root, &nonce, "fetch-v1", pause);
        defer child.kill(io);
        try expectMarkerWithin(io, &child, if (std.mem.eql(u8, pause, "quarantine")) "GENERATION_QUARANTINED\n" else "QUARANTINE_EVIDENCE_STARTED\n", 10_000);
        child.kill(io);
        const before = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(before);
        var audit = try runWorkerCommand(std.testing.allocator, io, root, &nonce, "audit-v1", "none");
        defer audit.deinit(std.testing.allocator);
        try expectFailure(audit);
        const after = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(after);
        try std.testing.expectEqualStrings(before, after);
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "fetch-no-source-v1");
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "audit-v1");
        try std.testing.expectEqual(@as(usize, 2), try generationCount(io, tmp.dir));
    }
}

test "quarantine evidence tampering is rejected by audit and fetch without mutation" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    inline for (.{ "hash", "identity", "schema", "malformed", "acl" }) |fault| {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();
        var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
        const nonce = [_]u8{'c'} ** 32;
        try writeSentinel(io, tmp.dir, &nonce);
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "seed-selected-payload-tamper-v1");
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "fetch-v1");
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "tamper-quarantine-" ++ fault);
        const before = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(before);
        inline for (.{ "audit-v1", "fetch-no-source-v1" }) |command| {
            var result = try runWorkerCommand(std.testing.allocator, io, root, &nonce, command, "none");
            defer result.deinit(std.testing.allocator);
            try expectFailure(result);
        }
        const after = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(after);
        try std.testing.expectEqualStrings(before, after);
    }
}

test "crashes on both sides of selector replacement always leave a valid selection" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var before_tmp = std.testing.tmpDir(.{ .iterate = true });
    defer before_tmp.cleanup();
    var before_root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const before_root = before_root_buffer[0..try before_tmp.dir.realPath(io, &before_root_buffer)];
    var before_nonce_bytes: [16]u8 = undefined;
    io.random(&before_nonce_bytes);
    const before_nonce = std.fmt.bytesToHex(before_nonce_bytes, .lower);
    try writeSentinel(io, before_tmp.dir, &before_nonce);
    try runWorkerExpectSuccess(
        std.testing.allocator,
        io,
        before_root,
        &before_nonce,
        "fetch-v1",
    );
    const old_generation = try currentGeneration(std.testing.allocator, io, before_tmp.dir);
    defer std.testing.allocator.free(old_generation);

    var before_child = try spawnWorker(
        io,
        before_root,
        &before_nonce,
        "fetch-v2",
        "generation",
    );
    defer before_child.kill(io);
    try expectMarkerWithin(io, &before_child, "GENERATION_PUBLISHED\n", 10_000);
    before_child.kill(io);
    const selection_after_first_crash = try currentGeneration(
        std.testing.allocator,
        io,
        before_tmp.dir,
    );
    defer std.testing.allocator.free(selection_after_first_crash);
    try std.testing.expectEqualStrings(old_generation, selection_after_first_crash);
    try runWorkerExpectSuccess(
        std.testing.allocator,
        io,
        before_root,
        &before_nonce,
        "audit-v1",
    );
    try runWorkerExpectSuccess(
        std.testing.allocator,
        io,
        before_root,
        &before_nonce,
        "fetch-v2",
    );
    try runWorkerExpectSuccess(
        std.testing.allocator,
        io,
        before_root,
        &before_nonce,
        "audit-v2",
    );

    var after_tmp = std.testing.tmpDir(.{ .iterate = true });
    defer after_tmp.cleanup();
    var after_root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const after_root = after_root_buffer[0..try after_tmp.dir.realPath(io, &after_root_buffer)];
    var after_nonce_bytes: [16]u8 = undefined;
    io.random(&after_nonce_bytes);
    const after_nonce = std.fmt.bytesToHex(after_nonce_bytes, .lower);
    try writeSentinel(io, after_tmp.dir, &after_nonce);
    try runWorkerExpectSuccess(
        std.testing.allocator,
        io,
        after_root,
        &after_nonce,
        "fetch-v1",
    );
    const after_old_generation = try currentGeneration(std.testing.allocator, io, after_tmp.dir);
    defer std.testing.allocator.free(after_old_generation);

    var after_child = try spawnWorker(
        io,
        after_root,
        &after_nonce,
        "fetch-v2",
        "selector",
    );
    defer after_child.kill(io);
    try expectMarkerWithin(io, &after_child, "SELECTOR_PUBLISHED\n", 10_000);
    after_child.kill(io);
    const selection_after_second_crash = try currentGeneration(
        std.testing.allocator,
        io,
        after_tmp.dir,
    );
    defer std.testing.allocator.free(selection_after_second_crash);
    try std.testing.expect(!std.mem.eql(u8, after_old_generation, selection_after_second_crash));
    try runWorkerExpectSuccess(
        std.testing.allocator,
        io,
        after_root,
        &after_nonce,
        "audit-v2",
    );
}

test "marker watchdog fails promptly and reaps a withholding worker" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
    var nonce_bytes: [16]u8 = undefined;
    io.random(&nonce_bytes);
    const nonce = std.fmt.bytesToHex(nonce_bytes, .lower);
    try writeSentinel(io, tmp.dir, &nonce);

    var child = try spawnWorker(io, root, &nonce, "withhold-marker-v1", "none");
    defer child.kill(io);
    try std.testing.expectError(
        error.WorkerDeadlineExceeded,
        expectMarkerWithin(io, &child, "NEVER\n", 100),
    );
}

test "a crash with a root stage is cleaned by the next exclusive fetch" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
    var nonce_bytes: [16]u8 = undefined;
    io.random(&nonce_bytes);
    const nonce = std.fmt.bytesToHex(nonce_bytes, .lower);
    try writeSentinel(io, tmp.dir, &nonce);

    var child = try spawnWorker(io, root, &nonce, "fetch-v1", "source");
    defer child.kill(io);
    try expectMarkerWithin(io, &child, "SOURCE_OPENED\n", 10_000);
    child.kill(io);
    try std.testing.expectEqual(@as(usize, 1), try rootStageCount(io, tmp.dir));
    try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "fetch-v1");
    try std.testing.expectEqual(@as(usize, 0), try rootStageCount(io, tmp.dir));
    try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "audit-v1");
}

test "mutable inherited ACL stages recover after archive and nested payload crashes" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    inline for (.{ "archive", "payload_materialized" }) |pause| {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();
        var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
        const nonce = [_]u8{'9'} ** 32;
        try writeSentinel(io, tmp.dir, &nonce);
        var child = try spawnWorker(io, root, &nonce, "fetch-nested-v1", pause);
        defer child.kill(io);
        try expectMarkerWithin(io, &child, if (std.mem.eql(u8, pause, "archive")) "ARCHIVE_MATERIALIZED\n" else "PAYLOAD_MATERIALIZED\n", 10_000);
        child.kill(io);
        try std.testing.expectEqual(@as(usize, 1), try rootStageCount(io, tmp.dir));
        var entries = tmp.dir.iterate();
        while (try entries.next(io)) |entry| {
            if (!std.mem.startsWith(u8, entry.name, ".stage-")) continue;
            var stage = try tmp.dir.openDir(io, entry.name, .{ .iterate = true, .follow_symlinks = false });
            defer stage.close(io);
            var archive = try stage.openFile(io, "archive.bin", .{ .follow_symlinks = false });
            defer archive.close(io);
            try std.testing.expect((try archive.stat(io)).size > 0);
            if (std.mem.eql(u8, pause, "payload_materialized")) {
                const payload = try stage.readFileAlloc(io, "payload/nested/deep/data.bin", std.testing.allocator, .limited(4096));
                defer std.testing.allocator.free(payload);
                try std.testing.expectEqualStrings(fixture_v1, payload);
            }
        }
        const before = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(before);
        var audit = try runWorkerCommand(std.testing.allocator, io, root, &nonce, "audit-nested-v1", "none");
        defer audit.deinit(std.testing.allocator);
        try expectFailure(audit);
        const after = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(after);
        try std.testing.expectEqualStrings(before, after);
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "bootstrap-nested-v1");
        try std.testing.expectEqual(@as(usize, 0), try rootStageCount(io, tmp.dir));
        try std.testing.expectEqual(@as(usize, 1), try generationCount(io, tmp.dir));
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "audit-nested-v1");
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "bootstrap-nested-no-source-v1");
    }
}

test "frozen stage crashes are rejected read-only and quarantined by exclusive recovery" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    inline for (.{ "stage_frozen", "stage_pins_released" }) |pause| {
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();
        var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
        const nonce = [_]u8{'e'} ** 32;
        try writeSentinel(io, tmp.dir, &nonce);
        var child = try spawnWorker(io, root, &nonce, "fetch-v1", pause);
        defer child.kill(io);
        try expectMarkerWithin(io, &child, if (std.mem.eql(u8, pause, "stage_frozen")) "STAGE_FROZEN\n" else "STAGE_PINS_RELEASED\n", 10_000);
        child.kill(io);
        try std.testing.expectEqual(@as(usize, 1), try rootStageCount(io, tmp.dir));
        const before = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(before);
        var audit = try runWorkerCommand(std.testing.allocator, io, root, &nonce, "audit-v1", "none");
        defer audit.deinit(std.testing.allocator);
        try expectFailure(audit);
        const after = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(after);
        try std.testing.expectEqualStrings(before, after);
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "bootstrap-v1");
        try std.testing.expectEqual(@as(usize, 0), try rootStageCount(io, tmp.dir));
        var quarantine = try tmp.dir.openDir(io, ".v2/presentmon/quarantine", .{ .iterate = true, .follow_symlinks = false });
        defer quarantine.close(io);
        var retained: usize = 0;
        var entries = quarantine.iterate();
        while (try entries.next(io)) |entry| {
            if (entry.kind == .directory) retained += 1;
        }
        try std.testing.expectEqual(@as(usize, 1), retained);
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "audit-v1");
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "bootstrap-no-source-v1");
    }
}

test "a partially frozen interrupted stage fails closed without deleting mixed ACL children" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
    const nonce = [_]u8{'f'} ** 32;
    try writeSentinel(io, tmp.dir, &nonce);
    var child = try spawnWorker(io, root, &nonce, "fetch-v1", "stage_children_frozen");
    defer child.kill(io);
    try expectMarkerWithin(io, &child, "STAGE_CHILDREN_FROZEN\n", 10_000);
    child.kill(io);
    const before = try snapshotCache(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(before);
    inline for (.{ "audit-v1", "bootstrap-no-source-v1", "fetch-no-source-v1" }) |command| {
        var result = try runWorkerCommand(std.testing.allocator, io, root, &nonce, command, "none");
        defer result.deinit(std.testing.allocator);
        try expectFailure(result);
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, "SourceUnexpected") == null);
        const after = try snapshotCache(std.testing.allocator, io, tmp.dir);
        defer std.testing.allocator.free(after);
        try std.testing.expectEqualStrings(before, after);
    }
    try std.testing.expectError(error.OwnerOnlyAclVerificationFailed, deps_fetch.runFixtureCacheOperation(
        std.testing.allocator,
        io,
        root,
        fixtureDirectArtifact(),
        fixture_v1,
        .bootstrap,
        .{},
    ));
    try std.testing.expectEqual(@as(usize, 1), try rootStageCount(io, tmp.dir));
}

test "audit rejects strict v2 schema tampering without mutation" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    inline for (std.meta.tags(SchemaTamper)) |tamper| {
        exerciseSchemaTamper(tamper) catch |err| {
            std.debug.print("strict-v2 fixture failed case={t} error={t}\n", .{ tamper, err });
            return err;
        };
    }
}

test "acquisition releases every allocation and preserves a recoverable transaction" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const archive = try makeStoredZip(std.testing.allocator, &.{
        .{ .name = "a.txt", .data = "aaa" },
        .{ .name = "b.txt", .data = "bbb" },
    });
    defer std.testing.allocator.free(archive);
    var archive_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(archive, &archive_digest, .{});
    const archive_digest_hex = std.fmt.bytesToHex(archive_digest, .lower);
    const members = [_]deps.MemberLock{
        .{ .path = "a.txt", .size_bytes = 3 },
        .{ .path = "b.txt", .size_bytes = 3 },
    };
    const artifact = fixtureZipArtifact(archive, &archive_digest_hex, &members);

    const empty_allocations = try runAcquisitionAllocationCampaign(archive, artifact, false);
    const replacement_allocations = try runAcquisitionAllocationCampaign(archive, artifact, true);
    try std.testing.expect(empty_allocations > 0);
    try std.testing.expect(replacement_allocations > 0);
}

const AllocationObserver = struct {
    materialization_started: bool = false,
    materialized: bool = false,
};

fn observeAllocation(
    context_opaque: ?*anyopaque,
    event: deps_fetch.FixtureEvent,
) anyerror!void {
    const context: *AllocationObserver = @ptrCast(@alignCast(context_opaque.?));
    switch (event) {
        .payload_materialization_started => context.materialization_started = true,
        .payload_materialized => context.materialized = true,
        else => {},
    }
}

fn runAcquisitionAllocationCampaign(
    archive: []const u8,
    artifact: deps.Artifact,
    with_old_generation: bool,
) !usize {
    const max_allocations = 1024;
    var observed_partial_materialization_oom = false;
    var source_digest_before: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(archive, &source_digest_before, .{});
    for (0..max_allocations) |fail_index| {
        errdefer std.debug.print(
            "acquisition-allocation postcondition old={} fail-index={d}\n",
            .{ with_old_generation, fail_index },
        );
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();
        var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
        const nonce = [_]u8{'a'} ** 32;
        try writeSentinel(io, tmp.dir, &nonce);

        var old_selector: ?[]u8 = null;
        defer if (old_selector) |selector| std.testing.allocator.free(selector);
        const old_artifact = fixtureDirectArtifact();
        if (with_old_generation) {
            try deps_fetch.runFixtureCacheOperation(
                std.testing.allocator,
                io,
                root,
                old_artifact,
                fixture_v1,
                .fetch,
                .{},
            );
            old_selector = try currentGeneration(std.testing.allocator, io, tmp.dir);
        }

        var observer: AllocationObserver = .{};
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        var succeeded = false;
        deps_fetch.runFixtureCacheOperation(
            failing.allocator(),
            io,
            root,
            artifact,
            archive,
            .fetch,
            .{ .context = &observer, .callback = observeAllocation },
        ) catch |err| {
            if (err != error.OutOfMemory) {
                std.debug.print(
                    "acquisition-allocation old={} fail-index={d} error={s}\n",
                    .{ with_old_generation, fail_index, @errorName(err) },
                );
                return err;
            }
            if (!failing.has_induced_failure) return error.UnexpectedOutOfMemory;
            if (observer.materialization_started and !observer.materialized) {
                observed_partial_materialization_oom = true;
            }
        };
        if (!failing.has_induced_failure) succeeded = true;
        if (failing.allocated_bytes != failing.freed_bytes) return error.MemoryLeakDetected;
        try assertNoStageNames(std.testing.allocator, io, tmp.dir);

        const selected = try maybeCurrentGeneration(std.testing.allocator, io, tmp.dir);
        defer if (selected) |name| std.testing.allocator.free(name);
        if (selected) |name| {
            const selected_artifact = if (old_selector != null and
                std.mem.eql(u8, name, old_selector.?))
                old_artifact
            else
                artifact;
            const selected_bytes = if (std.mem.eql(
                u8,
                selected_artifact.version,
                old_artifact.version,
            ))
                fixture_v1
            else
                archive;
            try deps_fetch.runFixtureCacheOperation(
                std.testing.allocator,
                io,
                root,
                selected_artifact,
                selected_bytes,
                .audit,
                .{},
            );
        } else {
            try deps_fetch.runFixtureCacheOperation(
                std.testing.allocator,
                io,
                root,
                artifact,
                archive,
                .fetch,
                .{},
            );
            try deps_fetch.runFixtureCacheOperation(
                std.testing.allocator,
                io,
                root,
                artifact,
                archive,
                .audit,
                .{},
            );
        }
        var source_digest_after: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(archive, &source_digest_after, .{});
        try std.testing.expectEqualSlices(u8, &source_digest_before, &source_digest_after);
        if (succeeded) {
            try std.testing.expect(observed_partial_materialization_oom);
            return fail_index;
        }
    }
    return error.AllocationCampaignLimitExceeded;
}

fn assertNoStageNames(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
) !void {
    var walker = try root.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (std.mem.startsWith(u8, entry.basename, ".stage-")) {
            return error.InterruptedStagePresent;
        }
    }
}

fn maybeCurrentGeneration(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
) !?[]u8 {
    return currentGeneration(allocator, io, root) catch |err| switch (err) {
        error.FileNotFound => null,
        else => |e| return e,
    };
}

fn fixtureDirectArtifact() deps.Artifact {
    return .{
        .id = "presentmon",
        .version = "fixture-v1",
        .purpose = "allocation fixture old generation",
        .source_url = "https://example.invalid/fixture",
        .license_spdx = "MIT",
        .license_url = "https://example.invalid/fixture/LICENSE",
        .url = "https://example.invalid/fixture.bin",
        .allowed_path_prefix = "/fixture.bin",
        .integrity = .byte_archive,
        .archive_format = .direct_file,
        .archive_root = "",
        .archive_size_bytes = fixture_v1.len,
        .archive_sha256 = fixture_v1_sha256,
        .expected_entries = 1,
        .expected_regular_files = 1,
        .download_limit_bytes = 4096,
        .expanded_limit_bytes = 4096,
        .expected_expanded_bytes = fixture_v1.len,
        .dependencies = &.{},
        .build_switches = &.{},
    };
}

fn fixtureZipArtifact(
    archive: []const u8,
    digest_hex: []const u8,
    members: []const deps.MemberLock,
) deps.Artifact {
    return .{
        .id = "presentmon",
        .version = "fixture-zip",
        .purpose = "allocation fixture two-member transaction",
        .source_url = "https://example.invalid/fixture",
        .license_spdx = "MIT",
        .license_url = "https://example.invalid/fixture/LICENSE",
        .url = "https://example.invalid/fixture.zip",
        .allowed_path_prefix = "/fixture.zip",
        .integrity = .byte_archive,
        .archive_format = .restricted_zip,
        .archive_root = "",
        .archive_size_bytes = archive.len,
        .archive_sha256 = digest_hex,
        .expected_entries = 2,
        .expected_regular_files = 2,
        .download_limit_bytes = 4096,
        .expanded_limit_bytes = 4096,
        .expected_expanded_bytes = 6,
        .inventory = members,
        .retained_members = members,
        .dependencies = &.{},
        .build_switches = &.{},
    };
}

const makeStoredZip = @import("deps_fetch_fixture_archive.zig").makeStoredZip;

const SchemaTamper = enum {
    unknown_root_file,
    root_reparse,
    extra_store_file,
    unknown_artifact,
    malformed_generation,
    generation_reparse,
    selected_archive_broad_acl,
    selected_payload_broad_acl,
    inactive_payload_reparse,
    inactive_payload_broad_acl,
    inactive_archive_broad_acl,
    inactive_payload_tamper,
    inactive_archive_tamper,
    inactive_receipt_tamper,
    inactive_unexpected_child,
    too_many_generations,
    quarantine_unknown_file,
    quarantine_malformed_generation,
    quarantine_generation_reparse,
    quarantine_too_many_generations,
    quarantine_orphan_sidecar,
    quarantine_selector_escape,
};

fn exerciseSchemaTamper(tamper: SchemaTamper) !void {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try tmp.dir.realPath(io, &root_buffer)];
    var nonce_bytes: [16]u8 = undefined;
    io.random(&nonce_bytes);
    const nonce = std.fmt.bytesToHex(nonce_bytes, .lower);
    try writeSentinel(io, tmp.dir, &nonce);
    const selected_acl = tamper == .selected_archive_broad_acl or
        tamper == .selected_payload_broad_acl;
    const has_quarantine = switch (tamper) {
        .quarantine_unknown_file, .quarantine_malformed_generation, .quarantine_generation_reparse, .quarantine_too_many_generations, .quarantine_orphan_sidecar, .quarantine_selector_escape => true,
        else => false,
    };
    const has_inactive_generation = tamper == .inactive_payload_reparse or
        tamper == .inactive_payload_broad_acl or
        tamper == .inactive_archive_broad_acl or
        tamper == .inactive_payload_tamper or
        tamper == .inactive_archive_tamper or
        tamper == .inactive_receipt_tamper or
        tamper == .inactive_unexpected_child;
    if (has_quarantine) {
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "seed-selected-payload-tamper-v1");
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "fetch-v1");
    } else if (selected_acl) {
        // Seed a sealed v2 cache with the selected generation's requested
        // broad ACL. This is built before the OWNER RIGHTS seal, so it does
        // not hold a descendant handle across Windows directory rename.
        const command = if (tamper == .selected_archive_broad_acl)
            "seed-selected-archive-acl-v1"
        else
            "seed-selected-payload-acl-v1";
        try runWorkerExpectSuccess(
            std.testing.allocator,
            io,
            root,
            &nonce,
            command,
        );
    } else if (has_inactive_generation) {
        // The seed command performs a normal v1 -> v2 acquisition, then adds
        // one immutable, intentionally corrupt retained generation.
        try runWorkerExpectSuccess(
            std.testing.allocator,
            io,
            root,
            &nonce,
            inactiveFaultCommand(tamper),
        );
    } else {
        try runWorkerExpectSuccess(std.testing.allocator, io, root, &nonce, "fetch-v1");
    }
    var store = try tmp.dir.openDir(io, ".v2/presentmon", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer store.close(io);
    var generations = try store.openDir(io, deps.cache_generations_directory, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer generations.close(io);
    switch (tamper) {
        .unknown_root_file => {
            var extra = try tmp.dir.createFile(io, "unexpected-root", .{ .exclusive = true });
            extra.close(io);
        },
        .root_reparse => {
            try tmp.dir.createDir(io, "root-junction", .default_dir);
            const target = try std.fs.path.join(std.testing.allocator, &.{ root, ".v2" });
            defer std.testing.allocator.free(target);
            const link = try std.fs.path.join(std.testing.allocator, &.{ root, "root-junction" });
            defer std.testing.allocator.free(link);
            try makeDirectoryJunction(std.testing.allocator, target, link);
        },
        .extra_store_file => {
            var extra = try store.createFile(io, "unexpected", .{ .exclusive = true });
            extra.close(io);
        },
        .unknown_artifact => try tmp.dir.createDir(io, ".v2/unknown-artifact", .default_dir),
        .malformed_generation => try generations.createDir(io, "not-a-generation", .default_dir),
        .generation_reparse => {
            const selected = try currentGeneration(std.testing.allocator, io, tmp.dir);
            defer std.testing.allocator.free(selected);
            const target = try std.fs.path.join(std.testing.allocator, &.{
                root,
                ".v2",
                "presentmon",
                deps.cache_generations_directory,
                selected,
            });
            defer std.testing.allocator.free(target);
            try generations.createDir(
                io,
                "g-ffffffffffffffffffffffff",
                .default_dir,
            );
            const link = try std.fs.path.join(std.testing.allocator, &.{
                root,
                ".v2",
                "presentmon",
                deps.cache_generations_directory,
                "g-ffffffffffffffffffffffff",
            });
            defer std.testing.allocator.free(link);
            try makeDirectoryJunction(std.testing.allocator, target, link);
        },
        .selected_archive_broad_acl, .selected_payload_broad_acl => {},
        .inactive_payload_reparse,
        .inactive_payload_broad_acl,
        .inactive_archive_broad_acl,
        .inactive_payload_tamper,
        .inactive_archive_tamper,
        .inactive_receipt_tamper,
        .inactive_unexpected_child,
        => {},
        .too_many_generations => try createGenerationOverflow(io, generations),
        .quarantine_unknown_file,
        .quarantine_malformed_generation,
        .quarantine_generation_reparse,
        .quarantine_too_many_generations,
        .quarantine_orphan_sidecar,
        .quarantine_selector_escape,
        => {
            var quarantine = try store.openDir(io, deps.cache_quarantine_directory, .{ .iterate = true, .follow_symlinks = false });
            defer quarantine.close(io);
            const name = "g-222222222222222222222222";
            switch (tamper) {
                .quarantine_unknown_file => {
                    var file = try quarantine.createFile(io, "unexpected", .{ .exclusive = true });
                    file.close(io);
                },
                .quarantine_malformed_generation => try quarantine.createDir(io, "not-a-generation", .default_dir),
                .quarantine_generation_reparse => {
                    const link_name = "g-ffffffffffffffffffffffff";
                    try quarantine.createDir(io, link_name, .default_dir);
                    const link = try std.fs.path.join(std.testing.allocator, &.{ root, ".v2", "presentmon", "quarantine", link_name });
                    defer std.testing.allocator.free(link);
                    try makeDirectoryJunction(std.testing.allocator, root, link);
                },
                .quarantine_too_many_generations => try createGenerationOverflow(io, quarantine),
                .quarantine_orphan_sidecar => {
                    var file = try quarantine.createFile(io, "g-ffffffffffffffffffffffff.json", .{ .exclusive = true });
                    file.close(io);
                },
                .quarantine_selector_escape => {
                    var buffer: [deps.cache_selector_max_bytes]u8 = undefined;
                    const selector = try deps.formatCacheSelector(&buffer, name);
                    var file = try store.createFile(io, deps.cache_selector_file, .{ .truncate = true });
                    defer file.close(io);
                    try file.writeStreamingAll(io, selector);
                    try file.sync(io);
                },
                else => unreachable,
            }
        },
    }
    const before = try snapshotCache(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(before);
    const audit_command = if (has_inactive_generation) "audit-v2" else "audit-v1";
    var audit = try runWorkerCommand(
        std.testing.allocator,
        io,
        root,
        &nonce,
        audit_command,
        "none",
    );
    defer audit.deinit(std.testing.allocator);
    try expectFailure(audit);
    const after = try snapshotCache(std.testing.allocator, io, tmp.dir);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualStrings(before, after);
}

fn inactiveFaultCommand(tamper: SchemaTamper) []const u8 {
    return switch (tamper) {
        .inactive_payload_reparse => "seed-inactive-payload-reparse-v1",
        .inactive_payload_broad_acl => "seed-inactive-payload-acl-v1",
        .inactive_archive_broad_acl => "seed-inactive-archive-acl-v1",
        .inactive_payload_tamper => "seed-inactive-payload-tamper-v1",
        .inactive_archive_tamper => "seed-inactive-archive-tamper-v1",
        .inactive_receipt_tamper => "seed-inactive-receipt-tamper-v1",
        .inactive_unexpected_child => "seed-inactive-unexpected-child-v1",
        else => unreachable,
    };
}

fn createGenerationOverflow(io: std.Io, generations: std.Io.Dir) !void {
    const hex = "0123456789abcdef";
    for (0..65) |index| {
        var name: [deps.cache_generation_name_bytes]u8 = undefined;
        name[0] = 'g';
        name[1] = '-';
        @memset(name[2..], '0');
        var value = index;
        var cursor = name.len;
        while (cursor > 2) : (cursor -= 1) {
            name[cursor - 1] = hex[value & 0xf];
            value >>= 4;
        }
        try generations.createDir(io, &name, .default_dir);
    }
}

fn makeDirectoryJunction(
    allocator: std.mem.Allocator,
    target_path: []const u8,
    link_path: []const u8,
) !void {
    const substitute_utf8 = try std.fmt.allocPrint(allocator, "\\??\\{s}", .{target_path});
    defer allocator.free(substitute_utf8);
    const substitute = try std.unicode.utf8ToUtf16LeAlloc(allocator, substitute_utf8);
    defer allocator.free(substitute);
    const display = try std.unicode.utf8ToUtf16LeAlloc(allocator, target_path);
    defer allocator.free(display);
    const substitute_bytes = substitute.len * @sizeOf(u16);
    const display_bytes = display.len * @sizeOf(u16);
    const path_bytes = substitute_bytes + 2 + display_bytes + 2;
    const reparse_data_length = 8 + path_bytes;
    const total_bytes = 8 + reparse_data_length;
    const buffer = try allocator.alloc(u8, total_bytes);
    defer allocator.free(buffer);
    @memset(buffer, 0);
    std.mem.writeInt(u32, buffer[0..4], io_reparse_tag_mount_point, .little);
    std.mem.writeInt(u16, buffer[4..6], @intCast(reparse_data_length), .little);
    std.mem.writeInt(u16, buffer[8..10], 0, .little);
    std.mem.writeInt(u16, buffer[10..12], @intCast(substitute_bytes), .little);
    std.mem.writeInt(u16, buffer[12..14], @intCast(substitute_bytes + 2), .little);
    std.mem.writeInt(u16, buffer[14..16], @intCast(display_bytes), .little);
    @memcpy(buffer[16 .. 16 + substitute_bytes], std.mem.sliceAsBytes(substitute));
    const display_start = 16 + substitute_bytes + 2;
    @memcpy(buffer[display_start .. display_start + display_bytes], std.mem.sliceAsBytes(display));

    const link_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, link_path);
    defer allocator.free(link_w);
    const handle = CreateFileW(
        link_w.ptr,
        generic_write,
        file_share_read | file_share_write | file_share_delete,
        null,
        open_existing,
        file_flag_open_reparse_point | file_flag_backup_semantics,
        null,
    );
    if (handle == std.os.windows.INVALID_HANDLE_VALUE) return error.JunctionOpenFailed;
    defer std.os.windows.CloseHandle(handle);
    var returned: u32 = 0;
    if (DeviceIoControl(
        handle,
        fsctl_set_reparse_point,
        buffer.ptr,
        @intCast(buffer.len),
        null,
        0,
        &returned,
        null,
    ) == 0) return error.JunctionCreationFailed;
}

const generic_write: u32 = 0x40000000;
const file_share_read: u32 = 0x00000001;
const file_share_write: u32 = 0x00000002;
const file_share_delete: u32 = 0x00000004;
const open_existing: u32 = 3;
const file_flag_open_reparse_point: u32 = 0x00200000;
const file_flag_backup_semantics: u32 = 0x02000000;
const io_reparse_tag_mount_point: u32 = 0xa0000003;
const fsctl_set_reparse_point: u32 = 0x000900a4;

extern "kernel32" fn CreateFileW(
    file_name: [*:0]const u16,
    desired_access: u32,
    share_mode: u32,
    security_attributes: ?*const anyopaque,
    creation_disposition: u32,
    flags_and_attributes: u32,
    template_file: ?std.os.windows.HANDLE,
) callconv(.winapi) std.os.windows.HANDLE;

extern "kernel32" fn DeviceIoControl(
    device: std.os.windows.HANDLE,
    control_code: u32,
    input: ?*const anyopaque,
    input_size: u32,
    output: ?*anyopaque,
    output_size: u32,
    bytes_returned: *u32,
    overlapped: ?*anyopaque,
) callconv(.winapi) i32;

const OwnedRunResult = struct {
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,

    fn deinit(result: *OwnedRunResult, allocator: std.mem.Allocator) void {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
        result.* = undefined;
    }
};

fn runWorker(
    allocator: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
) !OwnedRunResult {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(64 * 1024),
    });
    return .{ .term = result.term, .stdout = result.stdout, .stderr = result.stderr };
}

fn runWorkerCommand(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    nonce: []const u8,
    command: []const u8,
    pause: []const u8,
) !OwnedRunResult {
    return runWorker(allocator, io, &.{
        fixture_options.worker_path,
        command,
        root,
        pause,
        nonce,
    });
}

fn runWorkerExpectSuccess(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    nonce: []const u8,
    command: []const u8,
) !void {
    var result = try runWorkerCommand(allocator, io, root, nonce, command, "none");
    defer result.deinit(allocator);
    expectSuccessfulTerm(result.term) catch |err| {
        std.debug.print("fixture worker stderr:\n{s}\n", .{result.stderr});
        return err;
    };
}

fn spawnWorker(
    io: std.Io,
    root: []const u8,
    nonce: []const u8,
    command: []const u8,
    pause: []const u8,
) !std.process.Child {
    return std.process.spawn(io, .{
        .argv = &.{ fixture_options.worker_path, command, root, pause, nonce },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .inherit,
    });
}

fn expectSuccessfulTerm(term: std.process.Child.Term) !void {
    switch (term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.UnexpectedWorkerTermination,
    }
}

fn expectFailure(result: OwnedRunResult) !void {
    switch (result.term) {
        .exited => |code| try std.testing.expect(code != 0),
        else => {},
    }
}

fn expectFailureContaining(result: OwnedRunResult, needle: []const u8) !void {
    try expectFailure(result);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, needle) != null);
}

const DeadlineOutcome = union(enum) {
    operation: anyerror!void,
    timeout: anyerror!void,
};

const WaitOutcome = union(enum) {
    operation: anyerror!std.process.Child.Term,
    timeout: anyerror!void,
};

fn expectMarkerWithin(
    io: std.Io,
    child: *std.process.Child,
    expected: []const u8,
    timeout_ms: i64,
) !void {
    var outcomes: [2]DeadlineOutcome = undefined;
    var selection = std.Io.Select(DeadlineOutcome).init(io, &outcomes);
    defer selection.cancelDiscard();
    try selection.concurrent(.operation, readExpectedMarker, .{ io, child.stdout.?, expected });
    try selection.concurrent(.timeout, deadline, .{ io, timeout_ms });
    switch (try selection.await()) {
        .operation => |result| result catch return error.MarkerUnavailable,
        .timeout => |result| {
            try result;
            selection.cancelDiscard();
            child.kill(io);
            return error.WorkerDeadlineExceeded;
        },
    }
}

fn readExpectedMarker(io: std.Io, stdout: std.Io.File, expected: []const u8) !void {
    if (expected.len > 64) return error.MarkerTooLong;
    var buffer: [64]u8 = undefined;
    var reader = stdout.readerStreaming(io, &.{});
    try reader.interface.readSliceAll(buffer[0..expected.len]);
    if (!std.mem.eql(u8, expected, buffer[0..expected.len])) return error.MarkerMismatch;
}

fn waitChildWithin(
    io: std.Io,
    child: *std.process.Child,
    timeout_ms: i64,
) !std.process.Child.Term {
    var outcomes: [2]WaitOutcome = undefined;
    var selection = std.Io.Select(WaitOutcome).init(io, &outcomes);
    defer selection.cancelDiscard();
    try selection.concurrent(.operation, waitChild, .{ io, child });
    try selection.concurrent(.timeout, deadline, .{ io, timeout_ms });
    switch (try selection.await()) {
        .operation => |result| return result,
        .timeout => |result| {
            try result;
            selection.cancelDiscard();
            child.kill(io);
            return error.WorkerDeadlineExceeded;
        },
    }
}

fn waitChild(io: std.Io, child: *std.process.Child) !std.process.Child.Term {
    return child.wait(io);
}

fn deadline(io: std.Io, milliseconds: i64) !void {
    try std.Io.Clock.Duration.sleep(.{
        .clock = .awake,
        .raw = .fromMilliseconds(milliseconds),
    }, io);
}

fn writeSentinel(io: std.Io, root: std.Io.Dir, nonce: []const u8) !void {
    var file = try root.createFile(io, sentinel_name, .{ .exclusive = true });
    defer file.close(io);
    var buffer: [sentinel_prefix.len + 32 + 1]u8 = undefined;
    const contents = try std.fmt.bufPrint(&buffer, "{s}{s}\n", .{ sentinel_prefix, nonce });
    try file.writeStreamingAll(io, contents);
    try file.sync(io);
}

fn currentGeneration(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
) ![]u8 {
    var store = try root.openDir(io, ".v2/presentmon", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer store.close(io);
    const selector = try store.readFileAlloc(
        io,
        deps.cache_selector_file,
        allocator,
        .limited(deps.cache_selector_max_bytes + 1),
    );
    defer allocator.free(selector);
    return allocator.dupe(u8, try deps.parseCacheSelector(selector));
}

fn generationCount(io: std.Io, root: std.Io.Dir) !usize {
    var generations = root.openDir(io, ".v2/presentmon/generations", .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => |e| return e,
    };
    defer generations.close(io);
    var count: usize = 0;
    var iterator = generations.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .directory) return error.InvalidFixtureGeneration;
        count += 1;
    }
    return count;
}

fn rootStageCount(io: std.Io, root: std.Io.Dir) !usize {
    var count: usize = 0;
    var iterator = root.iterate();
    while (try iterator.next(io)) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".stage-")) count += 1;
    }
    return count;
}

const SnapshotEntry = struct {
    path: []u8,
    stat: std.Io.File.Stat,
    digest: [32]u8,
    acl_digest: [32]u8,
};

fn snapshotCache(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
) ![]u8 {
    var entries: std.ArrayList(SnapshotEntry) = .empty;
    defer {
        for (entries.items) |entry| allocator.free(entry.path);
        entries.deinit(allocator);
    }
    try entries.append(allocator, .{
        .path = try allocator.dupe(u8, ""),
        .stat = try root.stat(io),
        .digest = [_]u8{0} ** 32,
        .acl_digest = try deps_fetch.aclFingerprint(root.handle),
    });
    var walker = try root.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        const path = try allocator.dupe(u8, entry.path);
        for (path) |*byte| if (byte.* == '\\') {
            byte.* = '/';
        };
        errdefer allocator.free(path);
        switch (entry.kind) {
            .directory => {
                var child = try entry.dir.openDir(io, entry.basename, .{
                    .iterate = true,
                    .follow_symlinks = false,
                });
                defer child.close(io);
                try entries.append(allocator, .{
                    .path = path,
                    .stat = try child.stat(io),
                    .digest = [_]u8{0} ** 32,
                    .acl_digest = try deps_fetch.aclFingerprint(child.handle),
                });
            },
            .file => {
                var identity = try entry.dir.openFile(io, entry.basename, .{
                    .path_only = true,
                    .follow_symlinks = false,
                    .resolve_beneath = true,
                });
                defer identity.close(io);
                const stat = try identity.stat(io);
                var file = try entry.dir.openFile(io, entry.basename, .{
                    .allow_directory = false,
                    .follow_symlinks = true,
                    .resolve_beneath = true,
                });
                defer file.close(io);
                const readable_stat = try file.stat(io);
                if (readable_stat.kind != .file or readable_stat.inode != stat.inode or
                    readable_stat.size != stat.size)
                {
                    return error.SnapshotIdentityChanged;
                }
                var hasher = std.crypto.hash.sha2.Sha256.init(.{});
                var reader = file.readerStreaming(io, &.{});
                var chunk: [4096]u8 = undefined;
                var remaining = stat.size;
                while (remaining != 0) {
                    const count: usize = @intCast(@min(remaining, chunk.len));
                    try reader.interface.readSliceAll(chunk[0..count]);
                    hasher.update(chunk[0..count]);
                    remaining -= count;
                }
                var digest: [32]u8 = undefined;
                hasher.final(&digest);
                try entries.append(allocator, .{
                    .path = path,
                    .stat = stat,
                    .digest = digest,
                    .acl_digest = try deps_fetch.aclFingerprint(identity.handle),
                });
            },
            else => {
                var reparse = try entry.dir.openFile(io, entry.basename, .{
                    .path_only = true,
                    .follow_symlinks = false,
                    .resolve_beneath = true,
                });
                defer reparse.close(io);
                try entries.append(allocator, .{
                    .path = path,
                    .stat = try reparse.stat(io),
                    .digest = [_]u8{0} ** 32,
                    .acl_digest = try deps_fetch.aclFingerprint(reparse.handle),
                });
            },
        }
    }
    std.mem.sort(SnapshotEntry, entries.items, {}, struct {
        fn lessThan(_: void, lhs: SnapshotEntry, rhs: SnapshotEntry) bool {
            return std.mem.lessThan(u8, lhs.path, rhs.path);
        }
    }.lessThan);
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    for (entries.items) |entry| {
        const kind: u8 = @intFromEnum(entry.stat.kind);
        const digest_hex = std.fmt.bytesToHex(entry.digest, .lower);
        const acl_digest_hex = std.fmt.bytesToHex(entry.acl_digest, .lower);
        try output.writer.print(
            "{d}:{s}|{d}|{d}|{d}|{d}|{d}|{d}|{s}|{s}\n",
            .{
                entry.path.len,
                entry.path,
                kind,
                entry.stat.inode,
                entry.stat.nlink,
                entry.stat.size,
                entry.stat.mtime.nanoseconds,
                entry.stat.ctime.nanoseconds,
                &digest_hex,
                &acl_digest_hex,
            },
        );
    }
    return output.toOwnedSlice();
}
