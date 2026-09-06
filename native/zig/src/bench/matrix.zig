//! Canonical fixture campaign matrix. It names coverage; it never runs hardware.
const std = @import("std");

pub const seed: u64 = 0x544558464c4f5737;
pub const canonical_row_count: usize = 54;

pub const CellKind = enum { performance, conditional, physical };
pub const Resolution = enum { p1080, p1440, p4k };
pub const ShellRenderer = enum { hardware, warp };

pub const RequiredCell = struct {
    id: []const u8,
    repetitions: u16,
    kind: CellKind,
};

pub const required_cells = [_]RequiredCell{
    .{ .id = "P0-baseline", .repetitions = 30, .kind = .performance },
    .{ .id = "P1-pixel-refresh", .repetitions = 30, .kind = .performance },
    .{ .id = "P2-software", .repetitions = 30, .kind = .performance },
    .{ .id = "P3-balanced", .repetitions = 30, .kind = .performance },
    .{ .id = "P4-rdp", .repetitions = 30, .kind = .performance },
    .{ .id = "P5-battery", .repetitions = 30, .kind = .performance },
    .{ .id = "P6-large-editor", .repetitions = 30, .kind = .performance },
    .{ .id = "P7-search-query", .repetitions = 30, .kind = .performance },
    .{ .id = "P8-search-rebuild", .repetitions = 30, .kind = .performance },
    .{ .id = "V0-hdr", .repetitions = 1, .kind = .conditional },
};

// The order is part of the preregistration. It is the Cartesian product of
// resolution (3), refresh (3), DPI (3), and shell renderer (2), with the
// renderer varying fastest. This is the smallest complete strength-three
// array for those four core factors.
pub const canonical_ids = [_][]const u8{
    "M00", "M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08", "M09",
    "M10", "M11", "M12", "M13", "M14", "M15", "M16", "M17", "M18", "M19",
    "M20", "M21", "M22", "M23", "M24", "M25", "M26", "M27", "M28", "M29",
    "M30", "M31", "M32", "M33", "M34", "M35", "M36", "M37", "M38", "M39",
    "M40", "M41", "M42", "M43", "M44", "M45", "M46", "M47", "M48", "M49",
    "M50", "M51", "M52", "M53",
};

pub const Row = struct {
    id: []const u8,
    cell_id: []const u8,
    // A row may be the canonical representative for several named cells that
    // share its core display factors (for example P0/P4/P5/P6/P7/P8). The
    // aliases are fixed, reviewable data, not caller-provided arbitrary cells.
    cell_aliases: [8][]const u8 = .{ "", "", "", "", "", "", "", "" },
    kind: CellKind,
    repetitions: u16,
    resolution: Resolution = .p1080,
    refresh_hz: u16 = 60,
    dpi: u16 = 100,
    shell_renderer: ShellRenderer = .hardware,
};

pub const Campaign = struct {
    allocator: std.mem.Allocator,
    rows: []Row,
    owned_rows: []Row,
    storage: [][32]u8,
    seed: u64 = seed,

    pub fn deinit(self: *Campaign) void {
        self.allocator.free(self.owned_rows);
        self.allocator.free(self.storage);
        self.* = undefined;
    }
};

pub const ValidationError = error{
    DuplicateRowId,
    MissingCell,
    UnknownCell,
    InvalidRepetitions,
    InvalidKind,
    InvalidRowCount,
    InvalidSeed,
    InvalidRowId,
    InvalidOrder,
    InvalidFactors,
    Empty,
};

pub fn requiredCells() []const RequiredCell {
    return required_cells[0..];
}

fn putName(buffer: *[32]u8, name: []const u8) []const u8 {
    std.debug.assert(name.len <= buffer.len);
    @memset(buffer, 0);
    @memcpy(buffer[0..name.len], name);
    return buffer[0..name.len];
}

fn coreFactors(index: usize) struct { resolution: Resolution, refresh_hz: u16, dpi: u16, shell_renderer: ShellRenderer } {
    const shell_index = index % 2;
    const dpi_index = (index / 2) % 3;
    const refresh_index = (index / 6) % 3;
    const resolution_index = (index / 18) % 3;
    return .{
        .resolution = @enumFromInt(resolution_index),
        .refresh_hz = switch (refresh_index) {
            0 => 60,
            1 => 120,
            else => 144,
        },
        .dpi = switch (dpi_index) {
            0 => 100,
            1 => 150,
            else => 200,
        },
        .shell_renderer = if (shell_index == 0) .hardware else .warp,
    };
}

fn aliasesFor(index: usize) struct { cell_id: []const u8, kind: CellKind, repetitions: u16, aliases: [8][]const u8 } {
    var aliases: [8][]const u8 = .{ "", "", "", "", "", "", "", "" };
    return switch (index) {
        // 1080p/60/100% hardware is the baseline representative. The named
        // profile/workload cells remain distinct by cell ID and are never
        // pooled by this fixture matrix.
        0 => blk: {
            aliases[0] = "P4-rdp";
            aliases[1] = "P5-battery";
            aliases[2] = "P6-large-editor";
            aliases[3] = "P7-search-query";
            aliases[4] = "P8-search-rebuild";
            break :blk .{ .cell_id = "P0-baseline", .kind = .performance, .repetitions = 30, .aliases = aliases };
        },
        // 1080p/60/100% WARP + DirectWriteDC editor.
        1 => .{ .cell_id = "P2-software", .kind = .performance, .repetitions = 30, .aliases = aliases },
        // 1440p/120/150% hardware.
        26 => .{ .cell_id = "P3-balanced", .kind = .performance, .repetitions = 30, .aliases = aliases },
        // 4K/144/200% hardware is the pixel-refresh performance row. HDR is a
        // separate conditional journey on the same display factors; it keeps
        // its own one-shot semantics as an explicitly typed alias.
        52 => blk: {
            aliases[0] = "V0-hdr";
            break :blk .{ .cell_id = "P1-pixel-refresh", .kind = .performance, .repetitions = 30, .aliases = aliases };
        },
        else => .{ .cell_id = "matrix", .kind = .performance, .repetitions = 0, .aliases = aliases },
    };
}

pub fn makeCampaign(allocator: std.mem.Allocator) !Campaign {
    const owned_rows = try allocator.alloc(Row, canonical_row_count);
    errdefer allocator.free(owned_rows);
    const storage = try allocator.alloc([32]u8, canonical_row_count);
    errdefer allocator.free(storage);

    for (owned_rows, 0..) |*row, index| {
        const cell = aliasesFor(index);
        const factors = coreFactors(index);
        row.* = .{
            .id = putName(&storage[index], canonical_ids[index]),
            .cell_id = cell.cell_id,
            .cell_aliases = cell.aliases,
            .kind = cell.kind,
            .repetitions = cell.repetitions,
            .resolution = factors.resolution,
            .refresh_hz = factors.refresh_hz,
            .dpi = factors.dpi,
            .shell_renderer = factors.shell_renderer,
        };
    }
    return .{ .allocator = allocator, .rows = owned_rows, .owned_rows = owned_rows, .storage = storage };
}

fn rowContainsCell(row: Row, id: []const u8) bool {
    if (std.mem.eql(u8, row.cell_id, id)) return true;
    for (row.cell_aliases) |alias| if (alias.len != 0 and std.mem.eql(u8, alias, id)) return true;
    return false;
}

pub fn countCell(rows: []const Row, id: []const u8) usize {
    var count: usize = 0;
    for (rows) |row| {
        if (rowContainsCell(row, id)) count += 1;
    }
    return count;
}

pub fn repetitionsFor(rows: []const Row, id: []const u8) u16 {
    for (required_cells) |required| if (std.mem.eql(u8, required.id, id)) return required.repetitions;
    for (rows) |row| if (rowContainsCell(row, id)) return row.repetitions;
    return 0;
}

pub fn coreRowCount(rows: []const Row) usize {
    return rows.len;
}

pub fn validateRow(row: Row) ValidationError!void {
    if (row.id.len == 0 or row.cell_id.len == 0) return error.Empty;
    if (std.mem.eql(u8, row.cell_id, "matrix")) {
        if (row.kind != .performance or row.repetitions != 0) return error.InvalidKind;
    } else {
        var primary_known = false;
        for (required_cells) |required| {
            if (std.mem.eql(u8, row.cell_id, required.id)) {
                primary_known = true;
                if (row.kind != required.kind) return error.InvalidKind;
                if (row.repetitions != required.repetitions) return error.InvalidRepetitions;
                break;
            }
        }
        if (!primary_known) return error.UnknownCell;
    }
    for (row.cell_aliases) |alias| {
        if (alias.len == 0) continue;
        var known = false;
        for (required_cells) |required| if (std.mem.eql(u8, alias, required.id)) {
            known = true;
            break;
        };
        if (!known) return error.UnknownCell;
    }
}

pub fn validate(campaign: Campaign) ValidationError!void {
    if (campaign.seed != seed) return error.InvalidSeed;
    if (campaign.rows.len != canonical_row_count) return error.InvalidRowCount;
    if (campaign.rows.len != campaign.owned_rows.len) return error.InvalidRowCount;

    for (campaign.rows, 0..) |row, index| {
        try validateRow(row);
        for (campaign.rows[0..index]) |previous| if (std.mem.eql(u8, previous.id, row.id)) return error.DuplicateRowId;
        if (!std.mem.eql(u8, row.id, canonical_ids[index])) return error.InvalidRowId;
        const expected = coreFactors(index);
        if (row.resolution != expected.resolution or row.refresh_hz != expected.refresh_hz or
            row.dpi != expected.dpi or row.shell_renderer != expected.shell_renderer)
        {
            return error.InvalidFactors;
        }
        const expected_cell = aliasesFor(index);
        if (!std.mem.eql(u8, row.cell_id, expected_cell.cell_id) or row.kind != expected_cell.kind or row.repetitions != expected_cell.repetitions) {
            return error.InvalidOrder;
        }
        for (row.cell_aliases, expected_cell.aliases) |actual, expected_alias| if (!std.mem.eql(u8, actual, expected_alias)) return error.InvalidOrder;
    }
    for (required_cells) |required| {
        if (countCell(campaign.rows, required.id) != 1) return error.MissingCell;
        if (repetitionsFor(campaign.rows, required.id) != required.repetitions) return error.InvalidRepetitions;
    }
}
