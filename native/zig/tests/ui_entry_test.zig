const std = @import("std");
const entry = @import("ui_entry");

const option = "--trace-trial=0123456789abcdeffedcba9876543210";
const expected = [_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10 };

const EntropyProbe = struct {
    calls: usize = 0,
    requested_bytes: usize = 0,
    fail: bool = false,

    fn fill(context: ?*anyopaque, bytes: []u8) std.Io.RandomSecureError!void {
        const self: *EntropyProbe = @ptrCast(@alignCast(context.?));
        self.calls += 1;
        self.requested_bytes = bytes.len;
        if (self.fail) return error.EntropyUnavailable;
        for (bytes, 0..) |*byte, index| byte.* = @intCast(index);
    }

    fn source(self: *EntropyProbe) entry.Entropy {
        return .{ .context = self, .fill = fill };
    }
};

fn expectRejected(expected_error: anyerror, arguments: []const []const u8) !void {
    var entropy = EntropyProbe{ .fail = true };
    try std.testing.expectError(expected_error, entry.admit(arguments, entropy.source()));
    try std.testing.expectEqual(@as(usize, 0), entropy.calls);
}

test "supplied trace trial decodes exact bytes without entropy" {
    var entropy = EntropyProbe{ .fail = true };
    const admitted = try entry.admit(&.{option}, entropy.source());
    try std.testing.expectEqualSlices(u8, &expected, &admitted.trace_trial);
    try std.testing.expectEqual(entry.Origin.supplied, admitted.origin);
    try std.testing.expectEqual(@as(usize, 0), entropy.calls);

    const zeros = try entry.admit(&.{"--trace-trial=00000000000000000000000000000000"}, entropy.source());
    const ones = try entry.admit(&.{"--trace-trial=ffffffffffffffffffffffffffffffff"}, entropy.source());
    try std.testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &zeros.trace_trial);
    try std.testing.expectEqualSlices(u8, &([_]u8{0xff} ** 16), &ones.trace_trial);
    try std.testing.expectEqual(@as(usize, 0), entropy.calls);
}

test "absent trace trial requests exactly sixteen entropy bytes once" {
    var entropy = EntropyProbe{};
    const admitted = try entry.admit(&.{}, entropy.source());
    const bytes = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    try std.testing.expectEqualSlices(u8, &bytes, &admitted.trace_trial);
    try std.testing.expectEqual(entry.Origin.generated, admitted.origin);
    try std.testing.expectEqual(@as(usize, 1), entropy.calls);
    try std.testing.expectEqual(@as(usize, 16), entropy.requested_bytes);
}

test "entropy failure aborts admission without retry or fallback" {
    var entropy = EntropyProbe{ .fail = true };
    try std.testing.expectError(error.EntropyUnavailable, entry.admit(&.{}, entropy.source()));
    try std.testing.expectEqual(@as(usize, 1), entropy.calls);
    try std.testing.expectEqual(@as(usize, 16), entropy.requested_bytes);
}

test "duplicate trial arguments fail even when both values are valid" {
    try expectRejected(error.DuplicateTraceTrial, &.{ option, option });
    try expectRejected(error.DuplicateTraceTrial, &.{ option, "--trace-trial=ffffffffffffffffffffffffffffffff" });
}

test "uppercase wrong width nonhex and trailing trial forms are rejected before entropy" {
    const invalid = [_][]const u8{
        "--trace-trial=",
        "--trace-trial=0",
        "--trace-trial=00112233445566778899aabbccddeef",
        "--trace-trial=00112233445566778899aabbccddeeff0",
        "--trace-trial=00112233445566778899AABBCCDDEEFF",
        "--trace-trial=00112233445566778899aabbccddeeFf",
        "--trace-trial=g0112233445566778899aabbccddeeff",
        "--trace-trial=00112233445566778899aabbccddeefg",
        "--trace-trial=00112233445566778899aabbccddeef/",
        "--trace-trial=00112233445566778899aabbccddeef:",
        "--trace-trial=00112233445566778899aabbccddeeff ",
        "--trace-trial=00112233445566778899aabbccddeeff\n",
        "--trace-trial=00112233445566778899aabbccddeeff\x00",
        "--trace-trial=00112233445566778899aabbccddeeff=extra",
        "--trace-trial=00112233445566778899aabbccddeef\xff",
        "--trace-trial=00112233445566778899aabbccddeeff --worker=pdf",
    };
    for (invalid) |argument| try expectRejected(error.MalformedTraceTrial, &.{argument});
}

test "separated trial values and alternate spellings are not accepted" {
    try expectRejected(error.MalformedTraceTrial, &.{ "--trace-trial", "00112233445566778899aabbccddeeff" });
    try expectRejected(error.MalformedTraceTrial, &.{ "--trace-trial=", "00112233445566778899aabbccddeeff" });
    for ([_][]const u8{ "--trace-trial", "--trace-trial 00112233445566778899aabbccddeeff", "--trace-trial:00112233445566778899aabbccddeeff" }) |argument| {
        try expectRejected(error.MalformedTraceTrial, &.{argument});
    }
    for ([_][]const u8{ "--TRACE-TRIAL=00112233445566778899aabbccddeeff", "--trace_trial=00112233445566778899aabbccddeeff", "-trace-trial=00112233445566778899aabbccddeeff" }) |argument| {
        try expectRejected(error.UnknownArgument, &.{argument});
    }
}

test "worker selectors and every worker prefix are rejected" {
    for ([_][]const u8{ "--worker", "--worker=pdf", "--worker=PdfWorker", "--worker=science", "--worker-role=UI", "--worker-extra", "--worker\x00" }) |argument| {
        try expectRejected(error.WorkerSelectorNotAllowed, &.{argument});
        try expectRejected(error.WorkerSelectorNotAllowed, &.{ option, argument });
        try expectRejected(error.WorkerSelectorNotAllowed, &.{ argument, option });
    }
}

test "internal and probe switches cannot enable an alternate UI entry path" {
    for ([_][]const u8{ "--probe", "--probe=texflow.role.v1:UI", "--probe-mode", "--probe\x00", "--internal", "--internal=fixture", "--internal-policy=relaxed" }) |argument| {
        try expectRejected(error.InternalProbeNotAllowed, &.{argument});
        try expectRejected(error.InternalProbeNotAllowed, &.{ option, argument });
        try expectRejected(error.InternalProbeNotAllowed, &.{ argument, option });
    }
}

test "bootstrap handle switches fail before entropy regardless of handle spelling" {
    for ([_][]const u8{ "--bootstrap-handle", "--bootstrap-handle=0", "--bootstrap-handle=1234", "--bootstrap-handles=1,2", "--worker-bootstrap-handle", "--worker-bootstrap-handle=0xffff", "--worker-bootstrap-handle-extra" }) |argument| {
        try expectRejected(error.WorkerBootstrapNotAllowed, &.{argument});
        try expectRejected(error.WorkerBootstrapNotAllowed, &.{ option, argument });
        try expectRejected(error.WorkerBootstrapNotAllowed, &.{ argument, option });
    }
}

test "unknown positional empty fixture policy and trailing arguments all fail closed" {
    for ([_][]const u8{ "", "TExFlow.exe", "document.tex", "--", "--help", "--fixture", "--test", "--policy=relaxed", "--acceptance", "--unknown", "\x00", "\xff", "00112233445566778899aabbccddeeff" }) |argument| {
        try expectRejected(error.UnknownArgument, &.{argument});
        try expectRejected(error.UnknownArgument, &.{ option, argument });
        try expectRejected(error.UnknownArgument, &.{ argument, option });
    }
}

test "production adapter uses only the secure entropy callback and propagates its failure" {
    var probe = EntropyProbe{};
    var vtable = std.Io.failing.vtable.*;
    vtable.randomSecure = EntropyProbe.fill;
    const io = std.Io{ .userdata = &probe, .vtable = &vtable };
    const generated = try entry.admitOs(&.{}, io);
    const bytes = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    try std.testing.expectEqualSlices(u8, &bytes, &generated.trace_trial);
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expectEqual(@as(usize, 16), probe.requested_bytes);
    probe.fail = true;
    try std.testing.expectError(error.EntropyUnavailable, entry.admitOs(&.{}, io));
    try std.testing.expectEqual(@as(usize, 2), probe.calls);
    try std.testing.expectError(error.UnknownArgument, entry.admitOs(&.{"--fixture"}, io));
    const supplied = try entry.admitOs(&.{option}, io);
    try std.testing.expectEqualSlices(u8, &expected, &supplied.trace_trial);
    try std.testing.expectEqual(@as(usize, 2), probe.calls);
}

test "every noncanonical byte is rejected at every hex position without entropy" {
    const prefix = "--trace-trial=";
    var argument: [prefix.len + 32]u8 = undefined;
    @memcpy(argument[0..prefix.len], prefix);
    @memset(argument[prefix.len..], '0');
    for (0..32) |position| {
        for (0..256) |candidate| {
            const byte: u8 = @intCast(candidate);
            if (std.mem.indexOfScalar(u8, "0123456789abcdef", byte) != null) continue;
            argument[prefix.len + position] = byte;
            try expectRejected(error.MalformedTraceTrial, &.{&argument});
        }
        argument[prefix.len + position] = '0';
    }
}
