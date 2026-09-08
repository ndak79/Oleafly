//! Tests for the UIA text provider contract, range pool, snapshot
//! lifecycle, and cross-thread command routing.

const std = @import("std");
const snapshot_mod = @import("uia_snapshot");
const range_mod = @import("uia_range");
const thread_mod = @import("uia_thread");
const provider_mod = @import("uia_provider");

const testing = std.testing;
const alloc = testing.allocator;

test "snapshot create and release" {
    const snap = try snapshot_mod.create(alloc, "hello world", 1, 0);
    try testing.expectEqual(@as(u64, 1), snap.revision);
    try testing.expectEqual(@as(usize, 11), snap.byteLen());
    try testing.expectEqualStrings("hello world", snap.text());
    snap.release();
}

test "snapshot acquire adds a reference" {
    const snap = try snapshot_mod.create(alloc, "test", 1, 0);
    snap.acquire();
    snap.release();
    // Still alive with one reference.
    try testing.expectEqualStrings("test", snap.text());
    snap.release();
}

test "range init and getText" {
    const snap = try snapshot_mod.create(alloc, "abcdef", 1, 0);
    defer snap.release();
    var r = range_mod.Range.init(1, 1, 1, 4, 4, 1, 0);
    const text = try r.getText(snap, 100);
    try testing.expectEqualStrings("bcd", text);
}

test "range degenerate is detected" {
    const r = range_mod.Range.init(1, 5, 5, 5, 5, 1, 0);
    try testing.expect(r.degenerate);
}

test "range applyEdit shifts after anchor" {
    var r = range_mod.Range.init(1, 10, 10, 20, 20, 1, 0);
    const edit = snapshot_mod.EditRecord{
        .start_byte = 5,
        .deleted_bytes = 2,
        .inserted_bytes = 5,
        .start_utf16 = 5,
        .deleted_utf16 = 2,
        .inserted_utf16 = 5,
        .revision = 2,
    };
    r.applyEdit(edit, 0);
    try testing.expectEqual(@as(usize, 13), r.start.byte);
    try testing.expectEqual(@as(usize, 23), r.end.byte);
}

test "range applyEdit collapses interior anchor" {
    var r = range_mod.Range.init(1, 6, 6, 8, 8, 1, 0);
    const edit = snapshot_mod.EditRecord{
        .start_byte = 5,
        .deleted_bytes = 5,
        .inserted_bytes = 3,
        .start_utf16 = 5,
        .deleted_utf16 = 5,
        .inserted_utf16 = 3,
        .revision = 2,
    };
    r.applyEdit(edit, 0);
    // Start has before affinity -> collapses to edit start.
    try testing.expectEqual(@as(usize, 5), r.start.byte);
    // End has after affinity -> collapses to edit start + inserted.
    try testing.expectEqual(@as(usize, 8), r.end.byte);
}

test "range pool enforces cap" {
    var pool = range_mod.RangePool.init(alloc);
    defer pool.deinit();
    var i: usize = 0;
    while (i < snapshot_mod.max_live_ranges) : (i += 1) {
        _ = try pool.create(0, 0, 10, 10, 1, 0);
    }
    try testing.expectError(error.CapExceeded, pool.create(0, 0, 10, 10, 1, 0));
}

test "range pool removeById" {
    var pool = range_mod.RangePool.init(alloc);
    defer pool.deinit();
    const r = try pool.create(0, 0, 10, 10, 1, 0);
    const id = r.id;
    try testing.expectEqual(@as(usize, 1), pool.count());
    try testing.expect(pool.removeById(id));
    try testing.expectEqual(@as(usize, 0), pool.count());
}

test "provider thread snapshot publish and retrieve" {
    var pt = thread_mod.ProviderThread.init(alloc);
    defer pt.deinit();
    const snap = try snapshot_mod.create(alloc, "initial", 1, 0);
    pt.publishSnapshot(snap);
    const retrieved = pt.getSnapshot().?;
    try testing.expectEqualStrings("initial", retrieved.text());
    snap.release();
}

test "provider thread mutation roundtrip" {
    var pt = thread_mod.ProviderThread.init(alloc);
    defer pt.deinit();
    const req_id = pt.allocateRequestId();
    try testing.expect(pt.postMutation(.{
        .kind = .set_focus,
        .request_id = req_id,
        .revision = 1,
    }));
    var buf: [4]thread_mod.MutationCommand = undefined;
    const n = pt.drainMutations(&buf);
    try testing.expectEqual(@as(usize, 1), n);
    try testing.expectEqual(req_id, buf[0].request_id);

    pt.postResult(.{ .request_id = req_id, .accepted = true, .revision = 1 });
    const result = pt.pollResult().?;
    try testing.expectEqual(req_id, result.request_id);
    try testing.expect(result.accepted);
}

test "provider does not support ValuePattern" {
    var pt = thread_mod.ProviderThread.init(alloc);
    defer pt.deinit();
    var p = provider_mod.Provider.init(&pt);
    try testing.expect(!p.isValuePatternSupported());
    try testing.expect(p.supportsPattern(.text));
    try testing.expect(p.supportsPattern(.text2));
    try testing.expect(p.supportsPattern(.scroll));
    try testing.expect(!p.supportsPattern(.value));
}

test "provider documentRange covers full document" {
    var pt = thread_mod.ProviderThread.init(alloc);
    defer pt.deinit();
    const snap = try snapshot_mod.create(alloc, "hello", 1, 0);
    pt.publishSnapshot(snap);
    var p = provider_mod.Provider.init(&pt);
    const range = p.documentRange().?;
    try testing.expectEqual(@as(usize, 0), range.start.byte);
    try testing.expectEqual(@as(usize, 5), range.end.byte);
    snap.release();
}

test "provider getText respects max_length at UTF-8 boundary" {
    var pt = thread_mod.ProviderThread.init(alloc);
    defer pt.deinit();
    // "café" in UTF-8: c a f 0xC3 0xA9
    const snap = try snapshot_mod.create(alloc, "caf\xc3\xa9", 1, 0);
    pt.publishSnapshot(snap);
    var p = provider_mod.Provider.init(&pt);
    const text = p.getText(4).?;
    // Should not split the é (0xC3 0xA9); backs up to 3 bytes.
    try testing.expectEqual(@as(usize, 3), text.len);
    try testing.expectEqualStrings("caf", text);
    snap.release();
}

test "provider connect and disconnect lifecycle" {
    var pt = thread_mod.ProviderThread.init(alloc);
    defer pt.deinit();
    var p = provider_mod.Provider.init(&pt);
    try testing.expect(!p.connected);
    p.connect(42, 99);
    try testing.expect(p.connected);
    try testing.expectEqual(@as(u32, 42), p.runtime_id[0]);
    p.disconnect();
    try testing.expect(!p.connected);
}

test "edit journal wraps generation and invalidates ranges" {
    var pt = thread_mod.ProviderThread.init(alloc);
    defer pt.deinit();
    _ = try pt.range_pool.create(0, 0, 10, 10, 1, 0);
    try testing.expect(pt.range_pool.ranges.items[0].valid);
    // Fill journal to trigger wrap.
    var i: usize = 0;
    while (i < snapshot_mod.max_edit_journal) : (i += 1) {
        pt.recordEdit(.{
            .start_byte = 0,
            .deleted_bytes = 0,
            .inserted_bytes = 1,
            .start_utf16 = 0,
            .deleted_utf16 = 0,
            .inserted_utf16 = 1,
            .revision = @intCast(i + 2),
        });
    }
    // After journal wrap, generation increases and ranges are invalidated.
    try testing.expect(!pt.range_pool.ranges.items[0].valid);
    try testing.expect(pt.journal_generation > 0);
}
