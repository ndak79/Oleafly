const std = @import("std");
const units = @import("text_units");

test "UTF-8 bytes map to exact UTF-16 endpoints without normalization" {
    const text = "A Ắ cafe\u{301} 👩‍🔬\r\nשלום";
    var document = try units.Document.init(std.testing.allocator, text);
    defer document.deinit();

    try std.testing.expectEqual(text.len, document.byteLength());
    try std.testing.expectEqual(@as(usize, 21), document.utf16Length());
    try std.testing.expectEqual(@as(usize, 0), try document.byteToUtf16(0));
    try std.testing.expectEqual(@as(usize, 1), try document.byteToUtf16(1));
    try std.testing.expectEqual(@as(usize, 2), try document.utf16ToByte(2));
    try std.testing.expectEqual(@as(usize, text.len), try document.utf16ToByte(document.utf16Length()));
    try std.testing.expectError(error.InvalidBoundary, document.byteToUtf16(3));
    try std.testing.expectError(error.InvalidUtf16Boundary, document.utf16ToByte(11));
}

test "grapheme units keep combining marks and emoji ZWJ sequences together" {
    const text = "A\u{301} 👩‍🔬";
    var document = try units.Document.init(std.testing.allocator, text);
    defer document.deinit();
    const characters = try document.collect(std.testing.allocator, .character);
    defer std.testing.allocator.free(characters);

    try std.testing.expectEqual(@as(usize, 3), characters.len);
    try std.testing.expectEqualStrings("A\u{301}", text[characters[0].start.byte..characters[0].end.byte]);
    try std.testing.expectEqualStrings(" ", text[characters[1].start.byte..characters[1].end.byte]);
    try std.testing.expectEqualStrings("👩‍🔬", text[characters[2].start.byte..characters[2].end.byte]);
}

test "control-only character runs do not become movement units" {
    const text = "\u{200e}\u{202a}\u{2069}A";
    var document = try units.Document.init(std.testing.allocator, text);
    defer document.deinit();
    const characters = try document.collect(std.testing.allocator, .character);
    defer std.testing.allocator.free(characters);
    try std.testing.expectEqual(@as(usize, 1), characters.len);
    try std.testing.expectEqualStrings("A", text[characters[0].start.byte..characters[0].end.byte]);
}

test "word units attach leading breaks and retain trailing breaks" {
    const text = "  hello, world  ";
    var document = try units.Document.init(std.testing.allocator, text);
    defer document.deinit();
    const words = try document.collect(std.testing.allocator, .word);
    defer std.testing.allocator.free(words);

    try std.testing.expect(words.len >= 4);
    try std.testing.expectEqualStrings("  hello", text[words[0].start.byte..words[0].end.byte]);
    try std.testing.expectEqualStrings(
        ",",
        text[words[1].start.byte..words[1].end.byte],
    );
}

test "lines preserve CRLF and expose the trailing empty line" {
    const text = "one\r\ntwo\n";
    var document = try units.Document.init(std.testing.allocator, text);
    defer document.deinit();
    const lines = try document.collect(std.testing.allocator, .line);
    defer std.testing.allocator.free(lines);
    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("one\r\n", text[lines[0].start.byte..lines[0].end.byte]);
    try std.testing.expectEqualStrings("two\n", text[lines[1].start.byte..lines[1].end.byte]);
    try std.testing.expectEqual(@as(usize, 0), lines[2].byteLen());
}

test "format units are maximal equal-attribute byte runs at UTF-8 boundaries" {
    const text = "abé";
    var document = try units.Document.init(std.testing.allocator, text);
    defer document.deinit();
    const attributes = [_]u8{ 1, 1, 2, 2 };
    const formats = try document.formatUnits(std.testing.allocator, &attributes);
    defer std.testing.allocator.free(formats);
    try std.testing.expectEqual(@as(usize, 2), formats.len);
    try std.testing.expectEqualStrings("ab", text[formats[0].start.byte..formats[0].end.byte]);
    try std.testing.expectEqualStrings("é", text[formats[1].start.byte..formats[1].end.byte]);
    try std.testing.expectError(error.InvalidAttributeMap, document.formatUnits(std.testing.allocator, &.{1}));
}

test "lossy or unbounded input is rejected before indexing" {
    try std.testing.expectError(error.InvalidUtf8, units.Document.init(std.testing.allocator, &[_]u8{ 0xc0, 0xaf }));
    try std.testing.expectError(error.EmbeddedNul, units.Document.init(std.testing.allocator, "a\x00b"));
}
