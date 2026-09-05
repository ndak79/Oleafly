//! Portable GUI argument admission, called before window/database/network
//! initialization. Arguments exclude argv[0]; already-tokenized UTF-8 slices
//! are borrowed only for the duration of admission. No allocation or Win32
//! import is needed. Native command-line decoding and inherited OS handle
//! inspection remain responsibilities of the later process-entry binding.
//!
//! A trial ID is correlation data only. It cannot select a worker, fixture,
//! test seam, policy, or acceptance mode. The result contains only its sixteen
//! bytes and their source. Injectable entropy is an internal API dependency,
//! never a command-line option. The production caller uses `admitOs` with its
//! system-backed std.Io; secure entropy failure aborts admission without a
//! PRNG, clock, zero-value, or retry fallback.

const std = @import("std");

pub const Origin = enum { supplied, generated };
pub const Admission = struct { trace_trial: [16]u8, origin: Origin };
pub const ArgumentError = error{
    DuplicateTraceTrial,
    MalformedTraceTrial,
    WorkerSelectorNotAllowed,
    InternalProbeNotAllowed,
    WorkerBootstrapNotAllowed,
    UnknownArgument,
};
pub const AdmissionError = ArgumentError || std.Io.RandomSecureError;

/// Synchronous entropy provider. A successful call must fill the entire slice;
/// admission requests exactly sixteen bytes once, only when no ID was supplied.
pub const Entropy = struct {
    context: ?*anyopaque,
    fill: *const fn (?*anyopaque, []u8) std.Io.RandomSecureError!void,
};

pub fn admit(arguments: []const []const u8, entropy: Entropy) AdmissionError!Admission {
    var supplied: ?[16]u8 = null;
    for (arguments) |argument| {
        // Check the narrower bootstrap prefix before the general worker
        // prefix so callers receive the precise prohibited-entry reason.
        if (std.mem.startsWith(u8, argument, "--bootstrap-handle") or
            std.mem.startsWith(u8, argument, "--worker-bootstrap-handle")) return error.WorkerBootstrapNotAllowed;
        if (std.mem.startsWith(u8, argument, "--worker")) return error.WorkerSelectorNotAllowed;
        if (std.mem.startsWith(u8, argument, "--probe") or
            std.mem.startsWith(u8, argument, "--internal")) return error.InternalProbeNotAllowed;
        if (!std.mem.startsWith(u8, argument, "--trace-trial")) return error.UnknownArgument;
        if (!std.mem.startsWith(u8, argument, "--trace-trial=")) return error.MalformedTraceTrial;
        if (supplied != null) return error.DuplicateTraceTrial;
        supplied = try decodeTrial(argument["--trace-trial=".len..]);
    }

    // Validate the complete argument vector before calling any dependency;
    // a valid first option never masks an invalid trailing argument.
    if (supplied) |bytes| return .{ .trace_trial = bytes, .origin = .supplied };
    var bytes: [16]u8 = undefined;
    try entropy.fill(entropy.context, &bytes);
    return .{ .trace_trial = bytes, .origin = .generated };
}

/// Uses std.Io's secure OS entropy operation, which has no weak fallback.
/// The caller supplies its existing system I/O backend; this does not create
/// an event loop, initialize application services, or import platform bindings.
pub fn admitOs(arguments: []const []const u8, io: std.Io) AdmissionError!Admission {
    var context = io;
    return admit(arguments, .{ .context = &context, .fill = fillOs });
}

fn fillOs(context: ?*anyopaque, bytes: []u8) std.Io.RandomSecureError!void {
    const io: *const std.Io = @ptrCast(@alignCast(context.?));
    try io.randomSecure(bytes);
}

fn decodeTrial(text: []const u8) error{MalformedTraceTrial}![16]u8 {
    if (text.len != 32) return error.MalformedTraceTrial;
    var result: [16]u8 = undefined;
    for (&result, 0..) |*byte, index| {
        byte.* = (try lowerHex(text[index * 2])) << 4 | try lowerHex(text[index * 2 + 1]);
    }
    return result;
}

fn lowerHex(byte: u8) error{MalformedTraceTrial}!u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        else => error.MalformedTraceTrial,
    };
}
