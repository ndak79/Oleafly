const std = @import("std");
const model = @import("editor_model");
const editor_buffer = @import("editor_buffer");
const text_units = @import("text_units");

test "editor model attaches, materializes, and tracks lines" {
    const allocator = std.testing.allocator;
    const text = "First line\nSecond line\nThird line\n";
    var m = try model.Model.attach(allocator, "C:\\test.tex", text);
    defer m.deinit();

    try std.testing.expectEqual(text.len, m.textLength());
    try std.testing.expectEqual(@as(usize, 4), m.lineCount());
    try std.testing.expectEqual(@as(usize, 0), try m.lineStart(0));
    try std.testing.expectEqual(@as(usize, 11), try m.lineStart(1));
    try std.testing.expectEqual(@as(usize, 23), try m.lineStart(2));
    try std.testing.expectEqual(@as(usize, 34), try m.lineStart(3));
    try m.audit(allocator);
}

test "editor model updates line index incrementally across edits" {
    const allocator = std.testing.allocator;
    const text = "line 1\nline 2\nline 3\n";
    var m = try model.Model.attach(allocator, "C:\\test.tex", text);
    defer m.deinit();

    // Insert a new line inside line 2
    try m.applyEdit(1, 7, 0, "inserted line\n");
    try std.testing.expectEqual(@as(usize, 5), m.lineCount());
    try m.audit(allocator);

    // Delete the inserted line
    try m.applyEdit(2, 7, "inserted line\n".len, "");
    try std.testing.expectEqual(@as(usize, 4), m.lineCount());
    try m.audit(allocator);
}

test "editor model rejects invalid UTF-8 and maintains audit convergence" {
    const allocator = std.testing.allocator;
    const text = "Valid ASCII text\n";
    var m = try model.Model.attach(allocator, "C:\\test.tex", text);
    defer m.deinit();

    // Attempt to insert invalid UTF-8 bytes
    const invalid = [_]u8{ 0xff, 0xfe };
    try std.testing.expectError(error.InvalidUtf8, m.applyEdit(1, 0, 0, &invalid));
    try m.audit(allocator);
}

test "editor model takes immutable text-unit snapshots with revision stamps" {
    const allocator = std.testing.allocator;
    const text = "Hello world\nSecond line\n";
    var m = try model.Model.attach(allocator, "C:\\test.tex", text);
    defer m.deinit();

    var snap1 = try m.snapshot(allocator);
    defer snap1.deinit();
    try std.testing.expectEqual(@as(u64, 0), snap1.revision);
    try std.testing.expectEqualStrings(text, snap1.text());

    try m.applyEdit(1, 0, 5, "Dear");
    try std.testing.expectEqual(@as(u64, 1), m.revision());

    var snap2 = try m.snapshot(allocator);
    defer snap2.deinit();
    try std.testing.expectEqual(@as(u64, 1), snap2.revision);
    try std.testing.expectEqualStrings("Dear world\nSecond line\n", snap2.text());
    // snap1 remains unchanged and valid
    try std.testing.expectEqualStrings(text, snap1.text());
}
