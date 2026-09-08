//! Immutable, revision-stamped text snapshot for the UIA provider STA.
//!
//! The UI thread publishes a snapshot after every edit.  The provider STA
//! owns the reference and reads from it without touching Scintilla or any
//! mutable UI storage.  Snapshots are structurally shared and reference-
//! counted; the provider STA holds a strong reference and drops it when a
//! newer revision arrives or the provider shuts down.

const std = @import("std");
const text_units = @import("text_units");

pub const max_live_ranges: usize = 1024;
pub const max_edit_journal: usize = 4096;
pub const max_journal_bytes: usize = 4 * 1024 * 1024;

pub const EditRecord = struct {
    /// Byte offset where the edit starts in the pre-edit document.
    start_byte: usize,
    /// Number of bytes deleted.
    deleted_bytes: usize,
    /// Number of bytes inserted.
    inserted_bytes: usize,
    /// UTF-16 offset where the edit starts.
    start_utf16: usize,
    /// Number of UTF-16 code units deleted.
    deleted_utf16: usize,
    /// Number of UTF-16 code units inserted.
    inserted_utf16: usize,
    /// Revision that produced this edit.
    revision: u64,
};

pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    /// The full document text (UTF-8, never normalized).
    bytes: []const u8,
    /// Pre-computed text-unit index with grapheme/word boundaries and
    /// UTF-8/UTF-16 checkpoints.
    index: text_units.Document,
    /// Monotonically increasing revision from the editor model.
    revision: u64,
    /// Generation counter; incremented when the edit journal wraps.
    generation: u64,
    /// Reference count for structural sharing.
    ref_count: std.atomic.Value(u32),
    /// Visible geometry at snapshot time (screen coordinates).
    first_visible_line: usize = 0,
    visible_line_count: usize = 0,
    /// Caret and selection at snapshot time (byte offsets).
    caret_byte: usize = 0,
    anchor_byte: usize = 0,

    pub fn acquire(self: *Snapshot) void {
        _ = self.ref_count.fetchAdd(1, .monotonic);
    }

    pub fn release(self: *Snapshot) void {
        if (self.ref_count.fetchSub(1, .release) == 1) {
            _ = self.ref_count.load(.acquire);
            self.deinit();
        }
    }

    fn deinit(self: *Snapshot) void {
        const allocator = self.allocator;
        self.index.deinit();
        allocator.free(self.bytes);
        allocator.destroy(self);
    }

    pub fn text(self: *const Snapshot) []const u8 {
        return self.bytes;
    }

    pub fn utf16Length(self: *const Snapshot) usize {
        return self.index.utf16Length();
    }

    pub fn byteLen(self: *const Snapshot) usize {
        return self.bytes.len;
    }
};

/// Create a new snapshot from raw document bytes.  The snapshot is
/// allocated on the heap with an initial reference count of 1.
pub fn create(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    revision: u64,
    generation: u64,
) !*Snapshot {
    const owned = try allocator.dupe(u8, bytes);
    errdefer allocator.free(owned);
    var index = try text_units.Document.init(allocator, owned);
    errdefer index.deinit();
    const snap = try allocator.create(Snapshot);
    snap.* = .{
        .allocator = allocator,
        .bytes = owned,
        .index = index,
        .revision = revision,
        .generation = generation,
        .ref_count = std.atomic.Value(u32).init(1),
    };
    return snap;
}
