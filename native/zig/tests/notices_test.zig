const std = @import("std");
const notices = @import("notices");
const contract = @import("notices_contract");
const testing = std.testing;
const allocator = testing.allocator;

test "source package includes notice tooling and the native notice" {
    try testing.expect(std.mem.indexOf(u8, contract.zon, "\"tools/zig/notices.zig\"") != null);
    try testing.expect(std.mem.indexOf(u8, contract.zon, "\"native/zig\"") != null);
    try testing.expect(std.mem.indexOf(u8, contract.zon, "\"LICENSE\"") != null);
    try testing.expect(std.mem.indexOf(u8, contract.zon, "\".gitattributes\"") != null);
}

test "portable compile check has no external Git checkout fixture edge" {
    try testing.expect(!contract.portable_check_has_checkout_edge);
}

test "inventory preserves all twelve locked source identities and honest roles" {
    if (comptime !@hasDecl(notices, "lockedInventory")) return error.MissingNoticeInventory;
    var inventory = try notices.lockedInventory(allocator);
    defer inventory.deinit();
    try testing.expectEqual(@as(usize, 12), inventory.records.len);
    const expected = .{
        .{ "scintilla", "5.6.6", .product_static },
        .{ "sqlite", "3.53.4", .product_static },
        .{ "zigwin32", "42.0.39-preview", .product_static },
        .{ "unicode-ucd", "17.0.0", .build_only_generated_data },
        .{ "lexilla", "5.5.3", .test_only_comparator },
        .{ "pdfium-reference", "154.0.8035.0", .reference_only },
        .{ "pdfium-root-source", "6f2272e1f3aaa141305475b83ef4eac2c1f527b8", .reference_only },
        .{ "pdfium-build-recipe", "5453f3afc4785cbad82c05f6ceb4dabea0cb81a0", .reference_only },
        .{ "depot-tools", "a0fd6e66af74304c9b4605665435f4e88849e046", .reconstruction_tool },
    };
    inline for (expected) |row| {
        const record = notices.findRecord(inventory.records, row[0]).?;
        try testing.expectEqualStrings(row[1], record.version);
        try testing.expectEqual(@as(notices.Role, row[2]), record.role);
    }
    try notices.validateInventory(allocator, inventory.records);
}

test "inventory rejects duplicate missing unknown or altered provenance records" {
    if (comptime !@hasDecl(notices, "validateInventory")) return error.MissingNoticeInventoryValidator;
    var inventory = try notices.lockedInventory(allocator);
    defer inventory.deinit();
    const records = try allocator.dupe(notices.Record, inventory.records);
    defer allocator.free(records);
    try testing.expectError(error.MissingSourceRecord, notices.validateInventory(allocator, records[1..]));
    records[1] = records[0];
    try testing.expectError(error.DuplicateSourceRecord, notices.validateInventory(allocator, records));
    @memcpy(records, inventory.records);
    records[0].id = "unknown-runtime";
    try testing.expectError(error.UnknownSourceRecord, notices.validateInventory(allocator, records));
    inline for (.{ "version", "purpose", "source_url", "acquisition_url", "license_spdx", "license_url", "source_identity" }) |field| {
        @memcpy(records, inventory.records);
        @field(records[0], field) = "wrong";
        try testing.expectError(error.SourceIdentityMismatch, notices.validateInventory(allocator, records));
    }
}

test "reference test QA and build inputs cannot be promoted to shipping runtime" {
    if (comptime !@hasDecl(notices, "validateInventory")) return error.MissingNoticeInventoryValidator;
    var inventory = try notices.lockedInventory(allocator);
    defer inventory.deinit();
    for (inventory.records) |*record| {
        const original = record.role;
        record.role = if (original == .product_static) .reference_only else .product_static;
        try testing.expectError(error.SourceRoleMismatch, notices.validateInventory(allocator, inventory.records));
        record.role = original;
    }
}

test "shipping notice has canonical bytes lineage versions and unresolved PDFium status" {
    if (comptime !@hasDecl(notices, "renderShippingNotice")) return error.MissingNoticeRenderer;
    var inventory = try notices.lockedInventory(allocator);
    defer inventory.deinit();
    const rendered = try notices.renderShippingNotice(allocator, inventory.records);
    defer allocator.free(rendered);
    try testing.expectEqualStrings(rendered, contract.shipping_notice);
    try testing.expect(std.mem.startsWith(u8, rendered, "TExFlow\n"));
    try testing.expect(std.mem.indexOfScalar(u8, rendered, '\r') == null);
    for ([_][]const u8{
        "TExFlow is derived from Oleafly.",                                 "AGPL-3.0-or-later",                                          "UNICODE LICENSE V3",
        "Component: scintilla\nVersion: 5.6.6\nRole: product-static\n",     "Component: sqlite\nVersion: 3.53.4\nRole: product-static\n", "Component: unicode-ucd\nVersion: 17.0.0\nRole: build-only-generated-data\n",
        "Attestation: pdfium-chromium-8035-win-x64",                        "PDFium transitive runtime closure: UNVERIFIED",              "not a shipping runtime",
        "ccfac1aad9e78624ebfb3f54f3f4ddb77af6db2f52803f150e2f9876beda49fe",
    }) |text| try testing.expect(std.mem.indexOf(u8, rendered, text) != null);
    // The unmodified Scintilla license heading names Lexilla; a component
    // record for the comparator must nevertheless never enter this notice.
    for ([_][]const u8{ "Component: lexilla\n", "LicenseRef-Lexilla", "Component: presentmon\n", "THIRD_PARTY_LICENSES.md" }) |text|
        try testing.expect(std.mem.indexOf(u8, rendered, text) == null);
    try notices.validateShippingNotice(allocator, inventory.records, rendered);
    try testing.expectError(error.NonCanonicalNotice, notices.validateShippingNotice(allocator, inventory.records, rendered[1..]));
    const extra = try std.mem.concat(allocator, u8, &.{ rendered, "\nComponent: lexilla\n" });
    defer allocator.free(extra);
    try testing.expectError(error.NonCanonicalNotice, notices.validateShippingNotice(allocator, inventory.records, extra));
}

test "notice and source inventory rendering ignore input order" {
    if (comptime !@hasDecl(notices, "renderSourceInventory")) return error.MissingSourceInventoryRenderer;
    var inventory = try notices.lockedInventory(allocator);
    defer inventory.deinit();
    const first = try notices.renderShippingNotice(allocator, inventory.records);
    defer allocator.free(first);
    const source_first = try notices.renderSourceInventory(allocator, inventory.records);
    defer allocator.free(source_first);
    std.mem.reverse(notices.Record, inventory.records);
    const second = try notices.renderShippingNotice(allocator, inventory.records);
    defer allocator.free(second);
    const source_second = try notices.renderSourceInventory(allocator, inventory.records);
    defer allocator.free(source_second);
    try testing.expectEqualSlices(u8, first, second);
    try testing.expectEqualSlices(u8, source_first, source_second);
    try testing.expect(std.mem.indexOf(u8, source_first, "Component: lexilla\nVersion: 5.5.3\nRole: test-only-comparator\n") != null);
    try testing.expect(std.mem.indexOf(u8, source_first, "SPDX: LicenseRef-Lexilla\n") != null);
}

test "upstream shipping license text retains exact independently recorded source hashes" {
    // Exact License.txt/LICENSE bytes from the pinned Scintilla and zigwin32
    // source archives. Scintilla's file has no final LF; zigwin32's has one.
    const sections = .{
        .{ "License for Lexilla, Scintilla, and SciTE\n", 864, "ac32743bd464c837e481beae20df65a9207f84d3ff1912f6003000343e9c753d" },
        .{ "Copyright 2021 Jonathan Marler\n", 1055, "eefca0917085be6c874e5e2e72c7ff69de4ed3420759b1c82045fb7d90228da9" },
    };
    inline for (sections) |section| {
        const start = std.mem.indexOf(u8, contract.shipping_notice, section[0]) orelse return error.MissingLicenseText;
        try testing.expect(start + section[1] <= contract.shipping_notice.len);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(contract.shipping_notice[start..][0..section[1]], &digest, .{});
        try testing.expectEqualStrings(section[2], &std.fmt.bytesToHex(digest, .lower));
    }
}

test "notice parser rejects duplicate omitted changed and noncanonical fields" {
    var inventory = try notices.lockedInventory(allocator);
    defer inventory.deinit();
    const mutations = .{
        .{ "Component: sqlite\n", "Component: scintilla\n" },
        .{ "Version: 5.6.6\n", "Version: 5.6.7\n" },
        .{ "UNICODE LICENSE V3\n", "" },
        .{ "TExFlow is derived from Oleafly.", "TExFlow has no source lineage." },
        .{ "Role: reference-only\n", "Role: product-static\n" },
        .{ "PDFium transitive runtime closure: UNVERIFIED", "PDFium transitive runtime closure: VERIFIED" },
        .{ "License: https://www.scintilla.org/License.txt", "License: https://example.invalid/license" },
        .{ "\n", "\r\n" },
    };
    inline for (mutations) |mutation| {
        try testing.expect(std.mem.indexOf(u8, contract.shipping_notice, mutation[0]) != null);
        const changed = try std.mem.replaceOwned(u8, allocator, contract.shipping_notice, mutation[0], mutation[1]);
        defer allocator.free(changed);
        try testing.expectError(error.NonCanonicalNotice, notices.validateShippingNotice(allocator, inventory.records, changed));
    }
}

test "legal package contract requires exact LICENSE and notice with no extra record" {
    if (comptime !@hasDecl(notices, "validateLegalPayload")) return error.MissingLegalPayloadValidator;
    const files = [_]notices.LegalFile{
        .{ .path = "LICENSE", .bytes = contract.license },
        .{ .path = "THIRD_PARTY_NOTICES.txt", .bytes = contract.shipping_notice },
    };
    try notices.validateLegalPayload(allocator, &files);
    try notices.validateLegalPayload(allocator, &.{ files[1], files[0] });
    try testing.expectError(error.MissingLegalFile, notices.validateLegalPayload(allocator, files[0..1]));
    try testing.expectError(error.DuplicateLegalFile, notices.validateLegalPayload(allocator, &.{ files[0], files[0] }));
    try testing.expectError(error.UnexpectedLegalFile, notices.validateLegalPayload(allocator, &.{ files[0], files[1], .{ .path = "licenses/lexilla.txt", .bytes = "test-only" } }));
    try testing.expectError(error.LegalFileMismatch, notices.validateLegalPayload(allocator, &.{ .{ .path = "LICENSE", .bytes = "wrong" }, files[1] }));
    try testing.expectError(error.NonCanonicalNotice, notices.validateLegalPayload(allocator, &.{ files[0], .{ .path = "THIRD_PARTY_NOTICES.txt", .bytes = "wrong" } }));
}
