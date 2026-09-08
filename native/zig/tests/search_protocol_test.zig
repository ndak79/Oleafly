//! Contract tests for search projection serialization and commit aggregate hashes.

const std = @import("std");
const search = @import("data_search");

const testing = std.testing;

test "search aggregate hash calculation binds all entity fields" {
    const project_uuid = [_]u8{0x11} ** 16;
    const entity_uuid = [_]u8{0x22} ** 16;
    const entity_revision: u64 = 5;
    const ledger_seq: u64 = 100;
    const ledger_hash = [_]u8{0x33} ** 32;
    const watermark: u64 = 100;
    const generation: u64 = 2;

    const field_digests: [4][32]u8 = .{
        [_]u8{0x01} ** 32,
        [_]u8{0x02} ** 32,
        [_]u8{0x03} ** 32,
        [_]u8{0x04} ** 32,
    };

    const hash1 = search.SearchIndex.computeAggregateHash(
        project_uuid,
        entity_uuid,
        entity_revision,
        ledger_seq,
        ledger_hash,
        watermark,
        generation,
        field_digests,
    );

    // Recomputing with same parameters must be identical
    const hash2 = search.SearchIndex.computeAggregateHash(
        project_uuid,
        entity_uuid,
        entity_revision,
        ledger_seq,
        ledger_hash,
        watermark,
        generation,
        field_digests,
    );
    try testing.expectEqualSlices(u8, &hash1, &hash2);

    // Altering one field digest must change the aggregate hash
    var altered_digests = field_digests;
    altered_digests[0][0] ^= 0xFF;
    const hash3 = search.SearchIndex.computeAggregateHash(
        project_uuid,
        entity_uuid,
        entity_revision,
        ledger_seq,
        ledger_hash,
        watermark,
        generation,
        altered_digests,
    );
    try testing.expect(!std.mem.eql(u8, &hash1, &hash3));
}
