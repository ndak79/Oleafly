const std = @import("std");
const strings = @import("app_strings");

test "versioned English resources fail closed for missing and unsupported locales" {
    try std.testing.expectEqual(@as(u32, 1), strings.table_version);
    try std.testing.expectEqualStrings("Open Folder", try strings.lookup("en-US", .open_folder));
    try std.testing.expectEqualStrings("Source", try strings.lookup("en-US", .source));
    try std.testing.expectError(error.UnsupportedLocale, strings.lookup("fr-FR", .source));
    try std.testing.expectError(error.UnsupportedLocale, strings.lookup("en", .source));
    try std.testing.expectError(error.MissingString, strings.lookup_name("en-US", "does.not.exist"));
}

test "pseudo locale expands text and preserves composed combining and BiDi markers" {
    const allocator = std.testing.allocator;
    const composed = "Café";
    const decomposed = "Cafe\u{301}";
    const bidi = "مرحبا";
    const expanded = try strings.pseudo_localize(allocator, composed, .{ .expand = true });
    defer allocator.free(expanded);
    try std.testing.expect(std.mem.startsWith(u8, expanded, "["));
    try std.testing.expect(expanded.len > composed.len);
    const combining = try strings.pseudo_localize(allocator, decomposed, .{ .combining = true });
    defer allocator.free(combining);
    try std.testing.expect(strings.contains_combining_mark(combining));
    const isolated = try strings.pseudo_localize(allocator, bidi, .{ .bidi_isolate = true });
    defer allocator.free(isolated);
    try std.testing.expect(strings.contains_bidi_isolates(isolated));
}

fn exercisePseudoLocalization(allocator: std.mem.Allocator) !void {
    const output = try strings.pseudo_localize(allocator, "Café", .{
        .expand = true,
        .combining = true,
        .bidi_isolate = true,
    });
    defer allocator.free(output);
}

test "pseudo localization releases every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exercisePseudoLocalization, .{});
}
