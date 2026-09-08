//! Property tests for IPC wire framing, HMAC authentication, and sequence tracking.

const std = @import("std");
const frame = @import("ipc_frame");
const peer = @import("ipc_peer");

const testing = std.testing;

test "frame encode and decode roundtrip" {
    const key = [_]u8{0x42} ** 32;
    var header = frame.Header{
        .role = @intFromEnum(frame.Role.ui),
        .msg_type = @intFromEnum(frame.MessageType.pdf_open_doc),
        .channel_seq = 1,
        .request_id = 100,
        .payload_len = 0,
        .project_uuid = [_]u8{0xAA} ** 16,
        .project_revision = 42,
        .deadline_qpc = 999999999,
    };

    const payload = "sample payload bytes for testing";
    var buf: [512]u8 = undefined;

    const encoded_len = try frame.encode(&header, payload, &key, &buf);
    try testing.expectEqual(frame.header_length + payload.len, encoded_len);

    const view = try frame.decode(buf[0..encoded_len], &key, 1000);
    try testing.expectEqual(frame.magic_value, view.header.magic);
    try testing.expectEqual(header.request_id, view.header.request_id);
    try testing.expectEqualStrings(payload, view.payload);
}

test "frame rejects corrupted magic" {
    const key = [_]u8{0x42} ** 32;
    var header = frame.Header{
        .role = @intFromEnum(frame.Role.ui),
        .msg_type = @intFromEnum(frame.MessageType.heartbeat),
        .channel_seq = 0,
        .request_id = 1,
        .payload_len = 0,
    };
    var buf: [256]u8 = undefined;
    const len = try frame.encode(&header, "test", &key, &buf);

    // Corrupt magic
    buf[0] ^= 0xFF;
    try testing.expectError(error.InvalidMagic, frame.decode(buf[0..len], &key, 0));
}

test "frame rejects tampered payload" {
    const key = [_]u8{0x42} ** 32;
    var header = frame.Header{
        .role = @intFromEnum(frame.Role.ui),
        .msg_type = @intFromEnum(frame.MessageType.heartbeat),
        .channel_seq = 0,
        .request_id = 1,
        .payload_len = 0,
    };
    var buf: [256]u8 = undefined;
    const len = try frame.encode(&header, "good payload", &key, &buf);

    // Tamper with one payload byte
    buf[frame.header_length + 2] ^= 0x01;
    try testing.expectError(error.HmacMismatch, frame.decode(buf[0..len], &key, 0));
}

test "frame rejects truncated buffer" {
    const key = [_]u8{0x42} ** 32;
    var buf: [50]u8 = undefined;
    @memset(&buf, 0);
    try testing.expectError(error.TruncatedHeader, frame.decode(&buf, &key, 0));
}

test "peer key derivation produces distinct directional keys" {
    const master = [_]u8{0x11} ** 32;
    const ui_chal = [_]u8{0x22} ** 32;
    const worker_chal = [_]u8{0x33} ** 32;

    const keys = peer.deriveKeys(&master, &ui_chal, &worker_chal, .pdf_worker);
    try testing.expect(!std.mem.eql(u8, &keys.ui_to_worker, &keys.worker_to_ui));
}

test "peer session sequence validation enforces strict ordering" {
    const master = [_]u8{0x11} ** 32;
    const ui_chal = [_]u8{0x22} ** 32;
    const worker_chal = [_]u8{0x33} ** 32;
    const keys = peer.deriveKeys(&master, &ui_chal, &worker_chal, .pdf_worker);

    var session = peer.Session.init(.pdf_worker);
    defer session.deinit();
    session.setAuthenticated(&keys, false);

    // Expected first recv sequence is 0
    try session.validateRecvSequence(0);
    // Next expected is 1
    try session.validateRecvSequence(1);
    // Replaying 0 should fail
    try testing.expectError(error.SequenceReplay, session.validateRecvSequence(0));
    // Skipping to 5 should fail with SequenceMismatch
    try testing.expectError(error.SequenceMismatch, session.validateRecvSequence(5));
}
