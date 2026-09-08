//! Deterministic corpus of scientific entities for full-text search tests.

const std = @import("std");

pub const PaperEntry = struct {
    entity_uuid: [16]u8,
    title: []const u8,
    abstract: []const u8,
    claim_text: []const u8,
    evidence_text: []const u8,
};

pub const sample_papers: [3]PaperEntry = .{
    .{
        .entity_uuid = [_]u8{0x01} ** 16,
        .title = "High-Throughput LaTeX Compilation via Incremental Parsing",
        .abstract = "We present an incremental parsing pipeline that achieves sub-millisecond styling on large scientific manuscripts.",
        .claim_text = "Incremental line indexing reduces lexer re-scan latency by over ninety percent.",
        .evidence_text = "Measurements across 10 MiB documents show consistent 4ms styling slices.",
    },
    .{
        .entity_uuid = [_]u8{0x02} ** 16,
        .title = "Isolated PDF Rendering Architecture for Untrusted Scientific Preprints",
        .abstract = "Rendering arbitrary user-submitted PDF files requires strict OS-level sandboxing to mitigate memory safety risks.",
        .claim_text = "Less-Privileged AppContainer processes cannot access user files or local network interfaces.",
        .evidence_text = "Token audit proves TokenIsLessPrivilegedAppContainer equals 1 with empty capabilities.",
    },
    .{
        .entity_uuid = [_]u8{0x03} ** 16,
        .title = "Deterministic Content-Addressed Verification in Native Scientific Editors",
        .abstract = "Reproducible document pipelines require cryptographic hash chains over canonical events and chunks.",
        .claim_text = "Every state transition is verifiable through an unbroken SHA-256 event hash chain.",
        .evidence_text = "Replay of 10,000 synthetic events yields identical final content digests.",
    },
};

test "search corpus has valid entries" {
    try std.testing.expectEqual(@as(usize, 3), sample_papers.len);
    for (sample_papers) |paper| {
        try std.testing.expect(paper.title.len > 0);
        try std.testing.expect(paper.abstract.len > 0);
    }
}
