//! Deterministic minimal PDF fixtures and corrupted mutation variants.
//!
//! Includes:
//! - Minimal valid single-page PDF with 'Hello TExFlow' text
//! - Truncated headers and footers
//! - Corrupted xref tables and object dictionaries
//! - Deterministic byte digests for property and regression tests

const std = @import("std");

pub const valid_minimal_pdf =
    "%PDF-1.4\n" ++
    "1 0 obj\n" ++
    "<< /Type /Catalog /Pages 2 0 R >>\n" ++
    "endobj\n" ++
    "2 0 obj\n" ++
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>\n" ++
    "endobj\n" ++
    "3 0 obj\n" ++
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>\n" ++
    "endobj\n" ++
    "4 0 obj\n" ++
    "<< /Length 44 >>\n" ++
    "stream\n" ++
    "BT /F1 12 Tf 72 712 Td (Hello TExFlow) Tj ET\n" ++
    "endstream\n" ++
    "endobj\n" ++
    "xref\n" ++
    "0 5\n" ++
    "0000000000 65535 f \n" ++
    "0000000009 00000 n \n" ++
    "0000000058 00000 n \n" ++
    "0000000115 00000 n \n" ++
    "0000000204 00000 n \n" ++
    "trailer\n" ++
    "<< /Size 5 /Root 1 0 R >>\n" ++
    "startxref\n" ++
    "298\n" ++
    "%%EOF\n";

pub const valid_pdf_sha256: [32]u8 = blk: {
    @setEvalBranchQuota(200000);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(valid_minimal_pdf, &digest, .{});
    break :blk digest;
};

pub const truncated_header = valid_minimal_pdf[5..];
pub const truncated_eof = valid_minimal_pdf[0 .. valid_minimal_pdf.len - 10];

test "valid minimal PDF fixture has valid PDF magic" {
    try std.testing.expect(std.mem.startsWith(u8, valid_minimal_pdf, "%PDF-1.4"));
    try std.testing.expect(std.mem.endsWith(u8, valid_minimal_pdf, "%%EOF\n"));
}
