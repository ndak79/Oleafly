//! Benchmark workload specifications for the T0.2 campaign.
//!
//! Defines named workloads:
//! - W0-smoke: fast lifecycle startup and shutdown
//! - W1-typing: interactive Latin and Vietnamese keystroke sequence
//! - W2-large-editor: 10 MiB LaTeX document open, styling convergence, and scroll
//! - W3-scroll: rapid viewport paging and scroll bar dragging
//! - W4-undo: 1,000 continuous edits followed by full undo stack reversal
//! - W5-pdf: PDF document open, 512x512 tile rendering, and page change
//! - W6-search: 100-result search query, BM25 ranking, and index rebuild

const std = @import("std");

pub const WorkloadId = enum {
    w0_smoke,
    w1_typing,
    w2_large_editor,
    w3_scroll,
    w4_undo,
    w5_pdf,
    w6_search,

    pub fn label(self: WorkloadId) []const u8 {
        return switch (self) {
            .w0_smoke => "W0-smoke",
            .w1_typing => "W1-typing",
            .w2_large_editor => "W2-large-editor",
            .w3_scroll => "W3-scroll",
            .w4_undo => "W4-undo",
            .w5_pdf => "W5-pdf",
            .w6_search => "W6-search",
        };
    }

    pub fn targetDurationMs(self: WorkloadId) u64 {
        return switch (self) {
            .w0_smoke => 200,
            .w1_typing => 1000,
            .w2_large_editor => 2000,
            .w3_scroll => 1500,
            .w4_undo => 1000,
            .w5_pdf => 1000,
            .w6_search => 500,
        };
    }
};

test "workload labels and targets are valid" {
    inline for (@typeInfo(WorkloadId).@"enum".fields) |field| {
        const id: WorkloadId = @enumFromInt(field.value);
        try std.testing.expect(id.label().len > 0);
        try std.testing.expect(id.targetDurationMs() > 0);
    }
}
