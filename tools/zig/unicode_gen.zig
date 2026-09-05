const std = @import("std");

const SourceLock = struct {
    path: []const u8,
    size: usize,
    sha256: []const u8,
};

const SourceSnapshot = struct {
    const Entry = struct {
        path: []const u8,
        bytes: []u8,
    };

    allocator: std.mem.Allocator,
    entries: []Entry,

    fn deinit(self: *SourceSnapshot) void {
        for (self.entries) |entry| self.allocator.free(entry.bytes);
        self.allocator.free(self.entries);
        self.* = undefined;
    }

    fn get(self: *const SourceSnapshot, path: []const u8) ![]const u8 {
        for (self.entries) |entry| {
            if (std.mem.eql(u8, entry.path, path)) return entry.bytes;
        }
        return error.MissingUnicodeMember;
    }
};

const source_locks = [_]SourceLock{
    .{ .path = "ReadMe.txt", .size = 740, .sha256 = "9fe1a90bd32659d7953616283dc2bffaa165518aae9ace026040c42c559ba606" },
    .{ .path = "UnicodeData.txt", .size = 2_198_209, .sha256 = "2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c" },
    .{ .path = "CaseFolding.txt", .size = 87_539, .sha256 = "ff8d8fefbf123574205085d6714c36149eb946d717a0c585c27f0f4ef58c4183" },
    .{ .path = "DerivedCoreProperties.txt", .size = 1_134_783, .sha256 = "24c7fed1195c482faaefd5c1e7eb821c5ee1fb6de07ecdbaa64b56a99da22c08" },
    .{ .path = "DerivedNormalizationProps.txt", .size = 1_377_582, .sha256 = "71fd6a206a2c0cdd41feb6b7f656aa31091db45e9cedc926985d718397f9e488" },
    .{ .path = "CompositionExclusions.txt", .size = 9_007, .sha256 = "2f239196ef3b5b61db5cc476e9bd80f534d15aa1b74e1be1dea5d042a344c85f" },
    .{ .path = "NormalizationTest.txt", .size = 2_827_429, .sha256 = "5019ffd530751a741900c849c0e010332f142a3612234639bd200b82138a87db" },
    .{ .path = "auxiliary/GraphemeBreakProperty.txt", .size = 99_377, .sha256 = "d6b51d1d2ae5c33b451b7ed994b48f1f4dc62b2272a5831e7fd418514a6bae89" },
    .{ .path = "auxiliary/GraphemeBreakTest.txt", .size = 126_570, .sha256 = "e2d134d2c52919bace503ebb6a551c1855fe1a1faec18478c78fff254a1793ec" },
    .{ .path = "auxiliary/WordBreakProperty.txt", .size = 114_445, .sha256 = "72274cac1e6b919507db35655c3e175aa27274668a1ece95c28d2069f2ad9852" },
    .{ .path = "auxiliary/WordBreakTest.txt", .size = 322_136, .sha256 = "1de23a75f37904abc7d206239ee8d34f8fdf0fb4ab32a7174dfbabbde25419b2" },
    .{ .path = "emoji/emoji-data.txt", .size = 107_324, .sha256 = "2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b" },
};

const MapEntry = struct {
    codepoint: u21,
    offset: u32,
    length: u8,
};

const CccEntry = struct {
    codepoint: u21,
    value: u8,
};

const Range = struct {
    start: u21,
    end: u21,
    value: u8,
};

const Composition = struct {
    starter: u21,
    combining: u21,
    composite: u21,
};

const GraphemeProperty = enum(u8) {
    other,
    cr,
    lf,
    control,
    extend,
    zwj,
    regional_indicator,
    prepend,
    spacing_mark,
    l,
    v,
    t,
    lv,
    lvt,
};

const WordProperty = enum(u8) {
    other,
    cr,
    lf,
    newline,
    extend,
    format,
    zwj,
    regional_indicator,
    katakana,
    hebrew_letter,
    aletter,
    single_quote,
    double_quote,
    midnumlet,
    midletter,
    midnum,
    numeric,
    extendnumlet,
    wsegspace,
};

const InCbProperty = enum(u8) {
    none,
    consonant,
    linker,
    extend,
};

const Tables = struct {
    decomposition: std.ArrayList(MapEntry) = .empty,
    decomposition_values: std.ArrayList(u21) = .empty,
    case_folding: std.ArrayList(MapEntry) = .empty,
    case_folding_values: std.ArrayList(u21) = .empty,
    ccc: std.ArrayList(CccEntry) = .empty,
    compositions: std.ArrayList(Composition) = .empty,
    grapheme: std.ArrayList(Range) = .empty,
    word: std.ArrayList(Range) = .empty,
    incb: std.ArrayList(Range) = .empty,
    extended_pictographic: std.ArrayList(Range) = .empty,
    letter_or_number: std.ArrayList(Range) = .empty,

    fn deinit(self: *Tables, allocator: std.mem.Allocator) void {
        self.decomposition.deinit(allocator);
        self.decomposition_values.deinit(allocator);
        self.case_folding.deinit(allocator);
        self.case_folding_values.deinit(allocator);
        self.ccc.deinit(allocator);
        self.compositions.deinit(allocator);
        self.grapheme.deinit(allocator);
        self.word.deinit(allocator);
        self.incb.deinit(allocator);
        self.extended_pictographic.deinit(allocator);
        self.letter_or_number.deinit(allocator);
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.InvalidArguments;
    if (std.mem.eql(u8, args[1], "generate")) {
        if (args.len != 4) return error.InvalidArguments;
        const output = try generate(allocator, init.io, args[2]);
        defer allocator.free(output);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[3], .data = output });
        return;
    }
    if (std.mem.eql(u8, args[1], "compare")) {
        if (args.len != 5) return error.InvalidArguments;
        try compareGenerated(allocator, init.io, args[2], args[3], args[4]);
        return;
    }
    return error.InvalidArguments;
}

fn generate(allocator: std.mem.Allocator, io: std.Io, root: []const u8) ![]u8 {
    var sources = try loadLockedSources(allocator, io, root, &source_locks);
    defer sources.deinit();
    const readme = try sources.get("ReadMe.txt");
    if (std.mem.indexOf(u8, readme, "Version 17.0.0") == null or
        std.mem.indexOf(u8, readme, "2025-08-15") == null)
    {
        return error.WrongUnicodeVersion;
    }

    return generateFromSnapshot(allocator, &sources);
}

fn generateFromSnapshot(allocator: std.mem.Allocator, sources: *const SourceSnapshot) ![]u8 {
    var tables: Tables = .{};
    defer tables.deinit(allocator);

    const exclusions = try parseCompositionExclusions(
        allocator,
        try sources.get("CompositionExclusions.txt"),
    );
    defer allocator.free(exclusions);
    try parseUnicodeData(
        allocator,
        try sources.get("UnicodeData.txt"),
        exclusions,
        &tables,
    );
    try parseCaseFolding(allocator, try sources.get("CaseFolding.txt"), &tables);
    try parseBreakProperties(
        allocator,
        try sources.get("auxiliary/GraphemeBreakProperty.txt"),
        try sources.get("auxiliary/WordBreakProperty.txt"),
        &tables,
    );
    try parseInCb(allocator, try sources.get("DerivedCoreProperties.txt"), &tables);
    try parseEmojiProperties(allocator, try sources.get("emoji/emoji-data.txt"), &tables);

    try sortAndMergeRanges(&tables.grapheme);
    try sortAndMergeRanges(&tables.word);
    try sortAndMergeRanges(&tables.incb);
    try sortAndMergeRanges(&tables.extended_pictographic);
    try sortAndMergeRanges(&tables.letter_or_number);
    std.mem.sort(Composition, tables.compositions.items, {}, lessComposition);
    if (tables.compositions.items.len > 1) {
        for (tables.compositions.items[1..], tables.compositions.items[0 .. tables.compositions.items.len - 1]) |current, previous| {
            if (current.starter == previous.starter and current.combining == previous.combining) {
                return error.DuplicateComposition;
            }
        }
    }

    return emitModule(allocator, &tables);
}

fn loadLockedSources(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    locks: []const SourceLock,
) !SourceSnapshot {
    const entries = try allocator.alloc(SourceSnapshot.Entry, locks.len);
    errdefer allocator.free(entries);
    var initialized: usize = 0;
    errdefer for (entries[0..initialized]) |entry| allocator.free(entry.bytes);

    for (locks, 0..) |lock, index| {
        for (locks[0..index]) |previous| {
            if (std.mem.eql(u8, previous.path, lock.path)) {
                return error.InvalidUnicodeMemberLock;
            }
        }
        const bytes = try readSource(allocator, io, root, lock.path, lock.size);
        errdefer allocator.free(bytes);
        if (bytes.len != lock.size) return error.UnicodeMemberSizeMismatch;
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        var expected: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&expected, lock.sha256) catch
            return error.InvalidUnicodeMemberLock;
        if (!std.mem.eql(u8, &digest, &expected)) return error.UnicodeMemberHashMismatch;
        entries[index] = .{ .path = lock.path, .bytes = bytes };
        initialized += 1;
    }
    return .{ .allocator = allocator, .entries = entries };
}

fn readSource(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    relative: []const u8,
    limit: usize,
) ![]u8 {
    const path = try std.fs.path.join(allocator, &.{ root, relative });
    defer allocator.free(path);
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(limit + 1));
}

fn parseCompositionExclusions(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) ![]Range {
    var exclusions: std.ArrayList(Range) = .empty;
    errdefer exclusions.deinit(allocator);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const line = contentBeforeComment(raw_line);
        if (line.len == 0) continue;
        const codepoints = try parseCodepointRange(line);
        try exclusions.append(allocator, .{ .start = codepoints.start, .end = codepoints.end, .value = 1 });
    }
    try sortAndMergeRanges(&exclusions);
    return exclusions.toOwnedSlice(allocator);
}

fn parseUnicodeData(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    exclusions: []const Range,
    tables: *Tables,
) !void {
    const PendingRange = struct { start: u21, category: []const u8 };
    var pending: ?PendingRange = null;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        var fields: [15][]const u8 = undefined;
        var field_count: usize = 0;
        var field_it = std.mem.splitScalar(u8, line, ';');
        while (field_it.next()) |field| {
            if (field_count >= fields.len) return error.InvalidUnicodeData;
            fields[field_count] = field;
            field_count += 1;
        }
        if (field_count != fields.len) return error.InvalidUnicodeData;
        const codepoint = try parseCodepoint(fields[0]);
        const name = fields[1];
        const category = fields[2];
        if (std.mem.endsWith(u8, name, ", First>")) {
            if (pending != null) return error.InvalidUnicodeDataRange;
            pending = .{ .start = codepoint, .category = category };
            continue;
        }
        if (std.mem.endsWith(u8, name, ", Last>")) {
            const first = pending orelse return error.InvalidUnicodeDataRange;
            if (codepoint < first.start or !std.mem.eql(u8, category, first.category)) {
                return error.InvalidUnicodeDataRange;
            }
            if (isLetterOrNumberCategory(category)) {
                try tables.letter_or_number.append(allocator, .{
                    .start = first.start,
                    .end = codepoint,
                    .value = 1,
                });
            }
            pending = null;
            continue;
        }
        if (pending != null) return error.InvalidUnicodeDataRange;
        if (isLetterOrNumberCategory(category)) {
            try tables.letter_or_number.append(allocator, .{
                .start = codepoint,
                .end = codepoint,
                .value = 1,
            });
        }

        const ccc_value = try std.fmt.parseInt(u8, fields[3], 10);
        if (ccc_value != 0) {
            try tables.ccc.append(allocator, .{ .codepoint = codepoint, .value = ccc_value });
        }

        const decomposition = std.mem.trim(u8, fields[5], " \t");
        if (decomposition.len == 0 or decomposition[0] == '<') continue;
        const offset: u32 = @intCast(tables.decomposition_values.items.len);
        const length = try appendCodepointSequence(
            allocator,
            &tables.decomposition_values,
            decomposition,
        );
        if (length == 0 or length > 4) return error.InvalidCanonicalDecomposition;
        try tables.decomposition.append(allocator, .{
            .codepoint = codepoint,
            .offset = offset,
            .length = length,
        });
        if (length == 2 and !rangeContains(exclusions, codepoint)) {
            try tables.compositions.append(allocator, .{
                .starter = tables.decomposition_values.items[offset],
                .combining = tables.decomposition_values.items[offset + 1],
                .composite = codepoint,
            });
        }
    }
    if (pending != null) return error.InvalidUnicodeDataRange;
}

fn parseCaseFolding(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    tables: *Tables,
) !void {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const line = contentBeforeComment(raw_line);
        if (line.len == 0) continue;
        var it = std.mem.splitScalar(u8, line, ';');
        const fields = [3][]const u8{
            std.mem.trim(u8, it.next() orelse return error.InvalidCaseFolding, " \t"),
            std.mem.trim(u8, it.next() orelse return error.InvalidCaseFolding, " \t"),
            std.mem.trim(u8, it.next() orelse return error.InvalidCaseFolding, " \t"),
        };
        if (it.next()) |trailer| {
            if (std.mem.trim(u8, trailer, " \t").len != 0 or it.next() != null) {
                return error.InvalidCaseFolding;
            }
        }
        if (fields[1].len != 1 or std.mem.indexOfScalar(u8, "CFST", fields[1][0]) == null) {
            return error.UnknownCaseFoldingStatus;
        }
        if (fields[1][0] == 'S' or fields[1][0] == 'T') continue;
        const codepoint = try parseCodepoint(fields[0]);
        const offset: u32 = @intCast(tables.case_folding_values.items.len);
        const length = try appendCodepointSequence(
            allocator,
            &tables.case_folding_values,
            fields[2],
        );
        if (length == 0 or length > 3) return error.InvalidCaseFolding;
        try tables.case_folding.append(allocator, .{
            .codepoint = codepoint,
            .offset = offset,
            .length = length,
        });
    }
}

fn parseBreakProperties(
    allocator: std.mem.Allocator,
    grapheme_bytes: []const u8,
    word_bytes: []const u8,
    tables: *Tables,
) !void {
    var grapheme_lines = std.mem.splitScalar(u8, grapheme_bytes, '\n');
    while (grapheme_lines.next()) |line| {
        if (try parseGraphemePropertyLine(line)) |range| {
            try tables.grapheme.append(allocator, range);
        }
    }

    var word_lines = std.mem.splitScalar(u8, word_bytes, '\n');
    while (word_lines.next()) |line| {
        if (try parseWordPropertyLine(line)) |range| {
            try tables.word.append(allocator, range);
        }
    }
}

fn parseGraphemePropertyLine(raw_line: []const u8) !?Range {
    const fields = (try parseTwoFieldProperty(raw_line)) orelse return null;
    const property: GraphemeProperty = if (std.mem.eql(u8, fields.property, "CR")) .cr else if (std.mem.eql(u8, fields.property, "LF")) .lf else if (std.mem.eql(u8, fields.property, "Control")) .control else if (std.mem.eql(u8, fields.property, "Extend")) .extend else if (std.mem.eql(u8, fields.property, "ZWJ")) .zwj else if (std.mem.eql(u8, fields.property, "Regional_Indicator")) .regional_indicator else if (std.mem.eql(u8, fields.property, "Prepend")) .prepend else if (std.mem.eql(u8, fields.property, "SpacingMark")) .spacing_mark else if (std.mem.eql(u8, fields.property, "L")) .l else if (std.mem.eql(u8, fields.property, "V")) .v else if (std.mem.eql(u8, fields.property, "T")) .t else if (std.mem.eql(u8, fields.property, "LV")) .lv else if (std.mem.eql(u8, fields.property, "LVT")) .lvt else return error.UnknownGraphemeProperty;
    return .{ .start = fields.range.start, .end = fields.range.end, .value = @intFromEnum(property) };
}

fn parseWordPropertyLine(raw_line: []const u8) !?Range {
    const fields = (try parseTwoFieldProperty(raw_line)) orelse return null;
    const property: WordProperty = if (std.mem.eql(u8, fields.property, "CR")) .cr else if (std.mem.eql(u8, fields.property, "LF")) .lf else if (std.mem.eql(u8, fields.property, "Newline")) .newline else if (std.mem.eql(u8, fields.property, "Extend")) .extend else if (std.mem.eql(u8, fields.property, "Format")) .format else if (std.mem.eql(u8, fields.property, "ZWJ")) .zwj else if (std.mem.eql(u8, fields.property, "Regional_Indicator")) .regional_indicator else if (std.mem.eql(u8, fields.property, "Katakana")) .katakana else if (std.mem.eql(u8, fields.property, "Hebrew_Letter")) .hebrew_letter else if (std.mem.eql(u8, fields.property, "ALetter")) .aletter else if (std.mem.eql(u8, fields.property, "Single_Quote")) .single_quote else if (std.mem.eql(u8, fields.property, "Double_Quote")) .double_quote else if (std.mem.eql(u8, fields.property, "MidNumLet")) .midnumlet else if (std.mem.eql(u8, fields.property, "MidLetter")) .midletter else if (std.mem.eql(u8, fields.property, "MidNum")) .midnum else if (std.mem.eql(u8, fields.property, "Numeric")) .numeric else if (std.mem.eql(u8, fields.property, "ExtendNumLet")) .extendnumlet else if (std.mem.eql(u8, fields.property, "WSegSpace")) .wsegspace else return error.UnknownWordProperty;
    return .{ .start = fields.range.start, .end = fields.range.end, .value = @intFromEnum(property) };
}

const PropertyFields = struct { range: CodepointRange, property: []const u8 };

fn parseTwoFieldProperty(raw_line: []const u8) !?PropertyFields {
    const line = contentBeforeComment(raw_line);
    if (line.len == 0) return null;
    var it = std.mem.splitScalar(u8, line, ';');
    const range_text = it.next() orelse return error.InvalidUnicodePropertyLine;
    const property = it.next() orelse return error.InvalidUnicodePropertyLine;
    if (it.next() != null) return error.InvalidUnicodePropertyLine;
    return .{
        .range = try parseCodepointRange(range_text),
        .property = std.mem.trim(u8, property, " \t"),
    };
}

fn parseInCb(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    tables: *Tables,
) !void {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const line = contentBeforeComment(raw_line);
        if (line.len == 0) continue;
        var it = std.mem.splitScalar(u8, line, ';');
        const range_text = it.next() orelse continue;
        const property = std.mem.trim(u8, it.next() orelse continue, " \t");
        if (!std.mem.eql(u8, property, "InCB")) continue;
        const value = std.mem.trim(u8, it.next() orelse return error.InvalidInCbProperty, " \t");
        if (it.next() != null) return error.InvalidInCbProperty;
        const parsed_value: InCbProperty = if (std.mem.eql(u8, value, "Consonant")) .consonant else if (std.mem.eql(u8, value, "Linker")) .linker else if (std.mem.eql(u8, value, "Extend")) .extend else return error.UnknownInCbProperty;
        const range = try parseCodepointRange(range_text);
        try tables.incb.append(allocator, .{
            .start = range.start,
            .end = range.end,
            .value = @intFromEnum(parsed_value),
        });
    }
}

fn parseEmojiProperties(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    tables: *Tables,
) !void {
    const known = [_][]const u8{
        "Emoji",           "Emoji_Presentation",    "Emoji_Modifier", "Emoji_Modifier_Base",
        "Emoji_Component", "Extended_Pictographic",
    };
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const fields = (try parseTwoFieldProperty(raw_line)) orelse continue;
        var recognized = false;
        for (known) |property| {
            if (std.mem.eql(u8, fields.property, property)) {
                recognized = true;
                break;
            }
        }
        if (!recognized) return error.UnknownEmojiProperty;
        if (std.mem.eql(u8, fields.property, "Extended_Pictographic")) {
            try tables.extended_pictographic.append(allocator, .{
                .start = fields.range.start,
                .end = fields.range.end,
                .value = 1,
            });
        }
    }
}

const CodepointRange = struct { start: u21, end: u21 };

fn parseCodepointRange(raw: []const u8) !CodepointRange {
    const text = std.mem.trim(u8, raw, " \t\r");
    if (std.mem.indexOf(u8, text, "..")) |separator| {
        const start = try parseCodepoint(text[0..separator]);
        const end = try parseCodepoint(text[separator + 2 ..]);
        if (start > end) return error.InvalidCodepointRange;
        return .{ .start = start, .end = end };
    }
    const codepoint = try parseCodepoint(text);
    return .{ .start = codepoint, .end = codepoint };
}

fn parseCodepoint(raw: []const u8) !u21 {
    const text = std.mem.trim(u8, raw, " \t\r");
    if (text.len == 0 or text.len > 6) return error.InvalidCodepoint;
    const value = std.fmt.parseInt(u21, text, 16) catch return error.InvalidCodepoint;
    // UCD property ranges include surrogate code points even though valid
    // UTF-8 input never can. Keep them in source-table parsing and reject
    // surrogate scalars at the UTF-8 runtime boundary instead.
    if (value > 0x10ffff) return error.InvalidCodepoint;
    return value;
}

fn appendCodepointSequence(
    allocator: std.mem.Allocator,
    destination: *std.ArrayList(u21),
    raw: []const u8,
) !u8 {
    const before = destination.items.len;
    var it = std.mem.tokenizeAny(u8, raw, " \t");
    while (it.next()) |item| try destination.append(allocator, try parseCodepoint(item));
    return @intCast(destination.items.len - before);
}

fn contentBeforeComment(raw_line: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, raw_line, '#') orelse raw_line.len;
    return std.mem.trim(u8, raw_line[0..end], " \t\r");
}

fn isLetterOrNumberCategory(category: []const u8) bool {
    return category.len == 2 and (category[0] == 'L' or category[0] == 'N');
}

fn rangeContains(ranges: []const Range, codepoint: u21) bool {
    var low: usize = 0;
    var high = ranges.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const range = ranges[middle];
        if (codepoint < range.start) high = middle else if (codepoint > range.end) low = middle + 1 else return true;
    }
    return false;
}

fn sortAndMergeRanges(ranges: *std.ArrayList(Range)) !void {
    if (ranges.items.len == 0) return;
    std.mem.sort(Range, ranges.items, {}, lessRange);
    var write: usize = 1;
    for (ranges.items[1..]) |current| {
        var previous = &ranges.items[write - 1];
        if (current.start <= previous.end) return error.OverlappingUnicodeRange;
        if (current.value == previous.value and current.start == previous.end + 1) {
            previous.end = current.end;
        } else {
            ranges.items[write] = current;
            write += 1;
        }
    }
    ranges.items.len = write;
}

fn lessRange(_: void, left: Range, right: Range) bool {
    if (left.start != right.start) return left.start < right.start;
    if (left.end != right.end) return left.end < right.end;
    return left.value < right.value;
}

fn lessComposition(_: void, left: Composition, right: Composition) bool {
    if (left.starter != right.starter) return left.starter < right.starter;
    if (left.combining != right.combining) return left.combining < right.combining;
    return left.composite < right.composite;
}

fn emitModule(allocator: std.mem.Allocator, tables: *const Tables) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try output.appendSlice(allocator,
        \\// Generated deterministically by tools/zig/unicode_gen.zig. Do not edit.
        \\pub const unicode_version = "17.0.0";
        \\pub const uax15_revision = 57;
        \\pub const uax29_revision = 47;
        \\pub const source_archive_sha256 = "2066d1909b2ea93916ce092da1c0ee4808ea3ef8407c94b4f14f5b7eb263d28e";
        \\pub const MapEntry = struct { codepoint: u21, offset: u32, length: u8 };
        \\pub const CccEntry = struct { codepoint: u21, value: u8 };
        \\pub const Range = struct { start: u21, end: u21, value: u8 };
        \\pub const Composition = struct { starter: u21, combining: u21, composite: u21 };
        \\
    );
    const table_bytes = tables.decomposition.items.len * @sizeOf(MapEntry) +
        tables.decomposition_values.items.len * @sizeOf(u21) +
        tables.case_folding.items.len * @sizeOf(MapEntry) +
        tables.case_folding_values.items.len * @sizeOf(u21) +
        tables.ccc.items.len * @sizeOf(CccEntry) +
        tables.compositions.items.len * @sizeOf(Composition) +
        (tables.grapheme.items.len + tables.word.items.len + tables.incb.items.len +
            tables.extended_pictographic.items.len + tables.letter_or_number.items.len) * @sizeOf(Range);
    if (table_bytes > 512 * 1024) return error.UnicodeTableTooLarge;
    try output.print(allocator, "pub const table_bytes: usize = {d};\n\n", .{table_bytes});
    try emitMapEntries(allocator, &output, "decomposition", tables.decomposition.items);
    try emitCodepoints(allocator, &output, "decomposition_values", tables.decomposition_values.items);
    try emitMapEntries(allocator, &output, "case_folding", tables.case_folding.items);
    try emitCodepoints(allocator, &output, "case_folding_values", tables.case_folding_values.items);
    try emitCccEntries(allocator, &output, tables.ccc.items);
    try emitCompositions(allocator, &output, tables.compositions.items);
    try emitRanges(allocator, &output, "grapheme", tables.grapheme.items);
    try emitRanges(allocator, &output, "word", tables.word.items);
    try emitRanges(allocator, &output, "incb", tables.incb.items);
    try emitRanges(allocator, &output, "extended_pictographic", tables.extended_pictographic.items);
    try emitRanges(allocator, &output, "letter_or_number", tables.letter_or_number.items);
    return output.toOwnedSlice(allocator);
}

fn emitMapEntries(allocator: std.mem.Allocator, output: *std.ArrayList(u8), name: []const u8, entries: []const MapEntry) !void {
    try output.print(allocator, "pub const {s} = [_]MapEntry{{\n", .{name});
    for (entries) |entry| try output.print(allocator, "    .{{ .codepoint = 0x{x}, .offset = {d}, .length = {d} }},\n", .{ entry.codepoint, entry.offset, entry.length });
    try output.appendSlice(allocator, "};\n\n");
}

fn emitCodepoints(allocator: std.mem.Allocator, output: *std.ArrayList(u8), name: []const u8, values: []const u21) !void {
    try output.print(allocator, "pub const {s} = [_]u21{{\n", .{name});
    for (values, 0..) |value, index| {
        if (index % 12 == 0) try output.appendSlice(allocator, "    ");
        try output.print(allocator, "0x{x},", .{value});
        if (index % 12 == 11 or index + 1 == values.len) try output.append(allocator, '\n') else try output.append(allocator, ' ');
    }
    try output.appendSlice(allocator, "};\n\n");
}

fn emitCccEntries(allocator: std.mem.Allocator, output: *std.ArrayList(u8), entries: []const CccEntry) !void {
    try output.appendSlice(allocator, "pub const ccc = [_]CccEntry{\n");
    for (entries) |entry| try output.print(allocator, "    .{{ .codepoint = 0x{x}, .value = {d} }},\n", .{ entry.codepoint, entry.value });
    try output.appendSlice(allocator, "};\n\n");
}

fn emitCompositions(allocator: std.mem.Allocator, output: *std.ArrayList(u8), entries: []const Composition) !void {
    try output.appendSlice(allocator, "pub const compositions = [_]Composition{\n");
    for (entries) |entry| try output.print(allocator, "    .{{ .starter = 0x{x}, .combining = 0x{x}, .composite = 0x{x} }},\n", .{ entry.starter, entry.combining, entry.composite });
    try output.appendSlice(allocator, "};\n\n");
}

fn emitRanges(allocator: std.mem.Allocator, output: *std.ArrayList(u8), name: []const u8, ranges: []const Range) !void {
    try output.print(allocator, "pub const {s} = [_]Range{{\n", .{name});
    for (ranges) |range| try output.print(allocator, "    .{{ .start = 0x{x}, .end = 0x{x}, .value = {d} }},\n", .{ range.start, range.end, range.value });
    try output.appendSlice(allocator, "};\n\n");
}

fn compareGenerated(
    allocator: std.mem.Allocator,
    io: std.Io,
    first_path: []const u8,
    second_path: []const u8,
    receipt_path: []const u8,
) !void {
    const first = try std.Io.Dir.cwd().readFileAlloc(io, first_path, allocator, .limited(2 * 1024 * 1024));
    defer allocator.free(first);
    const second = try std.Io.Dir.cwd().readFileAlloc(io, second_path, allocator, .limited(2 * 1024 * 1024));
    defer allocator.free(second);
    if (!std.mem.eql(u8, first, second)) return error.NondeterministicUnicodeTables;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(first, &digest, .{});
    var receipt: std.ArrayList(u8) = .empty;
    defer receipt.deinit(allocator);
    try receipt.print(allocator, "unicode-version=17.0.0\nsource-bytes={d}\nsha256=", .{first.len});
    for (digest) |byte| try receipt.print(allocator, "{x:0>2}", .{byte});
    try receipt.append(allocator, '\n');
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = receipt_path, .data = receipt.items });
}

test "property parsers reject unknown Unicode values" {
    try std.testing.expectError(
        error.UnknownGraphemeProperty,
        parseGraphemePropertyLine("0041 ; Future_Property"),
    );
    try std.testing.expectError(
        error.UnknownWordProperty,
        parseWordPropertyLine("0041 ; Future_Property"),
    );
}

test "codepoint range parser is strict" {
    const range = try parseCodepointRange("0041..005A");
    try std.testing.expectEqual(@as(u21, 0x41), range.start);
    try std.testing.expectEqual(@as(u21, 0x5a), range.end);
    try std.testing.expectError(error.InvalidCodepoint, parseCodepoint("110000"));
    try std.testing.expectError(error.InvalidCodepointRange, parseCodepointRange("005A..0041"));
}

test "verified Unicode snapshot is immune to a deterministic path swap" {
    const io = std.testing.io;
    const original = "0041\n";
    const replacement = "0042\n";
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(original, &digest, .{});
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    const locks = [_]SourceLock{.{
        .path = "CompositionExclusions.txt",
        .size = original.len,
        .sha256 = &digest_hex,
    }};

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{
        .sub_path = locks[0].path,
        .data = original,
    });
    const root = try tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var snapshot = try loadLockedSources(std.testing.allocator, io, root, &locks);
    defer snapshot.deinit();
    try tmp.dir.writeFile(io, .{
        .sub_path = locks[0].path,
        .data = replacement,
    });

    const exclusions = try parseCompositionExclusions(
        std.testing.allocator,
        try snapshot.get(locks[0].path),
    );
    defer std.testing.allocator.free(exclusions);
    try std.testing.expectEqual(@as(usize, 1), exclusions.len);
    try std.testing.expectEqual(@as(u21, 0x41), exclusions[0].start);
    try std.testing.expectEqual(@as(u21, 0x41), exclusions[0].end);
}

fn exerciseUnicodeGenerationAllocation(allocator: std.mem.Allocator) !void {
    var entries = [_]SourceSnapshot.Entry{
        .{ .path = "CompositionExclusions.txt", .bytes = @constCast("") },
        .{ .path = "UnicodeData.txt", .bytes = @constCast("0041;LATIN CAPITAL LETTER A;Lu;0;L;;;;;N;;;;0061;\n") },
        .{ .path = "CaseFolding.txt", .bytes = @constCast("0041; C; 0061;\n") },
        .{ .path = "auxiliary/GraphemeBreakProperty.txt", .bytes = @constCast("000D ; CR\n") },
        .{ .path = "auxiliary/WordBreakProperty.txt", .bytes = @constCast("0041 ; ALetter\n") },
        .{ .path = "DerivedCoreProperties.txt", .bytes = @constCast("094D ; InCB; Linker\n") },
        .{ .path = "emoji/emoji-data.txt", .bytes = @constCast("1F600 ; Extended_Pictographic\n") },
    };
    const sources: SourceSnapshot = .{
        .allocator = allocator,
        .entries = &entries,
    };
    const generated = try generateFromSnapshot(allocator, &sources);
    defer allocator.free(generated);
    try std.testing.expect(generated.len > 0);
}

fn checkAllocationFailuresThroughOnePast(
    comptime exercise: anytype,
    extra_args: anytype,
) !usize {
    const max_allocations = 4_096;
    for (0..max_allocations) |fail_index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        @call(.auto, exercise, .{failing.allocator()} ++ extra_args) catch |err| {
            if (err != error.OutOfMemory) return err;
            if (!failing.has_induced_failure) return error.UnexpectedOutOfMemory;
            if (failing.allocated_bytes != failing.freed_bytes) {
                return error.MemoryLeakDetected;
            }
            continue;
        };
        if (failing.has_induced_failure) return error.SwallowedOutOfMemoryError;
        if (failing.allocated_bytes != failing.freed_bytes) {
            return error.MemoryLeakDetected;
        }
        // A fail index equal to the successful allocation count is the first
        // index at which no allocation can be failed: the required one-past
        // run. Reaching it also proves the allocation trace was deterministic.
        try std.testing.expect(fail_index > 0);
        return fail_index;
    }
    return error.AllocationCampaignLimitExceeded;
}

fn checkUnicodeGenerationAllocationFailures() !usize {
    return checkAllocationFailuresThroughOnePast(
        exerciseUnicodeGenerationAllocation,
        .{},
    );
}

fn exerciseUnicodeSnapshotAllocation(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    locks: []const SourceLock,
) anyerror!void {
    var snapshot = try loadLockedSources(allocator, io, root, locks);
    defer snapshot.deinit();
    try std.testing.expectEqualStrings("0041\n", try snapshot.get(locks[0].path));
}

fn checkUnicodeSnapshotAllocationFailures() !void {
    const io = std.testing.io;
    const source = "0041\n";
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &digest, .{});
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    const locks = [_]SourceLock{.{
        .path = "CompositionExclusions.txt",
        .size = source.len,
        .sha256 = &digest_hex,
    }};

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = locks[0].path, .data = source });
    const root = try tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    const allocation_count = try checkAllocationFailuresThroughOnePast(
        exerciseUnicodeSnapshotAllocation,
        .{ io, root, &locks },
    );
    try std.testing.expectEqual(@as(usize, 4), allocation_count);
    const retained = try tmp.dir.readFileAlloc(
        io,
        locks[0].path,
        std.testing.allocator,
        .limited(source.len + 1),
    );
    defer std.testing.allocator.free(retained);
    try std.testing.expectEqualStrings(source, retained);
}

fn checkUnicodeComparisonAllocationFailures() !void {
    const io = std.testing.io;
    const generated = "pub const unicode_version = \"17.0.0\";\n";
    const max_allocations = 4_096;
    for (0..max_allocations) |fail_index| {
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        defer tmp.cleanup();
        try tmp.dir.writeFile(io, .{ .sub_path = "first.zig", .data = generated });
        try tmp.dir.writeFile(io, .{ .sub_path = "second.zig", .data = generated });
        const root = try tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
        defer std.testing.allocator.free(root);
        const first_path = try std.fs.path.join(
            std.testing.allocator,
            &.{ root, "first.zig" },
        );
        defer std.testing.allocator.free(first_path);
        const second_path = try std.fs.path.join(
            std.testing.allocator,
            &.{ root, "second.zig" },
        );
        defer std.testing.allocator.free(second_path);
        const receipt_path = try std.fs.path.join(
            std.testing.allocator,
            &.{ root, "receipt.txt" },
        );
        defer std.testing.allocator.free(receipt_path);

        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        compareGenerated(
            failing.allocator(),
            io,
            first_path,
            second_path,
            receipt_path,
        ) catch |err| {
            if (err != error.OutOfMemory) return err;
            if (!failing.has_induced_failure) return error.UnexpectedOutOfMemory;
            if (failing.allocated_bytes != failing.freed_bytes) {
                return error.MemoryLeakDetected;
            }
            try std.testing.expectError(
                error.FileNotFound,
                tmp.dir.access(io, "receipt.txt", .{}),
            );
            continue;
        };
        if (failing.has_induced_failure) return error.SwallowedOutOfMemoryError;
        if (failing.allocated_bytes != failing.freed_bytes) {
            return error.MemoryLeakDetected;
        }
        try std.testing.expectEqual(@as(usize, 5), fail_index);
        const receipt = try tmp.dir.readFileAlloc(
            io,
            "receipt.txt",
            std.testing.allocator,
            .limited(256),
        );
        defer std.testing.allocator.free(receipt);
        try std.testing.expect(std.mem.startsWith(
            u8,
            receipt,
            "unicode-version=17.0.0\n",
        ));
        return;
    }
    return error.AllocationCampaignLimitExceeded;
}

test "Unicode generation releases every allocation through and one past success" {
    const successful_allocation_count = try checkUnicodeGenerationAllocationFailures();
    try std.testing.expectEqual(@as(usize, 9), successful_allocation_count);
}

test "Unicode source snapshot releases every allocation through and one past success" {
    try checkUnicodeSnapshotAllocationFailures();
}

test "Unicode comparison leaves no partial receipt on allocation failure" {
    try checkUnicodeComparisonAllocationFailures();
}
