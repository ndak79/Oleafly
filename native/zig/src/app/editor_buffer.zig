const std = @import("std");

pub const ContentHash = [32]u8;

pub const Encoding = enum {
    utf8,
    utf8_bom,
};

pub const NewlinePolicy = enum {
    none,
    lf,
    crlf,
    cr,
    mixed,
};

pub const State = enum {
    clean,
    dirty,
    conflicted,
    missing,
};

pub const EditRecord = struct {
    sequence: u64,
    start: usize,
    deleted_len: usize,
    inserted_len: usize,
};

const PieceSource = enum {
    original,
    added,
};

const Piece = struct {
    source: PieceSource,
    start: usize,
    len: usize,
};

pub const Buffer = struct {
    allocator: std.mem.Allocator,
    path_storage: []u8,
    original: []u8,
    added: std.ArrayList(u8) = .empty,
    pieces: std.ArrayList(Piece) = .empty,
    journal_storage: std.ArrayList(EditRecord) = .empty,
    has_bom: bool,
    newline_policy_storage: NewlinePolicy,
    text_length: usize,
    revision_value: u64 = 0,
    saved_revision_value: u64 = 0,
    saved_hash_value: ContentHash,
    current_hash_value: ?ContentHash,
    state_value: State = .clean,

    pub fn attach(allocator: std.mem.Allocator, canonical_path: []const u8, disk_bytes: []const u8) !Buffer {
        const has_bom = disk_bytes.len >= 3 and std.mem.eql(u8, disk_bytes[0..3], "\xef\xbb\xbf");
        const text_bytes = if (has_bom) disk_bytes[3..] else disk_bytes;
        if (!std.unicode.utf8ValidateSlice(text_bytes)) return error.InvalidUtf8;

        const path_storage = try allocator.dupe(u8, canonical_path);
        errdefer allocator.free(path_storage);
        const original = try allocator.dupe(u8, text_bytes);
        errdefer allocator.free(original);

        var pieces: std.ArrayList(Piece) = .empty;
        errdefer pieces.deinit(allocator);
        if (original.len != 0) {
            try pieces.append(allocator, .{
                .source = .original,
                .start = 0,
                .len = original.len,
            });
        }

        const initial_hash = hash(disk_bytes);
        return .{
            .allocator = allocator,
            .path_storage = path_storage,
            .original = original,
            .pieces = pieces,
            .has_bom = has_bom,
            .newline_policy_storage = detectNewlinePolicy(text_bytes),
            .text_length = text_bytes.len,
            .saved_hash_value = initial_hash,
            .current_hash_value = initial_hash,
        };
    }

    pub fn deinit(self: *Buffer) void {
        self.journal_storage.deinit(self.allocator);
        self.pieces.deinit(self.allocator);
        self.added.deinit(self.allocator);
        self.allocator.free(self.original);
        self.allocator.free(self.path_storage);
        self.* = undefined;
    }

    pub fn applyEdit(
        self: *Buffer,
        sequence: u64,
        start: usize,
        deleted_len: usize,
        inserted: []const u8,
    ) !void {
        if (self.revision_value == std.math.maxInt(u64)) return error.SequenceOverflow;
        const expected_sequence = self.revision_value + 1;
        if (sequence < expected_sequence) return error.StaleSequence;
        if (sequence > expected_sequence) return error.MissingSequence;
        if (start > self.text_length or deleted_len > self.text_length - start) return error.InvalidRange;
        if (!std.unicode.utf8ValidateSlice(inserted)) return error.InvalidUtf8;
        if (deleted_len == 0 and inserted.len == 0) return error.EmptyEdit;
        if (inserted.len > std.math.maxInt(usize) - (self.text_length - deleted_len)) return error.LengthOverflow;

        var next_pieces: std.ArrayList(Piece) = .empty;
        errdefer next_pieces.deinit(self.allocator);

        const old_added_len = self.added.items.len;
        errdefer self.added.items.len = old_added_len;
        if (inserted.len != 0) try self.added.appendSlice(self.allocator, inserted);

        try self.appendLogicalRange(&next_pieces, 0, start);
        if (inserted.len != 0) {
            try appendPiece(&next_pieces, .added, old_added_len, inserted.len, self.allocator);
        }
        try self.appendLogicalRange(&next_pieces, start + deleted_len, self.text_length);
        try self.journal_storage.append(self.allocator, .{
            .sequence = sequence,
            .start = start,
            .deleted_len = deleted_len,
            .inserted_len = inserted.len,
        });

        self.pieces.deinit(self.allocator);
        self.pieces = next_pieces;
        next_pieces = .empty;
        self.text_length = self.text_length - deleted_len + inserted.len;
        self.revision_value = sequence;
        self.current_hash_value = null;
        switch (self.state_value) {
            .clean, .dirty => self.state_value = .dirty,
            .conflicted, .missing => {},
        }
    }

    pub fn materialize(self: *const Buffer, allocator: std.mem.Allocator) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(allocator);
        const bom_len: usize = if (self.has_bom) 3 else 0;
        try output.ensureTotalCapacity(allocator, self.text_length + bom_len);
        if (self.has_bom) try output.appendSlice(allocator, "\xef\xbb\xbf");
        for (self.pieces.items) |piece| {
            const source = self.sourceSlice(piece);
            try output.appendSlice(allocator, source);
        }
        return output.toOwnedSlice(allocator);
    }

    pub fn currentHash(self: *Buffer) !ContentHash {
        if (self.current_hash_value) |known| return known;
        const bytes = try self.materialize(self.allocator);
        defer self.allocator.free(bytes);
        const computed = hash(bytes);
        self.current_hash_value = computed;
        return computed;
    }

    pub fn savedHash(self: *const Buffer) ContentHash {
        return self.saved_hash_value;
    }

    pub fn markSaved(self: *Buffer, expected_hash: ContentHash) !void {
        if (self.state_value == .conflicted or self.state_value == .missing) return error.UnresolvedState;
        const current = try self.currentHash();
        if (!std.mem.eql(u8, &current, &expected_hash)) return error.HashMismatch;
        self.saved_hash_value = current;
        self.saved_revision_value = self.revision_value;
        self.state_value = .clean;
    }

    pub fn markConflicted(self: *Buffer) void {
        self.state_value = .conflicted;
    }

    pub fn markMissing(self: *Buffer) void {
        self.state_value = .missing;
    }

    pub fn path(self: *const Buffer) []const u8 {
        return self.path_storage;
    }

    pub fn revision(self: *const Buffer) u64 {
        return self.revision_value;
    }

    pub fn savedRevision(self: *const Buffer) u64 {
        return self.saved_revision_value;
    }

    pub fn textLength(self: *const Buffer) usize {
        return self.text_length;
    }

    pub fn state(self: *const Buffer) State {
        return self.state_value;
    }

    pub fn encoding(self: *const Buffer) Encoding {
        return if (self.has_bom) .utf8_bom else .utf8;
    }

    pub fn newlinePolicy(self: *const Buffer) NewlinePolicy {
        return self.newline_policy_storage;
    }

    pub fn journal(self: *const Buffer) []const EditRecord {
        return self.journal_storage.items;
    }

    fn appendLogicalRange(self: *const Buffer, output: *std.ArrayList(Piece), range_start: usize, range_end: usize) !void {
        if (range_start >= range_end) return;
        var cursor: usize = 0;
        for (self.pieces.items) |piece| {
            const piece_start = cursor;
            const piece_end = piece_start + piece.len;
            const overlap_start = @max(range_start, piece_start);
            const overlap_end = @min(range_end, piece_end);
            if (overlap_start < overlap_end) {
                try appendPiece(
                    output,
                    piece.source,
                    piece.start + (overlap_start - piece_start),
                    overlap_end - overlap_start,
                    self.allocator,
                );
            }
            cursor = piece_end;
            if (cursor >= range_end) break;
        }
    }

    fn sourceSlice(self: *const Buffer, piece: Piece) []const u8 {
        const source = switch (piece.source) {
            .original => self.original,
            .added => self.added.items,
        };
        return source[piece.start .. piece.start + piece.len];
    }
};

fn appendPiece(
    output: *std.ArrayList(Piece),
    source: PieceSource,
    start: usize,
    len: usize,
    allocator: std.mem.Allocator,
) !void {
    if (len == 0) return;
    if (output.items.len != 0) {
        const last_index = output.items.len - 1;
        const last = &output.items[last_index];
        if (last.source == source and last.start + last.len == start) {
            last.len += len;
            return;
        }
    }
    try output.append(allocator, .{ .source = source, .start = start, .len = len });
}

fn hash(bytes: []const u8) ContentHash {
    var digest: ContentHash = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

fn detectNewlinePolicy(bytes: []const u8) NewlinePolicy {
    var saw_lf = false;
    var saw_crlf = false;
    var saw_cr = false;
    var index: usize = 0;
    while (index < bytes.len) {
        switch (bytes[index]) {
            '\r' => {
                if (index + 1 < bytes.len and bytes[index + 1] == '\n') {
                    saw_crlf = true;
                    index += 2;
                } else {
                    saw_cr = true;
                    index += 1;
                }
            },
            '\n' => {
                saw_lf = true;
                index += 1;
            },
            else => index += 1,
        }
    }

    const kinds = @as(u8, @intFromBool(saw_lf)) +
        @as(u8, @intFromBool(saw_crlf)) +
        @as(u8, @intFromBool(saw_cr));
    if (kinds == 0) return .none;
    if (kinds > 1) return .mixed;
    if (saw_crlf) return .crlf;
    if (saw_cr) return .cr;
    return .lf;
}
