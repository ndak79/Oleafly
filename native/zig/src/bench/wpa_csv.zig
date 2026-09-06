//! Strict fixture parser for a WPA-export-like event table.
const std = @import("std");
const events = @import("bench_events");

pub const Header = "TrialId,PID,AdapterLuid,TimestampQpc,Provider,EventName,PayloadHex,Lost";
pub const Row = struct {
    trial_id: [16]u8,
    process_id: u32,
    adapter_luid: u64,
    timestamp_qpc: u64,
    provider: []u8,
    event_name: []u8,
    payload: [64]u8,
    lost: bool,
};
pub const Table = struct {
    allocator: std.mem.Allocator,
    rows: []Row,
    pub fn deinit(self: *Table) void {
        for (self.rows) |row| {
            self.allocator.free(row.provider);
            self.allocator.free(row.event_name);
        }
        self.allocator.free(self.rows);
        self.* = undefined;
    }
};

fn hex(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}
fn parse_id(text: []const u8) ![16]u8 {
    if (text.len != 32) return error.InvalidTrialId;
    var id: [16]u8 = undefined;
    for (0..16) |i| {
        const hi = hex(text[i * 2]) orelse return error.InvalidTrialId;
        const lo = hex(text[i * 2 + 1]) orelse return error.InvalidTrialId;
        id[i] = (hi << 4) | lo;
    }
    var nonzero = false;
    for (id) |byte| nonzero = nonzero or byte != 0;
    if (!nonzero) return error.InvalidTrialId;
    return id;
}
fn parse_fields(line: []const u8, output: *[8][]const u8) !void {
    var count: usize = 0;
    var start: usize = 0;
    var quoted = false;
    var i: usize = 0;
    while (i <= line.len) : (i += 1) {
        const at_end = i == line.len;
        const byte = if (at_end) 0 else line[i];
        if (byte == '"') {
            if (i == start) {
                quoted = true;
                start += 1;
            } else if (quoted and (i + 1 == line.len or line[i + 1] == ',')) {
                quoted = false;
                if (count >= output.len) return error.InvalidNumber;
                output[count] = line[start..i];
                count += 1;
                if (i + 1 < line.len) {
                    start = i + 2;
                    i += 1;
                } else start = line.len + 1;
            } else return error.MalformedCsv;
        } else if (byte == ',' and !quoted) {
            if (count >= output.len) return error.InvalidNumber;
            output[count] = line[start..i];
            count += 1;
            start = i + 1;
        } else if (at_end) {
            if (start > line.len) break;
            if (quoted) return error.MalformedCsv;
            if (count >= output.len) return error.InvalidNumber;
            output[count] = line[start..i];
            count += 1;
        }
    }
    if (count != output.len) return error.MalformedCsv;
}
fn integer(comptime T: type, text: []const u8) !T {
    return std.fmt.parseInt(T, text, 10) catch error.InvalidNumber;
}
fn boolean(text: []const u8) !bool {
    if (std.mem.eql(u8, text, "0")) return false;
    if (std.mem.eql(u8, text, "1")) return true;
    return error.InvalidBoolean;
}
fn parse_payload(text: []const u8) ![64]u8 {
    if (text.len != 128) return error.InvalidPayload;
    var payload: [64]u8 = undefined;
    for (0..64) |i| {
        const hi = hex(text[i * 2]) orelse return error.InvalidPayload;
        const lo = hex(text[i * 2 + 1]) orelse return error.InvalidPayload;
        payload[i] = (hi << 4) | lo;
    }
    return payload;
}

pub fn parse(allocator: std.mem.Allocator, csv: []const u8) !Table {
    if (std.mem.startsWith(u8, csv, "\xef\xbb\xbf")) return error.BomNotAllowed;
    var lines = std.mem.splitScalar(u8, csv, '\n');
    const header = std.mem.trimEnd(u8, lines.next() orelse return error.InvalidHeader, "\r");
    if (!std.mem.eql(u8, header, Header)) return error.InvalidHeader;
    var rows: std.ArrayList(Row) = .empty;
    errdefer {
        for (rows.items) |row| {
            allocator.free(row.provider);
            allocator.free(row.event_name);
        }
        rows.deinit(allocator);
    }
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        var value: [8][]const u8 = undefined;
        try parse_fields(line, &value);
        const provider = try allocator.dupe(u8, value[4]);
        errdefer allocator.free(provider);
        const event_name = try allocator.dupe(u8, value[5]);
        errdefer allocator.free(event_name);
        try rows.append(allocator, .{
            .trial_id = try parse_id(value[0]),
            .process_id = try integer(u32, value[1]),
            .adapter_luid = try integer(u64, value[2]),
            .timestamp_qpc = try integer(u64, value[3]),
            .provider = provider,
            .event_name = event_name,
            .payload = try parse_payload(value[6]),
            .lost = try boolean(value[7]),
        });
    }
    return .{ .allocator = allocator, .rows = try rows.toOwnedSlice(allocator) };
}

pub const Expected = struct { trial_id: [16]u8, process_id: u32, adapter_luid: u64 };
pub const ValidateError = error{ Empty, MixedTrial, MixedProcess, MixedAdapter, TimestampDiscontinuity, LostSample, InvalidProvider, InvalidEventName, PayloadMetadataMismatch };

pub fn validate(rows: []const Row, expected: Expected) ValidateError!void {
    if (rows.len == 0) return error.Empty;
    var previous: ?u64 = null;
    for (rows) |row| {
        if (!std.mem.eql(u8, &row.trial_id, &expected.trial_id)) return error.MixedTrial;
        if (row.process_id != expected.process_id) return error.MixedProcess;
        if (row.adapter_luid != expected.adapter_luid) return error.MixedAdapter;
        if (previous) |qpc| if (row.timestamp_qpc <= qpc) return error.TimestampDiscontinuity;
        if (row.lost) return error.LostSample;
        if (!std.mem.eql(u8, row.provider, "texflow")) return error.InvalidProvider;
        if (!std.mem.eql(u8, row.event_name, "render")) return error.InvalidEventName;
        const event = events.parse(&row.payload) catch return error.PayloadMetadataMismatch;
        if (!std.mem.eql(u8, &event.trial_id, &row.trial_id) or event.process_id != row.process_id or event.adapter_luid != row.adapter_luid or event.qpc != row.timestamp_qpc) return error.PayloadMetadataMismatch;
        previous = row.timestamp_qpc;
    }
}
