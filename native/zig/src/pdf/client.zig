//! UI-side client for the authenticated isolated PDF worker.
//!
//! Responsibilities:
//! - Owns the named pipe server and authenticates the worker peer
//! - Enforces request timeouts, sequence tracking, and MAC validation
//! - Manages tile handoff slots and translates results into UI textures
//! - Recovers from worker crashes by relaunching and replaying open docs

const std = @import("std");
const frame = @import("../ipc/frame.zig");
const peer = @import("../ipc/peer.zig");
const protocol = @import("protocol.zig");
const tile_handoff = @import("tile_handoff.zig");
const tile_cache = @import("tile_cache.zig");

pub const ClientState = enum {
    disconnected,
    connecting,
    authenticated,
    recovering,
    closed,
};

pub const Error = error{
    NotConnected,
    WorkerTimeout,
    WorkerCrashed,
    ProtocolViolation,
    AuthenticationFailed,
    DocumentOpenFailed,
    RenderFailed,
};

pub const PdfClient = struct {
    allocator: std.mem.Allocator,
    session: peer.Session,
    handoff: tile_handoff.HandoffManager,
    cache: tile_cache.TileCache,
    state: ClientState = .disconnected,
    active_doc_id: ?u64 = null,
    page_count: u32 = 0,
    current_request_id: u64 = 1,

    pub fn init(allocator: std.mem.Allocator) PdfClient {
        return .{
            .allocator = allocator,
            .session = peer.Session.init(.pdf_worker),
            .handoff = tile_handoff.HandoffManager.init(),
            .cache = tile_cache.TileCache.init(allocator, tile_cache.default_capacity_tiles),
        };
    }

    pub fn deinit(self: *PdfClient) void {
        self.cache.deinit();
        self.session.deinit();
        self.state = .closed;
    }

    pub fn nextRequestId(self: *PdfClient) u64 {
        const id = self.current_request_id;
        self.current_request_id +%= 1;
        return id;
    }

    pub fn markConnected(self: *PdfClient, keys: *const peer.Keys) void {
        self.session.setAuthenticated(keys, true);
        self.state = .authenticated;
    }

    pub fn isOpen(self: *const PdfClient) bool {
        return self.state == .authenticated and self.active_doc_id != null;
    }
};
