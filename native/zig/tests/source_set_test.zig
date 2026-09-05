const std = @import("std");
const source_set = @import("source_set");
const identity = @import("app_build_identity");

const abc_sha256 = blob("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
const script_sha256 = blob("a8076d3d28d21e02012b20eaf7dbf75409a6277134439025f282e368e3305abf");
const entries = [_]source_set.Entry{
    .{ .path = "a.txt", .mode = "100644", .content_length = 3, .blob_sha256 = abc_sha256 },
    .{ .path = "bin/run", .mode = "100755", .content_length = 10, .blob_sha256 = script_sha256 },
};

fn blob(comptime value: []const u8) [32]u8 {
    var result: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&result, value) catch unreachable;
    return result;
}

fn expectDigest(expected: []const u8, input: []const source_set.Entry) !void {
    const actual = source_set.hex(try source_set.digest(std.testing.allocator, input));
    try std.testing.expectEqualStrings(expected, &actual);
}

fn expectDifferent(baseline: [32]u8, input: []const source_set.Entry) !void {
    const changed = try source_set.digest(std.testing.allocator, input);
    try std.testing.expect(!std.mem.eql(u8, &baseline, &changed));
}

test "source-set v2 empty single and multi-entry independent known answers" {
    // Independently generated with Node crypto from explicit Buffer fields,
    // not from this module's encoder. Blobs are SHA-256 of abc and #!/bin/sh\n.
    try expectDigest("28467ffbc06be0c64af4c69e474a73ff534d2bd8d9a52be301771e127339bebc", &.{});
    try expectDigest("e39749a2560b995e56daaa0eef9a2933ba01f7476fe996e16244fb8c154d327f", entries[0..1]);
    try expectDigest("877c06e5451678c60805734b59e0adfba6f6aedac5682dca21dbd219b5236eaa", &entries);
}

test "source-set hashes raw UTF8 byte lengths and does not normalize path bytes" {
    var composed = entries[0];
    composed.path = "caf\u{e9}.tex";
    try expectDigest("c8edd2e482403e953524cf6b4733d66de258695d28dc1d502ea49eaa22dea55f", &.{composed});
    var decomposed = composed;
    decomposed.path = "cafe\u{301}.tex";
    try expectDifferent(try source_set.digest(std.testing.allocator, &.{composed}), &.{decomposed});
}

test "source-set accepts entire u64 content length without truncation" {
    var entry = entries[0];
    // Values above u64 cannot inhabit this API; lengths are not cast from usize.
    try std.testing.expect(@TypeOf(entry.content_length) == u64);
    entry.content_length = std.math.maxInt(u64);
    try expectDigest("a657f572fcd0c6b8b7083c9fe8f24be495d39b4f49f2352ce1fea0b3d3aa5769", &.{entry});
}

test "source-set count path mode length and every blob bit affect identity" {
    const baseline = try source_set.digest(std.testing.allocator, &entries);
    // The encoded count changes from two to three (one bit); it is derived
    // from the supplied slice, never separately accepted from a caller.
    var third = entries[0];
    third.path = "z.txt";
    try expectDifferent(baseline, &.{ entries[0], entries[1], third });

    var changed = entries;
    changed[0].path = "A.txt"; // One raw path bit changes; ordering stays valid.
    try expectDifferent(baseline, &changed);
    changed = entries;
    changed[0].mode = "100755";
    try expectDifferent(baseline, &changed);
    changed = entries;
    for (0..64) |bit| {
        changed[0].content_length = entries[0].content_length ^ (@as(u64, 1) << @intCast(bit));
        try expectDifferent(baseline, &changed);
    }
    for (0..256) |bit| {
        changed = entries;
        changed[0].blob_sha256[bit / 8] ^= @as(u8, 1) << @intCast(bit % 8);
        try expectDifferent(baseline, &changed);
    }
}

test "source-set rejects every one-bit mode mutation and unsupported modes" {
    var entry = entries[0];
    for ([_][]const u8{ "100644", "100755" }) |valid_mode| {
        for (0..48) |bit| {
            var mode: [6]u8 = undefined;
            @memcpy(&mode, valid_mode);
            mode[bit / 8] ^= @as(u8, 1) << @intCast(bit % 8);
            entry.mode = &mode;
            try std.testing.expectError(error.InvalidMode, source_set.digest(std.testing.allocator, &.{entry}));
        }
    }
    for ([_][]const u8{ "", "10064", "0100644", "100644\x00", "100644 ", "100664", "120000", "160000" }) |mode| {
        entry.mode = mode;
        try std.testing.expectError(error.InvalidMode, source_set.digest(std.testing.allocator, &.{entry}));
    }
}

test "source-set rejects unsafe relative paths and malformed UTF8" {
    const invalid = [_][]const u8{
        "",         "/a",       "//host/a", "C:/a",     "C:a",          "a:b",              "a::$DATA", "a\\b",
        "a/",       "a//b",     ".",        "..",       "./a",          "a/./b",            "a/../b",   "a/..",
        "a.",       "a ",       "a./b",     "a /b",     "a\x00b",       "a\x01b",           "a\x1fb",   "a\x7fb",
        "a\u{80}b", "a\u{9f}b", "\xff",     "\xc0\xaf", "\xed\xa0\x80", "\xf4\x90\x80\x80", "a\"b",     "a*b",
        "a?b",      "a<b",      "a>b",      "a|b",
    };
    for (invalid) |path| {
        var entry = entries[0];
        entry.path = path;
        try std.testing.expectError(error.InvalidPath, source_set.digest(std.testing.allocator, &.{entry}));
    }
}

test "source-set rejects reserved Windows device components at any depth" {
    const invalid = [_][]const u8{
        "CON",         "con.txt",  "a/PrN.log", "AUX/a",    "NUL",             "CLOCK$",    "conin$",      "CONOUT$.txt",
        "COM1",        "com9.tex", "LPT1",      "lpt9.bin", "a/COM\u{b9}.txt", "LPT\u{b2}", "COM\u{b3}/a", "CON .txt",
        "a/LPT1 .txt",
    };
    for (invalid) |path| {
        var entry = entries[0];
        entry.path = path;
        try std.testing.expectError(error.InvalidPath, source_set.digest(std.testing.allocator, &.{entry}));
    }
    for ([_][]const u8{ ".gitignore", "dir/a b.txt", "COM0", "COM10", "LPT0", "LPT10", "console.txt", "src/\u{3b1}.zig" }) |path| {
        var entry = entries[0];
        entry.path = path;
        _ = try source_set.digest(std.testing.allocator, &.{entry});
    }
}

test "source-set requires strictly ascending raw byte order without sorting" {
    try std.testing.expectError(error.UnsortedPaths, source_set.digest(std.testing.allocator, &.{ entries[1], entries[0] }));
    try std.testing.expectError(error.DuplicatePath, source_set.digest(std.testing.allocator, &.{ entries[0], entries[0] }));
    var upper = entries[0];
    upper.path = "Z.txt";
    var lower = entries[1];
    lower.path = "a.txt";
    _ = try source_set.digest(std.testing.allocator, &.{ upper, lower });
    try std.testing.expectError(error.UnsortedPaths, source_set.digest(std.testing.allocator, &.{ lower, upper }));
}

test "source-set rejects Unicode17 folded and canonical-equivalent collisions" {
    const pairs = [_][2][]const u8{
        .{ "A.txt", "a.txt" },
        .{ "Stra\u{df}e.tex", "strasse.tex" },
        .{ "caf\u{e9}.tex", "cafe\u{301}.tex" },
        .{ "Kelvin.tex", "\u{212a}elvin.tex" },
        .{ "\u{1100}\u{1161}.tex", "\u{ac00}.tex" },
        .{ "A\u{306}\u{301}.tex", "\u{1eae}.tex" },
        .{ "a\u{301}\u{327}.tex", "a\u{327}\u{301}.tex" },
    };
    for (pairs) |pair| {
        var collision = entries;
        const ordered = std.mem.order(u8, pair[0], pair[1]) == .lt;
        collision[0].path = pair[if (ordered) 0 else 1];
        collision[1].path = pair[if (ordered) 1 else 0];
        try std.testing.expectError(error.PathCollision, source_set.digest(std.testing.allocator, &collision));
    }
    var first = entries[0];
    first.path = "A.txt";
    var middle = entries[0];
    middle.path = "B.txt";
    var last = entries[0];
    last.path = "a.txt";
    try std.testing.expectError(error.PathCollision, source_set.digest(std.testing.allocator, &.{ first, middle, last }));
}

fn expectPrefixCollision(allocator: std.mem.Allocator, file: []const u8, child: []const u8) !void {
    var collision = entries;
    const file_first = std.mem.order(u8, file, child) == .lt;
    collision[0].path = if (file_first) file else child;
    collision[1].path = if (file_first) child else file;
    if (source_set.digest(allocator, &collision)) |_| {
        return error.ExpectedPrefixCollision;
    } else |err| switch (err) {
        error.PathCollision => {},
        else => return err,
    }
}

test "source-set rejects file-directory prefixes in either canonical entry order" {
    // Raw byte ordering can place either the file or its aliased child first.
    try expectPrefixCollision(std.testing.allocator, "a", "a/b");
    try expectPrefixCollision(std.testing.allocator, "A", "a/b");
    try expectPrefixCollision(std.testing.allocator, "a", "A/b");
    try expectPrefixCollision(std.testing.allocator, "src/A", "SRC/a/b/c");
    try expectPrefixCollision(std.testing.allocator, "SRC/a/b", "src/A/B/c");
    // A raw prefix neighbor between the file and child must not hide conflict.
    var paths = [_]source_set.Entry{ entries[0], entries[0], entries[0] };
    paths[0].path = "a";
    paths[1].path = "a-b";
    paths[2].path = "a/b";
    try std.testing.expectError(error.PathCollision, source_set.digest(std.testing.allocator, &paths));
}

test "source-set file-directory prefixes use Unicode17 full folding and NFD" {
    const pairs = [_][2][]const u8{
        .{ "Stra\u{df}e", "strasse/b" },
        .{ "strasse", "Stra\u{df}e/b" },
        .{ "caf\u{e9}", "cafe\u{301}/b" },
        .{ "cafe\u{301}", "caf\u{e9}/b" },
        .{ "\u{1eae}", "a\u{306}\u{301}/b" },
        .{ "\u{ac00}", "\u{1100}\u{1161}/b" },
        .{ "src/\u{212a}", "SRC/k/b" },
    };
    for (pairs) |pair| try expectPrefixCollision(std.testing.allocator, pair[0], pair[1]);
}

test "source-set permits shared directory aliases and non-component prefixes" {
    var valid = [_]source_set.Entry{entries[0]} ** 7;
    const paths = [_][]const u8{
        "A/b", "CAF\u{c9}/a", "a-b", "a.b", "a/c", "ab", "cafe\u{301}/b",
    };
    for (&valid, paths) |*entry, path| entry.path = path;
    const baseline = try source_set.digest(std.testing.allocator, &valid);
    try std.testing.expectEqual(baseline, try source_set.digest(std.testing.allocator, &valid));
}

test "build identity composes unchanged v1 with source-set v2 and every dependency bit" {
    const source = try source_set.digest(std.testing.allocator, &entries);
    const lock = [_]u8{0x42} ** 32;
    const baseline = identity.compute(source, lock);
    try std.testing.expectEqualStrings("d922ddc5c610ca158bb378a34618510637be6dc33b35981f0c86a84835664d90", &identity.hex(baseline));
    for (0..256) |bit| {
        var changed = lock;
        changed[bit / 8] ^= @as(u8, 1) << @intCast(bit % 8);
        try std.testing.expect(!std.mem.eql(u8, &baseline, &identity.compute(source, changed)));
    }
}

fn exerciseAllocations(allocator: std.mem.Allocator) !void {
    var unicode_entries = entries;
    unicode_entries[1].path = "caf\u{e9}/\u{1eae}.tex";
    _ = try source_set.digest(allocator, &unicode_entries);
    var collision = entries;
    collision[0].path = "CAF\u{c9}.tex";
    collision[1].path = "cafe\u{301}.tex";
    if (source_set.digest(allocator, &collision)) |_| {
        return error.ExpectedCollision;
    } else |err| switch (err) {
        error.PathCollision => {},
        else => return err,
    }
    try expectPrefixCollision(allocator, "A", "a/b/c/d");
    try expectPrefixCollision(allocator, "caf\u{e9}", "cafe\u{301}/b/c/d");
}

test "source-set releases allocations on success collision and every OOM boundary" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseAllocations, .{});
}
