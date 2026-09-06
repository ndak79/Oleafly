const std = @import("std");
const contract = @import("scintilla_runtime_contract");

fn completeFacts() contract.RuntimeFacts {
    return .{
        .class_registered = true,
        .direct_api_resolved = true,
        .document_created = true,
        .null_lexer_selected = true,
        .style_notification_seen = true,
        .batched_styles_applied = true,
    };
}

test "complete Windows lifecycle facts satisfy the contract" {
    const result = contract.evaluate(.windows, completeFacts());
    switch (result) {
        .satisfied => {},
        else => return error.UnexpectedScintillaRuntimeContractResult,
    }
}

test "a missing Windows lifecycle event is reported explicitly" {
    var facts = completeFacts();
    facts.style_notification_seen = false;

    switch (contract.evaluate(.windows, facts)) {
        .missing_lifecycle_event => |fact| try std.testing.expectEqual(.style_notification_seen, fact),
        else => return error.ExpectedMissingScintillaLifecycleEvent,
    }
}

test "Linux is compile-only and explicitly not in scope" {
    switch (contract.evaluate(.linux, .{})) {
        .not_in_scope => |scope| try std.testing.expectEqual(.linux, scope),
        else => return error.ExpectedLinuxScintillaRuntimeContractNotInScope,
    }
}
