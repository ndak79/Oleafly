//! Peer authentication, key derivation, and directional sequence tracking.
//!
//! Derives directional HMAC keys via HKDF-SHA-256:
//! - Salt: SHA-256(protocol_label ++ ui_challenge ++ worker_challenge)
//! - IKM: 256-bit bootstrap master secret
//! - PRK: HKDF-Extract(salt, IKM)
//! - UI-to-Role key: HKDF-Expand(PRK, "ui-to-role:" ++ role_str, 32)
//! - Role-to-UI key: HKDF-Expand(PRK, "role-to-ui:" ++ role_str, 32)
//!
//! Enforces strict non-wrapping sequence numbers per direction.

const std = @import("std");
const crypto = std.crypto;
const Sha256 = crypto.hash.sha2.Sha256;
const HkdfSha256 = crypto.kdf.hkdf.HkdfSha256;
const frame = @import("frame.zig");

pub const protocol_label: []const u8 = "texflow-ipc-v1";
pub const challenge_length: usize = 32;
pub const key_length: usize = 32;

pub const PeerState = enum {
    unauthenticated,
    challenge_sent,
    challenge_received,
    authenticated,
    closed,
};

pub const Error = error{
    InvalidState,
    AuthenticationFailed,
    SequenceReplay,
    SequenceWrap,
    SequenceMismatch,
    ChannelClosed,
};

pub const Direction = enum {
    ui_to_worker,
    worker_to_ui,
};

pub const Keys = struct {
    ui_to_worker: [32]u8,
    worker_to_ui: [32]u8,

    pub fn clear(self: *Keys) void {
        crypto.secureZero(u8, &self.ui_to_worker);
        crypto.secureZero(u8, &self.worker_to_ui);
        self.* = undefined;
    }
};

/// Derive directional HMAC keys from master secret and both challenges.
pub fn deriveKeys(
    master_secret: *const [32]u8,
    ui_challenge: *const [32]u8,
    worker_challenge: *const [32]u8,
    role: frame.Role,
) Keys {
    // 1. Salt = SHA-256(protocol_label || ui_challenge || worker_challenge)
    var salt: [32]u8 = undefined;
    var salt_hasher = Sha256.init(.{});
    salt_hasher.update(protocol_label);
    salt_hasher.update(ui_challenge);
    salt_hasher.update(worker_challenge);
    salt_hasher.final(&salt);

    // 2. PRK = HKDF-Extract(salt, master_secret)
    const prk = HkdfSha256.extract(&salt, master_secret);

    // 3. Expand UI-to-worker key
    var keys: Keys = undefined;
    const role_byte = [1]u8{@intFromEnum(role)};
    const ui_info = "ui-to-worker:" ++ role_byte;
    HkdfSha256.expand(&keys.ui_to_worker, ui_info, prk);

    // 4. Expand worker-to-UI key
    const worker_info = "worker-to-ui:" ++ role_byte;
    HkdfSha256.expand(&keys.worker_to_ui, worker_info, prk);

    return keys;
}

pub const Session = struct {
    role: frame.Role,
    state: PeerState = .unauthenticated,
    send_key: [32]u8 = [_]u8{0} ** 32,
    recv_key: [32]u8 = [_]u8{0} ** 32,
    send_seq: u64 = 0,
    recv_seq: u64 = 0,
    local_challenge: [32]u8 = [_]u8{0} ** 32,
    remote_challenge: [32]u8 = [_]u8{0} ** 32,

    pub fn init(role: frame.Role) Session {
        return .{
            .role = role,
        };
    }

    pub fn deinit(self: *Session) void {
        crypto.secureZero(u8, &self.send_key);
        crypto.secureZero(u8, &self.recv_key);
        crypto.secureZero(u8, &self.local_challenge);
        crypto.secureZero(u8, &self.remote_challenge);
        self.state = .closed;
    }

    /// Complete the handshake with derived directional keys.
    pub fn setAuthenticated(
        self: *Session,
        keys: *const Keys,
        is_ui: bool,
    ) void {
        if (is_ui) {
            self.send_key = keys.ui_to_worker;
            self.recv_key = keys.worker_to_ui;
        } else {
            self.send_key = keys.worker_to_ui;
            self.recv_key = keys.ui_to_worker;
        }
        self.send_seq = 0;
        self.recv_seq = 0;
        self.state = .authenticated;
    }

    /// Allocate the next sequence number for an outgoing frame.
    pub fn nextSendSequence(self: *Session) Error!u64 {
        if (self.state != .authenticated) return error.InvalidState;
        if (self.send_seq == std.math.maxInt(u64)) return error.SequenceWrap;
        const seq = self.send_seq;
        self.send_seq += 1;
        return seq;
    }

    /// Validate and accept the sequence number of an incoming frame.
    pub fn validateRecvSequence(self: *Session, seq: u64) Error!void {
        if (self.state != .authenticated) return error.InvalidState;
        if (seq != self.recv_seq) {
            if (seq < self.recv_seq) return error.SequenceReplay;
            return error.SequenceMismatch;
        }
        if (self.recv_seq == std.math.maxInt(u64)) return error.SequenceWrap;
        self.recv_seq += 1;
    }

    /// Prepare an outgoing header with the current session parameters.
    pub fn prepareHeader(
        self: *Session,
        msg_type: frame.MessageType,
        request_id: u64,
        project_uuid: [16]u8,
        project_revision: u64,
        deadline_qpc: u64,
    ) Error!frame.Header {
        const seq = try self.nextSendSequence();
        return frame.Header{
            .role = @intFromEnum(self.role),
            .msg_type = @intFromEnum(msg_type),
            .channel_seq = seq,
            .request_id = request_id,
            .payload_len = 0, // updated by frame.encode
            .project_uuid = project_uuid,
            .project_revision = project_revision,
            .deadline_qpc = deadline_qpc,
        };
    }

    /// Validate an incoming frame against the session receive key and sequence.
    pub fn validateIncoming(
        self: *Session,
        raw_bytes: []const u8,
        current_qpc: u64,
    ) (frame.Error || Error)!frame.FrameView {
        if (self.state != .authenticated) return error.InvalidState;
        const view = try frame.decode(raw_bytes, &self.recv_key, current_qpc);
        try self.validateRecvSequence(view.header.channel_seq);
        return view;
    }
};
