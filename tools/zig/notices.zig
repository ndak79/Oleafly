//! Offline native source/license and shipping-notice contract.
const std = @import("std");
const deps = @import("deps");
const contract = @import("notices_contract");
const Allocator = std.mem.Allocator;

pub const Role = enum {
    product_static,
    build_only_generated_data,
    test_only_comparator,
    reference_only,
    qa_only,
    reconstruction_tool,
};

pub const Record = struct {
    id: []const u8,
    version: []const u8,
    role: Role,
    purpose: []const u8,
    source_url: []const u8,
    acquisition_url: []const u8,
    license_spdx: []const u8,
    license_url: []const u8,
    identity_kind: enum { archive_sha256, canonical_tree_sha256, git_tree_sha1 },
    source_identity: []const u8,
};

pub const Inventory = struct {
    allocator: Allocator,
    manifest: std.json.Parsed(deps.Manifest),
    records: []Record,

    pub fn deinit(self: *Inventory) void {
        self.allocator.free(self.records);
        self.manifest.deinit();
    }
};

/// Lock verification precedes projection. This inventory records provenance,
/// not an assertion that any reference, QA tool, or source archive ships.
pub fn lockedInventory(allocator: Allocator) !Inventory {
    const manifest = try deps.parseLockedManifest(allocator);
    errdefer manifest.deinit();
    const records = try allocator.alloc(Record, manifest.value.artifacts.len + manifest.value.git_sources.len);
    errdefer allocator.free(records);
    for (manifest.value.artifacts, records[0..manifest.value.artifacts.len]) |artifact, *record| {
        record.* = .{
            .id = artifact.id,
            .version = artifact.version,
            .role = try sourceRole(artifact.id),
            .purpose = artifact.purpose,
            .source_url = artifact.source_url,
            .acquisition_url = artifact.url,
            .license_spdx = artifact.license_spdx,
            .license_url = artifact.license_url,
            .identity_kind = if (artifact.integrity == .canonical_tree) .canonical_tree_sha256 else .archive_sha256,
            .source_identity = artifact.canonical_tree_sha256 orelse artifact.archive_sha256 orelse return error.MissingSourceIdentity,
        };
    }
    for (manifest.value.git_sources, records[manifest.value.artifacts.len..]) |source, *record| {
        record.* = .{
            .id = source.id,
            .version = source.version,
            .role = try sourceRole(source.id),
            .purpose = source.purpose,
            .source_url = source.source_url,
            .acquisition_url = source.repository_url,
            .license_spdx = source.license_spdx,
            .license_url = source.license_url,
            .identity_kind = .git_tree_sha1,
            .source_identity = source.tree,
        };
    }
    std.mem.sort(Record, records, {}, struct {
        fn lessThan(_: void, a: Record, b: Record) bool {
            return std.mem.order(u8, a.id, b.id) == .lt;
        }
    }.lessThan);
    return .{ .allocator = allocator, .manifest = manifest, .records = records };
}

fn sourceRole(id: []const u8) !Role {
    const roles = .{
        .{ "scintilla", .product_static },          .{ "sqlite", .product_static },
        .{ "zigwin32", .product_static },           .{ "unicode-ucd", .build_only_generated_data },
        .{ "lexilla", .test_only_comparator },      .{ "pdfium-reference", .reference_only },
        .{ "pdfium-root-source", .reference_only }, .{ "pdfium-build-recipe", .reference_only },
        .{ "presentmon", .qa_only },                .{ "accessibility-insights", .qa_only },
        .{ "github-cli", .qa_only },                .{ "depot-tools", .reconstruction_tool },
    };
    inline for (roles) |row| if (std.mem.eql(u8, id, row[0])) return row[1];
    return error.UnknownSourceRecord;
}

pub fn findRecord(records: []const Record, id: []const u8) ?Record {
    for (records) |record| if (std.mem.eql(u8, record.id, id)) return record;
    return null;
}

pub fn validateInventory(allocator: Allocator, records: []const Record) !void {
    for (records, 0..) |record, index| {
        if (findRecord(records[0..index], record.id) != null) return error.DuplicateSourceRecord;
    }
    var expected = try lockedInventory(allocator);
    defer expected.deinit();
    for (records) |record| {
        const locked = findRecord(expected.records, record.id) orelse return error.UnknownSourceRecord;
        if (record.role != locked.role) return error.SourceRoleMismatch;
        if (record.identity_kind != locked.identity_kind) return error.SourceIdentityMismatch;
        inline for (.{ "version", "purpose", "source_url", "acquisition_url", "license_spdx", "license_url", "source_identity" }) |field| {
            if (!std.mem.eql(u8, @field(record, field), @field(locked, field))) return error.SourceIdentityMismatch;
        }
    }
    if (records.len != expected.records.len) return error.MissingSourceRecord;
}

fn roleText(role: Role) []const u8 {
    return switch (role) {
        .product_static => "product-static",
        .build_only_generated_data => "build-only-generated-data",
        .test_only_comparator => "test-only-comparator",
        .reference_only => "reference-only",
        .qa_only => "qa-only",
        .reconstruction_tool => "reconstruction-tool",
    };
}

fn writeRecord(writer: *std.Io.Writer, record: Record) !void {
    try writer.print(
        "Component: {s}\nVersion: {s}\nRole: {s}\nPurpose: {s}\nSource: {s}\nAcquisition: {s}\nSPDX: {s}\nLicense: {s}\nIdentity ({s}): {s}\n",
        .{ record.id, record.version, roleText(record.role), record.purpose, record.source_url, record.acquisition_url, record.license_spdx, record.license_url, @tagName(record.identity_kind), record.source_identity },
    );
}

/// Complete source/tool inventory. The separately labeled Lexilla license
/// record is emitted here only; this output is not a shipping payload list.
pub fn renderSourceInventory(allocator: Allocator, records: []const Record) ![]u8 {
    try validateInventory(allocator, records);
    var locked = try lockedInventory(allocator);
    defer locked.deinit();
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    try output.writer.print("TExFlow source/license inventory\nLock SHA-256: {s}\nNot a shipping payload inventory. Test, reference, QA, and reconstruction roles are excluded from shipping.\n", .{deps.locked_manifest_sha256});
    for (locked.records) |record| {
        try output.writer.writeAll("\n");
        try writeRecord(&output.writer, record);
    }
    return output.toOwnedSlice();
}

pub fn renderShippingNotice(allocator: Allocator, records: []const Record) ![]u8 {
    try validateInventory(allocator, records);
    var locked = try lockedInventory(allocator);
    defer locked.deinit();
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    // Existing product/source-lineage attribution and full Unicode License v3
    // are retained verbatim except for canonical LF line endings.
    const root_notice = try std.mem.replaceOwned(u8, allocator, contract.root_notice, "\r\n", "\n");
    defer allocator.free(root_notice);
    try output.writer.writeAll(root_notice);
    try output.writer.print("\n-------------------------------------------------------------------------------\nNative source and license contract (T0.2b)\nLock SHA-256: {s}\n\nProduct-static identifies the selected source role, not completed installation.\nUnicode input archives are build-only; generated data retain the license above.\nThis contract does not certify a complete release payload.\n", .{deps.locked_manifest_sha256});
    for (locked.records) |record| {
        if (record.role != .product_static and record.role != .build_only_generated_data) continue;
        try output.writer.writeAll("\n");
        try writeRecord(&output.writer, record);
        if (std.mem.eql(u8, record.id, "scintilla")) try output.writer.writeAll("\n" ++ scintilla_license ++ "\n");
        if (std.mem.eql(u8, record.id, "sqlite")) try output.writer.writeAll("\n" ++ sqlite_notice ++ "\n");
        if (std.mem.eql(u8, record.id, "zigwin32")) try output.writer.writeAll("\n" ++ zigwin32_license ++ "\n");
    }
    try output.writer.writeAll("\n-------------------------------------------------------------------------------\nPDFium reference provenance (not a shipping runtime)\nPDFium transitive runtime closure: UNVERIFIED\nThe lock does not contain a resolved transitive runtime source/license inventory.\nReconstruction and exact runtime licenses are required before release admission.\nThe community reference DLL, root source, and build recipe remain reference-only.\n");
    for (locked.records) |record| {
        if (record.role != .reference_only) continue;
        try output.writer.writeAll("\n");
        try writeRecord(&output.writer, record);
    }
    const attestation = locked.manifest.value.attestations[0];
    const reference = deps.findArtifact(locked.manifest.value, "pdfium-reference").?;
    try output.writer.print("\nAttestation: {s}\nSubject: {s}\nSubject SHA-256: {s}\nWorkflow repository: {s}\nBuild-recipe commit: {s}\nReference DLL: {s}\nReference DLL SHA-256: {s}\nAttested community reference only; excluded from shipping runtime.\n", .{
        attestation.id,                         attestation.subject_name,  attestation.subject_sha256,
        attestation.workflow_repository,        attestation.source_digest, reference.retained_members[0].path,
        reference.retained_members[0].sha256.?,
    });
    return output.toOwnedSlice();
}

/// Byte-for-byte canonical parsing: no duplicate, missing, reordered, extra,
/// relabeled, or altered notice field can be accepted as another document.
pub fn validateShippingNotice(allocator: Allocator, records: []const Record, bytes: []const u8) !void {
    const canonical = try renderShippingNotice(allocator, records);
    defer allocator.free(canonical);
    if (!std.mem.eql(u8, bytes, canonical)) return error.NonCanonicalNotice;
}

pub const LegalFile = struct { path: []const u8, bytes: []const u8 };

/// Validate the legal subset of a future package. This is deliberately not
/// a claim about all installed files and creates no install/build edge.
pub fn validateLegalPayload(allocator: Allocator, files: []const LegalFile) !void {
    var license: ?[]const u8 = null;
    var notice: ?[]const u8 = null;
    for (files) |file| {
        const slot = if (std.mem.eql(u8, file.path, "LICENSE")) &license else if (std.mem.eql(u8, file.path, "THIRD_PARTY_NOTICES.txt")) &notice else return error.UnexpectedLegalFile;
        if (slot.* != null) return error.DuplicateLegalFile;
        slot.* = file.bytes;
    }
    const license_bytes = license orelse return error.MissingLegalFile;
    const notice_bytes = notice orelse return error.MissingLegalFile;
    if (!std.mem.eql(u8, license_bytes, contract.license)) return error.LegalFileMismatch;
    var inventory = try lockedInventory(allocator);
    defer inventory.deinit();
    try validateShippingNotice(allocator, inventory.records, notice_bytes);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.InvalidArguments;
    var inventory = try lockedInventory(init.gpa);
    defer inventory.deinit();
    if (std.mem.eql(u8, args[1], "check")) {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, "native/zig/THIRD_PARTY_NOTICES.txt", init.gpa, .limited(64 * 1024));
        defer init.gpa.free(bytes);
        try validateShippingNotice(init.gpa, inventory.records, bytes);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        std.debug.print("TExFlow canonical notice: {d} bytes, SHA-256 {s}; PDFium runtime closure UNVERIFIED\n", .{ bytes.len, std.fmt.bytesToHex(digest, .lower) });
        return;
    }
    const bytes = if (std.mem.eql(u8, args[1], "render")) try renderShippingNotice(init.gpa, inventory.records) else if (std.mem.eql(u8, args[1], "inventory")) try renderSourceInventory(init.gpa, inventory.records) else return error.InvalidArguments;
    defer init.gpa.free(bytes);
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    try stdout.interface.writeAll(bytes);
    try stdout.interface.flush();
}

// Transcribed without changing upstream attribution from the pinned source
// artifacts' License.txt, sqlite3.c header, and LICENSE respectively.
const scintilla_license =
    \\License for Lexilla, Scintilla, and SciTE
    \\
    \\Copyright 1998-2021 by Neil Hodgson <neilh@scintilla.org>
    \\
    \\All Rights Reserved
    \\
    \\Permission to use, copy, modify, and distribute this software and its
    \\documentation for any purpose and without fee is hereby granted,
    \\provided that the above copyright notice appear in all copies and that
    \\both that copyright notice and this permission notice appear in
    \\supporting documentation.
    \\
    \\NEIL HODGSON DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS
    \\SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
    \\AND FITNESS, IN NO EVENT SHALL NEIL HODGSON BE LIABLE FOR ANY
    \\SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
    \\WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
    \\WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
    \\TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE
    \\OR PERFORMANCE OF THIS SOFTWARE.
;

const sqlite_notice =
    \\SQLite is in the public domain. SPDX identifier: blessing.
    \\In place of a legal notice, the pinned amalgamation offers this blessing:
    \\
    \\May you do good and not evil.
    \\May you find forgiveness for yourself and forgive others.
    \\May you share freely, never taking more than you give.
;

const zigwin32_license =
    \\Copyright 2021 Jonathan Marler
    \\
    \\Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
    \\
    \\The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
    \\
    \\THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
;
