const std = @import("std");

pub const table_version: u32 = 1;
pub const english_locale = "en-US";

pub const Key = enum {
    open_folder,
    project,
    source,
    pdf,
    auto,
    on_save,
    manual,
    compile,
    save,
    ready,
    unavailable,
    rebuilding,
    error_status,
    mode,
    splitter,
    status,
    recovery,
};

pub const StringKey = Key;

const Entry = struct {
    key: Key,
    name: []const u8,
    value: []const u8,
};

pub const english_table = [_]Entry{
    .{ .key = .open_folder, .name = "open_folder", .value = "Open Folder" },
    .{ .key = .project, .name = "project", .value = "Project" },
    .{ .key = .source, .name = "source", .value = "Source" },
    .{ .key = .pdf, .name = "pdf", .value = "PDF" },
    .{ .key = .auto, .name = "auto", .value = "Auto" },
    .{ .key = .on_save, .name = "on_save", .value = "On Save" },
    .{ .key = .manual, .name = "manual", .value = "Manual" },
    .{ .key = .compile, .name = "compile", .value = "Compile" },
    .{ .key = .save, .name = "save", .value = "Save" },
    .{ .key = .ready, .name = "ready", .value = "Ready" },
    .{ .key = .unavailable, .name = "unavailable", .value = "Unavailable" },
    .{ .key = .rebuilding, .name = "rebuilding", .value = "Rebuilding" },
    .{ .key = .error_status, .name = "error_status", .value = "Error" },
    .{ .key = .mode, .name = "mode", .value = "Render mode" },
    .{ .key = .splitter, .name = "splitter", .value = "Resize panes" },
    .{ .key = .status, .name = "status", .value = "Status" },
    .{ .key = .recovery, .name = "recovery", .value = "Recover" },
};

pub fn lookup(locale: []const u8, key: Key) ![]const u8 {
    if (!std.mem.eql(u8, locale, english_locale)) return error.UnsupportedLocale;
    return lookup_english(key) orelse error.MissingString;
}

pub const get = lookup;

pub fn lookup_english(key: Key) ?[]const u8 {
    inline for (english_table) |entry| {
        if (entry.key == key) return entry.value;
    }
    return null;
}

pub const lookupEnglish = lookup_english;

pub fn lookup_name(locale: []const u8, name: []const u8) ![]const u8 {
    if (!std.mem.eql(u8, locale, english_locale)) return error.UnsupportedLocale;
    for (english_table) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return entry.value;
    }
    return error.MissingString;
}

pub const lookupName = lookup_name;

pub const PseudoOptions = struct {
    expand: bool = false,
    combining: bool = false,
    bidi_isolate: bool = false,
};

/// Deterministic pseudo-locale helper used by the resource QA lane.  It is a
/// test-only transformation over an already-selected English value; it never
/// acts as a translation fallback.
pub fn pseudo_localize(allocator: std.mem.Allocator, value: []const u8, options: PseudoOptions) ![]u8 {
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    if (options.bidi_isolate) try result.appendSlice(allocator, "\u{2068}");
    if (options.expand) try result.appendSlice(allocator, "[");

    var view = std.unicode.Utf8View.initUnchecked(value);
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |codepoint| {
        var encoded: [4]u8 = undefined;
        const length = std.unicode.utf8Encode(codepoint, &encoded) catch return error.InvalidScalar;
        try result.appendSlice(allocator, encoded[0..length]);
        if (options.combining and !is_combining_mark(codepoint)) {
            try result.appendSlice(allocator, "\u{301}");
        }
        if (options.expand and is_ascii_letter(codepoint)) {
            try result.appendSlice(allocator, "\u{a0}");
        }
    }

    if (options.expand) try result.appendSlice(allocator, "]");
    if (options.bidi_isolate) try result.appendSlice(allocator, "\u{2069}");
    return result.toOwnedSlice(allocator);
}

pub const pseudoLocalize = pseudo_localize;

fn is_ascii_letter(codepoint: u21) bool {
    return (codepoint >= 'a' and codepoint <= 'z') or (codepoint >= 'A' and codepoint <= 'Z');
}

fn is_combining_mark(codepoint: u21) bool {
    return (codepoint >= 0x0300 and codepoint <= 0x036f) or
        (codepoint >= 0x1ab0 and codepoint <= 0x1aff) or
        (codepoint >= 0x1dc0 and codepoint <= 0x1dff) or
        (codepoint >= 0x20d0 and codepoint <= 0x20ff) or
        (codepoint >= 0xfe20 and codepoint <= 0xfe2f);
}

pub fn contains_combining_mark(value: []const u8) bool {
    if (!std.unicode.utf8ValidateSlice(value)) return false;
    var view = std.unicode.Utf8View.initUnchecked(value);
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |codepoint| {
        if (is_combining_mark(codepoint)) return true;
    }
    return false;
}

pub const containsCombiningMark = contains_combining_mark;

pub fn contains_bidi_isolates(value: []const u8) bool {
    if (!std.unicode.utf8ValidateSlice(value)) return false;
    var view = std.unicode.Utf8View.initUnchecked(value);
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |codepoint| {
        if (codepoint >= 0x2066 and codepoint <= 0x2069) return true;
    }
    return false;
}

pub const containsBidiIsolates = contains_bidi_isolates;
