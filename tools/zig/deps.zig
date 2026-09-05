const std = @import("std");
const builtin = @import("builtin");

pub const Integrity = enum {
    byte_archive,
    canonical_tree,
};

pub const ArchiveFormat = enum {
    tar_gzip,
    restricted_zip,
    direct_file,
};

pub const TarMetadataPolicy = enum {
    none,
    gnu_long_name,
    gitiles_pax,
    github_codeload_pax,
};

pub const FetchPolicy = enum {
    ordinary,
    operator_provisioned,
};

pub const MemberLock = struct {
    path: []const u8,
    size_bytes: u64,
    sha256: ?[]const u8 = null,
    kind: MemberKind = .file,
};

pub const MemberKind = enum {
    file,
    directory,
};

pub const AuthenticodeLock = struct {
    subject: []const u8,
    thumbprint_sha1: []const u8,
};

pub const BuildProfile = struct {
    target: []const u8,
    cpu_model: []const u8,
    optimize: []const u8,
    strip: bool,
    app_owned_language: []const u8,
    ui_subsystem: []const u8,
    worker_subsystem: []const u8,
};

pub const InternalLink = struct {
    path: []const u8,
    target: []const u8,
};

pub const GitSource = struct {
    id: []const u8,
    version: []const u8,
    purpose: []const u8,
    source_url: []const u8,
    license_spdx: []const u8,
    license_url: []const u8,
    repository_url: []const u8,
    commit: []const u8,
    tree: []const u8,
    auto_update: bool,
    internal_links: []const InternalLink,
};

pub const AttestationLock = struct {
    id: []const u8,
    api_url: []const u8,
    accept: []const u8,
    api_version: []const u8,
    repository_id: u64,
    result_count: u16,
    raw_snappy_size_bytes: u64,
    raw_snappy_sha256: []const u8,
    decompressed_json_size_bytes: u64,
    jsonl_path: []const u8,
    jsonl_size_bytes: u64,
    jsonl_sha256: []const u8,
    predicate_type: []const u8,
    subject_count: u16,
    subject_name: []const u8,
    subject_sha256: []const u8,
    bundle_host: []const u8,
    bundle_path: []const u8,
    bundle_query_fields: []const []const u8,
    certificate_identity: []const u8,
    oidc_issuer: []const u8,
    workflow_repository: []const u8,
    source_ref: []const u8,
    source_digest: []const u8,
    runner_environment: []const u8,
    invocation_url: []const u8,
};

pub const TrustedRootLock = struct {
    id: []const u8,
    path: []const u8,
    snapshot_date: []const u8,
    size_bytes: u64,
    sha256: []const u8,
    line_count: u16,
    media_type: []const u8,
    instances: []const []const u8,
    independent_acquisitions: u16,
};

pub const Product = struct {
    display_name: []const u8,
    namespace: []const u8,
};

pub const Artifact = struct {
    id: []const u8,
    version: []const u8,
    purpose: []const u8,
    source_url: []const u8,
    license_spdx: []const u8,
    license_url: []const u8,
    url: []const u8,
    allowed_path_prefix: []const u8,
    integrity: Integrity,
    archive_format: ArchiveFormat,
    archive_root: []const u8,
    tar_metadata_policy: TarMetadataPolicy = .none,
    archive_size_bytes: ?u64,
    archive_sha256: ?[]const u8,
    canonical_tree_sha256: ?[]const u8 = null,
    expected_entries: u32,
    expected_regular_files: ?u32 = null,
    download_limit_bytes: u64 = 16 * 1024 * 1024,
    expanded_limit_bytes: u64 = 128 * 1024 * 1024,
    tar_stream_limit_bytes: ?u64 = null,
    expected_expanded_bytes: ?u64 = null,
    inventory: []const MemberLock = &.{},
    retained_members: []const MemberLock = &.{},
    allowed_exact_paths: []const []const u8 = &.{},
    allowed_path_prefixes: []const []const u8 = &.{},
    version_marker: ?[]const u8 = null,
    license_notice: ?[]const u8 = null,
    allow_zip_data_descriptor: bool = false,
    allowed_zip_extra_fields: []const u16 = &.{},
    executable_version: ?[]const u8 = null,
    commit: ?[]const u8 = null,
    package_hash: ?[]const u8 = null,
    authenticode: ?AuthenticodeLock = null,
    fetch_policy: FetchPolicy = .ordinary,
    dependencies: []const []const u8,
    build_switches: []const []const u8,
};

pub const Manifest = struct {
    schema_version: u16,
    product: Product,
    build_profile: ?BuildProfile = null,
    artifacts: []const Artifact,
    git_sources: []const GitSource = &.{},
    attestations: []const AttestationLock = &.{},
    trusted_roots: []const TrustedRootLock = &.{},
};

pub const locked_manifest_bytes = @embedFile("native-deps.json");
pub const locked_manifest_sha256 =
    "58ecebe7665c1624edec379778bda99e25e033ef7ce368a473b442f119ad6e5e";
pub const locked_pdfium_attestation_bytes =
    @embedFile("attestations/pdfium-chromium-8035-win-x64.jsonl");
const locked_pdfium_integrated_time: i64 = 1_788_183_009;
pub const locked_github_trusted_root_bytes =
    @embedFile("attestations/github-attestation-trusted-root-2026-09-04.jsonl");
pub const locked_pdfium_snappy_bytes =
    @embedFile("attestations/pdfium-chromium-8035-win-x64.snappy");

pub const cache_v2_directory = ".v2";
pub const cache_generations_directory = "generations";
pub const cache_quarantine_directory = "quarantine";
pub const cache_selector_file = "current";
pub const cache_generation_name_bytes = 26;
pub const cache_selector_max_bytes =
    "texflow-native-cache-v2\n".len + cache_generation_name_bytes + 1;

const cache_selector_prefix = "texflow-native-cache-v2\n";

pub fn validateCacheGenerationName(name: []const u8) !void {
    if (name.len != cache_generation_name_bytes or !std.mem.startsWith(u8, name, "g-")) {
        return error.InvalidCacheSelector;
    }
    for (name[2..]) |byte| {
        if (!std.ascii.isDigit(byte) and !(byte >= 'a' and byte <= 'f')) {
            return error.InvalidCacheSelector;
        }
    }
}

pub fn formatCacheSelector(
    buffer: *[cache_selector_max_bytes]u8,
    generation_name: []const u8,
) ![]const u8 {
    try validateCacheGenerationName(generation_name);
    return std.fmt.bufPrint(
        buffer,
        "{s}{s}\n",
        .{ cache_selector_prefix, generation_name },
    ) catch return error.InvalidCacheSelector;
}

pub fn parseCacheSelector(bytes: []const u8) ![]const u8 {
    if (bytes.len != cache_selector_max_bytes or
        !std.mem.startsWith(u8, bytes, cache_selector_prefix) or
        bytes[bytes.len - 1] != '\n')
    {
        return error.InvalidCacheSelector;
    }
    const generation_name = bytes[cache_selector_prefix.len .. bytes.len - 1];
    try validateCacheGenerationName(generation_name);
    return generation_name;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 2 and std.mem.eql(u8, args[1], "audit-evidence")) {
        const summary = try validatePdfiumEvidence(
            allocator,
            locked_pdfium_attestation_bytes,
            locked_github_trusted_root_bytes,
        );
        std.debug.print(
            "pdfium-evidence subjects={d} matching={d}\n",
            .{ summary.subjects, summary.matching_subjects },
        );
        return;
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "audit-ucd")) {
        var manifest = try parseLockedManifest(allocator);
        defer manifest.deinit();
        const artifact = findArtifact(manifest.value, "unicode-ucd") orelse
            return error.MissingUnicodeArtifact;
        const archive_size = artifact.archive_size_bytes orelse
            return error.InconsistentIntegrityMode;
        const archive = try std.Io.Dir.cwd().readFileAlloc(
            init.io,
            args[2],
            allocator,
            .limited(std.math.cast(usize, archive_size + 1) orelse
                return error.ArchiveCompressedTooLarge),
        );
        defer allocator.free(archive);
        if (archive.len != archive_size) return error.ArchiveSizeMismatch;
        try verifySha256(archive, artifact.archive_sha256.?);
        const summary = try inspectZip(allocator, archive, zipPolicyForArtifact(artifact));
        if (summary.entries != artifact.expected_entries or
            summary.content_bytes != artifact.expected_expanded_bytes.?)
        {
            return error.ZipInventoryMismatch;
        }
        std.debug.print(
            "ucd-audit entries={d} files={d} bytes={d}\n",
            .{ summary.entries, summary.regular_files, summary.content_bytes },
        );
        return;
    }
    return error.InvalidArguments;
}

fn zipPolicyForArtifact(artifact: Artifact) ZipPolicy {
    return zipPolicyForArtifactWithFold(artifact, asciiCollisionFold);
}

fn zipPolicyForArtifactWithFold(
    artifact: Artifact,
    collision_fold: CollisionFoldFn,
) ZipPolicy {
    return .{
        .max_archive_bytes = std.math.cast(usize, artifact.download_limit_bytes) orelse
            std.math.maxInt(usize),
        .max_entries = std.math.cast(u16, artifact.expected_entries) orelse
            std.math.maxInt(u16),
        .max_member_bytes = artifact.expanded_limit_bytes,
        .max_total_bytes = artifact.expanded_limit_bytes,
        .max_compression_ratio = 1_024,
        .allow_data_descriptor = artifact.allow_zip_data_descriptor,
        .allowed_extra_field_ids = artifact.allowed_zip_extra_fields,
        .inventory = artifact.inventory,
        .retained_members = artifact.retained_members,
        .collision_fold = collision_fold,
    };
}

pub fn parseLockedManifest(allocator: std.mem.Allocator) !std.json.Parsed(Manifest) {
    return parseLockedManifestBytes(allocator, locked_manifest_bytes);
}

pub fn parseLockedManifestBytes(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !std.json.Parsed(Manifest) {
    verifySha256(bytes, locked_manifest_sha256) catch return error.LockMismatch;
    var parsed = try parseManifest(allocator, bytes);
    errdefer parsed.deinit();
    try validateLockedManifest(parsed.value);
    return parsed;
}

pub fn findArtifact(manifest: Manifest, id: []const u8) ?Artifact {
    for (manifest.artifacts) |artifact| {
        if (std.mem.eql(u8, artifact.id, id)) return artifact;
    }
    return null;
}

const ExpectedArtifact = struct {
    id: []const u8,
    size: ?u64,
    digest: ?[]const u8,
    tree_digest: ?[]const u8 = null,
    entries: u32,
    regular_files: ?u32 = null,
    tar_metadata_policy: TarMetadataPolicy = .none,
};

const expected_artifacts = [_]ExpectedArtifact{
    .{ .id = "scintilla", .size = 1_822_062, .digest = "b6b08598c68fac90990d010c1142494d707530602b5320753274d045c2b02189", .entries = 296, .tar_metadata_policy = .gnu_long_name },
    .{ .id = "lexilla", .size = 1_116_541, .digest = "4d9e64263c337034a06f9c67f330c605764cac02aee83c06f6c21f9527a71628", .entries = 993 },
    .{ .id = "unicode-ucd", .size = 9_101_877, .digest = "2066d1909b2ea93916ce092da1c0ee4808ea3ef8407c94b4f14f5b7eb263d28e", .entries = 74 },
    .{ .id = "pdfium-reference", .size = 3_772_597, .digest = "61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41", .entries = 50 },
    .{ .id = "pdfium-root-source", .size = null, .digest = null, .tree_digest = "eb5b5b34b65e795379f55a3109cc31b843395e8e6be737b2d2c35f2725c2e499", .entries = 5_548, .regular_files = 5_400, .tar_metadata_policy = .gitiles_pax },
    .{ .id = "pdfium-build-recipe", .size = 142_719, .digest = "00d9ef134460216465b19e11e59cf982dd1a4391d12be0f5ccf94466abcb84e6", .entries = 106, .tar_metadata_policy = .github_codeload_pax },
    .{ .id = "sqlite", .size = 3_283_177, .digest = "0e9483900e92cd5de8fd48d16bf9200145a61f7fd5be542a5ac81d8a9516eb9c", .entries = 54 },
    .{ .id = "zigwin32", .size = 7_358_806, .digest = "6fec64480a16e7797e0a010faef67a5fc22561551a955fcb73a023f0a114f8d7", .entries = 698, .tar_metadata_policy = .github_codeload_pax },
    .{ .id = "presentmon", .size = 956_768, .digest = "9bec3083069f58f911e6a512f4806db51a27bd096103087bc1d05ef54c80a191", .entries = 1 },
    .{ .id = "accessibility-insights", .size = 8_732_672, .digest = "bf4de9ac631bdac8a6cd5f5e7963bc6f9c1bc6261371ae7cd7170531ca6ba9a5", .entries = 1 },
    .{ .id = "github-cli", .size = 15_326_700, .digest = "227e35230b25db3fa1b997bab7cf4d67df0470a3b75b99e4ee66bce1a7cd4e72", .entries = 2 },
};

fn validateLockedManifest(manifest: Manifest) !void {
    const profile = manifest.build_profile orelse return error.LockMismatch;
    if (!std.mem.eql(u8, profile.target, "x86_64-windows-msvc") or
        !std.mem.eql(u8, profile.cpu_model, "baseline") or
        !std.mem.eql(u8, profile.optimize, "ReleaseSafe") or
        !profile.strip or
        !std.mem.eql(u8, profile.app_owned_language, "Zig") or
        !std.mem.eql(u8, profile.ui_subsystem, "windows") or
        !std.mem.eql(u8, profile.worker_subsystem, "console"))
    {
        return error.LockMismatch;
    }
    if (manifest.artifacts.len != expected_artifacts.len) return error.LockMismatch;
    for (expected_artifacts) |expected| {
        const artifact = findArtifact(manifest, expected.id) orelse return error.LockMismatch;
        if (artifact.archive_size_bytes != expected.size or
            !optionalStringEqual(artifact.archive_sha256, expected.digest) or
            !optionalStringEqual(artifact.canonical_tree_sha256, expected.tree_digest) or
            artifact.expected_entries != expected.entries or
            artifact.expected_regular_files != expected.regular_files or
            artifact.tar_metadata_policy != expected.tar_metadata_policy)
        {
            return error.LockMismatch;
        }
    }

    const ucd = findArtifact(manifest, "unicode-ucd") orelse return error.LockMismatch;
    if (ucd.inventory.len != 74 or ucd.retained_members.len != 12 or
        ucd.expected_expanded_bytes != 41_500_790 or
        !optionalStringEqual(ucd.version_marker, "2025-08-15") or
        !optionalStringEqual(ucd.license_notice, "Unicode License v3") or
        ucd.allowed_zip_extra_fields.len != 2 or
        ucd.allowed_zip_extra_fields[0] != 0x5455 or
        ucd.allowed_zip_extra_fields[1] != 0x7875)
    {
        return error.LockMismatch;
    }

    const github_cli = findArtifact(manifest, "github-cli") orelse return error.LockMismatch;
    if (github_cli.inventory.len != 2 or github_cli.retained_members.len != 2 or
        !optionalStringEqual(github_cli.executable_version, "2.100.0") or
        !authenticodeLockEqual(
            github_cli.authenticode,
            "CN=\"GitHub, Inc.\", O=\"GitHub, Inc.\", L=San Francisco, S=California, C=US",
            "2E3D67018EE2980D0C7910A24BB60E195E7068F2",
        ))
    {
        return error.LockMismatch;
    }
    const presentmon = findArtifact(manifest, "presentmon") orelse return error.LockMismatch;
    if (!optionalStringEqual(presentmon.executable_version, "2.5.1") or
        !authenticodeLockEqual(
            presentmon.authenticode,
            "CN=Intel Corporation, O=Intel Corporation, S=California, C=US",
            "4B923D748E9EBE27252FDBA244342C1888A2D23E",
        )) return error.LockMismatch;
    const accessibility = findArtifact(manifest, "accessibility-insights") orelse
        return error.LockMismatch;
    if (!optionalStringEqual(accessibility.executable_version, "1.1.2924.01") or
        !authenticodeLockEqual(
            accessibility.authenticode,
            "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US",
            "8F985BE8FD256085C90A95D3C74580511A1DB975",
        )) return error.LockMismatch;

    if (manifest.git_sources.len != 1) return error.LockMismatch;
    const git = manifest.git_sources[0];
    if (!std.mem.eql(u8, git.id, "depot-tools") or
        !std.mem.eql(
            u8,
            git.source_url,
            "https://chromium.googlesource.com/chromium/tools/depot_tools/+/a0fd6e66af74304c9b4605665435f4e88849e046",
        ) or
        !std.mem.eql(
            u8,
            git.license_url,
            "https://chromium.googlesource.com/chromium/tools/depot_tools/+/a0fd6e66af74304c9b4605665435f4e88849e046/LICENSE",
        ) or
        !std.mem.eql(
            u8,
            git.repository_url,
            "https://chromium.googlesource.com/chromium/tools/depot_tools.git",
        ) or
        !std.mem.eql(u8, git.commit, "a0fd6e66af74304c9b4605665435f4e88849e046") or
        !std.mem.eql(u8, git.tree, "36d9263be5a52a8655d2c2bd63244019a96b3757") or
        git.auto_update or git.internal_links.len != 3)
    {
        return error.LockMismatch;
    }
    const expected_links = [_]InternalLink{
        .{ .path = "cros_sdk", .target = "cros" },
        .{ .path = "gerrit", .target = "cros" },
        .{ .path = "luci-auth-fido2-plugin", .target = "luci_auth_fido2_plugin.py" },
    };
    for (git.internal_links, expected_links) |actual, expected| {
        if (!std.mem.eql(u8, actual.path, expected.path) or
            !std.mem.eql(u8, actual.target, expected.target))
        {
            return error.LockMismatch;
        }
    }

    if (manifest.attestations.len != 1) return error.LockMismatch;
    const attestation = manifest.attestations[0];
    if (!std.mem.eql(u8, attestation.id, "pdfium-chromium-8035-win-x64") or
        attestation.repository_id != 103_962_638 or
        attestation.result_count != 1 or
        attestation.raw_snappy_size_bytes != 17_297 or
        !std.mem.eql(u8, attestation.raw_snappy_sha256, "ae84cc3ca94398519f7f67bdd33a7d29f589a74d88734f544efa815e1f39046c") or
        attestation.decompressed_json_size_bytes != 18_095 or
        attestation.jsonl_size_bytes != 18_096 or
        !std.mem.eql(u8, attestation.jsonl_sha256, "1f84f3d920a8c3ad5dc480899631eef877c43f99d1e85b634af55570f51e2ee6") or
        attestation.subject_count != 45 or
        !std.mem.eql(u8, attestation.subject_name, "pdfium-win-x64.tgz") or
        !std.mem.eql(u8, attestation.subject_sha256, "61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41") or
        attestation.bundle_query_fields.len != bundle_query_fields.len)
    {
        return error.LockMismatch;
    }
    for (bundle_query_fields, attestation.bundle_query_fields) |expected, actual| {
        if (!std.mem.eql(u8, expected, actual)) return error.LockMismatch;
    }

    if (manifest.trusted_roots.len != 1) return error.LockMismatch;
    const root = manifest.trusted_roots[0];
    if (!std.mem.eql(u8, root.id, "github-attestation-2026-09-04") or
        root.size_bytes != 34_636 or
        !std.mem.eql(u8, root.sha256, "db07310827da2ae2798ec7eefc5daf8432506ce458d5bc30cd2feba03708d239") or
        root.line_count != 2 or root.instances.len != 2 or
        root.independent_acquisitions != 2)
    {
        return error.LockMismatch;
    }
}

fn optionalStringEqual(actual: ?[]const u8, expected: ?[]const u8) bool {
    if (actual == null or expected == null) return actual == null and expected == null;
    return std.mem.eql(u8, actual.?, expected.?);
}

fn authenticodeLockEqual(
    actual: ?AuthenticodeLock,
    expected_subject: []const u8,
    expected_thumbprint: []const u8,
) bool {
    const signature = actual orelse return false;
    return std.mem.eql(u8, signature.subject, expected_subject) and
        std.mem.eql(u8, signature.thumbprint_sha1, expected_thumbprint);
}

pub fn parseManifest(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !std.json.Parsed(Manifest) {
    var parsed = try std.json.parseFromSlice(Manifest, allocator, bytes, .{
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
    });
    errdefer parsed.deinit();

    if (parsed.value.schema_version != 1) return error.UnsupportedSchemaVersion;
    if (!std.mem.eql(u8, parsed.value.product.display_name, "TExFlow") or
        !std.mem.eql(u8, parsed.value.product.namespace, "texflow"))
    {
        return error.InvalidProductIdentity;
    }

    for (parsed.value.artifacts) |artifact| {
        try validateArtifact(artifact);
    }
    try validateDependencyGraph(parsed.value.artifacts);
    for (parsed.value.git_sources) |source| try validateGitSource(source);
    for (parsed.value.attestations) |attestation| try validateAttestationLock(attestation);
    for (parsed.value.trusted_roots) |root| try validateTrustedRootLock(root);

    return parsed;
}

fn validateGitSource(source: GitSource) !void {
    if (source.id.len == 0 or source.version.len == 0 or source.purpose.len == 0 or
        source.license_spdx.len == 0)
    {
        return error.MissingIdentity;
    }
    const source_uri = try validateHttpsUrl(source.source_url);
    var source_host_buffer: [std.Io.net.HostName.max_len]u8 = undefined;
    const source_host = (try source_uri.getHost(&source_host_buffer)).bytes;
    if (!std.mem.eql(u8, source_host, "chromium.googlesource.com")) {
        return error.UnapprovedGitSourceHost;
    }
    _ = try validateHttpsUrl(source.license_url);
    const repository_uri = try validateHttpsUrl(source.repository_url);
    var repository_host_buffer: [std.Io.net.HostName.max_len]u8 = undefined;
    const repository_host = (try repository_uri.getHost(&repository_host_buffer)).bytes;
    if (!std.mem.eql(u8, repository_host, "chromium.googlesource.com")) {
        return error.UnapprovedGitSourceHost;
    }
    if (source.commit.len != 40 or !isLowerHex(source.commit) or
        source.tree.len != 40 or !isLowerHex(source.tree) or source.auto_update)
    {
        return error.InvalidGitSourceLock;
    }
    for (source.internal_links, 0..) |link, index| {
        try validateArchivePath(link.path);
        try validateArchivePath(link.target);
        for (source.internal_links[0..index]) |previous| {
            if (std.mem.eql(u8, previous.path, link.path)) return error.DuplicateInternalLink;
        }
    }
}

fn validateAttestationLock(attestation: AttestationLock) !void {
    const api_uri = validateHttpsUrl(attestation.api_url) catch
        return error.UnapprovedAttestationApiHost;
    if (api_uri.port != null) return error.UnapprovedAttestationApiHost;
    var host_buffer: [std.Io.net.HostName.max_len]u8 = undefined;
    const host = (api_uri.getHost(&host_buffer) catch
        return error.UnapprovedAttestationApiHost).bytes;
    if (!std.mem.eql(u8, host, "api.github.com")) {
        return error.UnapprovedAttestationApiHost;
    }
    var path_buffer: [4096]u8 = undefined;
    const path = api_uri.path.toRaw(&path_buffer) catch
        return error.UnapprovedAttestationApiPath;
    const expected_path = "/repos/bblanchon/pdfium-binaries/attestations/sha256:61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41";
    if (!std.mem.eql(u8, path, expected_path)) return error.UnapprovedAttestationApiPath;
    const query_marker = std.mem.indexOfScalar(u8, attestation.api_url, '?') orelse
        return error.UnapprovedAttestationApiQuery;
    if (!std.mem.eql(
        u8,
        attestation.api_url[query_marker + 1 ..],
        "predicate_type=provenance&per_page=100",
    )) return error.UnapprovedAttestationApiQuery;

    if (!std.mem.eql(u8, attestation.id, "pdfium-chromium-8035-win-x64") or
        !std.mem.eql(u8, attestation.accept, "application/vnd.github+json") or
        !std.mem.eql(u8, attestation.api_version, "2026-03-10") or
        attestation.repository_id != 103_962_638 or attestation.result_count != 1)
    {
        return error.WrongRepositoryId;
    }
    if (attestation.raw_snappy_size_bytes == 0 or
        attestation.decompressed_json_size_bytes == 0 or
        attestation.jsonl_size_bytes != attestation.decompressed_json_size_bytes + 1)
    {
        return error.InvalidAttestationSize;
    }
    if (!isLowerHexDigest(attestation.raw_snappy_sha256) or
        !isLowerHexDigest(attestation.jsonl_sha256))
    {
        return error.InvalidDigest;
    }
    validateArchivePath(attestation.jsonl_path) catch return error.InvalidAttestationPath;
    if (!std.mem.eql(u8, attestation.predicate_type, "https://slsa.dev/provenance/v1")) {
        return error.WrongPredicateType;
    }
    if (attestation.subject_count != 45 or
        !std.mem.eql(u8, attestation.subject_name, "pdfium-win-x64.tgz") or
        !std.mem.eql(u8, attestation.subject_sha256, "61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41"))
    {
        return error.WrongSubjectDigest;
    }
    if (!std.mem.eql(u8, attestation.bundle_host, "tmaproduction.blob.core.windows.net")) {
        return error.UnapprovedBundleHost;
    }
    if (!std.mem.eql(
        u8,
        attestation.bundle_path,
        "/attestations/103962638/2026/08/31/44147842.json.sn",
    )) return error.UnapprovedBundlePath;

    var seen = [_]bool{false} ** bundle_query_fields.len;
    for (attestation.bundle_query_fields) |field| {
        const index = bundleQueryFieldIndex(field) orelse
            return error.UnapprovedBundleQuery;
        if (seen[index]) return error.DuplicateBundleQueryField;
        seen[index] = true;
    }
    for (seen) |present| if (!present) return error.MissingBundleQueryField;

    if (!std.mem.eql(
        u8,
        attestation.certificate_identity,
        "https://github.com/bblanchon/pdfium-binaries/.github/workflows/build-all.yml@refs/heads/master",
    ) or !std.mem.eql(
        u8,
        attestation.oidc_issuer,
        "https://token.actions.githubusercontent.com",
    ) or !std.mem.eql(u8, attestation.workflow_repository, "bblanchon/pdfium-binaries") or
        !std.mem.eql(u8, attestation.source_ref, "refs/heads/master") or
        attestation.source_digest.len != 40 or !isLowerHex(attestation.source_digest) or
        !std.mem.eql(u8, attestation.runner_environment, "github-hosted") or
        !std.mem.eql(
            u8,
            attestation.invocation_url,
            "https://github.com/bblanchon/pdfium-binaries/actions/runs/33383157207/attempts/1",
        ))
    {
        return error.WrongWorkflowIdentity;
    }
}

fn validateTrustedRootLock(root: TrustedRootLock) !void {
    if (!std.mem.eql(u8, root.id, "github-attestation-2026-09-04") or
        !std.mem.eql(
            u8,
            root.path,
            "tools/zig/attestations/github-attestation-trusted-root-2026-09-04.jsonl",
        ) or root.size_bytes == 0 or !isLowerHexDigest(root.sha256) or
        root.line_count != 2 or !std.mem.eql(
        u8,
        root.media_type,
        "application/vnd.dev.sigstore.trustedroot+json;version=0.1",
    ) or root.independent_acquisitions != 2) {
        return error.InvalidTrustedRootLock;
    }
    if (!isStrictDate(root.snapshot_date)) return error.InvalidTrustedRootSnapshot;
    if (root.instances.len != 2 or
        !std.mem.eql(u8, root.instances[0], "sigstore-public-good") or
        !std.mem.eql(u8, root.instances[1], "github") or
        std.mem.eql(u8, root.instances[0], root.instances[1]))
    {
        return error.InvalidTrustedRootLock;
    }
}

const OriginPolicy = struct {
    host: []const u8,
    path: []const u8,
    query: ?[]const u8 = "download=1",
    integrity: Integrity,
    archive_format: ArchiveFormat,
    archive_root: []const u8,
    tar_metadata_policy: TarMetadataPolicy = .none,
    allow_zip_data_descriptor: bool = false,
    allowed_zip_extra_fields: []const u16 = &.{},
    allowed_exact_paths: []const []const u8 = &.{},
    allowed_path_prefixes: []const []const u8 = &.{},
};

const ProvenancePolicy = struct {
    source_url: []const u8,
    license_url: []const u8,
};

fn provenancePolicy(id: []const u8) !ProvenancePolicy {
    if (std.mem.eql(u8, id, "scintilla")) return .{
        .source_url = "https://www.scintilla.org/ScintillaDownload.html",
        .license_url = "https://www.scintilla.org/License.txt",
    };
    if (std.mem.eql(u8, id, "lexilla")) return .{
        .source_url = "https://www.scintilla.org/Lexilla.html",
        .license_url = "https://www.scintilla.org/License.txt",
    };
    if (std.mem.eql(u8, id, "unicode-ucd")) return .{
        .source_url = "https://www.unicode.org/versions/Unicode17.0.0/",
        .license_url = "https://www.unicode.org/license.txt",
    };
    if (std.mem.eql(u8, id, "pdfium-reference")) return .{
        .source_url = "https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium/8035",
        .license_url = "https://pdfium.googlesource.com/pdfium/+/6f2272e1f3aaa141305475b83ef4eac2c1f527b8/LICENSE",
    };
    if (std.mem.eql(u8, id, "pdfium-root-source")) return .{
        .source_url = "https://pdfium.googlesource.com/pdfium/",
        .license_url = "https://pdfium.googlesource.com/pdfium/+/6f2272e1f3aaa141305475b83ef4eac2c1f527b8/LICENSE",
    };
    if (std.mem.eql(u8, id, "pdfium-build-recipe")) return .{
        .source_url = "https://github.com/bblanchon/pdfium-binaries/tree/5453f3afc4785cbad82c05f6ceb4dabea0cb81a0",
        .license_url = "https://github.com/bblanchon/pdfium-binaries/blob/5453f3afc4785cbad82c05f6ceb4dabea0cb81a0/LICENSE",
    };
    if (std.mem.eql(u8, id, "sqlite")) return .{
        .source_url = "https://www.sqlite.org/download.html",
        .license_url = "https://www.sqlite.org/copyright.html",
    };
    if (std.mem.eql(u8, id, "zigwin32")) return .{
        .source_url = "https://github.com/marlersoft/zigwin32/tree/9f15c276b4e9d05afd34a10d8662a7dfc34647ea",
        .license_url = "https://github.com/marlersoft/zigwin32/blob/9f15c276b4e9d05afd34a10d8662a7dfc34647ea/LICENSE",
    };
    if (std.mem.eql(u8, id, "presentmon")) return .{
        .source_url = "https://github.com/GameTechDev/PresentMon/releases/tag/v2.5.1",
        .license_url = "https://github.com/GameTechDev/PresentMon/blob/v2.5.1/LICENSE.txt",
    };
    if (std.mem.eql(u8, id, "accessibility-insights")) return .{
        .source_url = "https://github.com/microsoft/accessibility-insights-windows/releases/tag/v1.1.2924.01",
        .license_url = "https://github.com/microsoft/accessibility-insights-windows/blob/main/LICENSE",
    };
    if (std.mem.eql(u8, id, "github-cli")) return .{
        .source_url = "https://github.com/cli/cli/releases/tag/v2.100.0",
        .license_url = "https://github.com/cli/cli/blob/v2.100.0/LICENSE",
    };
    return error.UnknownArtifactId;
}

fn originPolicy(id: []const u8) !OriginPolicy {
    if (std.mem.eql(u8, id, "scintilla")) {
        return .{
            .host = "www.scintilla.org",
            .path = "/scintilla566.tgz",
            .integrity = .byte_archive,
            .archive_format = .tar_gzip,
            .archive_root = "scintilla/",
            .tar_metadata_policy = .gnu_long_name,
        };
    }
    if (std.mem.eql(u8, id, "lexilla")) {
        return .{
            .host = "www.scintilla.org",
            .path = "/lexilla553.tgz",
            .integrity = .byte_archive,
            .archive_format = .tar_gzip,
            .archive_root = "lexilla/",
        };
    }
    if (std.mem.eql(u8, id, "unicode-ucd")) {
        return .{
            .host = "www.unicode.org",
            .path = "/Public/17.0.0/ucd/UCD.zip",
            .query = null,
            .integrity = .byte_archive,
            .archive_format = .restricted_zip,
            .archive_root = "",
            .allowed_zip_extra_fields = &.{ 0x5455, 0x7875 },
        };
    }
    if (std.mem.eql(u8, id, "pdfium-reference")) {
        return .{
            .host = "github.com",
            .path = "/bblanchon/pdfium-binaries/releases/download/chromium/8035/pdfium-win-x64.tgz",
            .integrity = .byte_archive,
            .archive_format = .tar_gzip,
            .archive_root = "",
            .allowed_exact_paths = &.{
                "LICENSE",
                "PDFiumConfig.cmake",
                "VERSION",
                "args.gn",
            },
            .allowed_path_prefixes = &.{
                "bin/",
                "include/",
                "lib/",
                "licenses/",
            },
        };
    }
    if (std.mem.eql(u8, id, "pdfium-root-source")) {
        return .{
            .host = "pdfium.googlesource.com",
            .path = "/pdfium/+archive/6f2272e1f3aaa141305475b83ef4eac2c1f527b8.tar.gz",
            .integrity = .canonical_tree,
            .archive_format = .tar_gzip,
            .archive_root = "",
            .tar_metadata_policy = .gitiles_pax,
        };
    }
    if (std.mem.eql(u8, id, "pdfium-build-recipe")) {
        return .{
            .host = "github.com",
            .path = "/bblanchon/pdfium-binaries/archive/5453f3afc4785cbad82c05f6ceb4dabea0cb81a0.tar.gz",
            .integrity = .byte_archive,
            .archive_format = .tar_gzip,
            .archive_root = "pdfium-binaries-5453f3afc4785cbad82c05f6ceb4dabea0cb81a0/",
            .tar_metadata_policy = .github_codeload_pax,
        };
    }
    if (std.mem.eql(u8, id, "sqlite")) {
        return .{
            .host = "www.sqlite.org",
            .path = "/2026/sqlite-autoconf-3530400.tar.gz",
            .integrity = .byte_archive,
            .archive_format = .tar_gzip,
            .archive_root = "sqlite-autoconf-3530400/",
        };
    }
    if (std.mem.eql(u8, id, "zigwin32")) {
        return .{
            .host = "github.com",
            .path = "/marlersoft/zigwin32/archive/9f15c276b4e9d05afd34a10d8662a7dfc34647ea.tar.gz",
            .integrity = .byte_archive,
            .archive_format = .tar_gzip,
            .archive_root = "zigwin32-9f15c276b4e9d05afd34a10d8662a7dfc34647ea/",
            .tar_metadata_policy = .github_codeload_pax,
        };
    }
    if (std.mem.eql(u8, id, "presentmon")) {
        return .{
            .host = "github.com",
            .path = "/GameTechDev/PresentMon/releases/download/v2.5.1/PresentMon-2.5.1-x64.exe",
            .integrity = .byte_archive,
            .archive_format = .direct_file,
            .archive_root = "",
        };
    }
    if (std.mem.eql(u8, id, "accessibility-insights")) {
        return .{
            .host = "github.com",
            .path = "/microsoft/accessibility-insights-windows/releases/download/v1.1.2924.01/AccessibilityInsights.msi",
            .integrity = .byte_archive,
            .archive_format = .direct_file,
            .archive_root = "",
        };
    }
    if (std.mem.eql(u8, id, "github-cli")) {
        return .{
            .host = "github.com",
            .path = "/cli/cli/releases/download/v2.100.0/gh_2.100.0_windows_amd64.zip",
            .integrity = .byte_archive,
            .archive_format = .restricted_zip,
            .archive_root = "",
            .allow_zip_data_descriptor = true,
            .allowed_zip_extra_fields = &.{0x5455},
        };
    }
    return error.UnknownArtifactId;
}

const release_asset_query_fields = [_][]const u8{
    "sp",
    "sv",
    "sr",
    "spr",
    "se",
    "rscd",
    "rsct",
    "skoid",
    "sktid",
    "skt",
    "ske",
    "sks",
    "skv",
    "sig",
    "jwt",
    "response-content-disposition",
    "response-content-type",
};

const ReleaseAssetPolicy = struct {
    repository_id: []const u8,
};

fn releaseAssetPolicy(id: []const u8) ?ReleaseAssetPolicy {
    if (std.mem.eql(u8, id, "pdfium-reference")) {
        return .{ .repository_id = "103962638" };
    }
    if (std.mem.eql(u8, id, "presentmon")) {
        return .{ .repository_id = "53522468" };
    }
    if (std.mem.eql(u8, id, "accessibility-insights")) {
        return .{ .repository_id = "160750843" };
    }
    if (std.mem.eql(u8, id, "github-cli")) {
        return .{ .repository_id = "212613049" };
    }
    return null;
}

fn codeloadPath(id: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, id, "zigwin32")) {
        return "/marlersoft/zigwin32/tar.gz/9f15c276b4e9d05afd34a10d8662a7dfc34647ea";
    }
    if (std.mem.eql(u8, id, "pdfium-build-recipe")) {
        return "/bblanchon/pdfium-binaries/tar.gz/5453f3afc4785cbad82c05f6ceb4dabea0cb81a0";
    }
    return null;
}

/// Validates every URI reached after the exact manifest URI. This deliberately
/// accepts only the reviewed same-origin path, the exact commit-bound Codeload
/// path, or a signed GitHub release-asset path inside the locked repository.
pub fn validateDownloadTarget(id: []const u8, text: []const u8) !void {
    const uri = validateHttpsUrl(text) catch return error.UnapprovedDownloadTarget;
    var host_buffer: [std.Io.net.HostName.max_len]u8 = undefined;
    const host = (uri.getHost(&host_buffer) catch
        return error.UnapprovedDownloadTarget).bytes;
    var path_buffer: [4096]u8 = undefined;
    const path = uri.path.toRaw(&path_buffer) catch
        return error.UnapprovedDownloadTarget;

    const origin = originPolicy(id) catch return error.UnapprovedDownloadTarget;
    if (std.ascii.eqlIgnoreCase(host, origin.host) and
        std.mem.eql(u8, path, origin.path))
    {
        if (origin.query) |expected_query| {
            const query_component = uri.query orelse
                return error.UnapprovedDownloadTarget;
            var query_buffer: [256]u8 = undefined;
            const query = query_component.toRaw(&query_buffer) catch
                return error.UnapprovedDownloadTarget;
            if (!std.mem.eql(u8, query, expected_query)) {
                return error.UnapprovedDownloadTarget;
            }
        } else if (uri.query != null) {
            return error.UnapprovedDownloadTarget;
        }
        return;
    }

    if (codeloadPath(id)) |expected_path| {
        if (std.ascii.eqlIgnoreCase(host, "codeload.github.com") and
            std.mem.eql(u8, path, expected_path) and uri.query == null)
        {
            return;
        }
    }

    if (releaseAssetPolicy(id)) |release| {
        if (!std.ascii.eqlIgnoreCase(host, "release-assets.githubusercontent.com")) {
            return error.UnapprovedDownloadTarget;
        }
        var prefix_buffer: [96]u8 = undefined;
        const prefix = std.fmt.bufPrint(
            &prefix_buffer,
            "/github-production-release-asset/{s}/",
            .{release.repository_id},
        ) catch return error.UnapprovedDownloadTarget;
        if (!std.mem.startsWith(u8, path, prefix) or
            !isLowerUuid(path[prefix.len..]))
        {
            return error.UnapprovedDownloadTarget;
        }
        const marker = std.mem.indexOfScalar(u8, text, '?') orelse
            return error.UnapprovedDownloadTarget;
        try validateReleaseAssetQuery(text[marker + 1 ..]);
        return;
    }
    return error.UnapprovedDownloadTarget;
}

fn validateReleaseAssetQuery(query: []const u8) !void {
    if (query.len == 0 or query.len > 4096 or
        std.mem.indexOfScalar(u8, query, '#') != null)
    {
        return error.UnapprovedDownloadTarget;
    }
    var seen = [_]bool{false} ** release_asset_query_fields.len;
    var service_version: [10]u8 = undefined;
    var key_version: [10]u8 = undefined;
    var disposition: [512]u8 = undefined;
    var response_disposition: [512]u8 = undefined;
    var disposition_len: usize = 0;
    var response_disposition_len: usize = 0;

    var pairs = std.mem.splitScalar(u8, query, '&');
    while (pairs.next()) |pair| {
        const equals = std.mem.indexOfScalar(u8, pair, '=') orelse
            return error.UnapprovedDownloadTarget;
        if (equals == 0 or equals + 1 >= pair.len) {
            return error.UnapprovedDownloadTarget;
        }
        const key = pair[0..equals];
        const index = releaseAssetQueryFieldIndex(key) orelse
            return error.UnapprovedDownloadTarget;
        if (seen[index]) return error.UnapprovedDownloadTarget;
        seen[index] = true;

        var decoded_buffer: [2048]u8 = undefined;
        const value = if (std.mem.eql(u8, key, "rscd"))
            percentDecodeReleaseDisposition(pair[equals + 1 ..], &decoded_buffer) catch
                return error.UnapprovedDownloadTarget
        else
            percentDecodeQueryValue(pair[equals + 1 ..], &decoded_buffer) catch
                return error.UnapprovedDownloadTarget;
        if (std.mem.eql(u8, key, "sp")) {
            if (!std.mem.eql(u8, value, "r")) return error.UnapprovedDownloadTarget;
        } else if (std.mem.eql(u8, key, "sr") or std.mem.eql(u8, key, "sks")) {
            if (!std.mem.eql(u8, value, "b")) return error.UnapprovedDownloadTarget;
        } else if (std.mem.eql(u8, key, "spr")) {
            if (!std.mem.eql(u8, value, "https")) return error.UnapprovedDownloadTarget;
        } else if (std.mem.eql(u8, key, "sv")) {
            if (!std.mem.eql(u8, value, "2018-11-09")) {
                return error.UnapprovedDownloadTarget;
            }
            @memcpy(&service_version, value);
        } else if (std.mem.eql(u8, key, "skv")) {
            if (!std.mem.eql(u8, value, "2018-11-09")) {
                return error.UnapprovedDownloadTarget;
            }
            @memcpy(&key_version, value);
        } else if (std.mem.eql(u8, key, "se") or
            std.mem.eql(u8, key, "skt") or std.mem.eql(u8, key, "ske"))
        {
            if (!isStrictUtcTimestamp(value)) return error.UnapprovedDownloadTarget;
        } else if (std.mem.eql(u8, key, "skoid") or
            std.mem.eql(u8, key, "sktid"))
        {
            if (!isLowerUuid(value)) return error.UnapprovedDownloadTarget;
        } else if (std.mem.eql(u8, key, "sig")) {
            if (!isSha256Base64(value)) return error.UnapprovedDownloadTarget;
        } else if (std.mem.eql(u8, key, "jwt")) {
            if (!isCompactJwt(value)) return error.UnapprovedDownloadTarget;
        } else if (std.mem.eql(u8, key, "rsct") or
            std.mem.eql(u8, key, "response-content-type"))
        {
            if (!std.mem.eql(u8, value, "application/octet-stream")) {
                return error.UnapprovedDownloadTarget;
            }
        } else if (std.mem.eql(u8, key, "rscd")) {
            if (value.len > disposition.len or
                !std.mem.startsWith(u8, value, "attachment"))
            {
                return error.UnapprovedDownloadTarget;
            }
            disposition_len = value.len;
            @memcpy(disposition[0..value.len], value);
        } else if (std.mem.eql(u8, key, "response-content-disposition")) {
            if (value.len > response_disposition.len or
                !std.mem.startsWith(u8, value, "attachment"))
            {
                return error.UnapprovedDownloadTarget;
            }
            response_disposition_len = value.len;
            @memcpy(response_disposition[0..value.len], value);
        }
    }
    for (seen) |present| if (!present) return error.UnapprovedDownloadTarget;
    if (!std.mem.eql(u8, &service_version, &key_version) or
        disposition_len == 0 or disposition_len != response_disposition_len or
        !std.mem.eql(
            u8,
            disposition[0..disposition_len],
            response_disposition[0..response_disposition_len],
        ))
    {
        return error.UnapprovedDownloadTarget;
    }
}

fn releaseAssetQueryFieldIndex(key: []const u8) ?usize {
    for (release_asset_query_fields, 0..) |expected, index| {
        if (std.mem.eql(u8, key, expected)) return index;
    }
    return null;
}

fn percentDecodeReleaseDisposition(encoded: []const u8, buffer: []u8) ![]const u8 {
    if (encoded.len > buffer.len) return error.QueryValueTooLarge;
    // Convert each form-style '+' into an explicit percent-encoded space while
    // leaving every other byte under the shared strict decoder.
    var expanded: [4096]u8 = undefined;
    var cursor: usize = 0;
    for (encoded) |byte| {
        if (byte == '+') {
            if (cursor + 3 > expanded.len) return error.QueryValueTooLarge;
            @memcpy(expanded[cursor..][0..3], "%20");
            cursor += 3;
        } else {
            if (cursor == expanded.len) return error.QueryValueTooLarge;
            expanded[cursor] = byte;
            cursor += 1;
        }
    }
    return percentDecodeQueryValue(expanded[0..cursor], buffer);
}

fn isCompactJwt(value: []const u8) bool {
    if (value.len < 5 or value.len > 1536) return false;
    var dots: usize = 0;
    for (value) |byte| switch (byte) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '_' => {},
        '.' => dots += 1,
        else => return false,
    };
    return dots == 2;
}

pub const RedirectTracker = struct {
    const max_redirects = 3;

    seen: [max_redirects + 1][32]u8 = undefined,
    seen_count: u8 = 0,

    pub fn init(initial_url: []const u8) RedirectTracker {
        var result: RedirectTracker = .{};
        std.crypto.hash.sha2.Sha256.hash(initial_url, &result.seen[0], .{});
        result.seen_count = 1;
        return result;
    }

    pub fn follow(self: *RedirectTracker, url: []const u8) !void {
        if (self.seen_count >= self.seen.len) return error.TooManyDownloadRedirects;
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(url, &digest, .{});
        for (self.seen[0..self.seen_count]) |seen| {
            if (std.mem.eql(u8, &seen, &digest)) return error.DownloadRedirectLoop;
        }
        self.seen[self.seen_count] = digest;
        self.seen_count += 1;
    }
};

pub const DownloadVerifier = struct {
    const State = enum { receiving, verified, failed };

    limit_bytes: u64,
    expected_size: ?u64,
    expected_sha256: ?[]const u8,
    content_length: ?u64,
    bytes_received: u64 = 0,
    hasher: std.crypto.hash.sha2.Sha256 = .init(.{}),
    state: State = .receiving,

    pub fn init(artifact: Artifact, content_length: ?u64) !DownloadVerifier {
        if (artifact.download_limit_bytes == 0) return error.InvalidSizeLimit;
        if (content_length) |length| {
            if (length > artifact.download_limit_bytes) {
                return error.DownloadLimitExceeded;
            }
            if (artifact.integrity == .byte_archive and
                length != (artifact.archive_size_bytes orelse
                    return error.InconsistentIntegrityMode))
            {
                return error.ContentLengthMismatch;
            }
        }
        return .{
            .limit_bytes = artifact.download_limit_bytes,
            .expected_size = if (artifact.integrity == .byte_archive)
                artifact.archive_size_bytes
            else
                null,
            .expected_sha256 = if (artifact.integrity == .byte_archive)
                artifact.archive_sha256
            else
                null,
            .content_length = content_length,
        };
    }

    pub fn feed(self: *DownloadVerifier, bytes: []const u8) !void {
        errdefer self.state = .failed;
        if (self.state != .receiving) return error.DownloadIncomplete;
        const new_total = std.math.add(
            u64,
            self.bytes_received,
            bytes.len,
        ) catch return error.DownloadLimitExceeded;
        if (new_total > self.limit_bytes) return error.DownloadLimitExceeded;
        self.hasher.update(bytes);
        self.bytes_received = new_total;
    }

    pub fn markTransportFailure(self: *DownloadVerifier) void {
        self.state = .failed;
    }

    pub fn finish(self: *DownloadVerifier) !void {
        errdefer self.state = .failed;
        if (self.state != .receiving) return error.DownloadIncomplete;
        if (self.content_length) |length| {
            if (self.bytes_received != length) return error.ContentLengthMismatch;
        }
        if (self.expected_size) |size| {
            if (self.bytes_received != size) return error.DownloadSizeMismatch;
        } else if (self.bytes_received == 0) {
            return error.DownloadSizeMismatch;
        }
        if (self.expected_sha256) |expected_hex| {
            const expected = try parseSha256(expected_hex);
            var actual: [32]u8 = undefined;
            self.hasher.final(&actual);
            if (!std.mem.eql(u8, &actual, &expected)) return error.DigestMismatch;
        }
        self.state = .verified;
    }

    pub fn mayActivate(self: *const DownloadVerifier) bool {
        return self.state == .verified;
    }
};

pub fn validateArtifact(artifact: Artifact) !void {
    if (artifact.id.len == 0 or artifact.version.len == 0 or artifact.purpose.len == 0) {
        return error.MissingIdentity;
    }
    if (artifact.source_url.len == 0) return error.MissingSourceIdentity;
    if (artifact.license_spdx.len == 0 or artifact.license_url.len == 0) {
        return error.MissingLicenseIdentity;
    }

    _ = try validateHttpsUrl(artifact.source_url);
    _ = try validateHttpsUrl(artifact.license_url);
    const provenance = try provenancePolicy(artifact.id);
    if (!std.mem.eql(u8, artifact.source_url, provenance.source_url)) {
        return error.UnapprovedSourceIdentity;
    }
    if (!std.mem.eql(u8, artifact.license_url, provenance.license_url)) {
        return error.UnapprovedLicenseIdentity;
    }
    const uri = try validateHttpsUrl(artifact.url);
    const policy = try originPolicy(artifact.id);

    var host_buffer: [std.Io.net.HostName.max_len]u8 = undefined;
    const host = (try uri.getHost(&host_buffer)).bytes;
    if (!std.ascii.eqlIgnoreCase(host, policy.host)) return error.UnapprovedHost;

    var path_buffer: [4096]u8 = undefined;
    const path = uri.path.toRaw(&path_buffer) catch return error.InvalidUrl;
    if (!std.mem.eql(u8, path, policy.path) or
        !std.mem.eql(u8, artifact.allowed_path_prefix, policy.path))
    {
        return error.UnapprovedPath;
    }
    if (policy.query) |expected_query| {
        const query_component = uri.query orelse return error.UnapprovedQuery;
        var query_buffer: [256]u8 = undefined;
        const query = query_component.toRaw(&query_buffer) catch
            return error.UnapprovedQuery;
        if (!std.mem.eql(u8, query, expected_query)) return error.UnapprovedQuery;
    } else if (uri.query != null) {
        return error.UnapprovedQuery;
    }

    if (artifact.integrity != policy.integrity or
        artifact.archive_format != policy.archive_format or
        artifact.tar_metadata_policy != policy.tar_metadata_policy or
        artifact.allow_zip_data_descriptor != policy.allow_zip_data_descriptor or
        !std.mem.eql(u16, artifact.allowed_zip_extra_fields, policy.allowed_zip_extra_fields) or
        !stringSlicesEqual(artifact.allowed_exact_paths, policy.allowed_exact_paths) or
        !stringSlicesEqual(artifact.allowed_path_prefixes, policy.allowed_path_prefixes))
    {
        return error.InconsistentIntegrityMode;
    }
    if (!std.mem.eql(u8, artifact.archive_root, policy.archive_root) or
        !isSafeArchiveRoot(artifact.archive_root))
    {
        return error.InvalidArchiveRoot;
    }
    switch (artifact.integrity) {
        .byte_archive => {
            const size = artifact.archive_size_bytes orelse return error.InconsistentIntegrityMode;
            const digest = artifact.archive_sha256 orelse return error.InconsistentIntegrityMode;
            if (artifact.canonical_tree_sha256 != null) return error.InconsistentIntegrityMode;
            if (!isLowerHexDigest(digest)) return error.InvalidDigest;
            if (size == 0 or artifact.expected_entries == 0) return error.InvalidSize;
            if (artifact.download_limit_bytes < size) return error.InvalidSizeLimit;
            if (artifact.expected_regular_files != null) return error.InconsistentIntegrityMode;
        },
        .canonical_tree => {
            if (artifact.archive_size_bytes != null or artifact.archive_sha256 != null) {
                return error.InconsistentIntegrityMode;
            }
            const digest = artifact.canonical_tree_sha256 orelse
                return error.InconsistentIntegrityMode;
            if (!isLowerHexDigest(digest)) return error.InvalidDigest;
            const regular_files = artifact.expected_regular_files orelse
                return error.InconsistentIntegrityMode;
            if (artifact.expected_entries == 0 or regular_files == 0 or
                regular_files > artifact.expected_entries)
            {
                return error.InvalidSize;
            }
        },
    }
    if (artifact.download_limit_bytes == 0 or
        artifact.download_limit_bytes > 16 * 1024 * 1024 * 1024 or
        artifact.expanded_limit_bytes == 0 or
        artifact.expanded_limit_bytes > 16 * 1024 * 1024 * 1024)
    {
        return error.InvalidSizeLimit;
    }
    if (artifact.tar_stream_limit_bytes) |limit| {
        if (artifact.archive_format != .tar_gzip) return error.InconsistentIntegrityMode;
        if (limit < artifact.expanded_limit_bytes or limit > 16 * 1024 * 1024 * 1024) {
            return error.InvalidSizeLimit;
        }
    } else if (artifact.integrity == .canonical_tree and artifact.archive_format == .tar_gzip) {
        return error.InconsistentIntegrityMode;
    }
    for (artifact.build_switches) |build_switch| {
        if (!isKnownBuildSwitch(build_switch)) return error.UnknownBuildSwitch;
    }
    for (artifact.inventory) |member| try validateMemberLock(member, false);
    for (artifact.retained_members) |member| try validateMemberLock(member, true);
    try validatePathAllowlist(artifact.allowed_exact_paths, artifact.allowed_path_prefixes);
    if (artifact.inventory.len != 0 and artifact.inventory.len != artifact.expected_entries) {
        return error.InvalidMemberInventory;
    }
    if (artifact.inventory.len != 0) {
        var total: u64 = 0;
        for (artifact.inventory, 0..) |member, index| {
            total = std.math.add(u64, total, member.size_bytes) catch
                return error.InvalidSizeLimit;
            for (artifact.inventory[index + 1 ..]) |other| {
                if (std.mem.eql(u8, member.path, other.path)) {
                    return error.DuplicateMemberPath;
                }
            }
        }
        if (artifact.expected_expanded_bytes) |expected| {
            if (total != expected) return error.InventoryByteCountMismatch;
        }
        for (artifact.retained_members) |retained| {
            var matched = false;
            for (artifact.inventory) |member| {
                if (std.mem.eql(u8, retained.path, member.path) and
                    retained.size_bytes == member.size_bytes and
                    retained.kind == member.kind)
                {
                    matched = true;
                    break;
                }
            }
            if (!matched) return error.InvalidMemberInventory;
        }
    }
    if (artifact.expected_expanded_bytes) |expected| {
        if (expected == 0 or expected > artifact.expanded_limit_bytes) {
            return error.InvalidSizeLimit;
        }
    }
    if (artifact.commit) |commit| {
        if (commit.len != 40 or !isLowerHex(commit)) return error.InvalidCommit;
    }
    if (artifact.package_hash) |package_hash| {
        if (package_hash.len == 0 or package_hash.len > 128) {
            return error.InvalidPackageHash;
        }
    }
    if (artifact.authenticode) |signature| {
        if (signature.subject.len == 0 or
            signature.thumbprint_sha1.len != 40 or
            !isUpperHex(signature.thumbprint_sha1))
        {
            return error.InvalidAuthenticodeLock;
        }
    }
    if (artifact.fetch_policy == .operator_provisioned and
        !std.mem.eql(u8, artifact.id, "accessibility-insights"))
    {
        return error.InvalidFetchPolicy;
    }
}

fn validateMemberLock(member: MemberLock, require_hash: bool) !void {
    switch (member.kind) {
        .file => {
            if (!isSafeMemberPath(member.path)) return error.InvalidMemberLock;
        },
        .directory => {
            if (member.path.len == 0 or member.path[member.path.len - 1] != '/' or
                member.size_bytes != 0 or member.sha256 != null)
            {
                return error.InvalidMemberLock;
            }
            if (!isSafeMemberPath(member.path[0 .. member.path.len - 1])) {
                return error.InvalidMemberLock;
            }
        },
    }
    if (require_hash and member.sha256 == null) return error.InvalidMemberLock;
    if (member.sha256) |digest| {
        if (!isLowerHexDigest(digest)) return error.InvalidDigest;
    }
}

fn validateHttpsUrl(text: []const u8) !std.Uri {
    const uri = std.Uri.parse(text) catch return error.InvalidUrl;
    if (!std.mem.eql(u8, uri.scheme, "https")) return error.NonHttpsUrl;
    if (uri.host == null or uri.user != null or uri.password != null or
        uri.fragment != null or uri.port != null)
    {
        return error.InvalidUrl;
    }
    return uri;
}

fn isSafeArchiveRoot(root: []const u8) bool {
    if (root.len == 0) return true;
    if (root.len < 2 or root[root.len - 1] != '/' or root[0] == '/') return false;
    if (std.mem.indexOf(u8, root, "\\") != null or
        std.mem.indexOf(u8, root, ":") != null or
        std.mem.indexOf(u8, root, "..") != null)
    {
        return false;
    }
    for (root) |byte| {
        if (byte < 0x20 or byte == 0x7f) return false;
    }
    return true;
}

fn isSafeMemberPath(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or path[path.len - 1] == '/') return false;
    if (std.mem.indexOf(u8, path, "\\") != null or
        std.mem.indexOf(u8, path, ":") != null)
    {
        return false;
    }
    var iterator = std.mem.splitScalar(u8, path, '/');
    while (iterator.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or
            std.mem.eql(u8, component, ".."))
        {
            return false;
        }
        for (component) |byte| {
            if (byte < 0x20 or byte == 0x7f) return false;
        }
    }
    return true;
}

fn isLowerHexDigest(digest: []const u8) bool {
    if (digest.len != 64) return false;
    for (digest) |byte| {
        if (!std.ascii.isDigit(byte) and !(byte >= 'a' and byte <= 'f')) return false;
    }
    return true;
}

fn isUpperHex(digest: []const u8) bool {
    for (digest) |byte| {
        if (!std.ascii.isDigit(byte) and !(byte >= 'A' and byte <= 'F')) return false;
    }
    return true;
}

fn isLowerHex(value: []const u8) bool {
    for (value) |byte| {
        if (!std.ascii.isDigit(byte) and !(byte >= 'a' and byte <= 'f')) return false;
    }
    return true;
}

fn isKnownBuildSwitch(build_switch: []const u8) bool {
    const known = [_][]const u8{
        "baseline-cpu",
        "build-only",
        "fts5",
        "no-v8",
        "no-xfa",
        "operator-provisioned",
        "product-static",
        "qa-only",
        "reference-only",
        "release-safe",
        "serialized",
        "strip",
        "test-only",
    };
    for (known) |candidate| {
        if (std.mem.eql(u8, candidate, build_switch)) return true;
    }
    return false;
}

pub fn validateArchivePath(path: []const u8) !void {
    if (path.len == 0 or path.len > 4096 or path[0] == '/' or path[path.len - 1] == '/' or
        !std.unicode.utf8ValidateSlice(path))
    {
        return error.UnsafeArchivePath;
    }
    for (path) |byte| {
        if (byte < 0x20 or byte == 0x7f or byte == '\\' or byte == ':' or
            byte == '"' or byte == '*' or byte == '?' or byte == '<' or
            byte == '>' or byte == '|')
        {
            return error.UnsafeArchivePath;
        }
    }

    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or
            std.mem.eql(u8, component, "..") or
            component[component.len - 1] == '.' or
            component[component.len - 1] == ' ' or
            isReservedDosName(component) or
            looksLikeShortNameAlias(component))
        {
            return error.UnsafeArchivePath;
        }
    }
}

fn isReservedDosName(component: []const u8) bool {
    const stem_end = std.mem.indexOfScalar(u8, component, '.') orelse component.len;
    const stem = component[0..stem_end];
    const fixed = [_][]const u8{
        "CON",
        "PRN",
        "AUX",
        "NUL",
        "CLOCK$",
        "CONIN$",
        "CONOUT$",
    };
    for (fixed) |reserved| {
        if (std.ascii.eqlIgnoreCase(stem, reserved)) return true;
    }
    if (stem.len == 4 and
        (std.ascii.eqlIgnoreCase(stem[0..3], "COM") or
            std.ascii.eqlIgnoreCase(stem[0..3], "LPT")) and
        stem[3] >= '1' and stem[3] <= '9')
    {
        return true;
    }
    if (stem.len == 5 and
        (std.ascii.eqlIgnoreCase(stem[0..3], "COM") or
            std.ascii.eqlIgnoreCase(stem[0..3], "LPT")) and
        stem[3] == 0xc2 and
        (stem[4] == 0xb9 or stem[4] == 0xb2 or stem[4] == 0xb3))
    {
        return true;
    }
    return false;
}

fn looksLikeShortNameAlias(component: []const u8) bool {
    const stem_end = std.mem.indexOfScalar(u8, component, '.') orelse component.len;
    const stem = component[0..stem_end];
    const tilde = std.mem.lastIndexOfScalar(u8, stem, '~') orelse return false;
    if (tilde == 0 or tilde + 1 == stem.len) return false;
    for (stem[tilde + 1 ..]) |byte| {
        if (!std.ascii.isDigit(byte)) return false;
    }
    return true;
}

pub const PathRegistry = struct {
    allocator: std.mem.Allocator,
    keys: std.StringHashMap(void),
    fold: CollisionFoldFn,

    pub fn init(allocator: std.mem.Allocator) PathRegistry {
        return initWithFold(allocator, asciiCollisionFold);
    }

    pub fn initWithFold(allocator: std.mem.Allocator, fold: CollisionFoldFn) PathRegistry {
        return .{
            .allocator = allocator,
            .keys = std.StringHashMap(void).init(allocator),
            .fold = fold,
        };
    }

    pub fn deinit(self: *PathRegistry) void {
        var iterator = self.keys.keyIterator();
        while (iterator.next()) |key| self.allocator.free(key.*);
        self.keys.deinit();
        self.* = undefined;
    }

    pub fn add(self: *PathRegistry, path: []const u8) !void {
        try validateArchivePath(path);
        const key = try collisionKey(self.allocator, path, self.fold);
        errdefer self.allocator.free(key);
        if (self.keys.contains(key)) return error.PathCollision;
        try self.keys.put(key, {});
    }
};

pub const CollisionFoldFn = *const fn (
    allocator: std.mem.Allocator,
    component: []const u8,
    max_output_bytes: usize,
) anyerror![]u8;

pub fn asciiCollisionFold(
    allocator: std.mem.Allocator,
    component: []const u8,
    max_output_bytes: usize,
) ![]u8 {
    if (component.len > max_output_bytes) return error.UnicodeOutputLimitExceeded;
    const output = try allocator.dupe(u8, component);
    for (output) |*byte| byte.* = std.ascii.toLower(byte.*);
    return output;
}

fn collisionKey(
    allocator: std.mem.Allocator,
    path: []const u8,
    fold: CollisionFoldFn,
) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    var components = std.mem.splitScalar(u8, path, '/');
    var first = true;
    while (components.next()) |component| {
        if (!first) output.writer.writeByte('/') catch return error.OutOfMemory;
        first = false;
        const folded = try fold(allocator, component, 64 * 1024);
        defer allocator.free(folded);
        output.writer.writeAll(folded) catch return error.OutOfMemory;
    }
    return output.toOwnedSlice();
}

pub const ArchiveLimits = struct {
    max_compressed_bytes: usize,
    max_decompressed_bytes: usize,
    max_member_bytes: u64,
    max_total_bytes: u64,
    max_entries: u32,
    max_compression_ratio: u32,
    required_root: []const u8,
    tar_metadata_policy: TarMetadataPolicy = .none,
    tar_metadata_identity: ?[]const u8 = null,
    allowed_exact_paths: []const []const u8 = &.{},
    allowed_path_prefixes: []const []const u8 = &.{},
    collision_fold: CollisionFoldFn = asciiCollisionFold,
};

pub const ArchiveSummary = struct {
    entries: u32,
    regular_files: u32,
    content_bytes: u64,
};

pub fn inspectTarGzip(
    allocator: std.mem.Allocator,
    compressed: []const u8,
    limits: ArchiveLimits,
) !ArchiveSummary {
    try validateArchiveLimits(limits);
    if (compressed.len == 0 or compressed.len > limits.max_compressed_bytes) {
        return error.ArchiveCompressedTooLarge;
    }

    const plain_buffer = try allocator.alloc(u8, limits.max_decompressed_bytes);
    defer allocator.free(plain_buffer);
    var input = std.Io.Reader.fixed(compressed);
    var output = std.Io.Writer.fixed(plain_buffer);
    var history: [std.compress.flate.max_window_len]u8 = undefined;
    var decompressor = std.compress.flate.Decompress.init(&input, .gzip, &history);
    const decompressed_len = decompressor.reader.streamRemaining(&output) catch |err| {
        if (err == error.WriteFailed) return error.ArchiveExpandedTooLarge;
        if (decompressor.err) |detail| {
            if (detail == error.EndOfStream) return error.TruncatedGzip;
        }
        return error.InvalidGzip;
    };
    if (decompressor.err != null) return error.InvalidGzip;
    if (input.bufferedLen() != 0) return error.TrailingGzipData;

    const ratio_limit = std.math.mul(
        usize,
        compressed.len,
        limits.max_compression_ratio,
    ) catch std.math.maxInt(usize);
    if (decompressed_len > ratio_limit) return error.CompressionRatioExceeded;
    return inspectTar(allocator, output.buffered(), limits);
}

pub fn inspectTar(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    limits: ArchiveLimits,
) !ArchiveSummary {
    try validateArchiveLimits(limits);
    var registry = PathRegistry.initWithFold(allocator, limits.collision_fold);
    defer registry.deinit();
    var summary: ArchiveSummary = .{
        .entries = 0,
        .regular_files = 0,
        .content_bytes = 0,
    };
    var iterator = TarIterator.init(
        bytes,
        limits.tar_metadata_policy,
        limits.tar_metadata_identity,
    );
    while (try iterator.next()) |entry| {
        if (entry.size > limits.max_member_bytes) return error.ArchiveMemberTooLarge;
        const collision_path = if (entry.is_directory and entry.path.len != 0 and
            entry.path[entry.path.len - 1] == '/')
            entry.path[0 .. entry.path.len - 1]
        else
            entry.path;
        try validateArchivePath(collision_path);
        if (limits.required_root.len != 0 and
            !std.mem.startsWith(u8, entry.path, limits.required_root))
        {
            return error.UnexpectedArchiveRoot;
        }
        if (!archivePathAllowed(
            entry.path,
            limits.allowed_exact_paths,
            limits.allowed_path_prefixes,
        )) return error.UnapprovedArchiveMember;
        try registry.add(collision_path);

        summary.entries = std.math.add(u32, summary.entries, 1) catch
            return error.TooManyArchiveEntries;
        if (summary.entries > limits.max_entries) return error.TooManyArchiveEntries;
        if (!entry.is_directory) {
            summary.regular_files = std.math.add(u32, summary.regular_files, 1) catch
                return error.TooManyArchiveEntries;
            summary.content_bytes = std.math.add(u64, summary.content_bytes, entry.size) catch
                return error.ArchiveExpandedTooLarge;
            if (summary.content_bytes > limits.max_total_bytes) {
                return error.ArchiveExpandedTooLarge;
            }
        }
    }
    return summary;
}

const TarLogicalEntry = struct {
    path: []const u8,
    data: []const u8,
    size: u64,
    is_directory: bool,
};

const TarIterator = struct {
    bytes: []const u8,
    metadata_policy: TarMetadataPolicy,
    metadata_identity: ?[]const u8,
    offset: usize = 0,
    pending_long_name: ?[]const u8 = null,
    pending_pax_path: ?[]const u8 = null,
    pending_pax: bool = false,
    pending_pax_header_len: usize = 0,
    path_buffer: [256]u8 = undefined,
    pax_header_buffer: [256]u8 = undefined,
    saw_global_pax: bool = false,
    finished: bool = false,

    fn init(
        bytes: []const u8,
        metadata_policy: TarMetadataPolicy,
        metadata_identity: ?[]const u8,
    ) TarIterator {
        return .{
            .bytes = bytes,
            .metadata_policy = metadata_policy,
            .metadata_identity = metadata_identity,
        };
    }

    fn next(self: *TarIterator) !?TarLogicalEntry {
        if (self.finished) return null;
        if (self.bytes.len < 1024 or self.bytes.len % 512 != 0) {
            return error.TruncatedTar;
        }
        while (self.offset + 512 <= self.bytes.len) {
            const header_offset = self.offset;
            const header = self.bytes[self.offset..][0..512];
            if (isZeroBlock(header)) {
                if (self.pending_long_name != null or self.pending_pax or
                    (self.metadata_policy == .github_codeload_pax and !self.saw_global_pax) or
                    self.offset + 1024 > self.bytes.len or
                    !isZeroBlock(self.bytes[self.offset + 512 ..][0..512]))
                {
                    return error.TruncatedTar;
                }
                for (self.bytes[self.offset + 1024 ..]) |byte| {
                    if (byte != 0) return error.TrailingTarData;
                }
                self.finished = true;
                return null;
            }

            try validateTarChecksum(header);
            const size = try parseTarOctal(header[124..136]);
            const data_len = std.math.cast(usize, size) orelse return error.InvalidTarNumber;
            const data_start = self.offset + 512;
            const data_end = std.math.add(usize, data_start, data_len) catch
                return error.InvalidTarNumber;
            const padded_size_u64 = std.math.add(u64, size, 511) catch
                return error.InvalidTarNumber;
            const padded_size = std.math.cast(usize, padded_size_u64 & ~@as(u64, 511)) orelse
                return error.InvalidTarNumber;
            const next_offset = std.math.add(usize, data_start, padded_size) catch
                return error.InvalidTarNumber;
            if (data_end > self.bytes.len or next_offset > self.bytes.len) {
                return error.TruncatedTar;
            }
            self.offset = next_offset;

            const kind = header[156];
            if (kind == 'L') {
                if (self.metadata_policy != .gnu_long_name or self.pending_pax or
                    self.pending_long_name != null or
                    !std.mem.eql(u8, try strictTarTextField(header[0..100]), "././@LongLink") or
                    size < 102 or size > 4096)
                {
                    return error.UnsafeGnuLongName;
                }
                const encoded = self.bytes[data_start..data_end];
                if (encoded[encoded.len - 1] != 0 or
                    std.mem.indexOfScalar(u8, encoded[0 .. encoded.len - 1], 0) != null or
                    !std.unicode.utf8ValidateSlice(encoded[0 .. encoded.len - 1]))
                {
                    return error.UnsafeGnuLongName;
                }
                self.pending_long_name = encoded[0 .. encoded.len - 1];
                continue;
            }
            if (kind == 'x') {
                if (self.metadata_policy != .gitiles_pax) return error.UnsupportedTarEntry;
                if (self.pending_pax or self.pending_long_name != null or size < 28 or size > 4096) {
                    return error.UnsafePaxMetadata;
                }
                const pax_header_path = try tarPath(header, &self.path_buffer);
                @memcpy(self.pax_header_buffer[0..pax_header_path.len], pax_header_path);
                self.pending_pax_header_len = pax_header_path.len;
                const metadata = try parseGitilesPax(self.bytes[data_start..data_end]);
                self.pending_pax_path = metadata.path;
                self.pending_pax = true;
                continue;
            }
            if (kind == 'g') {
                if (self.metadata_policy != .github_codeload_pax) {
                    return error.UnsupportedTarEntry;
                }
                if (header_offset != 0 or self.saw_global_pax or self.pending_pax or
                    self.pending_long_name != null or size != 52 or
                    !std.mem.eql(u8, try strictTarTextField(header[0..100]), "pax_global_header") or
                    (try strictTarTextField(header[345..500])).len != 0)
                {
                    return error.UnsafePaxMetadata;
                }
                try validateGithubCodeloadPax(
                    self.bytes[data_start..data_end],
                    self.metadata_identity orelse return error.UnsafePaxMetadata,
                );
                self.saw_global_pax = true;
                continue;
            }
            if (kind != 0 and kind != '0' and kind != '5') {
                return error.UnsupportedTarEntry;
            }
            if (kind == '5' and size != 0) return error.UnsupportedTarEntry;

            const header_path = try tarPath(header, &self.path_buffer);
            const effective_path = if (self.pending_pax) block: {
                const target = self.pending_pax_path orelse header_path;
                if (self.pending_pax_path != null and
                    (header_path.len != 100 or target.len < header_path.len or
                        !std.mem.startsWith(u8, target, header_path)))
                {
                    return error.UnsafePaxMetadata;
                }
                if (!gitilesPaxHeaderMatches(
                    self.pax_header_buffer[0..self.pending_pax_header_len],
                    target,
                )) return error.UnsafePaxMetadata;
                self.pending_pax = false;
                self.pending_pax_path = null;
                break :block target;
            } else if (self.pending_long_name) |long_name| block: {
                if (long_name.len <= header_path.len or
                    !std.mem.startsWith(u8, long_name, header_path))
                {
                    return error.UnsafeGnuLongName;
                }
                self.pending_long_name = null;
                break :block long_name;
            } else header_path;
            return .{
                .path = effective_path,
                .data = self.bytes[data_start..data_end],
                .size = size,
                .is_directory = kind == '5',
            };
        }
        return error.TruncatedTar;
    }
};

const GitilesPaxMetadata = struct {
    path: ?[]const u8 = null,
};

fn parseGitilesPax(bytes: []const u8) !GitilesPaxMetadata {
    if (!std.unicode.utf8ValidateSlice(bytes)) return error.UnsafePaxMetadata;
    var metadata: GitilesPaxMetadata = .{};
    var cursor: usize = 0;
    var record_index: u8 = 0;
    var saw_mtime = false;
    while (cursor < bytes.len) : (record_index += 1) {
        if (record_index >= 2) return error.UnsafePaxMetadata;
        const relative_space = std.mem.indexOfScalar(u8, bytes[cursor..], ' ') orelse
            return error.UnsafePaxMetadata;
        const space = cursor + relative_space;
        const length_text = bytes[cursor..space];
        if (length_text.len == 0 or (length_text.len > 1 and length_text[0] == '0')) {
            return error.UnsafePaxMetadata;
        }
        for (length_text) |byte| {
            if (!std.ascii.isDigit(byte)) return error.UnsafePaxMetadata;
        }
        const record_length = std.fmt.parseInt(usize, length_text, 10) catch
            return error.UnsafePaxMetadata;
        const record_end = std.math.add(usize, cursor, record_length) catch
            return error.UnsafePaxMetadata;
        if (record_end > bytes.len or record_end <= space + 2 or bytes[record_end - 1] != '\n') {
            return error.UnsafePaxMetadata;
        }
        const payload = bytes[space + 1 .. record_end - 1];
        const equals = std.mem.indexOfScalar(u8, payload, '=') orelse
            return error.UnsafePaxMetadata;
        const key = payload[0..equals];
        const value = payload[equals + 1 ..];
        if (std.mem.eql(u8, key, "path")) {
            if (record_index != 0 or metadata.path != null or value.len <= 99 or value.len > 4096) {
                return error.UnsafePaxMetadata;
            }
            metadata.path = value;
        } else if (std.mem.eql(u8, key, "mtime")) {
            if (saw_mtime or !isGitilesMtime(value)) return error.UnsafePaxMetadata;
            saw_mtime = true;
        } else {
            return error.UnsafePaxMetadata;
        }
        cursor = record_end;
    }
    if (!saw_mtime or record_index == 0) return error.UnsafePaxMetadata;
    return metadata;
}

fn isGitilesMtime(value: []const u8) bool {
    if (value.len != 18 or value[10] != '.') return false;
    for (value, 0..) |byte, index| {
        if (index != 10 and !std.ascii.isDigit(byte)) return false;
    }
    return true;
}

fn gitilesPaxHeaderMatches(header_path: []const u8, target: []const u8) bool {
    const prefix = "./PaxHeaders.X/";
    const full_len = std.math.add(usize, prefix.len, target.len) catch return false;
    const expected_len = @min(@as(usize, 99), full_len);
    if (header_path.len != expected_len) return false;
    for (header_path, 0..) |actual, index| {
        const expected = if (index < prefix.len)
            prefix[index]
        else if (target[index - prefix.len] == '/')
            '_'
        else
            target[index - prefix.len];
        if (actual != expected) return false;
    }
    return true;
}

fn validateGithubCodeloadPax(bytes: []const u8, expected_commit: []const u8) !void {
    const prefix = "52 comment=";
    if (bytes.len != 52 or expected_commit.len != 40 or
        !std.mem.startsWith(u8, bytes, prefix) or bytes[bytes.len - 1] != '\n' or
        !std.mem.eql(u8, bytes[prefix.len .. bytes.len - 1], expected_commit))
    {
        return error.UnsafePaxMetadata;
    }
}

const CanonicalFileRecord = struct {
    path: []u8,
    size: u64,
    digest: [32]u8,
};

pub fn canonicalTreeDigestTarGzip(
    allocator: std.mem.Allocator,
    compressed: []const u8,
    limits: ArchiveLimits,
    expected_files: u32,
) ![32]u8 {
    try validateArchiveLimits(limits);
    if (compressed.len == 0 or compressed.len > limits.max_compressed_bytes) {
        return error.ArchiveCompressedTooLarge;
    }
    const plain_buffer = try allocator.alloc(u8, limits.max_decompressed_bytes);
    defer allocator.free(plain_buffer);
    var input = std.Io.Reader.fixed(compressed);
    var output = std.Io.Writer.fixed(plain_buffer);
    var history: [std.compress.flate.max_window_len]u8 = undefined;
    var decompressor = std.compress.flate.Decompress.init(&input, .gzip, &history);
    const decompressed_len = decompressor.reader.streamRemaining(&output) catch |err| {
        if (err == error.WriteFailed) return error.ArchiveExpandedTooLarge;
        if (decompressor.err) |detail| {
            if (detail == error.EndOfStream) return error.TruncatedGzip;
        }
        return error.InvalidGzip;
    };
    if (decompressor.err != null) return error.InvalidGzip;
    if (input.bufferedLen() != 0) return error.TrailingGzipData;
    const ratio_limit = std.math.mul(
        usize,
        compressed.len,
        limits.max_compression_ratio,
    ) catch std.math.maxInt(usize);
    if (decompressed_len > ratio_limit) return error.CompressionRatioExceeded;
    return canonicalTreeDigest(
        allocator,
        output.buffered(),
        limits,
        expected_files,
    );
}

pub fn canonicalTreeDigest(
    allocator: std.mem.Allocator,
    tar_bytes: []const u8,
    limits: ArchiveLimits,
    expected_files: u32,
) ![32]u8 {
    const summary = try inspectTar(allocator, tar_bytes, limits);
    if (summary.regular_files != expected_files) {
        return error.CanonicalTreeFileCountMismatch;
    }

    var records: std.ArrayList(CanonicalFileRecord) = .empty;
    defer {
        for (records.items) |record| allocator.free(record.path);
        records.deinit(allocator);
    }
    try records.ensureTotalCapacity(allocator, expected_files);
    var iterator = TarIterator.init(
        tar_bytes,
        limits.tar_metadata_policy,
        limits.tar_metadata_identity,
    );
    while (try iterator.next()) |entry| {
        if (!entry.is_directory) {
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(entry.data, &digest, .{});
            const owned_path = try allocator.dupe(u8, entry.path);
            errdefer allocator.free(owned_path);
            try records.append(allocator, .{
                .path = owned_path,
                .size = entry.size,
                .digest = digest,
            });
        }
    }
    if (records.items.len != expected_files) return error.CanonicalTreeFileCountMismatch;
    std.mem.sort(CanonicalFileRecord, records.items, {}, lessCanonicalRecord);

    var tree_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (records.items) |record| {
        tree_hasher.update(record.path);
        tree_hasher.update("\t");
        var size_buffer: [32]u8 = undefined;
        const size_text = std.fmt.bufPrint(&size_buffer, "{d}", .{record.size}) catch
            return error.InvalidTarNumber;
        tree_hasher.update(size_text);
        tree_hasher.update("\t");
        const digest_hex = std.fmt.bytesToHex(record.digest, .lower);
        tree_hasher.update(&digest_hex);
        tree_hasher.update("\n");
    }
    var result: [32]u8 = undefined;
    tree_hasher.final(&result);
    return result;
}

pub fn verifyCanonicalTreeDigest(actual: [32]u8, expected_hex: []const u8) !void {
    if (!isLowerHexDigest(expected_hex)) return error.InvalidDigest;
    var expected: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&expected, expected_hex) catch return error.InvalidDigest;
    if (!std.mem.eql(u8, &actual, &expected)) return error.CanonicalTreeDigestMismatch;
}

fn lessCanonicalRecord(_: void, left: CanonicalFileRecord, right: CanonicalFileRecord) bool {
    return std.mem.order(u8, left.path, right.path) == .lt;
}

fn validateArchiveLimits(limits: ArchiveLimits) !void {
    if (limits.max_compressed_bytes == 0 or
        limits.max_decompressed_bytes < 1024 or
        limits.max_member_bytes == 0 or
        limits.max_total_bytes == 0 or
        limits.max_entries == 0 or
        limits.max_compression_ratio == 0 or
        limits.max_member_bytes > limits.max_total_bytes)
    {
        return error.InvalidArchiveLimits;
    }
    if (limits.tar_metadata_policy == .github_codeload_pax) {
        const identity = limits.tar_metadata_identity orelse
            return error.InvalidArchiveLimits;
        if (identity.len != 40 or !isLowerHex(identity)) return error.InvalidArchiveLimits;
    } else if (limits.tar_metadata_identity != null) {
        return error.InvalidArchiveLimits;
    }
    validatePathAllowlist(limits.allowed_exact_paths, limits.allowed_path_prefixes) catch
        return error.InvalidArchiveLimits;
    if (limits.required_root.len != 0) {
        for (limits.allowed_exact_paths) |path| {
            if (!std.mem.startsWith(u8, path, limits.required_root)) {
                return error.InvalidArchiveLimits;
            }
        }
        for (limits.allowed_path_prefixes) |prefix| {
            if (!std.mem.startsWith(u8, prefix, limits.required_root)) {
                return error.InvalidArchiveLimits;
            }
        }
    }
}

fn isZeroBlock(block: []const u8) bool {
    for (block) |byte| {
        if (byte != 0) return false;
    }
    return true;
}

fn validateTarChecksum(header: []const u8) !void {
    const expected = try parseTarOctal(header[148..156]);
    var actual: u64 = 0;
    for (header, 0..) |byte, index| {
        actual += if (index >= 148 and index < 156) ' ' else byte;
    }
    if (actual != expected) return error.InvalidTarChecksum;
}

fn parseTarOctal(field: []const u8) !u64 {
    if (field.len == 0 or field[0] & 0x80 != 0) return error.InvalidTarNumber;
    var value: u64 = 0;
    var saw_digit = false;
    var ended = false;
    for (field) |byte| {
        if (byte == 0 or byte == ' ') {
            if (saw_digit) ended = true;
            continue;
        }
        if (ended or byte < '0' or byte > '7') return error.InvalidTarNumber;
        saw_digit = true;
        value = std.math.mul(u64, value, 8) catch return error.InvalidTarNumber;
        value = std.math.add(u64, value, byte - '0') catch
            return error.InvalidTarNumber;
    }
    if (!saw_digit) return error.InvalidTarNumber;
    return value;
}

fn tarPath(header: []const u8, buffer: *[256]u8) ![]const u8 {
    const name = try strictTarTextField(header[0..100]);
    const prefix = try strictTarTextField(header[345..500]);
    if (name.len == 0) return error.UnsafeArchivePath;
    if (prefix.len == 0) {
        @memcpy(buffer[0..name.len], name);
        return buffer[0..name.len];
    }
    const needed = std.math.add(usize, prefix.len, name.len + 1) catch
        return error.UnsafeArchivePath;
    if (needed > buffer.len) return error.UnsafeArchivePath;
    @memcpy(buffer[0..prefix.len], prefix);
    buffer[prefix.len] = '/';
    @memcpy(buffer[prefix.len + 1 .. needed], name);
    return buffer[0..needed];
}

fn strictTarTextField(field: []const u8) ![]const u8 {
    const end = std.mem.indexOfScalar(u8, field, 0) orelse return field;
    for (field[end..]) |byte| {
        if (byte != 0) return error.UnsafeArchivePath;
    }
    return field[0..end];
}

pub const ZipPolicy = struct {
    max_archive_bytes: usize,
    max_entries: u16,
    max_member_bytes: u64,
    max_total_bytes: u64,
    max_compression_ratio: u32,
    allow_data_descriptor: bool,
    allowed_extra_field_ids: []const u16,
    inventory: []const MemberLock,
    retained_members: []const MemberLock,
    collision_fold: CollisionFoldFn = asciiCollisionFold,
};

const ZipRange = struct {
    start: usize,
    end: usize,
};

pub fn inspectZip(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    policy: ZipPolicy,
) !ArchiveSummary {
    if (bytes.len < 22) return error.TruncatedZip;
    if (bytes.len > policy.max_archive_bytes or policy.max_entries == 0 or
        policy.max_member_bytes == 0 or policy.max_total_bytes == 0 or
        policy.max_compression_ratio == 0 or
        policy.max_member_bytes > policy.max_total_bytes or policy.max_entries > 128)
    {
        return error.InvalidZipPolicy;
    }

    const eocd_offset = bytes.len - 22;
    if (try readZipU32(bytes, eocd_offset) != 0x06054b50) {
        return error.ZipCommentOrTrailingData;
    }
    const disk = try readZipU16(bytes, eocd_offset + 4);
    const central_disk = try readZipU16(bytes, eocd_offset + 6);
    const entries_on_disk = try readZipU16(bytes, eocd_offset + 8);
    const entries_total = try readZipU16(bytes, eocd_offset + 10);
    const central_size = try readZipU32(bytes, eocd_offset + 12);
    const central_offset = try readZipU32(bytes, eocd_offset + 16);
    const comment_length = try readZipU16(bytes, eocd_offset + 20);
    if (comment_length != 0) return error.ZipCommentOrTrailingData;
    if (disk != 0 or central_disk != 0) return error.MultiDiskZip;
    if (entries_total == std.math.maxInt(u16) or central_size == std.math.maxInt(u32) or
        central_offset == std.math.maxInt(u32))
    {
        return error.Zip64Unsupported;
    }
    if (entries_on_disk != entries_total) return error.MultiDiskZip;
    if (entries_total == 0 or entries_total > policy.max_entries) {
        return error.TooManyArchiveEntries;
    }
    if (policy.inventory.len != 0 and policy.inventory.len != entries_total) {
        return error.ZipInventoryMismatch;
    }

    const central_start: usize = central_offset;
    const central_end = std.math.add(usize, central_start, central_size) catch
        return error.TruncatedZip;
    if (central_end != eocd_offset) return error.ZipCentralDirectoryMismatch;

    var registry = PathRegistry.initWithFold(allocator, policy.collision_fold);
    defer registry.deinit();
    var ranges: [128]ZipRange = undefined;
    if (policy.retained_members.len > 128) return error.InvalidZipPolicy;
    var retained_seen = [_]bool{false} ** 128;
    var summary: ArchiveSummary = .{
        .entries = 0,
        .regular_files = 0,
        .content_bytes = 0,
    };
    var central_cursor = central_start;
    for (0..entries_total) |entry_index| {
        if (try readZipU32(bytes, central_cursor) != 0x02014b50) {
            return error.TruncatedZip;
        }
        const flags = try readZipU16(bytes, central_cursor + 8);
        const method = try readZipU16(bytes, central_cursor + 10);
        const crc = try readZipU32(bytes, central_cursor + 16);
        const compressed_size = try readZipU32(bytes, central_cursor + 20);
        const expanded_size = try readZipU32(bytes, central_cursor + 24);
        const name_length = try readZipU16(bytes, central_cursor + 28);
        const extra_length = try readZipU16(bytes, central_cursor + 30);
        const member_comment_length = try readZipU16(bytes, central_cursor + 32);
        const member_disk = try readZipU16(bytes, central_cursor + 34);
        const external_attributes = try readZipU32(bytes, central_cursor + 38);
        const local_offset_u32 = try readZipU32(bytes, central_cursor + 42);
        if (compressed_size == std.math.maxInt(u32) or
            expanded_size == std.math.maxInt(u32) or
            local_offset_u32 == std.math.maxInt(u32))
        {
            return error.Zip64Unsupported;
        }
        if (member_comment_length != 0) return error.ZipCommentOrTrailingData;
        if (member_disk != 0) return error.MultiDiskZip;
        try validateZipFlags(flags, policy.allow_data_descriptor);
        if (method != 0 and method != 8) return error.UnsupportedZipMethod;

        const central_name_start = central_cursor + 46;
        const central_name_end = std.math.add(
            usize,
            central_name_start,
            name_length,
        ) catch return error.TruncatedZip;
        const central_extra_end = std.math.add(
            usize,
            central_name_end,
            extra_length,
        ) catch return error.TruncatedZip;
        if (central_extra_end > central_end) return error.TruncatedZip;
        const central_name = bytes[central_name_start..central_name_end];

        const local_offset: usize = local_offset_u32;
        for (ranges[0..entry_index]) |range| {
            if (local_offset == range.start) return error.DuplicateZipRecord;
        }
        if (try readZipU32(bytes, local_offset) != 0x04034b50) return error.TruncatedZip;
        const local_flags = try readZipU16(bytes, local_offset + 6);
        const local_method = try readZipU16(bytes, local_offset + 8);
        const local_crc = try readZipU32(bytes, local_offset + 14);
        const local_compressed_size = try readZipU32(bytes, local_offset + 18);
        const local_expanded_size = try readZipU32(bytes, local_offset + 22);
        const local_name_length = try readZipU16(bytes, local_offset + 26);
        const local_extra_length = try readZipU16(bytes, local_offset + 28);
        const local_name_start = local_offset + 30;
        const local_name_end = std.math.add(
            usize,
            local_name_start,
            local_name_length,
        ) catch return error.TruncatedZip;
        const local_extra_end = std.math.add(
            usize,
            local_name_end,
            local_extra_length,
        ) catch return error.TruncatedZip;
        if (local_extra_end > central_start) return error.TruncatedZip;
        const local_name = bytes[local_name_start..local_name_end];
        if (!std.mem.eql(u8, central_name, local_name)) return error.ZipNameMismatch;
        if (flags != local_flags or method != local_method) return error.ZipHeaderMismatch;
        if (flags & 0x0008 == 0 and
            (crc != local_crc or compressed_size != local_compressed_size or
                expanded_size != local_expanded_size))
        {
            return error.ZipSizeMismatch;
        }
        if (flags & 0x0008 != 0 and
            (local_crc != 0 or local_compressed_size != 0 or local_expanded_size != 0))
        {
            return error.AmbiguousZipDataDescriptor;
        }

        const is_directory = central_name.len != 0 and
            central_name[central_name.len - 1] == '/';
        const collision_name = if (is_directory)
            central_name[0 .. central_name.len - 1]
        else
            central_name;
        try validateArchivePath(collision_name);
        try registry.add(collision_name);
        if (is_directory and
            (crc != 0 or local_crc != 0 or
                compressed_size != 0 or local_compressed_size != 0 or
                expanded_size != 0 or local_expanded_size != 0 or
                method != 0 or local_method != 0 or flags & 0x0008 != 0))
        {
            return error.InvalidZipDirectory;
        }
        if (expanded_size > policy.max_member_bytes) return error.ArchiveMemberTooLarge;

        if (policy.inventory.len != 0) {
            const expected = policy.inventory[entry_index];
            const expected_directory = expected.kind == .directory;
            if (!std.mem.eql(u8, expected.path, central_name) or
                expected.size_bytes != expanded_size or
                expected_directory != is_directory)
            {
                return error.ZipInventoryMismatch;
            }
        }

        try validateZipExternalAttributes(external_attributes, is_directory);
        const central_extra = try validateZipExtraFields(
            bytes[central_name_end..central_extra_end],
            policy.allowed_extra_field_ids,
            .central,
        );
        const local_extra = try validateZipExtraFields(
            bytes[local_name_end..local_extra_end],
            policy.allowed_extra_field_ids,
            .local,
        );
        try validateZipExtraFieldPair(local_extra, central_extra);

        const data_start = local_extra_end;
        const data_end = std.math.add(usize, data_start, compressed_size) catch
            return error.TruncatedZip;
        if (data_end > central_start) return error.TruncatedZip;
        var record_end = data_end;
        if (flags & 0x0008 != 0) {
            if (!policy.allow_data_descriptor) return error.UnsupportedZipFlags;
            if (try readZipU32(bytes, data_end) != 0x08074b50 or
                try readZipU32(bytes, data_end + 4) != crc or
                try readZipU32(bytes, data_end + 8) != compressed_size or
                try readZipU32(bytes, data_end + 12) != expanded_size)
            {
                return error.AmbiguousZipDataDescriptor;
            }
            record_end = data_end + 16;
        }
        for (ranges[0..entry_index]) |range| {
            if (local_offset < range.end and record_end > range.start) {
                return error.OverlappingZipRange;
            }
        }
        ranges[entry_index] = .{ .start = local_offset, .end = record_end };

        if (!is_directory) {
            var expected_digest: ?[]const u8 = null;
            if (policy.inventory.len != 0) {
                expected_digest = policy.inventory[entry_index].sha256;
            }
            for (policy.retained_members, 0..) |retained, retained_index| {
                if (std.mem.eql(u8, retained.path, central_name)) {
                    if (retained.kind != .file or retained.size_bytes != expanded_size) {
                        return error.ZipInventoryMismatch;
                    }
                    if (expected_digest) |digest| {
                        if (retained.sha256 == null or
                            !std.mem.eql(u8, digest, retained.sha256.?))
                        {
                            return error.ZipInventoryMismatch;
                        }
                    } else {
                        expected_digest = retained.sha256;
                    }
                    retained_seen[retained_index] = true;
                }
            }
            try verifyZipPayload(
                allocator,
                bytes[data_start..data_end],
                method,
                expanded_size,
                crc,
                policy.max_compression_ratio,
                expected_digest,
            );
            summary.regular_files += 1;
            summary.content_bytes = std.math.add(
                u64,
                summary.content_bytes,
                expanded_size,
            ) catch return error.ArchiveExpandedTooLarge;
            if (summary.content_bytes > policy.max_total_bytes) {
                return error.ArchiveExpandedTooLarge;
            }
        }
        summary.entries += 1;
        central_cursor = central_extra_end;
    }
    if (central_cursor != central_end) return error.ZipCentralDirectoryMismatch;
    std.mem.sort(ZipRange, ranges[0..entries_total], {}, lessZipRange);
    var expected_local_offset: usize = 0;
    for (ranges[0..entries_total]) |range| {
        if (range.start != expected_local_offset) return error.UnreferencedZipLocalData;
        expected_local_offset = range.end;
    }
    if (expected_local_offset != central_start) return error.UnreferencedZipLocalData;
    for (retained_seen[0..policy.retained_members.len]) |seen| {
        if (!seen) return error.ZipInventoryMismatch;
    }
    return summary;
}

fn validateZipFlags(flags: u16, allow_descriptor: bool) !void {
    const allowed: u16 = 0x0800 | if (allow_descriptor) @as(u16, 0x0008) else 0;
    if (flags & ~allowed != 0) return error.UnsupportedZipFlags;
}

fn validateZipExternalAttributes(attributes: u32, is_directory: bool) !void {
    if (attributes & 0x0000_0400 != 0) return error.ZipReparsePoint;
    if ((attributes & 0x0000_0010 != 0) != is_directory) {
        return error.ZipDirectoryAttributeMismatch;
    }
    const unix_mode = @as(u16, @truncate(attributes >> 16));
    const kind = unix_mode & 0xf000;
    if (is_directory) {
        if (kind != 0 and kind != 0x4000) return error.ZipLinkOrSpecialEntry;
    } else if (kind != 0 and kind != 0x8000) return error.ZipLinkOrSpecialEntry;
}

fn lessZipRange(_: void, left: ZipRange, right: ZipRange) bool {
    if (left.start != right.start) return left.start < right.start;
    return left.end < right.end;
}

const ZipExtraLocation = enum { local, central };

const ZipTimestampExtra = struct {
    flags: u8,
    modified: u32,
};

const ZipExtraFields = struct {
    timestamp: ?ZipTimestampExtra = null,
    unix_owner: ?[]const u8 = null,
};

fn validateZipExtraFields(
    extra: []const u8,
    allowed: []const u16,
    location: ZipExtraLocation,
) !ZipExtraFields {
    var cursor: usize = 0;
    var seen: [16]u16 = undefined;
    var seen_count: usize = 0;
    var result: ZipExtraFields = .{};
    while (cursor < extra.len) {
        if (extra.len - cursor < 4) return error.MalformedZipExtraField;
        const id = std.mem.readInt(u16, extra[cursor..][0..2], .little);
        const size = std.mem.readInt(u16, extra[cursor + 2 ..][0..2], .little);
        cursor += 4;
        if (size > extra.len - cursor) return error.MalformedZipExtraField;
        var permitted = false;
        for (allowed) |candidate| {
            if (candidate == id) permitted = true;
        }
        if (!permitted) return error.UnknownZipExtraField;
        for (seen[0..seen_count]) |candidate| {
            if (candidate == id) return error.DuplicateZipExtraField;
        }
        if (seen_count == seen.len) return error.TooManyZipExtraFields;
        seen[seen_count] = id;
        seen_count += 1;
        const payload = extra[cursor..][0..size];
        switch (id) {
            0x5455 => {
                if (payload.len < 5 or payload[0] & ~@as(u8, 0x07) != 0 or
                    payload[0] & 0x01 == 0)
                {
                    return error.MalformedZipExtraField;
                }
                const expected_size: usize = switch (location) {
                    .local => 1 + 4 * @popCount(payload[0]),
                    .central => 5,
                };
                if (payload.len != expected_size) return error.MalformedZipExtraField;
                result.timestamp = .{
                    .flags = payload[0],
                    .modified = std.mem.readInt(u32, payload[1..][0..4], .little),
                };
            },
            0x7875 => {
                if (payload.len < 5 or payload[0] != 1) {
                    return error.MalformedZipExtraField;
                }
                const uid_size: usize = payload[1];
                if (uid_size == 0 or uid_size > 8 or 2 + uid_size >= payload.len) {
                    return error.MalformedZipExtraField;
                }
                const gid_size_offset = 2 + uid_size;
                const gid_size: usize = payload[gid_size_offset];
                if (gid_size == 0 or gid_size > 8 or
                    gid_size_offset + 1 + gid_size != payload.len)
                {
                    return error.MalformedZipExtraField;
                }
                result.unix_owner = payload;
            },
            else => return error.UnknownZipExtraField,
        }
        cursor += size;
    }
    return result;
}

fn validateZipExtraFieldPair(local: ZipExtraFields, central: ZipExtraFields) !void {
    if ((local.timestamp == null) != (central.timestamp == null) or
        (local.unix_owner == null) != (central.unix_owner == null))
    {
        return error.ZipExtraFieldMismatch;
    }
    if (local.timestamp) |local_timestamp| {
        const central_timestamp = central.timestamp.?;
        if (local_timestamp.flags != central_timestamp.flags or
            local_timestamp.modified != central_timestamp.modified)
        {
            return error.ZipExtraFieldMismatch;
        }
    }
    if (local.unix_owner) |local_owner| {
        if (!std.mem.eql(u8, local_owner, central.unix_owner.?)) {
            return error.ZipExtraFieldMismatch;
        }
    }
}

fn verifyZipPayload(
    allocator: std.mem.Allocator,
    compressed: []const u8,
    method: u16,
    expected_size: u32,
    expected_crc: u32,
    max_ratio: u32,
    expected_sha256: ?[]const u8,
) !void {
    const ratio_limit = std.math.mul(usize, compressed.len, max_ratio) catch
        std.math.maxInt(usize);
    if (expected_size > ratio_limit) return error.CompressionRatioExceeded;
    if (method == 0) {
        if (compressed.len != expected_size) return error.ZipSizeMismatch;
        if (std.hash.Crc32.hash(compressed) != expected_crc) return error.ZipCrcMismatch;
        if (expected_sha256) |digest| try verifySha256(compressed, digest);
        return;
    }

    const output_buffer = try allocator.alloc(u8, expected_size);
    defer allocator.free(output_buffer);
    var input = std.Io.Reader.fixed(compressed);
    var output = std.Io.Writer.fixed(output_buffer);
    var history: [std.compress.flate.max_window_len]u8 = undefined;
    var decompressor = std.compress.flate.Decompress.init(&input, .raw, &history);
    const actual_size = decompressor.reader.streamRemaining(&output) catch
        return error.InvalidZipDeflate;
    if (decompressor.err != null or input.bufferedLen() != 0 or
        actual_size != expected_size)
    {
        return error.InvalidZipDeflate;
    }
    if (std.hash.Crc32.hash(output.buffered()) != expected_crc) {
        return error.ZipCrcMismatch;
    }
    if (expected_sha256) |digest| try verifySha256(output.buffered(), digest);
}

pub const MaterializedArchive = struct {
    archive: ArchiveSummary,
    payload_files: u32,
    payload_bytes: u64,
    payload_sha256: [32]u8,
};

/// Revalidates an immutable staged archive, derives the exact payload digest,
/// and optionally materializes it through directory-relative handles. Passing
/// null is the read-only cache-audit path.
pub fn materializeArtifact(
    allocator: std.mem.Allocator,
    io: std.Io,
    artifact: Artifact,
    archive_bytes: []const u8,
    destination: ?std.Io.Dir,
    collision_fold: CollisionFoldFn,
) !MaterializedArchive {
    var records: std.ArrayList(CanonicalFileRecord) = .empty;
    defer {
        for (records.items) |record| allocator.free(record.path);
        records.deinit(allocator);
    }

    const summary = switch (artifact.archive_format) {
        .tar_gzip => try materializeTarGzip(
            allocator,
            io,
            artifact,
            archive_bytes,
            destination,
            collision_fold,
            &records,
        ),
        .restricted_zip => try materializeZip(
            allocator,
            io,
            artifact,
            archive_bytes,
            destination,
            collision_fold,
            &records,
        ),
        .direct_file => try materializeDirectFile(
            allocator,
            io,
            artifact,
            archive_bytes,
            destination,
            &records,
        ),
    };
    if (summary.entries != artifact.expected_entries) {
        return error.ArchiveEntryCountMismatch;
    }
    if (artifact.expected_regular_files) |expected| {
        if (summary.regular_files != expected) return error.ArchiveRegularFileCountMismatch;
    }
    if (artifact.expected_expanded_bytes) |expected| {
        if (summary.content_bytes != expected) return error.ArchiveExpandedSizeMismatch;
    }
    var payload_bytes: u64 = 0;
    for (records.items) |record| {
        payload_bytes = std.math.add(u64, payload_bytes, record.size) catch
            return error.ArchiveExpandedTooLarge;
    }
    return .{
        .archive = summary,
        .payload_files = std.math.cast(u32, records.items.len) orelse
            return error.TooManyArchiveEntries,
        .payload_bytes = payload_bytes,
        .payload_sha256 = hashCanonicalRecords(records.items),
    };
}

fn materializeTarGzip(
    allocator: std.mem.Allocator,
    io: std.Io,
    artifact: Artifact,
    compressed: []const u8,
    destination: ?std.Io.Dir,
    collision_fold: CollisionFoldFn,
    records: *std.ArrayList(CanonicalFileRecord),
) !ArchiveSummary {
    const limits = archiveLimitsForArtifact(artifact, collision_fold);
    const summary = try inspectTarGzip(allocator, compressed, limits);
    if (artifact.integrity == .canonical_tree) {
        const digest = try canonicalTreeDigestTarGzip(
            allocator,
            compressed,
            limits,
            artifact.expected_regular_files.?,
        );
        try verifyCanonicalTreeDigest(digest, artifact.canonical_tree_sha256.?);
    }
    const plain = try decompressGzipAlloc(allocator, compressed, limits);
    defer allocator.free(plain);

    var retained_seen = [_]bool{false} ** 128;
    if (artifact.retained_members.len > retained_seen.len) {
        return error.InvalidMemberInventory;
    }
    var iterator = TarIterator.init(
        plain,
        limits.tar_metadata_policy,
        limits.tar_metadata_identity,
    );
    while (try iterator.next()) |entry| {
        if (entry.is_directory) {
            if (destination) |dir| {
                if (artifact.retained_members.len == 0) {
                    const clean = if (entry.path[entry.path.len - 1] == '/')
                        entry.path[0 .. entry.path.len - 1]
                    else
                        entry.path;
                    try ensureVerifiedDirectory(io, dir, clean);
                }
            }
        } else {
            const retained_index = retainedMemberIndex(artifact.retained_members, entry.path);
            if (artifact.retained_members.len == 0 or retained_index != null) {
                if (retained_index) |index| {
                    retained_seen[index] = true;
                    const member = artifact.retained_members[index];
                    if (member.size_bytes != entry.size) {
                        return error.ArchiveRetainedMemberMismatch;
                    }
                    try verifySha256(entry.data, member.sha256.?);
                }
                try appendCanonicalRecord(allocator, records, entry.path, entry.data);
                if (destination) |dir| {
                    try writeVerifiedFile(io, dir, entry.path, entry.data);
                }
            }
        }
    }
    for (retained_seen[0..artifact.retained_members.len]) |seen| {
        if (!seen) return error.ArchiveRetainedMemberMismatch;
    }
    return summary;
}

fn materializeZip(
    allocator: std.mem.Allocator,
    io: std.Io,
    artifact: Artifact,
    bytes: []const u8,
    destination: ?std.Io.Dir,
    collision_fold: CollisionFoldFn,
    records: *std.ArrayList(CanonicalFileRecord),
) !ArchiveSummary {
    const policy = zipPolicyForArtifactWithFold(artifact, collision_fold);
    const summary = try inspectZip(allocator, bytes, policy);
    const eocd_offset = bytes.len - 22;
    const entries = try readZipU16(bytes, eocd_offset + 10);
    var central_cursor: usize = try readZipU32(bytes, eocd_offset + 16);
    var retained_seen = [_]bool{false} ** 128;
    if (artifact.retained_members.len > retained_seen.len) {
        return error.InvalidMemberInventory;
    }
    for (0..entries) |_| {
        const flags = try readZipU16(bytes, central_cursor + 8);
        const method = try readZipU16(bytes, central_cursor + 10);
        const compressed_size = try readZipU32(bytes, central_cursor + 20);
        const expanded_size = try readZipU32(bytes, central_cursor + 24);
        const name_length = try readZipU16(bytes, central_cursor + 28);
        const extra_length = try readZipU16(bytes, central_cursor + 30);
        const comment_length = try readZipU16(bytes, central_cursor + 32);
        const local_offset: usize = try readZipU32(bytes, central_cursor + 42);
        const name_start = central_cursor + 46;
        const name_end = name_start + name_length;
        const name = bytes[name_start..name_end];
        central_cursor = name_end + extra_length + comment_length;
        const is_directory = name[name.len - 1] == '/';
        if (is_directory) {
            if (destination) |dir| {
                if (artifact.retained_members.len == 0) {
                    try ensureVerifiedDirectory(io, dir, name[0 .. name.len - 1]);
                }
            }
            continue;
        }
        const retained_index = retainedMemberIndex(artifact.retained_members, name);
        if (artifact.retained_members.len != 0 and retained_index == null) continue;

        const local_name_length = try readZipU16(bytes, local_offset + 26);
        const local_extra_length = try readZipU16(bytes, local_offset + 28);
        const data_start = local_offset + 30 + local_name_length + local_extra_length;
        const data_end = data_start + compressed_size;
        const data = if (method == 0)
            try allocator.dupe(u8, bytes[data_start..data_end])
        else
            try inflateRawAlloc(allocator, bytes[data_start..data_end], expanded_size);
        defer allocator.free(data);
        if (flags & 0x0008 != 0 and !policy.allow_data_descriptor) {
            return error.UnsupportedZipFlags;
        }
        if (retained_index) |index| retained_seen[index] = true;
        try appendCanonicalRecord(allocator, records, name, data);
        if (destination) |dir| try writeVerifiedFile(io, dir, name, data);
    }
    for (retained_seen[0..artifact.retained_members.len]) |seen| {
        if (!seen) return error.ArchiveRetainedMemberMismatch;
    }
    return summary;
}

fn materializeDirectFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    artifact: Artifact,
    bytes: []const u8,
    destination: ?std.Io.Dir,
    records: *std.ArrayList(CanonicalFileRecord),
) !ArchiveSummary {
    const name = directFileName(artifact.id) orelse return error.UnknownArtifactId;
    try appendCanonicalRecord(allocator, records, name, bytes);
    if (destination) |dir| try writeVerifiedFile(io, dir, name, bytes);
    return .{ .entries = 1, .regular_files = 1, .content_bytes = bytes.len };
}

fn directFileName(id: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, id, "presentmon")) return "PresentMon-2.5.1-x64.exe";
    if (std.mem.eql(u8, id, "accessibility-insights")) return "AccessibilityInsights.msi";
    return null;
}

fn retainedMemberIndex(members: []const MemberLock, path: []const u8) ?usize {
    for (members, 0..) |member, index| {
        if (member.kind == .file and std.mem.eql(u8, member.path, path)) return index;
    }
    return null;
}

fn archiveLimitsForArtifact(
    artifact: Artifact,
    collision_fold: CollisionFoldFn,
) ArchiveLimits {
    return .{
        .max_compressed_bytes = std.math.cast(usize, artifact.download_limit_bytes) orelse
            std.math.maxInt(usize),
        .max_decompressed_bytes = std.math.cast(
            usize,
            artifact.tar_stream_limit_bytes orelse artifact.expanded_limit_bytes,
        ) orelse
            std.math.maxInt(usize),
        .max_member_bytes = artifact.expanded_limit_bytes,
        .max_total_bytes = artifact.expanded_limit_bytes,
        .max_entries = artifact.expected_entries,
        .max_compression_ratio = 1_024,
        .required_root = artifact.archive_root,
        .tar_metadata_policy = artifact.tar_metadata_policy,
        .tar_metadata_identity = if (artifact.tar_metadata_policy == .github_codeload_pax)
            artifact.commit
        else
            null,
        .allowed_exact_paths = artifact.allowed_exact_paths,
        .allowed_path_prefixes = artifact.allowed_path_prefixes,
        .collision_fold = collision_fold,
    };
}

fn stringSlicesEqual(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_item, right_item| {
        if (!std.mem.eql(u8, left_item, right_item)) return false;
    }
    return true;
}

fn validatePathAllowlist(
    exact_paths: []const []const u8,
    prefixes: []const []const u8,
) !void {
    if (exact_paths.len > 32 or prefixes.len > 32) return error.InvalidPathAllowlist;
    for (exact_paths, 0..) |path, index| {
        if (path.len == 0 or path[path.len - 1] == '/') {
            return error.InvalidPathAllowlist;
        }
        validateArchivePath(path) catch return error.InvalidPathAllowlist;
        for (exact_paths[index + 1 ..]) |other| {
            if (std.mem.eql(u8, path, other)) return error.InvalidPathAllowlist;
        }
    }
    for (prefixes, 0..) |prefix, index| {
        if (prefix.len < 2 or prefix[prefix.len - 1] != '/') {
            return error.InvalidPathAllowlist;
        }
        validateArchivePath(prefix[0 .. prefix.len - 1]) catch
            return error.InvalidPathAllowlist;
        for (prefixes[index + 1 ..]) |other| {
            if (std.mem.eql(u8, prefix, other)) return error.InvalidPathAllowlist;
        }
    }
}

fn archivePathAllowed(
    path: []const u8,
    exact_paths: []const []const u8,
    prefixes: []const []const u8,
) bool {
    if (exact_paths.len == 0 and prefixes.len == 0) return true;
    for (exact_paths) |exact| {
        if (std.mem.eql(u8, path, exact)) return true;
    }
    for (prefixes) |prefix| {
        if (std.mem.startsWith(u8, path, prefix)) return true;
    }
    return false;
}

fn decompressGzipAlloc(
    allocator: std.mem.Allocator,
    compressed: []const u8,
    limits: ArchiveLimits,
) ![]u8 {
    const plain_buffer = try allocator.alloc(u8, limits.max_decompressed_bytes);
    errdefer allocator.free(plain_buffer);
    var input = std.Io.Reader.fixed(compressed);
    var output = std.Io.Writer.fixed(plain_buffer);
    var history: [std.compress.flate.max_window_len]u8 = undefined;
    var decompressor = std.compress.flate.Decompress.init(&input, .gzip, &history);
    _ = decompressor.reader.streamRemaining(&output) catch |err| {
        if (err == error.WriteFailed) return error.ArchiveExpandedTooLarge;
        if (decompressor.err) |detail| {
            if (detail == error.EndOfStream) return error.TruncatedGzip;
        }
        return error.InvalidGzip;
    };
    if (decompressor.err != null or input.bufferedLen() != 0) return error.InvalidGzip;
    return allocator.realloc(plain_buffer, output.buffered().len);
}

fn inflateRawAlloc(
    allocator: std.mem.Allocator,
    compressed: []const u8,
    expected_size: usize,
) ![]u8 {
    const output_buffer = try allocator.alloc(u8, expected_size);
    errdefer allocator.free(output_buffer);
    var input = std.Io.Reader.fixed(compressed);
    var output = std.Io.Writer.fixed(output_buffer);
    var history: [std.compress.flate.max_window_len]u8 = undefined;
    var decompressor = std.compress.flate.Decompress.init(&input, .raw, &history);
    const actual = decompressor.reader.streamRemaining(&output) catch
        return error.InvalidZipDeflate;
    if (decompressor.err != null or input.bufferedLen() != 0 or actual != expected_size) {
        return error.InvalidZipDeflate;
    }
    return output_buffer;
}

fn appendCanonicalRecord(
    allocator: std.mem.Allocator,
    records: *std.ArrayList(CanonicalFileRecord),
    path: []const u8,
    bytes: []const u8,
) !void {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const owned_path = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_path);
    try records.append(allocator, .{
        .path = owned_path,
        .size = bytes.len,
        .digest = digest,
    });
}

fn hashCanonicalRecords(records: []CanonicalFileRecord) [32]u8 {
    std.mem.sort(CanonicalFileRecord, records, {}, lessCanonicalRecord);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var size_buffer: [32]u8 = undefined;
    for (records) |record| {
        hasher.update(record.path);
        hasher.update("\t");
        const size_text = std.fmt.bufPrint(&size_buffer, "{d}", .{record.size}) catch
            unreachable;
        hasher.update(size_text);
        hasher.update("\t");
        const digest_hex = std.fmt.bytesToHex(record.digest, .lower);
        hasher.update(&digest_hex);
        hasher.update("\n");
    }
    var result: [32]u8 = undefined;
    hasher.final(&result);
    return result;
}

fn writeVerifiedFile(io: std.Io, root: std.Io.Dir, path: []const u8, bytes: []const u8) !void {
    try validateArchivePath(path);
    const separator = std.mem.lastIndexOfScalar(u8, path, '/');
    var parent = try openOrCreateDirectory(io, root, if (separator) |index|
        path[0..index]
    else
        "");
    defer parent.close(io);
    const basename = if (separator) |index| path[index + 1 ..] else path;
    var file = try parent.createFile(io, basename, .{
        .read = true,
        .exclusive = true,
        .permissions = privateFilePermissions(),
        .resolve_beneath = true,
    });
    defer file.close(io);
    const stat = try file.stat(io);
    if (stat.kind != .file) return error.ExtractionEntryTypeMismatch;
    try file.writeStreamingAll(io, bytes);
    try file.sync(io);
}

fn ensureVerifiedDirectory(io: std.Io, root: std.Io.Dir, path: []const u8) !void {
    var dir = try openOrCreateDirectory(io, root, path);
    defer dir.close(io);
}

fn openOrCreateDirectory(io: std.Io, root: std.Io.Dir, path: []const u8) !std.Io.Dir {
    var current = try root.openDir(io, ".", .{ .follow_symlinks = false });
    errdefer current.close(io);
    if (path.len == 0) return current;
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0) return error.UnsafeArchivePath;
        current.createDir(io, component, privateDirPermissions()) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => |e| return e,
        };
        var next = try current.openDir(io, component, .{ .follow_symlinks = false });
        errdefer next.close(io);
        const stat = try next.stat(io);
        if (stat.kind != .directory) return error.ExtractionReparsePoint;
        current.close(io);
        current = next;
    }
    return current;
}

fn privateDirPermissions() std.Io.Dir.Permissions {
    return if (builtin.os.tag == .windows)
        .default_dir
    else
        .fromMode(0o700);
}

fn privateFilePermissions() std.Io.Dir.Permissions {
    return if (builtin.os.tag == .windows)
        .default_file
    else
        .fromMode(0o600);
}

pub fn hashMaterializedDirectory(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
    max_total_bytes: u64,
) !struct { files: u32, bytes: u64, digest: [32]u8 } {
    var records: std.ArrayList(CanonicalFileRecord) = .empty;
    defer {
        for (records.items) |record| allocator.free(record.path);
        records.deinit(allocator);
    }
    var walker = try root.walk(allocator);
    defer walker.deinit();
    var total: u64 = 0;
    while (try walker.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                var child = try entry.dir.openDir(io, entry.basename, .{
                    .iterate = true,
                    .follow_symlinks = false,
                });
                defer child.close(io);
                if ((try child.stat(io)).kind != .directory) {
                    return error.ExtractionReparsePoint;
                }
                var iterator = child.iterate();
                if (try iterator.next(io) == null) return error.UnexpectedEmptyDirectory;
                continue;
            },
            .file => {},
            else => return error.ExtractionReparsePoint,
        }
        var verification_file = try entry.dir.openFile(io, entry.basename, .{
            .follow_symlinks = false,
            .resolve_beneath = true,
        });
        defer verification_file.close(io);
        const stat = try verification_file.stat(io);
        if (stat.kind != .file) return error.ExtractionEntryTypeMismatch;
        var file = try entry.dir.openFile(io, entry.basename, .{
            .follow_symlinks = true,
            .resolve_beneath = true,
        });
        defer file.close(io);
        const readable_stat = try file.stat(io);
        if (readable_stat.kind != .file or readable_stat.inode != stat.inode or
            readable_stat.size != stat.size)
        {
            return error.ExtractionIdentityChanged;
        }
        total = std.math.add(u64, total, stat.size) catch
            return error.ArchiveExpandedTooLarge;
        if (total > max_total_bytes) return error.ArchiveExpandedTooLarge;
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        var reader_buffer: [64 * 1024]u8 = undefined;
        var reader = file.reader(io, &reader_buffer);
        var chunk: [64 * 1024]u8 = undefined;
        var read_total: u64 = 0;
        while (true) {
            const count = reader.interface.readSliceShort(&chunk) catch
                return reader.err orelse error.ReadFailed;
            if (count == 0) break;
            hasher.update(chunk[0..count]);
            read_total += count;
        }
        if (read_total != stat.size) return error.ExtractionSizeMismatch;
        var digest: [32]u8 = undefined;
        hasher.final(&digest);
        const normalized_path = try allocator.dupe(u8, entry.path);
        errdefer allocator.free(normalized_path);
        for (normalized_path) |*byte| if (byte.* == '\\') {
            byte.* = '/';
        };
        try records.append(allocator, .{
            .path = normalized_path,
            .size = stat.size,
            .digest = digest,
        });
    }
    return .{
        .files = std.math.cast(u32, records.items.len) orelse
            return error.TooManyArchiveEntries,
        .bytes = total,
        .digest = hashCanonicalRecords(records.items),
    };
}

pub fn verifySha256(bytes: []const u8, expected_hex: []const u8) !void {
    const expected = try parseSha256(expected_hex);
    var actual: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &actual, .{});
    if (!std.mem.eql(u8, &actual, &expected)) return error.DigestMismatch;
}

fn parseSha256(expected_hex: []const u8) ![32]u8 {
    if (!isLowerHexDigest(expected_hex)) return error.InvalidDigest;
    var expected: [32]u8 = undefined;
    for (0..expected.len) |index| {
        expected[index] = std.fmt.parseInt(
            u8,
            expected_hex[index * 2 ..][0..2],
            16,
        ) catch return error.InvalidDigest;
    }
    return expected;
}

fn readZipU16(bytes: []const u8, offset: usize) !u16 {
    if (offset > bytes.len or bytes.len - offset < 2) return error.TruncatedZip;
    return std.mem.readInt(u16, bytes[offset..][0..2], .little);
}

fn readZipU32(bytes: []const u8, offset: usize) !u32 {
    if (offset > bytes.len or bytes.len - offset < 4) return error.TruncatedZip;
    return std.mem.readInt(u32, bytes[offset..][0..4], .little);
}

pub const AttestationSummary = struct {
    subjects: u16,
    matching_subjects: u16,
};

const AttestationApiEntry = struct {
    repository_id: u64,
    bundle_url: []const u8,
    initiator: []const u8,
};

const AttestationApiResponse = struct {
    attestations: []const AttestationApiEntry,
};

pub const AttestationApiSelection = struct {
    bundle_url: []u8,
    path: []const u8,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.bundle_url);
    }
};

const bundle_query_fields = [_][]const u8{
    "se",  "sig", "ske", "skoid", "sks", "skt", "sktid",
    "skv", "sp",  "spr", "sr",    "st",  "sv",
};

pub fn validateAttestationApiResponse(
    allocator: std.mem.Allocator,
    response_json: []const u8,
    now_utc: []const u8,
) !AttestationApiSelection {
    if (response_json.len == 0 or response_json.len > 64 * 1024) {
        return error.AttestationApiResponseTooLarge;
    }
    if (!isStrictUtcTimestamp(now_utc)) return error.InvalidCurrentTime;

    var parsed = try std.json.parseFromSlice(
        AttestationApiResponse,
        allocator,
        response_json,
        .{
            .duplicate_field_behavior = .@"error",
            .ignore_unknown_fields = false,
        },
    );
    defer parsed.deinit();
    if (parsed.value.attestations.len != 1) return error.WrongAttestationResultCount;

    const entry = parsed.value.attestations[0];
    if (entry.repository_id != 103_962_638) return error.WrongRepositoryId;
    if (!std.mem.eql(u8, entry.initiator, "user")) return error.WrongAttestationInitiator;
    const path = try validateAttestationBundleUrl(entry.bundle_url, now_utc);

    const owned_url = try allocator.dupe(u8, entry.bundle_url);
    errdefer allocator.free(owned_url);
    const path_offset = @intFromPtr(path.ptr) - @intFromPtr(entry.bundle_url.ptr);
    return .{
        .bundle_url = owned_url,
        .path = owned_url[path_offset .. path_offset + path.len],
    };
}

fn validateAttestationBundleUrl(url: []const u8, now_utc: []const u8) ![]const u8 {
    const uri = validateHttpsUrl(url) catch return error.MalformedBundleUrl;
    if (uri.port != null) return error.MalformedBundleUrl;

    var host_buffer: [std.Io.net.HostName.max_len]u8 = undefined;
    const host = (uri.getHost(&host_buffer) catch return error.MalformedBundleUrl).bytes;
    if (!std.mem.eql(u8, host, "tmaproduction.blob.core.windows.net")) {
        return error.UnapprovedBundleHost;
    }

    const query_marker = std.mem.indexOfScalar(u8, url, '?') orelse
        return error.MalformedBundleUrl;
    if (query_marker == 0 or query_marker + 1 >= url.len or
        std.mem.indexOfScalar(u8, url[query_marker + 1 ..], '?') != null)
    {
        return error.MalformedBundleUrl;
    }
    var path_buffer: [4096]u8 = undefined;
    const raw_path = uri.path.toRaw(&path_buffer) catch return error.MalformedBundleUrl;
    const expected_path = "/attestations/103962638/2026/08/31/44147842.json.sn";
    if (!std.mem.eql(u8, raw_path, expected_path)) return error.UnapprovedBundlePath;

    var seen = [_]bool{false} ** bundle_query_fields.len;
    var version = [_]u8{0} ** 10;
    var key_version = [_]u8{0} ** 10;
    var have_version = false;
    var have_key_version = false;
    var count: usize = 0;
    var pairs = std.mem.splitScalar(u8, url[query_marker + 1 ..], '&');
    while (pairs.next()) |pair| {
        if (pair.len == 0) return error.MalformedBundleUrl;
        const equals = std.mem.indexOfScalar(u8, pair, '=') orelse
            return error.MalformedBundleUrl;
        if (equals == 0 or equals + 1 >= pair.len or
            std.mem.indexOfScalar(u8, pair[equals + 1 ..], '=') != null)
        {
            return error.MalformedBundleUrl;
        }
        const key = pair[0..equals];
        const field_index = bundleQueryFieldIndex(key) orelse
            return error.UnapprovedBundleQuery;
        if (seen[field_index]) return error.DuplicateBundleQueryField;
        seen[field_index] = true;
        count += 1;

        var decoded_buffer: [512]u8 = undefined;
        const decoded = percentDecodeQueryValue(
            pair[equals + 1 ..],
            &decoded_buffer,
        ) catch return error.MalformedBundleUrl;
        if (std.mem.eql(u8, key, "se") or std.mem.eql(u8, key, "ske")) {
            if (!isStrictUtcTimestamp(decoded)) return error.MalformedBundleUrl;
            if (!utcLessThan(now_utc, decoded)) return error.ExpiredBundleUrl;
        } else if (std.mem.eql(u8, key, "st") or std.mem.eql(u8, key, "skt")) {
            if (!isStrictUtcTimestamp(decoded)) return error.MalformedBundleUrl;
            if (utcLessThan(now_utc, decoded)) return error.BundleUrlNotYetValid;
        } else if (std.mem.eql(u8, key, "sig")) {
            if (!isSha256Base64(decoded)) return error.MalformedBundleUrl;
        } else if (std.mem.eql(u8, key, "skoid") or std.mem.eql(u8, key, "sktid")) {
            if (!isLowerUuid(decoded)) return error.MalformedBundleUrl;
        } else if (std.mem.eql(u8, key, "sks") or std.mem.eql(u8, key, "sr")) {
            if (!std.mem.eql(u8, decoded, "b")) return error.UnapprovedBundleQuery;
        } else if (std.mem.eql(u8, key, "sp")) {
            if (!std.mem.eql(u8, decoded, "r")) return error.UnapprovedBundleQuery;
        } else if (std.mem.eql(u8, key, "spr")) {
            if (!std.mem.eql(u8, decoded, "https")) return error.UnapprovedBundleQuery;
        } else if (std.mem.eql(u8, key, "sv")) {
            if (!isStrictDate(decoded)) return error.MalformedBundleUrl;
            @memcpy(&version, decoded);
            have_version = true;
        } else if (std.mem.eql(u8, key, "skv")) {
            if (!isStrictDate(decoded)) return error.MalformedBundleUrl;
            @memcpy(&key_version, decoded);
            have_key_version = true;
        }
    }
    if (count != bundle_query_fields.len) return error.MissingBundleQueryField;
    for (seen) |present| if (!present) return error.MissingBundleQueryField;
    if (!have_version or !have_key_version or !std.mem.eql(u8, &version, &key_version)) {
        return error.UnapprovedBundleQuery;
    }
    return url[std.mem.indexOf(u8, url, raw_path).?..query_marker];
}

fn bundleQueryFieldIndex(key: []const u8) ?usize {
    for (bundle_query_fields, 0..) |expected, index| {
        if (std.mem.eql(u8, key, expected)) return index;
    }
    return null;
}

fn percentDecodeQueryValue(encoded: []const u8, buffer: []u8) ![]const u8 {
    var input_index: usize = 0;
    var output_index: usize = 0;
    while (input_index < encoded.len) {
        if (output_index >= buffer.len) return error.QueryValueTooLarge;
        const byte = encoded[input_index];
        if (byte == '%') {
            if (input_index + 2 >= encoded.len) return error.InvalidPercentEncoding;
            const high = hexNibble(encoded[input_index + 1]) orelse
                return error.InvalidPercentEncoding;
            const low = hexNibble(encoded[input_index + 2]) orelse
                return error.InvalidPercentEncoding;
            buffer[output_index] = (high << 4) | low;
            input_index += 3;
        } else {
            if (byte == '+' or byte < 0x21 or byte == 0x7f) {
                return error.InvalidPercentEncoding;
            }
            buffer[output_index] = byte;
            input_index += 1;
        }
        if (buffer[output_index] < 0x20 or buffer[output_index] == 0x7f) {
            return error.InvalidPercentEncoding;
        }
        output_index += 1;
    }
    return buffer[0..output_index];
}

fn hexNibble(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

fn isStrictUtcTimestamp(value: []const u8) bool {
    if (value.len != 20 or value[4] != '-' or value[7] != '-' or
        value[10] != 'T' or value[13] != ':' or value[16] != ':' or value[19] != 'Z')
    {
        return false;
    }
    const digit_positions = [_]usize{ 0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18 };
    for (digit_positions) |position| {
        if (value[position] < '0' or value[position] > '9') return false;
    }
    const year = decimalPair(value[0], value[1]) * 100 + decimalPair(value[2], value[3]);
    const month = decimalPair(value[5], value[6]);
    const day = decimalPair(value[8], value[9]);
    const hour = decimalPair(value[11], value[12]);
    const minute = decimalPair(value[14], value[15]);
    const second = decimalPair(value[17], value[18]);
    if (year < 2024 or year > 2100 or month == 0 or month > 12 or
        day == 0 or day > daysInMonth(year, month) or hour > 23 or
        minute > 59 or second > 59)
    {
        return false;
    }
    return true;
}

fn isStrictDate(value: []const u8) bool {
    if (value.len != 10) return false;
    var timestamp: [20]u8 = undefined;
    @memcpy(timestamp[0..10], value);
    @memcpy(timestamp[10..], "T00:00:00Z");
    return isStrictUtcTimestamp(&timestamp);
}

fn parseVerifiedTimestamp(value: []const u8) !i64 {
    if (value.len != 20 and value.len != 25) return error.WrongVerifiedTimestamp;
    var local_timestamp: [20]u8 = undefined;
    @memcpy(local_timestamp[0..19], value[0..19]);
    local_timestamp[19] = 'Z';
    if (!isStrictUtcTimestamp(&local_timestamp)) return error.WrongVerifiedTimestamp;

    var offset_seconds: i64 = 0;
    if (value.len == 20) {
        if (value[19] != 'Z') return error.WrongVerifiedTimestamp;
    } else {
        if ((value[19] != '+' and value[19] != '-') or value[22] != ':') {
            return error.WrongVerifiedTimestamp;
        }
        for ([_]usize{ 20, 21, 23, 24 }) |position| {
            if (!std.ascii.isDigit(value[position])) return error.WrongVerifiedTimestamp;
        }
        const offset_hour = decimalPair(value[20], value[21]);
        const offset_minute = decimalPair(value[23], value[24]);
        if (offset_hour > 23 or offset_minute > 59) return error.WrongVerifiedTimestamp;
        offset_seconds = @as(i64, offset_hour) * 3600 + @as(i64, offset_minute) * 60;
        // RFC3339 -00:00 denotes an unknown local offset, not a known UTC zone.
        if (value[19] == '-') {
            if (offset_seconds == 0) return error.WrongVerifiedTimestamp;
            offset_seconds = -offset_seconds;
        }
    }

    const year = decimalPair(value[0], value[1]) * 100 + decimalPair(value[2], value[3]);
    const month = decimalPair(value[5], value[6]);
    var days: i64 = decimalPair(value[8], value[9]) - 1;
    for (1970..year) |previous_year| {
        days += std.time.epoch.getDaysInYear(@intCast(previous_year));
    }
    for (1..month) |previous_month| {
        days += daysInMonth(year, @intCast(previous_month));
    }
    return days * 86400 + @as(i64, decimalPair(value[11], value[12])) * 3600 +
        @as(i64, decimalPair(value[14], value[15])) * 60 +
        decimalPair(value[17], value[18]) - offset_seconds;
}

fn decimalPair(a: u8, b: u8) u16 {
    return @as(u16, a - '0') * 10 + @as(u16, b - '0');
}

fn daysInMonth(year: u16, month: u16) u16 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)) 29 else 28,
        else => 0,
    };
}

fn utcLessThan(a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn isLowerUuid(value: []const u8) bool {
    if (value.len != 36 or value[8] != '-' or value[13] != '-' or
        value[18] != '-' or value[23] != '-')
    {
        return false;
    }
    for (value, 0..) |byte, index| {
        if (index == 8 or index == 13 or index == 18 or index == 23) continue;
        if (!(byte >= '0' and byte <= '9') and !(byte >= 'a' and byte <= 'f')) return false;
    }
    return true;
}

fn isSha256Base64(value: []const u8) bool {
    if (value.len != 44) return false;
    const size = std.base64.standard.Decoder.calcSizeForSlice(value) catch return false;
    if (size != 32) return false;
    var decoded: [32]u8 = undefined;
    std.base64.standard.Decoder.decode(&decoded, value) catch return false;
    return true;
}

pub fn validatePdfiumEvidence(
    allocator: std.mem.Allocator,
    bundle_jsonl: []const u8,
    trusted_root_jsonl: []const u8,
) !AttestationSummary {
    if (bundle_jsonl.len != 18_096 or trusted_root_jsonl.len != 34_636) {
        return error.EvidenceDigestMismatch;
    }
    verifySha256(
        bundle_jsonl,
        "1f84f3d920a8c3ad5dc480899631eef877c43f99d1e85b634af55570f51e2ee6",
    ) catch return error.EvidenceDigestMismatch;
    verifySha256(
        trusted_root_jsonl,
        "db07310827da2ae2798ec7eefc5daf8432506ce458d5bc30cd2feba03708d239",
    ) catch return error.EvidenceDigestMismatch;

    try validateTrustedRootStructure(allocator, trusted_root_jsonl);
    const statement = try decodeDssePayload(allocator, bundle_jsonl);
    defer allocator.free(statement);
    return validateSlsaStatement(allocator, statement);
}

pub fn validateGhVerificationResult(
    allocator: std.mem.Allocator,
    output_json: []const u8,
) !AttestationSummary {
    if (output_json.len == 0 or output_json.len > 256 * 1024 or
        std.mem.indexOfScalar(u8, output_json, '\r') != null)
    {
        return error.InvalidGhVerificationResult;
    }
    var parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        output_json,
        .{ .duplicate_field_behavior = .@"error" },
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidGhVerificationResult,
    };
    defer parsed.deinit();
    const results = switch (parsed.value) {
        .array => |array| array.items,
        else => return error.InvalidGhVerificationResult,
    };
    if (results.len != 1) return error.WrongGhVerificationResultCount;
    try rejectUnknownJsonFields(
        results[0],
        &.{ "attestation", "verificationResult" },
        error.UnknownGhVerificationField,
    );
    _ = switch (try jsonField(results[0], "attestation")) {
        .object => {},
        else => return error.InvalidGhVerificationResult,
    };
    const verification = try jsonField(results[0], "verificationResult");
    try rejectUnknownJsonFields(
        verification,
        &.{ "mediaType", "signature", "statement", "verifiedTimestamps", "verifiedIdentity" },
        error.UnknownGhVerificationField,
    );
    try expectJsonStringField(
        verification,
        "mediaType",
        "application/vnd.dev.sigstore.verificationresult+json;version=0.1",
        error.InvalidGhVerificationResult,
    );
    const signature = try jsonField(verification, "signature");
    try rejectUnknownJsonFields(
        signature,
        &.{"certificate"},
        error.UnknownGhVerificationField,
    );
    const certificate = try jsonField(signature, "certificate");
    const expected_fields = [_]struct { []const u8, []const u8 }{
        .{ "certificateIssuer", "CN=sigstore-intermediate,O=sigstore.dev" },
        .{ "subjectAlternativeName", "https://github.com/bblanchon/pdfium-binaries/.github/workflows/build-all.yml@refs/heads/master" },
        .{ "issuer", "https://token.actions.githubusercontent.com" },
        .{ "githubWorkflowTrigger", "workflow_dispatch" },
        .{ "githubWorkflowSHA", "5453f3afc4785cbad82c05f6ceb4dabea0cb81a0" },
        .{ "githubWorkflowName", "Build all" },
        .{ "githubWorkflowRepository", "bblanchon/pdfium-binaries" },
        .{ "githubWorkflowRef", "refs/heads/master" },
        .{ "buildSignerURI", "https://github.com/bblanchon/pdfium-binaries/.github/workflows/build-all.yml@refs/heads/master" },
        .{ "buildSignerDigest", "5453f3afc4785cbad82c05f6ceb4dabea0cb81a0" },
        .{ "sourceRepositoryURI", "https://github.com/bblanchon/pdfium-binaries" },
        .{ "sourceRepositoryIdentifier", "103962638" },
        .{ "sourceRepositoryRef", "refs/heads/master" },
        .{ "sourceRepositoryDigest", "5453f3afc4785cbad82c05f6ceb4dabea0cb81a0" },
        .{ "sourceRepositoryOwnerURI", "https://github.com/bblanchon" },
        .{ "sourceRepositoryOwnerIdentifier", "5462433" },
        .{ "buildConfigURI", "https://github.com/bblanchon/pdfium-binaries/.github/workflows/build-all.yml@refs/heads/master" },
        .{ "buildConfigDigest", "5453f3afc4785cbad82c05f6ceb4dabea0cb81a0" },
        .{ "buildTrigger", "workflow_dispatch" },
        .{ "sourceRepositoryVisibilityAtSigning", "public" },
        .{ "runnerEnvironment", "github-hosted" },
        .{ "runInvocationURI", "https://github.com/bblanchon/pdfium-binaries/actions/runs/33383157207/attempts/1" },
    };
    try rejectUnknownJsonFields(
        certificate,
        &.{
            "certificateIssuer",
            "subjectAlternativeName",
            "issuer",
            "githubWorkflowTrigger",
            "githubWorkflowSHA",
            "githubWorkflowName",
            "githubWorkflowRepository",
            "githubWorkflowRef",
            "buildSignerURI",
            "buildSignerDigest",
            "sourceRepositoryURI",
            "sourceRepositoryIdentifier",
            "sourceRepositoryRef",
            "sourceRepositoryDigest",
            "sourceRepositoryOwnerURI",
            "sourceRepositoryOwnerIdentifier",
            "buildConfigURI",
            "buildConfigDigest",
            "buildTrigger",
            "sourceRepositoryVisibilityAtSigning",
            "runnerEnvironment",
            "runInvocationURI",
        },
        error.UnknownGhVerificationField,
    );
    for (expected_fields) |field| {
        try expectJsonStringField(certificate, field[0], field[1], error.WrongGhCertificateIdentity);
    }

    const identity = try jsonField(verification, "verifiedIdentity");
    try rejectUnknownJsonFields(
        identity,
        &.{ "subjectAlternativeName", "issuer", "runnerEnvironment" },
        error.UnknownGhVerificationField,
    );
    const identity_san = try jsonField(identity, "subjectAlternativeName");
    try rejectUnknownJsonFields(
        identity_san,
        &.{"subjectAlternativeName"},
        error.UnknownGhVerificationField,
    );
    try expectJsonStringField(
        identity_san,
        "subjectAlternativeName",
        "https://github.com/bblanchon/pdfium-binaries/.github/workflows/build-all.yml@refs/heads/master",
        error.WrongGhCertificateIdentity,
    );
    try expectJsonStringField(identity, "runnerEnvironment", "github-hosted", error.WrongGhCertificateIdentity);
    const identity_issuer = try jsonField(identity, "issuer");
    try rejectUnknownJsonFields(
        identity_issuer,
        &.{ "issuer", "regexp" },
        error.UnknownGhVerificationField,
    );
    // Pinned gh 2.100.0 reports this generic policy even with the exact
    // --cert-oidc-issuer argument. It is not our issuer trust check: the
    // verified certificate's issuer is independently required above.
    try expectJsonStringField(identity_issuer, "issuer", "", error.WrongGhCertificateIdentity);
    try expectJsonStringField(identity_issuer, "regexp", ".*", error.WrongGhCertificateIdentity);

    const timestamps = try jsonArrayField(verification, "verifiedTimestamps");
    if (timestamps.len != 1) return error.WrongVerifiedTimestamp;
    try rejectUnknownJsonFields(
        timestamps[0],
        &.{ "timestamp", "type", "uri" },
        error.UnknownGhVerificationField,
    );
    // gh serializes Sigstore's verified instant using the host's local zone.
    // Bind that instant to the locked transparency entry, not its presentation.
    const verified_timestamp = try parseVerifiedTimestamp(try jsonStringField(timestamps[0], "timestamp"));
    if (verified_timestamp != locked_pdfium_integrated_time) return error.WrongVerifiedTimestamp;
    try expectJsonStringField(timestamps[0], "type", "Tlog", error.WrongVerifiedTimestamp);
    try expectJsonStringField(
        timestamps[0],
        "uri",
        "https://rekor.sigstore.dev",
        error.WrongVerifiedTimestamp,
    );

    const statement = try jsonField(verification, "statement");
    var encoded: std.Io.Writer.Allocating = .init(allocator);
    defer encoded.deinit();
    // Writer.Allocating intentionally collapses capacity/allocation failure to
    // WriteFailed. This in-memory writer has no other sink failure mode, so
    // preserve the allocator contract rather than misclassifying OOM as JSON.
    std.json.Stringify.value(statement, .{}, &encoded.writer) catch
        return error.OutOfMemory;
    const statement_json = try encoded.toOwnedSlice();
    defer allocator.free(statement_json);
    return validateSlsaStatement(allocator, statement_json);
}

pub fn decodeDssePayload(
    allocator: std.mem.Allocator,
    bundle_jsonl: []const u8,
) ![]u8 {
    if (bundle_jsonl.len == 0 or bundle_jsonl.len > 64 * 1024 or
        bundle_jsonl[bundle_jsonl.len - 1] != '\n' or
        std.mem.indexOfScalar(u8, bundle_jsonl[0 .. bundle_jsonl.len - 1], '\n') != null or
        std.mem.indexOfScalar(u8, bundle_jsonl, '\r') != null)
    {
        return error.InvalidAttestationJsonl;
    }

    var parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        bundle_jsonl[0 .. bundle_jsonl.len - 1],
        .{ .duplicate_field_behavior = .@"error" },
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidAttestationBundle,
    };
    defer parsed.deinit();
    const root = parsed.value;
    if (!std.mem.eql(
        u8,
        try jsonStringField(root, "mediaType"),
        "application/vnd.dev.sigstore.bundle.v0.3+json",
    )) return error.WrongAttestationMediaType;

    const envelope = try jsonField(root, "dsseEnvelope");
    if (!std.mem.eql(
        u8,
        try jsonStringField(envelope, "payloadType"),
        "application/vnd.in-toto+json",
    )) return error.WrongAttestationMediaType;
    const signatures = try jsonArrayField(envelope, "signatures");
    if (signatures.len != 1) return error.WrongAttestationSignatureCount;

    const material = try jsonField(root, "verificationMaterial");
    const tlog_entries = try jsonArrayField(material, "tlogEntries");
    if (tlog_entries.len != 1) return error.WrongTransparencyEntryCount;
    const integrated_time = try jsonStringField(tlog_entries[0], "integratedTime");
    if (!std.mem.eql(u8, integrated_time, std.fmt.comptimePrint("{d}", .{locked_pdfium_integrated_time}))) {
        return error.WrongVerifiedTimestamp;
    }

    const certificate = try jsonField(material, "certificate");
    const certificate_base64 = try jsonStringField(certificate, "rawBytes");
    const certificate_size = std.base64.standard.Decoder.calcSizeForSlice(
        certificate_base64,
    ) catch return error.InvalidAttestationCertificate;
    if (certificate_size == 0 or certificate_size > 16 * 1024) {
        return error.InvalidAttestationCertificate;
    }
    const certificate_der = try allocator.alloc(u8, certificate_size);
    defer allocator.free(certificate_der);
    std.base64.standard.Decoder.decode(
        certificate_der,
        certificate_base64,
    ) catch return error.InvalidAttestationCertificate;
    const required_certificate_strings = [_][]const u8{
        "https://github.com/bblanchon/pdfium-binaries/.github/workflows/build-all.yml@refs/heads/master",
        "https://token.actions.githubusercontent.com",
        "bblanchon/pdfium-binaries",
        "refs/heads/master",
        "5453f3afc4785cbad82c05f6ceb4dabea0cb81a0",
        "github-hosted",
        "103962638",
        "https://github.com/bblanchon/pdfium-binaries/actions/runs/33383157207/attempts/1",
    };
    for (required_certificate_strings) |required| {
        if (std.mem.indexOf(u8, certificate_der, required) == null) {
            return error.WrongCertificateIdentity;
        }
    }

    const payload = try jsonStringField(envelope, "payload");
    const payload_size = std.base64.standard.Decoder.calcSizeForSlice(payload) catch
        return error.InvalidDssePayload;
    if (payload_size == 0 or payload_size > 64 * 1024) return error.InvalidDssePayload;
    const decoded = try allocator.alloc(u8, payload_size);
    errdefer allocator.free(decoded);
    std.base64.standard.Decoder.decode(decoded, payload) catch
        return error.InvalidDssePayload;
    return decoded;
}

pub fn validateSlsaStatement(
    allocator: std.mem.Allocator,
    statement_json: []const u8,
) !AttestationSummary {
    if (statement_json.len == 0 or statement_json.len > 64 * 1024) {
        return error.InvalidSlsaStatement;
    }
    var parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        statement_json,
        .{ .duplicate_field_behavior = .@"error" },
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidSlsaStatement,
    };
    defer parsed.deinit();
    const root = parsed.value;
    try rejectUnknownJsonFields(
        root,
        &.{ "_type", "subject", "predicateType", "predicate" },
        error.UnknownSlsaField,
    );
    if (!std.mem.eql(
        u8,
        try jsonStringField(root, "_type"),
        "https://in-toto.io/Statement/v1",
    )) return error.InvalidSlsaStatement;
    if (!std.mem.eql(
        u8,
        try jsonStringField(root, "predicateType"),
        "https://slsa.dev/provenance/v1",
    )) return error.WrongPredicateType;

    const subjects = try jsonArrayField(root, "subject");
    if (subjects.len != 45) return error.WrongSubjectCount;
    var matching: u16 = 0;
    for (subjects) |subject| {
        try rejectUnknownJsonFields(
            subject,
            &.{ "digest", "name" },
            error.UnknownSlsaField,
        );
        const name = try jsonStringField(subject, "name");
        const digest = try jsonField(subject, "digest");
        try rejectUnknownJsonFields(
            digest,
            &.{"sha256"},
            error.UnknownSlsaField,
        );
        const sha256 = try jsonStringField(digest, "sha256");
        if (!isLowerHexDigest(sha256)) return error.InvalidDigest;
        if (std.mem.eql(u8, name, "pdfium-win-x64.tgz") and
            std.mem.eql(
                u8,
                sha256,
                "61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41",
            ))
        {
            matching += 1;
        }
    }
    if (matching == 0) return error.MissingMatchingSubject;
    if (matching != 1) return error.DuplicateMatchingSubject;

    const predicate = try jsonField(root, "predicate");
    try rejectUnknownJsonFields(
        predicate,
        &.{ "buildDefinition", "runDetails" },
        error.UnknownSlsaField,
    );
    const definition = try jsonField(predicate, "buildDefinition");
    try rejectUnknownJsonFields(
        definition,
        &.{ "buildType", "externalParameters", "internalParameters", "resolvedDependencies" },
        error.UnknownSlsaField,
    );
    if (!std.mem.eql(
        u8,
        try jsonStringField(definition, "buildType"),
        "https://actions.github.io/buildtypes/workflow/v1",
    )) return error.WrongWorkflowIdentity;
    const external = try jsonField(definition, "externalParameters");
    try rejectUnknownJsonFields(
        external,
        &.{"workflow"},
        error.UnknownSlsaField,
    );
    const workflow = try jsonField(external, "workflow");
    try rejectUnknownJsonFields(
        workflow,
        &.{ "path", "ref", "repository" },
        error.UnknownSlsaField,
    );
    try expectJsonStringField(
        workflow,
        "repository",
        "https://github.com/bblanchon/pdfium-binaries",
        error.WrongWorkflowIdentity,
    );
    try expectJsonStringField(
        workflow,
        "path",
        ".github/workflows/build-all.yml",
        error.WrongWorkflowIdentity,
    );
    try expectJsonStringField(
        workflow,
        "ref",
        "refs/heads/master",
        error.WrongWorkflowIdentity,
    );
    const internal = try jsonField(definition, "internalParameters");
    try rejectUnknownJsonFields(
        internal,
        &.{"github"},
        error.UnknownSlsaField,
    );
    const github = try jsonField(internal, "github");
    try rejectUnknownJsonFields(
        github,
        &.{ "event_name", "repository_id", "repository_owner_id", "runner_environment" },
        error.UnknownSlsaField,
    );
    try expectJsonStringField(
        github,
        "event_name",
        "workflow_dispatch",
        error.WrongWorkflowIdentity,
    );
    try expectJsonStringField(
        github,
        "repository_id",
        "103962638",
        error.WrongWorkflowIdentity,
    );
    try expectJsonStringField(
        github,
        "repository_owner_id",
        "5462433",
        error.WrongWorkflowIdentity,
    );
    try expectJsonStringField(
        github,
        "runner_environment",
        "github-hosted",
        error.WrongWorkflowIdentity,
    );

    const dependencies = try jsonArrayField(definition, "resolvedDependencies");
    if (dependencies.len != 1) return error.WrongWorkflowIdentity;
    try rejectUnknownJsonFields(
        dependencies[0],
        &.{ "digest", "uri" },
        error.UnknownSlsaField,
    );
    try expectJsonStringField(
        dependencies[0],
        "uri",
        "git+https://github.com/bblanchon/pdfium-binaries@refs/heads/master",
        error.WrongWorkflowIdentity,
    );
    const dependency_digest = try jsonField(dependencies[0], "digest");
    try rejectUnknownJsonFields(
        dependency_digest,
        &.{"gitCommit"},
        error.UnknownSlsaField,
    );
    try expectJsonStringField(
        dependency_digest,
        "gitCommit",
        "5453f3afc4785cbad82c05f6ceb4dabea0cb81a0",
        error.WrongWorkflowIdentity,
    );

    const run_details = try jsonField(predicate, "runDetails");
    try rejectUnknownJsonFields(
        run_details,
        &.{ "builder", "metadata" },
        error.UnknownSlsaField,
    );
    const builder = try jsonField(run_details, "builder");
    try rejectUnknownJsonFields(
        builder,
        &.{"id"},
        error.UnknownSlsaField,
    );
    try expectJsonStringField(
        builder,
        "id",
        "https://github.com/bblanchon/pdfium-binaries/.github/workflows/build-all.yml@refs/heads/master",
        error.WrongWorkflowIdentity,
    );
    const metadata = try jsonField(run_details, "metadata");
    try rejectUnknownJsonFields(
        metadata,
        &.{"invocationId"},
        error.UnknownSlsaField,
    );
    try expectJsonStringField(
        metadata,
        "invocationId",
        "https://github.com/bblanchon/pdfium-binaries/actions/runs/33383157207/attempts/1",
        error.WrongWorkflowIdentity,
    );

    return .{
        .subjects = @intCast(subjects.len),
        .matching_subjects = matching,
    };
}

pub fn validateTrustedRootStructure(
    allocator: std.mem.Allocator,
    jsonl: []const u8,
) !void {
    if (jsonl.len == 0 or jsonl.len > 64 * 1024 or jsonl[jsonl.len - 1] != '\n') {
        return error.WrongTrustedRootCount;
    }
    const first_lf = std.mem.indexOfScalar(u8, jsonl, '\n') orelse
        return error.WrongTrustedRootCount;
    const second_lf_relative = std.mem.indexOfScalar(
        u8,
        jsonl[first_lf + 1 ..],
        '\n',
    ) orelse return error.WrongTrustedRootCount;
    const second_lf = first_lf + 1 + second_lf_relative;
    if (second_lf != jsonl.len - 1) return error.WrongTrustedRootCount;
    const first_end = if (first_lf > 0 and jsonl[first_lf - 1] == '\r')
        first_lf - 1
    else
        first_lf;
    const second_start = first_lf + 1;
    const second_end = if (second_lf > second_start and jsonl[second_lf - 1] == '\r')
        second_lf - 1
    else
        second_lf;
    const first = jsonl[0..first_end];
    const second = jsonl[second_start..second_end];
    if (first.len == 0 or second.len == 0) return error.WrongTrustedRootCount;
    if (std.mem.indexOfScalar(u8, first, '\r') != null or
        std.mem.indexOfScalar(u8, second, '\r') != null)
    {
        return error.MalformedTrustedRoot;
    }
    if (std.mem.eql(u8, first, second)) return error.DuplicateTrustedRoot;

    var first_parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        first,
        .{ .duplicate_field_behavior = .@"error" },
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.MalformedTrustedRoot,
    };
    defer first_parsed.deinit();
    var second_parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        second,
        .{ .duplicate_field_behavior = .@"error" },
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.MalformedTrustedRoot,
    };
    defer second_parsed.deinit();
    const media_type = "application/vnd.dev.sigstore.trustedroot+json;version=0.1";
    if (!std.mem.eql(
        u8,
        jsonStringField(first_parsed.value, "mediaType") catch
            return error.WrongTrustedRootMediaType,
        media_type,
    ) or !std.mem.eql(
        u8,
        jsonStringField(second_parsed.value, "mediaType") catch
            return error.WrongTrustedRootMediaType,
        media_type,
    )) return error.WrongTrustedRootMediaType;

    const public_tlogs = jsonArrayField(first_parsed.value, "tlogs") catch
        return error.MissingPublicGoodRoot;
    if (public_tlogs.len != 2 or
        std.mem.indexOf(u8, first, "https://rekor.sigstore.dev") == null)
    {
        return error.MissingPublicGoodRoot;
    }
    const github_cas = jsonArrayField(second_parsed.value, "certificateAuthorities") catch
        return error.MissingGithubRoot;
    const github_tsas = jsonArrayField(second_parsed.value, "timestampAuthorities") catch
        return error.MissingGithubRoot;
    if (github_cas.len != 6 or github_tsas.len != 6) return error.MissingGithubRoot;
}

fn jsonField(value: std.json.Value, name: []const u8) !std.json.Value {
    return switch (value) {
        .object => |object| object.get(name) orelse error.MissingJsonField,
        else => error.WrongJsonType,
    };
}

fn rejectUnknownJsonFields(
    value: std.json.Value,
    comptime allowed_fields: []const []const u8,
    unknown_field_error: anyerror,
) !void {
    const object = switch (value) {
        .object => |object| object,
        else => return error.WrongJsonType,
    };
    for (object.keys()) |actual| {
        var allowed = false;
        inline for (allowed_fields) |expected| {
            if (std.mem.eql(u8, actual, expected)) {
                allowed = true;
                break;
            }
        }
        if (!allowed) return unknown_field_error;
    }
}

fn jsonStringField(value: std.json.Value, name: []const u8) ![]const u8 {
    return switch (try jsonField(value, name)) {
        .string => |string| string,
        else => error.WrongJsonType,
    };
}

fn jsonArrayField(value: std.json.Value, name: []const u8) ![]const std.json.Value {
    return switch (try jsonField(value, name)) {
        .array => |array| array.items,
        else => error.WrongJsonType,
    };
}

fn expectJsonStringField(
    value: std.json.Value,
    name: []const u8,
    expected: []const u8,
    mismatch_error: anyerror,
) !void {
    const actual = jsonStringField(value, name) catch return mismatch_error;
    if (!std.mem.eql(u8, actual, expected)) return mismatch_error;
}

pub fn decodeRawSnappy(
    allocator: std.mem.Allocator,
    input: []const u8,
    max_output_bytes: usize,
) ![]u8 {
    var cursor: usize = 0;
    const advertised_u32 = try readSnappyVarint(input, &cursor);
    const advertised: usize = advertised_u32;
    if (advertised > max_output_bytes) return error.SnappyOutputLimitExceeded;
    const output = try allocator.alloc(u8, advertised);
    errdefer allocator.free(output);
    var output_cursor: usize = 0;

    while (output_cursor < output.len) {
        if (cursor >= input.len) return error.TruncatedSnappyTag;
        const tag = input[cursor];
        cursor += 1;
        switch (tag & 0x03) {
            0 => {
                var length: usize = tag >> 2;
                if (length < 60) {
                    length += 1;
                } else {
                    const encoded_bytes = length - 59;
                    if (encoded_bytes > 4 or input.len - cursor < encoded_bytes) {
                        return error.TruncatedSnappyLiteral;
                    }
                    var encoded_length: u32 = 0;
                    for (input[cursor .. cursor + encoded_bytes], 0..) |byte, index| {
                        encoded_length |= @as(u32, byte) << @intCast(index * 8);
                    }
                    cursor += encoded_bytes;
                    length = std.math.add(
                        usize,
                        @as(usize, encoded_length),
                        1,
                    ) catch return error.SnappyOutputOverflow;
                }
                if (input.len - cursor < length) return error.TruncatedSnappyLiteral;
                if (output.len - output_cursor < length) return error.SnappyOutputOverflow;
                @memcpy(
                    output[output_cursor .. output_cursor + length],
                    input[cursor .. cursor + length],
                );
                cursor += length;
                output_cursor += length;
            },
            1 => {
                if (cursor >= input.len) return error.InvalidSnappyCopy;
                const length: usize = 4 + ((tag >> 2) & 0x07);
                const offset = (@as(usize, tag & 0xe0) << 3) | input[cursor];
                cursor += 1;
                try copySnappy(output, &output_cursor, offset, length);
            },
            2 => {
                if (input.len - cursor < 2) return error.InvalidSnappyCopy;
                const length: usize = 1 + (tag >> 2);
                const offset: usize = std.mem.readInt(
                    u16,
                    input[cursor..][0..2],
                    .little,
                );
                cursor += 2;
                try copySnappy(output, &output_cursor, offset, length);
            },
            3 => {
                if (input.len - cursor < 4) return error.InvalidSnappyCopy;
                const length: usize = 1 + (tag >> 2);
                const offset_u32 = std.mem.readInt(
                    u32,
                    input[cursor..][0..4],
                    .little,
                );
                cursor += 4;
                try copySnappy(output, &output_cursor, offset_u32, length);
            },
            else => unreachable,
        }
    }
    if (cursor != input.len) return error.TrailingSnappyData;
    return output;
}

fn readSnappyVarint(input: []const u8, cursor: *usize) !u32 {
    var value: u32 = 0;
    for (0..5) |index| {
        if (cursor.* >= input.len) return error.TruncatedSnappyVarint;
        const byte = input[cursor.*];
        cursor.* += 1;
        if (index == 4 and byte > 0x0f) return error.OverlongSnappyVarint;
        value |= @as(u32, byte & 0x7f) << @intCast(index * 7);
        if (byte & 0x80 == 0) return value;
    }
    return error.OverlongSnappyVarint;
}

fn copySnappy(
    output: []u8,
    cursor: *usize,
    offset: usize,
    length: usize,
) !void {
    if (offset == 0 or offset > cursor.*) return error.InvalidSnappyCopy;
    if (output.len - cursor.* < length) return error.SnappyOutputOverflow;
    for (0..length) |_| {
        output[cursor.*] = output[cursor.* - offset];
        cursor.* += 1;
    }
}

pub fn validateDependencyGraph(artifacts: []const Artifact) !void {
    const max_artifacts = 64;
    if (artifacts.len > max_artifacts) return error.TooManyArtifacts;

    for (artifacts, 0..) |artifact, index| {
        for (artifacts[index + 1 ..]) |other| {
            if (std.mem.eql(u8, artifact.id, other.id)) return error.DuplicateArtifactId;
        }
    }

    var states = [_]u8{0} ** max_artifacts;
    for (artifacts, 0..) |_, index| {
        try visitDependency(artifacts, states[0..artifacts.len], index);
    }
}

fn visitDependency(artifacts: []const Artifact, states: []u8, index: usize) !void {
    if (states[index] == 2) return;
    if (states[index] == 1) return error.DependencyCycle;
    states[index] = 1;

    for (artifacts[index].dependencies, 0..) |dependency, dependency_index| {
        for (artifacts[index].dependencies[dependency_index + 1 ..]) |other| {
            if (std.mem.eql(u8, dependency, other)) return error.DuplicateDependency;
        }

        var found: ?usize = null;
        for (artifacts, 0..) |candidate, candidate_index| {
            if (std.mem.eql(u8, dependency, candidate.id)) {
                found = candidate_index;
                break;
            }
        }
        try visitDependency(artifacts, states, found orelse return error.UnknownDependency);
    }

    states[index] = 2;
}
