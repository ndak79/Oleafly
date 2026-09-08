//! Contract tests for LPAC process configuration and token audit predicates.

const std = @import("std");
const process = @import("platform_process");

const testing = std.testing;

test "worker roles map to distinct monikers" {
    const pdf_moniker = process.WorkerRole.pdf.moniker();
    const sci_moniker = process.WorkerRole.science.moniker();

    try testing.expectEqualStrings("texflow.pdfworker.v1", pdf_moniker);
    try testing.expectEqualStrings("texflow.scienceworker.v1", sci_moniker);
    try testing.expect(!std.mem.eql(u8, pdf_moniker, sci_moniker));
}

test "token audit predicate requires all security flags" {
    var audit = process.TokenAudit{
        .is_app_container = true,
        .is_lpac = true,
        .empty_capabilities = true,
        .low_integrity = true,
    };
    try testing.expect(audit.isVerified());

    // If LPAC flag is missing, audit must fail
    audit.is_lpac = false;
    try testing.expect(!audit.isVerified());

    // If capabilities are not empty, audit must fail
    audit.is_lpac = true;
    audit.empty_capabilities = false;
    try testing.expect(!audit.isVerified());
}

test "suspended token audit stub succeeds in portable mode" {
    const audit = try process.auditSuspendedToken(null);
    try testing.expect(audit.isVerified());
}
