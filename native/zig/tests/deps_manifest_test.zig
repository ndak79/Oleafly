const std = @import("std");
const deps = @import("deps");
const package_contract = @import("package_contract");

const valid_manifest =
    \\{
    \\  "schema_version": 1,
    \\  "product": { "display_name": "TExFlow", "namespace": "texflow" },
    \\  "artifacts": [
    \\    {
    \\      "id": "scintilla",
    \\      "version": "5.6.6",
    \\      "purpose": "product-editor-source",
    \\      "source_url": "https://www.scintilla.org/ScintillaDownload.html",
    \\      "license_spdx": "LicenseRef-Scintilla",
    \\      "license_url": "https://www.scintilla.org/License.txt",
    \\      "url": "https://www.scintilla.org/scintilla566.tgz?download=1",
    \\      "allowed_path_prefix": "/scintilla566.tgz",
    \\      "integrity": "byte_archive",
    \\      "archive_format": "tar_gzip",
    \\      "archive_root": "scintilla/",
    \\      "tar_metadata_policy": "gnu_long_name",
    \\      "archive_size_bytes": 1822062,
    \\      "archive_sha256": "b6b08598c68fac90990d010c1142494d707530602b5320753274d045c2b02189",
    \\      "expected_entries": 296,
    \\      "dependencies": [],
    \\      "build_switches": ["product-static"]
    \\    }
    \\  ]
    \\}
;

fn expectManifestReplacementError(
    expected: anyerror,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const changed = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        deps.locked_manifest_bytes,
        needle,
        replacement,
    );
    defer std.testing.allocator.free(changed);
    var parsed = deps.parseManifest(std.testing.allocator, changed) catch |actual| {
        try std.testing.expectEqual(expected, actual);
        return;
    };
    parsed.deinit();
    return error.ExpectedManifestError;
}

fn expectLockedManifestReplacementError(
    expected: anyerror,
    needle: []const u8,
    replacement: []const u8,
) !void {
    const changed = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        deps.locked_manifest_bytes,
        needle,
        replacement,
    );
    defer std.testing.allocator.free(changed);
    var parsed = deps.parseLockedManifestBytes(std.testing.allocator, changed) catch |actual| {
        try std.testing.expectEqual(expected, actual);
        return;
    };
    parsed.deinit();
    return error.ExpectedManifestError;
}

test "manifest accepts a bounded HTTPS byte archive" {
    var parsed = try deps.parseManifest(std.testing.allocator, valid_manifest);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u16, 1), parsed.value.schema_version);
    try std.testing.expectEqualStrings("scintilla", parsed.value.artifacts[0].id);
}

test "manifest rejects non-HTTPS dependency URLs" {
    const invalid =
        \\{
        \\  "schema_version": 1,
        \\  "product": { "display_name": "TExFlow", "namespace": "texflow" },
        \\  "artifacts": [
        \\    {
        \\      "id": "scintilla",
        \\      "version": "5.6.6",
        \\      "purpose": "product-editor-source",
        \\      "source_url": "https://www.scintilla.org/ScintillaDownload.html",
        \\      "license_spdx": "LicenseRef-Scintilla",
        \\      "license_url": "https://www.scintilla.org/License.txt",
        \\      "url": "http://www.scintilla.org/scintilla566.tgz?download=1",
        \\      "allowed_path_prefix": "/scintilla566.tgz",
        \\      "integrity": "byte_archive",
        \\      "archive_format": "tar_gzip",
        \\      "archive_root": "scintilla/",
        \\      "archive_size_bytes": 1822062,
        \\      "archive_sha256": "b6b08598c68fac90990d010c1142494d707530602b5320753274d045c2b02189",
        \\      "expected_entries": 296,
        \\      "dependencies": [],
        \\      "build_switches": ["product-static"]
        \\    }
        \\  ]
        \\}
    ;

    try std.testing.expectError(
        error.NonHttpsUrl,
        deps.parseManifest(std.testing.allocator, invalid),
    );
}

fn sampleArtifact() deps.Artifact {
    return .{
        .id = "scintilla",
        .version = "5.6.6",
        .purpose = "product-editor-source",
        .source_url = "https://www.scintilla.org/ScintillaDownload.html",
        .license_spdx = "LicenseRef-Scintilla",
        .license_url = "https://www.scintilla.org/License.txt",
        .url = "https://www.scintilla.org/scintilla566.tgz?download=1",
        .allowed_path_prefix = "/scintilla566.tgz",
        .integrity = .byte_archive,
        .archive_format = .tar_gzip,
        .archive_root = "scintilla/",
        .tar_metadata_policy = .gnu_long_name,
        .archive_size_bytes = 1_822_062,
        .archive_sha256 = "b6b08598c68fac90990d010c1142494d707530602b5320753274d045c2b02189",
        .expected_entries = 296,
        .dependencies = &.{},
        .build_switches = &.{"product-static"},
    };
}

test "artifact identity, origin, bounds, archive, digest, and switches fail closed" {
    var artifact = sampleArtifact();

    artifact.id = "";
    try std.testing.expectError(error.MissingIdentity, deps.validateArtifact(artifact));
    artifact = sampleArtifact();
    artifact.source_url = "";
    try std.testing.expectError(error.MissingSourceIdentity, deps.validateArtifact(artifact));
    artifact = sampleArtifact();
    artifact.license_spdx = "";
    try std.testing.expectError(error.MissingLicenseIdentity, deps.validateArtifact(artifact));
    artifact = sampleArtifact();
    artifact.source_url = "https://example.com/ScintillaDownload.html";
    try std.testing.expectError(error.UnapprovedSourceIdentity, deps.validateArtifact(artifact));
    artifact = sampleArtifact();
    artifact.license_url = "https://example.com/License.txt";
    try std.testing.expectError(error.UnapprovedLicenseIdentity, deps.validateArtifact(artifact));

    artifact = sampleArtifact();
    artifact.url = "https://example.com/scintilla566.tgz?download=1";
    try std.testing.expectError(error.UnapprovedHost, deps.validateArtifact(artifact));
    artifact = sampleArtifact();
    artifact.url = "https://www.scintilla.org/not-scintilla.tgz";
    try std.testing.expectError(error.UnapprovedPath, deps.validateArtifact(artifact));

    artifact = sampleArtifact();
    artifact.archive_sha256 = "B6B08598C68FAC90990D010C1142494D707530602B5320753274D045C2B02189";
    try std.testing.expectError(error.InvalidDigest, deps.validateArtifact(artifact));
    artifact = sampleArtifact();
    artifact.archive_size_bytes = 0;
    try std.testing.expectError(error.InvalidSize, deps.validateArtifact(artifact));
    artifact = sampleArtifact();
    artifact.download_limit_bytes = artifact.archive_size_bytes.? - 1;
    try std.testing.expectError(error.InvalidSizeLimit, deps.validateArtifact(artifact));

    artifact = sampleArtifact();
    artifact.integrity = .canonical_tree;
    try std.testing.expectError(error.InconsistentIntegrityMode, deps.validateArtifact(artifact));
    artifact = sampleArtifact();
    artifact.archive_root = "../scintilla/";
    try std.testing.expectError(error.InvalidArchiveRoot, deps.validateArtifact(artifact));

    const unknown_switches = [_][]const u8{"ambient-toolchain"};
    artifact = sampleArtifact();
    artifact.build_switches = &unknown_switches;
    try std.testing.expectError(error.UnknownBuildSwitch, deps.validateArtifact(artifact));
}

test "manifest rejects duplicate IDs and dependency cycles" {
    const duplicate = sampleArtifact();
    const duplicate_artifacts = [_]deps.Artifact{ duplicate, duplicate };
    try std.testing.expectError(
        error.DuplicateArtifactId,
        deps.validateDependencyGraph(&duplicate_artifacts),
    );

    const a_dependencies = [_][]const u8{"b"};
    const b_dependencies = [_][]const u8{"a"};
    var a = sampleArtifact();
    a.id = "a";
    a.dependencies = &a_dependencies;
    var b = sampleArtifact();
    b.id = "b";
    b.dependencies = &b_dependencies;
    const cyclic = [_]deps.Artifact{ a, b };
    try std.testing.expectError(
        error.DependencyCycle,
        deps.validateDependencyGraph(&cyclic),
    );
}

test "typed JSON rejects duplicate and unknown fields" {
    const duplicate_field =
        \\{
        \\  "schema_version": 1,
        \\  "schema_version": 1,
        \\  "product": { "display_name": "TExFlow", "namespace": "texflow" },
        \\  "artifacts": []
        \\}
    ;
    try std.testing.expectError(
        error.DuplicateField,
        deps.parseManifest(std.testing.allocator, duplicate_field),
    );

    const unknown_field =
        \\{
        \\  "schema_version": 1,
        \\  "product": { "display_name": "TExFlow", "namespace": "texflow" },
        \\  "artifacts": [],
        \\  "allow_ambient_network": true
        \\}
    ;
    try std.testing.expectError(
        error.UnknownField,
        deps.parseManifest(std.testing.allocator, unknown_field),
    );
}

test "committed lock covers the complete reviewed native dependency set" {
    var parsed = try deps.parseLockedManifest(std.testing.allocator);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 11), parsed.value.artifacts.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.git_sources.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.attestations.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.trusted_roots.len);

    const ucd = deps.findArtifact(parsed.value, "unicode-ucd").?;
    try std.testing.expectEqual(@as(usize, 74), ucd.inventory.len);
    try std.testing.expectEqual(@as(u64, 41_500_790), ucd.expected_expanded_bytes.?);
    try std.testing.expectEqual(@as(usize, 12), ucd.retained_members.len);
    try std.testing.expectEqualStrings("2025-08-15", ucd.version_marker.?);

    const github_cli = deps.findArtifact(parsed.value, "github-cli").?;
    try std.testing.expectEqual(@as(usize, 2), github_cli.retained_members.len);
    try std.testing.expectEqualStrings("2.100.0", github_cli.executable_version.?);
    try std.testing.expect(github_cli.allow_zip_data_descriptor);
    try std.testing.expectEqualSlices(u16, &.{0x5455}, github_cli.allowed_zip_extra_fields);

    const pdfium = deps.findArtifact(parsed.value, "pdfium-reference").?;
    const expected_exact = [_][]const u8{ "LICENSE", "PDFiumConfig.cmake", "VERSION", "args.gn" };
    const expected_prefixes = [_][]const u8{ "bin/", "include/", "lib/", "licenses/" };
    try std.testing.expectEqual(expected_exact.len, pdfium.allowed_exact_paths.len);
    for (expected_exact, pdfium.allowed_exact_paths) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual);
    }
    try std.testing.expectEqual(expected_prefixes.len, pdfium.allowed_path_prefixes.len);
    for (expected_prefixes, pdfium.allowed_path_prefixes) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual);
    }

    const accessibility = deps.findArtifact(parsed.value, "accessibility-insights").?;
    try std.testing.expectEqual(deps.FetchPolicy.operator_provisioned, accessibility.fetch_policy);

    try std.testing.expectEqualStrings(
        "a0fd6e66af74304c9b4605665435f4e88849e046",
        parsed.value.git_sources[0].commit,
    );
    try std.testing.expectEqual(@as(u64, 18_096), parsed.value.attestations[0].jsonl_size_bytes);
    try std.testing.expectEqual(@as(usize, 13), parsed.value.attestations[0].bundle_query_fields.len);
    try std.testing.expectEqualStrings("skv", parsed.value.attestations[0].bundle_query_fields[7]);
    try std.testing.expectEqual(@as(u64, 34_636), parsed.value.trusted_roots[0].size_bytes);
}

test "committed executable signer identities are exact lock data" {
    try expectLockedManifestReplacementError(
        error.LockMismatch,
        "2E3D67018EE2980D0C7910A24BB60E195E7068F2",
        "3E3D67018EE2980D0C7910A24BB60E195E7068F2",
    );
    try expectLockedManifestReplacementError(
        error.LockMismatch,
        "CN=Intel Corporation, O=Intel Corporation, S=California, C=US",
        "CN=Other Corporation, O=Intel Corporation, S=California, C=US",
    );
}

test "locked manifest digest rejects otherwise schema-valid field drift" {
    try expectLockedManifestReplacementError(
        error.LockMismatch,
        "\"version\": \"5.6.6\"",
        "\"version\": \"5.6.7\"",
    );
    try expectLockedManifestReplacementError(
        error.LockMismatch,
        "\"download_limit_bytes\": 4194304",
        "\"download_limit_bytes\": 4194305",
    );
}

test "canonical tar lock separates files, logical entries, payload, and tar envelope" {
    var parsed = try deps.parseLockedManifest(std.testing.allocator);
    defer parsed.deinit();

    const pdfium_source = deps.findArtifact(parsed.value, "pdfium-root-source").?;
    try std.testing.expectEqual(@as(u32, 5_548), pdfium_source.expected_entries);
    try std.testing.expectEqual(@as(u32, 5_400), pdfium_source.expected_regular_files.?);
    try std.testing.expectEqual(@as(u64, 40_484_895), pdfium_source.expected_expanded_bytes.?);
    try std.testing.expectEqual(@as(u64, 64 * 1024 * 1024), pdfium_source.tar_stream_limit_bytes.?);
    try std.testing.expect(pdfium_source.tar_stream_limit_bytes.? > pdfium_source.expanded_limit_bytes);
}

test "committed lock rejects digest drift and inconsistent inventory bytes" {
    const changed_digest = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        deps.locked_manifest_bytes,
        "b6b08598c68fac90990d010c1142494d707530602b5320753274d045c2b02189",
        "0000000000000000000000000000000000000000000000000000000000000000",
    );
    defer std.testing.allocator.free(changed_digest);
    try std.testing.expectError(
        error.LockMismatch,
        deps.parseLockedManifestBytes(std.testing.allocator, changed_digest),
    );

    const changed_size = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        deps.locked_manifest_bytes,
        "\"path\": \"ArabicShaping.txt\", \"size_bytes\": 41441",
        "\"path\": \"ArabicShaping.txt\", \"size_bytes\": 41442",
    );
    defer std.testing.allocator.free(changed_size);
    try std.testing.expectError(
        error.LockMismatch,
        deps.parseLockedManifestBytes(std.testing.allocator, changed_size),
    );
    try std.testing.expectError(
        error.InventoryByteCountMismatch,
        deps.parseManifest(std.testing.allocator, changed_size),
    );
}

test "committed lock rejects duplicate archive inventory paths" {
    const duplicate_path = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        deps.locked_manifest_bytes,
        "auxiliary/WordBreakProperty.txt",
        "ArabicShaping.txt",
    );
    defer std.testing.allocator.free(duplicate_path);
    try std.testing.expectError(
        error.LockMismatch,
        deps.parseLockedManifestBytes(std.testing.allocator, duplicate_path),
    );
    try std.testing.expectError(
        error.DuplicateMemberPath,
        deps.parseManifest(std.testing.allocator, duplicate_path),
    );
}

test "source package carries Unicode-3.0 notice and excludes UCD archives and caches" {
    const notice = package_contract.notice;
    const package_manifest = package_contract.zon;

    try std.testing.expect(std.mem.startsWith(u8, notice, "TExFlow\n"));
    try std.testing.expect(std.mem.indexOf(u8, notice, "SPDX-License-Identifier: Unicode-3.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, notice, "UNICODE LICENSE V3") != null);
    try std.testing.expect(std.mem.indexOf(u8, notice, "Copyright © 1991-2026 Unicode, Inc.") != null);
    try std.testing.expect(std.mem.indexOf(u8, notice, "THE DATA FILES AND SOFTWARE ARE PROVIDED \"AS IS\"") != null);

    try std.testing.expect(std.mem.indexOf(u8, package_manifest, "\"NOTICE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, package_manifest, "tools/zig/.cache") == null);
    try std.testing.expect(std.mem.indexOf(u8, package_manifest, "archive.bin") == null);
    try std.testing.expect(std.mem.indexOf(u8, package_manifest, "UCD.zip") == null);
}

test "attestation and trusted-root locks reject origin and identity drift" {
    try expectManifestReplacementError(
        error.UnapprovedAttestationApiHost,
        "https://api.github.com/repos/bblanchon/pdfium-binaries/attestations/sha256:",
        "https://example.invalid/repos/bblanchon/pdfium-binaries/attestations/sha256:",
    );
    try expectManifestReplacementError(
        error.UnapprovedAttestationApiQuery,
        "predicate_type=provenance&per_page=100",
        "predicate_type=release&per_page=100",
    );
    try expectManifestReplacementError(
        error.UnapprovedBundleHost,
        "\"bundle_host\": \"tmaproduction.blob.core.windows.net\"",
        "\"bundle_host\": \"example.invalid\"",
    );
    try expectManifestReplacementError(
        error.UnapprovedBundlePath,
        "\"bundle_path\": \"/attestations/103962638/2026/08/31/44147842.json.sn\"",
        "\"bundle_path\": \"/attestations/103962638/latest/release.zip\"",
    );
    try expectManifestReplacementError(
        error.DuplicateBundleQueryField,
        "\"sktid\", \"skv\"",
        "\"sktid\", \"sktid\"",
    );
    try expectManifestReplacementError(
        error.WrongSubjectDigest,
        "\"subject_sha256\": \"61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41\"",
        "\"subject_sha256\": \"0000000000000000000000000000000000000000000000000000000000000000\"",
    );
    try expectManifestReplacementError(
        error.InvalidTrustedRootSnapshot,
        "\"snapshot_date\": \"2026-09-04\"",
        "\"snapshot_date\": \"2026-99-99\"",
    );
}

test "cache selector round trips one strict immutable generation name" {
    var buffer: [deps.cache_selector_max_bytes]u8 = undefined;
    const encoded = try deps.formatCacheSelector(
        &buffer,
        "g-0123456789abcdef01234567",
    );
    try std.testing.expectEqualStrings(
        "texflow-native-cache-v2\ng-0123456789abcdef01234567\n",
        encoded,
    );
    try std.testing.expectEqualStrings(
        "g-0123456789abcdef01234567",
        try deps.parseCacheSelector(encoded),
    );
}

test "cache selector rejects traversal aliases and non-canonical bytes" {
    const invalid = [_][]const u8{
        "texflow-native-cache-v2\n../legacy\n",
        "texflow-native-cache-v2\ng-0123456789ABCDEF01234567\n",
        "texflow-native-cache-v2\ng-0123456789abcdef0123456\n",
        "texflow-native-cache-v2\ng-0123456789abcdef01234567",
        "texflow-native-cache-v2\ng-0123456789abcdef01234567\nextra\n",
        "texflow-native-cache-v1\ng-0123456789abcdef01234567\n",
    };
    for (invalid) |bytes| {
        try std.testing.expectError(error.InvalidCacheSelector, deps.parseCacheSelector(bytes));
    }
}

test "developer guide treats the V2 native dependency cache as one opaque root" {
    const guide = package_contract.development_guide;
    try std.testing.expect(std.mem.indexOf(
        u8,
        guide,
        "tools/zig/.cache/native-deps/<artifact-id>/",
    ) == null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        guide,
        ".v2/<artifact-id>/generations/g-<24-lowercase-hex>/",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        guide,
        "move the entire separately\nprefilled and verified opaque cache root as one unit",
    ) != null);
}

fn exerciseManifestParser(allocator: std.mem.Allocator) anyerror!void {
    var parsed = try deps.parseManifest(allocator, valid_manifest);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("scintilla", parsed.value.artifacts[0].id);
}

fn exerciseLockedManifestParser(allocator: std.mem.Allocator) anyerror!void {
    var parsed = try deps.parseLockedManifestBytes(allocator, deps.locked_manifest_bytes);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("TExFlow", parsed.value.product.display_name);
}

fn checkAllocationFailuresThroughOnePast(comptime exercise: anytype) !usize {
    const max_allocations = 16_384;
    for (0..max_allocations) |fail_index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        exercise(failing.allocator()) catch |err| {
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
        return fail_index;
    }
    return error.AllocationCampaignLimitExceeded;
}

test "manifest parsers release every allocation through and one past success" {
    const manifest_allocations = try checkAllocationFailuresThroughOnePast(
        exerciseManifestParser,
    );
    const locked_manifest_allocations = try checkAllocationFailuresThroughOnePast(
        exerciseLockedManifestParser,
    );
    try std.testing.expectEqual(@as(usize, 3), manifest_allocations);
    try std.testing.expectEqual(@as(usize, 6), locked_manifest_allocations);
}
