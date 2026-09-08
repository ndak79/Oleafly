//! Piece-table editor model with a bounded, locally updated line index.
//!
//! The mutable source stays in `app/editor_buffer.zig`.  This layer adds the
//! editor-facing invariants: edits are UTF-8-boundary safe, line metadata is
//! rebuilt only around the changed region, and immutable text-unit snapshots
//! are created only when a reader explicitly asks for one.

const std = @import("std");
const editor_buffer = @import("editor_buffer");
const text_units = @import("text_units");

pub const max_edit_records: usize = 4_096;
pub const max_journal_bytes: usize = 4 * 1024 * 1024;
const context_lines: usize = 3;

pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    revision: u64,
    bytes: []u8,
    index: text_units.Document,

    pub fn deinit(self: *Snapshot) void {
        self.index.deinit();
        self.allocator.free(self.bytes);
        self.* = undefined;
    }

    pub fn text(self: *const Snapshot) []const u8 {
        return self.bytes;
    }

    pub fn units(self: *const Snapshot) *const text_units.Document {
        return &self.index;
    }
};

pub const LineIndex = struct {
    allocator: std.mem.Allocator,
    starts: std.ArrayList(usize) = .empty,
    sequence: u64 = 0,
    text_length: usize = 0,

    pub fn init(allocator: std.mem.Allocator, bytes: []const u8) !LineIndex {
        var index = LineIndex{
            .allocator = allocator,
            .text_length = bytes.len,
        };
        errdefer index.deinit();
        try index.starts.append(allocator, 0);
        try appendLineStarts(&index.starts, allocator, bytes, 0, true);
        return index;
    }

    pub fn deinit(self: *LineIndex) void {
        self.starts.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn lineCount(self: *const LineIndex) usize {
        return self.starts.items.len;
    }

    pub fn lineStart(self: *const LineIndex, line: usize) !usize {
        if (line >= self.starts.items.len) return error.LineOutOfRange;
        return self.starts.items[line];
    }

    pub fn lineAtByte(self: *const LineIndex, byte: usize) !usize {
        if (byte > self.text_length) return error.InvalidRange;
        var low: usize = 0;
        var high: usize = self.starts.items.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.starts.items[middle] <= byte) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        return low - 1;
    }

    pub fn prepareEdit(
        self: *LineIndex,
        old_buffer: *const editor_buffer.Buffer,
        start: usize,
        deleted_len: usize,
        inserted: []const u8,
    ) !EditPlan {
        const old_length = old_buffer.textLength();
        if (start > old_length or deleted_len > old_length - start) return error.InvalidRange;
        if (!try old_buffer.isByteBoundary(start) or
            !try old_buffer.isByteBoundary(start + deleted_len)) return error.InvalidBoundary;
        if (!std.unicode.utf8ValidateSlice(inserted)) return error.InvalidUtf8;
        if (std.mem.indexOfScalar(u8, inserted, 0) != null) return error.EmbeddedNul;

        const new_length = std.math.sub(usize, old_length, deleted_len) catch return error.LengthOverflow;
        const checked_length = std.math.add(usize, new_length, inserted.len) catch return error.LengthOverflow;
        const start_line = try self.lineAtByte(start);
        const end_line = try self.lineAtByte(start + deleted_len);
        // Keep a few complete lines after the edit in the rescan window. The
        // tail is a byte boundary, not necessarily a stored line start; when
        // the edit reaches the final line, the document end is the boundary.
        const tail_line = @min(self.starts.items.len, end_line + context_lines + 1);
        const rescan_start = self.starts.items[start_line];
        const old_tail = if (tail_line < self.starts.items.len) self.starts.items[tail_line] else old_length;
        const old_after_start = start + deleted_len;
        if (old_tail < old_after_start) return error.InvalidIndex;

        const delta = signedDelta(inserted.len, deleted_len) catch return error.LengthOverflow;
        const new_tail = shiftOffset(old_tail, delta) catch return error.LengthOverflow;
        if (new_tail < rescan_start or new_tail > checked_length) return error.InvalidIndex;

        var region: std.ArrayList(u8) = .empty;
        defer region.deinit(self.allocator);
        try region.ensureTotalCapacity(self.allocator, new_tail - rescan_start);
        const before = try old_buffer.copyRange(self.allocator, rescan_start, start - rescan_start);
        defer self.allocator.free(before);
        try region.appendSlice(self.allocator, before);
        try region.appendSlice(self.allocator, inserted);
        const after = try old_buffer.copyRange(self.allocator, old_after_start, old_tail - old_after_start);
        defer self.allocator.free(after);
        try region.appendSlice(self.allocator, after);
        if (region.items.len != new_tail - rescan_start) return error.InvalidIndex;

        var new_starts: std.ArrayList(usize) = .empty;
        errdefer new_starts.deinit(self.allocator);
        try new_starts.append(self.allocator, rescan_start);
        try appendLineStarts(
            &new_starts,
            self.allocator,
            region.items,
            rescan_start,
            tail_line == self.starts.items.len,
        );

        const remove_count = tail_line - start_line;
        const retained_count = self.starts.items.len - remove_count;
        try self.starts.ensureTotalCapacity(
            self.allocator,
            retained_count + new_starts.items.len,
        );
        return .{
            .replace_at = start_line,
            .remove_count = remove_count,
            .new_length = checked_length,
            .delta = delta,
            .new_starts = new_starts,
        };
    }

    pub fn commitEdit(self: *LineIndex, plan: *EditPlan, sequence: u64) void {
        const old_count = self.starts.items.len;
        if (plan.remove_count != 0) {
            std.mem.copyForwards(
                usize,
                self.starts.items[plan.replace_at..],
                self.starts.items[plan.replace_at + plan.remove_count .. old_count],
            );
            self.starts.items.len -= plan.remove_count;
        }
        for (self.starts.items[plan.replace_at..]) |*offset| {
            offset.* = shiftOffset(offset.*, plan.delta) catch unreachable;
        }

        const retained_count = self.starts.items.len;
        const inserted_count = plan.new_starts.items.len;
        self.starts.items.len = retained_count + inserted_count;
        std.mem.copyBackwards(
            usize,
            self.starts.items[plan.replace_at + inserted_count ..],
            self.starts.items[plan.replace_at..retained_count],
        );
        std.mem.copyForwards(
            usize,
            self.starts.items[plan.replace_at .. plan.replace_at + inserted_count],
            plan.new_starts.items,
        );
        self.text_length = plan.new_length;
        self.sequence = sequence;
    }

    pub fn audit(self: *const LineIndex, bytes: []const u8, sequence: u64) !void {
        if (bytes.len != self.text_length or sequence != self.sequence) return error.IndexDiverged;
        var expected: std.ArrayList(usize) = .empty;
        defer expected.deinit(self.allocator);
        try expected.append(self.allocator, 0);
        try appendLineStarts(&expected, self.allocator, bytes, 0, true);
        if (!std.mem.eql(usize, expected.items, self.starts.items)) return error.IndexDiverged;
    }
};

pub const EditPlan = struct {
    replace_at: usize,
    remove_count: usize,
    new_length: usize,
    delta: i64,
    new_starts: std.ArrayList(usize),

    pub fn deinit(self: *EditPlan, allocator: std.mem.Allocator) void {
        self.new_starts.deinit(allocator);
        self.* = undefined;
    }
};

pub const Model = struct {
    allocator: std.mem.Allocator,
    buffer: editor_buffer.Buffer,
    lines: LineIndex,
    journal_bytes: usize = 0,

    pub fn attach(
        allocator: std.mem.Allocator,
        canonical_path: []const u8,
        disk_bytes: []const u8,
    ) !Model {
        var buffer = try editor_buffer.Buffer.attach(allocator, canonical_path, disk_bytes);
        errdefer buffer.deinit();
        const has_bom = disk_bytes.len >= 3 and std.mem.eql(u8, disk_bytes[0..3], "\xef\xbb\xbf");
        const text_bytes = if (has_bom) disk_bytes[3..] else disk_bytes;
        var lines = try LineIndex.init(allocator, text_bytes);
        errdefer lines.deinit();
        return .{
            .allocator = allocator,
            .buffer = buffer,
            .lines = lines,
        };
    }

    pub fn deinit(self: *Model) void {
        self.lines.deinit();
        self.buffer.deinit();
        self.* = undefined;
    }

    pub fn applyEdit(
        self: *Model,
        sequence: u64,
        start: usize,
        deleted_len: usize,
        inserted: []const u8,
    ) !void {
        if (self.buffer.journal().len >= max_edit_records) return error.JournalLimitExceeded;
        const record_cost = @sizeOf(editor_buffer.EditRecord) + deleted_len + inserted.len;
        if (record_cost > max_journal_bytes -| self.journal_bytes) return error.JournalLimitExceeded;

        var plan = try self.lines.prepareEdit(&self.buffer, start, deleted_len, inserted);
        defer plan.deinit(self.allocator);
        try self.buffer.applyEdit(sequence, start, deleted_len, inserted);
        self.lines.commitEdit(&plan, sequence);
        self.journal_bytes += record_cost;
    }

    pub fn snapshot(self: *const Model, allocator: std.mem.Allocator) !Snapshot {
        const bytes = try self.buffer.materializeText(allocator);
        errdefer allocator.free(bytes);
        var index = try text_units.Document.init(allocator, bytes);
        errdefer index.deinit();
        return .{
            .allocator = allocator,
            .revision = self.buffer.revision(),
            .bytes = bytes,
            .index = index,
        };
    }

    pub fn audit(self: *const Model, allocator: std.mem.Allocator) !void {
        const bytes = try self.buffer.materializeText(allocator);
        defer allocator.free(bytes);
        try self.lines.audit(bytes, self.buffer.revision());
    }

    pub fn revision(self: *const Model) u64 {
        return self.buffer.revision();
    }

    pub fn textLength(self: *const Model) usize {
        return self.buffer.textLength();
    }

    pub fn lineCount(self: *const Model) usize {
        return self.lines.lineCount();
    }

    pub fn lineStart(self: *const Model, line: usize) !usize {
        return self.lines.lineStart(line);
    }

    pub fn currentHash(self: *Model) !editor_buffer.ContentHash {
        return self.buffer.currentHash();
    }
};

fn appendLineStarts(
    starts: *std.ArrayList(usize),
    allocator: std.mem.Allocator,
    bytes: []const u8,
    base: usize,
    include_end: bool,
) !void {
    var index: usize = 0;
    while (index < bytes.len) {
        const next = switch (bytes[index]) {
            '\r' => if (index + 1 < bytes.len and bytes[index + 1] == '\n') index + 2 else index + 1,
            '\n' => index + 1,
            else => {
                index += 1;
                continue;
            },
        };
        const line_start = base + next;
        if (include_end or line_start < base + bytes.len) try starts.append(allocator, line_start);
        index = next;
    }
}

fn signedDelta(inserted_len: usize, deleted_len: usize) !i64 {
    const inserted = std.math.cast(i64, inserted_len) orelse return error.LengthOverflow;
    const deleted = std.math.cast(i64, deleted_len) orelse return error.LengthOverflow;
    return std.math.sub(i64, inserted, deleted) catch return error.LengthOverflow;
}

fn shiftOffset(offset: usize, delta: i64) !usize {
    if (delta >= 0) {
        return std.math.add(usize, offset, std.math.cast(usize, delta) orelse return error.LengthOverflow) catch error.LengthOverflow;
    }
    const magnitude = std.math.cast(usize, -(delta + 1)) orelse return error.LengthOverflow;
    const amount = magnitude + 1;
    return std.math.sub(usize, offset, amount) catch error.LengthOverflow;
}
