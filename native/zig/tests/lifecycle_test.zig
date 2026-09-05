const std = @import("std");
const lifecycle = @import("app_lifecycle");

test "lifecycle acquires ownership monotonically and tears it down in reverse" {
    var app = lifecycle.Lifecycle.init();
    try app.acquire(.ui_thread);
    try app.acquire(.database);
    try app.acquire(.worker);
    try app.acquire(.uia);
    try app.acquire(.graphics);
    try std.testing.expectEqual(lifecycle.Phase.running, app.phase());
    _ = app.begin_close();
    try std.testing.expectError(error.OutOfOrderRelease, app.release(.uia));
    try std.testing.expectEqual(lifecycle.ReleaseOutcome.released, app.release(.graphics));
    try std.testing.expectEqual(lifecycle.ReleaseOutcome.released, app.release(.uia));
    try std.testing.expectEqual(lifecycle.ReleaseOutcome.released, app.release(.worker));
    try std.testing.expectEqual(lifecycle.ReleaseOutcome.released, app.release(.database));
    try std.testing.expectEqual(lifecycle.ReleaseOutcome.released, app.release(.ui_thread));
    try std.testing.expectEqual(lifecycle.Phase.closed, app.phase());
    try std.testing.expectEqual(lifecycle.ReleaseOutcome.already_released, app.release(.ui_thread));
}

test "close admission and exit outcomes are typed and idempotent" {
    var clean = lifecycle.Lifecycle.init();
    try clean.acquire(.ui_thread);
    try clean.acquire(.database);
    try std.testing.expectEqual(lifecycle.CloseOutcome.admitted, clean.begin_close());
    try std.testing.expectEqual(lifecycle.CloseOutcome.already_closing, clean.begin_close());
    _ = try clean.release(.database);
    _ = try clean.release(.ui_thread);
    try std.testing.expectEqual(lifecycle.ExitOutcome.clean, clean.finish(.clean));
    try std.testing.expectEqual(lifecycle.ExitOutcome.already_finished, clean.finish(.clean));

    var crashed = lifecycle.Lifecycle.init();
    try crashed.acquire(.ui_thread);
    try std.testing.expectEqual(lifecycle.ExitOutcome.crashed, crashed.crash());
    try std.testing.expectEqual(lifecycle.Phase.crashed, crashed.phase());
    try std.testing.expectEqual(lifecycle.ExitOutcome.already_finished, crashed.crash());
}

test "lifecycle rejects ownership resurrection and release before close" {
    var app = lifecycle.Lifecycle.init();
    try app.acquire(.ui_thread);
    try std.testing.expectError(error.ReleaseBeforeClose, app.release(.ui_thread));
    try std.testing.expectError(error.DuplicateOwnership, app.acquire(.ui_thread));
    _ = app.begin_close();
    try std.testing.expectError(error.AcquireAfterClose, app.acquire(.database));
}

test "empty startup can close cleanly and clean exit reports readiness" {
    var empty = lifecycle.Lifecycle.init();
    try std.testing.expectEqual(lifecycle.CloseOutcome.admitted, empty.begin_close());
    try std.testing.expectEqual(lifecycle.Phase.closed, empty.phase());
    try std.testing.expectEqual(lifecycle.ExitOutcome.clean, empty.finish(.clean));
    try std.testing.expectEqual(lifecycle.ExitOutcome.already_finished, empty.finish(.clean));

    var not_ready = lifecycle.Lifecycle.init();
    try std.testing.expectEqual(lifecycle.ExitOutcome.not_ready, not_ready.finish(.clean));
    try std.testing.expectEqual(lifecycle.Phase.created, not_ready.phase());
}
