const std = @import("std");
const presenter = @import("presenter");
const Presenter = presenter.Presenter;
const Rect = presenter.Rect;

const full = Rect{ .left = 0, .top = 0, .right = 100, .bottom = 80 };
const damage_a = Rect{ .left = 10, .top = 10, .right = 30, .bottom = 20 };
const damage_b = Rect{ .left = 20, .top = 5, .right = 40, .bottom = 15 };

fn init() !Presenter {
    return Presenter.init(.{ .extent = .{ .width = 100, .height = 80 } });
}

fn frame(model: *Presenter, id: u64) !presenter.FramePlan {
    try model.bind_back_buffer();
    if (model.wait_plan(.{}).frame) try std.testing.expect(model.wake(.frame));
    return model.begin_frame(id);
}

fn present(model: *Presenter, id: u64) !void {
    const plan = try frame(model, id);
    try model.complete_frame(plan.token, .presented);
}

test "first and every frame require a fresh latency signal and successful presents require rebind" {
    try std.testing.expectEqual(@as(u32, 1), presenter.max_frame_latency);
    var model = try init();
    try std.testing.expectEqual(presenter.State.visible, model.state());
    try model.bind_back_buffer();
    try std.testing.expectError(error.FrameNotReady, model.begin_frame(1));
    try std.testing.expect(!model.wake(.input));
    try std.testing.expect(!model.wake(.worker));
    try std.testing.expectError(error.FrameNotReady, model.begin_frame(1));
    try std.testing.expect(model.wake(.frame));
    try std.testing.expectEqual(presenter.State.ready, model.state());
    const first = try model.begin_frame(1);
    try std.testing.expect(first.full_redraw);
    try std.testing.expectEqual(full, first.draw_rect);
    try std.testing.expectEqual(@as(?Rect, null), first.dirty_rect);
    try std.testing.expectError(error.FrameInFlight, model.begin_frame(2));
    try std.testing.expectError(error.FrameInFlight, model.release_back_buffer());
    try model.complete_frame(first.token, .presented);
    try std.testing.expect(!model.can_present(first.token));
    try std.testing.expectEqual(presenter.State.visible, model.state());
    try std.testing.expect(model.mark_dirty(damage_a));
    try std.testing.expect(model.wake(.frame));
    try std.testing.expectError(error.BackBufferNotBound, model.begin_frame(2));
    try model.bind_back_buffer();
    const second = try model.begin_frame(2);
    try model.complete_frame(second.token, .presented);
    try std.testing.expect(model.mark_dirty(damage_b));
    try model.bind_back_buffer();
    try std.testing.expectError(error.FrameNotReady, model.begin_frame(3));
}

test "invalidation before frame admission preserves the acquired latency grant" {
    var model = try init();
    try model.bind_back_buffer();
    try std.testing.expect(model.wake(.frame));
    model.invalidate(.theme_changed);
    try std.testing.expect(!model.wait_plan(.{}).frame);
    try std.testing.expectEqual(presenter.State.ready, model.state());
    const plan = try model.begin_frame(1);
    try std.testing.expect(plan.full_redraw);
    try model.complete_frame(plan.token, .presented);
}

test "invalidation after frame admission returns an unsubmitted latency grant" {
    var model = try init();
    try model.bind_back_buffer();
    try std.testing.expect(model.wake(.frame));
    _ = try model.begin_frame(1);
    model.invalidate(.uncertain_coverage);
    try std.testing.expectEqual(presenter.State.ready, model.state());
    const replacement = try model.begin_frame(2);
    try model.complete_frame(replacement.token, .presented);
}

test "two buffer history repairs prior scene damage and overlapping dirty regions" {
    var model = try init();
    try present(&model, 1);
    try std.testing.expect(model.buffer_history_valid(0));
    try std.testing.expect(!model.buffer_history_valid(1));
    try std.testing.expect(model.mark_dirty(damage_a));
    const second = try frame(&model, 2);
    try std.testing.expectEqual(@as(u1, 1), second.buffer_index);
    try std.testing.expect(second.full_redraw);
    try model.complete_frame(second.token, .presented);
    try std.testing.expect(model.mark_dirty(damage_b));
    const third = try frame(&model, 3);
    try std.testing.expectEqual(@as(u1, 0), third.buffer_index);
    try std.testing.expect(!third.full_redraw);
    const repaired = Rect{ .left = 10, .top = 5, .right = 40, .bottom = 20 };
    try std.testing.expectEqual(repaired, third.draw_rect);
    try std.testing.expectEqual(@as(?Rect, repaired), third.dirty_rect);
    try model.complete_frame(third.token, .presented);
    try std.testing.expect(model.mark_dirty(.{ .left = 70, .top = 50, .right = 90, .bottom = 70 }));
    const fourth = try frame(&model, 4);
    // The previous buffer needs B and the new damage, not A again.
    try std.testing.expectEqual(Rect{ .left = 20, .top = 5, .right = 90, .bottom = 70 }, fourth.draw_rect);
}

test "dirty union clips to the surface and ignores empty or outside rectangles" {
    var model = try init();
    try present(&model, 1);
    try std.testing.expect(model.mark_dirty(damage_a));
    try present(&model, 2);
    try std.testing.expect(!model.mark_dirty(.{ .left = 5, .top = 5, .right = 5, .bottom = 10 }));
    try std.testing.expect(!model.mark_dirty(.{ .left = 110, .top = 0, .right = 120, .bottom = 10 }));
    try std.testing.expect(model.mark_dirty(.{ .left = -20, .top = -10, .right = 15, .bottom = 12 }));
    try std.testing.expect(model.mark_dirty(.{ .left = 90, .top = 70, .right = 200, .bottom = 100 }));
    const plan = try frame(&model, 3);
    try std.testing.expectEqual(full, plan.draw_rect);
    try std.testing.expectEqual(@as(?Rect, full), plan.dirty_rect);
}

test "new damage arriving during a frame is retained for the next frame" {
    var model = try init();
    try present(&model, 1);
    try std.testing.expect(model.mark_dirty(damage_a));
    try present(&model, 2);
    try std.testing.expect(model.mark_dirty(damage_b));
    const third = try frame(&model, 3);
    try std.testing.expect(model.mark_dirty(.{ .left = 70, .top = 50, .right = 90, .bottom = 70 }));
    try model.complete_frame(third.token, .presented);
    const fourth = try frame(&model, 4);
    try std.testing.expectEqual(Rect{ .left = 20, .top = 5, .right = 90, .bottom = 70 }, fourth.draw_rect);
}

test "occluded and minimized states admit no present and resume with full redraw" {
    for ([_]presenter.Visibility{ .occluded, .minimized }) |visibility| {
        var model = try init();
        try present(&model, 1);
        try std.testing.expect(model.mark_dirty(damage_a));
        const pending = try frame(&model, 2);
        model.set_visibility(visibility);
        try std.testing.expectEqual(if (visibility == .occluded) presenter.State.occluded else .minimized, model.state());
        try std.testing.expect(!model.can_present(pending.token));
        try std.testing.expectError(error.StaleFrame, model.complete_frame(pending.token, .presented));
        try std.testing.expect(!model.wake(.frame));
        try std.testing.expectError(error.NotPresentable, model.begin_frame(3));
        try std.testing.expect(!model.wait_plan(.{}).frame);
        try std.testing.expectEqual(@as(?u64, null), model.wait_plan(.{}).deadline_ms);
        try std.testing.expectEqual(@as(u64, 1), model.last_valid_frame().?.id);
        model.set_visibility(.visible);
        const resumed = try frame(&model, 3);
        try std.testing.expect(resumed.full_redraw);
        try std.testing.expectEqual(@as(?Rect, null), resumed.dirty_rect);
    }
}

test "an occluded Present result keeps the last good frame and suspends further frames" {
    var model = try init();
    try present(&model, 1);
    try std.testing.expect(model.mark_dirty(damage_a));
    const pending = try frame(&model, 2);
    try model.complete_frame(pending.token, .occluded);
    try std.testing.expectEqual(presenter.State.occluded, model.state());
    try std.testing.expectEqual(@as(u64, 1), model.last_valid_frame().?.id);
    try std.testing.expect(!model.wait_plan(.{}).frame);
    try std.testing.expectError(error.NotPresentable, model.begin_frame(3));
}

test "resuming after an occluded Present requires a fresh latency grant" {
    var model = try init();
    try present(&model, 1);
    try std.testing.expect(model.mark_dirty(damage_a));
    const pending = try frame(&model, 2);
    try model.complete_frame(pending.token, .occluded);
    model.set_visibility(.visible);
    try model.bind_back_buffer();
    try std.testing.expectError(error.FrameNotReady, model.begin_frame(3));
    try std.testing.expect(model.wake(.frame));
    const resumed = try model.begin_frame(3);
    try model.complete_frame(resumed.token, .presented);
}

test "quiescent waits have no polling deadline and explicit input worker deadlines use the earliest" {
    var model = try init();
    const initial = model.wait_plan(.{});
    try std.testing.expect(initial.frame and initial.input and initial.worker);
    try std.testing.expectEqual(@as(?u64, null), initial.deadline_ms);
    try present(&model, 1);
    const idle = model.wait_plan(.{});
    try std.testing.expect(!idle.frame and idle.input and idle.worker);
    try std.testing.expect(!model.wake(.frame));
    try std.testing.expectEqual(@as(?u64, 15), model.wait_plan(.{ .input_ms = 40, .worker_ms = 15 }).deadline_ms);
    try std.testing.expectEqual(@as(?u64, 0), model.wait_plan(.{ .input_ms = 0, .worker_ms = 15 }).deadline_ms);
    model.set_visibility(.occluded);
    const hidden = model.wait_plan(.{ .worker_ms = 90 });
    try std.testing.expect(!hidden.frame);
    try std.testing.expectEqual(@as(?u64, 90), hidden.deadline_ms);
    try std.testing.expectEqual(@as(?u64, null), model.wait_plan(.{}).deadline_ms);
}

test "resize completion requires released references and invalidates pending frame tokens" {
    var model = try init();
    try present(&model, 1);
    try std.testing.expect(model.mark_dirty(damage_a));
    const pending = try frame(&model, 2);
    const resize = try model.request_resize(.{ .width = 160, .height = 120 });
    try std.testing.expectEqual(presenter.State.resizing, model.state());
    try std.testing.expect(!model.can_present(pending.token));
    try std.testing.expectError(error.StaleFrame, model.complete_frame(pending.token, .presented));
    try std.testing.expectError(error.BufferReferencesHeld, model.complete_resize(resize, .succeeded));
    try std.testing.expectError(error.TransitionInProgress, model.request_resize(.{ .width = 50, .height = 50 }));
    try model.release_back_buffer();
    try model.complete_resize(resize, .succeeded);
    try std.testing.expectError(error.StaleTransition, model.complete_resize(resize, .succeeded));
    try std.testing.expectEqual(@as(u64, 1), model.last_valid_frame().?.id);
    try std.testing.expect(!model.buffer_history_valid(0) and !model.buffer_history_valid(1));
    const replacement = try frame(&model, 3);
    try std.testing.expectEqual(Rect{ .left = 0, .top = 0, .right = 160, .bottom = 120 }, replacement.draw_rect);
    try std.testing.expect(replacement.full_redraw);
    try std.testing.expectEqual(@as(u64, 1), model.last_valid_frame().?.id);
    try model.complete_frame(replacement.token, .presented);
    try std.testing.expectEqual(@as(u64, 3), model.last_valid_frame().?.id);
}

test "DPI transition is atomic and minimized visibility survives completion" {
    var model = try init();
    try present(&model, 1);
    const change = try model.request_dpi_change(144, .{ .width = 150, .height = 120 });
    try std.testing.expectEqual(@as(u16, 96), model.surface.dpi);
    model.set_visibility(.minimized);
    try model.release_back_buffer();
    try model.complete_resize(change, .succeeded);
    try std.testing.expectEqual(@as(u16, 144), model.surface.dpi);
    try std.testing.expectEqual(presenter.State.minimized, model.state());
    try std.testing.expectEqual(@as(u16, 96), model.last_valid_frame().?.surface.dpi);
    model.set_visibility(.visible);
    const replacement = try frame(&model, 2);
    try std.testing.expect(replacement.full_redraw);
    try model.complete_frame(replacement.token, .presented);
    try std.testing.expectEqual(@as(u16, 144), model.last_valid_frame().?.surface.dpi);
}

test "invalid surface requests leave state intact and failed resize keeps the old surface" {
    var model = try init();
    try std.testing.expectError(error.InvalidExtent, model.request_resize(.{ .width = 0, .height = 80 }));
    try std.testing.expectError(error.InvalidExtent, Presenter.init(.{ .extent = .{ .width = std.math.maxInt(u32), .height = 80 } }));
    try std.testing.expectError(error.InvalidDpi, model.request_dpi_change(0, .{ .width = 100, .height = 80 }));
    try std.testing.expectEqual(presenter.State.visible, model.state());
    try present(&model, 1);
    const change = try model.request_resize(.{ .width = 160, .height = 120 });
    try model.release_back_buffer();
    try model.complete_resize(change, .failed);
    try std.testing.expectEqual(@as(u32, 100), model.surface.extent.width);
    try std.testing.expectEqual(@as(u64, 1), model.last_valid_frame().?.id);
    const retry = try frame(&model, 2);
    try std.testing.expectEqual(@as(u1, 1), retry.buffer_index);
    try std.testing.expect(retry.full_redraw);
    try std.testing.expectEqual(full, retry.draw_rect);
}

test "device loss requires release then explicit hardware recovery with bounded WARP fallback" {
    var model = try init();
    try present(&model, 1);
    try std.testing.expect(model.mark_dirty(damage_a));
    const pending = try frame(&model, 2);
    model.device_lost(.removed);
    try std.testing.expectEqual(presenter.State.device_lost, model.state());
    try std.testing.expectError(error.StaleFrame, model.complete_frame(pending.token, .presented));
    try std.testing.expectError(error.BufferReferencesHeld, model.begin_rebuild());
    try std.testing.expect(!model.wait_plan(.{}).frame);
    try model.release_back_buffer();
    const hardware = try model.begin_rebuild();
    try std.testing.expectEqual(presenter.RenderPath.hardware, hardware.path);
    try std.testing.expectEqual(presenter.State.rebuilding, model.state());
    try std.testing.expectError(error.TransitionInProgress, model.begin_rebuild());
    try std.testing.expectEqual(presenter.RecoveryOutcome.retry_warp, try model.complete_rebuild(hardware, .unavailable));
    try std.testing.expectEqual(presenter.State.device_lost, model.state());
    const warp = try model.begin_rebuild();
    try std.testing.expectEqual(presenter.RenderPath.warp, warp.path);
    try std.testing.expectError(error.StaleTransition, model.complete_rebuild(hardware, .succeeded));
    try std.testing.expectEqual(presenter.RecoveryOutcome.restored, try model.complete_rebuild(warp, .succeeded));
    try std.testing.expectEqual(@as(u64, 1), model.last_valid_frame().?.id);
    const replacement = try frame(&model, 3);
    try std.testing.expectEqual(presenter.RenderPath.warp, replacement.path);
    try std.testing.expect(replacement.full_redraw);
    try model.complete_frame(replacement.token, .presented);
    try std.testing.expectEqual(@as(u64, 3), model.last_valid_frame().?.id);
    try std.testing.expectEqual(presenter.RenderPath.warp, model.last_valid_frame().?.path);
}

test "failed present and failed WARP rebuild preserve last frame without automatic retry" {
    var model = try Presenter.init(.{ .extent = .{ .width = 100, .height = 80 }, .path = .warp });
    try present(&model, 1);
    try std.testing.expect(model.mark_dirty(damage_a));
    const pending = try frame(&model, 2);
    try model.complete_frame(pending.token, .failed);
    try std.testing.expectEqual(presenter.State.device_lost, model.state());
    try model.release_back_buffer();
    const rebuild = try model.begin_rebuild();
    try std.testing.expectEqual(presenter.RenderPath.warp, rebuild.path);
    try std.testing.expectEqual(presenter.RecoveryOutcome.failed, try model.complete_rebuild(rebuild, .unavailable));
    try std.testing.expectEqual(presenter.State.device_lost, model.state());
    try std.testing.expectEqual(@as(u64, 1), model.last_valid_frame().?.id);
    try std.testing.expect(!model.wait_plan(.{}).frame);
    try std.testing.expectEqual(@as(?u64, null), model.wait_plan(.{}).deadline_ms);
    try std.testing.expect(!model.wake(.frame));
}

test "invalidation reasons force full redraw and forbid partial metadata" {
    for ([_]presenter.Invalidation{ .invalid_history, .uncertain_coverage, .theme_changed, .adapter_changed }) |reason| {
        var model = try init();
        try present(&model, 1);
        try std.testing.expect(model.mark_dirty(damage_a));
        try present(&model, 2);
        model.invalidate(reason);
        const replacement = try frame(&model, 3);
        try std.testing.expect(replacement.full_redraw);
        try std.testing.expectEqual(full, replacement.draw_rect);
        try std.testing.expectEqual(@as(?Rect, null), replacement.dirty_rect);
    }
}

test "flip discard challenger always redraws full client on hardware and WARP" {
    for ([_]presenter.RenderPath{ .hardware, .warp }) |path| {
        var model = try Presenter.init(.{ .extent = .{ .width = 100, .height = 80 }, .path = path, .mode = .flip_discard });
        try present(&model, 1);
        try std.testing.expect(model.mark_dirty(damage_a));
        try present(&model, 2);
        try std.testing.expect(model.mark_dirty(damage_b));
        const third = try frame(&model, 3);
        try std.testing.expectEqual(path, third.path);
        try std.testing.expect(third.full_redraw);
        try std.testing.expectEqual(full, third.draw_rect);
        try std.testing.expectEqual(@as(?Rect, null), third.dirty_rect);
    }
}

test "resize device loss retires its token and restoration retains hidden visibility" {
    var model = try init();
    try present(&model, 1);
    const resize = try model.request_resize(.{ .width = 160, .height = 120 });
    try model.release_back_buffer();
    try model.complete_resize(resize, .{ .device_lost = .reset });
    try std.testing.expectEqual(presenter.State.device_lost, model.state());
    try std.testing.expectError(error.StaleTransition, model.complete_resize(resize, .succeeded));
    const rebuild = try model.begin_rebuild();
    model.set_visibility(.occluded);
    try std.testing.expectEqual(presenter.RecoveryOutcome.restored, try model.complete_rebuild(rebuild, .succeeded));
    try std.testing.expectEqual(presenter.State.occluded, model.state());
    try std.testing.expectEqual(@as(u64, 1), model.last_valid_frame().?.id);
    try std.testing.expect(!model.wake(.frame));
    model.set_visibility(.visible);
    const restored = try frame(&model, 2);
    try std.testing.expectEqual(presenter.RenderPath.hardware, restored.path);
    try std.testing.expect(restored.full_redraw);
}

test "device rebuild requires a fresh latency grant for the replacement chain" {
    var model = try init();
    try model.bind_back_buffer();
    try std.testing.expect(model.wake(.frame));
    model.device_lost(.adapter_changed);
    try model.release_back_buffer();
    const attempt = try model.begin_rebuild();
    try std.testing.expectEqual(presenter.RecoveryOutcome.restored, try model.complete_rebuild(attempt, .succeeded));
    try model.bind_back_buffer();
    try std.testing.expectError(error.FrameNotReady, model.begin_frame(1));
    try std.testing.expect(model.wake(.frame));
    const replacement = try model.begin_frame(1);
    try model.complete_frame(replacement.token, .presented);
}

test "new device loss rejects an obsolete rebuild completion" {
    var model = try init();
    model.device_lost(.adapter_changed);
    const obsolete = try model.begin_rebuild();
    model.device_lost(.removed);
    try std.testing.expectError(error.StaleTransition, model.complete_rebuild(obsolete, .succeeded));
    const current = try model.begin_rebuild();
    try std.testing.expectError(error.StaleTransition, model.complete_rebuild(obsolete, .succeeded));
    try std.testing.expectEqual(presenter.RecoveryOutcome.restored, try model.complete_rebuild(current, .succeeded));
    try std.testing.expectEqual(@as(?presenter.FrameRecord, null), model.last_valid_frame());
    const first = try frame(&model, 1);
    try std.testing.expect(first.full_redraw);
}

test "present device loss before any successful frame never fabricates a last valid frame" {
    var model = try init();
    const first = try frame(&model, 1);
    try model.complete_frame(first.token, .{ .device_lost = .hung });
    try std.testing.expectEqual(@as(?presenter.FrameRecord, null), model.last_valid_frame());
    try std.testing.expectEqual(presenter.State.device_lost, model.state());
    try std.testing.expectError(error.BufferReferencesHeld, model.begin_rebuild());
    try model.release_back_buffer();
    const attempt = try model.begin_rebuild();
    try std.testing.expectEqual(presenter.RecoveryOutcome.failed, try model.complete_rebuild(attempt, .failed));
    try std.testing.expectEqual(@as(?u64, null), model.wait_plan(.{}).deadline_ms);
}

test "coverage invalidation revokes a prepared frame before present" {
    var model = try init();
    try present(&model, 1);
    try std.testing.expect(model.mark_dirty(damage_a));
    const pending = try frame(&model, 2);
    model.invalidate(.uncertain_coverage);
    try std.testing.expect(!model.can_present(pending.token));
    try std.testing.expectError(error.StaleFrame, model.complete_frame(pending.token, .presented));
    try std.testing.expectEqual(@as(u64, 1), model.last_valid_frame().?.id);
    // The canceled frame never reached Present, so its same-chain latency
    // grant is reusable immediately for the full-redraw replacement.
    const replacement = try model.begin_frame(3);
    try std.testing.expect(replacement.full_redraw);
    try std.testing.expectEqual(@as(?Rect, null), replacement.dirty_rect);
}

test "successful present unbinds the target but resize still requires releasing held references" {
    var model = try init();
    try present(&model, 1);
    const resize = try model.request_resize(.{ .width = 160, .height = 120 });
    try std.testing.expectError(error.BufferReferencesHeld, model.complete_resize(resize, .succeeded));
    try model.release_back_buffer();
    try model.complete_resize(resize, .succeeded);
    try std.testing.expectEqual(@as(u64, 1), model.last_valid_frame().?.id);
}

test "device rebuild still requires releasing references retained after a successful present" {
    var model = try init();
    try present(&model, 1);
    model.device_lost(.adapter_changed);
    try std.testing.expectError(error.BufferReferencesHeld, model.begin_rebuild());
    try model.release_back_buffer();
    const attempt = try model.begin_rebuild();
    try std.testing.expectEqual(presenter.RecoveryOutcome.restored, try model.complete_rebuild(attempt, .succeeded));
    try std.testing.expectEqual(@as(u64, 1), model.last_valid_frame().?.id);
}
