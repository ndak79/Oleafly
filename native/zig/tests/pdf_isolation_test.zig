//! Tests for PDF worker process isolation, role identification, and sandboxing.

const std = @import("std");
const process = @import("platform_process");
const frame = @import("ipc_frame");

const testing = std.testing;

test "pdf worker role matches moniker and IPC enum" {
    const role = frame.Role.pdf_worker;
    try testing.expectEqual(@as(u8, 1), @intFromEnum(role));

    const moniker = process.WorkerRole.pdf.moniker();
    try testing.expectEqualStrings("texflow.pdfworker.v1", moniker);
}

test "pdf worker has distinct identity from science worker" {
    const pdf_role = frame.Role.pdf_worker;
    const sci_role = frame.Role.science_worker;
    try testing.expect(pdf_role != sci_role);

    const pdf_moniker = process.WorkerRole.pdf.moniker();
    const sci_moniker = process.WorkerRole.science.moniker();
    try testing.expect(!std.mem.eql(u8, pdf_moniker, sci_moniker));
}
