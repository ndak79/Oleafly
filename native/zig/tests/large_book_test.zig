const std = @import("std");
const fixture = @import("large_book");

fn sha256(bytes: []const u8) [fixture.digest_bytes]u8 {
    var digest: [fixture.digest_bytes]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

fn count(bytes: []const u8, needle: []const u8) usize {
    var total: usize = 0;
    var offset: usize = 0;
    while (std.mem.indexOf(u8, bytes[offset..], needle)) |relative| {
        total += 1;
        offset += relative + needle.len;
    }
    return total;
}

test "large-book fixture is deterministic, varied, and structurally closed" {
    const options = fixture.Options{ .target_bytes = 64 * 1024, .seed = 0x1234_5678 };
    var first = try fixture.generate(std.testing.allocator, options);
    defer first.deinit();
    var second = try fixture.generate(std.testing.allocator, options);
    defer second.deinit();

    try std.testing.expectEqualSlices(u8, first.bytes, second.bytes);
    try std.testing.expectEqual(first.metrics.byte_sha256, second.metrics.byte_sha256);
    try std.testing.expectEqual(first.metrics.line_sha256, second.metrics.line_sha256);
    try std.testing.expectEqual(first.metrics.section_sha256, second.metrics.section_sha256);
    try std.testing.expectEqual(first.metrics.byte_count, @as(u64, @intCast(first.bytes.len)));
    try fixture.validateMetrics(first.metrics, options);
    try std.testing.expect(std.unicode.utf8ValidateSlice(first.bytes));

    var alternate = try fixture.generate(std.testing.allocator, .{ .target_bytes = options.target_bytes, .seed = options.seed + 1 });
    defer alternate.deinit();
    try std.testing.expect(!std.mem.eql(u8, first.bytes, alternate.bytes));
    try std.testing.expect(!std.mem.eql(u8, &first.metrics.byte_sha256, &alternate.metrics.byte_sha256));

    try std.testing.expectEqual(first.metrics.table_count, @as(u64, @intCast(count(first.bytes, "\\begin{table}"))));
    try std.testing.expectEqual(first.metrics.table_count, @as(u64, @intCast(count(first.bytes, "\\end{table}"))));
    try std.testing.expectEqual(count(first.bytes, "\\begin{document}"), count(first.bytes, "\\end{document}"));
    try std.testing.expectEqual(count(first.bytes, "\\begin{tabular}"), count(first.bytes, "\\end{tabular}"));
    try std.testing.expectEqual(count(first.bytes, "\\begin{itemize}"), count(first.bytes, "\\end{itemize}"));
    try std.testing.expectEqual(count(first.bytes, "\\begin{thebibliography}"), count(first.bytes, "\\end{thebibliography}"));
    try std.testing.expectEqual(first.metrics.math_block_count, @as(u64, @intCast(count(first.bytes, "\\begin{equation}"))));
    try std.testing.expectEqual(first.metrics.math_block_count, @as(u64, @intCast(count(first.bytes, "\\end{equation}"))));
    try std.testing.expect(first.metrics.inline_math_count > 0);
    try std.testing.expect(std.mem.indexOf(u8, first.bytes, "Tiếng Việt") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.bytes, "Tie\xCC\x82\xCC\x81ng") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.bytes, "中文") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.bytes, "العربية") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.bytes, "🧪") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.bytes, "long-line-checkpoint-") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.bytes, "\\paragraph{Indexed observation 0}") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.bytes, "\\paragraph{Indexed observation 1}") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.bytes, "\\cite{ref:") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.bytes, "\\label{sec:") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.bytes, "\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.bytes, "\r") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.bytes, "\n") != null);
}

test "default fixture reaches the T0.2d size gate and hashes exact bytes" {
    var book = try fixture.generate(std.testing.allocator, .{});
    defer book.deinit();

    try std.testing.expect(book.bytes.len >= fixture.minimum_output_bytes);
    try std.testing.expect(book.bytes.len <= fixture.maximum_output_bytes);
    try std.testing.expectEqual(sha256(book.bytes), book.metrics.byte_sha256);
    try fixture.validateMetrics(book.metrics, .{});
}

test "fixture target is nonzero and bounded" {
    try std.testing.expectError(error.InvalidTargetBytes, fixture.generate(std.testing.allocator, .{ .target_bytes = 0 }));
    try std.testing.expectError(
        error.InvalidTargetBytes,
        fixture.generate(std.testing.allocator, .{ .target_bytes = fixture.maximum_target_bytes + 1 }),
    );
}
