//! Lossless document offsets and UIA text-unit boundaries.
//!
//! Source bytes are borrowed and never normalized.  The index stores compact
//! UTF-16 checkpoints plus boundary bitsets; exact endpoints are decoded from
//! the nearest checkpoint, so an ASCII-heavy document does not pay one record
//! per byte.

const std = @import("std");
const unicode = @import("unicode");

pub const max_document_bytes: usize = 32 * 1024 * 1024;
pub const max_metadata_bytes: usize = 24 * 1024 * 1024;
pub const checkpoint_stride: usize = 256;

pub const UnitKind = enum {
    character,
    word,
    format,
    line,
    paragraph,
    document,
};

pub const Point = struct {
    byte: usize,
    utf16: usize,
};

pub const Unit = struct {
    kind: UnitKind,
    start: Point,
    end: Point,

    pub fn byteLen(self: Unit) usize {
        return self.end.byte - self.start.byte;
    }

    pub fn utf16Len(self: Unit) usize {
        return self.end.utf16 - self.start.utf16;
    }
};

pub const Error = error{
    DocumentTooLarge,
    MetadataLimitExceeded,
    EmbeddedNul,
    InvalidUtf8,
    InvalidBoundary,
    InvalidUtf16Boundary,
    InvalidAttributeMap,
    ScalarLimitExceeded,
    OffsetOverflow,
};

const Checkpoint = struct {
    byte: u32,
    utf16: u32,
};

pub const Document = struct {
    allocator: std.mem.Allocator,
    bytes: []const u8,
    grapheme_bits: []u8,
    word_bits: []u8,
    checkpoints: []Checkpoint,
    utf16_length: u32,
    scalar_count: u32,
    metadata_bytes: usize,

    pub fn init(allocator: std.mem.Allocator, bytes: []const u8) !Document {
        if (bytes.len > max_document_bytes) return error.DocumentTooLarge;
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
        if (std.mem.indexOfScalar(u8, bytes, 0) != null) return error.EmbeddedNul;

        const bitset_len = bitsetBytes(bytes.len + 1);
        const metadata_floor = bitset_len * 2;
        if (metadata_floor > max_metadata_bytes) return error.MetadataLimitExceeded;

        const grapheme_bits = try allocator.alloc(u8, bitset_len);
        errdefer allocator.free(grapheme_bits);
        @memset(grapheme_bits, 0);
        const word_bits = try allocator.alloc(u8, bitset_len);
        errdefer allocator.free(word_bits);
        @memset(word_bits, 0);

        const scalar_limit = bytes.len + 1;
        const grapheme_boundaries = unicode.graphemeBoundaries(allocator, bytes, scalar_limit) catch |err| {
            return switch (err) {
                error.InvalidUtf8 => error.InvalidUtf8,
                error.UnicodeScalarLimitExceeded => error.ScalarLimitExceeded,
                else => err,
            };
        };
        defer allocator.free(grapheme_boundaries);
        const word_boundaries = unicode.wordBoundaries(allocator, bytes, scalar_limit) catch |err| {
            return switch (err) {
                error.InvalidUtf8 => error.InvalidUtf8,
                error.UnicodeScalarLimitExceeded => error.ScalarLimitExceeded,
                else => err,
            };
        };
        defer allocator.free(word_boundaries);
        for (grapheme_boundaries) |offset| {
            if (offset > bytes.len) return error.InvalidBoundary;
            setBit(grapheme_bits, offset);
        }
        for (word_boundaries) |offset| {
            if (offset > bytes.len) return error.InvalidBoundary;
            setBit(word_bits, offset);
        }

        var checkpoints: std.ArrayList(Checkpoint) = .empty;
        errdefer checkpoints.deinit(allocator);
        try checkpoints.append(allocator, .{ .byte = 0, .utf16 = 0 });
        var byte_offset: usize = 0;
        var utf16_offset: usize = 0;
        var scalar_count: usize = 0;
        var next_checkpoint = checkpoint_stride;
        while (byte_offset < bytes.len) {
            const codepoint = try decodeAt(bytes, byte_offset);
            const sequence_len = try std.unicode.utf8ByteSequenceLength(bytes[byte_offset]);
            byte_offset += sequence_len;
            utf16_offset = std.math.add(usize, utf16_offset, utf16Units(codepoint)) catch return error.OffsetOverflow;
            scalar_count = std.math.add(usize, scalar_count, 1) catch return error.OffsetOverflow;
            if (byte_offset >= next_checkpoint and byte_offset < bytes.len) {
                try checkpoints.append(allocator, .{
                    .byte = std.math.cast(u32, byte_offset) orelse return error.OffsetOverflow,
                    .utf16 = std.math.cast(u32, utf16_offset) orelse return error.OffsetOverflow,
                });
                next_checkpoint = byte_offset + checkpoint_stride;
            }
        }
        if (utf16_offset > std.math.maxInt(u32) or scalar_count > std.math.maxInt(u32)) return error.OffsetOverflow;
        const checkpoint_slice = try checkpoints.toOwnedSlice(allocator);
        errdefer allocator.free(checkpoint_slice);
        const metadata_bytes = bitset_len * 2 + checkpoint_slice.len * @sizeOf(Checkpoint);
        if (metadata_bytes > max_metadata_bytes) return error.MetadataLimitExceeded;

        return .{
            .allocator = allocator,
            .bytes = bytes,
            .grapheme_bits = grapheme_bits,
            .word_bits = word_bits,
            .checkpoints = checkpoint_slice,
            .utf16_length = @intCast(utf16_offset),
            .scalar_count = @intCast(scalar_count),
            .metadata_bytes = metadata_bytes,
        };
    }

    pub fn deinit(self: *Document) void {
        self.allocator.free(self.grapheme_bits);
        self.allocator.free(self.word_bits);
        self.allocator.free(self.checkpoints);
        self.* = undefined;
    }

    pub fn text(self: *const Document) []const u8 {
        return self.bytes;
    }

    pub fn byteLength(self: *const Document) usize {
        return self.bytes.len;
    }

    pub fn utf16Length(self: *const Document) usize {
        return self.utf16_length;
    }

    pub fn scalarCount(self: *const Document) usize {
        return self.scalar_count;
    }

    pub fn metadataBytes(self: *const Document) usize {
        return self.metadata_bytes;
    }

    pub fn byteToUtf16(self: *const Document, byte: usize) !usize {
        return (try self.pointAtByte(byte)).utf16;
    }

    pub fn utf16ToByte(self: *const Document, utf16: usize) !usize {
        return (try self.pointAtUtf16(utf16)).byte;
    }

    pub fn pointAtByte(self: *const Document, byte: usize) !Point {
        if (byte > self.bytes.len) return error.InvalidBoundary;
        const checkpoint = self.checkpointForByte(byte);
        var cursor = checkpoint.byte;
        var units: usize = checkpoint.utf16;
        while (cursor < byte) {
            const codepoint = try decodeAt(self.bytes, cursor);
            const sequence_len = try std.unicode.utf8ByteSequenceLength(self.bytes[cursor]);
            if (sequence_len > byte - cursor) return error.InvalidBoundary;
            cursor += sequence_len;
            units += utf16Units(codepoint);
        }
        if (cursor != byte) return error.InvalidBoundary;
        return .{ .byte = byte, .utf16 = units };
    }

    pub fn pointAtUtf16(self: *const Document, utf16: usize) !Point {
        if (utf16 > self.utf16_length) return error.InvalidUtf16Boundary;
        const checkpoint = self.checkpointForUtf16(utf16);
        var cursor = checkpoint.byte;
        var units: usize = checkpoint.utf16;
        while (units < utf16) {
            const codepoint = try decodeAt(self.bytes, cursor);
            const sequence_len = try std.unicode.utf8ByteSequenceLength(self.bytes[cursor]);
            const advance = utf16Units(codepoint);
            if (advance > utf16 - units) return error.InvalidUtf16Boundary;
            cursor += sequence_len;
            units += advance;
        }
        if (units != utf16) return error.InvalidUtf16Boundary;
        return .{ .byte = cursor, .utf16 = utf16 };
    }

    pub fn count(self: *const Document, kind: UnitKind) !usize {
        const units = try self.collect(self.allocator, kind);
        defer self.allocator.free(units);
        return units.len;
    }

    pub fn unitAt(self: *const Document, allocator: std.mem.Allocator, kind: UnitKind, index: usize) !Unit {
        const units = try self.collect(allocator, kind);
        defer allocator.free(units);
        if (index >= units.len) return error.UnitOutOfRange;
        return units[index];
    }

    pub fn collect(self: *const Document, allocator: std.mem.Allocator, kind: UnitKind) ![]Unit {
        var result: std.ArrayList(Unit) = .empty;
        errdefer result.deinit(allocator);
        switch (kind) {
            .document => try result.append(allocator, self.makeUnit(.document, 0, self.bytes.len)),
            .character => try self.collectBoundaryUnits(allocator, &result, .character, self.grapheme_bits, true),
            .word => try self.collectWordUnits(allocator, &result),
            .line, .paragraph => try self.collectLineUnits(allocator, &result, kind),
            .format => return error.InvalidAttributeMap,
        }
        return result.toOwnedSlice(allocator);
    }

    pub fn formatUnits(self: *const Document, allocator: std.mem.Allocator, attributes: []const u8) ![]Unit {
        if (attributes.len != self.bytes.len) return error.InvalidAttributeMap;
        var result: std.ArrayList(Unit) = .empty;
        errdefer result.deinit(allocator);
        if (attributes.len == 0) return result.toOwnedSlice(allocator);
        var start: usize = 0;
        var value = attributes[0];
        for (attributes[1..], 1..) |attribute, index| {
            if (attribute == value) continue;
            _ = try self.pointAtByte(index);
            try result.append(allocator, self.makeUnit(.format, start, index));
            start = index;
            value = attribute;
        }
        try result.append(allocator, self.makeUnit(.format, start, attributes.len));
        return result.toOwnedSlice(allocator);
    }

    fn collectBoundaryUnits(
        self: *const Document,
        allocator: std.mem.Allocator,
        result: *std.ArrayList(Unit),
        kind: UnitKind,
        bits: []const u8,
        exclude_controls: bool,
    ) !void {
        if (self.bytes.len == 0) {
            try result.append(allocator, self.makeUnit(.document, 0, 0));
            return;
        }
        var previous: ?usize = null;
        var offset: usize = 0;
        while (offset <= self.bytes.len) : (offset += 1) {
            if (!getBit(bits, offset)) continue;
            if (previous) |start| {
                if (!exclude_controls or !isControlOnly(self.bytes[start..offset])) {
                    try result.append(allocator, self.makeUnit(kind, start, offset));
                }
            }
            previous = offset;
        }
        if (result.items.len == 0) try result.append(allocator, self.makeUnit(.document, 0, self.bytes.len));
    }

    fn collectWordUnits(self: *const Document, allocator: std.mem.Allocator, result: *std.ArrayList(Unit)) !void {
        if (self.bytes.len == 0) {
            try result.append(allocator, self.makeUnit(.document, 0, 0));
            return;
        }
        var raw: std.ArrayList(Unit) = .empty;
        defer raw.deinit(allocator);
        try self.collectBoundaryUnits(allocator, &raw, .word, self.word_bits, false);
        if (raw.items.len == 1 and raw.items[0].kind == .document) {
            try result.append(allocator, raw.items[0]);
            return;
        }
        var first_lexical: ?usize = null;
        for (raw.items, 0..) |unit, index| {
            if (containsLexical(self.bytes[unit.start.byte..unit.end.byte])) {
                first_lexical = index;
                break;
            }
        }
        if (first_lexical == null) {
            try result.append(allocator, self.makeUnit(.document, 0, self.bytes.len));
            return;
        }
        const first = first_lexical.?;
        try result.append(allocator, self.makeUnit(.word, 0, raw.items[first].end.byte));
        for (raw.items[first + 1 ..]) |unit| try result.append(allocator, unit);
    }

    fn collectLineUnits(self: *const Document, allocator: std.mem.Allocator, result: *std.ArrayList(Unit), kind: UnitKind) !void {
        var start: usize = 0;
        var index: usize = 0;
        while (index < self.bytes.len) {
            const end = switch (self.bytes[index]) {
                '\r' => if (index + 1 < self.bytes.len and self.bytes[index + 1] == '\n') index + 2 else index + 1,
                '\n' => index + 1,
                else => {
                    index += 1;
                    continue;
                },
            };
            try result.append(allocator, self.makeUnit(kind, start, end));
            start = end;
            index = end;
        }
        try result.append(allocator, self.makeUnit(kind, start, self.bytes.len));
    }

    fn makeUnit(self: *const Document, kind: UnitKind, start: usize, end: usize) Unit {
        return .{
            .kind = kind,
            .start = .{ .byte = start, .utf16 = self.byteToUtf16(start) catch unreachable },
            .end = .{ .byte = end, .utf16 = self.byteToUtf16(end) catch unreachable },
        };
    }

    fn checkpointForByte(self: *const Document, byte: usize) Checkpoint {
        var low: usize = 0;
        var high: usize = self.checkpoints.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.checkpoints[middle].byte <= byte) low = middle + 1 else high = middle;
        }
        return self.checkpoints[low - 1];
    }

    fn checkpointForUtf16(self: *const Document, utf16: usize) Checkpoint {
        var low: usize = 0;
        var high: usize = self.checkpoints.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.checkpoints[middle].utf16 <= utf16) low = middle + 1 else high = middle;
        }
        return self.checkpoints[low - 1];
    }
};

fn bitsetBytes(bit_count: usize) usize {
    return (bit_count + 7) / 8;
}

fn setBit(bits: []u8, index: usize) void {
    bits[index / 8] |= @as(u8, 1) << @intCast(index % 8);
}

fn getBit(bits: []const u8, index: usize) bool {
    return bits[index / 8] & (@as(u8, 1) << @intCast(index % 8)) != 0;
}

fn utf16Units(codepoint: u21) usize {
    return if (codepoint > 0xffff) 2 else 1;
}

fn decodeAt(bytes: []const u8, index: usize) !u21 {
    const sequence_len = try std.unicode.utf8ByteSequenceLength(bytes[index]);
    if (index + sequence_len > bytes.len) return error.InvalidUtf8;
    return switch (sequence_len) {
        1 => bytes[index],
        2 => std.unicode.utf8Decode2(bytes[index..][0..2].*),
        3 => std.unicode.utf8Decode3(bytes[index..][0..3].*),
        4 => std.unicode.utf8Decode4(bytes[index..][0..4].*),
        else => error.InvalidUtf8,
    } catch error.InvalidUtf8;
}

fn isControlOnly(bytes: []const u8) bool {
    if (bytes.len == 0) return true;
    var index: usize = 0;
    while (index < bytes.len) {
        const codepoint = decodeAt(bytes, index) catch return true;
        if (!isExcludedControl(codepoint)) return false;
        index += std.unicode.utf8ByteSequenceLength(bytes[index]) catch return true;
    }
    return true;
}

fn isExcludedControl(codepoint: u21) bool {
    return codepoint <= 0x1f or
        (codepoint >= 0x7f and codepoint <= 0x9f) or
        codepoint == 0x061c or
        (codepoint >= 0x200e and codepoint <= 0x200f) or
        (codepoint >= 0x202a and codepoint <= 0x202e) or
        (codepoint >= 0x2066 and codepoint <= 0x2069) or
        codepoint == 0xfeff;
}

fn containsLexical(bytes: []const u8) bool {
    var index: usize = 0;
    while (index < bytes.len) {
        const codepoint = decodeAt(bytes, index) catch return false;
        if (unicode.isLetterOrNumber(codepoint)) return true;
        index += std.unicode.utf8ByteSequenceLength(bytes[index]) catch return false;
    }
    return false;
}
