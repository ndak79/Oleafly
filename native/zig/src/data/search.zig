//! Disposable search database manager, FTS5 schema, and generation staging.
//!
//! Invariants:
//! - Contentless-delete FTS5 table: search_fts(title, abstract, claim_text, evidence_text)
//! - Auxiliary rowid-to-UUID map: rowid INTEGER PRIMARY KEY, entity_uuid BLOB(16) UNIQUE
//! - BM25 ranking: bm25(search_fts, 1.0, 1.0, 1.0, 1.0)
//! - Search database is disposable: rebuilds idempotently from canonical ledger
//! - Staging generation swap: builds in temp dir, verifies manifest, replaces pointer

const std = @import("std");
const crypto = std.crypto;
const Sha256 = crypto.hash.sha2.Sha256;
const ledger = @import("ledger.zig");

pub const max_results_cap: usize = 100;
pub const tokenizer_name: []const u8 = "texflow17";

pub const SearchFieldId = enum(u8) {
    title = 1,
    abstract = 2,
    claim_text = 3,
    evidence_text = 4,
};

pub const SearchHit = struct {
    entity_uuid: [16]u8,
    rank: f64,
    matched_fields: u8,
};

pub const SearchIndex = struct {
    allocator: std.mem.Allocator,
    generation: u64 = 1,
    watermark: u64 = 0,
    doc_count: u32 = 0,
    is_rebuilding: bool = false,

    pub fn init(allocator: std.mem.Allocator) SearchIndex {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SearchIndex) void {
        self.* = undefined;
    }

    /// Compute the commit aggregate hash for a 4-field search projection
    pub fn computeAggregateHash(
        project_uuid: [16]u8,
        entity_uuid: [16]u8,
        entity_revision: u64,
        ledger_seq: u64,
        ledger_hash: [32]u8,
        watermark: u64,
        generation: u64,
        field_digests: [4][32]u8,
    ) [32]u8 {
        var hasher = Sha256.init(.{});
        hasher.update("texflow:search-entity:v1\x00");
        hasher.update(&project_uuid);
        hasher.update(&entity_uuid);

        var rev_buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &rev_buf, entity_revision, .little);
        hasher.update(&rev_buf);

        var seq_buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &seq_buf, ledger_seq, .little);
        hasher.update(&seq_buf);

        hasher.update(&ledger_hash);

        var wm_buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &wm_buf, watermark, .little);
        hasher.update(&wm_buf);

        var gen_buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &gen_buf, generation, .little);
        hasher.update(&gen_buf);

        for (&field_digests) |*d| {
            hasher.update(d);
        }

        var digest: [32]u8 = undefined;
        hasher.final(&digest);
        return digest;
    }
};
