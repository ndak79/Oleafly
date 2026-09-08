//! Monotonic tile-section handoff state machine.
//!
//! Lifecycle: created -> writing -> ready -> consuming -> retired
//! - created: UI creates 1 MiB pagefile section, duplicates write-only to worker
//! - writing: worker decodes into section, computes SHA-256 digest
//! - ready: worker unmaps and closes write handle, signals completion
//! - consuming: UI maps read-only, copies to private staging, validates digest
//! - retired: UI permanently closes and retires section

const std = @import("std");
const protocol = @import("protocol.zig");

pub const State = enum {
    created,
    writing,
    ready,
    consuming,
    retired,
};

pub const Error = error{
    InvalidTransition,
    SectionDigestMismatch,
    SectionSizeMismatch,
    SlotOccupied,
    SlotNotFound,
};

pub const TileSlot = struct {
    slot_id: u32,
    generation: u64,
    state: State = .created,
    page_index: u32 = 0,
    expected_digest: [32]u8 = [_]u8{0} ** 32,
    section_handle: ?*anyopaque = null,

    pub fn canTransitionTo(self: *const TileSlot, next: State) bool {
        return switch (self.state) {
            .created => next == .writing or next == .retired,
            .writing => next == .ready or next == .retired,
            .ready => next == .consuming or next == .retired,
            .consuming => next == .retired,
            .retired => false,
        };
    }

    pub fn transition(self: *TileSlot, next: State) Error!void {
        if (!self.canTransitionTo(next)) return error.InvalidTransition;
        self.state = next;
    }
};

pub const HandoffManager = struct {
    slots: [protocol.max_tile_sections]TileSlot = undefined,
    active_count: usize = 0,
    current_generation: u64 = 1,

    pub fn init() HandoffManager {
        var mgr = HandoffManager{};
        for (&mgr.slots, 0..) |*slot, i| {
            slot.* = TileSlot{
                .slot_id = @intCast(i),
                .generation = 0,
                .state = .retired,
            };
        }
        mgr.active_count = 0;
        return mgr;
    }

    pub fn allocateSlot(self: *HandoffManager, page_index: u32) Error!*TileSlot {
        for (&self.slots) |*slot| {
            if (slot.state == .retired) {
                self.current_generation +%= 1;
                slot.* = TileSlot{
                    .slot_id = slot.slot_id,
                    .generation = self.current_generation,
                    .state = .created,
                    .page_index = page_index,
                };
                self.active_count += 1;
                return slot;
            }
        }
        return error.SlotOccupied;
    }

    pub fn findSlot(self: *HandoffManager, slot_id: u32, generation: u64) ?*TileSlot {
        if (slot_id >= protocol.max_tile_sections) return null;
        const slot = &self.slots[slot_id];
        if (slot.generation == generation and slot.state != .retired) return slot;
        return null;
    }

    pub fn retireSlot(self: *HandoffManager, slot_id: u32) void {
        if (slot_id >= protocol.max_tile_sections) return;
        const slot = &self.slots[slot_id];
        if (slot.state != .retired) {
            slot.state = .retired;
            if (self.active_count > 0) self.active_count -= 1;
        }
    }
};
