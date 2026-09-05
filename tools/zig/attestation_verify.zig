const std = @import("std");
const builtin = @import("builtin");
const deps = @import("deps");

const gh_version_output =
    "gh version 2.100.0 (2026-09-03)\n" ++
    "https://github.com/cli/cli/releases/tag/v2.100.0\n";
const pdfium_sha256 = "61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41";
const source_digest = "5453f3afc4785cbad82c05f6ceb4dabea0cb81a0";
const workflow_identity =
    "https://github.com/bblanchon/pdfium-binaries/.github/workflows/build-all.yml@refs/heads/master";
const generic_verifier_rejection = "Error: verifying with issuer \"sigstore.dev\"";
const config_sentinel_contents = "locked non-directory config sentinel\n";
const audit_profile_files = [_][]const u8{
    "gh.exe",
    "pdfium.tgz",
    "bundle.jsonl",
    "trusted-root.jsonl",
    "config-sentinel",
    "mutated-pdfium.tgz",
    "mutated-bundle.jsonl",
    "mutated-root.jsonl",
    "github-only-root.jsonl",
};
const VerificationArgIndex = struct {
    const artifact = 3;
    const repository = 5;
    const bundle = 7;
    const trusted_root = 9;
    const certificate_identity = 11;
    const source_ref = 17;
    const source_digest = 19;
    const signer_digest = 21;
};
const rekor_public_key =
    "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE2G2Y+2tabdTV5BcGiBIx0a9fAFwrkBbmLSGtks4L3qX6" ++
    "yYY0zufBnhC8Ur/iy55GhWP/9A/bY2LhC30M9+RYtw==";
const ctlog_public_key =
    "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEbfwR+RJudXscgRBRpKX1XFDy3PyudDxz/SfnRi1fT8ek" ++
    "pfBd2O1uoz7jr3Z8nKzxA69EUQ+eFCFI3zeubPWU7w==";

const Inputs = struct {
    gh: []const u8,
    artifact: []const u8,
    bundle: []const u8,
    trusted_root: []const u8,
};

const HeldSnapshot = struct {
    allocator: std.mem.Allocator,
    gh_path: []u8,
    artifact_path: []u8,
    bundle_path: []u8,
    trusted_root_path: []u8,
    config_sentinel_path: []u8,
    gh_file: std.Io.File,
    artifact_file: std.Io.File,
    bundle_file: std.Io.File,
    trusted_root_file: std.Io.File,
    config_sentinel_file: std.Io.File,

    fn inputs(self: *const HeldSnapshot) Inputs {
        return .{
            .gh = self.gh_path,
            .artifact = self.artifact_path,
            .bundle = self.bundle_path,
            .trusted_root = self.trusted_root_path,
        };
    }

    fn deinit(self: *HeldSnapshot, io: std.Io) void {
        self.config_sentinel_file.close(io);
        self.trusted_root_file.close(io);
        self.bundle_file.close(io);
        self.artifact_file.close(io);
        self.gh_file.close(io);
        self.allocator.free(self.trusted_root_path);
        self.allocator.free(self.bundle_path);
        self.allocator.free(self.artifact_path);
        self.allocator.free(self.gh_path);
        self.allocator.free(self.config_sentinel_path);
    }
};

const PinnedFixture = struct {
    allocator: std.mem.Allocator,
    path: []u8,
    file: std.Io.File,
    sha256: [32]u8,

    fn create(
        allocator: std.mem.Allocator,
        io: std.Io,
        profile_path: []const u8,
        name: []const u8,
        bytes: []const u8,
    ) !PinnedFixture {
        const path = try std.fs.path.join(allocator, &.{ profile_path, name });
        errdefer allocator.free(path);
        const file = try createPinnedPrivateFile(allocator, io, path, bytes);
        errdefer file.close(io);
        var sha256: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &sha256, .{});
        return .{ .allocator = allocator, .path = path, .file = file, .sha256 = sha256 };
    }

    fn verify(self: *const PinnedFixture, allocator: std.mem.Allocator) !void {
        const bytes = try readPinnedFileAlloc(allocator, self.file, 4 * 1024 * 1024);
        defer allocator.free(bytes);
        var actual: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &actual, .{});
        if (!std.mem.eql(u8, &actual, &self.sha256)) return error.AuditFixtureChanged;
    }

    fn deinit(self: *PinnedFixture, io: std.Io) void {
        self.file.close(io);
        self.allocator.free(self.path);
    }
};

const NegativeFixtures = struct {
    mutated_artifact: PinnedFixture,
    mutated_bundle: PinnedFixture,
    mutated_root: PinnedFixture,
    github_only_root: PinnedFixture,

    fn verify(self: *const NegativeFixtures, allocator: std.mem.Allocator) !void {
        try self.mutated_artifact.verify(allocator);
        try self.mutated_bundle.verify(allocator);
        try self.mutated_root.verify(allocator);
        try self.github_only_root.verify(allocator);
    }

    fn deinit(self: *NegativeFixtures, io: std.Io) void {
        self.github_only_root.deinit(io);
        self.mutated_root.deinit(io);
        self.mutated_bundle.deinit(io);
        self.mutated_artifact.deinit(io);
    }
};

const AuditProtocol = struct {
    context: ?*anyopaque = null,
    run_gh: *const fn (
        ?*anyopaque,
        std.mem.Allocator,
        std.Io,
        []const []const u8,
        *const std.process.Environ.Map,
        []const u8,
        usize,
        usize,
    ) anyerror!std.process.RunResult,
    verify_locked_buffers: *const fn (
        ?*anyopaque,
        std.mem.Allocator,
        []const u8,
        []const u8,
        []const u8,
        []const u8,
    ) anyerror!void,
    verify_executable: *const fn (
        ?*anyopaque,
        std.mem.Allocator,
        std.Io,
        []const u8,
        std.Io.File,
    ) anyerror!void,
    validate_result: *const fn (
        ?*anyopaque,
        std.mem.Allocator,
        []const u8,
    ) anyerror!deps.AttestationSummary,
    validate_mutated_root: *const fn (
        ?*anyopaque,
        std.mem.Allocator,
        []const u8,
    ) anyerror!void,
    after_profile_created: *const fn (
        ?*anyopaque,
        std.Io,
        std.Io.Dir,
        std.Io.Dir,
        []const u8,
    ) anyerror!void,
    after_profile_precheck: *const fn (
        ?*anyopaque,
        std.Io,
        std.Io.Dir,
    ) anyerror!void,
};

const production_protocol: AuditProtocol = .{
    .run_gh = productionRunGh,
    .verify_locked_buffers = productionVerifyLockedBuffers,
    .verify_executable = productionVerifyExecutable,
    .validate_result = productionValidateResult,
    .validate_mutated_root = productionValidateMutatedRoot,
    .after_profile_created = productionAfterProfileCreated,
    .after_profile_precheck = productionAfterProfilePrecheck,
};

fn productionRunGh(
    _: ?*anyopaque,
    allocator: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
    environment: *const std.process.Environ.Map,
    cwd: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
) anyerror!std.process.RunResult {
    return runGh(
        allocator,
        io,
        argv,
        environment,
        cwd,
        stdout_limit,
        stderr_limit,
    );
}

fn productionVerifyLockedBuffers(
    _: ?*anyopaque,
    allocator: std.mem.Allocator,
    gh_bytes: []const u8,
    artifact_bytes: []const u8,
    bundle: []const u8,
    trusted_root: []const u8,
) anyerror!void {
    return verifyLockedBuffers(
        allocator,
        gh_bytes,
        artifact_bytes,
        bundle,
        trusted_root,
    );
}

fn productionVerifyExecutable(
    _: ?*anyopaque,
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    file: std.Io.File,
) anyerror!void {
    return verifyGhAuthenticode(allocator, io, path, file);
}

fn productionValidateResult(
    _: ?*anyopaque,
    allocator: std.mem.Allocator,
    result: []const u8,
) anyerror!deps.AttestationSummary {
    return deps.validateGhVerificationResult(allocator, result);
}

fn productionValidateMutatedRoot(
    _: ?*anyopaque,
    allocator: std.mem.Allocator,
    root: []const u8,
) anyerror!void {
    return deps.validateTrustedRootStructure(allocator, root);
}

fn productionAfterProfileCreated(
    _: ?*anyopaque,
    _: std.Io,
    _: std.Io.Dir,
    _: std.Io.Dir,
    _: []const u8,
) anyerror!void {}

fn productionAfterProfilePrecheck(
    _: ?*anyopaque,
    _: std.Io,
    _: std.Io.Dir,
) anyerror!void {}

pub fn main(init: std.process.Init) !void {
    if (builtin.os.tag != .windows) return error.UnsupportedAttestationAuditHost;

    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 7 or !std.mem.eql(u8, args[1], "verify")) {
        return error.InvalidArguments;
    }
    const cache_root_path = args[2];
    const inputs: Inputs = .{
        .gh = args[3],
        .artifact = args[4],
        .bundle = args[5],
        .trusted_root = args[6],
    };
    try verifyAbsolutePath(cache_root_path);
    try verifyAbsoluteInputs(inputs);

    const temp_parent_path = try auditTempParent(init.environ_map);
    var temp_parent = try std.Io.Dir.openDirAbsolute(init.io, temp_parent_path, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer temp_parent.close(init.io);
    if ((try temp_parent.stat(init.io)).kind != .directory) {
        return error.InvalidAuditTemp;
    }
    var random_bytes: [12]u8 = undefined;
    init.io.random(&random_bytes);
    const random_hex = std.fmt.bytesToHex(random_bytes, .lower);
    var profile_name_buffer: [64]u8 = undefined;
    const profile_name = try std.fmt.bufPrint(
        &profile_name_buffer,
        ".attestation-audit-{s}",
        .{random_hex},
    );
    try validateAuditWorkspaceDisjoint(
        allocator,
        init.io,
        temp_parent,
        profile_name,
        cache_root_path,
        inputs,
    );
    const summary = try runAuditWithProfile(
        allocator,
        init.io,
        init.environ_map,
        inputs,
        temp_parent,
        profile_name,
        &production_protocol,
    );
    std.debug.print(
        "attestation-audit verified subjects={d} matching={d} cli=2.100.0 negative=10 " ++
            "network-isolation=unverified proxy=loopback-poisoned\n",
        .{ summary.subjects, summary.matching_subjects },
    );
}

fn runAuditWithProfile(
    allocator: std.mem.Allocator,
    io: std.Io,
    parent_environment: *const std.process.Environ.Map,
    inputs: Inputs,
    temp_parent: std.Io.Dir,
    profile_name: []const u8,
    protocol: *const AuditProtocol,
) !deps.AttestationSummary {
    var profile = try createPrivateDirectory(
        allocator,
        io,
        temp_parent,
        profile_name,
    );
    var profile_open = true;
    defer if (profile_open) profile.close(io);
    var audit_error: ?anyerror = null;
    var summary: ?deps.AttestationSummary = null;
    protocol.after_profile_created(
        protocol.context,
        io,
        temp_parent,
        profile,
        profile_name,
    ) catch |err| {
        audit_error = err;
    };
    if (audit_error == null) {
        summary = runProfileAudit(
            allocator,
            io,
            parent_environment,
            inputs,
            profile,
            protocol,
        ) catch |err| failed: {
            audit_error = err;
            break :failed null;
        };
    }
    profile.close(io);
    profile_open = false;
    temp_parent.deleteTree(io, profile_name) catch
        return error.AuditTempCleanupFailed;
    if (temp_parent.openDir(io, profile_name, .{
        .iterate = true,
        .follow_symlinks = false,
    })) |leftover| {
        leftover.close(io);
        return error.AuditTempCleanupFailed;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return error.AuditTempCleanupFailed,
    }
    if (audit_error) |err| return err;
    return summary.?;
}

fn runProfileAudit(
    allocator: std.mem.Allocator,
    io: std.Io,
    parent_environment: *const std.process.Environ.Map,
    inputs: Inputs,
    profile: std.Io.Dir,
    protocol: *const AuditProtocol,
) !deps.AttestationSummary {
    var advapi = try Advapi32.open();
    defer advapi.close();
    var cleanup_security = try OwnerSecurity.init(allocator, &advapi, .directory_full);
    defer cleanup_security.deinit();
    var audit_error: ?anyerror = null;
    const summary = runProfileAuditInner(
        allocator,
        io,
        parent_environment,
        inputs,
        profile,
        protocol,
    ) catch |err| failed: {
        audit_error = err;
        break :failed null;
    };
    try applyOwnerSecurity(
        &advapi,
        profile.handle,
        &cleanup_security,
        0x03,
        file_all_access,
    );
    if (audit_error) |err| return err;
    return summary.?;
}

fn runProfileAuditInner(
    allocator: std.mem.Allocator,
    io: std.Io,
    parent_environment: *const std.process.Environ.Map,
    inputs: Inputs,
    profile: std.Io.Dir,
    protocol: *const AuditProtocol,
) !deps.AttestationSummary {
    if ((try profile.stat(io)).kind != .directory) {
        return error.InvalidAuditProfile;
    }
    var profile_iterator = profile.iterate();
    if (try profile_iterator.next(io) != null) return error.AuditProfileNotEmpty;
    const profile_path = try profile.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(profile_path);
    var snapshot = try createHeldSnapshot(
        allocator,
        io,
        inputs,
        profile_path,
        protocol,
    );
    defer snapshot.deinit(io);
    const verified_inputs = snapshot.inputs();

    try protocol.verify_executable(
        protocol.context,
        allocator,
        io,
        snapshot.gh_path,
        snapshot.gh_file,
    );
    var negative_fixtures = try prepareNegativeFixtures(
        allocator,
        io,
        &snapshot,
        profile_path,
        protocol,
    );
    defer negative_fixtures.deinit(io);
    try freezePrivateDirectory(allocator, profile.handle);
    try verifyAuditProfileLayout(io, profile);
    try protocol.after_profile_precheck(protocol.context, io, profile);
    try verifyAuditProfileLayout(io, profile);

    var environment = try scrubbedEnvironment(
        allocator,
        parent_environment,
        snapshot.config_sentinel_path,
    );
    defer environment.deinit();

    const version = try protocol.run_gh(
        protocol.context,
        allocator,
        io,
        &.{ verified_inputs.gh, "version" },
        &environment,
        profile_path,
        4 * 1024,
        4 * 1024,
    );
    defer allocator.free(version.stdout);
    defer allocator.free(version.stderr);
    try requireSuccessful(version.term, error.GhVersionFailed);
    try validateGhVersion(version.stdout, version.stderr);

    const verify_argv = verificationArgs(verified_inputs);
    const result = try protocol.run_gh(
        protocol.context,
        allocator,
        io,
        &verify_argv,
        &environment,
        profile_path,
        256 * 1024,
        64 * 1024,
    );
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try requireSuccessful(result.term, error.GhVerificationFailed);
    if (result.stderr.len != 0) return error.UnexpectedGhStderr;
    const summary = try protocol.validate_result(
        protocol.context,
        allocator,
        result.stdout,
    );
    try runNegativeMatrix(
        allocator,
        io,
        verified_inputs,
        &negative_fixtures,
        profile_path,
        &environment,
        protocol,
    );
    try verifyHeldSnapshot(allocator, io, &snapshot, protocol);
    try negative_fixtures.verify(allocator);
    try verifyAuditProfileLayout(io, profile);
    return summary;
}

fn validateGhVersion(stdout: []const u8, stderr: []const u8) !void {
    if (stderr.len != 0 or !std.mem.eql(u8, stdout, gh_version_output)) {
        return error.WrongGhVersion;
    }
}

fn prepareNegativeFixtures(
    allocator: std.mem.Allocator,
    io: std.Io,
    snapshot: *const HeldSnapshot,
    profile_path: []const u8,
    protocol: *const AuditProtocol,
) !NegativeFixtures {
    const artifact = try readPinnedFileAlloc(allocator, snapshot.artifact_file, 3_772_598);
    defer allocator.free(artifact);
    const mutated_artifact = try allocator.dupe(u8, artifact);
    defer allocator.free(mutated_artifact);
    mutated_artifact[mutated_artifact.len / 2] ^= 1;
    var mutated_artifact_fixture = try PinnedFixture.create(
        allocator,
        io,
        profile_path,
        "mutated-pdfium.tgz",
        mutated_artifact,
    );
    errdefer mutated_artifact_fixture.deinit(io);

    const bundle = try readPinnedFileAlloc(
        allocator,
        snapshot.bundle_file,
        deps.locked_pdfium_attestation_bytes.len + 1,
    );
    defer allocator.free(bundle);
    const mutated_bundle = try allocator.dupe(u8, bundle);
    defer allocator.free(mutated_bundle);
    const signature = std.mem.indexOf(u8, mutated_bundle, "\"sig\":\"") orelse
        return error.InvalidAttestationBundle;
    mutated_bundle[signature + "\"sig\":\"".len] = if (mutated_bundle[signature + "\"sig\":\"".len] == 'A') 'B' else 'A';
    var mutated_bundle_fixture = try PinnedFixture.create(
        allocator,
        io,
        profile_path,
        "mutated-bundle.jsonl",
        mutated_bundle,
    );
    errdefer mutated_bundle_fixture.deinit(io);

    const root = try readPinnedFileAlloc(
        allocator,
        snapshot.trusted_root_file,
        deps.locked_github_trusted_root_bytes.len + 1,
    );
    defer allocator.free(root);
    const mutated_root = try mutateTrustedRootPublicKey(allocator, root);
    defer allocator.free(mutated_root);
    try protocol.validate_mutated_root(protocol.context, allocator, mutated_root);
    var mutated_root_fixture = try PinnedFixture.create(
        allocator,
        io,
        profile_path,
        "mutated-root.jsonl",
        mutated_root,
    );
    errdefer mutated_root_fixture.deinit(io);
    const first_lf = std.mem.indexOfScalar(u8, root, '\n') orelse
        return error.InvalidTrustedRoot;
    var github_only_root_fixture = try PinnedFixture.create(
        allocator,
        io,
        profile_path,
        "github-only-root.jsonl",
        root[first_lf + 1 ..],
    );
    errdefer github_only_root_fixture.deinit(io);
    return .{
        .mutated_artifact = mutated_artifact_fixture,
        .mutated_bundle = mutated_bundle_fixture,
        .mutated_root = mutated_root_fixture,
        .github_only_root = github_only_root_fixture,
    };
}

fn verifyAuditProfileLayout(io: std.Io, profile: std.Io.Dir) !void {
    var seen = [_]bool{false} ** audit_profile_files.len;
    var iterator = profile.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file) return error.UnexpectedAuditProfileEntry;
        var matched = false;
        for (audit_profile_files, 0..) |name, index| {
            if (!std.mem.eql(u8, entry.name, name)) continue;
            if (seen[index]) return error.UnexpectedAuditProfileEntry;
            seen[index] = true;
            matched = true;
            break;
        }
        if (!matched) return error.UnexpectedAuditProfileEntry;
    }
    for (seen) |present| {
        if (!present) return error.MissingAuditProfileEntry;
    }
}

fn runNegativeMatrix(
    allocator: std.mem.Allocator,
    io: std.Io,
    inputs: Inputs,
    fixtures: *const NegativeFixtures,
    profile_path: []const u8,
    environment: *const std.process.Environ.Map,
    protocol: *const AuditProtocol,
) !void {
    var negative = verificationArgs(inputs);
    negative[VerificationArgIndex.artifact] = fixtures.mutated_artifact.path;
    try expectGhFailure(
        allocator,
        io,
        &negative,
        environment,
        profile_path,
        generic_verifier_rejection,
        error.MutatedArtifactAccepted,
        protocol,
    );
    negative = verificationArgs(inputs);
    negative[VerificationArgIndex.bundle] = fixtures.mutated_bundle.path;
    try expectGhFailure(allocator, io, &negative, environment, profile_path, generic_verifier_rejection, error.MutatedBundleAccepted, protocol);
    negative = verificationArgs(inputs);
    negative[VerificationArgIndex.trusted_root] = fixtures.mutated_root.path;
    try expectGhFailure(allocator, io, &negative, environment, profile_path, generic_verifier_rejection, error.ModifiedRootAccepted, protocol);
    negative = verificationArgs(inputs);
    negative[VerificationArgIndex.trusted_root] = fixtures.github_only_root.path;
    try expectGhFailure(
        allocator,
        io,
        &negative,
        environment,
        profile_path,
        "no custom verifier found for issuer \"sigstore.dev\"",
        error.MissingPublicRootAccepted,
        protocol,
    );
    negative = verificationArgs(inputs);
    negative[VerificationArgIndex.certificate_identity] =
        "https://github.com/bblanchon/pdfium-binaries/.github/workflows/build-all.yml@refs/heads/main";
    try expectGhFailure(allocator, io, &negative, environment, profile_path, generic_verifier_rejection, error.LookalikeIdentityAccepted, protocol);
    negative = verificationArgs(inputs);
    negative[VerificationArgIndex.repository] = "bblanchon/pdfium-binariez";
    try expectGhFailure(
        allocator,
        io,
        &negative,
        environment,
        profile_path,
        "expected SourceRepositoryURI to be https://github.com/bblanchon/pdfium-binariez",
        error.WrongRepositoryAccepted,
        protocol,
    );
    negative = verificationArgs(inputs);
    negative[VerificationArgIndex.source_ref] = "refs/heads/main";
    try expectGhFailure(
        allocator,
        io,
        &negative,
        environment,
        profile_path,
        "expected SourceRepositoryRef to be refs/heads/main",
        error.WrongSourceRefAccepted,
        protocol,
    );
    negative = verificationArgs(inputs);
    negative[VerificationArgIndex.source_digest] = "6453f3afc4785cbad82c05f6ceb4dabea0cb81a0";
    try expectGhFailure(
        allocator,
        io,
        &negative,
        environment,
        profile_path,
        "expected SourceRepositoryDigest to be 6453f3afc4785cbad82c05f6ceb4dabea0cb81a0",
        error.WrongSourceDigestAccepted,
        protocol,
    );
    negative = verificationArgs(inputs);
    negative[VerificationArgIndex.signer_digest] = "6453f3afc4785cbad82c05f6ceb4dabea0cb81a0";
    try expectGhFailure(
        allocator,
        io,
        &negative,
        environment,
        profile_path,
        "expected BuildSignerDigest to be 6453f3afc4785cbad82c05f6ceb4dabea0cb81a0",
        error.WrongSignerDigestAccepted,
        protocol,
    );

    const baseline = verificationArgs(inputs);
    var contradictory: [27][]const u8 = undefined;
    @memcpy(contradictory[0..baseline.len], &baseline);
    contradictory[25] = "--cert-identity-regex";
    contradictory[26] = ".*";
    try expectGhFailure(
        allocator,
        io,
        &contradictory,
        environment,
        profile_path,
        "if any flags in the group [cert-identity cert-identity-regex signer-repo signer-workflow]",
        error.ContradictoryIdentityAccepted,
        protocol,
    );
}

fn mutateTrustedRootPublicKey(allocator: std.mem.Allocator, root: []const u8) ![]u8 {
    comptime {
        if (rekor_public_key.len != ctlog_public_key.len) @compileError("trusted-root keys must have equal encoding lengths");
    }

    const offset = std.mem.indexOf(u8, root, rekor_public_key) orelse
        return error.InvalidTrustedRoot;
    if (std.mem.indexOf(u8, root[offset + rekor_public_key.len ..], rekor_public_key) != null or
        std.mem.indexOf(u8, root, ctlog_public_key) == null)
    {
        return error.InvalidTrustedRoot;
    }
    const mutated = try allocator.dupe(u8, root);
    @memcpy(mutated[offset..][0..ctlog_public_key.len], ctlog_public_key);
    return mutated;
}

fn writePrivateFile(io: std.Io, dir: std.Io.Dir, name: []const u8, bytes: []const u8) !void {
    try dir.writeFile(io, .{
        .sub_path = name,
        .data = bytes,
        .flags = .{
            .exclusive = true,
            .permissions = privateFilePermissions(),
            .resolve_beneath = true,
        },
    });
}

fn expectGhFailure(
    allocator: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
    environment: *const std.process.Environ.Map,
    cwd: []const u8,
    expected_stderr: []const u8,
    accepted_error: anyerror,
    protocol: *const AuditProtocol,
) !void {
    const result = try protocol.run_gh(
        protocol.context,
        allocator,
        io,
        argv,
        environment,
        cwd,
        64 * 1024,
        64 * 1024,
    );
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try requireGhRejection(
        result.term,
        result.stdout,
        result.stderr,
        expected_stderr,
        accepted_error,
    );
}

fn requireGhRejection(
    term: std.process.Child.Term,
    stdout: []const u8,
    stderr: []const u8,
    expected_stderr: []const u8,
    accepted_error: anyerror,
) !void {
    switch (term) {
        .exited => |code| switch (code) {
            0 => return accepted_error,
            1 => {
                if (stdout.len != 0 or expected_stderr.len == 0 or
                    std.mem.indexOf(u8, stderr, expected_stderr) == null)
                {
                    return error.UnexpectedGhRejection;
                }
            },
            else => return error.UnexpectedGhFailureStatus,
        },
        else => return error.UnexpectedGhTermination,
    }
}

fn verifyAbsoluteInputs(inputs: Inputs) !void {
    inline for (.{ inputs.gh, inputs.artifact, inputs.bundle, inputs.trusted_root }) |path| {
        try verifyAbsolutePath(path);
    }
}

fn verifyAbsolutePath(path: []const u8) !void {
    if (!std.fs.path.isAbsolute(path) or std.mem.indexOfScalar(u8, path, 0) != null or
        std.mem.indexOfAny(u8, path, "\r\n") != null)
    {
        return error.NonAbsoluteAuditInput;
    }
}

fn auditTempParent(parent: *const std.process.Environ.Map) ![]const u8 {
    const path = parent.get("TEMP") orelse return error.MissingAuditTemp;
    if (!isLocalDriveAbsolute(path) or std.mem.indexOfScalar(u8, path, 0) != null or
        std.mem.indexOfAny(u8, path, "\r\n") != null)
    {
        return error.InvalidAuditTemp;
    }
    return path;
}

fn isLocalDriveAbsolute(path: []const u8) bool {
    return path.len >= 3 and std.ascii.isAlphabetic(path[0]) and path[1] == ':' and
        (path[2] == '\\' or path[2] == '/');
}

fn samePathByte(a: u8, b: u8) bool {
    if ((a == '\\' or a == '/') and (b == '\\' or b == '/')) return true;
    return std.ascii.toLower(a) == std.ascii.toLower(b);
}

fn trimPathSeparators(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 3 and (path[end - 1] == '\\' or path[end - 1] == '/')) end -= 1;
    return path[0..end];
}

fn pathContains(ancestor_raw: []const u8, candidate_raw: []const u8) bool {
    const ancestor = trimPathSeparators(ancestor_raw);
    const candidate = trimPathSeparators(candidate_raw);
    if (ancestor.len > candidate.len) return false;
    for (ancestor, candidate[0..ancestor.len]) |a, b| {
        if (!samePathByte(a, b)) return false;
    }
    return ancestor.len == candidate.len or candidate[ancestor.len] == '\\' or
        candidate[ancestor.len] == '/';
}

fn pathsOverlap(a: []const u8, b: []const u8) bool {
    return pathContains(a, b) or pathContains(b, a);
}

fn validateAuditProfileName(name: []const u8) !void {
    if (name.len == 0 or std.mem.indexOfAny(u8, name, "\\/:\x00\r\n") != null or
        name[name.len - 1] == '.' or name[name.len - 1] == ' ')
    {
        return error.InvalidAuditProfile;
    }
}

fn validateAuditWorkspaceDisjoint(
    allocator: std.mem.Allocator,
    io: std.Io,
    temp_parent: std.Io.Dir,
    profile_name: []const u8,
    cache_root_path: []const u8,
    inputs: Inputs,
) !void {
    try validateAuditProfileName(profile_name);
    const temp_real = try temp_parent.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(temp_real);
    // The candidate does not exist yet. Its parent is canonical, and creation
    // uses this same held parent plus a single basename with CREATE and
    // DONT_REPARSE. A collision fails before the audit can write any inputs.
    const profile_path = try std.fs.path.join(allocator, &.{ temp_real, profile_name });
    defer allocator.free(profile_path);
    const cache_root = try std.Io.Dir.realPathFileAbsoluteAlloc(
        io,
        cache_root_path,
        allocator,
    );
    defer allocator.free(cache_root);
    const gh_real = try std.Io.Dir.realPathFileAbsoluteAlloc(io, inputs.gh, allocator);
    defer allocator.free(gh_real);
    const artifact_real = try std.Io.Dir.realPathFileAbsoluteAlloc(io, inputs.artifact, allocator);
    defer allocator.free(artifact_real);
    const bundle_real = try std.Io.Dir.realPathFileAbsoluteAlloc(io, inputs.bundle, allocator);
    defer allocator.free(bundle_real);
    const root_real = try std.Io.Dir.realPathFileAbsoluteAlloc(io, inputs.trusted_root, allocator);
    defer allocator.free(root_real);

    if (!pathContains(cache_root, artifact_real) or !pathContains(cache_root, gh_real)) {
        return error.InvalidCacheLayout;
    }
    if (pathsOverlap(profile_path, cache_root) or pathsOverlap(profile_path, bundle_real) or
        pathsOverlap(profile_path, root_real))
    {
        return error.AuditTempOverlapsLockedInput;
    }
}

fn readNoFollowFileAlloc(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    limit: u64,
) ![]u8 {
    if (builtin.os.tag == .windows) {
        var pinned = try openPinnedFile(allocator, io, path);
        defer pinned.close(io);
        return readPinnedFileAlloc(allocator, pinned, limit);
    }
    var file = try std.Io.Dir.cwd().openFile(io, path, .{
        .allow_directory = false,
        .follow_symlinks = false,
    });
    defer file.close(io);
    return readIoFileAlloc(allocator, io, file, limit);
}

fn readIoFileAlloc(
    allocator: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    limit: u64,
) ![]u8 {
    const stat = try file.stat(io);
    if (stat.kind != .file or stat.size > limit) return error.InvalidAuditInput;
    const size = std.math.cast(usize, stat.size) orelse return error.InvalidAuditInput;
    const bytes = try allocator.alloc(u8, size);
    errdefer allocator.free(bytes);
    if (try file.readPositionalAll(io, bytes, 0) != size) return error.AuditInputChanged;
    const after = try file.stat(io);
    if (after.kind != .file or after.size != stat.size or after.inode != stat.inode) {
        return error.AuditInputChanged;
    }
    return bytes;
}

fn readPinnedFileAlloc(
    allocator: std.mem.Allocator,
    file: std.Io.File,
    limit: u64,
) ![]u8 {
    var file_size: i64 = 0;
    if (GetFileSizeEx(file.handle, &file_size) == 0 or file_size < 0 or
        @as(u64, @intCast(file_size)) > limit)
    {
        return error.InvalidAuditInput;
    }
    if (SetFilePointerEx(file.handle, 0, null, file_begin) == 0) {
        return error.AuditInputReadFailed;
    }
    const size = std.math.cast(usize, file_size) orelse return error.InvalidAuditInput;
    const bytes = try allocator.alloc(u8, size);
    errdefer allocator.free(bytes);
    var offset: usize = 0;
    while (offset < bytes.len) {
        const chunk_size: u32 = @intCast(@min(bytes.len - offset, std.math.maxInt(u32)));
        var read: u32 = 0;
        if (ReadFile(file.handle, bytes[offset..].ptr, chunk_size, &read, null) == 0) {
            return error.AuditInputReadFailed;
        }
        if (read == 0) return error.AuditInputChanged;
        offset += read;
    }
    var final_size: i64 = 0;
    if (GetFileSizeEx(file.handle, &final_size) == 0 or final_size != file_size) {
        return error.AuditInputChanged;
    }
    return bytes;
}

fn verifyLockedBuffers(
    allocator: std.mem.Allocator,
    gh_bytes: []const u8,
    artifact_bytes: []const u8,
    bundle: []const u8,
    trusted_root: []const u8,
) !void {
    try deps.verifySha256(
        gh_bytes,
        "2ae2b350c227a618f2d8965b1900aeee13446ff42e17ef0bd5a0b6405c593cfb",
    );
    try deps.verifySha256(artifact_bytes, pdfium_sha256);
    if (!std.mem.eql(u8, bundle, deps.locked_pdfium_attestation_bytes)) {
        return error.EvidenceDigestMismatch;
    }
    if (!std.mem.eql(u8, trusted_root, deps.locked_github_trusted_root_bytes)) {
        return error.EvidenceDigestMismatch;
    }
    _ = try deps.validatePdfiumEvidence(allocator, bundle, trusted_root);
}

fn createHeldSnapshot(
    allocator: std.mem.Allocator,
    io: std.Io,
    inputs: Inputs,
    profile_path: []const u8,
    protocol: *const AuditProtocol,
) !HeldSnapshot {
    const gh_bytes = try readNoFollowFileAlloc(allocator, io, inputs.gh, 42_992_953);
    defer allocator.free(gh_bytes);
    const artifact_bytes = try readNoFollowFileAlloc(allocator, io, inputs.artifact, 3_772_598);
    defer allocator.free(artifact_bytes);
    const bundle = try readNoFollowFileAlloc(
        allocator,
        io,
        inputs.bundle,
        deps.locked_pdfium_attestation_bytes.len + 1,
    );
    defer allocator.free(bundle);
    const trusted_root = try readNoFollowFileAlloc(
        allocator,
        io,
        inputs.trusted_root,
        deps.locked_github_trusted_root_bytes.len + 1,
    );
    defer allocator.free(trusted_root);
    try protocol.verify_locked_buffers(
        protocol.context,
        allocator,
        gh_bytes,
        artifact_bytes,
        bundle,
        trusted_root,
    );

    const gh_path = try std.fs.path.join(allocator, &.{ profile_path, "gh.exe" });
    errdefer allocator.free(gh_path);
    const artifact_path = try std.fs.path.join(allocator, &.{ profile_path, "pdfium.tgz" });
    errdefer allocator.free(artifact_path);
    const bundle_path = try std.fs.path.join(allocator, &.{ profile_path, "bundle.jsonl" });
    errdefer allocator.free(bundle_path);
    const trusted_root_path = try std.fs.path.join(allocator, &.{ profile_path, "trusted-root.jsonl" });
    errdefer allocator.free(trusted_root_path);
    const config_sentinel_path = try std.fs.path.join(
        allocator,
        &.{ profile_path, "config-sentinel" },
    );
    errdefer allocator.free(config_sentinel_path);

    const gh_file = try createPinnedPrivateFile(allocator, io, gh_path, gh_bytes);
    errdefer gh_file.close(io);
    const artifact_file = try createPinnedPrivateFile(
        allocator,
        io,
        artifact_path,
        artifact_bytes,
    );
    errdefer artifact_file.close(io);
    const bundle_file = try createPinnedPrivateFile(allocator, io, bundle_path, bundle);
    errdefer bundle_file.close(io);
    const trusted_root_file = try createPinnedPrivateFile(
        allocator,
        io,
        trusted_root_path,
        trusted_root,
    );
    errdefer trusted_root_file.close(io);
    const config_sentinel_file = try createPinnedPrivateFile(
        allocator,
        io,
        config_sentinel_path,
        config_sentinel_contents,
    );
    errdefer config_sentinel_file.close(io);

    var snapshot: HeldSnapshot = .{
        .allocator = allocator,
        .gh_path = gh_path,
        .artifact_path = artifact_path,
        .bundle_path = bundle_path,
        .trusted_root_path = trusted_root_path,
        .config_sentinel_path = config_sentinel_path,
        .gh_file = gh_file,
        .artifact_file = artifact_file,
        .bundle_file = bundle_file,
        .trusted_root_file = trusted_root_file,
        .config_sentinel_file = config_sentinel_file,
    };
    try verifyHeldSnapshot(allocator, io, &snapshot, protocol);
    return snapshot;
}

fn verifyHeldSnapshot(
    allocator: std.mem.Allocator,
    io: std.Io,
    snapshot: *const HeldSnapshot,
    protocol: *const AuditProtocol,
) !void {
    _ = io;
    const gh_bytes = try readPinnedFileAlloc(allocator, snapshot.gh_file, 42_992_953);
    defer allocator.free(gh_bytes);
    const artifact_bytes = try readPinnedFileAlloc(allocator, snapshot.artifact_file, 3_772_598);
    defer allocator.free(artifact_bytes);
    const bundle = try readPinnedFileAlloc(
        allocator,
        snapshot.bundle_file,
        deps.locked_pdfium_attestation_bytes.len + 1,
    );
    defer allocator.free(bundle);
    const trusted_root = try readPinnedFileAlloc(
        allocator,
        snapshot.trusted_root_file,
        deps.locked_github_trusted_root_bytes.len + 1,
    );
    defer allocator.free(trusted_root);
    const config_sentinel = try readPinnedFileAlloc(
        allocator,
        snapshot.config_sentinel_file,
        config_sentinel_contents.len,
    );
    defer allocator.free(config_sentinel);
    if (!std.mem.eql(u8, config_sentinel, config_sentinel_contents)) {
        return error.AuditConfigSentinelChanged;
    }
    try protocol.verify_locked_buffers(
        protocol.context,
        allocator,
        gh_bytes,
        artifact_bytes,
        bundle,
        trusted_root,
    );
}

fn verificationArgs(inputs: Inputs) [25][]const u8 {
    return .{
        inputs.gh,
        "attestation",
        "verify",
        inputs.artifact,
        "--repo",
        "bblanchon/pdfium-binaries",
        "--bundle",
        inputs.bundle,
        "--custom-trusted-root",
        inputs.trusted_root,
        "--cert-identity",
        workflow_identity,
        "--cert-oidc-issuer",
        "https://token.actions.githubusercontent.com",
        "--predicate-type",
        "https://slsa.dev/provenance/v1",
        "--source-ref",
        "refs/heads/master",
        "--source-digest",
        source_digest,
        "--signer-digest",
        source_digest,
        "--deny-self-hosted-runners",
        "--format",
        "json",
    };
}

fn scrubbedEnvironment(
    allocator: std.mem.Allocator,
    parent: *const std.process.Environ.Map,
    config_sentinel_path: []const u8,
) !std.process.Environ.Map {
    var environment = std.process.Environ.Map.init(allocator);
    errdefer environment.deinit();
    const system_root = parent.get("SystemRoot") orelse return error.MissingSystemRoot;
    if (!std.fs.path.isAbsolute(system_root)) return error.InvalidSystemRoot;
    try environment.put("SystemRoot", system_root);
    try environment.put("WINDIR", system_root);
    try environment.put("HOME", config_sentinel_path);
    try environment.put("USERPROFILE", config_sentinel_path);
    try environment.put("APPDATA", config_sentinel_path);
    try environment.put("LOCALAPPDATA", config_sentinel_path);
    try environment.put("XDG_CONFIG_HOME", config_sentinel_path);
    try environment.put("XDG_CACHE_HOME", config_sentinel_path);
    try environment.put("TEMP", config_sentinel_path);
    try environment.put("TMP", config_sentinel_path);
    try environment.put("GH_CONFIG_DIR", config_sentinel_path);
    try environment.put("GH_PROMPT_DISABLED", "1");
    try environment.put("GH_NO_UPDATE_NOTIFIER", "1");
    try environment.put("GIT_TERMINAL_PROMPT", "0");
    try environment.put("GIT_CONFIG_NOSYSTEM", "1");
    try environment.put("GIT_CONFIG_GLOBAL", "NUL");
    try environment.put("HTTP_PROXY", "http://127.0.0.1:9");
    try environment.put("HTTPS_PROXY", "http://127.0.0.1:9");
    try environment.put("ALL_PROXY", "http://127.0.0.1:9");
    try environment.put("NO_PROXY", "");
    return environment;
}

fn runGh(
    allocator: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
    environment: *const std.process.Environ.Map,
    cwd: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
) !std.process.RunResult {
    return std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .environ_map = environment,
        .stdout_limit = .limited(stdout_limit),
        .stderr_limit = .limited(stderr_limit),
        .timeout = .{ .duration = .{
            .clock = .awake,
            .raw = .fromSeconds(30),
        } },
        .create_no_window = true,
    });
}

fn openPinnedFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !std.Io.File {
    const path_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, path);
    defer allocator.free(path_w);
    const handle = CreateFileW(
        path_w.ptr,
        generic_read,
        file_share_read,
        null,
        open_existing,
        file_attribute_normal | file_flag_open_reparse_point,
        null,
    );
    if (handle == std.os.windows.INVALID_HANDLE_VALUE) return error.AuditInputPinFailed;
    const file: std.Io.File = .{ .handle = handle, .flags = .{ .nonblocking = false } };
    errdefer file.close(io);
    if ((try file.stat(io)).kind != .file) return error.InvalidAuditInput;
    return file;
}

fn openPinnedDirectory(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !std.Io.Dir {
    const path_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, path);
    defer allocator.free(path_w);
    const handle = CreateFileW(
        path_w.ptr,
        generic_read,
        file_share_read,
        null,
        open_existing,
        file_flag_backup_semantics | file_flag_open_reparse_point,
        null,
    );
    if (handle == std.os.windows.INVALID_HANDLE_VALUE) return error.AuditProfilePinFailed;
    const dir: std.Io.Dir = .{ .handle = handle };
    errdefer dir.close(io);
    if ((try dir.stat(io)).kind != .directory) return error.InvalidAuditProfile;
    return dir;
}

fn requireSuccessful(term: std.process.Child.Term, failure: anyerror) !void {
    switch (term) {
        .exited => |code| if (code != 0) return failure,
        else => return failure,
    }
}

fn privateDirPermissions() std.Io.Dir.Permissions {
    return if (builtin.os.tag == .windows) .default_dir else .fromMode(0o700);
}

fn privateFilePermissions() std.Io.Dir.Permissions {
    return if (builtin.os.tag == .windows) .default_file else .fromMode(0o600);
}

const dacl_security_information: u32 = 0x0000_0004;
const owner_security_information: u32 = 0x0000_0001;
const protected_dacl_security_information: u32 = 0x8000_0000;
const load_library_search_system32: u32 = 0x0000_0800;
const file_all_access: u32 = 0x001f_01ff;
const generic_read: u32 = 0x8000_0000;
const generic_write: u32 = 0x4000_0000;
const read_control: u32 = 0x0002_0000;
const write_dac: u32 = 0x0004_0000;
const write_owner: u32 = 0x0008_0000;
const file_generic_read_execute: u32 = 0x0012_00a9;
const file_share_read: u32 = 0x0000_0001;
const file_share_write: u32 = 0x0000_0002;
const file_share_delete: u32 = 0x0000_0004;
const open_existing: u32 = 3;
const create_new: u32 = 1;
const file_attribute_normal: u32 = 0x0000_0080;
const file_flag_backup_semantics: u32 = 0x0200_0000;
const file_flag_open_reparse_point: u32 = 0x0020_0000;
const file_begin: u32 = 0;
const wtd_ui_none: u32 = 2;
const wtd_revoke_none: u32 = 0;
const wtd_choice_file: u32 = 1;
const wtd_stateaction_verify: u32 = 1;
const wtd_stateaction_close: u32 = 2;
const wtd_cache_only_url_retrieval: u32 = 0x0000_1000;
const wtd_revocation_check_none: u32 = 0x0000_0010;
const cert_name_rdn_type: u32 = 2;
const cert_x500_name_str: u32 = 3;
const cert_name_str_reverse_flag: u32 = 0x0200_0000;
const gh_authenticode_subject =
    "CN=\"GitHub, Inc.\", O=\"GitHub, Inc.\", L=San Francisco, S=California, C=US";
const gh_authenticode_thumbprint_sha1 = "2E3D67018EE2980D0C7910A24BB60E195E7068F2";

const WintrustFileInfo = extern struct {
    cb_struct: u32,
    file_path: [*:0]const u16,
    file: ?std.os.windows.HANDLE,
    known_subject: ?*const std.os.windows.GUID,
};

const WintrustData = extern struct {
    cb_struct: u32,
    policy_callback_data: ?*anyopaque,
    sip_client_data: ?*anyopaque,
    ui_choice: u32,
    revocation_checks: u32,
    union_choice: u32,
    file_info: *WintrustFileInfo,
    state_action: u32,
    state_data: ?std.os.windows.HANDLE,
    url_reference: ?[*:0]u16,
    provider_flags: u32,
    ui_context: u32,
    signature_settings: ?*anyopaque,
};

const CertificateContext = extern struct {
    encoding_type: u32,
    encoded: ?[*]const u8,
    encoded_len: u32,
    cert_info: ?*anyopaque,
    cert_store: ?std.os.windows.HANDLE,
};

const CryptProviderData = opaque {};
const CryptProviderSigner = opaque {};
const CryptProviderCertificate = extern struct {
    cb_struct: u32,
    certificate: ?*const CertificateContext,
};

const WinVerifyTrust = *const fn (
    ?std.os.windows.HANDLE,
    *const std.os.windows.GUID,
    *WintrustData,
) callconv(.winapi) i32;
const WtHelperProvDataFromStateData = *const fn (
    std.os.windows.HANDLE,
) callconv(.winapi) ?*CryptProviderData;
const WtHelperGetProvSignerFromChain = *const fn (
    *CryptProviderData,
    u32,
    i32,
    u32,
) callconv(.winapi) ?*CryptProviderSigner;
const WtHelperGetProvCertFromChain = *const fn (
    *CryptProviderSigner,
    u32,
) callconv(.winapi) ?*CryptProviderCertificate;
const CertGetNameString = *const fn (
    *const CertificateContext,
    u32,
    u32,
    ?*const anyopaque,
    ?[*]u16,
    u32,
) callconv(.winapi) u32;

const AuthenticodeApi = struct {
    wintrust_module: std.os.windows.HMODULE,
    crypt32_module: std.os.windows.HMODULE,
    verify_trust: WinVerifyTrust,
    provider_data: WtHelperProvDataFromStateData,
    provider_signer: WtHelperGetProvSignerFromChain,
    provider_certificate: WtHelperGetProvCertFromChain,
    certificate_name: CertGetNameString,

    fn open() !AuthenticodeApi {
        const wintrust_module = LoadLibraryExW(
            std.unicode.utf8ToUtf16LeStringLiteral("wintrust.dll"),
            null,
            load_library_search_system32,
        ) orelse return error.AuthenticodeUnavailable;
        errdefer _ = FreeLibrary(wintrust_module);
        const crypt32_module = LoadLibraryExW(
            std.unicode.utf8ToUtf16LeStringLiteral("crypt32.dll"),
            null,
            load_library_search_system32,
        ) orelse return error.AuthenticodeUnavailable;
        errdefer _ = FreeLibrary(crypt32_module);
        return .{
            .wintrust_module = wintrust_module,
            .crypt32_module = crypt32_module,
            .verify_trust = try lookupAuthenticodeProcedure(
                wintrust_module,
                WinVerifyTrust,
                "WinVerifyTrust",
            ),
            .provider_data = try lookupAuthenticodeProcedure(
                wintrust_module,
                WtHelperProvDataFromStateData,
                "WTHelperProvDataFromStateData",
            ),
            .provider_signer = try lookupAuthenticodeProcedure(
                wintrust_module,
                WtHelperGetProvSignerFromChain,
                "WTHelperGetProvSignerFromChain",
            ),
            .provider_certificate = try lookupAuthenticodeProcedure(
                wintrust_module,
                WtHelperGetProvCertFromChain,
                "WTHelperGetProvCertFromChain",
            ),
            .certificate_name = try lookupAuthenticodeProcedure(
                crypt32_module,
                CertGetNameString,
                "CertGetNameStringW",
            ),
        };
    }

    fn close(self: *AuthenticodeApi) void {
        _ = FreeLibrary(self.crypt32_module);
        _ = FreeLibrary(self.wintrust_module);
    }
};

fn lookupAuthenticodeProcedure(
    module: std.os.windows.HMODULE,
    comptime T: type,
    name: [:0]const u8,
) !T {
    const procedure = GetProcAddress(module, name.ptr) orelse
        return error.AuthenticodeUnavailable;
    return @ptrCast(procedure);
}

fn certificateSubject(
    allocator: std.mem.Allocator,
    api: *const AuthenticodeApi,
    certificate: *const CertificateContext,
) ![]u8 {
    const name_format: u32 = cert_x500_name_str | cert_name_str_reverse_flag;
    const count = api.certificate_name(
        certificate,
        cert_name_rdn_type,
        0,
        @ptrCast(&name_format),
        null,
        0,
    );
    if (count < 2 or count > 1024) return error.InvalidGhAuthenticodeSubject;
    const wide = try allocator.alloc(u16, count);
    defer allocator.free(wide);
    if (api.certificate_name(
        certificate,
        cert_name_rdn_type,
        0,
        @ptrCast(&name_format),
        wide.ptr,
        count,
    ) != count or wide[count - 1] != 0) return error.InvalidGhAuthenticodeSubject;
    return std.unicode.wtf16LeToWtf8Alloc(allocator, wide[0 .. count - 1]);
}

fn requireGhAuthenticodeIdentity(
    subject: []const u8,
    thumbprint_sha1: []const u8,
) !void {
    if (!std.mem.eql(u8, subject, gh_authenticode_subject)) {
        return error.WrongGhAuthenticodeSubject;
    }
    if (!std.mem.eql(u8, thumbprint_sha1, gh_authenticode_thumbprint_sha1)) {
        return error.WrongGhAuthenticodeThumbprint;
    }
}

fn verifyAuthenticodeSigner(
    allocator: std.mem.Allocator,
    path: []const u8,
    file: std.Io.File,
) !void {
    if (builtin.os.tag != .windows) return error.UnsupportedAttestationAuditHost;
    const path_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, path);
    defer allocator.free(path_w);
    var api = try AuthenticodeApi.open();
    defer api.close();

    var file_info: WintrustFileInfo = .{
        .cb_struct = @sizeOf(WintrustFileInfo),
        .file_path = path_w.ptr,
        .file = file.handle,
        .known_subject = null,
    };
    var trust_data: WintrustData = .{
        .cb_struct = @sizeOf(WintrustData),
        .policy_callback_data = null,
        .sip_client_data = null,
        .ui_choice = wtd_ui_none,
        .revocation_checks = wtd_revoke_none,
        .union_choice = wtd_choice_file,
        .file_info = &file_info,
        .state_action = wtd_stateaction_verify,
        .state_data = null,
        .url_reference = null,
        // Both controls are intentional: no revocation processing and no URL
        // retrieval on a cache miss. The verifier must remain offline.
        .provider_flags = wtd_cache_only_url_retrieval | wtd_revocation_check_none,
        .ui_context = 0,
        .signature_settings = null,
    };
    const generic_verify_v2: std.os.windows.GUID = .{
        .Data1 = 0x00aa_c56b,
        .Data2 = 0xcd44,
        .Data3 = 0x11d0,
        .Data4 = .{ 0x8c, 0xc2, 0x00, 0xc0, 0x4f, 0xc2, 0x95, 0xee },
    };
    const status = api.verify_trust(null, &generic_verify_v2, &trust_data);
    defer {
        trust_data.state_action = wtd_stateaction_close;
        _ = api.verify_trust(null, &generic_verify_v2, &trust_data);
    }
    if (status != 0) return error.GhAuthenticodeVerificationFailed;
    const state = trust_data.state_data orelse return error.InvalidGhAuthenticodeSigner;
    const provider = api.provider_data(state) orelse
        return error.InvalidGhAuthenticodeSigner;
    const signer = api.provider_signer(provider, 0, 0, 0) orelse
        return error.InvalidGhAuthenticodeSigner;
    const provider_certificate = api.provider_certificate(signer, 0) orelse
        return error.InvalidGhAuthenticodeSigner;
    const certificate = provider_certificate.certificate orelse
        return error.InvalidGhAuthenticodeSigner;

    const subject = try certificateSubject(allocator, &api, certificate);
    defer allocator.free(subject);
    const encoded = certificate.encoded orelse return error.InvalidGhAuthenticodeSigner;
    if (certificate.encoded_len == 0 or certificate.encoded_len > 128 * 1024) {
        return error.InvalidGhAuthenticodeSigner;
    }
    var digest: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
    std.crypto.hash.Sha1.hash(encoded[0..certificate.encoded_len], &digest, .{});
    const thumbprint = std.fmt.bytesToHex(digest, .upper);
    try requireGhAuthenticodeIdentity(subject, &thumbprint);
}

fn verifyGhAuthenticode(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    file: std.Io.File,
) !void {
    _ = io;
    try verifyAuthenticodeSigner(allocator, path, file);
}

const ConvertStringSecurityDescriptor = *const fn (
    [*:0]const u16,
    u32,
    *?*anyopaque,
    ?*u32,
) callconv(.winapi) i32;
const OpenProcessToken = *const fn (
    std.os.windows.HANDLE,
    u32,
    *std.os.windows.HANDLE,
) callconv(.winapi) i32;
const GetTokenInformation = *const fn (
    std.os.windows.HANDLE,
    u32,
    ?*anyopaque,
    u32,
    *u32,
) callconv(.winapi) i32;
const ConvertSidToStringSid = *const fn (
    *const anyopaque,
    *?[*:0]u16,
) callconv(.winapi) i32;
const ConvertStringSidToSid = *const fn (
    [*:0]const u16,
    *?*anyopaque,
) callconv(.winapi) i32;
const GetSecurityDescriptorOwner = *const fn (
    *const anyopaque,
    *?*anyopaque,
    *i32,
) callconv(.winapi) i32;
const GetSecurityDescriptorDacl = *const fn (
    *const anyopaque,
    *i32,
    *?*anyopaque,
    *i32,
) callconv(.winapi) i32;
const SetSecurityInfo = *const fn (
    std.os.windows.HANDLE,
    u32,
    u32,
    ?*anyopaque,
    ?*anyopaque,
    ?*anyopaque,
    ?*anyopaque,
) callconv(.winapi) u32;
const GetSecurityInfo = *const fn (
    std.os.windows.HANDLE,
    u32,
    u32,
    ?*?*anyopaque,
    ?*?*anyopaque,
    ?*?*anyopaque,
    ?*?*anyopaque,
    *?*anyopaque,
) callconv(.winapi) u32;
const EqualSid = *const fn (
    *const anyopaque,
    *const anyopaque,
) callconv(.winapi) i32;
const GetLengthSid = *const fn (*const anyopaque) callconv(.winapi) u32;
const GetAce = *const fn (
    *const anyopaque,
    u32,
    *?*anyopaque,
) callconv(.winapi) i32;
const GetSecurityDescriptorControl = *const fn (
    *const anyopaque,
    *u16,
    *u32,
) callconv(.winapi) i32;

const Advapi32 = struct {
    module: std.os.windows.HMODULE,
    convert: ConvertStringSecurityDescriptor,
    open_process_token: OpenProcessToken,
    get_token_information: GetTokenInformation,
    convert_sid_to_string: ConvertSidToStringSid,
    convert_string_to_sid: ConvertStringSidToSid,
    get_descriptor_owner: GetSecurityDescriptorOwner,
    get_descriptor_dacl: GetSecurityDescriptorDacl,
    set_security_info: SetSecurityInfo,
    get_security_info: GetSecurityInfo,
    equal_sid: EqualSid,
    get_length_sid: GetLengthSid,
    get_ace: GetAce,
    get_descriptor_control: GetSecurityDescriptorControl,

    fn open() !Advapi32 {
        const module = LoadLibraryExW(
            std.unicode.utf8ToUtf16LeStringLiteral("advapi32.dll"),
            null,
            load_library_search_system32,
        ) orelse return error.OwnerOnlyAclUnavailable;
        errdefer _ = FreeLibrary(module);
        return .{
            .module = module,
            .convert = try lookupProcedure(
                module,
                ConvertStringSecurityDescriptor,
                "ConvertStringSecurityDescriptorToSecurityDescriptorW",
            ),
            .open_process_token = try lookupProcedure(
                module,
                OpenProcessToken,
                "OpenProcessToken",
            ),
            .get_token_information = try lookupProcedure(
                module,
                GetTokenInformation,
                "GetTokenInformation",
            ),
            .convert_sid_to_string = try lookupProcedure(
                module,
                ConvertSidToStringSid,
                "ConvertSidToStringSidW",
            ),
            .convert_string_to_sid = try lookupProcedure(
                module,
                ConvertStringSidToSid,
                "ConvertStringSidToSidW",
            ),
            .get_descriptor_owner = try lookupProcedure(
                module,
                GetSecurityDescriptorOwner,
                "GetSecurityDescriptorOwner",
            ),
            .get_descriptor_dacl = try lookupProcedure(
                module,
                GetSecurityDescriptorDacl,
                "GetSecurityDescriptorDacl",
            ),
            .set_security_info = try lookupProcedure(
                module,
                SetSecurityInfo,
                "SetSecurityInfo",
            ),
            .get_security_info = try lookupProcedure(
                module,
                GetSecurityInfo,
                "GetSecurityInfo",
            ),
            .equal_sid = try lookupProcedure(module, EqualSid, "EqualSid"),
            .get_length_sid = try lookupProcedure(
                module,
                GetLengthSid,
                "GetLengthSid",
            ),
            .get_ace = try lookupProcedure(module, GetAce, "GetAce"),
            .get_descriptor_control = try lookupProcedure(
                module,
                GetSecurityDescriptorControl,
                "GetSecurityDescriptorControl",
            ),
        };
    }

    fn close(self: *Advapi32) void {
        _ = FreeLibrary(self.module);
    }
};

fn lookupProcedure(
    module: std.os.windows.HMODULE,
    comptime T: type,
    name: [:0]const u8,
) !T {
    const procedure = GetProcAddress(module, name.ptr) orelse
        return error.OwnerOnlyAclUnavailable;
    return @ptrCast(procedure);
}

const CurrentUserSid = struct {
    allocator: std.mem.Allocator,
    bytes: []align(@alignOf(TokenUser)) u8,
    sid: *anyopaque,

    fn deinit(self: *CurrentUserSid) void {
        self.allocator.free(self.bytes);
    }
};

const SidAndAttributes = extern struct {
    sid: ?*anyopaque,
    attributes: u32,
};

const TokenUser = extern struct {
    user: SidAndAttributes,
};

const OwnerSecurityAccess = enum {
    directory_full,
    file_full,
    read_execute,
};

const OwnerSecurity = struct {
    allocator: std.mem.Allocator,
    current_sid: CurrentUserSid,
    owner_rights_sid: ?*anyopaque,
    sid_text: []u8,
    sddl: []u8,
    sddl_w: [:0]u16,
    descriptor: *anyopaque,
    owner: *anyopaque,
    dacl: *anyopaque,

    fn init(
        allocator: std.mem.Allocator,
        advapi: *const Advapi32,
        access: OwnerSecurityAccess,
    ) !OwnerSecurity {
        var current_sid = try currentUserSid(allocator, advapi);
        errdefer current_sid.deinit();
        const sid_text = try currentUserSidString(allocator, advapi, current_sid.sid);
        errdefer allocator.free(sid_text);
        const sddl = switch (access) {
            .directory_full => try std.fmt.allocPrint(
                allocator,
                "O:{s}D:P(A;OICI;FA;;;{s})",
                .{ sid_text, sid_text },
            ),
            .file_full => try std.fmt.allocPrint(
                allocator,
                "O:{s}D:P(A;;FA;;;{s})",
                .{ sid_text, sid_text },
            ),
            .read_execute => try std.fmt.allocPrint(
                allocator,
                // OWNER RIGHTS (S-1-3-4) suppresses the owner's implicit
                // WRITE_DAC grant while granting only read/execute during the
                // runner window. The already-held full-access handle remains
                // usable to restore the cleanup DACL after the child exits.
                "O:{s}D:P(A;;GRGX;;;OW)",
                .{sid_text},
            ),
        };
        errdefer allocator.free(sddl);
        const sddl_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, sddl);
        errdefer allocator.free(sddl_w);
        var descriptor: ?*anyopaque = null;
        if (advapi.convert(sddl_w.ptr, 1, &descriptor, null) == 0 or descriptor == null) {
            return error.OwnerOnlyAclFailed;
        }
        errdefer _ = LocalFree(descriptor);
        var owner: ?*anyopaque = null;
        var owner_defaulted: i32 = 0;
        var dacl: ?*anyopaque = null;
        var dacl_present: i32 = 0;
        var dacl_defaulted: i32 = 0;
        if (advapi.get_descriptor_owner(
            descriptor.?,
            &owner,
            &owner_defaulted,
        ) == 0 or owner == null or owner_defaulted != 0 or
            advapi.get_descriptor_dacl(
                descriptor.?,
                &dacl_present,
                &dacl,
                &dacl_defaulted,
            ) == 0 or dacl_present == 0 or dacl == null or dacl_defaulted != 0)
        {
            return error.OwnerOnlyAclFailed;
        }
        var owner_rights_sid: ?*anyopaque = null;
        if (access == .read_execute and
            (advapi.convert_string_to_sid(
                std.unicode.utf8ToUtf16LeStringLiteral("S-1-3-4"),
                &owner_rights_sid,
            ) == 0 or owner_rights_sid == null))
        {
            return error.OwnerOnlyAclFailed;
        }
        errdefer {
            if (owner_rights_sid) |sid| _ = LocalFree(sid);
        }
        return .{
            .allocator = allocator,
            .current_sid = current_sid,
            .owner_rights_sid = owner_rights_sid,
            .sid_text = sid_text,
            .sddl = sddl,
            .sddl_w = sddl_w,
            .descriptor = descriptor.?,
            .owner = owner.?,
            .dacl = dacl.?,
        };
    }

    fn deinit(self: *OwnerSecurity) void {
        if (self.owner_rights_sid) |sid| _ = LocalFree(sid);
        _ = LocalFree(self.descriptor);
        self.allocator.free(self.sddl_w);
        self.allocator.free(self.sddl);
        self.allocator.free(self.sid_text);
        self.current_sid.deinit();
    }
};

fn currentUserSid(
    allocator: std.mem.Allocator,
    advapi: *const Advapi32,
) !CurrentUserSid {
    var token: std.os.windows.HANDLE = undefined;
    if (advapi.open_process_token(GetCurrentProcess(), 0x0000_0008, &token) == 0) {
        return error.CurrentUserSidUnavailable;
    }
    defer _ = CloseHandle(token);
    var required: u32 = 0;
    _ = advapi.get_token_information(token, 1, null, 0, &required);
    if (required < @sizeOf(TokenUser) or required > 4096) {
        return error.CurrentUserSidUnavailable;
    }
    const bytes = try allocator.alignedAlloc(u8, .of(TokenUser), required);
    errdefer allocator.free(bytes);
    if (advapi.get_token_information(token, 1, bytes.ptr, required, &required) == 0) {
        return error.CurrentUserSidUnavailable;
    }
    const token_user: *const TokenUser = @ptrCast(@alignCast(bytes.ptr));
    const sid = token_user.user.sid orelse return error.CurrentUserSidUnavailable;
    const sid_len = advapi.get_length_sid(sid);
    if (sid_len < 8 or sid_len > required) return error.CurrentUserSidUnavailable;
    return .{ .allocator = allocator, .bytes = bytes, .sid = sid };
}

fn currentUserSidString(
    allocator: std.mem.Allocator,
    advapi: *const Advapi32,
    sid: *const anyopaque,
) ![]u8 {
    var wide: ?[*:0]u16 = null;
    if (advapi.convert_sid_to_string(sid, &wide) == 0 or wide == null) {
        return error.CurrentUserSidUnavailable;
    }
    defer _ = LocalFree(wide);
    return std.unicode.wtf16LeToWtf8Alloc(allocator, std.mem.span(wide.?));
}

fn verifyOwnerOnlyAcl(
    advapi: *const Advapi32,
    handle: std.os.windows.HANDLE,
    current_sid: *const anyopaque,
    owner_rights_sid: ?*const anyopaque,
    expected_ace_flags: u8,
    expected_access_mask: u32,
) !void {
    var owner: ?*anyopaque = null;
    var dacl: ?*anyopaque = null;
    var descriptor: ?*anyopaque = null;
    if (advapi.get_security_info(
        handle,
        1,
        owner_security_information | dacl_security_information,
        &owner,
        null,
        &dacl,
        null,
        &descriptor,
    ) != 0 or owner == null or dacl == null or descriptor == null) {
        return error.OwnerOnlyAclVerificationFailed;
    }
    defer _ = LocalFree(descriptor);
    if (advapi.equal_sid(owner.?, current_sid) == 0) {
        return error.WrongAuditProfileOwner;
    }
    var control: u16 = 0;
    var revision: u32 = 0;
    if (advapi.get_descriptor_control(descriptor.?, &control, &revision) == 0 or
        control & 0x1000 == 0)
    {
        return error.OwnerOnlyAclVerificationFailed;
    }

    const acl: [*]const u8 = @ptrCast(dacl.?);
    const acl_size = std.mem.readInt(u16, acl[2..4], .little);
    const ace_count = std.mem.readInt(u16, acl[4..6], .little);
    if (acl[0] != 2 or acl_size < 20 or ace_count != 1) {
        return error.OwnerOnlyAclVerificationFailed;
    }
    if (owner_rights_sid) |rights_sid| {
        try verifyExactAce(
            advapi,
            dacl.?,
            0,
            0,
            0,
            expected_access_mask,
            rights_sid,
        );
        return;
    }
    try verifyExactAce(
        advapi,
        dacl.?,
        0,
        0,
        expected_ace_flags,
        expected_access_mask,
        current_sid,
    );
}

fn verifyExactAce(
    advapi: *const Advapi32,
    dacl: *const anyopaque,
    index: u32,
    expected_type: u8,
    expected_flags: u8,
    expected_mask: u32,
    expected_sid: *const anyopaque,
) !void {
    var ace: ?*anyopaque = null;
    if (advapi.get_ace(dacl, index, &ace) == 0 or ace == null) {
        return error.OwnerOnlyAclVerificationFailed;
    }
    const ace_bytes: [*]const u8 = @ptrCast(ace.?);
    const ace_size = std.mem.readInt(u16, ace_bytes[2..4], .little);
    if (ace_size < 16) return error.OwnerOnlyAclVerificationFailed;
    const ace_mask = std.mem.readInt(u32, ace_bytes[4..8], .little);
    if (ace_bytes[0] != expected_type or ace_bytes[1] != expected_flags or
        ace_mask != expected_mask)
    {
        return error.OwnerOnlyAclVerificationFailed;
    }
    const ace_sid: *const anyopaque = @ptrCast(ace_bytes + 8);
    if (advapi.equal_sid(ace_sid, expected_sid) == 0 or
        ace_size != 8 + advapi.get_length_sid(ace_sid))
    {
        return error.OwnerOnlyAclVerificationFailed;
    }
}

fn applyOwnerSecurity(
    advapi: *const Advapi32,
    handle: std.os.windows.HANDLE,
    security: *const OwnerSecurity,
    expected_ace_flags: u8,
    expected_access_mask: u32,
) !void {
    if (advapi.set_security_info(
        handle,
        1,
        owner_security_information | dacl_security_information |
            protected_dacl_security_information,
        security.owner,
        null,
        security.dacl,
        null,
    ) != 0) return error.OwnerOnlyAclFailed;
    try verifyOwnerOnlyAcl(
        advapi,
        handle,
        security.current_sid.sid,
        security.owner_rights_sid,
        expected_ace_flags,
        expected_access_mask,
    );
}

fn createPrivateDirectory(
    allocator: std.mem.Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    name: []const u8,
) !std.Io.Dir {
    if (builtin.os.tag != .windows) return error.UnsupportedAttestationAuditHost;
    try validateAuditProfileName(name);
    var advapi = try Advapi32.open();
    defer advapi.close();
    var security = try OwnerSecurity.init(allocator, &advapi, .directory_full);
    defer security.deinit();

    const name_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, name);
    defer allocator.free(name_w);
    var object_name = std.os.windows.UNICODE_STRING.init(name_w);
    const attributes: std.os.windows.OBJECT.ATTRIBUTES = .{
        .RootDirectory = parent.handle,
        .ObjectName = &object_name,
        .Attributes = .{ .DONT_REPARSE = true },
        .SecurityDescriptor = security.descriptor,
        .SecurityQualityOfService = null,
    };
    var handle: std.os.windows.HANDLE = undefined;
    var status_block: std.os.windows.IO_STATUS_BLOCK = undefined;
    switch (std.os.windows.ntdll.NtCreateFile(
        &handle,
        .{
            .GENERIC = .{ .ALL = true },
            .STANDARD = .{ .SYNCHRONIZE = true },
        },
        &attributes,
        &status_block,
        null,
        .{ .NORMAL = true },
        .{ .READ = true },
        .CREATE,
        .{ .DIRECTORY_FILE = true, .IO = .SYNCHRONOUS_NONALERT },
        null,
        0,
    )) {
        .SUCCESS => {},
        .OBJECT_NAME_COLLISION => return error.AuditProfileAlreadyExists,
        else => return error.AuditProfileCreateFailed,
    }
    var directory: std.Io.Dir = .{ .handle = handle };
    applyOwnerSecurity(&advapi, handle, &security, 0x03, file_all_access) catch |err| {
        directory.close(io);
        parent.deleteTree(io, name) catch return error.AuditTempCleanupFailed;
        return err;
    };
    return directory;
}

fn createPinnedPrivateFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    bytes: []const u8,
) !std.Io.File {
    if (builtin.os.tag != .windows) return error.UnsupportedAttestationAuditHost;
    var advapi = try Advapi32.open();
    defer advapi.close();
    var security = try OwnerSecurity.init(allocator, &advapi, .read_execute);
    defer security.deinit();
    const path_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, path);
    defer allocator.free(path_w);
    var attributes: std.os.windows.SECURITY_ATTRIBUTES = .{
        .nLength = @sizeOf(std.os.windows.SECURITY_ATTRIBUTES),
        .lpSecurityDescriptor = security.descriptor,
        .bInheritHandle = .FALSE,
    };
    const handle = CreateFileW(
        path_w.ptr,
        generic_read | generic_write | read_control | write_dac | write_owner,
        file_share_read,
        @ptrCast(&attributes),
        create_new,
        file_attribute_normal | file_flag_open_reparse_point,
        null,
    );
    if (handle == std.os.windows.INVALID_HANDLE_VALUE) return error.AuditSnapshotCreateFailed;
    const file: std.Io.File = .{ .handle = handle, .flags = .{ .nonblocking = false } };
    var file_open = true;
    defer if (file_open) file.close(io);
    var offset: usize = 0;
    while (offset < bytes.len) {
        const chunk_size: u32 = @intCast(@min(bytes.len - offset, std.math.maxInt(u32)));
        var written: u32 = 0;
        if (WriteFile(handle, bytes[offset..].ptr, chunk_size, &written, null) == 0 or
            written == 0)
        {
            return error.AuditSnapshotWriteFailed;
        }
        offset += written;
    }
    if (FlushFileBuffers(handle) == 0 or SetFilePointerEx(handle, 0, null, file_begin) == 0) {
        return error.AuditSnapshotWriteFailed;
    }
    try verifyOwnerOnlyAcl(
        &advapi,
        handle,
        security.current_sid.sid,
        security.owner_rights_sid,
        0,
        file_generic_read_execute,
    );

    // Windows cannot execute an image while a write-access handle is open.
    // Reopen the same object before closing the writer: the bridge denies
    // deletion, and the protected OWNER RIGHTS DACL denies new writes and
    // WRITE_DAC from creation onward. The final pin again shares only reads.
    const bridge = ReOpenFile(
        handle,
        generic_read,
        file_share_read | file_share_write,
        file_flag_open_reparse_point,
    );
    if (bridge == std.os.windows.INVALID_HANDLE_VALUE) return error.AuditInputPinFailed;
    defer _ = CloseHandle(bridge);
    file.close(io);
    file_open = false;
    const pinned_handle = ReOpenFile(
        bridge,
        generic_read,
        file_share_read,
        file_flag_open_reparse_point,
    );
    if (pinned_handle == std.os.windows.INVALID_HANDLE_VALUE) return error.AuditInputPinFailed;
    return .{ .handle = pinned_handle, .flags = .{ .nonblocking = false } };
}

fn freezePrivateDirectory(
    allocator: std.mem.Allocator,
    handle: std.os.windows.HANDLE,
) !void {
    var advapi = try Advapi32.open();
    defer advapi.close();
    var security = try OwnerSecurity.init(allocator, &advapi, .read_execute);
    defer security.deinit();
    try applyOwnerSecurity(
        &advapi,
        handle,
        &security,
        0,
        file_generic_read_execute,
    );
}

extern "kernel32" fn LoadLibraryExW(
    file_name: [*:0]const u16,
    file: ?std.os.windows.HANDLE,
    flags: u32,
) callconv(.winapi) ?std.os.windows.HMODULE;
extern "kernel32" fn CreateFileW(
    file_name: [*:0]const u16,
    desired_access: u32,
    share_mode: u32,
    security_attributes: ?*anyopaque,
    creation_disposition: u32,
    flags_and_attributes: u32,
    template_file: ?std.os.windows.HANDLE,
) callconv(.winapi) std.os.windows.HANDLE;
extern "kernel32" fn ReOpenFile(
    original_file: std.os.windows.HANDLE,
    desired_access: u32,
    share_mode: u32,
    flags_and_attributes: u32,
) callconv(.winapi) std.os.windows.HANDLE;
extern "kernel32" fn GetFileSizeEx(
    file: std.os.windows.HANDLE,
    size: *i64,
) callconv(.winapi) i32;
extern "kernel32" fn SetFilePointerEx(
    file: std.os.windows.HANDLE,
    distance: i64,
    new_position: ?*i64,
    move_method: u32,
) callconv(.winapi) i32;
extern "kernel32" fn ReadFile(
    file: std.os.windows.HANDLE,
    buffer: [*]u8,
    bytes_to_read: u32,
    bytes_read: *u32,
    overlapped: ?*anyopaque,
) callconv(.winapi) i32;
extern "kernel32" fn WriteFile(
    file: std.os.windows.HANDLE,
    buffer: [*]const u8,
    bytes_to_write: u32,
    bytes_written: *u32,
    overlapped: ?*anyopaque,
) callconv(.winapi) i32;
extern "kernel32" fn FlushFileBuffers(
    file: std.os.windows.HANDLE,
) callconv(.winapi) i32;
extern "kernel32" fn GetProcAddress(
    module: std.os.windows.HMODULE,
    procedure_name: [*:0]const u8,
) callconv(.winapi) ?std.os.windows.FARPROC;
extern "kernel32" fn FreeLibrary(module: std.os.windows.HMODULE) callconv(.winapi) i32;
extern "kernel32" fn LocalFree(memory: ?*anyopaque) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetCurrentProcess() callconv(.winapi) std.os.windows.HANDLE;
extern "kernel32" fn CloseHandle(handle: std.os.windows.HANDLE) callconv(.winapi) i32;

const tiny_gh_fixture = "tiny signed gh fixture";
const tiny_artifact_fixture = "tiny pdfium fixture";
const tiny_bundle_fixture = "{\"sig\":\"A\"}\n";
const tiny_root_fixture =
    "{\"rawBytes\":\"" ++ rekor_public_key ++ "\"}\n" ++
    "{\"rawBytes\":\"" ++ ctlog_public_key ++ "\"}\n";

const FakeAuditContext = struct {
    runner_calls: usize = 0,
    executable_checks: usize = 0,
    profile_guard_checks: usize = 0,
};

fn fakeAuditContext(raw: ?*anyopaque) *FakeAuditContext {
    return @ptrCast(@alignCast(raw.?));
}

fn fakeVerifyLockedBuffers(
    _: ?*anyopaque,
    _: std.mem.Allocator,
    gh_bytes: []const u8,
    artifact_bytes: []const u8,
    bundle: []const u8,
    trusted_root: []const u8,
) anyerror!void {
    try std.testing.expectEqualStrings(tiny_gh_fixture, gh_bytes);
    try std.testing.expectEqualStrings(tiny_artifact_fixture, artifact_bytes);
    try std.testing.expectEqualStrings(tiny_bundle_fixture, bundle);
    try std.testing.expectEqualStrings(tiny_root_fixture, trusted_root);
}

fn fakeVerifyExecutable(
    raw: ?*anyopaque,
    allocator: std.mem.Allocator,
    _: std.Io,
    path: []const u8,
    file: std.Io.File,
) anyerror!void {
    const context = fakeAuditContext(raw);
    try std.testing.expect(std.mem.endsWith(u8, path, "gh.exe"));
    const bytes = try readPinnedFileAlloc(allocator, file, tiny_gh_fixture.len);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings(tiny_gh_fixture, bytes);
    context.executable_checks += 1;
}

fn fakeValidateResult(
    _: ?*anyopaque,
    _: std.mem.Allocator,
    result: []const u8,
) anyerror!deps.AttestationSummary {
    try std.testing.expectEqualStrings("{}", result);
    return .{ .subjects = 45, .matching_subjects = 1 };
}

fn fakeValidateMutatedRoot(
    _: ?*anyopaque,
    _: std.mem.Allocator,
    root: []const u8,
) anyerror!void {
    try std.testing.expectEqual(tiny_root_fixture.len, root.len);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, root, rekor_public_key));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, root, ctlog_public_key));
}

fn fakeAfterProfileCreated(
    raw: ?*anyopaque,
    io: std.Io,
    _: std.Io.Dir,
    profile: std.Io.Dir,
    _: []const u8,
) anyerror!void {
    const context = fakeAuditContext(raw);
    try std.testing.expectEqual(std.Io.File.Kind.directory, (try profile.stat(io)).kind);
    context.profile_guard_checks += 1;
}

fn fakeAfterProfilePrecheck(
    _: ?*anyopaque,
    _: std.Io,
    _: std.Io.Dir,
) anyerror!void {}

fn fakeRejectExecutable(
    raw: ?*anyopaque,
    _: std.mem.Allocator,
    _: std.Io,
    _: []const u8,
    _: std.Io.File,
) anyerror!void {
    const context = fakeAuditContext(raw);
    try std.testing.expectEqual(@as(usize, 0), context.runner_calls);
    return error.WrongGhAuthenticodeSubject;
}

fn fakeInjectAfterProfilePrecheck(
    raw: ?*anyopaque,
    io: std.Io,
    profile: std.Io.Dir,
) anyerror!void {
    const context = fakeAuditContext(raw);
    try std.testing.expectEqual(@as(usize, 0), context.runner_calls);
    const profile_path = try profile.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(profile_path);
    try expectDirectoryDaclWriteDenied(std.testing.allocator, profile_path);
    try writePrivateFile(io, profile, "ambient-config.yml", "malicious: true\n");
}

fn expectDirectoryDaclWriteDenied(
    allocator: std.mem.Allocator,
    path: []const u8,
) !void {
    const path_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, path);
    defer allocator.free(path_w);
    const handle = CreateFileW(
        path_w.ptr,
        write_dac,
        file_share_read | file_share_write | file_share_delete,
        null,
        open_existing,
        file_flag_backup_semantics | file_flag_open_reparse_point,
        null,
    );
    if (handle != std.os.windows.INVALID_HANDLE_VALUE) {
        _ = CloseHandle(handle);
        return error.FrozenProfileDaclWritable;
    }
    if (std.os.windows.GetLastError() != .ACCESS_DENIED) {
        return error.UnexpectedFrozenProfileOpenFailure;
    }
}

fn allocatedRunResult(
    allocator: std.mem.Allocator,
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
) !std.process.RunResult {
    const stdout_copy = try allocator.dupe(u8, stdout);
    errdefer allocator.free(stdout_copy);
    const stderr_copy = try allocator.dupe(u8, stderr);
    errdefer allocator.free(stderr_copy);
    return .{
        .term = .{ .exited = exit_code },
        .stdout = stdout_copy,
        .stderr = stderr_copy,
    };
}

fn verifyFakeRunnerEnvironment(
    environment: *const std.process.Environ.Map,
    cwd: []const u8,
) !void {
    try std.testing.expect(environment.get("GH_TOKEN") == null);
    try std.testing.expect(environment.get("PATH") == null);
    const sentinel = environment.get("HOME").?;
    try std.testing.expect(std.mem.endsWith(u8, sentinel, "config-sentinel"));
    try std.testing.expect(std.mem.startsWith(u8, sentinel, cwd));
    try std.testing.expectEqualStrings(sentinel, environment.get("USERPROFILE").?);
    try std.testing.expectEqualStrings(sentinel, environment.get("APPDATA").?);
    try std.testing.expectEqualStrings(sentinel, environment.get("LOCALAPPDATA").?);
    try std.testing.expectEqualStrings(sentinel, environment.get("XDG_CONFIG_HOME").?);
    try std.testing.expectEqualStrings(sentinel, environment.get("XDG_CACHE_HOME").?);
    try std.testing.expectEqualStrings(sentinel, environment.get("GH_CONFIG_DIR").?);
    try std.testing.expectEqualStrings(sentinel, environment.get("TEMP").?);
    try std.testing.expectEqualStrings(sentinel, environment.get("TMP").?);
    try std.testing.expectEqualStrings("http://127.0.0.1:9", environment.get("HTTP_PROXY").?);
    try std.testing.expectEqualStrings("http://127.0.0.1:9", environment.get("HTTPS_PROXY").?);
    try std.testing.expectEqualStrings("http://127.0.0.1:9", environment.get("ALL_PROXY").?);
}

fn fakeRunGh(
    raw: ?*anyopaque,
    allocator: std.mem.Allocator,
    _: std.Io,
    argv: []const []const u8,
    environment: *const std.process.Environ.Map,
    cwd: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
) anyerror!std.process.RunResult {
    const context = fakeAuditContext(raw);
    try verifyFakeRunnerEnvironment(environment, cwd);
    const call = context.runner_calls;
    context.runner_calls += 1;
    switch (call) {
        0 => {
            try std.testing.expectEqual(@as(usize, 2), argv.len);
            try std.testing.expectEqualStrings("version", argv[1]);
            try std.testing.expectEqual(@as(usize, 4 * 1024), stdout_limit);
            try std.testing.expectEqual(@as(usize, 4 * 1024), stderr_limit);
            return allocatedRunResult(allocator, 0, gh_version_output, "");
        },
        1 => {
            try std.testing.expectEqual(@as(usize, 25), argv.len);
            try std.testing.expect(std.mem.endsWith(u8, argv[0], "gh.exe"));
            try std.testing.expect(std.mem.endsWith(u8, argv[VerificationArgIndex.artifact], "pdfium.tgz"));
            try std.testing.expect(std.mem.endsWith(u8, argv[VerificationArgIndex.bundle], "bundle.jsonl"));
            try std.testing.expect(std.mem.endsWith(u8, argv[VerificationArgIndex.trusted_root], "trusted-root.jsonl"));
            try std.testing.expectEqual(@as(usize, 256 * 1024), stdout_limit);
            try std.testing.expectEqual(@as(usize, 64 * 1024), stderr_limit);
            return allocatedRunResult(allocator, 0, "{}", "");
        },
        2 => {
            try std.testing.expect(std.mem.endsWith(
                u8,
                argv[VerificationArgIndex.artifact],
                "mutated-pdfium.tgz",
            ));
            return allocatedRunResult(allocator, 1, "", generic_verifier_rejection);
        },
        3 => {
            try std.testing.expect(std.mem.endsWith(
                u8,
                argv[VerificationArgIndex.bundle],
                "mutated-bundle.jsonl",
            ));
            return allocatedRunResult(allocator, 1, "", generic_verifier_rejection);
        },
        4 => {
            try std.testing.expect(std.mem.endsWith(
                u8,
                argv[VerificationArgIndex.trusted_root],
                "mutated-root.jsonl",
            ));
            return allocatedRunResult(allocator, 1, "", generic_verifier_rejection);
        },
        5 => {
            try std.testing.expect(std.mem.endsWith(
                u8,
                argv[VerificationArgIndex.trusted_root],
                "github-only-root.jsonl",
            ));
            return allocatedRunResult(
                allocator,
                1,
                "",
                "no custom verifier found for issuer \"sigstore.dev\"",
            );
        },
        6 => {
            try std.testing.expect(std.mem.endsWith(
                u8,
                argv[VerificationArgIndex.certificate_identity],
                "@refs/heads/main",
            ));
            return allocatedRunResult(allocator, 1, "", generic_verifier_rejection);
        },
        7 => return allocatedRunResult(
            allocator,
            1,
            "",
            "expected SourceRepositoryURI to be https://github.com/bblanchon/pdfium-binariez",
        ),
        8 => return allocatedRunResult(
            allocator,
            1,
            "",
            "expected SourceRepositoryRef to be refs/heads/main",
        ),
        9 => return allocatedRunResult(
            allocator,
            1,
            "",
            "expected SourceRepositoryDigest to be 6453f3afc4785cbad82c05f6ceb4dabea0cb81a0",
        ),
        10 => return allocatedRunResult(
            allocator,
            1,
            "",
            "expected BuildSignerDigest to be 6453f3afc4785cbad82c05f6ceb4dabea0cb81a0",
        ),
        11 => {
            try std.testing.expectEqual(@as(usize, 27), argv.len);
            try std.testing.expectEqualStrings("--cert-identity-regex", argv[25]);
            return allocatedRunResult(
                allocator,
                1,
                "",
                "if any flags in the group [cert-identity cert-identity-regex signer-repo signer-workflow]",
            );
        },
        else => return error.UnexpectedFakeRunnerCall,
    }
}

const ProfileAuditAllocationFixture = struct {
    root: std.Io.Dir,
    temp_parent: std.Io.Dir,
    parent_environment: *const std.process.Environ.Map,
    inputs: Inputs,
    profile_name: []const u8,
    context: *FakeAuditContext,
    protocol: *const AuditProtocol,
};

fn expectOriginalFixtureInputs(fixture: *const ProfileAuditAllocationFixture) !void {
    const cases = [_]struct { path: []const u8, expected: []const u8 }{
        .{ .path = "inputs/gh.exe", .expected = tiny_gh_fixture },
        .{ .path = "inputs/pdfium.tgz", .expected = tiny_artifact_fixture },
        .{ .path = "inputs/bundle.jsonl", .expected = tiny_bundle_fixture },
        .{ .path = "inputs/root.jsonl", .expected = tiny_root_fixture },
    };
    for (cases) |case| {
        const bytes = try fixture.root.readFileAlloc(
            std.testing.io,
            case.path,
            std.testing.allocator,
            .limited(case.expected.len + 1),
        );
        defer std.testing.allocator.free(bytes);
        try std.testing.expectEqualStrings(case.expected, bytes);
    }
}

fn expectProfileAbsent(fixture: *const ProfileAuditAllocationFixture) !void {
    if (fixture.temp_parent.openDir(std.testing.io, fixture.profile_name, .{
        .iterate = true,
        .follow_symlinks = false,
    })) |leftover| {
        leftover.close(std.testing.io);
        return error.AuditProfileResidue;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }
}

fn exerciseProfileAuditAllocationFailure(
    allocator: std.mem.Allocator,
    fixture: *ProfileAuditAllocationFixture,
) anyerror!void {
    fixture.context.* = .{};
    const summary = runAuditWithProfile(
        allocator,
        std.testing.io,
        fixture.parent_environment,
        fixture.inputs,
        fixture.temp_parent,
        fixture.profile_name,
        fixture.protocol,
    ) catch |err| {
        try expectProfileAbsent(fixture);
        try expectOriginalFixtureInputs(fixture);
        return err;
    };
    try expectProfileAbsent(fixture);
    try expectOriginalFixtureInputs(fixture);
    try std.testing.expectEqual(@as(u16, 45), summary.subjects);
    try std.testing.expectEqual(@as(u16, 1), summary.matching_subjects);
    try std.testing.expectEqual(@as(usize, 1), fixture.context.executable_checks);
    try std.testing.expectEqual(@as(usize, 1), fixture.context.profile_guard_checks);
    try std.testing.expectEqual(@as(usize, 12), fixture.context.runner_calls);
}

fn checkAllAllocationFailuresAndOnePast(
    comptime test_fn: anytype,
    extra_args: anytype,
) !usize {
    var counting = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try @call(.auto, test_fn, .{counting.allocator()} ++ extra_args);
    const allocation_count = counting.alloc_index;
    try std.testing.expect(allocation_count > 0);
    try std.testing.expectEqual(counting.allocated_bytes, counting.freed_bytes);

    var one_past = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = allocation_count,
    });
    try @call(.auto, test_fn, .{one_past.allocator()} ++ extra_args);
    try std.testing.expect(!one_past.has_induced_failure);
    try std.testing.expectEqual(allocation_count, one_past.alloc_index);
    try std.testing.expectEqual(one_past.allocated_bytes, one_past.freed_bytes);

    try std.testing.checkAllAllocationFailures(std.testing.allocator, test_fn, extra_args);
    return allocation_count;
}

fn runProfileAuditAllocationFailureMatrix() !void {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "inputs");
    try tmp.dir.createDirPath(io, "audit-temp");
    try writePrivateFile(io, tmp.dir, "inputs/gh.exe", tiny_gh_fixture);
    try writePrivateFile(io, tmp.dir, "inputs/pdfium.tgz", tiny_artifact_fixture);
    try writePrivateFile(io, tmp.dir, "inputs/bundle.jsonl", tiny_bundle_fixture);
    try writePrivateFile(io, tmp.dir, "inputs/root.jsonl", tiny_root_fixture);

    const gh_path = try tmp.dir.realPathFileAlloc(io, "inputs/gh.exe", std.testing.allocator);
    defer std.testing.allocator.free(gh_path);
    const artifact_path = try tmp.dir.realPathFileAlloc(
        io,
        "inputs/pdfium.tgz",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(artifact_path);
    const bundle_path = try tmp.dir.realPathFileAlloc(
        io,
        "inputs/bundle.jsonl",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(bundle_path);
    const root_path = try tmp.dir.realPathFileAlloc(
        io,
        "inputs/root.jsonl",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(root_path);
    var temp_parent = try tmp.dir.openDir(io, "audit-temp", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer temp_parent.close(io);
    var environment = std.process.Environ.Map.init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("SystemRoot", "C:\\Windows");
    try environment.put("GH_TOKEN", "ambient-secret-must-not-propagate");
    try environment.put("PATH", "C:\\ambient\\bin");

    var random_bytes: [12]u8 = undefined;
    io.random(&random_bytes);
    const random_hex = std.fmt.bytesToHex(random_bytes, .lower);
    var profile_name_buffer: [64]u8 = undefined;
    const profile_name = try std.fmt.bufPrint(
        &profile_name_buffer,
        ".attestation-audit-{s}",
        .{random_hex},
    );
    var context: FakeAuditContext = .{};
    const protocol: AuditProtocol = .{
        .context = &context,
        .run_gh = fakeRunGh,
        .verify_locked_buffers = fakeVerifyLockedBuffers,
        .verify_executable = fakeVerifyExecutable,
        .validate_result = fakeValidateResult,
        .validate_mutated_root = fakeValidateMutatedRoot,
        .after_profile_created = fakeAfterProfileCreated,
        .after_profile_precheck = fakeAfterProfilePrecheck,
    };
    var fixture: ProfileAuditAllocationFixture = .{
        .root = tmp.dir,
        .temp_parent = temp_parent,
        .parent_environment = &environment,
        .inputs = .{
            .gh = gh_path,
            .artifact = artifact_path,
            .bundle = bundle_path,
            .trusted_root = root_path,
        },
        .profile_name = profile_name,
        .context = &context,
        .protocol = &protocol,
    };

    var rejected_protocol = protocol;
    rejected_protocol.verify_executable = fakeRejectExecutable;
    fixture.protocol = &rejected_protocol;
    context = .{};
    try std.testing.expectError(
        error.WrongGhAuthenticodeSubject,
        runAuditWithProfile(
            std.testing.allocator,
            io,
            &environment,
            fixture.inputs,
            temp_parent,
            profile_name,
            &rejected_protocol,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), context.runner_calls);
    try expectProfileAbsent(&fixture);
    try expectOriginalFixtureInputs(&fixture);

    var injected_protocol = protocol;
    injected_protocol.after_profile_precheck = fakeInjectAfterProfilePrecheck;
    fixture.protocol = &injected_protocol;
    context = .{};
    try std.testing.expectError(
        error.AccessDenied,
        runAuditWithProfile(
            std.testing.allocator,
            io,
            &environment,
            fixture.inputs,
            temp_parent,
            profile_name,
            &injected_protocol,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), context.runner_calls);
    try expectProfileAbsent(&fixture);
    try expectOriginalFixtureInputs(&fixture);

    fixture.protocol = &protocol;
    const allocation_count = try checkAllAllocationFailuresAndOnePast(
        exerciseProfileAuditAllocationFailure,
        .{&fixture},
    );
    std.debug.print("runProfileAudit allocation_count={d}\n", .{allocation_count});
}

test "verification arguments pin every identity dimension without regex fallback" {
    const inputs: Inputs = .{
        .gh = "C:\\locked\\gh.exe",
        .artifact = "C:\\locked\\pdfium.tgz",
        .bundle = "C:\\locked\\bundle.jsonl",
        .trusted_root = "C:\\locked\\root.jsonl",
    };
    const args = verificationArgs(inputs);
    try std.testing.expectEqual(@as(usize, 25), args.len);
    try std.testing.expectEqualStrings(inputs.artifact, args[VerificationArgIndex.artifact]);
    try std.testing.expectEqualStrings("bblanchon/pdfium-binaries", args[VerificationArgIndex.repository]);
    try std.testing.expectEqualStrings(inputs.bundle, args[VerificationArgIndex.bundle]);
    try std.testing.expectEqualStrings(inputs.trusted_root, args[VerificationArgIndex.trusted_root]);
    try std.testing.expectEqualStrings("--cert-identity", args[10]);
    try std.testing.expectEqualStrings(workflow_identity, args[VerificationArgIndex.certificate_identity]);
    try std.testing.expectEqualStrings("refs/heads/master", args[VerificationArgIndex.source_ref]);
    try std.testing.expectEqualStrings(source_digest, args[VerificationArgIndex.source_digest]);
    try std.testing.expectEqualStrings(source_digest, args[VerificationArgIndex.signer_digest]);
    try std.testing.expectEqualStrings("--deny-self-hosted-runners", args[22]);
    for (args) |arg| {
        try std.testing.expect(!std.mem.eql(u8, arg, "--cert-identity-regex"));
        try std.testing.expect(!std.mem.eql(u8, arg, "--signer-workflow"));
    }
}

test "version and scrubbed environment reject drift and omit ambient credentials" {
    // The attestation runner contract is Windows-specific: it validates the
    // locked `gh.exe` environment and Windows profile roots. Keep the parser
    // and evidence tests portable, but do not make a POSIX path spelling alter
    // this Windows-only environment oracle.
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    try validateGhVersion(gh_version_output, "");
    try std.testing.expectError(
        error.WrongGhVersion,
        validateGhVersion("gh version 2.99.0\n", ""),
    );

    var parent = std.process.Environ.Map.init(std.testing.allocator);
    defer parent.deinit();
    try parent.put("SystemRoot", "C:\\Windows");
    try parent.put("GH_TOKEN", "must-not-propagate");
    try parent.put("HTTPS_PROXY", "http://ambient.invalid");
    var clean = try scrubbedEnvironment(
        std.testing.allocator,
        &parent,
        "C:\\locked\\empty-profile",
    );
    defer clean.deinit();
    try std.testing.expect(clean.get("GH_TOKEN") == null);
    try std.testing.expect(clean.get("PATH") == null);
    try std.testing.expectEqualStrings(
        "http://127.0.0.1:9",
        clean.get("HTTPS_PROXY").?,
    );
    try std.testing.expectEqualStrings(
        "C:\\locked\\empty-profile",
        clean.get("GH_CONFIG_DIR").?,
    );
}

test "trusted-root negative substitutes a valid public key without damaging structure" {
    const mutated = try mutateTrustedRootPublicKey(
        std.testing.allocator,
        deps.locked_github_trusted_root_bytes,
    );
    defer std.testing.allocator.free(mutated);

    try std.testing.expectEqual(deps.locked_github_trusted_root_bytes.len, mutated.len);
    try std.testing.expect(!std.mem.eql(
        u8,
        deps.locked_github_trusted_root_bytes,
        mutated,
    ));
    try std.testing.expectEqual(
        @as(usize, 1),
        std.mem.count(u8, deps.locked_github_trusted_root_bytes, rekor_public_key),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        std.mem.count(u8, deps.locked_github_trusted_root_bytes, ctlog_public_key),
    );
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, mutated, rekor_public_key));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, mutated, ctlog_public_key));
    try deps.validateTrustedRootStructure(std.testing.allocator, mutated);
}

test "audit inputs require absolute paths without control characters" {
    const absolute = if (builtin.os.tag == .windows) "C:\\audit\\input" else "/audit/input";
    try verifyAbsolutePath(absolute);
    for ([_][]const u8{ "", ".zig-cache/input", "..\\input", "C:input" }) |path| {
        try std.testing.expectError(error.NonAbsoluteAuditInput, verifyAbsolutePath(path));
    }
    for ([_][]const u8{ "\x00", "\r", "\n" }) |control| {
        const path = try std.mem.concat(std.testing.allocator, u8, &.{ absolute, control });
        defer std.testing.allocator.free(path);
        try std.testing.expectError(error.NonAbsoluteAuditInput, verifyAbsolutePath(path));
    }
}

test "audit workspace requires an absolute temporary parent" {
    var environment = std.process.Environ.Map.init(std.testing.allocator);
    defer environment.deinit();
    try std.testing.expectError(error.MissingAuditTemp, auditTempParent(&environment));

    try environment.put("TEMP", "relative\\temp");
    try std.testing.expectError(error.InvalidAuditTemp, auditTempParent(&environment));

    try environment.put("TEMP", "C:\\Users\\tester\\AppData\\Local\\Temp");
    try std.testing.expectEqualStrings(
        "C:\\Users\\tester\\AppData\\Local\\Temp",
        try auditTempParent(&environment),
    );
}

test "audit profile name cannot escape or alias its checked parent" {
    try validateAuditProfileName(".attestation-audit-0123456789abcdef01234567");
    for ([_][]const u8{
        "",               ".",        "..",       "../escape",   "..\\escape", "C:escape",
        "profile:stream", "profile.", "profile ", "profile\x00", "profile\r",  "profile\n",
    }) |name| {
        try std.testing.expectError(error.InvalidAuditProfile, validateAuditProfileName(name));
    }
}

test "audit workspace permits shared TEMP ancestry but rejects actual overlap" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(
        io,
        "cache/.v2/github-cli/generations/g-111111111111111111111111/payload/bin",
    );
    try tmp.dir.createDirPath(
        io,
        "cache/.v2/pdfium-reference/generations/g-222222222222222222222222",
    );
    try tmp.dir.createDirPath(io, "evidence");
    try tmp.dir.createDirPath(io, "audit-temp");
    try writePrivateFile(
        io,
        tmp.dir,
        "cache/.v2/github-cli/generations/g-111111111111111111111111/payload/bin/gh.exe",
        "gh",
    );
    try writePrivateFile(
        io,
        tmp.dir,
        "cache/.v2/pdfium-reference/generations/g-222222222222222222222222/archive.bin",
        "pdf",
    );
    try writePrivateFile(io, tmp.dir, "evidence/bundle.jsonl", "bundle");
    try writePrivateFile(io, tmp.dir, "evidence/root.jsonl", "root");

    const root = try tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const cache_root = try std.fs.path.join(std.testing.allocator, &.{ root, "cache" });
    defer std.testing.allocator.free(cache_root);
    const inputs: Inputs = .{
        .gh = try std.fs.path.join(std.testing.allocator, &.{ root, "cache/.v2/github-cli/generations/g-111111111111111111111111/payload/bin/gh.exe" }),
        .artifact = try std.fs.path.join(std.testing.allocator, &.{ root, "cache/.v2/pdfium-reference/generations/g-222222222222222222222222/archive.bin" }),
        .bundle = try std.fs.path.join(std.testing.allocator, &.{ root, "evidence/bundle.jsonl" }),
        .trusted_root = try std.fs.path.join(std.testing.allocator, &.{ root, "evidence/root.jsonl" }),
    };
    defer std.testing.allocator.free(inputs.trusted_root);
    defer std.testing.allocator.free(inputs.bundle);
    defer std.testing.allocator.free(inputs.artifact);
    defer std.testing.allocator.free(inputs.gh);

    var safe_temp = try tmp.dir.openDir(io, "audit-temp", .{ .iterate = true });
    defer safe_temp.close(io);
    try validateAuditWorkspaceDisjoint(
        std.testing.allocator,
        io,
        safe_temp,
        ".attestation-audit-fixture",
        cache_root,
        inputs,
    );
    // Generated build-cache inputs and the private audit profile can be
    // siblings beneath TEMP; only the actual profile must remain disjoint.
    try validateAuditWorkspaceDisjoint(
        std.testing.allocator,
        io,
        tmp.dir,
        ".attestation-audit-fixture",
        cache_root,
        inputs,
    );
    try validateAuditWorkspaceDisjoint(
        std.testing.allocator,
        io,
        tmp.dir,
        "cache-sibling",
        cache_root,
        inputs,
    );
    // Reject equality with the cache and ancestry of locked evidence before
    // attempting CREATE, even though both names already exist in this fixture.
    for ([_][]const u8{ "cache", "evidence" }) |profile_name| {
        try std.testing.expectError(
            error.AuditTempOverlapsLockedInput,
            validateAuditWorkspaceDisjoint(
                std.testing.allocator,
                io,
                tmp.dir,
                profile_name,
                cache_root,
                inputs,
            ),
        );
    }

    var cache_temp = try tmp.dir.openDir(io, "cache", .{ .iterate = true });
    defer cache_temp.close(io);
    try std.testing.expectError(
        error.AuditTempOverlapsLockedInput,
        validateAuditWorkspaceDisjoint(
            std.testing.allocator,
            io,
            cache_temp,
            ".attestation-audit-fixture",
            cache_root,
            inputs,
        ),
    );

    var artifact_temp = try tmp.dir.openDir(
        io,
        "cache/.v2/pdfium-reference/generations/g-222222222222222222222222",
        .{ .iterate = true },
    );
    defer artifact_temp.close(io);
    try std.testing.expectError(
        error.AuditTempOverlapsLockedInput,
        validateAuditWorkspaceDisjoint(
            std.testing.allocator,
            io,
            artifact_temp,
            ".attestation-audit-fixture",
            cache_root,
            inputs,
        ),
    );
}

test "pinned snapshot handle denies same-owner rename and overwrite" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try writePrivateFile(io, tmp.dir, "locked.bin", "verified");
    const path = try tmp.dir.realPathFileAlloc(io, "locked.bin", std.testing.allocator);
    defer std.testing.allocator.free(path);
    const initial = try readNoFollowFileAlloc(std.testing.allocator, io, path, 8);
    defer std.testing.allocator.free(initial);
    try std.testing.expectEqualStrings("verified", initial);
    const pinned = try openPinnedFile(std.testing.allocator, io, path);
    defer pinned.close(io);

    if (tmp.dir.rename("locked.bin", tmp.dir, "moved.bin", io)) |_| {
        return error.PinnedSnapshotRenameAccepted;
    } else |err| switch (err) {
        error.AccessDenied, error.PermissionDenied, error.FileBusy => {},
        else => |unexpected| return unexpected,
    }
    if (tmp.dir.openFile(io, "locked.bin", .{
        .mode = .read_write,
        .allow_directory = false,
        .follow_symlinks = false,
    })) |writable| {
        writable.close(io);
        return error.PinnedSnapshotOverwriteAccepted;
    } else |err| switch (err) {
        error.AccessDenied, error.PermissionDenied, error.FileBusy => {},
        else => |unexpected| return unexpected,
    }

    const bytes = try readPinnedFileAlloc(std.testing.allocator, pinned, 8);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("verified", bytes);
}

test "private executable snapshot runs while final pin blocks writes and replacement" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const system_root = try std.testing.environ.getAlloc(allocator, "SystemRoot");
    defer allocator.free(system_root);
    const command_path = try std.fs.path.join(allocator, &.{ system_root, "System32", "cmd.exe" });
    defer allocator.free(command_path);
    const executable = try readNoFollowFileAlloc(allocator, io, command_path, 4 * 1024 * 1024);
    defer allocator.free(executable);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const directory_path = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(directory_path);
    const path = try std.fs.path.join(allocator, &.{ directory_path, "probe.exe" });
    defer allocator.free(path);
    const pinned = try createPinnedPrivateFile(allocator, io, path, executable);
    defer pinned.close(io);

    var environment = std.process.Environ.Map.init(allocator);
    defer environment.deinit();
    try environment.put("SystemRoot", system_root);
    const result = try std.process.run(allocator, io, .{
        .argv = &.{ path, "/d", "/c", "exit", "0" },
        .cwd = .{ .path = directory_path },
        .environ_map = &environment,
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(1024),
        .timeout = .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(10) } },
        .create_no_window = true,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try requireSuccessful(result.term, error.PinnedExecutableFailed);
    try std.testing.expectEqualStrings("", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);

    try expectDirectoryDaclWriteDenied(allocator, path);
    var written: u32 = 0;
    try std.testing.expectEqual(@as(i32, 0), WriteFile(pinned.handle, "X", 1, &written, null));
    try std.testing.expectEqual(std.os.windows.Win32Error.ACCESS_DENIED, std.os.windows.GetLastError());
    if (tmp.dir.openFile(io, "probe.exe", .{ .mode = .write_only })) |writable| {
        writable.close(io);
        return error.PinnedSnapshotOverwriteAccepted;
    } else |err| switch (err) {
        error.AccessDenied, error.PermissionDenied, error.FileBusy => {},
        else => return err,
    }
    if (tmp.dir.rename("probe.exe", tmp.dir, "moved.exe", io)) |_| {
        return error.PinnedSnapshotRenameAccepted;
    } else |err| switch (err) {
        error.AccessDenied, error.PermissionDenied, error.FileBusy => {},
        else => return err,
    }
    const retained = try readPinnedFileAlloc(allocator, pinned, executable.len + 1);
    defer allocator.free(retained);
    try std.testing.expectEqualSlices(u8, executable, retained);
}

test "audit workspace is atomically created with a protected current-owner ACL" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var profile = try createPrivateDirectory(
        std.testing.allocator,
        std.testing.io,
        tmp.dir,
        "profile",
    );
    try std.testing.expectEqual(
        std.Io.File.Kind.directory,
        (try profile.stat(std.testing.io)).kind,
    );
    profile.close(std.testing.io);
    if (createPrivateDirectory(
        std.testing.allocator,
        std.testing.io,
        tmp.dir,
        "profile",
    )) |existing| {
        existing.close(std.testing.io);
        return error.AuditProfileReused;
    } else |err| {
        try std.testing.expectEqual(error.AuditProfileAlreadyExists, err);
    }
    try tmp.dir.deleteDir(std.testing.io, "profile");
}

test "audit profile exact allowlist rejects injected entries" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    for (audit_profile_files) |name| try writePrivateFile(io, tmp.dir, name, "");
    try verifyAuditProfileLayout(io, tmp.dir);
    try writePrivateFile(io, tmp.dir, "ambient-config.yml", "malicious: true\n");
    try std.testing.expectError(
        error.UnexpectedAuditProfileEntry,
        verifyAuditProfileLayout(io, tmp.dir),
    );
}

test "current token SID does not match the built-in users group SID" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var advapi = try Advapi32.open();
    defer advapi.close();
    var current_sid = try currentUserSid(std.testing.allocator, &advapi);
    defer current_sid.deinit();
    var users_sid: ?*anyopaque = null;
    if (advapi.convert_string_to_sid(
        std.unicode.utf8ToUtf16LeStringLiteral("S-1-5-32-545"),
        &users_sid,
    ) == 0 or users_sid == null) return error.TestSidUnavailable;
    defer _ = LocalFree(users_sid);
    try std.testing.expect(advapi.equal_sid(current_sid.sid, users_sid.?) == 0);
}

test "held audit profile cannot be renamed or deleted before use" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var profile = try createPrivateDirectory(
        std.testing.allocator,
        io,
        tmp.dir,
        "profile",
    );
    if (tmp.dir.rename("profile", tmp.dir, "swapped", io)) |_| {
        profile.close(io);
        return error.AuditProfileRenameAccepted;
    } else |err| switch (err) {
        error.AccessDenied, error.PermissionDenied, error.FileBusy => {},
        else => |unexpected| {
            profile.close(io);
            return unexpected;
        },
    }
    if (tmp.dir.deleteDir(io, "profile")) |_| {
        profile.close(io);
        return error.AuditProfileDeleteAccepted;
    } else |err| switch (err) {
        error.AccessDenied, error.PermissionDenied, error.FileBusy => {},
        else => |unexpected| {
            profile.close(io);
            return unexpected;
        },
    }
    profile.close(io);
    try tmp.dir.deleteDir(io, "profile");
}

test "Authenticode identity rejects wrong subject and thumbprint" {
    try std.testing.expectError(
        error.WrongGhAuthenticodeSubject,
        requireGhAuthenticodeIdentity(
            "CN=GitHub Lookalike, O=GitHub, Inc., L=San Francisco, S=California, C=US",
            gh_authenticode_thumbprint_sha1,
        ),
    );
    try std.testing.expectError(
        error.WrongGhAuthenticodeThumbprint,
        requireGhAuthenticodeIdentity(
            gh_authenticode_subject,
            "3E3D67018EE2980D0C7910A24BB60E195E7068F2",
        ),
    );
}

test "catalog-only signed executable does not satisfy embedded signer requirement" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    const path = "C:\\Windows\\System32\\where.exe";
    const file = try openPinnedFile(std.testing.allocator, io, path);
    defer file.close(io);
    try std.testing.expectError(
        error.GhAuthenticodeVerificationFailed,
        verifyAuthenticodeSigner(std.testing.allocator, path, file),
    );
}

test "negative cases require a normal verifier rejection" {
    try requireGhRejection(
        .{ .exited = 1 },
        "",
        "locked diagnostic class",
        "locked diagnostic class",
        error.MutationAccepted,
    );
    try std.testing.expectError(
        error.UnexpectedGhRejection,
        requireGhRejection(
            .{ .exited = 1 },
            "unexpected stdout",
            "locked diagnostic class",
            "locked diagnostic class",
            error.MutationAccepted,
        ),
    );
    try std.testing.expectError(
        error.UnexpectedGhRejection,
        requireGhRejection(
            .{ .exited = 1 },
            "",
            "generic file error",
            "locked diagnostic class",
            error.MutationAccepted,
        ),
    );
    try std.testing.expectError(
        error.MutationAccepted,
        requireGhRejection(.{ .exited = 0 }, "", "", "locked", error.MutationAccepted),
    );
    try std.testing.expectError(
        error.UnexpectedGhFailureStatus,
        requireGhRejection(.{ .exited = 2 }, "", "", "locked", error.MutationAccepted),
    );
    try std.testing.expectError(
        error.UnexpectedGhTermination,
        requireGhRejection(.{ .unknown = 0xc000_0005 }, "", "", "locked", error.MutationAccepted),
    );
}

test "profile audit blocks owner DACL escalation and releases all state on allocation failure" {
    try runProfileAuditAllocationFailureMatrix();
}
