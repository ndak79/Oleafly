const std = @import("std");
const render = @import("app_live_render");

test "auto scheduling adapts inside the inclusive 220..750ms window" {
    var scheduler = render.Scheduler.init(.auto);
    try std.testing.expectEqual(@as(u64, 220), scheduler.delay_ms);
    _ = scheduler.edit(1, 0, .{ .edit_interval_ms = 40, .job_cost_ms = 900, .was_cancelled = true });
    try std.testing.expect(scheduler.delay_ms >= render.min_auto_delay_ms);
    try std.testing.expect(scheduler.delay_ms <= render.max_auto_delay_ms);
    _ = scheduler.edit(2, 40, .{ .edit_interval_ms = 900, .job_cost_ms = 20, .was_cancelled = false });
    try std.testing.expect(scheduler.delay_ms >= render.min_auto_delay_ms);
    try std.testing.expect(scheduler.delay_ms <= render.max_auto_delay_ms);
}

test "event and deadline driven scheduler exposes only the next deadline" {
    var scheduler = render.Scheduler.init(.auto);
    try std.testing.expectEqual(@as(?u64, null), scheduler.next_deadline());
    _ = scheduler.edit(7, 1_000, .{});
    try std.testing.expectEqual(@as(?u64, 1_220), scheduler.next_deadline());
    try std.testing.expectEqual(@as(?render.Request, null), scheduler.take_due(1_219));
    const request = scheduler.take_due(1_220) orelse return error.MissingRequest;
    try std.testing.expectEqual(@as(u64, 7), request.revision);
    try std.testing.expectEqual(@as(?u64, null), scheduler.next_deadline());
}

test "superseded work receives at most 75ms grace and only latest completion is current" {
    var scheduler = render.Scheduler.init(.auto);
    _ = scheduler.edit(1, 0, .{});
    _ = scheduler.take_due(220) orelse return error.MissingRequest;
    _ = scheduler.mark_started(1, 220);
    const decision = scheduler.edit(2, 300, .{});
    try std.testing.expectEqual(@as(?u64, 1), decision.cancel_revision);
    try std.testing.expectEqual(@as(?u64, 375), decision.cancel_deadline_ms);
    const repeated = scheduler.edit(3, 350, .{});
    try std.testing.expectEqual(@as(?u64, null), repeated.cancel_revision);
    try std.testing.expectEqual(@as(?u64, 375), repeated.cancel_deadline_ms);
    try std.testing.expectEqual(@as(u32, 1), scheduler.cancellation_count);
    try std.testing.expectEqual(@as(?u64, 375), scheduler.next_deadline());
    const cancellation = scheduler.take_cancellation_due(375) orelse return error.MissingCancellation;
    try std.testing.expectEqual(@as(u64, 1), cancellation.revision);
    try std.testing.expectEqual(@as(u64, 375), cancellation.due_ms);
    try std.testing.expectEqual(render.CompletionResult.stale, scheduler.complete(.{ .revision = 1, .artifact_id = 101, .succeeded = true }));
    try std.testing.expectEqual(@as(?u64, null), scheduler.active_revision);
    try std.testing.expectEqual(@as(?u64, 570), scheduler.next_deadline());
    _ = scheduler.take_due(570) orelse return error.MissingRequest;
    try std.testing.expect(scheduler.mark_started(3, 570));
    try std.testing.expectEqual(render.CompletionResult.accepted, scheduler.complete(.{ .revision = 3, .artifact_id = 303, .succeeded = true }));
    try std.testing.expectEqual(@as(?u64, 303), scheduler.current_artifact_id());
}

test "current artifact is invalidated by edits while last good remains available" {
    var scheduler = render.Scheduler.init(.auto);
    _ = scheduler.edit(1, 0, .{});
    _ = scheduler.take_due(220) orelse return error.MissingRequest;
    try std.testing.expect(scheduler.mark_started(1, 220));
    try std.testing.expectEqual(render.CompletionResult.accepted, scheduler.complete(.{ .revision = 1, .artifact_id = 101, .succeeded = true }));
    try std.testing.expectEqual(@as(?u64, 101), scheduler.current_artifact_id());
    try std.testing.expectEqual(@as(?u64, 101), scheduler.last_good_artifact_id());

    _ = scheduler.edit(2, 300, .{});
    try std.testing.expectEqual(@as(?u64, null), scheduler.current_artifact_id());
    try std.testing.expectEqual(@as(?u64, 101), scheduler.last_good_artifact_id());
    try std.testing.expectEqual(render.CompletionResult.not_started, scheduler.complete(.{ .revision = 2, .artifact_id = 202, .succeeded = true }));
    try std.testing.expectEqual(@as(?u64, null), scheduler.current_artifact_id());
    _ = scheduler.take_due(520) orelse return error.MissingRequest;
    try std.testing.expect(scheduler.mark_started(2, 520));
    try std.testing.expectEqual(render.CompletionResult.accepted, scheduler.complete(.{ .revision = 2, .artifact_id = 202, .succeeded = true }));
    try std.testing.expectEqual(@as(?u64, 202), scheduler.current_artifact_id());
}

test "a superseded worker cannot be overwritten before cancellation is acknowledged" {
    var scheduler = render.Scheduler.init(.manual);
    _ = scheduler.edit(1, 10, .{});
    try std.testing.expect(scheduler.mark_started(1, 10));
    _ = scheduler.edit(2, 20, .{});
    _ = scheduler.request_manual(2, 20) orelse return error.MissingRequest;
    try std.testing.expectEqual(@as(?render.Request, null), scheduler.take_due(20));
    try std.testing.expect(!scheduler.mark_started(2, 20));
    try std.testing.expectEqual(@as(?u64, 1), scheduler.active_revision);
    try std.testing.expectEqual(@as(?u64, 95), scheduler.cancel_deadline_ms);
    try std.testing.expectEqual(@as(?u64, 95), scheduler.next_deadline());
    _ = scheduler.take_cancellation_due(95) orelse return error.MissingCancellation;
    try std.testing.expect(scheduler.acknowledge_cancelled(1));
    try std.testing.expectEqual(@as(?u64, null), scheduler.active_revision);
    try std.testing.expectEqual(@as(?u64, 20), scheduler.next_deadline());
    _ = scheduler.take_due(95) orelse return error.MissingDeferredRequest;
    try std.testing.expect(scheduler.mark_started(2, 95));
}

test "manual and on-save modes never schedule from ordinary edits" {
    var manual = render.Scheduler.init(.manual);
    _ = manual.edit(1, 10, .{});
    try std.testing.expectEqual(@as(?u64, null), manual.next_deadline());
    try std.testing.expectEqual(@as(?u64, 20), (manual.request_manual(1, 20) orelse return error.MissingRequest).due_ms);
    try std.testing.expectEqual(@as(?u64, 20), manual.next_deadline());

    var on_save = render.Scheduler.init(.on_save);
    _ = on_save.edit(1, 10, .{});
    try std.testing.expectEqual(@as(?u64, null), on_save.next_deadline());
    _ = on_save.save(1, 50);
    try std.testing.expectEqual(@as(?u64, 50), on_save.next_deadline());
}
