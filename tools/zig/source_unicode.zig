//! Standalone Unicode-17 path-key support for source_identity.zig.
//!
//! The product's generated Unicode module is built from the locked UCD zip.
//! The build-graph identity collector runs before that module exists, so it
//! uses this checked-in, generator-produced table as the same-version
//! collision oracle. Raw path bytes remain unchanged in the source digest.
const std = @import("std");
const data = @import("source_unicode_data.zig");

pub const unicode_version = data.unicode_version;

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
            try appendBoundedScalars(allocator, &folded, data.case_folding_values[start..end], max_output_bytes);
        } else {
            try appendBoundedScalar(allocator, &folded, codepoint, max_output_bytes);
        }
    }

    var renormalized: std.ArrayList(u21) = .empty;
    defer renormalized.deinit(allocator);
    for (folded.items) |codepoint| {
        try decomposeAndAppend(allocator, &renormalized, codepoint, max_output_bytes, 0);
    }
    return encodeScalars(allocator, renormalized.items, max_output_bytes);
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
        for (hangul.slice()) |part| try appendCanonicalOrdered(allocator, output, part, max_output_bytes);
        return;
    }
    if (findMap(data.decomposition[0..], codepoint)) |mapping| {
        const start: usize = mapping.offset;
        const end = start + mapping.length;
        if (end > data.decomposition_values.len or mapping.length == 0) return error.CorruptUnicodeTable;
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
    const v_count = 21;
    const t_count = 28;
    const n_count = v_count * t_count;
    const s_count = 19 * n_count;
    if (codepoint < s_base or codepoint >= s_base + s_count) return null;
    const s_index = codepoint - s_base;
    const l_part: u21 = l_base + s_index / n_count;
    const v_part: u21 = v_base + (s_index % n_count) / t_count;
    const t_index = s_index % t_count;
    if (t_index == 0) return .{ .values = .{ l_part, v_part, 0 }, .length = 2 };
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
    if (values.len > max_output_bytes -| output.items.len) return error.UnicodeOutputLimitExceeded;
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
        if (length > max_output_bytes -| output.items.len) return error.UnicodeOutputLimitExceeded;
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
