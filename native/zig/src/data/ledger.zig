//! Canonical project-scoped event ledger and chunked immutable storage.
//!
//! Invariants:
//! - Sequence starts at 1, monotonically increasing per project
//! - Genesis event has all-zero 32-byte previous_hash
//! - Event hash: SHA-256("texflow:event:v1\0" || envelope || payload)
//! - Max inline canonical payload: 1 MiB (1,048,576 bytes)
//! - Large fields chunked in immutable rows of <=256 KiB (262,144 bytes)
//! - Exactly 4 typed field references per entity: title, abstract, claim, evidence

const std = @import("std");
const crypto = std.crypto;
const Sha256 = crypto.hash.sha2.Sha256;

pub const event_hash_prefix: []const u8 = "texflow:event:v1\x00";
pub const max_chunk_size: usize = 256 * 1024; // 256 KiB
pub const max_field_size: usize = 1024 * 1024; // 1 MiB
pub const max_entity_size: usize = 4 * 1024 * 1024; // 4 MiB
pub const max_payload_size: usize = 1024 * 1024; // 1 MiB

pub const empty_sha256 = [_]u8{
    0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
    0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
    0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
    0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
};

pub const FieldId = enum(u8) {
    title = 1,
    abstract = 2,
    claim_text = 3,
    evidence_text = 4,
};

pub const FieldReference = struct {
    field_id: FieldId,
    is_null: bool,
    byte_length: u32,
    content_sha256: [32]u8,

    pub fn initNull(field_id: FieldId) FieldReference {
        return .{
            .field_id = field_id,
            .is_null = true,
            .byte_length = 0,
            .content_sha256 = [_]u8{0} ** 32,
        };
    }

    pub fn initEmpty(field_id: FieldId) FieldReference {
        return .{
            .field_id = field_id,
            .is_null = false,
            .byte_length = 0,
            .content_sha256 = empty_sha256,
        };
    }

    pub fn initWithContent(field_id: FieldId, content: []const u8) FieldReference {
        var digest: [32]u8 = undefined;
        Sha256.hash(content, &digest, .{});
        return .{
            .field_id = field_id,
            .is_null = false,
            .byte_length = @intCast(content.len),
            .content_sha256 = digest,
        };
    }

    pub fn chunkCount(self: FieldReference) usize {
        if (self.is_null or self.byte_length == 0) return 0;
        return (self.byte_length + max_chunk_size - 1) / max_chunk_size;
    }
};

pub const Event = struct {
    project_uuid: [16]u8,
    sequence: u64,
    event_uuid: [16]u8,
    kind: u16,
    schema_version: u16 = 1,
    recorded_utc_ms: i64,
    previous_hash: [32]u8,
    payload_length: u32,
    canonical_payload: []const u8,

    pub fn computeHash(self: *const Event) [32]u8 {
        var hasher = Sha256.init(.{});
        hasher.update(event_hash_prefix);
        hasher.update(&self.project_uuid);

        var seq_buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &seq_buf, self.sequence, .little);
        hasher.update(&seq_buf);

        hasher.update(&self.event_uuid);

        var kind_buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &kind_buf, self.kind, .little);
        hasher.update(&kind_buf);

        var ver_buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &ver_buf, self.schema_version, .little);
        hasher.update(&ver_buf);

        var time_buf: [8]u8 = undefined;
        std.mem.writeInt(i64, &time_buf, self.recorded_utc_ms, .little);
        hasher.update(&time_buf);

        hasher.update(&self.previous_hash);

        var len_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &len_buf, self.payload_length, .little);
        hasher.update(&len_buf);

        hasher.update(self.canonical_payload);

        var digest: [32]u8 = undefined;
        hasher.final(&digest);
        return digest;
    }
};

pub const Ledger = struct {
    project_uuid: [16]u8,
    current_sequence: u64 = 0,
    last_event_hash: [32]u8 = [_]u8{0} ** 32,

    pub fn init(project_uuid: [16]u8) Ledger {
        return .{
            .project_uuid = project_uuid,
        };
    }

    pub fn appendEvent(
        self: *Ledger,
        event_uuid: [16]u8,
        kind: u16,
        recorded_utc_ms: i64,
        canonical_payload: []const u8,
    ) !Event {
        if (canonical_payload.len > max_payload_size) return error.PayloadTooLarge;

        const next_seq = self.current_sequence + 1;
        const prev_hash = if (self.current_sequence == 0)
            [_]u8{0} ** 32
        else
            self.last_event_hash;

        const event = Event{
            .project_uuid = self.project_uuid,
            .sequence = next_seq,
            .event_uuid = event_uuid,
            .kind = kind,
            .schema_version = 1,
            .recorded_utc_ms = recorded_utc_ms,
            .previous_hash = prev_hash,
            .payload_length = @intCast(canonical_payload.len),
            .canonical_payload = canonical_payload,
        };

        self.last_event_hash = event.computeHash();
        self.current_sequence = next_seq;
        return event;
    }
};
