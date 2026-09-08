//! Contract tests for tile handoff slot lifecycle and state transitions.

const std = @import("std");
const tile_handoff = @import("pdf_tile_handoff");
const protocol = @import("pdf_protocol");

const testing = std.testing;

test "tile slot transitions follow monotonic lifecycle" {
    var slot = tile_handoff.TileSlot{
        .slot_id = 0,
        .generation = 1,
        .state = .created,
    };

    // created -> writing -> ready -> consuming -> retired
    try slot.transition(.writing);
    try slot.transition(.ready);
    try slot.transition(.consuming);
    try slot.transition(.retired);
    try testing.expectEqual(tile_handoff.State.retired, slot.state);

    // Cannot transition from retired
    try testing.expectError(error.InvalidTransition, slot.transition(.created));
}

test "tile slot rejects backward transitions" {
    var slot = tile_handoff.TileSlot{
        .slot_id = 0,
        .generation = 1,
        .state = .ready,
    };
    try testing.expectError(error.InvalidTransition, slot.transition(.writing));
    try testing.expectError(error.InvalidTransition, slot.transition(.created));
}

test "handoff manager allocates up to max slots and enforces bounds" {
    var mgr = tile_handoff.HandoffManager.init();

    var slots: [protocol.max_tile_sections]*tile_handoff.TileSlot = undefined;
    for (&slots, 0..) |*s, i| {
        s.* = try mgr.allocateSlot(@intCast(i));
        try testing.expectEqual(tile_handoff.State.created, s.*.state);
    }
    try testing.expectEqual(protocol.max_tile_sections, mgr.active_count);

    // 5th allocation must fail
    try testing.expectError(error.SlotOccupied, mgr.allocateSlot(99));

    // Retire slot 0, then allocate again
    mgr.retireSlot(0);
    try testing.expectEqual(protocol.max_tile_sections - 1, mgr.active_count);

    const new_slot = try mgr.allocateSlot(99);
    try testing.expectEqual(@as(u32, 0), new_slot.slot_id);
}
