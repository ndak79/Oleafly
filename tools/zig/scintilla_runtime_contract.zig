//! Contract oracle for the future native Scintilla HWND probe.
//!
//! The facts are supplied by a platform-specific probe. This module only
//! evaluates the immutable acceptance contract and deliberately cannot claim
//! that a Windows window, document, or notification was observed.
const std = @import("std");

pub const Target = enum { windows, linux };
pub const RuntimeFacts = struct {
    class_registered: bool = false,
    direct_api_resolved: bool = false,
    document_created: bool = false,
    null_lexer_selected: bool = false,
    style_notification_seen: bool = false,
    batched_styles_applied: bool = false,
};

pub const Result = union(enum) {
    satisfied,
    not_in_scope: Target,
    missing_lifecycle_event: Fact,
};

pub const Fact = enum {
    class_registered,
    direct_api_resolved,
    document_created,
    null_lexer_selected,
    style_notification_seen,
    batched_styles_applied,
};

pub fn evaluate(target: Target, facts: RuntimeFacts) Result {
    if (target == .linux) return .{ .not_in_scope = .linux };
    const required = [_]struct { fact: Fact, value: bool }{
        .{ .fact = .class_registered, .value = facts.class_registered },
        .{ .fact = .direct_api_resolved, .value = facts.direct_api_resolved },
        .{ .fact = .document_created, .value = facts.document_created },
        .{ .fact = .null_lexer_selected, .value = facts.null_lexer_selected },
        .{ .fact = .style_notification_seen, .value = facts.style_notification_seen },
        .{ .fact = .batched_styles_applied, .value = facts.batched_styles_applied },
    };
    for (required) |item| if (!item.value) {
        return .{ .missing_lifecycle_event = item.fact };
    };
    return .satisfied;
}

test "complete facts are accepted only for Windows" {
    const facts = RuntimeFacts{
        .class_registered = true,
        .direct_api_resolved = true,
        .document_created = true,
        .null_lexer_selected = true,
        .style_notification_seen = true,
        .batched_styles_applied = true,
    };
    try std.testing.expect(evaluate(.windows, facts) == .satisfied);
}
