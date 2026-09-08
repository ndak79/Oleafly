//! Fixed-width wire framing and cryptographic envelope for TExFlow IPC.
//!
//! All fields are little-endian. Header layout:
//! - magic (4 bytes): 'TExF' (0x54457846)
//! - protocol_major (2 bytes): 1
//! - protocol_minor (2 bytes): 0
//! - role (1 byte): ui = 0, pdf_worker = 1, science_worker = 2
//! - reserved0 (1 byte): 0
//! - msg_type (2 bytes): typed enum
//! - flags (2 bytes): bitmask
//! - channel_seq (8 bytes): monotonically increasing per direction, never wraps
//! - request_id (8 bytes): caller correlation ID
//! - payload_len (4 bytes): length of payload following the header
//! - reserved1 (4 bytes): alignment padding
//! - project_uuid (16 bytes): bound project identifier
//! - project_revision (8 bytes): bound project edit revision
//! - deadline_qpc (8 bytes): absolute QPC deadline (0 only for handshake/shutdown)
//! - hmac (32 bytes): full HMAC-SHA-256 over header (with hmac=0) + payload

const std = @import("std");
const crypto = std.crypto;
const HmacSha256 = crypto.auth.hmac.sha2.HmacSha256;

pub const magic_value: u32 = 0x54457846; // 'TExF'
pub const current_major: u16 = 1;
pub const current_minor: u16 = 0;
pub const max_payload_size: u32 = 4 * 1024 * 1024; // 4 MiB

pub const Role = enum(u8) {
    ui = 0,
    pdf_worker = 1,
    science_worker = 2,
};

pub const MessageType = enum(u16) {
    // Handshake (0x0001 .. 0x000F)
    handshake_challenge = 1,
    handshake_response = 2,
    handshake_confirm = 3,

    // Control (0x0010 .. 0x001F)
    heartbeat = 16,
    shutdown = 17,
    quarantine = 18,

    // PDF (0x0020 .. 0x004F)
    pdf_open_doc = 32,
    pdf_doc_opened = 33,
    pdf_render_tile = 34,
    pdf_tile_ready = 35,
    pdf_get_text = 36,
    pdf_text_result = 37,
    pdf_cancel = 38,
    pdf_error = 39,

    // Science / Search (0x0050 .. 0x007F)
    science_index = 80,
    science_search = 81,
    science_search_result = 82,
    science_error = 83,
};

pub const Flags = struct {
    pub const none: u16 = 0;
    pub const handshake: u16 = 1 << 0;
    pub const compressed: u16 = 1 << 1;
    pub const canceled: u16 = 1 << 2;
    pub const end_of_stream: u16 = 1 << 3;
};

pub const Header = extern struct {
    magic: u32 = magic_value,
    protocol_major: u16 = current_major,
    protocol_minor: u16 = current_minor,
    role: u8,
    reserved0: u8 = 0,
    msg_type: u16,
    flags: u16 = Flags.none,
    channel_seq: u64,
    request_id: u64,
    payload_len: u32,
    reserved1: u32 = 0,
    project_uuid: [16]u8 = [_]u8{0} ** 16,
    project_revision: u64 = 0,
    deadline_qpc: u64 = 0,
    hmac: [32]u8 = [_]u8{0} ** 32,

    pub fn isHandshakeOrControl(self: *const Header) bool {
        return switch (@as(MessageType, @enumFromInt(self.msg_type))) {
            .handshake_challenge, .handshake_response, .handshake_confirm, .heartbeat, .shutdown, .quarantine => true,
            else => false,
        };
    }
};

pub const header_length: usize = @sizeOf(Header);

comptime {
    std.debug.assert(@sizeOf(Header) == 104);
}

pub const Error = error{
    BufferTooSmall,
    InvalidMagic,
    UnsupportedVersion,
    InvalidRole,
    InvalidMessageType,
    PayloadTooLarge,
    HmacMismatch,
    DeadlineExpired,
    SequenceOutOfOrder,
    TruncatedHeader,
    TruncatedPayload,
    MissingProjectBinding,
};

pub const FrameView = struct {
    header: Header,
    payload: []const u8,
};

/// Compute HMAC-SHA-256 over the canonical header (with its hmac field zeroed)
/// followed by the exact payload bytes.
pub fn computeHmac(header: *const Header, payload: []const u8, key: *const [32]u8) [32]u8 {
    var zeroed_header = header.*;
    @memset(&zeroed_header.hmac, 0);
    const header_bytes = std.mem.asBytes(&zeroed_header);

    var mac: [32]u8 = undefined;
    var ctx = HmacSha256.init(key);
    ctx.update(header_bytes);
    ctx.update(payload);
    ctx.final(&mac);
    return mac;
}

/// Encode a message frame into the provided destination buffer.
/// Returns the total number of bytes written (header_length + payload.len).
pub fn encode(
    header: *Header,
    payload: []const u8,
    key: *const [32]u8,
    dest: []u8,
) Error!usize {
    if (payload.len > max_payload_size) return error.PayloadTooLarge;
    const total_len = header_length + payload.len;
    if (dest.len < total_len) return error.BufferTooSmall;

    header.magic = magic_value;
    header.protocol_major = current_major;
    header.protocol_minor = current_minor;
    header.payload_len = @intCast(payload.len);
    header.hmac = computeHmac(header, payload, key);

    const header_bytes = std.mem.asBytes(header);
    @memcpy(dest[0..header_length], header_bytes);
    @memcpy(dest[header_length..total_len], payload);
    return total_len;
}

/// Decode and validate a message frame from the buffer.
/// If key is provided, the HMAC is verified using constant-time comparison.
pub fn decode(
    buffer: []const u8,
    key: ?*const [32]u8,
    current_qpc: u64,
) Error!FrameView {
    if (buffer.len < header_length) return error.TruncatedHeader;

    var header: Header = undefined;
    @memcpy(std.mem.asBytes(&header), buffer[0..header_length]);

    if (header.magic != magic_value) return error.InvalidMagic;
    if (header.protocol_major != current_major) return error.UnsupportedVersion;
    if (header.payload_len > max_payload_size) return error.PayloadTooLarge;

    const total_len = header_length + header.payload_len;
    if (buffer.len < total_len) return error.TruncatedPayload;

    const payload = buffer[header_length..total_len];

    // Validate HMAC if key is available
    if (key) |k| {
        const expected_hmac = computeHmac(&header, payload, k);
        if (!crypto.timing_safe.eql([32]u8, header.hmac, expected_hmac)) {
            return error.HmacMismatch;
        }
    }

    // Non-handshake/control messages must have valid project binding and unexpired deadline
    if (!header.isHandshakeOrControl()) {
        var is_zero_uuid = true;
        for (header.project_uuid) |b| {
            if (b != 0) {
                is_zero_uuid = false;
                break;
            }
        }
        if (is_zero_uuid) return error.MissingProjectBinding;
        if (current_qpc > 0 and header.deadline_qpc > 0 and current_qpc > header.deadline_qpc) {
            return error.DeadlineExpired;
        }
    }

    return FrameView{
        .header = header,
        .payload = payload,
    };
}
