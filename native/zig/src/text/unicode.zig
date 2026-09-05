const std = @import("std");
const data = @import("unicode_data");

pub const unicode_version = data.unicode_version;
pub const uax15_revision = data.uax15_revision;
pub const uax29_revision = data.uax29_revision;
pub const table_bytes = data.table_bytes;

pub const GraphemeProperty = enum(u8) {
    other,
    cr,
    lf,
    control,
    extend,
    zwj,
    regional_indicator,
    prepend,
    spacing_mark,
    l,
    v,
    t,
    lv,
    lvt,
};

pub const WordProperty = enum(u8) {
    other,
    cr,
    lf,
    newline,
    extend,
    format,
    zwj,
    regional_indicator,
    katakana,
    hebrew_letter,
    aletter,
    single_quote,
    double_quote,
    midnumlet,
    midletter,
    midnum,
    numeric,
    extendnumlet,
    wsegspace,
};

const InCbProperty = enum(u8) {
    none,
    consonant,
    linker,
    extend,
};

pub fn normalizeNfd(
    allocator: std.mem.Allocator,
    input: []const u8,
    max_output_bytes: usize,
) ![]u8 {
    const scalars = try decodeAndNormalizeNfd(allocator, input, max_output_bytes);
    defer allocator.free(scalars);
    return encodeScalars(allocator, scalars, max_output_bytes);
}

pub fn foldNfd(
    allocator: std.mem.Allocator,
    input: []const u8,
    max_output_bytes: usize,
) ![]u8 {
    const normalized = try decodeAndNormalizeNfd(allocator, input, max_output_bytes);
    defer allocator.free(normalized);
    var folded: std.ArrayList(u21) = .empty;
    defer folded.deinit(allocator);
    for (normalized) |codepoint| {
        if (findMap(data.case_folding[0..], codepoint)) |mapping| {
            const start: usize = mapping.offset;
            const end = start + mapping.length;
            if (end > data.case_folding_values.len) return error.CorruptUnicodeTable;
            try appendBoundedScalars(
                allocator,
                &folded,
                data.case_folding_values[start..end],
                max_output_bytes,
            );
        } else {
            try appendBoundedScalar(allocator, &folded, codepoint, max_output_bytes);
        }
    }

    var renormalized: std.ArrayList(u21) = .empty;
    defer renormalized.deinit(allocator);
    for (folded.items) |codepoint| {
        try decomposeAndAppend(
            allocator,
            &renormalized,
            codepoint,
            max_output_bytes,
            0,
        );
    }
    return encodeScalars(allocator, renormalized.items, max_output_bytes);
}

pub fn decodeScalars(
    allocator: std.mem.Allocator,
    input: []const u8,
    max_scalars: usize,
) ![]u21 {
    if (!std.unicode.utf8ValidateSlice(input)) return error.InvalidUtf8;
    var scalars: std.ArrayList(u21) = .empty;
    errdefer scalars.deinit(allocator);
    var view = std.unicode.Utf8View.initUnchecked(input);
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |codepoint| {
        if (scalars.items.len >= max_scalars) return error.UnicodeScalarLimitExceeded;
        try scalars.append(allocator, codepoint);
    }
    return scalars.toOwnedSlice(allocator);
}

fn decodeAndNormalizeNfd(
    allocator: std.mem.Allocator,
    input: []const u8,
    max_output_bytes: usize,
) ![]u21 {
    if (!std.unicode.utf8ValidateSlice(input)) return error.InvalidUtf8;
    var output: std.ArrayList(u21) = .empty;
    errdefer output.deinit(allocator);
    var view = std.unicode.Utf8View.initUnchecked(input);
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |codepoint| {
        try decomposeAndAppend(allocator, &output, codepoint, max_output_bytes, 0);
    }
    return output.toOwnedSlice(allocator);
}

fn decomposeAndAppend(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u21),
    codepoint: u21,
    max_output_bytes: usize,
    depth: u8,
) !void {
    if (depth > 32) return error.CorruptUnicodeTable;
    if (decomposeHangul(codepoint)) |hangul| {
        for (hangul.slice()) |part| {
            try appendCanonicalOrdered(allocator, output, part, max_output_bytes);
        }
        return;
    }
    if (findMap(data.decomposition[0..], codepoint)) |mapping| {
        const start: usize = mapping.offset;
        const end = start + mapping.length;
        if (end > data.decomposition_values.len or mapping.length == 0) {
            return error.CorruptUnicodeTable;
        }
        for (data.decomposition_values[start..end]) |part| {
            try decomposeAndAppend(allocator, output, part, max_output_bytes, depth + 1);
        }
        return;
    }
    try appendCanonicalOrdered(allocator, output, codepoint, max_output_bytes);
}

const HangulDecomposition = struct {
    values: [3]u21,
    length: u2,

    fn slice(self: *const @This()) []const u21 {
        return self.values[0..self.length];
    }
};

fn decomposeHangul(codepoint: u21) ?HangulDecomposition {
    const s_base = 0xac00;
    const l_base = 0x1100;
    const v_base = 0x1161;
    const t_base = 0x11a7;
    const l_count = 19;
    const v_count = 21;
    const t_count = 28;
    const n_count = v_count * t_count;
    const s_count = l_count * n_count;
    if (codepoint < s_base or codepoint >= s_base + s_count) return null;
    const s_index = codepoint - s_base;
    const l_part: u21 = l_base + s_index / n_count;
    const v_part: u21 = v_base + (s_index % n_count) / t_count;
    const t_index = s_index % t_count;
    if (t_index == 0) {
        return .{ .values = .{ l_part, v_part, 0 }, .length = 2 };
    }
    return .{ .values = .{ l_part, v_part, t_base + t_index }, .length = 3 };
}

fn appendCanonicalOrdered(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u21),
    codepoint: u21,
    max_output_bytes: usize,
) !void {
    try appendBoundedScalar(allocator, output, codepoint, max_output_bytes);
    const current_ccc = canonicalCombiningClass(codepoint);
    if (current_ccc == 0) return;
    var index = output.items.len - 1;
    while (index > 0) {
        const previous_ccc = canonicalCombiningClass(output.items[index - 1]);
        if (previous_ccc == 0 or previous_ccc <= current_ccc) break;
        std.mem.swap(u21, &output.items[index - 1], &output.items[index]);
        index -= 1;
    }
}

fn appendBoundedScalar(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u21),
    codepoint: u21,
    max_output_bytes: usize,
) !void {
    if (output.items.len >= max_output_bytes) return error.UnicodeOutputLimitExceeded;
    try output.append(allocator, codepoint);
}

fn appendBoundedScalars(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u21),
    values: []const u21,
    max_output_bytes: usize,
) !void {
    if (values.len > max_output_bytes -| output.items.len) {
        return error.UnicodeOutputLimitExceeded;
    }
    try output.appendSlice(allocator, values);
}

fn encodeScalars(
    allocator: std.mem.Allocator,
    scalars: []const u21,
    max_output_bytes: usize,
) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    for (scalars) |codepoint| {
        var encoded: [4]u8 = undefined;
        const length = std.unicode.utf8Encode(codepoint, &encoded) catch return error.InvalidScalar;
        if (length > max_output_bytes -| output.items.len) {
            return error.UnicodeOutputLimitExceeded;
        }
        try output.appendSlice(allocator, encoded[0..length]);
    }
    return output.toOwnedSlice(allocator);
}

fn canonicalCombiningClass(codepoint: u21) u8 {
    var low: usize = 0;
    var high = data.ccc.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const entry = data.ccc[middle];
        if (codepoint < entry.codepoint) high = middle else if (codepoint > entry.codepoint) low = middle + 1 else return entry.value;
    }
    return 0;
}

fn findMap(entries: anytype, codepoint: u21) ?@TypeOf(entries[0]) {
    var low: usize = 0;
    var high = entries.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const entry = entries[middle];
        if (codepoint < entry.codepoint) high = middle else if (codepoint > entry.codepoint) low = middle + 1 else return entry;
    }
    return null;
}

pub fn graphemeProperty(codepoint: u21) GraphemeProperty {
    return @enumFromInt(rangeValue(data.grapheme[0..], codepoint));
}

pub fn wordProperty(codepoint: u21) WordProperty {
    return @enumFromInt(rangeValue(data.word[0..], codepoint));
}

fn incbProperty(codepoint: u21) InCbProperty {
    return @enumFromInt(rangeValue(data.incb[0..], codepoint));
}

pub fn isExtendedPictographic(codepoint: u21) bool {
    return rangeValue(data.extended_pictographic[0..], codepoint) != 0;
}

pub fn isLetterOrNumber(codepoint: u21) bool {
    return rangeValue(data.letter_or_number[0..], codepoint) != 0;
}

fn rangeValue(ranges: anytype, codepoint: u21) u8 {
    var low: usize = 0;
    var high = ranges.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const range = ranges[middle];
        if (codepoint < range.start) high = middle else if (codepoint > range.end) low = middle + 1 else return range.value;
    }
    return 0;
}

pub fn isGraphemeBoundary(codepoints: []const u21, index: usize) bool {
    if (index == 0 or index >= codepoints.len) return true;
    const left = graphemeProperty(codepoints[index - 1]);
    const right = graphemeProperty(codepoints[index]);
    if (left == .cr and right == .lf) return false;
    if (isGraphemeControl(left) or isGraphemeControl(right)) return true;
    if (left == .l and (right == .l or right == .v or right == .lv or right == .lvt)) return false;
    if ((left == .lv or left == .v) and (right == .v or right == .t)) return false;
    if ((left == .lvt or left == .t) and right == .t) return false;
    if (right == .extend or right == .zwj or right == .spacing_mark) return false;
    if (left == .prepend) return false;
    if (incbProperty(codepoints[index]) == .consonant and hasInCbLinkerSequence(codepoints, index)) {
        return false;
    }
    if (isExtendedPictographic(codepoints[index]) and left == .zwj and
        hasExtendedPictographicBeforeZwj(codepoints, index - 1))
    {
        return false;
    }
    if (left == .regional_indicator and right == .regional_indicator) {
        var count: usize = 0;
        var cursor = index;
        while (cursor > 0 and graphemeProperty(codepoints[cursor - 1]) == .regional_indicator) {
            count += 1;
            cursor -= 1;
        }
        if (count % 2 == 1) return false;
    }
    return true;
}

fn isGraphemeControl(property: GraphemeProperty) bool {
    return property == .control or property == .cr or property == .lf;
}

fn hasInCbLinkerSequence(codepoints: []const u21, boundary: usize) bool {
    var cursor = boundary;
    var saw_linker = false;
    while (cursor > 0) {
        cursor -= 1;
        switch (incbProperty(codepoints[cursor])) {
            .linker => saw_linker = true,
            .extend => {},
            .consonant => return saw_linker,
            .none => return false,
        }
    }
    return false;
}

fn hasExtendedPictographicBeforeZwj(codepoints: []const u21, zwj_index: usize) bool {
    var cursor = zwj_index;
    while (cursor > 0) {
        cursor -= 1;
        if (graphemeProperty(codepoints[cursor]) == .extend) continue;
        return isExtendedPictographic(codepoints[cursor]);
    }
    return false;
}

pub fn isWordBoundary(codepoints: []const u21, index: usize) bool {
    if (index == 0 or index >= codepoints.len) return true;
    const raw_left = wordProperty(codepoints[index - 1]);
    const raw_right = wordProperty(codepoints[index]);
    if (raw_left == .cr and raw_right == .lf) return false;
    if (isWordNewline(raw_left) or isWordNewline(raw_right)) return true;
    if (raw_left == .zwj and isExtendedPictographic(codepoints[index])) return false;
    if (raw_left == .wsegspace and raw_right == .wsegspace) return false;
    if (isWordIgnored(raw_right)) return false;

    const left_index = previousWordSignificant(codepoints, index) orelse return true;
    const left = wordProperty(codepoints[left_index]);
    const right = raw_right;
    if (isAhLetter(left) and isAhLetter(right)) return false;
    if (isAhLetter(left) and isMidLetterOrMidNumLetQ(right)) {
        if (nextWordSignificant(codepoints, index + 1)) |next| {
            if (isAhLetter(wordProperty(codepoints[next]))) return false;
        }
    }
    if (isMidLetterOrMidNumLetQ(left) and isAhLetter(right)) {
        if (previousWordSignificant(codepoints, left_index)) |previous| {
            if (isAhLetter(wordProperty(codepoints[previous]))) return false;
        }
    }
    if (left == .hebrew_letter and right == .single_quote) return false;
    if (left == .hebrew_letter and right == .double_quote) {
        if (nextWordSignificant(codepoints, index + 1)) |next| {
            if (wordProperty(codepoints[next]) == .hebrew_letter) return false;
        }
    }
    if (left == .double_quote and right == .hebrew_letter) {
        if (previousWordSignificant(codepoints, left_index)) |previous| {
            if (wordProperty(codepoints[previous]) == .hebrew_letter) return false;
        }
    }
    if (left == .numeric and right == .numeric) return false;
    if (isAhLetter(left) and right == .numeric) return false;
    if (left == .numeric and isAhLetter(right)) return false;
    if (left == .numeric and isMidNumOrMidNumLetQ(right)) {
        if (nextWordSignificant(codepoints, index + 1)) |next| {
            if (wordProperty(codepoints[next]) == .numeric) return false;
        }
    }
    if (isMidNumOrMidNumLetQ(left) and right == .numeric) {
        if (previousWordSignificant(codepoints, left_index)) |previous| {
            if (wordProperty(codepoints[previous]) == .numeric) return false;
        }
    }
    if (left == .katakana and right == .katakana) return false;
    if (isWordCore(left) and right == .extendnumlet) return false;
    if (left == .extendnumlet and isWordCore(right)) return false;
    if (left == .regional_indicator and right == .regional_indicator) {
        var count: usize = 0;
        var cursor: ?usize = left_index;
        while (cursor) |current| {
            if (wordProperty(codepoints[current]) != .regional_indicator) break;
            count += 1;
            cursor = previousWordSignificant(codepoints, current);
        }
        if (count % 2 == 1) return false;
    }
    return true;
}

fn previousWordSignificant(codepoints: []const u21, before: usize) ?usize {
    var cursor = before;
    while (cursor > 0) {
        cursor -= 1;
        if (!isWordIgnored(wordProperty(codepoints[cursor]))) return cursor;
    }
    return null;
}

fn nextWordSignificant(codepoints: []const u21, from: usize) ?usize {
    var cursor = from;
    while (cursor < codepoints.len) : (cursor += 1) {
        if (!isWordIgnored(wordProperty(codepoints[cursor]))) return cursor;
    }
    return null;
}

fn isWordIgnored(property: WordProperty) bool {
    return property == .extend or property == .format or property == .zwj;
}

fn isWordNewline(property: WordProperty) bool {
    return property == .cr or property == .lf or property == .newline;
}

fn isAhLetter(property: WordProperty) bool {
    return property == .aletter or property == .hebrew_letter;
}

fn isMidLetterOrMidNumLetQ(property: WordProperty) bool {
    return property == .midletter or property == .midnumlet or property == .single_quote;
}

fn isMidNumOrMidNumLetQ(property: WordProperty) bool {
    return property == .midnum or property == .midnumlet or property == .single_quote;
}

fn isWordCore(property: WordProperty) bool {
    return isAhLetter(property) or property == .numeric or property == .katakana or property == .extendnumlet;
}

pub fn graphemeBoundaries(
    allocator: std.mem.Allocator,
    input: []const u8,
    max_scalars: usize,
) ![]usize {
    const scalars = try decodeScalars(allocator, input, max_scalars);
    defer allocator.free(scalars);
    var boundaries: std.ArrayList(usize) = .empty;
    errdefer boundaries.deinit(allocator);
    var byte_offset: usize = 0;
    for (scalars, 0..) |codepoint, index| {
        if (isGraphemeBoundary(scalars, index)) try boundaries.append(allocator, byte_offset);
        byte_offset += std.unicode.utf8CodepointSequenceLength(codepoint) catch
            return error.InvalidScalar;
    }
    try boundaries.append(allocator, byte_offset);
    return boundaries.toOwnedSlice(allocator);
}

pub fn wordBoundaries(
    allocator: std.mem.Allocator,
    input: []const u8,
    max_scalars: usize,
) ![]usize {
    const scalars = try decodeScalars(allocator, input, max_scalars);
    defer allocator.free(scalars);
    var boundaries: std.ArrayList(usize) = .empty;
    errdefer boundaries.deinit(allocator);
    var byte_offset: usize = 0;
    for (scalars, 0..) |codepoint, index| {
        if (isWordBoundary(scalars, index)) try boundaries.append(allocator, byte_offset);
        byte_offset += std.unicode.utf8CodepointSequenceLength(codepoint) catch
            return error.InvalidScalar;
    }
    try boundaries.append(allocator, byte_offset);
    return boundaries.toOwnedSlice(allocator);
}
