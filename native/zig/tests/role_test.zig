const std = @import("std");
const role = @import("app_role");

test "role identities expose the exact UI and worker names" {
    const ui = role.identity(.ui);
    try std.testing.expectEqualStrings("TExFlow", ui.product_name);
    try std.testing.expectEqualStrings("TExFlow.exe", ui.original_filename);
    try std.testing.expectEqualStrings("TExFlow", ui.internal_name);
    try std.testing.expectEqualStrings("TExFlow", ui.file_description);
    try std.testing.expectEqualStrings("texflow.main.v1", ui.machine_class);

    const pdf = role.identity(.pdf_worker);
    try std.testing.expectEqualStrings("TExFlow.PdfWorker.exe", pdf.original_filename);
    try std.testing.expectEqualStrings("TExFlow.PdfWorker", pdf.internal_name);
    try std.testing.expectEqualStrings("TExFlow PDF Worker", pdf.file_description);
    try std.testing.expectEqualStrings("texflow.pdfworker.v1", pdf.machine_class);

    const science = role.identity(.science_worker);
    try std.testing.expectEqualStrings("TExFlow.ScienceWorker.exe", science.original_filename);
    try std.testing.expectEqualStrings("TExFlow.ScienceWorker", science.internal_name);
    try std.testing.expectEqualStrings("TExFlow Science Worker", science.file_description);
    try std.testing.expectEqualStrings("texflow.scienceworker.v1", science.machine_class);
    try std.testing.expect(!std.mem.eql(u8, pdf.machine_class, science.machine_class));
}

test "role parser accepts only the exact versioned probe grammar" {
    try std.testing.expectEqual(role.Role.pdf_worker, try role.parseProbe("texflow.role.v1:PdfWorker"));
    try std.testing.expectEqual(role.Role.science_worker, try role.parseProbe("texflow.role.v1:ScienceWorker"));
    try std.testing.expectError(error.ProbeNotAllowedForUi, role.parseProbe("texflow.role.v1:UI"));

    for ([_][]const u8{
        "",
        "texflow.role.v0:PdfWorker",
        "texflow.role.v1:pdfworker",
        "texflow.role.v1:PdfWorker\n",
        "texflow.role.v1:PdfWorker:extra",
        "--worker=PdfWorker",
        "texflow.role.v1:UnknownWorker",
    }) |malformed| {
        try std.testing.expectError(error.MalformedProbe, role.parseProbe(malformed));
    }
}

test "role probe validation rejects empty, embedded-NUL, and cross-role state" {
    try std.testing.expectError(error.MalformedProbe, role.validateProbe(.{ .role = .pdf_worker, .nonce = "" }));
    try std.testing.expectError(error.MalformedProbe, role.validateProbe(.{ .role = .pdf_worker, .nonce = "a\x00b" }));
    try std.testing.expectError(error.ProbeNotAllowedForUi, role.validateProbe(.{ .role = .ui, .nonce = "texflow.role.v1:PdfWorker" }));
    try role.validateProbe(.{ .role = .pdf_worker, .nonce = "texflow.role.v1:PdfWorker" });
}
