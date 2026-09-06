const std = @import("std");
const repro = @import("pdfium_reproduce");

const allocator = std.testing.allocator;

const valid_receipt =
    \\{
    \\  "schema_version": 1,
    \\  "receipt_kind": "texflow-pdfium-repro-toolchain",
    \\  "phase": "reproduce",
    \\  "status": "approved",
    \\  "target": "x86_64-windows-msvc",
    \\  "root": {
    \\    "path": "C:/repro",
    \\    "absolute": true,
    \\    "disposable": true,
    \\    "repository_disjoint": true,
    \\    "reparse_free": true,
    \\    "whitespace_free": true,
    \\    "free_space_bytes": 107374182400,
    \\    "physical_memory_bytes": 17179869184
    \\  },
    \\  "network": {
    \\    "mode": "none",
    \\    "detached_nic": true,
    \\    "fetch_bytes": 0,
    \\    "route_count": 0,
    \\    "proxy": "unset",
    \\    "process_policy": "zig-owned"
    \\  },
    \\  "pins": {
    \\    "pdfium_commit": "6f2272e1f3aaa141305475b83ef4eac2c1f527b8",
    \\    "pdfium_tree_sha256": "eb5b5b34b65e795379f55a3109cc31b843395e8e6be737b2d2c35f2725c2e499",
    \\    "reference_archive_sha256": "61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41",
    \\    "reference_dll_sha256": "ccfac1aad9e78624ebfb3f54f3f4ddb77af6db2f52803f150e2f9876beda49fe",
    \\    "recipe_commit": "5453f3afc4785cbad82c05f6ceb4dabea0cb81a0",
    \\    "recipe_archive_sha256": "00d9ef134460216465b19e11e59cf982dd1a4391d12be0f5ccf94466abcb84e6",
    \\    "depot_tools_commit": "a0fd6e66af74304c9b4605665435f4e88849e046",
    \\    "depot_tools_tree_sha1": "36d9263be5a52a8655d2c2bd63244019a96b3757"
    \\  },
    \\  "toolchain": {
    \\    "runner_image_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
    \\    "visual_studio_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
    \\    "windows_sdk_version": "10.0.28000.0",
    \\    "windows_sdk_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
    \\    "resolved_deps_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
    \\    "cipd_graph_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
    \\    "python_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
    \\    "git_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
    \\    "cipd_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
    \\    "clang_sha256": "9999999999999999999999999999999999999999999999999999999999999999",
    \\    "linker_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    \\    "gn_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    \\    "ninja_sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    \\  },
    \\  "gn_args": ["pdf_enable_v8=false", "pdf_enable_xfa=false"],
    \\  "wrappers": [
    \\    {"name": "vpython3.bat", "sha256": "1616161616161616161616161616161616161616161616161616161616161616"}
    \\  ],
    \\  "processes": [
    \\    {"role": "clang", "path": "C:/repro/tools/clang.exe", "sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"},
    \\    {"role": "cipd", "path": "C:/repro/tools/cipd.exe", "sha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"},
    \\    {"role": "git", "path": "C:/repro/tools/git.exe", "sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"},
    \\    {"role": "gn", "path": "C:/repro/tools/gn.exe", "sha256": "1212121212121212121212121212121212121212121212121212121212121212"},
    \\    {"role": "linker", "path": "C:/repro/tools/link.exe", "sha256": "1313131313131313131313131313131313131313131313131313131313131313"},
    \\    {"role": "ninja", "path": "C:/repro/tools/ninja.exe", "sha256": "1414141414141414141414141414141414141414141414141414141414141414"},
    \\    {"role": "python", "path": "C:/repro/tools/python.exe", "sha256": "1515151515151515151515151515151515151515151515151515151515151515"}
    \\  ]
    \\}
;

test "approved receipt validates the locked PDFium inputs" {
    var parsed = try repro.parseAndValidate(allocator, valid_receipt);
    defer parsed.deinit();
    try repro.requireApprovedReproduction(parsed.value);
    try std.testing.expectEqualStrings("x86_64-windows-msvc", parsed.value.target);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.wrappers.len);
}

test "receipt digest binds the exact bytes" {
    const first = repro.receiptDigest(valid_receipt);
    const second = repro.receiptDigest(valid_receipt ++ "\n");
    try std.testing.expect(!std.mem.eql(u8, &first, &second));
}

test "candidate resolve receipts are never reproduction admissions" {
    const candidate = std.mem.replaceOwned(u8, allocator, valid_receipt, "\"phase\": \"reproduce\"", "\"phase\": \"resolve\"") catch unreachable;
    defer allocator.free(candidate);
    const status_candidate = std.mem.replaceOwned(u8, allocator, candidate, "\"status\": \"approved\"", "\"status\": \"candidate\"") catch unreachable;
    defer allocator.free(status_candidate);
    var parsed = try repro.parseAndValidate(allocator, status_candidate);
    defer parsed.deinit();
    try std.testing.expectError(error.ReproductionNotApproved, repro.requireApprovedReproduction(parsed.value));
}

test "receipt rejects a community or wrong PDFium pin" {
    const mutated = std.mem.replaceOwned(u8, allocator, valid_receipt, "61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41", "71513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41") catch unreachable;
    defer allocator.free(mutated);
    try std.testing.expectError(error.LockedPinMismatch, repro.parseAndValidate(allocator, mutated));
}

test "reproduction receipt rejects any route proxy or fetch bytes" {
    const mutated = std.mem.replaceOwned(u8, allocator, valid_receipt, "\"route_count\": 0", "\"route_count\": 1") catch unreachable;
    defer allocator.free(mutated);
    try std.testing.expectError(error.NetworkIsolationUnverified, repro.parseAndValidate(allocator, mutated));
}

test "reproduction receipt admits only the exact GN feature set" {
    const mutated = std.mem.replaceOwned(u8, allocator, valid_receipt, "\"gn_args\": [\"pdf_enable_v8=false\", \"pdf_enable_xfa=false\"]", "\"gn_args\": [\"is_component_build=true\", \"pdf_enable_v8=false\", \"pdf_enable_xfa=false\"]") catch unreachable;
    defer allocator.free(mutated);
    try std.testing.expectError(error.UnexpectedGnArg, repro.parseAndValidate(allocator, mutated));
}

test "reproduction receipt binds process paths and digests to the policy" {
    const bad_path = std.mem.replaceOwned(u8, allocator, valid_receipt, "C:/repro/tools/clang.exe", "C:/other/tools/clang.exe") catch unreachable;
    defer allocator.free(bad_path);
    try std.testing.expectError(error.ProcessRootMismatch, repro.parseAndValidate(allocator, bad_path));

    const bad_digest = std.mem.replaceOwned(u8, allocator, valid_receipt, "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", "dededededededededededededededededededededededededededededededede") catch unreachable;
    defer allocator.free(bad_digest);
    try std.testing.expectError(error.ToolchainIdentityMismatch, repro.parseAndValidate(allocator, bad_digest));
}

test "approval revalidates a receipt value instead of trusting the caller" {
    var parsed = try repro.parseAndValidate(allocator, valid_receipt);
    defer parsed.deinit();
    parsed.value.network.route_count = 1;
    try std.testing.expectError(error.NetworkIsolationUnverified, repro.requireApprovedReproduction(parsed.value));
}

test "approved receipts require at least one hashed wrapper" {
    const mutated = std.mem.replaceOwned(u8, allocator, valid_receipt, "    {\"name\": \"vpython3.bat\", \"sha256\": \"1616161616161616161616161616161616161616161616161616161616161616\"}\n", "") catch unreachable;
    defer allocator.free(mutated);
    try std.testing.expectError(error.ProcessGraphMismatch, repro.parseAndValidate(allocator, mutated));
}

test "receipt rejects duplicate or unknown JSON fields" {
    const duplicate = std.mem.replaceOwned(u8, allocator, valid_receipt, "\"schema_version\": 1,", "\"schema_version\": 1,\"schema_version\": 1,") catch unreachable;
    defer allocator.free(duplicate);
    try std.testing.expectError(error.DuplicateField, repro.parseAndValidate(allocator, duplicate));

    const unknown = std.mem.replaceOwned(u8, allocator, valid_receipt, "\"schema_version\": 1,", "\"unknown\": true,\"schema_version\": 1,") catch unreachable;
    defer allocator.free(unknown);
    try std.testing.expectError(error.UnknownField, repro.parseAndValidate(allocator, unknown));
}
