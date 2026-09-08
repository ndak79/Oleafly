//! ITextRangeProvider-compatible range with revision-stamped anchors.
//!
//! Each range stores its creation generation/revision and two typed
//! anchors (byte offsets into the snapshot).  Anchors are transformed
//! deterministically on edits: positions before an edit stay fixed,
//! positions after move by the delta, and deleted interior anchors
//! collapse to the replacement boundary.
//!
//! If the generation changed or the transform is inconsistent, the range
//! is invalidated and subsequent operations return `Stale`.

const std = @import("std");
const snapshot_mod = @import("uia_snapshot");

pub const Affinity = enum { before, after };

pub const Anchor = struct {
    byte: usize,
    utf16: usize,
    affinity: Affinity,
};

pub const RangeError = error{
    Stale,
    CapExceeded,
    InvalidOffset,
};

pub const Range = struct {
    id: u32,
    start: Anchor,
    end: Anchor,
    creation_revision: u64,
    creation_generation: u64,
    valid: bool = true,
    degenerate: bool = false,

    pub fn init(
        id: u32,
        start_byte: usize,
        start_utf16: usize,
        end_byte: usize,
        end_utf16: usize,
        revision: u64,
        generation: u64,
    ) Range {
        const is_degenerate = start_byte == end_byte;
        return .{
            .id = id,
            .start = .{
                .byte = start_byte,
                .utf16 = start_utf16,
                .affinity = if (is_degenerate) .after else .before,
            },
            .end = .{
                .byte = end_byte,
                .utf16 = end_utf16,
                .affinity = .after,
            },
            .creation_revision = revision,
            .creation_generation = generation,
            .degenerate = is_degenerate,
        };
    }

    /// Transform this range's anchors against a single edit.
    pub fn applyEdit(self: *Range, edit: snapshot_mod.EditRecord, generation: u64) void {
        if (!self.valid) return;
        if (generation != self.creation_generation) {
            self.valid = false;
            return;
        }
        self.start = transformAnchor(self.start, edit);
        self.end = transformAnchor(self.end, edit);
        if (self.start.byte > self.end.byte) {
            self.end = self.start;
        }
        self.degenerate = self.start.byte == self.end.byte;
        self.creation_revision = edit.revision;
    }

    /// Invalidate this range (e.g. journal eviction or shutdown).
    pub fn invalidate(self: *Range) void {
        self.valid = false;
    }

    /// Check validity against a snapshot.
    pub fn checkValid(self: *const Range, snap: *const snapshot_mod.Snapshot) RangeError!void {
        if (!self.valid) return error.Stale;
        if (self.creation_generation != snap.generation) return error.Stale;
        if (self.start.byte > snap.byteLen() or self.end.byte > snap.byteLen()) return error.Stale;
    }

    pub fn getText(self: *const Range, snap: *const snapshot_mod.Snapshot, max_len: usize) RangeError![]const u8 {
        try self.checkValid(snap);
        const start = self.start.byte;
        const end = self.end.byte;
        if (start >= end) return snap.text()[0..0];
        const len = end - start;
        const capped = @min(len, max_len);
        return snap.text()[start .. start + capped];
    }

    pub fn clone(self: *const Range, new_id: u32) Range {
        var copy = self.*;
        copy.id = new_id;
        return copy;
    }

    pub fn compare(self: *const Range, other: *const Range) i32 {
        if (self.start.byte < other.start.byte) return -1;
        if (self.start.byte > other.start.byte) return 1;
        if (self.end.byte < other.end.byte) return -1;
        if (self.end.byte > other.end.byte) return 1;
        return 0;
    }
};

fn transformAnchor(anchor: Anchor, edit: snapshot_mod.EditRecord) Anchor {
    const edit_end = edit.start_byte + edit.deleted_bytes;

    if (anchor.byte < edit.start_byte) return anchor;
    if (anchor.byte > edit_end) {
        const byte_delta = edit.inserted_bytes -| edit.deleted_bytes;
        const utf16_delta = edit.inserted_utf16 -| edit.deleted_utf16;
        if (edit.inserted_bytes >= edit.deleted_bytes) {
            return .{
                .byte = anchor.byte + byte_delta,
                .utf16 = anchor.utf16 + utf16_delta,
                .affinity = anchor.affinity,
            };
        }
        const shrink_bytes = edit.deleted_bytes - edit.inserted_bytes;
        const shrink_utf16 = edit.deleted_utf16 - edit.inserted_utf16;
        return .{
            .byte = anchor.byte -| shrink_bytes,
            .utf16 = anchor.utf16 -| shrink_utf16,
            .affinity = anchor.affinity,
        };
    }
    // Anchor is inside the deleted region: collapse to boundary.
    return switch (anchor.affinity) {
        .before => .{
            .byte = edit.start_byte,
            .utf16 = edit.start_utf16,
            .affinity = .before,
        },
        .after => .{
            .byte = edit.start_byte + edit.inserted_bytes,
            .utf16 = edit.start_utf16 + edit.inserted_utf16,
            .affinity = .after,
        },
    };
}

/// Pool of live ranges with a hard cap.
pub const RangePool = struct {
    allocator: std.mem.Allocator,
    ranges: std.ArrayList(Range) = .empty,
    next_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) RangePool {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RangePool) void {
        self.ranges.deinit(self.allocator);
    }

    pub fn count(self: *const RangePool) usize {
        return self.ranges.items.len;
    }

    pub fn create(
        self: *RangePool,
        start_byte: usize,
        start_utf16: usize,
        end_byte: usize,
        end_utf16: usize,
        revision: u64,
        generation: u64,
    ) RangeError!*Range {
        if (self.ranges.items.len >= snapshot_mod.max_live_ranges) return error.CapExceeded;
        const id = self.next_id;
        self.next_id +%= 1;
        const range = Range.init(id, start_byte, start_utf16, end_byte, end_utf16, revision, generation);
        self.ranges.append(self.allocator, range) catch return error.CapExceeded;
        return &self.ranges.items[self.ranges.items.len - 1];
    }

    pub fn cloneRange(self: *RangePool, source: *const Range) RangeError!*Range {
        if (self.ranges.items.len >= snapshot_mod.max_live_ranges) return error.CapExceeded;
        const id = self.next_id;
        self.next_id +%= 1;
        const copy = source.clone(id);
        self.ranges.append(self.allocator, copy) catch return error.CapExceeded;
        return &self.ranges.items[self.ranges.items.len - 1];
    }

    pub fn removeById(self: *RangePool, id: u32) bool {
        for (self.ranges.items, 0..) |r, i| {
            if (r.id == id) {
                _ = self.ranges.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn applyEdit(self: *RangePool, edit: snapshot_mod.EditRecord, generation: u64) void {
        for (self.ranges.items) |*r| {
            r.applyEdit(edit, generation);
        }
    }

    pub fn invalidateAll(self: *RangePool) void {
        for (self.ranges.items) |*r| {
            r.invalidate();
        }
    }
};
