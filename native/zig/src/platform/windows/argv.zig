const std = @import("std");

// CreateProcessW's 32767 UTF-16 code-unit limit includes the terminating NUL.
pub const max_command_line_units = 32766;
// Deliberate bounded launch-contract budget, not the Unicode Windows OS limit.
pub const max_environment_units = 32766;
pub const EnvironmentVariable = struct { name: []const u8, value: []const u8 };
pub const Options = struct {
    /// Canonical absolute executable selected and identity-checked by the caller.
    /// This module validates spelling; it does not open or authenticate files.
    application_path: ?[]const u8,
    /// Excludes argv[0], which is always the exact application path.
    arguments: []const []const u8,
    current_directory: []const u8,
    /// Only these variables are present. Empty means an empty double-NUL block,
    /// never a null pointer that would inherit the parent environment.
    environment: []const EnvironmentVariable,
};

pub const Prepared = struct {
    application_name: [:0]u16,
    command_line: [:0]u16,
    current_directory: [:0]u16,
    environment: [:0]u16,

    pub fn deinit(self: *Prepared, allocator: std.mem.Allocator) void {
        allocator.free(self.application_name);
        allocator.free(self.command_line);
        allocator.free(self.current_directory);
        allocator.free(self.environment);
        self.* = undefined;
    }
};

pub fn prepare(allocator: std.mem.Allocator, options: Options) !Prepared {
    const application = options.application_path orelse return error.MissingApplicationPath;
    const application_units = try textLength(application);
    if (application_units > max_command_line_units - 2) return error.CommandLineTooLong;
    _ = try textLength(options.current_directory);
    if (!safeAbsolutePath(application, true)) return error.UnsafeApplicationPath;
    if (!safeAbsolutePath(options.current_directory, false)) return error.UnsafeCurrentDirectory;

    const application_name = try std.unicode.utf8ToUtf16LeAllocZ(allocator, application);
    errdefer allocator.free(application_name);
    const current_directory = try std.unicode.utf8ToUtf16LeAllocZ(allocator, options.current_directory);
    errdefer allocator.free(current_directory);

    var line: std.ArrayList(u16) = .empty;
    defer line.deinit(allocator);
    // argv[0] uses the CRT's special executable-name rules. Its validated path
    // cannot contain quotes or end in a backslash, so quoting it is unambiguous.
    try appendUnits(&line, allocator, '"', 1);
    try line.appendSlice(allocator, application_name);
    try appendUnits(&line, allocator, '"', 1);
    for (options.arguments) |argument| {
        _ = try textLength(argument);
        const wide = try std.unicode.utf8ToUtf16LeAlloc(allocator, argument);
        defer allocator.free(wide);
        try appendUnits(&line, allocator, ' ', 1);
        try appendUnits(&line, allocator, '"', 1);
        var slashes: usize = 0;
        for (wide) |unit| {
            if (unit == '\\') {
                slashes += 1;
                continue;
            }
            // Before a literal quote: 2n+1 slashes. Else: preserve n slashes.
            try appendUnits(&line, allocator, '\\', if (unit == '"') slashes * 2 + 1 else slashes);
            try appendUnits(&line, allocator, unit, 1);
            slashes = 0;
        }
        // Trailing slashes precede the closing quote and must be doubled.
        try appendUnits(&line, allocator, '\\', slashes * 2);
        try appendUnits(&line, allocator, '"', 1);
    }
    const command_line = try line.toOwnedSliceSentinel(allocator, 0);
    errdefer allocator.free(command_line);
    const environment = try environmentBlock(allocator, options.environment);
    return .{
        .application_name = application_name,
        .command_line = command_line,
        .current_directory = current_directory,
        .environment = environment,
    };
}

fn textLength(text: []const u8) !usize {
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.EmbeddedNul;
    const length = std.unicode.calcUtf16LeLen(text) catch return error.InvalidUtf8;
    if (length > max_command_line_units) return error.CommandLineTooLong;
    return length;
}

fn appendUnits(line: *std.ArrayList(u16), allocator: std.mem.Allocator, unit: u16, count: usize) !void {
    if (count > max_command_line_units - line.items.len) return error.CommandLineTooLong;
    try line.appendNTimes(allocator, unit, count);
}

fn safeAbsolutePath(path: []const u8, executable: bool) bool {
    if (path.len < 3) return false;
    var start: usize = undefined;
    var required_components: usize = 0;
    if (std.ascii.isAlphabetic(path[0]) and path[1] == ':' and path[2] == '\\') {
        start = 3;
        required_components = if (executable) 1 else 0;
    } else if (std.mem.startsWith(u8, path, "\\\\")) {
        start = 2;
        required_components = if (executable) 3 else 2; // server, share, image
    } else return false;
    for (path[start..]) |byte| {
        if (byte < 32 or std.mem.indexOfScalar(u8, "/\":<>|?*", byte) != null) return false;
    }
    var components = std.mem.splitScalar(u8, path[start..], '\\');
    var count: usize = 0;
    var basename: []const u8 = "";
    while (components.next()) |component| {
        if (component.len == 0) {
            if (!executable and components.peek() == null) break;
            return false;
        }
        const last = component[component.len - 1];
        if (last == '.' or last == ' ') return false;
        if (reservedDevice(component)) return false;
        count += 1;
        basename = component;
    }
    if (count < required_components) return false;
    if (executable) {
        if (basename.len < 5 or !std.ascii.eqlIgnoreCase(basename[basename.len - 4 ..], ".exe")) return false;
        for ([_][]const u8{ "cmd.exe", "powershell.exe", "pwsh.exe" }) |shell| {
            if (std.ascii.eqlIgnoreCase(basename, shell)) return false;
        }
    }
    return true;
}

fn reservedDevice(component: []const u8) bool {
    const end = std.mem.indexOfScalar(u8, component, '.') orelse component.len;
    const stem = std.mem.trimEnd(u8, component[0..end], " ");
    for ([_][]const u8{ "CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$" }) |device| {
        if (std.ascii.eqlIgnoreCase(stem, device)) return true;
    }
    if (stem.len < 4) return false;
    if (!std.ascii.eqlIgnoreCase(stem[0..3], "COM") and !std.ascii.eqlIgnoreCase(stem[0..3], "LPT")) return false;
    const number = stem[3..];
    if (number.len == 1 and number[0] >= '1' and number[0] <= '9') return true;
    for ([_][]const u8{ "\u{b9}", "\u{b2}", "\u{b3}" }) |superscript| {
        if (std.mem.eql(u8, number, superscript)) return true;
    }
    return false;
}

fn environmentLessThan(_: void, a: EnvironmentVariable, b: EnvironmentVariable) bool {
    // Windows uses uppercase ordinal ordering. Lowercase folding would put
    // punctuation such as '_' before 'Z'. Names are validated as ASCII, so
    // uppercase only letters and compare every other byte unchanged.
    const common_length = @min(a.name.len, b.name.len);
    for (a.name[0..common_length], b.name[0..common_length]) |a_byte, b_byte| {
        const left = std.ascii.toUpper(a_byte);
        const right = std.ascii.toUpper(b_byte);
        if (left != right) return left < right;
    }
    return a.name.len < b.name.len;
}

fn environmentBlock(allocator: std.mem.Allocator, variables: []const EnvironmentVariable) ![:0]u16 {
    const sorted = try allocator.dupe(EnvironmentVariable, variables);
    defer allocator.free(sorted);
    var required: usize = 1; // final NUL, in addition to the final entry's NUL
    for (sorted) |variable| {
        if (variable.name.len == 0) return error.InvalidEnvironmentName;
        for (variable.name) |byte| {
            // ASCII names make Windows' case-insensitive ordering unambiguous.
            // Values remain unrestricted valid UTF-8, excluding embedded NUL.
            if (byte < 33 or byte > 126 or byte == '=') return error.InvalidEnvironmentName;
        }
        const value_units = try textLength(variable.value);
        if (variable.name.len > max_environment_units - required) return error.EnvironmentTooLong;
        required += variable.name.len;
        if (value_units + 2 > max_environment_units - required) return error.EnvironmentTooLong;
        required += value_units + 2; // '=' and entry NUL
    }
    std.mem.sort(EnvironmentVariable, sorted, {}, environmentLessThan);
    for (sorted, 0..) |variable, index| {
        if (index != 0 and std.ascii.eqlIgnoreCase(sorted[index - 1].name, variable.name)) return error.DuplicateEnvironmentName;
    }
    var result: std.ArrayList(u16) = .empty;
    defer result.deinit(allocator);
    for (sorted) |variable| {
        for (variable.name) |byte| try result.append(allocator, byte);
        try result.append(allocator, '=');
        const value = try std.unicode.utf8ToUtf16LeAlloc(allocator, variable.value);
        defer allocator.free(value);
        try result.appendSlice(allocator, value);
        try result.append(allocator, 0);
    }
    if (sorted.len == 0) try result.append(allocator, 0);
    return result.toOwnedSliceSentinel(allocator, 0);
}
