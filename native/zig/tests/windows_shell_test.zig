const std = @import("std");
const shell = @import("windows_shell");
const entry = @import("ui_entry");
const com = @import("windows_com");
const w = std.unicode.utf8ToUtf16LeStringLiteral;
const supplied = w("--trace-trial=00112233445566778899aabbccddeeff");

const Event = enum { entropy, dll, dpi, com_init, register, create, show, get, dispatch, destroy, unregister, com_uninit };
const Fake = struct {
    events: [40]Event = undefined,
    count: usize = 0,
    fail: ?Event = null,
    cleanup_fail: ?Event = null,
    message_result: i32 = 1,
    reads: usize = 0,

    fn record(self: *Fake, event: Event) bool {
        self.events[self.count] = event;
        self.count += 1;
        return self.fail != event and self.cleanup_fail != event;
    }
    pub fn restrictDllSearch(self: *Fake) bool {
        return self.record(.dll);
    }
    pub fn setDpiAwareness(self: *Fake) bool {
        return self.record(.dpi);
    }
    pub fn initializeCom(self: *Fake) bool {
        return self.record(.com_init);
    }
    pub fn uninitializeCom(self: *Fake) void {
        _ = self.record(.com_uninit);
    }
    pub fn registerClass(self: *Fake) bool {
        return self.record(.register);
    }
    pub fn unregisterClass(self: *Fake) bool {
        return self.record(.unregister);
    }
    pub fn createWindow(self: *Fake) bool {
        return self.record(.create);
    }
    pub fn destroyWindow(self: *Fake) bool {
        return self.record(.destroy);
    }
    pub fn showWindow(self: *Fake) void {
        _ = self.record(.show);
    }
    pub fn getMessage(self: *Fake) i32 {
        _ = self.record(.get);
        self.reads += 1;
        return if (self.reads == 1) self.message_result else 0;
    }
    pub fn dispatchMessage(self: *Fake) void {
        _ = self.record(.dispatch);
    }
    fn entropy(self: *Fake) entry.Entropy {
        return .{ .context = self, .fill = fill };
    }
    fn fill(context: ?*anyopaque, bytes: []u8) std.Io.RandomSecureError!void {
        const self: *Fake = @ptrCast(@alignCast(context.?));
        if (!self.record(.entropy)) return error.EntropyUnavailable;
        @memset(bytes, 0x5a);
    }
};

test "shell admits before DLL DPI COM HWND and waits before each dispatch" {
    var fake: Fake = .{};
    const result = shell.run(std.testing.allocator, &.{}, fake.entropy(), &fake);
    try std.testing.expectEqual(shell.ExitCode.success, result.code);
    try std.testing.expectEqual(entry.Origin.generated, result.admission.?.origin);
    try std.testing.expectEqual([_]u8{0x5a} ** 16, result.admission.?.trace_trial);
    try std.testing.expectEqualSlices(Event, &.{ .entropy, .dll, .dpi, .com_init, .register, .create, .show, .get, .dispatch, .get, .destroy, .unregister, .com_uninit }, fake.events[0..fake.count]);
}

test "shell rejects prohibited or malformed Unicode arguments without any setup" {
    const invalid_wide = [_:0]u16{0xd800};
    const invalid = [_][*:0]const u16{
        w("--worker"),                    w("--probe"),       w("--internal"),        w("--bootstrap-handle=7"),
        w("--worker-bootstrap-handle=7"), w("--trace-trial"), w("--trace-trial=ABC"), w("--unknown"),
        w("--\u{1f642}"),                 &invalid_wide,
    };
    for (invalid) |arg| {
        var fake: Fake = .{ .fail = .entropy };
        const result = shell.run(std.testing.allocator, &.{arg}, fake.entropy(), &fake);
        try std.testing.expectEqual(shell.ExitCode.admission_failed, result.code);
        try std.testing.expectEqual(@as(usize, 0), fake.count);
    }
    for ([_][]const [*:0]const u16{ &.{ supplied, supplied }, &.{ supplied, w("--worker") } }) |args| {
        var fake: Fake = .{ .fail = .entropy };
        try std.testing.expectEqual(shell.ExitCode.admission_failed, shell.run(std.testing.allocator, args, fake.entropy(), &fake).code);
        try std.testing.expectEqual(@as(usize, 0), fake.count);
    }
}

test "shell supplied trial needs no entropy and entropy failure needs no setup" {
    var fake: Fake = .{ .fail = .entropy };
    var result = shell.run(std.testing.allocator, &.{supplied}, fake.entropy(), &fake);
    try std.testing.expectEqual(shell.ExitCode.success, result.code);
    try std.testing.expectEqual(entry.Origin.supplied, result.admission.?.origin);
    try std.testing.expectEqual(Event.dll, fake.events[0]);
    fake = .{ .fail = .entropy };
    result = shell.run(std.testing.allocator, &.{}, fake.entropy(), &fake);
    try std.testing.expectEqual(shell.ExitCode.admission_failed, result.code);
    try std.testing.expectEqualSlices(Event, &.{.entropy}, fake.events[0..fake.count]);
}

test "shell cleans only acquired resources on every initialization failure" {
    const cases = .{
        .{ Event.dll, shell.ExitCode.dll_search_failed, &[_]Event{.dll} },
        .{ Event.dpi, shell.ExitCode.dpi_failed, &[_]Event{ .dll, .dpi } },
        .{ Event.com_init, shell.ExitCode.com_failed, &[_]Event{ .dll, .dpi, .com_init } },
        .{ Event.register, shell.ExitCode.class_failed, &[_]Event{ .dll, .dpi, .com_init, .register, .com_uninit } },
        .{ Event.create, shell.ExitCode.window_failed, &[_]Event{ .dll, .dpi, .com_init, .register, .create, .unregister, .com_uninit } },
    };
    inline for (cases) |case| {
        var fake: Fake = .{ .fail = case[0] };
        try std.testing.expectEqual(case[1], shell.run(std.testing.allocator, &.{supplied}, fake.entropy(), &fake).code);
        try std.testing.expectEqualSlices(Event, case[2], fake.events[0..fake.count]);
    }
}

test "shell treats GetMessage minus one as error and zero as quit without dispatch" {
    for ([_]i32{ -1, 0 }) |status| {
        var fake: Fake = .{ .message_result = status };
        const result = shell.run(std.testing.allocator, &.{supplied}, fake.entropy(), &fake);
        try std.testing.expectEqual(if (status < 0) shell.ExitCode.message_failed else shell.ExitCode.success, result.code);
        try std.testing.expectEqualSlices(Event, &.{ .dll, .dpi, .com_init, .register, .create, .show, .get, .destroy, .unregister, .com_uninit }, fake.events[0..fake.count]);
    }
}

test "shell reports cleanup failures but preserves the first operational failure" {
    for ([_]Event{ .destroy, .unregister }) |fault| {
        var fake: Fake = .{ .cleanup_fail = fault };
        const expected = if (fault == .destroy) shell.ExitCode.window_cleanup_failed else shell.ExitCode.class_cleanup_failed;
        try std.testing.expectEqual(expected, shell.run(std.testing.allocator, &.{supplied}, fake.entropy(), &fake).code);
        try std.testing.expectEqual(Event.com_uninit, fake.events[fake.count - 1]);
        fake = .{ .message_result = -1, .cleanup_fail = fault };
        try std.testing.expectEqual(shell.ExitCode.message_failed, shell.run(std.testing.allocator, &.{supplied}, fake.entropy(), &fake).code);
        try std.testing.expectEqual(Event.com_uninit, fake.events[fake.count - 1]);
    }
}

fn exerciseAdmission(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{ .fail = .entropy };
    const result = try shell.admitWide(allocator, &.{supplied}, fake.entropy());
    try std.testing.expectEqual(entry.Origin.supplied, result.origin);
}

test "wide admission releases every allocation on every OOM boundary" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseAdmission, .{});
}

test "COM accepts S_OK and S_FALSE but rejects failing HRESULT values" {
    try std.testing.expect(com.succeeded(0));
    try std.testing.expect(com.succeeded(1));
    try std.testing.expect(!com.succeeded(@bitCast(@as(u32, 0x80010106))));
    try std.testing.expect(!com.succeeded(-1));
}
