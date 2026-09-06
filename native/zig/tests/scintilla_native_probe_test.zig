const builtin = @import("builtin");
const std = @import("std");
const probe = @import("scintilla_native_probe");

fn completeFacts() probe.Facts {
    return .{
        .scintilla_class_registered = true,
        .parent_class_registered = true,
        .parent_handle_valid = true,
        .child_handle_valid = true,
        .parent_child_relation_valid = true,
        .direct_function_resolved = true,
        .direct_pointer_resolved = true,
        .document_created = true,
        .document_released = true,
        .null_lexer_selected = true,
        .style_notification_seen = true,
        .batched_styling_applied = true,
    };
}

test "complete Windows facts satisfy the native lifecycle gate" {
    switch (probe.evaluate(.windows_x86_64_msvc, completeFacts())) {
        .satisfied => |facts| try std.testing.expect(facts.batched_styling_applied),
        else => return error.ExpectedSatisfiedScintillaNativeProbe,
    }
}

test "missing parent notification fails closed" {
    var facts = completeFacts();
    facts.style_notification_seen = false;

    switch (probe.evaluate(.windows_x86_64_msvc, facts)) {
        .missing_fact => |fact| try std.testing.expectEqual(.style_notification_seen, fact),
        else => return error.ExpectedMissingStyleNotification,
    }
}

test "missing parent-child relationship fails closed" {
    var facts = completeFacts();
    facts.parent_child_relation_valid = false;

    switch (probe.evaluate(.windows_x86_64_msvc, facts)) {
        .missing_fact => |fact| try std.testing.expectEqual(.parent_child_relation_valid, fact),
        else => return error.ExpectedMissingParentChildRelation,
    }
}

test "invalid child handle fails closed before lifecycle claims" {
    var facts = completeFacts();
    facts.child_handle_valid = false;

    switch (probe.evaluate(.windows_x86_64_msvc, facts)) {
        .invalid_handle => |handle| try std.testing.expectEqual(.child, handle),
        else => return error.ExpectedInvalidChildHandle,
    }
}

test "Linux is compile-only and explicitly outside the runtime probe" {
    switch (probe.evaluate(.linux_compile_only, .{})) {
        .not_in_scope => |target| try std.testing.expectEqual(.linux_compile_only, target),
        else => return error.ExpectedLinuxNotInScope,
    }
}

test "the probe surface does not claim UI Automation evidence" {
    try std.testing.expect(!@hasDecl(probe, "uia"));
    try std.testing.expect(!@hasDecl(probe, "uia_evidence"));
}

test "runtime entry point is not in scope on non-Windows hosts" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    switch (probe.run()) {
        .not_in_scope => {},
        else => return error.ExpectedNonWindowsRuntimeSkip,
    }
}

test "Windows runtime probe reports every native lifecycle fact" {
    if (probe.currentTarget() != .windows_x86_64_msvc) return error.SkipZigTest;
    switch (probe.run()) {
        .satisfied => |facts| {
            try std.testing.expect(facts.scintilla_class_registered);
            try std.testing.expect(facts.document_released);
            try std.testing.expect(facts.style_notification_seen);
            try std.testing.expect(facts.batched_styling_applied);
        },
        else => return error.ScintillaNativeLifecycleProbeFailed,
    }
}
