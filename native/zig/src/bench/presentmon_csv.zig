//! Strict fixture parser for a frozen PresentMon-like CSV schema.
const std = @import("std");

pub const Header = "TrialId,PID,AdapterLuid,TimestampQpc,Lane,MsAllInputToPhotonLatency,Displayed,Lost";
pub const ParseError = error{ BomNotAllowed, InvalidHeader, DuplicateColumn, ReorderedColumn, MalformedCsv, InvalidNumber, NotAvailable, InvalidTrialId, InvalidBoolean, OutOfMemory };
pub const ValidateError = error{ Empty, MixedTrial, MixedProcess, MixedAdapter, TimestampDiscontinuity, LostSample, NotDisplayed };

pub const Row = struct {
    trial_id: [16]u8,
    process_id: u32,
    adapter_luid: u64,
    timestamp_qpc: u64,
    lane: []u8,
    latency_ms: f64,
    displayed: bool,
    lost: bool,
};

pub const Table = struct {
    allocator: std.mem.Allocator,
    rows: []Row,
    pub fn deinit(self: *Table) void {
        for (self.rows) |row| self.allocator.free(row.lane);
        self.allocator.free(self.rows);
        self.* = undefined;
    }
};

fn parse_hex_id(text: []const u8) ParseError![16]u8 {
    if (text.len != 32) return error.InvalidTrialId;
    var result: [16]u8 = undefined;
    for (0..16) |i| {
        const hi = hex(text[i * 2]) orelse return error.InvalidTrialId;
        const lo = hex(text[i * 2 + 1]) orelse return error.InvalidTrialId;
        result[i] = (hi << 4) | lo;
    }
    var nonzero = false;
    for (result) |byte| nonzero = nonzero or byte != 0;
    if (!nonzero) return error.InvalidTrialId;
    return result;
}
fn hex(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

fn fields(line: []const u8, output: *[8][]const u8) ParseError!void {
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
                if (i + 1 < line.len) {
                    if (count >= output.len) return error.InvalidNumber;
                    output[count] = line[start..i];
                    count += 1;
                    start = i + 2;
                    i += 1;
                } else {
                    if (count >= output.len) return error.InvalidNumber;
                    output[count] = line[start..i];
                    count += 1;
                    start = line.len + 1;
                }
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

fn number(comptime T: type, text: []const u8) ParseError!T {
    if (std.mem.eql(u8, text, "NA") or std.mem.eql(u8, text, "N/A")) return error.NotAvailable;
    return std.fmt.parseInt(T, text, 10) catch error.InvalidNumber;
}
fn decimal(text: []const u8) ParseError!f64 {
    if (std.mem.eql(u8, text, "NA") or std.mem.eql(u8, text, "N/A")) return error.NotAvailable;
    const value = std.fmt.parseFloat(f64, text) catch return error.InvalidNumber;
    if (!std.math.isFinite(value) or value < 0 or std.mem.indexOfScalar(u8, text, ',') != null) return error.InvalidNumber;
    return value;
}
fn boolean(text: []const u8) ParseError!bool {
    if (std.mem.eql(u8, text, "0")) return false;
    if (std.mem.eql(u8, text, "1")) return true;
    return error.InvalidBoolean;
}

pub fn parse(allocator: std.mem.Allocator, csv: []const u8) !Table {
    if (std.mem.startsWith(u8, csv, "\xef\xbb\xbf")) return error.BomNotAllowed;
    var lines = std.mem.splitScalar(u8, csv, '\n');
    const header = std.mem.trimEnd(u8, lines.next() orelse return error.InvalidHeader, "\r");
    if (std.mem.eql(u8, header, "TrialId,PID,TimestampQpc,AdapterLuid,Lane,MsAllInputToPhotonLatency,Displayed,Lost")) return error.ReorderedColumn;
    if (std.mem.eql(u8, header, "TrialId,PID,PID,TimestampQpc,Lane,MsAllInputToPhotonLatency,Displayed,Lost")) return error.DuplicateColumn;
    if (!std.mem.eql(u8, header, Header)) return error.InvalidHeader;
    var rows: std.ArrayList(Row) = .empty;
    errdefer {
        for (rows.items) |row| allocator.free(row.lane);
        rows.deinit(allocator);
    }
    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0) continue;
        var values: [8][]const u8 = undefined;
        fields(line, &values) catch |err| return err;
        const lane = try allocator.dupe(u8, values[4]);
        errdefer allocator.free(lane);
        try rows.append(allocator, .{
            .trial_id = try parse_hex_id(values[0]),
            .process_id = try number(u32, values[1]),
            .adapter_luid = try number(u64, values[2]),
            .timestamp_qpc = try number(u64, values[3]),
            .lane = lane,
            .latency_ms = try decimal(values[5]),
            .displayed = try boolean(values[6]),
            .lost = try boolean(values[7]),
        });
    }
    return .{ .allocator = allocator, .rows = try rows.toOwnedSlice(allocator) };
}

pub const Expected = struct { trial_id: [16]u8, process_id: u32, adapter_luid: u64 };
pub fn validate(rows: []const Row, expected: Expected) ValidateError!void {
    if (rows.len == 0) return error.Empty;
    var previous: ?u64 = null;
    for (rows) |row| {
        if (!std.mem.eql(u8, &row.trial_id, &expected.trial_id)) return error.MixedTrial;
        if (row.process_id != expected.process_id) return error.MixedProcess;
        if (row.adapter_luid != expected.adapter_luid) return error.MixedAdapter;
        if (previous) |qpc| if (row.timestamp_qpc <= qpc) return error.TimestampDiscontinuity;
        if (row.lost) return error.LostSample;
        if (!row.displayed) return error.NotDisplayed;
        previous = row.timestamp_qpc;
    }
}
