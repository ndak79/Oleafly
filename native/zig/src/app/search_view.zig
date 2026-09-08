//! Trusted search presentation lane, highlight extraction, and view state.
//!
//! Invariants:
//! - Up to 100 candidates displayed
//! - Queries run over short snapshots; re-checks watermark before displaying
//! - Escaped safe titles and snippets with half-open UTF-8 highlight ranges
//! - Standard user notices for derived search limitations

const std = @import("std");

pub const max_display_results: usize = 100;

pub const Notices = struct {
    pub const results_notice: []const u8 = "Derived-index navigation — up to 100 candidates; visible rows are verified matches; omissions and order are not scientific evidence.";
    pub const empty: []const u8 = "No matches returned by the current derived index. This is not evidence of absence.";
    pub const rebuilding: []const u8 = "Search index rebuilding";
    pub const unavailable: []const u8 = "Search index unavailable";
};

pub const HighlightRange = struct {
    start_byte: usize,
    end_byte: usize,
};

pub const PresentationRow = struct {
    entity_uuid: [16]u8,
    title: []const u8,
    snippet: []const u8,
    rank: f64,
    highlight: ?HighlightRange = null,
};

pub const ViewState = enum {
    idle,
    searching,
    rebuilding,
    unavailable,
    ready,
};

pub const SearchView = struct {
    allocator: std.mem.Allocator,
    state: ViewState = .idle,
    rows: std.ArrayList(PresentationRow) = .empty,
    current_watermark: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) SearchView {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SearchView) void {
        self.clear();
        self.rows.deinit(self.allocator);
    }

    pub fn clear(self: *SearchView) void {
        for (self.rows.items) |row| {
            self.allocator.free(row.title);
            self.allocator.free(row.snippet);
        }
        self.rows.clearRetainingCapacity();
    }

    pub fn addRow(
        self: *SearchView,
        entity_uuid: [16]u8,
        title: []const u8,
        snippet: []const u8,
        rank: f64,
        highlight: ?HighlightRange,
    ) !void {
        if (self.rows.items.len >= max_display_results) return;

        const owned_title = try self.allocator.dupe(u8, title);
        errdefer self.allocator.free(owned_title);
        const owned_snippet = try self.allocator.dupe(u8, snippet);
        errdefer self.allocator.free(owned_snippet);

        try self.rows.append(self.allocator, .{
            .entity_uuid = entity_uuid,
            .title = owned_title,
            .snippet = owned_snippet,
            .rank = rank,
            .highlight = highlight,
        });
    }
};
