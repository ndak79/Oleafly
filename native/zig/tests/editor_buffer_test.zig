const std = @import("std");
const editor = @import("editor_buffer");

fn sha256(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

test "attach preserves BOM and newline policy with exact initial identity" {
    const disk = "\xef\xbb\xbffirst\r\nsecond\r\n";
    var buffer = try editor.Buffer.attach(std.testing.allocator, "C:\\workspace\\paper\\main.tex", disk);
    defer buffer.deinit();

    try std.testing.expectEqualStrings("C:\\workspace\\paper\\main.tex", buffer.path());
    try std.testing.expectEqual(editor.Encoding.utf8_bom, buffer.encoding());
    try std.testing.expectEqual(editor.NewlinePolicy.crlf, buffer.newlinePolicy());
    try std.testing.expectEqual(editor.State.clean, buffer.state());
    try std.testing.expectEqual(@as(u64, 0), buffer.revision());
    try std.testing.expectEqual(@as(u64, 0), buffer.savedRevision());
    try std.testing.expectEqual(@as(usize, disk.len - 3), buffer.textLength());
    try std.testing.expectEqual(sha256(disk), buffer.savedHash());
    try std.testing.expectEqual(sha256(disk), try buffer.currentHash());

    const snapshot = try buffer.materialize(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expectEqualStrings(disk, snapshot);
}

test "piece-table edits require contiguous sequences and preserve exact bytes" {
    var buffer = try editor.Buffer.attach(std.testing.allocator, "main.tex", "alpha\nbeta\n");
    defer buffer.deinit();

    try buffer.applyEdit(1, 5, 0, " X");
    try std.testing.expectEqual(@as(u64, 1), buffer.revision());
    try std.testing.expectEqual(editor.State.dirty, buffer.state());
    try std.testing.expectEqual(@as(usize, 1), buffer.journal().len);
    try std.testing.expectEqual(@as(usize, 5), buffer.journal()[0].start);
    try std.testing.expectEqual(@as(usize, 0), buffer.journal()[0].deleted_len);
    try std.testing.expectEqual(@as(usize, 2), buffer.journal()[0].inserted_len);

    var snapshot = try buffer.materialize(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expectEqualStrings("alpha X\nbeta\n", snapshot);

    try std.testing.expectError(error.StaleSequence, buffer.applyEdit(1, 0, 0, "!"));
    try std.testing.expectError(error.MissingSequence, buffer.applyEdit(3, 0, 0, "!"));
    try std.testing.expectEqual(@as(u64, 1), buffer.revision());

    try buffer.applyEdit(2, 0, 5, "gamma");
    std.testing.allocator.free(snapshot);
    snapshot = try buffer.materialize(std.testing.allocator);
    try std.testing.expectEqualStrings("gamma X\nbeta\n", snapshot);
    try std.testing.expectEqual(@as(u64, 2), buffer.revision());
}

test "hash audit and save transition do not bless the wrong content" {
    var buffer = try editor.Buffer.attach(std.testing.allocator, "main.tex", "before\n");
    defer buffer.deinit();
    const saved = buffer.savedHash();

    try buffer.applyEdit(1, 0, 6, "after");
    const current = try buffer.currentHash();
    try std.testing.expect(!std.mem.eql(u8, &saved, &current));
    try std.testing.expectError(error.HashMismatch, buffer.markSaved(saved));
    try std.testing.expectEqual(editor.State.dirty, buffer.state());

    try buffer.markSaved(current);
    try std.testing.expectEqual(editor.State.clean, buffer.state());
    try std.testing.expectEqual(@as(u64, 1), buffer.savedRevision());

    buffer.markConflicted();
    try std.testing.expectEqual(editor.State.conflicted, buffer.state());
    try std.testing.expectError(error.UnresolvedState, buffer.markSaved(current));
    try buffer.applyEdit(2, 0, 0, "local ");
    try std.testing.expectEqual(editor.State.conflicted, buffer.state());

    buffer.markMissing();
    try std.testing.expectEqual(editor.State.missing, buffer.state());
    try std.testing.expectError(error.UnresolvedState, buffer.markSaved(try buffer.currentHash()));
}

test "invalid UTF-8 and ranges are rejected without mutation" {
    try std.testing.expectError(error.InvalidUtf8, editor.Buffer.attach(std.testing.allocator, "bad.tex", &[_]u8{ 0xff, 0xfe }));

    var buffer = try editor.Buffer.attach(std.testing.allocator, "main.tex", "stable\n");
    defer buffer.deinit();
    const before = try buffer.materialize(std.testing.allocator);
    defer std.testing.allocator.free(before);

    try std.testing.expectError(error.InvalidUtf8, buffer.applyEdit(1, 0, 0, &[_]u8{0xff}));
    try std.testing.expectError(error.InvalidRange, buffer.applyEdit(1, 99, 0, "x"));
    try std.testing.expectEqual(@as(u64, 0), buffer.revision());
    const after = try buffer.materialize(std.testing.allocator);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualStrings(before, after);
}

test "newline policy reports mixed and none without rewriting source bytes" {
    var mixed = try editor.Buffer.attach(std.testing.allocator, "mixed.tex", "a\r\nb\nc\rd");
    defer mixed.deinit();
    try std.testing.expectEqual(editor.NewlinePolicy.mixed, mixed.newlinePolicy());

    var none = try editor.Buffer.attach(std.testing.allocator, "one-line.tex", "one line");
    defer none.deinit();
    try std.testing.expectEqual(editor.NewlinePolicy.none, none.newlinePolicy());
}

test "piece-table boundaries match a reference replacement model" {
    const Case = struct {
        start: usize,
        deleted_len: usize,
        inserted: []const u8,
    };
    const cases = [_]Case{
        .{ .start = 0, .deleted_len = 0, .inserted = "A" },
        .{ .start = 11, .deleted_len = 0, .inserted = "Z" },
        .{ .start = 3, .deleted_len = 4, .inserted = "mid" },
        .{ .start = 1, .deleted_len = 1, .inserted = "" },
        .{ .start = 0, .deleted_len = 4, .inserted = "reset" },
        .{ .start = 5, .deleted_len = 0, .inserted = " λ" },
    };

    var buffer = try editor.Buffer.attach(std.testing.allocator, "boundaries.tex", "0123456789");
    defer buffer.deinit();
    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(std.testing.allocator);
    try expected.appendSlice(std.testing.allocator, "0123456789");

    for (cases, 0..) |case, index| {
        const sequence = @as(u64, @intCast(index + 1));
        try buffer.applyEdit(sequence, case.start, case.deleted_len, case.inserted);

        var next: std.ArrayList(u8) = .empty;
        try next.appendSlice(std.testing.allocator, expected.items[0..case.start]);
        try next.appendSlice(std.testing.allocator, case.inserted);
        try next.appendSlice(std.testing.allocator, expected.items[case.start + case.deleted_len ..]);
        expected.deinit(std.testing.allocator);
        expected = next;

        const snapshot = try buffer.materialize(std.testing.allocator);
        defer std.testing.allocator.free(snapshot);
        try std.testing.expectEqualSlices(u8, expected.items, snapshot);
    }
}
