const std = @import("std");
const matrix = @import("bench_matrix");

test "campaign matrix is deterministic, named, and covers every required cell" {
    var campaign = try matrix.makeCampaign(std.testing.allocator);
    defer campaign.deinit();
    try matrix.validate(campaign);
    try std.testing.expectEqual(@as(u64, 0x544558464c4f5737), campaign.seed);
    for (matrix.requiredCells()) |required| {
        try std.testing.expectEqual(@as(usize, 1), matrix.countCell(campaign.rows, required.id));
        try std.testing.expectEqual(required.repetitions, matrix.repetitionsFor(campaign.rows, required.id));
    }
    try std.testing.expectEqual(@as(usize, 54), matrix.coreRowCount(campaign.rows));
}

test "campaign validation rejects duplicate rows and missing core coverage" {
    var campaign = try matrix.makeCampaign(std.testing.allocator);
    defer campaign.deinit();

    const first_id = campaign.rows[0].id;
    campaign.rows[1].id = first_id;
    try std.testing.expectError(error.DuplicateRowId, matrix.validate(campaign));

    campaign.rows[1].id = "MISSING_DUPLICATE_REPAIRED";
    const old_rows = campaign.rows;
    campaign.rows = old_rows[1..];
    try std.testing.expectError(error.InvalidRowCount, matrix.validate(campaign));
}

test "campaign rows keep P1 performance separate from the V0 conditional journey" {
    var campaign = try matrix.makeCampaign(std.testing.allocator);
    defer campaign.deinit();
    var saw_p1 = false;
    var saw_v0 = false;
    for (campaign.rows) |row| {
        if (std.mem.eql(u8, row.cell_id, "P1-pixel-refresh")) {
            saw_p1 = true;
            try std.testing.expectEqual(matrix.CellKind.performance, row.kind);
            try std.testing.expectEqual(@as(u16, 30), row.repetitions);
            try std.testing.expectEqual(@as(usize, 1), matrix.countCell(campaign.rows, "P1-pixel-refresh"));
            try std.testing.expectEqual(@as(u16, 30), matrix.repetitionsFor(campaign.rows, "P1-pixel-refresh"));
        }
        for (row.cell_aliases) |alias| {
            if (std.mem.eql(u8, alias, "V0-hdr")) {
                saw_v0 = true;
                try std.testing.expectEqual(matrix.CellKind.conditional, matrix.requiredCells()[9].kind);
                try std.testing.expectEqual(@as(u16, 1), matrix.requiredCells()[9].repetitions);
                try std.testing.expectEqual(@as(usize, 1), matrix.countCell(campaign.rows, "V0-hdr"));
                try std.testing.expectEqual(@as(u16, 1), matrix.repetitionsFor(campaign.rows, "V0-hdr"));
            }
        }
    }
    try std.testing.expect(saw_p1);
    try std.testing.expect(saw_v0);
    try std.testing.expectError(error.UnknownCell, matrix.validateRow(.{
        .id = "C-unknown",
        .cell_id = "P9-not-registered",
        .kind = .performance,
        .repetitions = 30,
    }));
    try std.testing.expectError(error.UnknownCell, matrix.validateRow(.{
        .id = "C-physical",
        .cell_id = "C-physical",
        .kind = .physical,
        .repetitions = 1,
    }));
}

test "required coverage cannot be spoofed through a row id" {
    var campaign = try matrix.makeCampaign(std.testing.allocator);
    defer campaign.deinit();
    campaign.rows[0].cell_id = "C-fake";
    try std.testing.expectError(error.UnknownCell, matrix.validate(campaign));
}
