const std = @import("std");
const deps = @import("deps");

const valid_api_response =
    \\{"attestations":[{"repository_id":103962638,"bundle_url":"https://tmaproduction.blob.core.windows.net/attestations/103962638/2026/08/31/44147842.json.sn?se=2026-09-04T13%3A00%3A00Z&sig=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA%3D&ske=2026-09-04T14%3A00%3A00Z&skoid=322a4be5-8e0b-4548-9b48-4e436a2c7c75&sks=b&skt=2026-09-04T11%3A00%3A00Z&sktid=398a6654-997b-47e9-b12b-9515b896b4de&skv=2026-06-06&sp=r&spr=https&sr=b&st=2026-09-04T11%3A30%3A00Z&sv=2026-06-06","initiator":"user"}]}
;

fn makeGhVerificationResult(allocator: std.mem.Allocator) ![]u8 {
    // The consumed metadata matches the pinned gh 2.100.0 output for the
    // locked PDFium bundle; the statement comes from that bundle itself.
    const statement = try deps.decodeDssePayload(
        allocator,
        deps.locked_pdfium_attestation_bytes,
    );
    defer allocator.free(statement);

    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    try output.writer.writeAll(
        "[{\"attestation\":{},\"verificationResult\":{" ++
            "\"mediaType\":\"application/vnd.dev.sigstore.verificationresult+json;version=0.1\"," ++
            "\"verifiedIdentity\":{" ++
            "\"subjectAlternativeName\":{\"subjectAlternativeName\":\"https://github.com/bblanchon/pdfium-binaries/.github/workflows/build-all.yml@refs/heads/master\"}," ++
            "\"issuer\":{\"issuer\":\"\",\"regexp\":\".*\"},\"runnerEnvironment\":\"github-hosted\"}," ++
            "\"signature\":{\"certificate\":{" ++
            "\"certificateIssuer\":\"CN=sigstore-intermediate,O=sigstore.dev\"," ++
            "\"subjectAlternativeName\":\"https://github.com/bblanchon/pdfium-binaries/.github/workflows/build-all.yml@refs/heads/master\"," ++
            "\"issuer\":\"https://token.actions.githubusercontent.com\"," ++
            "\"githubWorkflowTrigger\":\"workflow_dispatch\"," ++
            "\"githubWorkflowSHA\":\"5453f3afc4785cbad82c05f6ceb4dabea0cb81a0\"," ++
            "\"githubWorkflowName\":\"Build all\"," ++
            "\"githubWorkflowRepository\":\"bblanchon/pdfium-binaries\"," ++
            "\"githubWorkflowRef\":\"refs/heads/master\"," ++
            "\"buildSignerURI\":\"https://github.com/bblanchon/pdfium-binaries/.github/workflows/build-all.yml@refs/heads/master\"," ++
            "\"buildSignerDigest\":\"5453f3afc4785cbad82c05f6ceb4dabea0cb81a0\"," ++
            "\"sourceRepositoryURI\":\"https://github.com/bblanchon/pdfium-binaries\"," ++
            "\"sourceRepositoryIdentifier\":\"103962638\"," ++
            "\"sourceRepositoryRef\":\"refs/heads/master\"," ++
            "\"sourceRepositoryDigest\":\"5453f3afc4785cbad82c05f6ceb4dabea0cb81a0\"," ++
            "\"sourceRepositoryOwnerURI\":\"https://github.com/bblanchon\"," ++
            "\"sourceRepositoryOwnerIdentifier\":\"5462433\"," ++
            "\"buildConfigURI\":\"https://github.com/bblanchon/pdfium-binaries/.github/workflows/build-all.yml@refs/heads/master\"," ++
            "\"buildConfigDigest\":\"5453f3afc4785cbad82c05f6ceb4dabea0cb81a0\"," ++
            "\"buildTrigger\":\"workflow_dispatch\"," ++
            "\"sourceRepositoryVisibilityAtSigning\":\"public\"," ++
            "\"runnerEnvironment\":\"github-hosted\"," ++
            "\"runInvocationURI\":\"https://github.com/bblanchon/pdfium-binaries/actions/runs/33383157207/attempts/1\"}}," ++
            "\"verifiedTimestamps\":[{\"timestamp\":\"2026-08-31T13:30:09Z\",\"type\":\"Tlog\",\"uri\":\"https://rekor.sigstore.dev\"}]," ++
            "\"statement\":",
    );
    try output.writer.writeAll(statement);
    try output.writer.writeAll("}}]\n");
    return output.toOwnedSlice();
}

const json_injection_slack = "                                                                ";

fn withJsonInjectionSlack(
    allocator: std.mem.Allocator,
    json: []const u8,
) ![]u8 {
    return std.mem.concat(allocator, u8, &.{ json, json_injection_slack });
}

fn findObjectCloseAfterMarker(
    json: []const u8,
    marker: []const u8,
    occurrence: usize,
) !usize {
    var marker_end: usize = 0;
    if (marker.len != 0) {
        var search_start: usize = 0;
        var current: usize = 0;
        while (true) {
            const relative = std.mem.indexOf(u8, json[search_start..], marker) orelse
                return error.TestFixtureMarkerMissing;
            const marker_start = search_start + relative;
            if (current == occurrence) {
                marker_end = marker_start + marker.len;
                break;
            }
            current += 1;
            search_start = marker_start + marker.len;
        }
    }

    const open_relative = std.mem.indexOfScalar(u8, json[marker_end..], '{') orelse
        return error.TestFixtureObjectMissing;
    const open = marker_end + open_relative;
    var depth: usize = 0;
    var in_string = false;
    var escaped = false;
    for (json[open..], open..) |byte, index| {
        if (in_string) {
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') {
                in_string = false;
            }
            continue;
        }
        switch (byte) {
            '"' => in_string = true,
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if (depth == 0) return index;
            },
            else => {},
        }
    }
    return error.TestFixtureObjectUnterminated;
}

fn injectAmbientObjectFieldSameLength(
    allocator: std.mem.Allocator,
    padded_json: []const u8,
    marker: []const u8,
    occurrence: usize,
) ![]u8 {
    const member = ",\"ambient\":0";
    if (!std.mem.endsWith(u8, padded_json, json_injection_slack) or
        member.len > json_injection_slack.len)
    {
        return error.TestFixtureSlackMissing;
    }
    const logical_end = padded_json.len - json_injection_slack.len;
    const close = try findObjectCloseAfterMarker(
        padded_json[0..logical_end],
        marker,
        occurrence,
    );
    const changed = try allocator.dupe(u8, padded_json);
    std.mem.copyBackwards(
        u8,
        changed[close + member.len .. logical_end + member.len],
        changed[close..logical_end],
    );
    @memcpy(changed[close .. close + member.len], member);
    @memset(changed[logical_end + member.len ..], ' ');
    return changed;
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

    // Zig 0.16's checkAllAllocationFailures stops at allocation_count - 1.
    // Exercise the first non-failing index too, proving the success path is
    // deterministic and releases everything it owns.
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

fn exerciseAttestationApiResponse(
    allocator: std.mem.Allocator,
    response: []const u8,
) anyerror!void {
    const selected = try deps.validateAttestationApiResponse(
        allocator,
        response,
        "2026-09-04T12:00:00Z",
    );
    defer selected.deinit(allocator);
    try std.testing.expectEqualStrings(
        "/attestations/103962638/2026/08/31/44147842.json.sn",
        selected.path,
    );
}

fn exerciseRawSnappy(allocator: std.mem.Allocator) anyerror!void {
    const decoded = try deps.decodeRawSnappy(allocator, &.{ 1, 0, 'a' }, 1);
    defer allocator.free(decoded);
    try std.testing.expectEqualStrings("a", decoded);
}

fn exerciseDssePayload(allocator: std.mem.Allocator) anyerror!void {
    const statement = try deps.decodeDssePayload(
        allocator,
        deps.locked_pdfium_attestation_bytes,
    );
    defer allocator.free(statement);
    try std.testing.expect(statement.len > 0);
}

fn exerciseSlsaStatement(
    allocator: std.mem.Allocator,
    statement: []const u8,
) anyerror!void {
    const summary = try deps.validateSlsaStatement(allocator, statement);
    try std.testing.expectEqual(@as(u16, 45), summary.subjects);
    try std.testing.expectEqual(@as(u16, 1), summary.matching_subjects);
}

fn exerciseTrustedRoot(allocator: std.mem.Allocator) anyerror!void {
    try deps.validateTrustedRootStructure(
        allocator,
        deps.locked_github_trusted_root_bytes,
    );
}

fn exercisePdfiumEvidence(allocator: std.mem.Allocator) anyerror!void {
    const summary = try deps.validatePdfiumEvidence(
        allocator,
        deps.locked_pdfium_attestation_bytes,
        deps.locked_github_trusted_root_bytes,
    );
    try std.testing.expectEqual(@as(u16, 45), summary.subjects);
    try std.testing.expectEqual(@as(u16, 1), summary.matching_subjects);
}

fn exerciseGhVerificationResult(
    allocator: std.mem.Allocator,
    result: []const u8,
) anyerror!void {
    const summary = try deps.validateGhVerificationResult(allocator, result);
    try std.testing.expectEqual(@as(u16, 45), summary.subjects);
    try std.testing.expectEqual(@as(u16, 1), summary.matching_subjects);
}

test "attestation API response handles every allocation failure" {
    _ = try checkAllAllocationFailuresAndOnePast(
        exerciseAttestationApiResponse,
        .{valid_api_response},
    );
}

test "raw Snappy handles every allocation failure" {
    _ = try checkAllAllocationFailuresAndOnePast(exerciseRawSnappy, .{});
}

test "DSSE payload handles every allocation failure" {
    _ = try checkAllAllocationFailuresAndOnePast(exerciseDssePayload, .{});
}

test "SLSA statement handles every allocation failure" {
    const statement = try deps.decodeDssePayload(
        std.testing.allocator,
        deps.locked_pdfium_attestation_bytes,
    );
    defer std.testing.allocator.free(statement);
    _ = try checkAllAllocationFailuresAndOnePast(exerciseSlsaStatement, .{statement});
}

test "trusted-root validation handles every allocation failure" {
    _ = try checkAllAllocationFailuresAndOnePast(exerciseTrustedRoot, .{});
}

test "PDFium evidence handles every allocation failure" {
    _ = try checkAllAllocationFailuresAndOnePast(exercisePdfiumEvidence, .{});
}

test "GitHub verification result handles every allocation failure" {
    const result = try makeGhVerificationResult(std.testing.allocator);
    defer std.testing.allocator.free(result);
    _ = try checkAllAllocationFailuresAndOnePast(exerciseGhVerificationResult, .{result});
}

test "raw Snappy decodes literals and bounded overlapping copies" {
    const literal = [_]u8{ 5, 16, 'h', 'e', 'l', 'l', 'o' };
    const decoded_literal = try deps.decodeRawSnappy(
        std.testing.allocator,
        &literal,
        64,
    );
    defer std.testing.allocator.free(decoded_literal);
    try std.testing.expectEqualStrings("hello", decoded_literal);

    const overlapping = [_]u8{ 6, 0, 'a', 5, 1 };
    const decoded_copy = try deps.decodeRawSnappy(
        std.testing.allocator,
        &overlapping,
        64,
    );
    defer std.testing.allocator.free(decoded_copy);
    try std.testing.expectEqualStrings("aaaaaa", decoded_copy);
}

test "raw Snappy rejects malformed length varints" {
    try std.testing.expectError(
        error.TruncatedSnappyVarint,
        deps.decodeRawSnappy(std.testing.allocator, &.{0x80}, 64),
    );
    try std.testing.expectError(
        error.OverlongSnappyVarint,
        deps.decodeRawSnappy(
            std.testing.allocator,
            &.{ 0x80, 0x80, 0x80, 0x80, 0x80, 0 },
            64,
        ),
    );
    try std.testing.expectError(
        error.SnappyOutputLimitExceeded,
        deps.decodeRawSnappy(std.testing.allocator, &.{0x7f}, 32),
    );
}

test "raw Snappy rejects zero, backward, and out-of-range copies" {
    try std.testing.expectError(
        error.InvalidSnappyCopy,
        deps.decodeRawSnappy(
            std.testing.allocator,
            &.{ 5, 0, 'a', 1, 0 },
            64,
        ),
    );
    try std.testing.expectError(
        error.InvalidSnappyCopy,
        deps.decodeRawSnappy(
            std.testing.allocator,
            &.{ 5, 0, 'a', 1, 2 },
            64,
        ),
    );
    try std.testing.expectError(
        error.InvalidSnappyCopy,
        deps.decodeRawSnappy(
            std.testing.allocator,
            &.{ 5, 0, 'a', 2, 0xff, 0xff },
            64,
        ),
    );
}

test "raw Snappy rejects literal, output, and trailing-byte overflow" {
    try std.testing.expectError(
        error.TruncatedSnappyLiteral,
        deps.decodeRawSnappy(std.testing.allocator, &.{ 4, 12, 'a' }, 64),
    );
    try std.testing.expectError(
        error.SnappyOutputOverflow,
        deps.decodeRawSnappy(
            std.testing.allocator,
            &.{ 2, 0, 'a', 5, 1 },
            64,
        ),
    );
    try std.testing.expectError(
        error.TrailingSnappyData,
        deps.decodeRawSnappy(
            std.testing.allocator,
            &.{ 1, 0, 'a', 0 },
            64,
        ),
    );
}

test "locked raw-Snappy transport expands to the committed one-LF JSONL" {
    const transport_sha256 = "ae84cc3ca94398519f7f67bdd33a7d29f589a74d88734f544efa815e1f39046c";
    try std.testing.expectEqual(@as(usize, 17_297), deps.locked_pdfium_snappy_bytes.len);
    try deps.verifySha256(deps.locked_pdfium_snappy_bytes, transport_sha256);

    const changed_transport = try std.testing.allocator.dupe(
        u8,
        deps.locked_pdfium_snappy_bytes,
    );
    defer std.testing.allocator.free(changed_transport);
    changed_transport[changed_transport.len / 2] ^= 1;
    try std.testing.expectError(
        error.DigestMismatch,
        deps.verifySha256(changed_transport, transport_sha256),
    );

    const decoded = try deps.decodeRawSnappy(
        std.testing.allocator,
        deps.locked_pdfium_snappy_bytes,
        18_095,
    );
    defer std.testing.allocator.free(decoded);

    try std.testing.expectEqual(@as(usize, 18_095), decoded.len);
    try std.testing.expectEqual(@as(usize, 18_096), deps.locked_pdfium_attestation_bytes.len);
    try std.testing.expectEqualSlices(
        u8,
        decoded,
        deps.locked_pdfium_attestation_bytes[0..decoded.len],
    );
    try std.testing.expectEqual(@as(u8, '\n'), deps.locked_pdfium_attestation_bytes[decoded.len]);
}

test "locked PDFium bundle and trusted roots pass exact evidence validation" {
    const summary = try deps.validatePdfiumEvidence(
        std.testing.allocator,
        deps.locked_pdfium_attestation_bytes,
        deps.locked_github_trusted_root_bytes,
    );
    try std.testing.expectEqual(@as(u16, 45), summary.subjects);
    try std.testing.expectEqual(@as(u16, 1), summary.matching_subjects);

    const changed_bundle = try std.testing.allocator.dupe(
        u8,
        deps.locked_pdfium_attestation_bytes,
    );
    defer std.testing.allocator.free(changed_bundle);
    changed_bundle[100] ^= 1;
    try std.testing.expectError(
        error.EvidenceDigestMismatch,
        deps.validatePdfiumEvidence(
            std.testing.allocator,
            changed_bundle,
            deps.locked_github_trusted_root_bytes,
        ),
    );

    const changed_root = try std.testing.allocator.dupe(
        u8,
        deps.locked_github_trusted_root_bytes,
    );
    defer std.testing.allocator.free(changed_root);
    changed_root[100] ^= 1;
    try std.testing.expectError(
        error.EvidenceDigestMismatch,
        deps.validatePdfiumEvidence(
            std.testing.allocator,
            deps.locked_pdfium_attestation_bytes,
            changed_root,
        ),
    );
}

test "GitHub CLI 2.100.0 verification result binds certificate timestamp and statement" {
    const result = try makeGhVerificationResult(std.testing.allocator);
    defer std.testing.allocator.free(result);

    const summary = try deps.validateGhVerificationResult(
        std.testing.allocator,
        result,
    );
    try std.testing.expectEqual(@as(u16, 45), summary.subjects);
    try std.testing.expectEqual(@as(u16, 1), summary.matching_subjects);
}

test "GitHub CLI verification result rejects identity timestamp and multiplicity drift" {
    const result = try makeGhVerificationResult(std.testing.allocator);
    defer std.testing.allocator.free(result);

    const self_hosted = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        result,
        "\"runnerEnvironment\":\"github-hosted\"",
        "\"runnerEnvironment\":\"self-hosted\"",
    );
    defer std.testing.allocator.free(self_hosted);
    try std.testing.expectError(
        error.WrongGhCertificateIdentity,
        deps.validateGhVerificationResult(std.testing.allocator, self_hosted),
    );

    const wrong_timestamp = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        result,
        "2026-08-31T13:30:09Z",
        "2026-08-31T20:30:10+07:00",
    );
    defer std.testing.allocator.free(wrong_timestamp);
    try std.testing.expectError(
        error.WrongVerifiedTimestamp,
        deps.validateGhVerificationResult(std.testing.allocator, wrong_timestamp),
    );

    const duplicate = try std.mem.concat(
        std.testing.allocator,
        u8,
        &.{ result[0 .. result.len - 2], ",", result[1..] },
    );
    defer std.testing.allocator.free(duplicate);
    try std.testing.expectError(
        error.WrongGhVerificationResultCount,
        deps.validateGhVerificationResult(std.testing.allocator, duplicate),
    );

    const missing_timestamp = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        result,
        "[{\"timestamp\":\"2026-08-31T13:30:09Z\",\"type\":\"Tlog\",\"uri\":\"https://rekor.sigstore.dev\"}]",
        "[]",
    );
    defer std.testing.allocator.free(missing_timestamp);
    try std.testing.expectError(
        error.WrongVerifiedTimestamp,
        deps.validateGhVerificationResult(std.testing.allocator, missing_timestamp),
    );
}

test "GitHub CLI verified timestamp accepts equivalent RFC3339 time zones" {
    const result = try makeGhVerificationResult(std.testing.allocator);
    defer std.testing.allocator.free(result);
    const equivalent = [_][]const u8{
        "2026-08-31T13:30:09Z",
        "2026-08-31T13:30:09+00:00",
        "2026-08-31T20:30:09+07:00",
        "2026-08-31T08:00:09-05:30",
        "2026-09-01T03:30:09+14:00",
        "2026-08-30T23:30:09-14:00",
    };
    for (equivalent) |timestamp| {
        const changed = try std.mem.replaceOwned(u8, std.testing.allocator, result, "2026-08-31T13:30:09Z", timestamp);
        defer std.testing.allocator.free(changed);
        const summary = try deps.validateGhVerificationResult(std.testing.allocator, changed);
        try std.testing.expectEqual(@as(u16, 45), summary.subjects);
        try std.testing.expectEqual(@as(u16, 1), summary.matching_subjects);
    }
}

test "GitHub CLI verified timestamp rejects instant drift and noncanonical forms" {
    const result = try makeGhVerificationResult(std.testing.allocator);
    defer std.testing.allocator.free(result);
    const invalid = [_][]const u8{
        "2026-08-31T13:30:08Z",
        "2026-08-31T13:30:10Z",
        "2026-08-31T20:30:09+06:00",
        "2026-08-31T20:30:09+07:01",
        "2026-08-31T20:30:09-07:00",
        "2026-08-31T13:30:09-00:00",
        "2026-08-31T13:30:09+24:00",
        "2026-08-31T13:30:09+00:60",
        "2026-08-31T13:30:09+0a:00",
        "2026-08-31T13:30:09+00:a0",
        "2026-08-31T13:30:09+0000",
        "2026-08-31T13:30:09+00",
        "2026-08-31T13:30:09+00:00:00",
        "2026-08-31T13:30:09.000Z",
        "2026-08-31T13:30:09.1+00:00",
        "2026-08-31T13:30:09",
        "2026-08-31T13:30:09z",
        "2026-08-31t13:30:09Z",
        "2026-08-31 13:30:09Z",
        "2026-08-31T24:30:09Z",
        "2026-08-31T13:60:09Z",
        "2026-08-31T13:30:60Z",
        "2026-02-29T13:30:09Z",
        "2026-00-31T13:30:09Z",
        "2026-08-00T13:30:09Z",
        "2026-08-31T13:30:09Zjunk",
        "",
    };
    for (invalid) |timestamp| {
        const changed = try std.mem.replaceOwned(u8, std.testing.allocator, result, "2026-08-31T13:30:09Z", timestamp);
        defer std.testing.allocator.free(changed);
        try std.testing.expectError(error.WrongVerifiedTimestamp, deps.validateGhVerificationResult(std.testing.allocator, changed));
    }
}

test "GitHub CLI verification result rejects unknown fields in every consumed object" {
    const result = try makeGhVerificationResult(std.testing.allocator);
    defer std.testing.allocator.free(result);
    const padded = try withJsonInjectionSlack(std.testing.allocator, result);
    defer std.testing.allocator.free(padded);
    _ = try deps.validateGhVerificationResult(std.testing.allocator, padded);

    const cases = [_]struct {
        marker: []const u8,
        occurrence: usize = 0,
    }{
        .{ .marker = "[" },
        .{ .marker = "\"verificationResult\":" },
        .{ .marker = "\"verifiedIdentity\":" },
        .{ .marker = "\"subjectAlternativeName\":" },
        .{ .marker = "\"issuer\":" },
        .{ .marker = "\"signature\":" },
        .{ .marker = "\"certificate\":" },
        .{ .marker = "\"verifiedTimestamps\":[" },
    };
    for (cases) |case| {
        const changed = try injectAmbientObjectFieldSameLength(
            std.testing.allocator,
            padded,
            case.marker,
            case.occurrence,
        );
        defer std.testing.allocator.free(changed);
        try std.testing.expectEqual(padded.len, changed.len);
        try std.testing.expectError(
            error.UnknownGhVerificationField,
            deps.validateGhVerificationResult(std.testing.allocator, changed),
        );
    }
}

test "GitHub CLI 2.100.0 rejects changed and non-string metadata values" {
    const allocator = std.testing.allocator;
    const result = try makeGhVerificationResult(allocator);
    defer allocator.free(result);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result, .{});
    defer parsed.deinit();
    const verification = parsed.value.array.items[0].object.get("verificationResult").?.object;
    const certificate = verification.get("signature").?.object.get("certificate").?.object;
    const identity = verification.get("verifiedIdentity").?.object;
    const identity_san = identity.get("subjectAlternativeName").?.object;
    const identity_issuer = identity.get("issuer").?.object;
    for ([_]std.json.ObjectMap{ certificate, identity_san, identity_issuer }) |object| {
        for (object.values()) |*value| {
            try expectGhMetadataValueRejected(parsed.value, value, error.WrongGhCertificateIdentity);
        }
    }
    try expectGhMetadataValueRejected(
        parsed.value,
        identity.getPtr("runnerEnvironment").?,
        error.WrongGhCertificateIdentity,
    );
    try expectGhMetadataValueRejected(
        parsed.value,
        verification.getPtr("mediaType").?,
        error.InvalidGhVerificationResult,
    );
}

fn expectGhMetadataValueRejected(
    result: std.json.Value,
    value: *std.json.Value,
    expected_error: anyerror,
) !void {
    const original = value.*;
    defer value.* = original;
    for ([_]std.json.Value{ .{ .string = "untrusted" }, .null }) |replacement| {
        value.* = replacement;
        const changed = try std.json.Stringify.valueAlloc(std.testing.allocator, result, .{});
        defer std.testing.allocator.free(changed);
        try std.testing.expectError(
            expected_error,
            deps.validateGhVerificationResult(std.testing.allocator, changed),
        );
    }
}

test "SLSA statement rejects wrong predicate, subject, and workflow identity" {
    const statement = try deps.decodeDssePayload(
        std.testing.allocator,
        deps.locked_pdfium_attestation_bytes,
    );
    defer std.testing.allocator.free(statement);
    _ = try deps.validateSlsaStatement(std.testing.allocator, statement);

    const wrong_predicate = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        statement,
        "https://slsa.dev/provenance/v1",
        "https://slsa.dev/provenance/v0",
    );
    defer std.testing.allocator.free(wrong_predicate);
    try std.testing.expectError(
        error.WrongPredicateType,
        deps.validateSlsaStatement(std.testing.allocator, wrong_predicate),
    );

    const missing_subject = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        statement,
        "pdfium-win-x64.tgz",
        "pdfium-win-x65.tgz",
    );
    defer std.testing.allocator.free(missing_subject);
    try std.testing.expectError(
        error.MissingMatchingSubject,
        deps.validateSlsaStatement(std.testing.allocator, missing_subject),
    );

    const duplicate_name = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        statement,
        "pdfium-android-arm.tgz",
        "pdfium-win-x64.tgz",
    );
    defer std.testing.allocator.free(duplicate_name);
    const duplicate_subject = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        duplicate_name,
        "a0f2fb18cf065f246d2c4ef4b89c0cc07218a0a69d08bda97f0297c7f8b7ec09",
        "61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41",
    );
    defer std.testing.allocator.free(duplicate_subject);
    try std.testing.expectError(
        error.DuplicateMatchingSubject,
        deps.validateSlsaStatement(std.testing.allocator, duplicate_subject),
    );

    const wrong_workflow = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        statement,
        "bblanchon/pdfium-binaries",
        "attackerxx/pdfium-binaries",
    );
    defer std.testing.allocator.free(wrong_workflow);
    try std.testing.expectError(
        error.WrongWorkflowIdentity,
        deps.validateSlsaStatement(std.testing.allocator, wrong_workflow),
    );
}

test "SLSA statement rejects unknown fields in every consumed object" {
    const statement = try deps.decodeDssePayload(
        std.testing.allocator,
        deps.locked_pdfium_attestation_bytes,
    );
    defer std.testing.allocator.free(statement);
    const padded = try withJsonInjectionSlack(std.testing.allocator, statement);
    defer std.testing.allocator.free(padded);
    _ = try deps.validateSlsaStatement(std.testing.allocator, padded);

    const cases = [_]struct {
        marker: []const u8,
        occurrence: usize = 0,
    }{
        .{ .marker = "" },
        .{ .marker = "\"subject\":[" },
        .{ .marker = "\"digest\":" },
        .{ .marker = "\"predicate\":" },
        .{ .marker = "\"buildDefinition\":" },
        .{ .marker = "\"externalParameters\":" },
        .{ .marker = "\"workflow\":" },
        .{ .marker = "\"internalParameters\":" },
        .{ .marker = "\"github\":" },
        .{ .marker = "\"resolvedDependencies\":[" },
        .{ .marker = "\"digest\":", .occurrence = 45 },
        .{ .marker = "\"runDetails\":" },
        .{ .marker = "\"builder\":" },
        .{ .marker = "\"metadata\":" },
    };
    for (cases) |case| {
        const changed = try injectAmbientObjectFieldSameLength(
            std.testing.allocator,
            padded,
            case.marker,
            case.occurrence,
        );
        defer std.testing.allocator.free(changed);
        try std.testing.expectEqual(padded.len, changed.len);
        try std.testing.expectError(
            error.UnknownSlsaField,
            deps.validateSlsaStatement(std.testing.allocator, changed),
        );
    }
}

test "SLSA statement binds previously ignored workflow values" {
    const statement = try deps.decodeDssePayload(
        std.testing.allocator,
        deps.locked_pdfium_attestation_bytes,
    );
    defer std.testing.allocator.free(statement);

    const cases = [_]struct { needle: []const u8, replacement: []const u8 }{
        .{
            .needle = "\"event_name\":\"workflow_dispatch\"",
            .replacement = "\"event_name\":\"workflow_dispatcg\"",
        },
        .{
            .needle = "\"repository_owner_id\":\"5462433\"",
            .replacement = "\"repository_owner_id\":\"5462434\"",
        },
        .{
            .needle = "git+https://github.com/bblanchon/pdfium-binaries@refs/heads/master",
            .replacement = "git+https://github.com/bblanchon/pdfium-binaries@refs/heads/mastes",
        },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.needle.len, case.replacement.len);
        const changed = try std.mem.replaceOwned(
            u8,
            std.testing.allocator,
            statement,
            case.needle,
            case.replacement,
        );
        defer std.testing.allocator.free(changed);
        try std.testing.expectEqual(statement.len, changed.len);
        try std.testing.expect(!std.mem.eql(u8, statement, changed));
        try std.testing.expectError(
            error.WrongWorkflowIdentity,
            deps.validateSlsaStatement(std.testing.allocator, changed),
        );
    }
}

test "trusted-root JSONL rejects missing, duplicate, and malformed roots" {
    try deps.validateTrustedRootStructure(
        std.testing.allocator,
        deps.locked_github_trusted_root_bytes,
    );

    const first_lf = std.mem.indexOfScalar(
        u8,
        deps.locked_github_trusted_root_bytes,
        '\n',
    ).?;
    const first_line = deps.locked_github_trusted_root_bytes[0 .. first_lf + 1];
    try std.testing.expectError(
        error.WrongTrustedRootCount,
        deps.validateTrustedRootStructure(std.testing.allocator, first_line),
    );

    const duplicate = try std.mem.concat(
        std.testing.allocator,
        u8,
        &.{ first_line, first_line },
    );
    defer std.testing.allocator.free(duplicate);
    try std.testing.expectError(
        error.DuplicateTrustedRoot,
        deps.validateTrustedRootStructure(std.testing.allocator, duplicate),
    );

    try std.testing.expectError(
        error.WrongTrustedRootMediaType,
        deps.validateTrustedRootStructure(
            std.testing.allocator,
            "{\"mediaType\":\"wrong\"}\n{}\n",
        ),
    );
}

test "attestation API accepts one bounded exact-repository result" {
    const selected = try deps.validateAttestationApiResponse(
        std.testing.allocator,
        valid_api_response,
        "2026-09-04T12:00:00Z",
    );
    defer selected.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(
        "/attestations/103962638/2026/08/31/44147842.json.sn",
        selected.path,
    );
}

test "attestation API rejects oversized, duplicate, and unknown results" {
    const oversized = try std.testing.allocator.alloc(u8, 64 * 1024 + 1);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, 'x');
    try std.testing.expectError(
        error.AttestationApiResponseTooLarge,
        deps.validateAttestationApiResponse(
            std.testing.allocator,
            oversized,
            "2026-09-04T12:00:00Z",
        ),
    );

    const duplicate = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_api_response,
        "]}",
        ",{" ++
            "\"repository_id\":103962638," ++
            "\"bundle_url\":\"https://example.invalid/duplicate\"," ++
            "\"initiator\":\"user\"}]}",
    );
    defer std.testing.allocator.free(duplicate);
    try std.testing.expectError(
        error.WrongAttestationResultCount,
        deps.validateAttestationApiResponse(
            std.testing.allocator,
            duplicate,
            "2026-09-04T12:00:00Z",
        ),
    );

    const unknown = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_api_response,
        "\"initiator\":\"user\"",
        "\"initiator\":\"user\",\"token\":\"ambient\"",
    );
    defer std.testing.allocator.free(unknown);
    try std.testing.expectError(
        error.UnknownField,
        deps.validateAttestationApiResponse(
            std.testing.allocator,
            unknown,
            "2026-09-04T12:00:00Z",
        ),
    );
}

test "attestation API rejects wrong repository, host, path, and query" {
    const cases = [_]struct { needle: []const u8, replacement: []const u8, expected: anyerror }{
        .{ .needle = "103962638", .replacement = "103962639", .expected = error.WrongRepositoryId },
        .{ .needle = "tmaproduction.blob.core.windows.net", .replacement = "example.invalid", .expected = error.UnapprovedBundleHost },
        .{ .needle = "44147842.json.sn", .replacement = "44147842.zip", .expected = error.UnapprovedBundlePath },
        .{ .needle = "spr=https", .replacement = "spr=http", .expected = error.UnapprovedBundleQuery },
        .{ .needle = "&sv=2026-06-06", .replacement = "&sv=2026-06-06&sv=2026-06-06", .expected = error.DuplicateBundleQueryField },
    };
    for (cases) |case| {
        const changed = try std.mem.replaceOwned(
            u8,
            std.testing.allocator,
            valid_api_response,
            case.needle,
            case.replacement,
        );
        defer std.testing.allocator.free(changed);
        try std.testing.expectError(
            case.expected,
            deps.validateAttestationApiResponse(
                std.testing.allocator,
                changed,
                "2026-09-04T12:00:00Z",
            ),
        );
    }
}

test "attestation API rejects expired and malformed signed URLs" {
    try std.testing.expectError(
        error.ExpiredBundleUrl,
        deps.validateAttestationApiResponse(
            std.testing.allocator,
            valid_api_response,
            "2026-09-04T15:00:00Z",
        ),
    );

    const malformed = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        valid_api_response,
        "2026-09-04T13%3A00%3A00Z",
        "2026-99-99T99%3A99%3A99Z",
    );
    defer std.testing.allocator.free(malformed);
    try std.testing.expectError(
        error.MalformedBundleUrl,
        deps.validateAttestationApiResponse(
            std.testing.allocator,
            malformed,
            "2026-09-04T12:00:00Z",
        ),
    );
}
