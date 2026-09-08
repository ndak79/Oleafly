//! Offline schema validator plus the fail-closed hosted PDFium controller.
//!
//! The legacy schema below remains available to the existing offline tests. It
//! is deliberately not accepted by the hosted controller: the controller has
//! its own receipt, live GitHub identity checks, runner-control-plane network
//! attestation, and direct GN/Ninja process graph.
const builtin = @import("builtin");
const std = @import("std");
const source_unicode = @import("source_unicode.zig");

pub const max_receipt_bytes: usize = 64 * 1024;
pub const minimum_repro_disk_bytes: u64 = 100 * 1024 * 1024 * 1024;
pub const minimum_repro_memory_bytes: u64 = 16 * 1024 * 1024 * 1024;

// These source/toolchain values are policy fixtures for the receipt schema.
// They are not independent rebuild or hosted-runner evidence.
pub const locked_pdfium_commit = "6f2272e1f3aaa141305475b83ef4eac2c1f527b8";
pub const locked_pdfium_tree_sha256 = "eb5b5b34b65e795379f55a3109cc31b843395e8e6be737b2d2c35f2725c2e499";
pub const locked_reference_archive_sha256 = "61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41";
pub const locked_reference_dll_sha256 = "ccfac1aad9e78624ebfb3f54f3f4ddb77af6db2f52803f150e2f9876beda49fe";
pub const locked_recipe_commit = "5453f3afc4785cbad82c05f6ceb4dabea0cb81a0";
pub const locked_recipe_archive_sha256 = "00d9ef134460216465b19e11e59cf982dd1a4391d12be0f5ccf94466abcb84e6";
pub const locked_depot_tools_commit = "a0fd6e66af74304c9b4605665435f4e88849e046";
pub const locked_depot_tools_tree_sha1 = "36d9263be5a52a8655d2c2bd63244019a96b3757";
// These identity digests are policy fixtures for this contract. They are not
// upstream or hosted-runner evidence; an authorized reconstruction slice must
// replace them with reviewed, independently measured values before admission.
const locked_runner_image_sha256 = "1111111111111111111111111111111111111111111111111111111111111111";
const locked_visual_studio_sha256 = "2222222222222222222222222222222222222222222222222222222222222222";
const locked_windows_sdk_sha256 = "3333333333333333333333333333333333333333333333333333333333333333";
const locked_resolved_deps_sha256 = "4444444444444444444444444444444444444444444444444444444444444444";
const locked_cipd_graph_sha256 = "5555555555555555555555555555555555555555555555555555555555555555";
const locked_python_sha256 = "6666666666666666666666666666666666666666666666666666666666666666";
const locked_git_sha256 = "7777777777777777777777777777777777777777777777777777777777777777";
const locked_cipd_sha256 = "8888888888888888888888888888888888888888888888888888888888888888";
const locked_clang_sha256 = "9999999999999999999999999999999999999999999999999999999999999999";
const locked_linker_sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const locked_gn_sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const locked_ninja_sha256 = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
const locked_wrapper_sha256 = "1616161616161616161616161616161616161616161616161616161616161616";
const locked_process_sha256 = [_][]const u8{
    "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    "1212121212121212121212121212121212121212121212121212121212121212",
    "1313131313131313131313131313131313131313131313131313131313131313",
    "1414141414141414141414141414141414141414141414141414141414141414",
    "1515151515151515151515151515151515151515151515151515151515151515",
};

pub const Receipt = struct {
    schema_version: u16,
    receipt_kind: []const u8,
    phase: []const u8,
    status: []const u8,
    target: []const u8,
    root: RootPolicy,
    network: NetworkPolicy,
    pins: LockedPins,
    toolchain: ToolchainIdentity,
    gn_args: []const []const u8,
    wrappers: []const WrapperIdentity,
    processes: []const ProcessIdentity,
};

pub const RootPolicy = struct {
    path: []const u8,
    absolute: bool,
    disposable: bool,
    repository_disjoint: bool,
    reparse_free: bool,
    whitespace_free: bool,
    free_space_bytes: u64,
    physical_memory_bytes: u64,
};

pub const NetworkPolicy = struct {
    mode: []const u8,
    detached_nic: bool,
    fetch_bytes: u64,
    route_count: u64,
    proxy: []const u8,
    process_policy: []const u8,
};

pub const LockedPins = struct {
    pdfium_commit: []const u8,
    pdfium_tree_sha256: []const u8,
    reference_archive_sha256: []const u8,
    reference_dll_sha256: []const u8,
    recipe_commit: []const u8,
    recipe_archive_sha256: []const u8,
    depot_tools_commit: []const u8,
    depot_tools_tree_sha1: []const u8,
};

pub const ToolchainIdentity = struct {
    runner_image_sha256: []const u8,
    visual_studio_sha256: []const u8,
    windows_sdk_version: []const u8,
    windows_sdk_sha256: []const u8,
    resolved_deps_sha256: []const u8,
    cipd_graph_sha256: []const u8,
    python_sha256: []const u8,
    git_sha256: []const u8,
    cipd_sha256: []const u8,
    clang_sha256: []const u8,
    linker_sha256: []const u8,
    gn_sha256: []const u8,
    ninja_sha256: []const u8,
};

pub const ProcessIdentity = struct {
    role: []const u8,
    path: []const u8,
    sha256: []const u8,
};

pub const WrapperIdentity = struct {
    name: []const u8,
    sha256: []const u8,
};

pub fn parseAndValidate(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !std.json.Parsed(Receipt) {
    if (bytes.len == 0 or bytes.len > max_receipt_bytes) return error.InvalidReceiptSize;
    var parsed = try std.json.parseFromSlice(Receipt, allocator, bytes, .{
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
    });
    errdefer parsed.deinit();
    try validateReceipt(parsed.value);
    return parsed;
}

pub fn receiptDigest(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

pub fn requireApprovedReproduction(receipt: Receipt) !void {
    try validateReceipt(receipt);
    if (!std.mem.eql(u8, receipt.phase, "reproduce") or
        !std.mem.eql(u8, receipt.status, "approved"))
    {
        return error.ReproductionNotApproved;
    }
    try validateReproductionNetwork(receipt.network);
}

pub fn validateReceipt(receipt: Receipt) !void {
    if (receipt.schema_version != 1) return error.UnsupportedSchemaVersion;
    if (!std.mem.eql(u8, receipt.receipt_kind, "texflow-pdfium-repro-toolchain")) {
        return error.InvalidReceiptKind;
    }
    if (!std.mem.eql(u8, receipt.target, "x86_64-windows-msvc")) {
        return error.TargetNotAdmitted;
    }
    if (std.mem.eql(u8, receipt.phase, "resolve")) {
        if (!std.mem.eql(u8, receipt.status, "candidate")) return error.InvalidReceiptStatus;
    } else if (std.mem.eql(u8, receipt.phase, "reproduce")) {
        if (!std.mem.eql(u8, receipt.status, "approved")) return error.InvalidReceiptStatus;
    } else return error.InvalidReceiptPhase;

    try validateRoot(receipt.root);
    try validateNetwork(receipt.network, receipt.phase);
    try validatePins(receipt.pins);
    try validateToolchain(receipt.toolchain);
    try validateGnArgs(receipt.gn_args);
    try validateWrappers(receipt.wrappers);
    try validateProcesses(receipt.processes, receipt.root.path);
}

fn validateRoot(root: RootPolicy) !void {
    if (root.path.len <= 3 or std.mem.endsWith(u8, root.path, "/") or std.mem.endsWith(u8, root.path, "\\") or
        std.mem.indexOfScalar(u8, root.path, '\\') != null)
    {
        return error.UnsafeRootPath;
    }
    try validatePathToken(root.path);
    if (!root.absolute or !root.disposable or !root.repository_disjoint or
        !root.reparse_free or !root.whitespace_free)
    {
        return error.ReproRootPolicyUnverified;
    }
    if (root.free_space_bytes < minimum_repro_disk_bytes) return error.InsufficientReproDisk;
    if (root.physical_memory_bytes < minimum_repro_memory_bytes) return error.InsufficientReproMemory;
}

fn validateNetwork(network: NetworkPolicy, phase: []const u8) !void {
    if (std.mem.eql(u8, phase, "resolve")) {
        if (!std.mem.eql(u8, network.mode, "resolve") and
            !std.mem.eql(u8, network.mode, "none"))
        {
            return error.InvalidNetworkMode;
        }
        return;
    }
    try validateReproductionNetwork(network);
}

fn validateReproductionNetwork(network: NetworkPolicy) !void {
    if (!std.mem.eql(u8, network.mode, "none") or !network.detached_nic or
        network.fetch_bytes != 0 or network.route_count != 0 or
        !std.mem.eql(u8, network.proxy, "unset") or
        !std.mem.eql(u8, network.process_policy, "zig-owned"))
    {
        return error.NetworkIsolationUnverified;
    }
}

fn validatePins(pins: LockedPins) !void {
    if (!std.mem.eql(u8, pins.pdfium_commit, locked_pdfium_commit) or
        !std.mem.eql(u8, pins.pdfium_tree_sha256, locked_pdfium_tree_sha256) or
        !std.mem.eql(u8, pins.reference_archive_sha256, locked_reference_archive_sha256) or
        !std.mem.eql(u8, pins.reference_dll_sha256, locked_reference_dll_sha256) or
        !std.mem.eql(u8, pins.recipe_commit, locked_recipe_commit) or
        !std.mem.eql(u8, pins.recipe_archive_sha256, locked_recipe_archive_sha256) or
        !std.mem.eql(u8, pins.depot_tools_commit, locked_depot_tools_commit) or
        !std.mem.eql(u8, pins.depot_tools_tree_sha1, locked_depot_tools_tree_sha1))
    {
        return error.LockedPinMismatch;
    }
    try validateLowerHex(pins.pdfium_commit, 40);
    try validateLowerHex(pins.recipe_commit, 40);
    try validateLowerHex(pins.depot_tools_commit, 40);
    try validateLowerHex(pins.pdfium_tree_sha256, 64);
    try validateLowerHex(pins.reference_archive_sha256, 64);
    try validateLowerHex(pins.reference_dll_sha256, 64);
    try validateLowerHex(pins.recipe_archive_sha256, 64);
    try validateLowerHex(pins.depot_tools_tree_sha1, 40);
}

fn validateToolchain(toolchain: ToolchainIdentity) !void {
    if (!std.mem.eql(u8, toolchain.windows_sdk_version, "10.0.28000.0")) {
        return error.ToolchainIdentityMismatch;
    }
    try validateLockedDigest(toolchain.runner_image_sha256, locked_runner_image_sha256);
    try validateLockedDigest(toolchain.visual_studio_sha256, locked_visual_studio_sha256);
    try validateLockedDigest(toolchain.windows_sdk_sha256, locked_windows_sdk_sha256);
    try validateLockedDigest(toolchain.resolved_deps_sha256, locked_resolved_deps_sha256);
    try validateLockedDigest(toolchain.cipd_graph_sha256, locked_cipd_graph_sha256);
    try validateLockedDigest(toolchain.python_sha256, locked_python_sha256);
    try validateLockedDigest(toolchain.git_sha256, locked_git_sha256);
    try validateLockedDigest(toolchain.cipd_sha256, locked_cipd_sha256);
    try validateLockedDigest(toolchain.clang_sha256, locked_clang_sha256);
    try validateLockedDigest(toolchain.linker_sha256, locked_linker_sha256);
    try validateLockedDigest(toolchain.gn_sha256, locked_gn_sha256);
    try validateLockedDigest(toolchain.ninja_sha256, locked_ninja_sha256);
}

fn validateGnArgs(args: []const []const u8) !void {
    const required = [_][]const u8{ "pdf_enable_v8=false", "pdf_enable_xfa=false" };
    if (args.len != required.len) return error.UnexpectedGnArg;
    for (args, required) |arg, expected| {
        try validateToken(arg);
        if (!std.mem.eql(u8, arg, expected)) return error.UnexpectedGnArg;
    }
}

fn validateWrappers(wrappers: []const WrapperIdentity) !void {
    if (wrappers.len != 1) return error.ProcessGraphMismatch;
    for (wrappers) |wrapper| {
        try validateToken(wrapper.name);
        if (!std.mem.eql(u8, wrapper.name, "vpython3.bat")) return error.UnsafeWrapper;
        try validateLockedDigest(wrapper.sha256, locked_wrapper_sha256);
    }
}

fn validateProcesses(processes: []const ProcessIdentity, root_path: []const u8) !void {
    const required = [_]struct { role: []const u8, basename: []const u8 }{
        .{ .role = "clang", .basename = "clang.exe" },
        .{ .role = "cipd", .basename = "cipd.exe" },
        .{ .role = "git", .basename = "git.exe" },
        .{ .role = "gn", .basename = "gn.exe" },
        .{ .role = "linker", .basename = "link.exe" },
        .{ .role = "ninja", .basename = "ninja.exe" },
        .{ .role = "python", .basename = "python.exe" },
    };
    if (processes.len != required.len) return error.ProcessGraphMismatch;
    var prefix_buf: [4096]u8 = undefined;
    const prefix = std.fmt.bufPrint(&prefix_buf, "{s}/tools/", .{root_path}) catch return error.UnsafeProcessPath;
    for (processes, required, locked_process_sha256) |process, expected, expected_digest| {
        if (!std.mem.eql(u8, process.role, expected.role)) return error.ProcessGraphMismatch;
        try validatePathToken(process.path);
        if (!std.mem.startsWith(u8, process.path, prefix)) return error.ProcessRootMismatch;
        if (std.mem.indexOfScalar(u8, process.path, '\\') != null) return error.ProcessIdentityMismatch;
        const basename = process.path[prefix.len..];
        if (std.mem.indexOfAny(u8, basename, "/\\") != null or !std.mem.eql(u8, basename, expected.basename)) {
            return error.ProcessIdentityMismatch;
        }
        try validateLockedDigest(process.sha256, expected_digest);
    }
}

fn validateLockedDigest(actual: []const u8, expected: []const u8) !void {
    if (!std.mem.eql(u8, actual, expected)) return error.ToolchainIdentityMismatch;
    try validateLowerHex(actual, expected.len);
}

fn validatePathToken(path: []const u8) !void {
    if (path.len < 4 or
        !((path[0] >= 'A' and path[0] <= 'Z') or (path[0] >= 'a' and path[0] <= 'z')) or
        path[1] != ':' or (path[2] != '/' and path[2] != '\\'))
    {
        return error.UnsafeProcessPath;
    }
    try validateToken(path);
    var components = std.mem.splitAny(u8, path[3..], "/\\");
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..") or
            component[component.len - 1] == '.')
        {
            return error.UnsafeProcessPath;
        }
    }
}

fn validateToken(token: []const u8) !void {
    if (token.len == 0) return error.EmptyToken;
    for (token) |byte| {
        if (byte < 0x20 or byte == 0x7f or byte == ' ' or byte == '\t' or
            byte == '"' or byte == '\'' or byte == 0x60 or byte == ';' or
            byte == '&' or byte == '|' or byte == '<' or byte == '>' or
            byte == '$')
        {
            return error.UnsafeToken;
        }
    }
}

fn validateLowerHex(value: []const u8, expected_len: usize) !void {
    if (value.len != expected_len) return error.InvalidDigest;
    for (value) |byte| {
        if (!((byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f'))) {
            return error.InvalidDigest;
        }
    }
}

// The strict controller is intentionally self-contained.  It consumes only
// operator-provisioned, already downloaded inputs and never calls deps_fetch,
// a package manager, a shell, or a network API.
const strict_receipt_schema_version: u16 = 2;
const strict_receipt_kind = "texflow-pdfium-controller-v2";
const approved_receipt_kind = "texflow-pdfium-approved-rebuild-v1";
const resolve_candidate_receipt_kind = "texflow-pdfium-resolve-candidate-v1";
const network_attestation_schema = "texflow-network-isolation-v1";
const maximum_controller_input_bytes: usize = 512 * 1024 * 1024;
const maximum_controller_tree_bytes: u64 = 64 * 1024 * 1024 * 1024;
const maximum_controller_tree_files: u64 = 1_000_000;
const maximum_controller_tree_path_bytes: usize = 4096;
const locked_pdfium_source_files: u64 = 5400;
const locked_pdfium_source_bytes: u64 = 40484895;
const locked_pdfium_source_subpath = "pdfium";
const locked_pdfium_version = "154.0.8035.0";
const locked_pdfium_resource_version = "154,0,8035,0";
const locked_pdfium_resource_year = "2026";

const strict_required_gn_args = [_][]const u8{
    "is_component_build=false",
    "is_debug=false",
    "pdf_enable_v8=false",
    "pdf_enable_xfa=false",
    "pdf_is_standalone=true",
    "pdf_use_partition_alloc=false",
    "target_cpu=\"x64\"",
    "target_os=\"win\"",
    "treat_warnings_as_errors=false",
};

const StrictToolchainExpectation = struct {
    runner_image_sha256: []const u8,
    visual_studio_sha256: []const u8,
    windows_sdk_version: []const u8,
    windows_sdk_sha256: []const u8,
    toolchain_closure_sha256: []const u8,
    git_sha256: []const u8,
    gn_sha256: []const u8,
    ninja_sha256: []const u8,
    compiler_sha256: []const u8,
    linker_sha256: []const u8,
    python_sha256: []const u8,
    resource_compiler_sha256: []const u8,
};

const StrictApprovedReceipt = struct {
    schema_version: u16,
    receipt_kind: []const u8,
    status: []const u8,
    target: []const u8,
    pdfium_commit: []const u8,
    pdfium_tree_sha256: []const u8,
    patched_pdfium_tree_sha256: []const u8,
    patched_pdfium_files: u64,
    patched_pdfium_bytes: u64,
    recipe_commit: []const u8,
    recipe_archive_sha256: []const u8,
    recipe_tree_sha256: []const u8,
    depot_tools_commit: []const u8,
    depot_tools_tree_sha1: []const u8,
    source_closure_sha256: []const u8,
    source_closure_files: u64,
    source_closure_bytes: u64,
    output_sha256: []const u8,
    output_size_bytes: u64,
    build_identity_sha256: []const u8,
    gn_args: []const []const u8,
    toolchain: StrictToolchainExpectation,
};

const tracked_toolchain_lock = @embedFile("pdfium-repro-toolchain.json");

const HostedRunIdentity = struct {
    server_url: []const u8,
    repository: []const u8,
    workflow: []const u8,
    workflow_ref: []const u8,
    job: []const u8,
    run_id: []const u8,
    run_attempt: []const u8,
    head_sha: []const u8,
    ref: []const u8,
    run_url: []const u8,
    runner_environment: []const u8,
    runner_os: []const u8,
    runner_arch: []const u8,
    image_os: []const u8,
    image_version: []const u8,
    runner_name_sha256: []const u8,
    image_identity_sha256: []const u8,

    fn deinit(self: *const HostedRunIdentity, allocator: std.mem.Allocator) void {
        if (self.runner_name_sha256.len != 0) allocator.free(self.runner_name_sha256);
        if (self.run_url.len != 0) allocator.free(self.run_url);
    }
};

const StrictNetworkEvidence = struct {
    mode: []const u8,
    source: []const u8,
    attestation_sha256: []const u8,
    route_count: u64,
    default_route_present: bool,
    negative_fetch_bytes: u64,
    proxy: []const u8,
    process_policy: []const u8,
};

const StrictInputEvidence = struct {
    status: []const u8,
    source_commit: []const u8,
    source_tree_sha256: []const u8,
    source_files: u64,
    source_bytes: u64,
    patched_source_tree_sha256: []const u8,
    patched_source_files: u64,
    patched_source_bytes: u64,
    source_closure_sha256: []const u8,
    source_closure_files: u64,
    source_closure_bytes: u64,
    recipe_commit: []const u8,
    recipe_archive_sha256: []const u8,
    recipe_tree_sha256: []const u8,
    depot_tools_commit: []const u8,
    depot_tools_tree_sha1: []const u8,
    approved_receipt_sha256: []const u8,
    free_space_bytes: u64,
    physical_memory_bytes: u64,
};

const StrictBuildEvidence = struct {
    status: []const u8,
    gn_args: []const []const u8,
    git_sha256: []const u8,
    gn_sha256: []const u8,
    ninja_sha256: []const u8,
    compiler_sha256: []const u8,
    linker_sha256: []const u8,
    python_sha256: []const u8,
    resource_compiler_sha256: []const u8,
    build_identity_sha256: []const u8,
};

const StrictOutputEvidence = struct {
    status: []const u8,
    path_redacted: []const u8,
    size_bytes: u64,
    sha256: []const u8,
    pe_machine: u16,
    pe_is_64: bool,
    actual_output: bool,
    reference_digest_rejected: bool,
};

const StrictRetentionEvidence = struct {
    status: []const u8,
    artifact_name: []const u8,
    artifact_id: []const u8,
    artifact_digest: []const u8,
    artifact_url: []const u8,
    retention_days: u16,
    receipt_sha256: []const u8,
    created_at: []const u8,
    expires_at: []const u8,
};

const StrictArtifactMetadata = struct {
    schema: []const u8,
    id: []const u8,
    name: []const u8,
    digest: []const u8,
    repository: []const u8,
    run_id: []const u8,
    run_attempt: []const u8,
    head_sha: []const u8,
    size_bytes: []const u8,
    expired: []const u8,
    created_at: []const u8,
    expires_at: []const u8,
};

pub const StrictControllerReceipt = struct {
    schema_version: u16,
    receipt_kind: []const u8,
    status: []const u8,
    reason: []const u8,
    scope: []const u8,
    run_identity_status: []const u8,
    run_identity: HostedRunIdentity,
    network: StrictNetworkEvidence,
    inputs: StrictInputEvidence,
    build: StrictBuildEvidence,
    output: StrictOutputEvidence,
    retention: StrictRetentionEvidence,
};

const StrictArtifactBinding = struct {
    schema_version: u16,
    receipt_kind: []const u8,
    status: []const u8,
    receipt_status: []const u8,
    restore_verified: bool,
    run_identity: HostedRunIdentity,
    artifact: StrictRetentionEvidence,
    receipt_sha256: []const u8,
};

const StrictRetentionObservation = struct {
    schema_version: u16,
    receipt_kind: []const u8,
    status: []const u8,
    source_status: []const u8,
    scope: []const u8,
    run_identity: HostedRunIdentity,
    revalidator_identity: HostedRunIdentity,
    artifact: StrictRetentionEvidence,
    receipt_sha256: []const u8,
    restored_sha256_a: []const u8,
    restored_sha256_b: []const u8,
    restore_count: u8,
    independent_runner: bool,
    independent_storage: bool,
    durable_status: []const u8,
};

const StrictTreeRecord = struct {
    path: []u8,
    size: u64,
    digest: [32]u8,
};

const StrictTreeSummary = struct {
    files: u64,
    bytes: u64,
    digest: [32]u8,
};

const StrictFileSummary = struct {
    bytes: u64,
    digest: [32]u8,
};

const StrictResourceEvidence = struct {
    free_space_bytes: u64,
    physical_memory_bytes: u64,
};

const StrictRouteEvidence = struct {
    route_count: u64,
    default_route_present: bool,
};

const StrictPeEvidence = struct {
    machine: u16,
    is_64: bool,
};

const StrictToolPaths = struct {
    git: []const u8,
    gn: []const u8,
    ninja: []const u8,
    compiler: []const u8,
    linker: []const u8,
    python: []const u8,
    resource_compiler: []const u8,
};

const WindowsMemoryStatusEx = extern struct {
    dw_length: u32,
    dw_memory_load: u32,
    ull_total_phys: u64,
    ull_avail_phys: u64,
    ull_total_page_file: u64,
    ull_avail_page_file: u64,
    ull_total_virtual: u64,
    ull_avail_virtual: u64,
    ull_avail_extended_virtual: u64,
};

extern "kernel32" fn GetDiskFreeSpaceExW(
    directory_name: [*:0]const u16,
    free_bytes_available: ?*u64,
    total_bytes: ?*u64,
    total_free_bytes: ?*u64,
) callconv(.winapi) i32;

extern "kernel32" fn GlobalMemoryStatusEx(status: *WindowsMemoryStatusEx) callconv(.winapi) i32;

fn emptyHostedRunIdentity() HostedRunIdentity {
    return .{
        .server_url = "",
        .repository = "",
        .workflow = "",
        .workflow_ref = "",
        .job = "",
        .run_id = "",
        .run_attempt = "",
        .head_sha = "",
        .ref = "",
        .run_url = "",
        .runner_environment = "",
        .runner_os = "",
        .runner_arch = "",
        .image_os = "",
        .image_version = "",
        .runner_name_sha256 = "",
        .image_identity_sha256 = "",
    };
}

fn emptyNetworkEvidence() StrictNetworkEvidence {
    return .{
        .mode = "not-asserted",
        .source = "not-run",
        .attestation_sha256 = "",
        .route_count = 0,
        .default_route_present = false,
        .negative_fetch_bytes = 0,
        .proxy = "not-checked",
        .process_policy = "not-run",
    };
}

fn emptyInputEvidence() StrictInputEvidence {
    return .{
        .status = "not-run",
        .source_commit = "",
        .source_tree_sha256 = "",
        .source_files = 0,
        .source_bytes = 0,
        .patched_source_tree_sha256 = "",
        .patched_source_files = 0,
        .patched_source_bytes = 0,
        .source_closure_sha256 = "",
        .source_closure_files = 0,
        .source_closure_bytes = 0,
        .recipe_commit = "",
        .recipe_archive_sha256 = "",
        .recipe_tree_sha256 = "",
        .depot_tools_commit = "",
        .depot_tools_tree_sha1 = "",
        .approved_receipt_sha256 = "",
        .free_space_bytes = 0,
        .physical_memory_bytes = 0,
    };
}

fn emptyBuildEvidence() StrictBuildEvidence {
    return .{
        .status = "not-run",
        .gn_args = &[_][]const u8{},
        .git_sha256 = "",
        .gn_sha256 = "",
        .ninja_sha256 = "",
        .compiler_sha256 = "",
        .linker_sha256 = "",
        .python_sha256 = "",
        .resource_compiler_sha256 = "",
        .build_identity_sha256 = "",
    };
}

fn emptyOutputEvidence() StrictOutputEvidence {
    return .{
        .status = "not-run",
        .path_redacted = "<redacted>",
        .size_bytes = 0,
        .sha256 = "",
        .pe_machine = 0,
        .pe_is_64 = false,
        .actual_output = false,
        .reference_digest_rejected = false,
    };
}

fn emptyRetentionEvidence() StrictRetentionEvidence {
    return .{
        .status = "pending-upload",
        .artifact_name = "",
        .artifact_id = "",
        .artifact_digest = "",
        .artifact_url = "",
        .retention_days = 0,
        .receipt_sha256 = "",
        .created_at = "",
        .expires_at = "",
    };
}

fn emptyControllerReceipt(reason: []const u8, scope: []const u8) StrictControllerReceipt {
    return .{
        .schema_version = strict_receipt_schema_version,
        .receipt_kind = strict_receipt_kind,
        .status = "unverified",
        .reason = reason,
        .scope = scope,
        .run_identity_status = "unverified",
        .run_identity = emptyHostedRunIdentity(),
        .network = emptyNetworkEvidence(),
        .inputs = emptyInputEvidence(),
        .build = emptyBuildEvidence(),
        .output = emptyOutputEvidence(),
        .retention = emptyRetentionEvidence(),
    };
}

fn strictOption(
    args: []const []const u8,
    name: []const u8,
    allowed: []const []const u8,
) ![]const u8 {
    var found: ?[]const u8 = null;
    var index: usize = 2;
    while (index < args.len) : (index += 2) {
        if (index + 1 >= args.len or !std.mem.startsWith(u8, args[index], "--")) {
            return error.InvalidArguments;
        }
        var known = false;
        for (allowed) |candidate| {
            if (std.mem.eql(u8, args[index], candidate)) {
                known = true;
                break;
            }
        }
        if (!known) return error.UnexpectedArgument;
        if (std.mem.eql(u8, args[index], name)) {
            if (found != null) return error.DuplicateArgument;
            found = args[index + 1];
        }
    }
    return found orelse error.MissingArgument;
}

fn strictOptionalOption(
    args: []const []const u8,
    name: []const u8,
    allowed: []const []const u8,
) !?[]const u8 {
    var found: ?[]const u8 = null;
    var index: usize = 2;
    while (index < args.len) : (index += 2) {
        if (index + 1 >= args.len or !std.mem.startsWith(u8, args[index], "--")) {
            return error.InvalidArguments;
        }
        var known = false;
        for (allowed) |candidate| {
            if (std.mem.eql(u8, args[index], candidate)) {
                known = true;
                break;
            }
        }
        if (!known) return error.UnexpectedArgument;
        if (std.mem.eql(u8, args[index], name)) {
            if (found != null) return error.DuplicateArgument;
            found = args[index + 1];
        }
    }
    return found;
}

fn strictRequiredEnv(environment: *const std.process.Environ.Map, name: []const u8) ![]const u8 {
    const value = environment.get(name) orelse return error.MissingRunnerInput;
    if (value.len == 0) return error.MissingRunnerInput;
    return value;
}

fn strictEnvIsTrue(environment: *const std.process.Environ.Map, name: []const u8) bool {
    return if (environment.get(name)) |value| std.mem.eql(u8, value, "true") else false;
}

fn validateStrictText(value: []const u8) !void {
    if (value.len == 0) return error.EmptyRunnerIdentity;
    for (value) |byte| {
        if (byte < 0x20 or byte == 0x7f or byte >= 0x80 or
            std.mem.indexOfScalar(u8, "\"'`;&|<>$\r\n", byte) != null)
        {
            return error.UnsafeRunnerIdentity;
        }
    }
}

fn validateStrictDecimal(value: []const u8) !void {
    if (value.len == 0 or (value.len > 1 and value[0] == '0')) return error.InvalidRunIdentity;
    for (value) |byte| if (byte < '0' or byte > '9') return error.InvalidRunIdentity;
    _ = std.fmt.parseUnsigned(u64, value, 10) catch return error.InvalidRunIdentity;
}

fn validateStrictNonzeroDecimal(value: []const u8) !void {
    try validateStrictDecimal(value);
    if (std.mem.eql(u8, value, "0")) return error.InvalidRunIdentity;
}

fn isLocalDriveAbsolute(path: []const u8) bool {
    return path.len >= 3 and std.ascii.isAlphabetic(path[0]) and path[1] == ':' and
        (path[2] == '\\' or path[2] == '/');
}

fn validateStrictPath(path: []const u8, allow_spaces: bool) !void {
    if (path.len < 4 or (!std.fs.path.isAbsolute(path) and !isLocalDriveAbsolute(path))) {
        return error.UnsafeControllerPath;
    }
    if (path[path.len - 1] == '/' or path[path.len - 1] == '\\') return error.UnsafeControllerPath;
    for (path, 0..) |byte, index| {
        if (byte == 0 or byte < 0x20 or byte == 0x7f or byte >= 0x80 or
            (!allow_spaces and byte == ' ') or
            (byte == ':' and !(isLocalDriveAbsolute(path) and index == 1)) or
            std.mem.indexOfScalar(u8, "\"'`;&|<>$*?\r\n", byte) != null)
        {
            return error.UnsafeControllerPath;
        }
    }
    const start: usize = if (isLocalDriveAbsolute(path)) 3 else 1;
    var components = std.mem.splitAny(u8, path[start..], "/\\");
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or
            std.mem.eql(u8, component, "..") or component[component.len - 1] == '.' or
            component[component.len - 1] == ' ' or strictTreeReservedDevice(component))
        {
            return error.UnsafeControllerPath;
        }
    }
}

fn validateStrictAbsolutePath(path: []const u8) !void {
    return validateStrictPath(path, false);
}

fn validateStrictInputPath(path: []const u8) !void {
    return validateStrictPath(path, true);
}

fn validateStrictToolPath(path: []const u8) !void {
    try validateStrictPath(path, true);
    var lower_name_buffer: [64]u8 = undefined;
    const name = std.fs.path.basename(path);
    if (name.len > lower_name_buffer.len) return error.UnsafeToolPath;
    const lower_name = std.ascii.lowerString(&lower_name_buffer, name);
    if (std.mem.endsWith(u8, lower_name, ".bat") or
        std.mem.endsWith(u8, lower_name, ".cmd") or
        std.mem.endsWith(u8, lower_name, ".ps1") or
        std.mem.endsWith(u8, lower_name, ".sh") or
        std.mem.endsWith(u8, lower_name, ".bash"))
    {
        return error.ShellToolRejected;
    }
}

fn trimStrictPath(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 1 and (path[end - 1] == '/' or path[end - 1] == '\\')) end -= 1;
    return path[0..end];
}

fn strictPathByteEqual(left: u8, right: u8) bool {
    if ((left == '/' or left == '\\') and (right == '/' or right == '\\')) return true;
    if (builtin.os.tag == .windows) return std.ascii.toLower(left) == std.ascii.toLower(right);
    return left == right;
}

fn strictPathWithin(ancestor_raw: []const u8, candidate_raw: []const u8) bool {
    const ancestor = trimStrictPath(ancestor_raw);
    const candidate = trimStrictPath(candidate_raw);
    if (ancestor.len > candidate.len) return false;
    for (ancestor, candidate[0..ancestor.len]) |left, right| {
        if (!strictPathByteEqual(left, right)) return false;
    }
    if (ancestor.len == candidate.len) return true;
    return candidate[ancestor.len] == '/' or candidate[ancestor.len] == '\\';
}

fn openStrictDirectoryNoFollow(
    io: std.Io,
    path: []const u8,
    iterate: bool,
) !std.Io.Dir {
    if (comptime builtin.os.tag == .windows) {
        const parsed = std.fs.path.parsePathWindows(u8, path);
        switch (parsed.kind) {
            .drive_absolute, .unc_absolute => {
                var current = try std.Io.Dir.openDirAbsolute(io, parsed.root, .{
                    .iterate = iterate,
                    .follow_symlinks = false,
                });
                errdefer current.close(io);
                var index = parsed.root.len;
                while (index < path.len) {
                    while (index < path.len and std.fs.path.isSep(path[index])) index += 1;
                    if (index == path.len) break;
                    const start = index;
                    while (index < path.len and !std.fs.path.isSep(path[index])) index += 1;
                    const component = path[start..index];
                    if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) {
                        return error.UnsafeControllerPath;
                    }
                    var next = try current.openDir(io, component, .{
                        .iterate = iterate,
                        .follow_symlinks = false,
                    });
                    errdefer next.close(io);
                    current.close(io);
                    current = next;
                }
                return current;
            },
            else => return error.UnsafeControllerPath,
        }
    } else {
        const parsed = std.fs.path.parsePathPosix(path);
        var current = try std.Io.Dir.openDirAbsolute(io, parsed.root, .{
            .iterate = iterate,
            .follow_symlinks = false,
        });
        errdefer current.close(io);
        var index = parsed.root.len;
        while (index < path.len) {
            while (index < path.len and std.fs.path.isSep(path[index])) index += 1;
            if (index == path.len) break;
            const start = index;
            while (index < path.len and !std.fs.path.isSep(path[index])) index += 1;
            const component = path[start..index];
            if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) {
                return error.UnsafeControllerPath;
            }
            var next = try current.openDir(io, component, .{
                .iterate = iterate,
                .follow_symlinks = false,
            });
            errdefer next.close(io);
            current.close(io);
            current = next;
        }
        return current;
    }
}

fn openStrictFileNoFollow(io: std.Io, path: []const u8) !std.Io.File {
    const parent_path = std.fs.path.dirname(path) orelse return error.UnsafeControllerPath;
    const basename = std.fs.path.basename(path);
    if (basename.len == 0 or std.mem.eql(u8, basename, ".") or std.mem.eql(u8, basename, "..")) {
        return error.UnsafeControllerPath;
    }
    var parent = try openStrictDirectoryNoFollow(io, parent_path, false);
    defer parent.close(io);
    return parent.openFile(io, basename, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    });
}

fn strictRelativePath(ancestor_raw: []const u8, candidate_raw: []const u8) ?[]const u8 {
    const ancestor = trimStrictPath(ancestor_raw);
    const candidate = trimStrictPath(candidate_raw);
    if (!strictPathWithin(ancestor, candidate) or ancestor.len >= candidate.len) return null;
    if (candidate[ancestor.len] != '/' and candidate[ancestor.len] != '\\') return null;
    const relative = candidate[ancestor.len + 1 ..];
    return if (relative.len == 0) null else relative;
}

fn strictPathsOverlap(left: []const u8, right: []const u8) bool {
    return strictPathWithin(left, right) or strictPathWithin(right, left);
}

fn requireDistinctEvidenceFiles(io: std.Io, paths: []const []const u8) !void {
    var identities: [3]std.Io.File.INode = undefined;
    if (paths.len > identities.len) return error.TooManyEvidenceFiles;
    for (paths, 0..) |path, index| {
        for (paths[0..index]) |previous| {
            if (strictPathsOverlap(previous, path)) return error.ArtifactRestoreAlias;
        }
        var file = try openStrictFileNoFollow(io, path);
        defer file.close(io);
        const stat = try file.stat(io);
        if (stat.kind != .file) return error.InputIsNotRegularFile;
        if (stat.inode == 0) return error.ArtifactRestoreIdentityUnavailable;
        for (identities[0..index]) |identity| {
            if (identity == stat.inode) return error.ArtifactRestoreAlias;
        }
        identities[index] = stat.inode;
    }
}

fn requireStrictOutside(path: []const u8, workspace: []const u8, repro_root: ?[]const u8) !void {
    if (strictPathsOverlap(workspace, path)) return error.ControllerPathOverlapsRepository;
    if (repro_root) |root| if (strictPathsOverlap(root, path)) return error.ControllerPathOverlapsReproRoot;
}

fn requireStrictDirectory(io: std.Io, path: []const u8) !void {
    var directory = try openStrictDirectoryNoFollow(io, path, true);
    defer directory.close(io);
    if ((try directory.stat(io)).kind != .directory) return error.InputIsNotDirectory;
}

fn requireStrictRegularFile(io: std.Io, path: []const u8) !void {
    var file = try openStrictFileNoFollow(io, path);
    defer file.close(io);
    if ((try file.stat(io)).kind != .file) return error.InputIsNotRegularFile;
}

fn requireStrictAbsent(io: std.Io, path: []const u8) !void {
    const parent_path = std.fs.path.dirname(path) orelse return error.UnsafeControllerPath;
    const basename = std.fs.path.basename(path);
    if (basename.len == 0 or std.mem.eql(u8, basename, ".") or std.mem.eql(u8, basename, "..")) {
        return error.UnsafeControllerPath;
    }
    var parent = openStrictDirectoryNoFollow(io, parent_path, false) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer parent.close(io);
    if (parent.openDir(io, basename, .{ .follow_symlinks = false })) |directory| {
        directory.close(io);
        return error.ReproBuildRootNotFresh;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }
    if (parent.openFile(io, basename, .{
        .allow_directory = false,
        .follow_symlinks = false,
    })) |file| {
        file.close(io);
        return error.ReproOutputAlreadyExists;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }
}

fn createStrictDirectoryPath(
    io: std.Io,
    ancestor_path: []const u8,
    child_path: []const u8,
) !std.Io.Dir {
    const relative = strictRelativePath(ancestor_path, child_path) orelse
        return error.ControllerPathNotContained;
    var ancestor = try openStrictDirectoryNoFollow(io, ancestor_path, true);
    defer ancestor.close(io);
    return ancestor.createDirPathOpen(io, relative, .{
        .open_options = .{
            .iterate = true,
            .follow_symlinks = false,
        },
    });
}

fn readStrictFileAlloc(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    limit: usize,
) ![]u8 {
    var file = try openStrictFileNoFollow(io, path);
    defer file.close(io);
    if ((try file.stat(io)).kind != .file) return error.InputIsNotRegularFile;
    var reader_buffer: [64 * 1024]u8 = undefined;
    var reader = file.reader(io, &reader_buffer);
    return reader.interface.allocRemaining(allocator, .limited(limit)) catch |err| switch (err) {
        error.ReadFailed => return reader.err orelse error.ReadFailed,
        else => return err,
    };
}

fn hashStrictFile(
    io: std.Io,
    path: []const u8,
    maximum_bytes: u64,
) !StrictFileSummary {
    const parent_path = std.fs.path.dirname(path) orelse return error.UnsafeControllerPath;
    const basename = std.fs.path.basename(path);
    var parent = try openStrictDirectoryNoFollow(io, parent_path, false);
    defer parent.close(io);
    var nofollow = try parent.openFile(io, basename, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    });
    defer nofollow.close(io);
    const before = try nofollow.stat(io);
    if (before.kind != .file) return error.InputIsNotRegularFile;
    if (before.size > maximum_bytes) return error.ControllerInputTooLarge;

    var file = try parent.openFile(io, basename, .{
        .allow_directory = false,
        .follow_symlinks = true,
        .resolve_beneath = true,
    });
    defer file.close(io);
    const opened = try file.stat(io);
    if (opened.kind != .file or opened.inode != before.inode or opened.size != before.size) {
        return error.InputChangedDuringHash;
    }

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var reader_buffer: [64 * 1024]u8 = undefined;
    var reader = file.reader(io, &reader_buffer);
    var chunk: [64 * 1024]u8 = undefined;
    var bytes: u64 = 0;
    while (true) {
        const count = reader.interface.readSliceShort(&chunk) catch
            return reader.err orelse error.ReadFailed;
        if (count == 0) break;
        bytes = std.math.add(u64, bytes, count) catch return error.ControllerInputTooLarge;
        if (bytes > maximum_bytes) return error.ControllerInputTooLarge;
        hasher.update(chunk[0..count]);
    }
    const after = try file.stat(io);
    if (after.kind != .file or after.inode != before.inode or after.size != before.size) {
        return error.InputChangedDuringHash;
    }
    if (bytes != before.size) return error.InputChangedDuringHash;
    var final_nofollow = try parent.openFile(io, basename, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    });
    defer final_nofollow.close(io);
    const final = try final_nofollow.stat(io);
    if (final.kind != .file or final.inode != before.inode or final.size != before.size) {
        return error.InputChangedDuringHash;
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return .{ .bytes = bytes, .digest = digest };
}

fn strictLessTreeRecord(_: void, left: StrictTreeRecord, right: StrictTreeRecord) bool {
    return std.mem.order(u8, left.path, right.path) == .lt;
}

fn strictHashTreeRecords(records: []StrictTreeRecord) [32]u8 {
    std.mem.sort(StrictTreeRecord, records, {}, strictLessTreeRecord);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var size_buffer: [32]u8 = undefined;
    for (records) |record| {
        hasher.update(record.path);
        hasher.update("\t");
        const size_text = std.fmt.bufPrint(&size_buffer, "{d}", .{record.size}) catch unreachable;
        hasher.update(size_text);
        hasher.update("\t");
        const digest_hex = std.fmt.bytesToHex(record.digest, .lower);
        hasher.update(&digest_hex);
        hasher.update("\n");
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn strictTreeReservedDevice(component: []const u8) bool {
    const stem_end = std.mem.indexOfScalar(u8, component, '.') orelse component.len;
    const stem = component[0..stem_end];
    for ([_][]const u8{ "CON", "PRN", "AUX", "NUL", "CLOCK$", "CONIN$", "CONOUT$" }) |reserved| {
        if (std.ascii.eqlIgnoreCase(stem, reserved)) return true;
    }
    if (stem.len == 4 and
        (std.ascii.eqlIgnoreCase(stem[0..3], "COM") or std.ascii.eqlIgnoreCase(stem[0..3], "LPT")) and
        stem[3] >= '1' and stem[3] <= '9') return true;
    return stem.len == 5 and
        (std.ascii.eqlIgnoreCase(stem[0..3], "COM") or std.ascii.eqlIgnoreCase(stem[0..3], "LPT")) and
        stem[3] == 0xc2 and
        (stem[4] == 0xb9 or stem[4] == 0xb2 or stem[4] == 0xb3);
}

fn validateStrictTreePath(path: []const u8) !void {
    if (path.len == 0 or path.len > maximum_controller_tree_path_bytes or
        path[0] == '/' or path[path.len - 1] == '/' or
        !std.unicode.utf8ValidateSlice(path)) return error.UnsafeTreePath;
    for (path) |byte| {
        if (byte < 0x20 or byte == 0x7f or byte == '\\' or byte == ':' or
            byte == '"' or byte == '*' or byte == '?' or byte == '<' or
            byte == '>' or byte == '|') return error.UnsafeTreePath;
    }
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or
            std.mem.eql(u8, component, "..") or component[component.len - 1] == '.' or
            component[component.len - 1] == ' ' or strictTreeReservedDevice(component))
        {
            return error.UnsafeTreePath;
        }
    }
}

fn registerStrictTreePath(
    allocator: std.mem.Allocator,
    keys: *std.StringHashMap(void),
    path: []const u8,
) !void {
    try validateStrictTreePath(path);
    const key = try source_unicode.foldNfd(allocator, path, maximum_controller_tree_path_bytes);
    errdefer allocator.free(key);
    if (keys.contains(key)) return error.ControllerTreePathCollision;
    try keys.put(key, {});
}

fn joinStrictTreePath(
    allocator: std.mem.Allocator,
    parent: []const u8,
    name: []const u8,
) ![]u8 {
    const separator = @intFromBool(parent.len != 0);
    const total = std.math.add(usize, parent.len, separator) catch return error.UnsafeTreePath;
    const length = std.math.add(usize, total, name.len) catch return error.UnsafeTreePath;
    if (length > maximum_controller_tree_path_bytes) return error.UnsafeTreePath;
    const path = try allocator.alloc(u8, length);
    if (parent.len != 0) {
        @memcpy(path[0..parent.len], parent);
        path[parent.len] = '/';
    }
    @memcpy(path[parent.len + separator ..], name);
    return path;
}

const StrictTreeFrame = struct {
    directory: std.Io.Dir,
    iterator: std.Io.Dir.Iterator,
    path: []u8,
};

const StrictCopyTreeFrame = struct {
    source: std.Io.Dir,
    destination: std.Io.Dir,
    iterator: std.Io.Dir.Iterator,
    path: []u8,
};

const StrictPatchSpec = struct {
    relative_path: []const u8,
    working_directory: []const u8,
};

const strict_patch_specs = [_]StrictPatchSpec{
    .{ .relative_path = "patches/shared_library.patch", .working_directory = "" },
    .{ .relative_path = "patches/public_headers.patch", .working_directory = "" },
    .{ .relative_path = "patches/clang_rt.patch", .working_directory = "build" },
    .{ .relative_path = "patches/win/build.patch", .working_directory = "build" },
};

fn hashStrictTree(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !StrictTreeSummary {
    var root = try openStrictDirectoryNoFollow(io, path, true);
    var root_transferred = false;
    errdefer if (!root_transferred) root.close(io);
    if ((try root.stat(io)).kind != .directory) return error.InputIsNotDirectory;

    var records: std.ArrayList(StrictTreeRecord) = .empty;
    defer {
        for (records.items) |record| allocator.free(record.path);
        records.deinit(allocator);
    }
    var path_keys = std.StringHashMap(void).init(allocator);
    defer {
        var key_iterator = path_keys.keyIterator();
        while (key_iterator.next()) |key| allocator.free(key.*);
        path_keys.deinit();
    }
    var frames: std.ArrayList(StrictTreeFrame) = .empty;
    defer {
        for (frames.items) |frame| {
            frame.directory.close(io);
            allocator.free(frame.path);
        }
        frames.deinit(allocator);
    }
    const root_path = try allocator.dupe(u8, "");
    var root_path_transferred = false;
    errdefer if (!root_path_transferred) allocator.free(root_path);
    try frames.append(allocator, .{
        .directory = root,
        .iterator = root.iterate(),
        .path = root_path,
    });
    root_transferred = true;
    root_path_transferred = true;
    var total: u64 = 0;
    while (frames.items.len != 0) {
        const frame = &frames.items[frames.items.len - 1];
        const entry = try frame.iterator.next(io) orelse {
            const finished = frames.pop().?;
            finished.directory.close(io);
            allocator.free(finished.path);
            continue;
        };
        if (std.mem.eql(u8, entry.name, ".git")) continue;
        const normalized_path = try joinStrictTreePath(allocator, frame.path, entry.name);
        var owned_path: ?[]u8 = normalized_path;
        defer if (owned_path) |path_value| allocator.free(path_value);
        switch (entry.kind) {
            .directory => {
                try registerStrictTreePath(allocator, &path_keys, normalized_path);
                var child = frame.directory.openDir(io, entry.name, .{
                    .iterate = true,
                    .follow_symlinks = false,
                }) catch return error.ReparsePointInInput;
                errdefer child.close(io);
                if ((try child.stat(io)).kind != .directory) return error.ReparsePointInInput;
                try frames.append(allocator, .{
                    .directory = child,
                    .iterator = child.iterate(),
                    .path = normalized_path,
                });
                owned_path = null;
            },
            .file => {
                try registerStrictTreePath(allocator, &path_keys, normalized_path);
                const file_summary = try hashStrictFileEntry(io, frame.directory, entry.name);
                total = std.math.add(u64, total, file_summary.bytes) catch
                    return error.ControllerTreeTooLarge;
                if (total > maximum_controller_tree_bytes) return error.ControllerTreeTooLarge;
                if (records.items.len >= maximum_controller_tree_files) return error.ControllerTreeTooManyFiles;
                const record_path = try allocator.dupe(u8, normalized_path);
                records.append(allocator, .{
                    .path = record_path,
                    .size = file_summary.bytes,
                    .digest = file_summary.digest,
                }) catch |err| {
                    allocator.free(record_path);
                    return err;
                };
            },
            else => return error.ReparsePointInInput,
        }
    }
    return .{
        .files = records.items.len,
        .bytes = total,
        .digest = strictHashTreeRecords(records.items),
    };
}

fn strictTreeSummaryEqual(left: StrictTreeSummary, right: StrictTreeSummary) bool {
    return left.files == right.files and left.bytes == right.bytes and
        std.mem.eql(u8, &left.digest, &right.digest);
}

fn requireStrictEmptyDirectory(io: std.Io, path: []const u8) !void {
    var directory = try openStrictDirectoryNoFollow(io, path, true);
    defer directory.close(io);
    var iterator = directory.iterate();
    if (try iterator.next(io)) |_| return error.ReproRootNotFresh;
}

fn copyStrictFile(
    io: std.Io,
    source: std.Io.Dir,
    source_name: []const u8,
    destination: std.Io.Dir,
    destination_name: []const u8,
) !void {
    var nofollow = source.openFile(io, source_name, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch return error.ReparsePointInInput;
    defer nofollow.close(io);
    const before = (try nofollow.stat(io));
    if (before.kind != .file) return error.ReparsePointInInput;

    // Keep the readable handle bound to the no-follow identity.  Copying from
    // this handle avoids reopening the source path through a reparse point.
    var file = source.openFile(io, source_name, .{
        .allow_directory = false,
        .follow_symlinks = true,
        .resolve_beneath = true,
    }) catch return error.ReparsePointInInput;
    defer file.close(io);
    const opened = try file.stat(io);
    if (opened.kind != .file or opened.inode != before.inode or opened.size != before.size) {
        return error.InputChangedDuringCopy;
    }

    var atomic = try destination.createFileAtomic(io, destination_name, .{
        .permissions = opened.permissions,
        .replace = false,
    });
    defer atomic.deinit(io);
    var reader_buffer: [64 * 1024]u8 = undefined;
    var reader = file.reader(io, &reader_buffer);
    var writer_buffer: [64 * 1024]u8 = undefined;
    var writer = atomic.file.writer(io, &writer_buffer);
    var bytes: u64 = 0;
    var chunk: [64 * 1024]u8 = undefined;
    while (true) {
        const count = reader.interface.readSliceShort(&chunk) catch
            return reader.err orelse error.SourceCopyFailed;
        if (count == 0) break;
        bytes = std.math.add(u64, bytes, count) catch return error.ControllerTreeTooLarge;
        if (bytes > maximum_controller_tree_bytes) return error.ControllerTreeTooLarge;
        writer.interface.writeAll(chunk[0..count]) catch
            return writer.err orelse error.SourceCopyFailed;
    }
    writer.interface.flush() catch return writer.err orelse error.SourceCopyFailed;
    if (bytes != before.size) return error.InputChangedDuringCopy;
    const after = try file.stat(io);
    if (after.kind != .file or after.inode != before.inode or after.size != before.size) {
        return error.InputChangedDuringCopy;
    }
    try atomic.link(io);
}

fn copyStrictTree(
    allocator: std.mem.Allocator,
    io: std.Io,
    source_path: []const u8,
    destination_path: []const u8,
    expected: StrictTreeSummary,
) !void {
    var source_root = try openStrictDirectoryNoFollow(io, source_path, true);
    var source_root_transferred = false;
    errdefer if (!source_root_transferred) source_root.close(io);
    var destination_root = try openStrictDirectoryNoFollow(io, destination_path, true);
    var destination_root_transferred = false;
    errdefer if (!destination_root_transferred) destination_root.close(io);

    var frames: std.ArrayList(StrictCopyTreeFrame) = .empty;
    defer {
        for (frames.items) |frame| {
            frame.source.close(io);
            frame.destination.close(io);
            allocator.free(frame.path);
        }
        frames.deinit(allocator);
    }
    const root_path = try allocator.dupe(u8, "");
    var root_path_transferred = false;
    errdefer if (!root_path_transferred) allocator.free(root_path);
    try frames.append(allocator, .{
        .source = source_root,
        .destination = destination_root,
        .iterator = source_root.iterate(),
        .path = root_path,
    });
    source_root_transferred = true;
    destination_root_transferred = true;
    root_path_transferred = true;

    while (frames.items.len != 0) {
        const frame = &frames.items[frames.items.len - 1];
        const entry = try frame.iterator.next(io) orelse {
            const finished = frames.pop().?;
            finished.source.close(io);
            finished.destination.close(io);
            allocator.free(finished.path);
            continue;
        };
        if (std.mem.eql(u8, entry.name, ".git")) continue;

        const normalized_path = try joinStrictTreePath(allocator, frame.path, entry.name);
        var owned_path: ?[]u8 = normalized_path;
        defer if (owned_path) |path| allocator.free(path);
        try validateStrictTreePath(normalized_path);

        switch (entry.kind) {
            .directory => {
                var source_child = frame.source.openDir(io, entry.name, .{
                    .iterate = true,
                    .follow_symlinks = false,
                }) catch return error.ReparsePointInInput;
                var source_child_transferred = false;
                errdefer if (!source_child_transferred) source_child.close(io);
                if ((try source_child.stat(io)).kind != .directory) return error.ReparsePointInInput;

                try frame.destination.createDir(io, entry.name, .default_dir);
                var destination_child = frame.destination.openDir(io, entry.name, .{
                    .iterate = true,
                    .follow_symlinks = false,
                }) catch return error.ReparsePointInInput;
                var destination_child_transferred = false;
                errdefer if (!destination_child_transferred) destination_child.close(io);
                if ((try destination_child.stat(io)).kind != .directory) return error.ReparsePointInInput;

                try frames.append(allocator, .{
                    .source = source_child,
                    .destination = destination_child,
                    .iterator = source_child.iterate(),
                    .path = normalized_path,
                });
                source_child_transferred = true;
                destination_child_transferred = true;
                owned_path = null;
            },
            .file => {
                try copyStrictFile(
                    io,
                    frame.source,
                    entry.name,
                    frame.destination,
                    entry.name,
                );
            },
            else => return error.ReparsePointInInput,
        }
    }

    const source_after = try hashStrictTree(allocator, io, source_path);
    if (!strictTreeSummaryEqual(source_after, expected)) return error.SourceChangedDuringCopy;
    const destination_after = try hashStrictTree(allocator, io, destination_path);
    if (!strictTreeSummaryEqual(destination_after, expected)) return error.SourceCopyMismatch;
}

const strict_pdfium_resource_rc =
    "1 VERSIONINFO\n" ++
    "FILEVERSION     " ++ locked_pdfium_resource_version ++ "\n" ++
    "PRODUCTVERSION  " ++ locked_pdfium_resource_version ++ "\n" ++
    "BEGIN\n" ++
    "    BLOCK \"StringFileInfo\"\n" ++
    "    BEGIN\n" ++
    "        BLOCK \"040904E4\"\n" ++
    "        BEGIN\n" ++
    "            VALUE \"CompanyName\",      \"Google Inc.\"\n" ++
    "            VALUE \"FileDescription\",  \"PDFium (compiled by github.com/bblanchon)\"\n" ++
    "            VALUE \"FileVersion\",      \"" ++ locked_pdfium_version ++ "\"\n" ++
    "            VALUE \"InternalName\",     \"pdfium\"\n" ++
    "            VALUE \"OriginalFilename\", \"pdfium.dll\"\n" ++
    "            VALUE \"ProductName\",      \"pdfium\"\n" ++
    "            VALUE \"ProductVersion\",   \"" ++ locked_pdfium_version ++ "\"\n" ++
    "            VALUE \"LegalCopyright\",   \"Copyright " ++ locked_pdfium_resource_year ++ " PDFium Authors. All rights reserved.\"\n" ++
    "        END\n" ++
    "    END\n" ++
    "    BLOCK \"VarFileInfo\"\n" ++
    "    BEGIN\n" ++
    "        VALUE \"Translation\", 0x409, 1252\n" ++
    "    END\n" ++
    "END\n";

fn writeStrictPdfiumResource(io: std.Io, destination_path: []const u8) !void {
    const resource_path = try std.fs.path.join(std.heap.page_allocator, &.{ destination_path, "resources.rc" });
    defer std.heap.page_allocator.free(resource_path);
    try requireStrictAbsent(io, resource_path);
    try writeStrictFile(io, resource_path, strict_pdfium_resource_rc);
}

fn applyStrictPdfiumPatches(
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    git: []const u8,
    recipe_root: []const u8,
    destination_path: []const u8,
) !StrictTreeSummary {
    for (strict_patch_specs) |spec| {
        const patch_path = try std.fs.path.join(allocator, &.{ recipe_root, spec.relative_path });
        defer allocator.free(patch_path);
        try requireStrictRegularFile(io, patch_path);

        const working_directory = if (spec.working_directory.len == 0)
            try allocator.dupe(u8, destination_path)
        else
            try std.fs.path.join(allocator, &.{ destination_path, spec.working_directory });
        defer allocator.free(working_directory);
        try requireStrictDirectory(io, working_directory);

        var check_argv = [_][]const u8{
            git,
            "apply",
            "--check",
            "--no-index",
            "--whitespace=error-all",
            "--recount",
            "--",
            patch_path,
        };
        const check_output = try runStrictTool(allocator, io, environment, working_directory, &check_argv);
        allocator.free(check_output);

        var apply_argv = [_][]const u8{
            git,
            "apply",
            "--no-index",
            "--whitespace=error-all",
            "--recount",
            "--",
            patch_path,
        };
        const apply_output = try runStrictTool(allocator, io, environment, working_directory, &apply_argv);
        allocator.free(apply_output);
    }
    try writeStrictPdfiumResource(io, destination_path);
    return hashStrictTree(allocator, io, destination_path);
}

const StrictPreparedPdfiumSource = struct {
    root_path: []u8,
    source_path: []u8,
    summary: StrictTreeSummary,
};

fn strictPdfiumSourcePath(
    allocator: std.mem.Allocator,
    closure_root: []const u8,
) ![]u8 {
    const path = try std.fs.path.join(allocator, &.{ closure_root, locked_pdfium_source_subpath });
    errdefer allocator.free(path);
    if (!strictPathWithin(closure_root, path)) return error.ControllerPathNotContained;
    return path;
}

fn prepareStrictPdfiumSource(
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    git: []const u8,
    repro_root: []const u8,
    source_closure_root: []const u8,
    recipe_root: []const u8,
    expected_closure: StrictTreeSummary,
) !StrictPreparedPdfiumSource {
    const destination_path = try std.fs.path.join(allocator, &.{ repro_root, "source" });
    errdefer allocator.free(destination_path);
    if (!strictPathWithin(repro_root, destination_path)) return error.ControllerPathNotContained;
    try requireStrictAbsent(io, destination_path);
    var destination = try createStrictDirectoryPath(io, repro_root, destination_path);
    destination.close(io);
    try copyStrictTree(allocator, io, source_closure_root, destination_path, expected_closure);
    const source_path = try strictPdfiumSourcePath(allocator, destination_path);
    errdefer allocator.free(source_path);
    try requireStrictDirectory(io, source_path);
    const patched_summary = try applyStrictPdfiumPatches(
        allocator,
        io,
        environment,
        git,
        recipe_root,
        source_path,
    );
    return .{
        .root_path = destination_path,
        .source_path = source_path,
        .summary = patched_summary,
    };
}

fn hashStrictFileEntry(io: std.Io, directory: std.Io.Dir, basename: []const u8) !StrictFileSummary {
    var nofollow = try directory.openFile(io, basename, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    });
    defer nofollow.close(io);
    const before = try nofollow.stat(io);
    if (before.kind != .file) return error.ReparsePointInInput;
    if (before.size > maximum_controller_tree_bytes) return error.ControllerInputTooLarge;

    // Zig's Windows no-follow handle is intentionally opened with
    // FILE_OPEN_REPARSE_POINT and is not readable on all supported NTFS
    // configurations.  Use a second readable handle, but bind it to the
    // no-follow file identity before and after the read; a path swap or
    // reparse substitution therefore fails closed instead of changing the
    // bytes being measured.
    var file = try directory.openFile(io, basename, .{
        .allow_directory = false,
        .follow_symlinks = true,
        .resolve_beneath = true,
    });
    defer file.close(io);
    const opened = try file.stat(io);
    if (opened.kind != .file or opened.inode != before.inode or opened.size != before.size) {
        return error.InputChangedDuringHash;
    }

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var reader_buffer: [64 * 1024]u8 = undefined;
    var reader = file.reader(io, &reader_buffer);
    var chunk: [64 * 1024]u8 = undefined;
    var bytes: u64 = 0;
    while (true) {
        const count = reader.interface.readSliceShort(&chunk) catch
            return reader.err orelse error.ReadFailed;
        if (count == 0) break;
        bytes = std.math.add(u64, bytes, count) catch return error.ControllerInputTooLarge;
        if (bytes > maximum_controller_tree_bytes) return error.ControllerInputTooLarge;
        hasher.update(chunk[0..count]);
    }
    const after = try file.stat(io);
    if (after.kind != .file or after.inode != before.inode or after.size != before.size or bytes != before.size) {
        return error.InputChangedDuringHash;
    }
    var final_nofollow = try directory.openFile(io, basename, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    });
    defer final_nofollow.close(io);
    const final = try final_nofollow.stat(io);
    if (final.kind != .file or final.inode != before.inode or final.size != before.size) {
        return error.InputChangedDuringHash;
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return .{ .bytes = bytes, .digest = digest };
}

fn strictHexDigestAlloc(allocator: std.mem.Allocator, digest: [32]u8) ![]u8 {
    const text = std.fmt.bytesToHex(digest, .lower);
    return allocator.dupe(u8, &text);
}

fn strictDigestMatches(digest: [32]u8, expected: []const u8) bool {
    const text = std.fmt.bytesToHex(digest, .lower);
    return std.mem.eql(u8, &text, expected);
}

fn collectHostedRunIdentity(
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
) !HostedRunIdentity {
    const actions = try strictRequiredEnv(environment, "GITHUB_ACTIONS");
    const ci = try strictRequiredEnv(environment, "CI");
    if (!std.mem.eql(u8, actions, "true") or !std.mem.eql(u8, ci, "true")) {
        return error.NotHostedGitHubActions;
    }

    const server_url = try strictRequiredEnv(environment, "GITHUB_SERVER_URL");
    const repository = try strictRequiredEnv(environment, "GITHUB_REPOSITORY");
    const workflow = try strictRequiredEnv(environment, "GITHUB_WORKFLOW");
    const workflow_ref = try strictRequiredEnv(environment, "GITHUB_WORKFLOW_REF");
    const job = try strictRequiredEnv(environment, "GITHUB_JOB");
    const run_id = try strictRequiredEnv(environment, "GITHUB_RUN_ID");
    const run_attempt = try strictRequiredEnv(environment, "GITHUB_RUN_ATTEMPT");
    const head_sha = try strictRequiredEnv(environment, "GITHUB_SHA");
    const ref = try strictRequiredEnv(environment, "GITHUB_REF");
    const runner_environment = try strictRequiredEnv(environment, "RUNNER_ENVIRONMENT");
    const runner_os = try strictRequiredEnv(environment, "RUNNER_OS");
    const runner_arch = try strictRequiredEnv(environment, "RUNNER_ARCH");
    const workspace = try strictRequiredEnv(environment, "GITHUB_WORKSPACE");
    const git = try strictRequiredEnv(environment, "TEXFLOW_GIT_PATH");
    const image_os = environment.get("ImageOS") orelse
        environment.get("TEXFLOW_PDFIUM_IMAGE_OS") orelse return error.MissingRunnerInput;
    const image_version = environment.get("ImageVersion") orelse
        environment.get("TEXFLOW_PDFIUM_IMAGE_VERSION") orelse return error.MissingRunnerInput;
    const runner_name = try strictRequiredEnv(environment, "RUNNER_NAME");

    if (!std.mem.eql(u8, server_url, "https://github.com") or
        !std.mem.eql(u8, repository, "ndak79/Oleafly") or
        !std.mem.eql(u8, workflow, "TExFlow native checks") or
        !std.mem.startsWith(u8, workflow_ref, "ndak79/Oleafly/.github/workflows/zig.yml@") or
        (!std.mem.eql(u8, runner_environment, "github-hosted") and
            !std.mem.eql(u8, runner_environment, "self-hosted")) or
        !std.mem.eql(u8, runner_arch, "X64"))
    {
        return error.InvalidHostedRunIdentity;
    }
    if (!std.mem.eql(u8, runner_os, "Windows") and !std.mem.eql(u8, runner_os, "Linux")) {
        return error.InvalidHostedRunIdentity;
    }
    try validateStrictNonzeroDecimal(run_id);
    try validateStrictNonzeroDecimal(run_attempt);
    try validateLowerHex(head_sha, 40);
    try validateStrictInputPath(workspace);
    try validateStrictToolPath(git);
    try requireStrictRegularFile(io, git);
    try validateHostedJob(job);
    inline for (.{ server_url, repository, workflow, workflow_ref, job, ref, image_os, image_version }) |value| {
        try validateStrictText(value);
    }
    if (std.mem.indexOfScalar(u8, ref, '\\') != null) return error.InvalidHostedRunIdentity;
    const workflow_ref_prefix = "ndak79/Oleafly/.github/workflows/zig.yml@";
    if (!std.mem.eql(u8, workflow_ref[workflow_ref_prefix.len..], ref)) {
        return error.InvalidHostedRunIdentity;
    }
    var git_environment = try makeScrubbedGitEnvironment(allocator, environment);
    defer git_environment.deinit();
    const actual_head = try runGitValue(allocator, io, &git_environment, git, workspace, "HEAD");
    defer allocator.free(actual_head);
    if (!std.mem.eql(u8, actual_head, head_sha)) return error.HostedCheckoutMismatch;

    const runner_name_digest = receiptDigest(runner_name);
    const runner_name_sha256 = try strictHexDigestAlloc(allocator, runner_name_digest);
    const run_url = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}/actions/runs/{s}",
        .{ server_url, repository, run_id },
    );
    const image_identity_sha256 = environment.get("TEXFLOW_PDFIUM_RUNNER_IMAGE_SHA256") orelse "";
    if (image_identity_sha256.len != 0) try validateLowerHex(image_identity_sha256, 64);

    return .{
        .server_url = server_url,
        .repository = repository,
        .workflow = workflow,
        .workflow_ref = workflow_ref,
        .job = job,
        .run_id = run_id,
        .run_attempt = run_attempt,
        .head_sha = head_sha,
        .ref = ref,
        .run_url = run_url,
        .runner_environment = runner_environment,
        .runner_os = runner_os,
        .runner_arch = runner_arch,
        .image_os = image_os,
        .image_version = image_version,
        .runner_name_sha256 = runner_name_sha256,
        .image_identity_sha256 = image_identity_sha256,
    };
}

fn validateHostedRunIdentity(identity: HostedRunIdentity) !void {
    if (!std.mem.eql(u8, identity.server_url, "https://github.com") or
        !std.mem.eql(u8, identity.repository, "ndak79/Oleafly") or
        !std.mem.eql(u8, identity.workflow, "TExFlow native checks") or
        !std.mem.startsWith(u8, identity.workflow_ref, "ndak79/Oleafly/.github/workflows/zig.yml@") or
        (!std.mem.eql(u8, identity.runner_environment, "github-hosted") and
            !std.mem.eql(u8, identity.runner_environment, "self-hosted")) or
        !std.mem.eql(u8, identity.runner_arch, "X64"))
    {
        return error.InvalidHostedRunIdentity;
    }
    if (!std.mem.eql(u8, identity.runner_os, "Windows") and
        !std.mem.eql(u8, identity.runner_os, "Linux")) return error.InvalidHostedRunIdentity;
    try validateStrictNonzeroDecimal(identity.run_id);
    try validateStrictNonzeroDecimal(identity.run_attempt);
    try validateLowerHex(identity.head_sha, 40);
    try validateHostedJob(identity.job);
    try validateLowerHex(identity.runner_name_sha256, 64);
    if (identity.image_identity_sha256.len != 0) try validateLowerHex(identity.image_identity_sha256, 64);
    inline for (.{
        identity.server_url,
        identity.repository,
        identity.workflow,
        identity.workflow_ref,
        identity.job,
        identity.ref,
        identity.run_url,
        identity.runner_environment,
        identity.runner_os,
        identity.image_os,
        identity.image_version,
    }) |value| try validateStrictText(value);
    const expected_run_url = try std.fmt.allocPrint(
        std.heap.page_allocator,
        "{s}/{s}/actions/runs/{s}",
        .{ identity.server_url, identity.repository, identity.run_id },
    );
    defer std.heap.page_allocator.free(expected_run_url);
    if (!std.mem.eql(u8, identity.run_url, expected_run_url)) return error.InvalidHostedRunIdentity;
    const workflow_ref_prefix = "ndak79/Oleafly/.github/workflows/zig.yml@";
    if (!std.mem.eql(u8, identity.workflow_ref[workflow_ref_prefix.len..], identity.ref)) {
        return error.InvalidHostedRunIdentity;
    }
}

fn validateHostedJob(job: []const u8) !void {
    for ([_][]const u8{
        "zig-windows",
        "zig-linux",
        "pdfium-reconstruction-scope",
        "pdfium-reconstruction",
        "pdfium-retention-revalidation",
        "pdfium-retention-delayed",
    }) |allowed| {
        if (std.mem.eql(u8, job, allowed)) return;
    }
    return error.InvalidHostedRunIdentity;
}

fn makeScrubbedGitEnvironment(
    allocator: std.mem.Allocator,
    parent: *const std.process.Environ.Map,
) !std.process.Environ.Map {
    var environment = std.process.Environ.Map.init(allocator);
    errdefer environment.deinit();
    if (builtin.os.tag == .windows) {
        const system_root = parent.get("SystemRoot") orelse return error.MissingSystemRoot;
        try validateStrictInputPath(system_root);
        try environment.put("SystemRoot", system_root);
        try environment.put("WINDIR", system_root);
    }
    try environment.put("GIT_CONFIG_NOSYSTEM", "1");
    try environment.put("GIT_CONFIG_GLOBAL", if (builtin.os.tag == .windows) "NUL" else "/dev/null");
    try environment.put("GIT_CONFIG_SYSTEM", if (builtin.os.tag == .windows) "NUL" else "/dev/null");
    try environment.put("GIT_ATTR_NOSYSTEM", "1");
    try environment.put("GIT_NO_REPLACE_OBJECTS", "1");
    try environment.put("GIT_OPTIONAL_LOCKS", "0");
    try environment.put("GIT_TERMINAL_PROMPT", "0");
    try environment.put("GIT_PAGER", "cat");
    try environment.put("GIT_EDITOR", "true");
    try environment.put("GIT_SEQUENCE_EDITOR", "true");
    try environment.put("LC_ALL", "C");
    return environment;
}

fn sameHostedRunLineage(left: HostedRunIdentity, right: HostedRunIdentity) bool {
    return std.mem.eql(u8, left.server_url, right.server_url) and
        std.mem.eql(u8, left.repository, right.repository) and
        std.mem.eql(u8, left.workflow, right.workflow) and
        std.mem.eql(u8, left.workflow_ref, right.workflow_ref) and
        std.mem.eql(u8, left.run_id, right.run_id) and
        std.mem.eql(u8, left.run_attempt, right.run_attempt) and
        std.mem.eql(u8, left.head_sha, right.head_sha) and
        std.mem.eql(u8, left.ref, right.ref) and
        std.mem.eql(u8, left.run_url, right.run_url);
}

fn sameHostedRun(left: HostedRunIdentity, right: HostedRunIdentity) bool {
    return std.mem.eql(u8, left.server_url, right.server_url) and
        std.mem.eql(u8, left.repository, right.repository) and
        std.mem.eql(u8, left.workflow, right.workflow) and
        std.mem.eql(u8, left.workflow_ref, right.workflow_ref) and
        std.mem.eql(u8, left.job, right.job) and
        std.mem.eql(u8, left.run_id, right.run_id) and
        std.mem.eql(u8, left.run_attempt, right.run_attempt) and
        std.mem.eql(u8, left.head_sha, right.head_sha) and
        std.mem.eql(u8, left.ref, right.ref) and
        std.mem.eql(u8, left.run_url, right.run_url) and
        std.mem.eql(u8, left.runner_environment, right.runner_environment) and
        std.mem.eql(u8, left.runner_os, right.runner_os) and
        std.mem.eql(u8, left.runner_arch, right.runner_arch) and
        std.mem.eql(u8, left.image_os, right.image_os) and
        std.mem.eql(u8, left.image_version, right.image_version) and
        std.mem.eql(u8, left.runner_name_sha256, right.runner_name_sha256) and
        std.mem.eql(u8, left.image_identity_sha256, right.image_identity_sha256);
}

fn validateDelayedRetentionRunner(
    current: HostedRunIdentity,
    source: HostedRunIdentity,
) !void {
    if (!std.mem.eql(u8, current.runner_environment, "self-hosted") or
        !std.mem.eql(u8, current.runner_os, "Windows") or
        !std.mem.eql(u8, current.runner_arch, "X64") or
        !std.mem.eql(u8, current.job, "pdfium-retention-delayed") or
        current.image_identity_sha256.len == 0 or
        std.mem.eql(u8, current.runner_name_sha256, source.runner_name_sha256))
    {
        return error.IndependentRunnerRequired;
    }
}

fn validateNoProxyEnvironment(environment: *const std.process.Environ.Map) !void {
    const names = [_][]const u8{
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy",
        "GIT_PROXY_COMMAND",
        "NODE_EXTRA_CA_CERTS",
    };
    for (names) |name| {
        if (environment.get(name)) |value| if (value.len != 0) return error.ProxyOrCredentialEnvironment;
    }
}

/// Validate the checked-in reconstruction lock without treating it as
/// measured evidence. It intentionally starts as an unverified skeleton;
/// promotion to `approved` is allowed only after a qualified runner supplies
/// every measured identity and the strict controller revalidates it.
pub fn validateTrackedToolchainLock(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !void {
    if (bytes.len == 0 or bytes.len > max_receipt_bytes) return error.InvalidReceiptSize;
    var parsed = try std.json.parseFromSlice(StrictApprovedReceipt, allocator, bytes, .{
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
    });
    defer parsed.deinit();
    const receipt = parsed.value;
    if (receipt.schema_version != 1 or
        !std.mem.eql(u8, receipt.receipt_kind, approved_receipt_kind) or
        !std.mem.eql(u8, receipt.target, "x86_64-windows-msvc"))
    {
        return error.InvalidApprovedReceipt;
    }
    try validateStrictLockedPins(receipt);
    try validateStrictGnArgList(receipt.gn_args);
    if (std.mem.eql(u8, receipt.status, "approved")) {
        try validateApprovedReceipt(receipt);
        return;
    }
    if (!std.mem.eql(u8, receipt.status, "unverified")) return error.InvalidApprovedReceipt;

    if (receipt.patched_pdfium_tree_sha256.len != 0 or
        receipt.patched_pdfium_files != 0 or
        receipt.patched_pdfium_bytes != 0 or
        receipt.recipe_tree_sha256.len != 0 or
        receipt.source_closure_sha256.len != 0 or
        receipt.source_closure_files != 0 or
        receipt.source_closure_bytes != 0 or
        receipt.output_sha256.len != 0 or
        receipt.output_size_bytes != 0 or
        receipt.build_identity_sha256.len != 0)
    {
        return error.InvalidUnverifiedToolchainLock;
    }
    const toolchain = receipt.toolchain;
    if (toolchain.windows_sdk_version.len != 0 or
        toolchain.runner_image_sha256.len != 0 or
        toolchain.visual_studio_sha256.len != 0 or
        toolchain.windows_sdk_sha256.len != 0 or
        toolchain.toolchain_closure_sha256.len != 0 or
        toolchain.git_sha256.len != 0 or
        toolchain.gn_sha256.len != 0 or
        toolchain.ninja_sha256.len != 0 or
        toolchain.compiler_sha256.len != 0 or
        toolchain.linker_sha256.len != 0 or
        toolchain.python_sha256.len != 0 or
        toolchain.resource_compiler_sha256.len != 0)
    {
        return error.InvalidUnverifiedToolchainLock;
    }
}

fn validateStrictLockedPins(receipt: StrictApprovedReceipt) !void {
    if (!std.mem.eql(u8, receipt.pdfium_commit, locked_pdfium_commit) or
        !std.mem.eql(u8, receipt.pdfium_tree_sha256, locked_pdfium_tree_sha256) or
        !std.mem.eql(u8, receipt.recipe_commit, locked_recipe_commit) or
        !std.mem.eql(u8, receipt.recipe_archive_sha256, locked_recipe_archive_sha256) or
        !std.mem.eql(u8, receipt.depot_tools_commit, locked_depot_tools_commit) or
        !std.mem.eql(u8, receipt.depot_tools_tree_sha1, locked_depot_tools_tree_sha1))
    {
        return error.LockedPinMismatch;
    }
    inline for (.{
        receipt.pdfium_commit,
        receipt.recipe_commit,
        receipt.depot_tools_commit,
        receipt.depot_tools_tree_sha1,
    }) |value| try validateLowerHex(value, 40);
    try validateLowerHex(receipt.pdfium_tree_sha256, 64);
    try validateLowerHex(receipt.recipe_archive_sha256, 64);
}

fn validateStrictMeasuredToolchain(toolchain: StrictToolchainExpectation) !void {
    try validateLowerHex(toolchain.runner_image_sha256, 64);
    try validateLowerHex(toolchain.visual_studio_sha256, 64);
    try validateLowerHex(toolchain.windows_sdk_sha256, 64);
    try validateLowerHex(toolchain.toolchain_closure_sha256, 64);
    inline for (.{
        toolchain.git_sha256,
        toolchain.gn_sha256,
        toolchain.ninja_sha256,
        toolchain.compiler_sha256,
        toolchain.linker_sha256,
        toolchain.python_sha256,
        toolchain.resource_compiler_sha256,
    }) |value| try validateLowerHex(value, 64);
    if (!std.mem.eql(u8, toolchain.windows_sdk_version, "10.0.28000.0")) {
        return error.ToolchainIdentityMismatch;
    }
}

/// A resolve candidate carries measured inputs but is never accepted by the
/// reconstruction gate.  Promotion still requires a human-reviewed exact
/// copy into the tracked approved lock.
fn validateResolveCandidate(receipt: StrictApprovedReceipt) !void {
    if (receipt.schema_version != 1 or
        !std.mem.eql(u8, receipt.receipt_kind, resolve_candidate_receipt_kind) or
        !std.mem.eql(u8, receipt.status, "candidate") or
        !std.mem.eql(u8, receipt.target, "x86_64-windows-msvc"))
    {
        return error.InvalidResolveCandidate;
    }
    try validateStrictLockedPins(receipt);
    try validateStrictGnArgList(receipt.gn_args);
    inline for (.{
        receipt.pdfium_tree_sha256,
        receipt.patched_pdfium_tree_sha256,
        receipt.recipe_tree_sha256,
        receipt.source_closure_sha256,
    }) |value| try validateLowerHex(value, 64);
    if (receipt.patched_pdfium_files == 0 or receipt.patched_pdfium_bytes == 0 or
        receipt.source_closure_files == 0 or receipt.source_closure_bytes == 0 or
        receipt.output_sha256.len != 0 or receipt.output_size_bytes != 0 or
        receipt.build_identity_sha256.len != 0)
    {
        return error.InvalidResolveCandidate;
    }
    try validateStrictMeasuredToolchain(receipt.toolchain);
}

fn validateStrictGnArgList(args: []const []const u8) !void {
    if (args.len != strict_required_gn_args.len) return error.UnexpectedGnArg;
    for (args, strict_required_gn_args) |actual, expected| {
        if (!std.mem.eql(u8, actual, expected)) return error.UnexpectedGnArg;
    }
}

fn validateApprovedReceipt(receipt: StrictApprovedReceipt) !void {
    if (receipt.schema_version != 1 or !std.mem.eql(u8, receipt.receipt_kind, approved_receipt_kind) or
        !std.mem.eql(u8, receipt.status, "approved") or
        !std.mem.eql(u8, receipt.target, "x86_64-windows-msvc"))
    {
        return error.InvalidApprovedReceipt;
    }
    try validateStrictLockedPins(receipt);
    inline for (.{
        receipt.pdfium_tree_sha256,
        receipt.patched_pdfium_tree_sha256,
        receipt.recipe_archive_sha256,
        receipt.recipe_tree_sha256,
        receipt.source_closure_sha256,
        receipt.output_sha256,
        receipt.build_identity_sha256,
    }) |value| try validateLowerHex(value, 64);
    if (receipt.patched_pdfium_files == 0 or receipt.patched_pdfium_bytes == 0 or
        receipt.source_closure_files == 0 or receipt.source_closure_bytes == 0 or
        receipt.output_size_bytes < 1024 * 1024 or
        std.mem.eql(u8, receipt.output_sha256, locked_reference_dll_sha256))
    {
        return error.InvalidApprovedReceipt;
    }
    if (receipt.gn_args.len != strict_required_gn_args.len) return error.UnexpectedGnArg;
    for (receipt.gn_args, strict_required_gn_args) |actual, expected| {
        if (!std.mem.eql(u8, actual, expected)) return error.UnexpectedGnArg;
    }
    const toolchain = receipt.toolchain;
    try validateLowerHex(toolchain.runner_image_sha256, 64);
    try validateLowerHex(toolchain.visual_studio_sha256, 64);
    try validateLowerHex(toolchain.windows_sdk_sha256, 64);
    try validateLowerHex(toolchain.toolchain_closure_sha256, 64);
    inline for (.{
        toolchain.git_sha256,
        toolchain.gn_sha256,
        toolchain.ninja_sha256,
        toolchain.compiler_sha256,
        toolchain.linker_sha256,
        toolchain.python_sha256,
        toolchain.resource_compiler_sha256,
    }) |value| try validateLowerHex(value, 64);
    if (!std.mem.eql(u8, toolchain.windows_sdk_version, "10.0.28000.0")) {
        return error.ToolchainIdentityMismatch;
    }
}

fn probeStrictResources(io: std.Io, repro_root: []const u8) !StrictResourceEvidence {
    if (builtin.os.tag != .windows) return error.PdfiumTargetRequiresWindows;
    var utf16: [32768]u16 = undefined;
    if (repro_root.len >= utf16.len) return error.UnsafeControllerPath;
    const length = std.unicode.utf8ToUtf16Le(utf16[0 .. utf16.len - 1], repro_root) catch
        return error.InvalidReproRoot;
    utf16[length] = 0;
    var free_bytes: u64 = 0;
    var total_bytes: u64 = 0;
    var total_free_bytes: u64 = 0;
    if (GetDiskFreeSpaceExW(
        utf16[0..length :0].ptr,
        &free_bytes,
        &total_bytes,
        &total_free_bytes,
    ) == 0) return error.ResourceProbeFailed;
    _ = io;
    var memory: WindowsMemoryStatusEx = .{
        .dw_length = @sizeOf(WindowsMemoryStatusEx),
        .dw_memory_load = 0,
        .ull_total_phys = 0,
        .ull_avail_phys = 0,
        .ull_total_page_file = 0,
        .ull_avail_page_file = 0,
        .ull_total_virtual = 0,
        .ull_avail_virtual = 0,
        .ull_avail_extended_virtual = 0,
    };
    if (GlobalMemoryStatusEx(&memory) == 0) return error.ResourceProbeFailed;
    if (free_bytes < minimum_repro_disk_bytes) return error.InsufficientReproDisk;
    if (memory.ull_total_phys < minimum_repro_memory_bytes) return error.InsufficientReproMemory;
    return .{
        .free_space_bytes = free_bytes,
        .physical_memory_bytes = memory.ull_total_phys,
    };
}

fn makeScrubbedBuildEnvironment(
    allocator: std.mem.Allocator,
    parent: *const std.process.Environ.Map,
    repro_root: []const u8,
    depot_tools_root: []const u8,
    tools: StrictToolPaths,
) !std.process.Environ.Map {
    var environment = std.process.Environ.Map.init(allocator);
    errdefer environment.deinit();

    if (builtin.os.tag == .windows) {
        const system_root = parent.get("SystemRoot") orelse return error.MissingSystemRoot;
        try validateStrictInputPath(system_root);
        try environment.put("SystemRoot", system_root);
        try environment.put("WINDIR", system_root);
    }
    try environment.put("HOME", repro_root);
    try environment.put("USERPROFILE", repro_root);
    try environment.put("TEMP", repro_root);
    try environment.put("TMP", repro_root);
    try environment.put("GIT_TERMINAL_PROMPT", "0");
    try environment.put("GIT_CONFIG_NOSYSTEM", "1");
    try environment.put("GIT_CONFIG_GLOBAL", if (builtin.os.tag == .windows) "NUL" else "/dev/null");
    try environment.put("GIT_CONFIG_SYSTEM", if (builtin.os.tag == .windows) "NUL" else "/dev/null");
    try environment.put("GIT_ATTR_NOSYSTEM", "1");
    try environment.put("GIT_NO_REPLACE_OBJECTS", "1");
    try environment.put("GIT_OPTIONAL_LOCKS", "0");
    try environment.put("PYTHONNOUSERSITE", "1");
    try environment.put("DEPOT_TOOLS_WIN_TOOLCHAIN", "0");
    try environment.put("DEPOT_TOOLS_UPDATE", "0");
    try environment.put("VPYTHON_BYPASS", "0");

    var directories: std.ArrayList([]const u8) = .empty;
    defer directories.deinit(allocator);
    // The recipe invokes `rc.exe` by basename. Put the hash-verified
    // resource compiler directory first so PATH lookup cannot select an
    // ambient SDK copy or another tool with the same basename.
    const resource_compiler_directory = std.fs.path.dirname(tools.resource_compiler) orelse
        return error.UnsafeControllerPath;
    try directories.append(allocator, resource_compiler_directory);
    try directories.append(allocator, depot_tools_root);
    inline for (.{
        tools.git,
        tools.gn,
        tools.ninja,
        tools.compiler,
        tools.linker,
        tools.python,
    }) |path| {
        const directory = std.fs.path.dirname(path) orelse return error.UnsafeControllerPath;
        try directories.append(allocator, directory);
    }
    if (builtin.os.tag == .windows) {
        const system_root = parent.get("SystemRoot") orelse return error.MissingSystemRoot;
        const system32 = try std.fs.path.join(allocator, &.{ system_root, "System32" });
        defer allocator.free(system32);
        try directories.append(allocator, system32);
    }
    const path_value = try std.mem.join(
        allocator,
        if (builtin.os.tag == .windows) ";" else ":",
        directories.items,
    );
    defer allocator.free(path_value);
    try environment.put("PATH", path_value);
    return environment;
}

fn runStrictTool(
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    cwd: []const u8,
    argv: []const []const u8,
) ![]u8 {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .environ_map = environment,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
        .timeout = .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(180 * 60) } },
        .create_no_window = true,
    });
    defer allocator.free(result.stderr);
    errdefer allocator.free(result.stdout);
    switch (result.term) {
        .exited => |code| if (code != 0) return error.ExternalToolFailed,
        else => return error.ExternalToolTerminated,
    }
    return result.stdout;
}

fn probeStrictNetworkCanary(
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    git: []const u8,
    cwd: []const u8,
) !void {
    const argv = [_][]const u8{
        git,
        "-C",
        cwd,
        "ls-remote",
        "--exit-code",
        "https://github.com/ndak79/Oleafly.git",
        "HEAD",
    };
    const result = try std.process.run(allocator, io, .{
        .argv = &argv,
        .cwd = .{ .path = cwd },
        .environ_map = environment,
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(64 * 1024),
        .timeout = .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(15) } },
        .create_no_window = true,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| {
            if (code == 0) return error.NetworkCanaryReached;
            try requireStrictNetworkBlock(result.stdout, result.stderr);
        },
        else => return error.NetworkCanaryUnverified,
    }
}

fn requireStrictNetworkBlock(stdout: []const u8, stderr: []const u8) !void {
    if (stdout.len != 0 or stderr.len == 0) return error.NetworkCanaryUnverified;
    for ([_][]const u8{
        "could not resolve",
        "failed to connect",
        "couldn't connect",
        "connection timed out",
        "network is unreachable",
        "no route to host",
        "connection reset",
        "connection was forcibly closed",
        "unable to access",
    }) |marker| {
        if (std.ascii.indexOfIgnoreCase(stderr, marker) != null) return;
    }
    return error.NetworkCanaryUnverified;
}

fn runGitValue(
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    git: []const u8,
    repository: []const u8,
    verb: []const u8,
) ![]u8 {
    var argv = [_][]const u8{ git, "-C", repository, "rev-parse", verb };
    const output = try runStrictTool(allocator, io, environment, repository, &argv);
    defer allocator.free(output);
    const value = std.mem.trim(u8, output, " \t\r\n");
    if (value.len == 0) return error.InvalidGitIdentity;
    return allocator.dupe(u8, value);
}

fn requireGitClean(
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    git: []const u8,
    repository: []const u8,
) !void {
    var argv = [_][]const u8{
        git,
        "-C",
        repository,
        "status",
        "--porcelain=v1",
        "--untracked-files=all",
    };
    const output = try runStrictTool(allocator, io, environment, repository, &argv);
    defer allocator.free(output);
    if (std.mem.trim(u8, output, " \t\r\n").len != 0) return error.SourceTreeDirty;
}

fn verifyStrictToolDigest(io: std.Io, path: []const u8, expected: []const u8) !void {
    const summary = try hashStrictFile(io, path, maximum_controller_input_bytes);
    if (!strictDigestMatches(summary.digest, expected)) return error.ToolchainIdentityMismatch;
}

fn strictAttestationValue(line: []const u8, key: []const u8) ![]const u8 {
    if (!std.mem.startsWith(u8, line, key) or line.len <= key.len or line[key.len] != '=') {
        return error.InvalidNetworkAttestation;
    }
    const value = line[key.len + 1 ..];
    try validateStrictText(value);
    return value;
}

fn validateNetworkAttestation(
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    path: []const u8,
    identity: HostedRunIdentity,
    repro_root: []const u8,
    workspace: []const u8,
) ![]u8 {
    try validateStrictInputPath(path);
    try requireStrictOutside(path, workspace, repro_root);
    const bytes = try readStrictFileAlloc(allocator, io, path, 16 * 1024);
    defer allocator.free(bytes);
    const expected_digest = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_NETWORK_ATTESTATION_SHA256");
    try validateLowerHex(expected_digest, 64);
    const file_summary = try hashStrictFile(io, path, 16 * 1024);
    if (!strictDigestMatches(file_summary.digest, expected_digest)) {
        return error.NetworkAttestationDigestMismatch;
    }

    const expected_keys = [_][]const u8{
        "schema",
        "origin",
        "mode",
        "run_id",
        "run_attempt",
        "head_sha",
        "route_count",
        "negative_fetch_bytes",
        "proxy",
        "process_policy",
    };
    var values: [expected_keys.len][]const u8 = undefined;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    for (expected_keys, 0..) |key, index| {
        const line = lines.next() orelse return error.InvalidNetworkAttestation;
        if (line.len == 0) return error.InvalidNetworkAttestation;
        values[index] = try strictAttestationValue(line, key);
    }
    if (lines.next()) |trailing| if (trailing.len != 0) return error.InvalidNetworkAttestation;

    if (!std.mem.eql(u8, values[0], network_attestation_schema) or
        !std.mem.eql(u8, values[1], "runner-control-plane") or
        !std.mem.eql(u8, values[2], "detached-nic") or
        !std.mem.eql(u8, values[3], identity.run_id) or
        !std.mem.eql(u8, values[4], identity.run_attempt) or
        !std.mem.eql(u8, values[5], identity.head_sha) or
        !std.mem.eql(u8, values[6], "0") or
        !std.mem.eql(u8, values[7], "0") or
        !std.mem.eql(u8, values[8], "unset") or
        !std.mem.eql(u8, values[9], "zig-owned"))
    {
        return error.NetworkIsolationUnverified;
    }
    return allocator.dupe(u8, expected_digest);
}

fn probeStrictRoutes(
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    cwd: []const u8,
) !StrictRouteEvidence {
    if (builtin.os.tag == .windows) {
        const system_root = environment.get("SystemRoot") orelse return error.MissingSystemRoot;
        const route_path = try std.fs.path.join(allocator, &.{ system_root, "System32", "route.exe" });
        defer allocator.free(route_path);
        var argv = [_][]const u8{ route_path, "PRINT" };
        const output = try runStrictTool(allocator, io, environment, cwd, &argv);
        defer allocator.free(output);
        return countStrictRoutes(output, true);
    }
    const ip_path = "/bin/ip";
    try requireStrictRegularFile(io, ip_path);
    var argv = [_][]const u8{ ip_path, "route", "show" };
    const output = try runStrictTool(allocator, io, environment, cwd, &argv);
    defer allocator.free(output);
    return countStrictRoutes(output, false);
}

fn countStrictRoutes(output: []const u8, windows: bool) !StrictRouteEvidence {
    var route_count: u64 = 0;
    var default_route = false;
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (windows) {
            var fields = std.mem.tokenizeAny(u8, line, " \t");
            const destination = fields.next() orelse continue;
            const mask = fields.next() orelse continue;
            if (std.mem.eql(u8, destination, "0.0.0.0") and std.mem.eql(u8, mask, "0.0.0.0")) {
                route_count += 1;
                default_route = true;
            } else if (parseStrictIpv4(destination)) |destination_value| {
                const mask_value = parseStrictIpv4(mask) orelse continue;
                // A detached Windows runner may retain only the loopback
                // 127/8 route. Every other IPv4 route is usable network
                // reachability and must invalidate the attestation, even
                // when it is not a default route.
                if ((destination_value & 0xff00_0000) != 0x7f00_0000 or
                    (mask_value & 0xff00_0000) != 0xff00_0000)
                {
                    route_count += 1;
                }
            } else {
                // IPv6 `route PRINT` rows begin with interface and metric,
                // unlike IPv4 rows. Find the CIDR destination rather than
                // assuming it is the first token.
                var ipv6_destination: ?[]const u8 =
                    if (std.mem.indexOfScalar(u8, destination, ':') != null) destination else null;
                while (ipv6_destination == null) {
                    const field = fields.next() orelse break;
                    if (std.mem.indexOfScalar(u8, field, ':') != null) ipv6_destination = field;
                }
                if (ipv6_destination) |destination_value| {
                    // Only the IPv6 loopback host route is permitted;
                    // link-local, multicast, and any other interface route
                    // are not.
                    if (!std.mem.eql(u8, destination_value, "::1/128")) {
                        if (std.mem.eql(u8, destination_value, "::/0")) default_route = true;
                        route_count += 1;
                    }
                }
            }
        } else if (!std.mem.startsWith(u8, line, "default") and
            std.mem.indexOf(u8, line, " dev lo") == null and
            !std.mem.eql(u8, line, "dev lo"))
        {
            route_count += 1;
        } else if (std.mem.startsWith(u8, line, "default")) {
            route_count += 1;
            default_route = true;
        }
    }
    if (route_count != 0) return error.NetworkIsolationUnverified;
    return .{ .route_count = route_count, .default_route_present = default_route };
}

fn parseStrictIpv4(value: []const u8) ?u32 {
    var parts = std.mem.splitScalar(u8, value, '.');
    var result: u32 = 0;
    var count: usize = 0;
    while (parts.next()) |part| {
        if (count == 4 or part.len == 0) return null;
        const octet = std.fmt.parseUnsigned(u8, part, 10) catch return null;
        result = (result << 8) | octet;
        count += 1;
    }
    return if (count == 4) result else null;
}

fn validateRecipeInputs(io: std.Io, recipe_root: []const u8) !void {
    const required_files = [_][]const u8{
        "patches/clang_rt.patch",
        "patches/public_headers.patch",
        "patches/shared_library.patch",
        "patches/win/build.patch",
        "patches/win/resources.rc",
        "steps/02-checkout.sh",
        "steps/03-patch.sh",
        "steps/05-configure.sh",
        "steps/06-build.sh",
    };
    for (required_files) |relative| {
        const path = try std.fs.path.join(std.heap.page_allocator, &.{ recipe_root, relative });
        defer std.heap.page_allocator.free(path);
        try requireStrictRegularFile(io, path);
    }
}

fn validateOfflineInputs(
    io: std.Io,
    workspace: []const u8,
    repro_root: []const u8,
    source_root: []const u8,
    source_closure_root: []const u8,
    recipe_root: []const u8,
    recipe_archive: []const u8,
    depot_tools_root: []const u8,
    approved_receipt: []const u8,
    network_attestation: []const u8,
    build_root: []const u8,
    output: []const u8,
) !void {
    try validateStrictAbsolutePath(repro_root);
    if (strictPathsOverlap(workspace, repro_root)) return error.ControllerPathOverlapsRepository;
    inline for (.{ source_root, source_closure_root, recipe_root, depot_tools_root }) |path| {
        try validateStrictInputPath(path);
        try requireStrictOutside(path, workspace, repro_root);
    }
    inline for (.{ recipe_archive, approved_receipt, network_attestation }) |path| {
        try validateStrictInputPath(path);
        try requireStrictOutside(path, workspace, repro_root);
    }
    try validateStrictAbsolutePath(build_root);
    try validateStrictAbsolutePath(output);
    if (!strictPathWithin(repro_root, build_root) or !strictPathWithin(build_root, output)) {
        return error.ControllerPathNotContained;
    }
    const prepared_source = try std.fs.path.join(std.heap.page_allocator, &.{ repro_root, "source" });
    defer std.heap.page_allocator.free(prepared_source);
    if (strictPathsOverlap(prepared_source, build_root) or
        strictPathsOverlap(prepared_source, output))
    {
        return error.ControllerInputsOverlap;
    }
    try requireStrictDirectory(io, repro_root);
    try requireStrictEmptyDirectory(io, repro_root);
    try requireStrictDirectory(io, source_root);
    try requireStrictDirectory(io, source_closure_root);
    const closure_pdfium = try strictPdfiumSourcePath(std.heap.page_allocator, source_closure_root);
    defer std.heap.page_allocator.free(closure_pdfium);
    try requireStrictDirectory(io, closure_pdfium);
    try requireStrictDirectory(io, recipe_root);
    try requireStrictDirectory(io, depot_tools_root);
    try requireStrictRegularFile(io, recipe_archive);
    try requireStrictRegularFile(io, approved_receipt);
    try requireStrictRegularFile(io, network_attestation);
    try requireStrictAbsent(io, build_root);
    try requireStrictAbsent(io, output);
    if (strictPathsOverlap(source_root, source_closure_root) or
        strictPathsOverlap(source_root, recipe_root) or strictPathsOverlap(source_root, depot_tools_root) or
        strictPathsOverlap(source_closure_root, recipe_root) or
        strictPathsOverlap(source_closure_root, depot_tools_root) or
        strictPathsOverlap(recipe_root, depot_tools_root)) return error.ControllerInputsOverlap;
    inline for (.{ recipe_archive, approved_receipt, network_attestation }) |file| {
        inline for (.{ source_root, source_closure_root, recipe_root, depot_tools_root }) |root| {
            if (strictPathsOverlap(file, root)) return error.ControllerInputsOverlap;
        }
    }
    try validateRecipeInputs(io, recipe_root);
}

fn updateIdentityPair(
    hasher: *std.crypto.hash.sha2.Sha256,
    key: []const u8,
    value: []const u8,
) void {
    hasher.update(key);
    hasher.update("=");
    hasher.update(value);
    hasher.update("\n");
}

fn updateIdentityNumber(
    hasher: *std.crypto.hash.sha2.Sha256,
    key: []const u8,
    value: u64,
) void {
    var buffer: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch unreachable;
    updateIdentityPair(hasher, key, text);
}

fn strictBuildIdentityDigest(
    approved: StrictApprovedReceipt,
    source_tree_sha256: []const u8,
    patched_source_tree_sha256: []const u8,
    patched_source_files: u64,
    patched_source_bytes: u64,
    source_closure_sha256: []const u8,
    recipe_tree_sha256: []const u8,
    depot_tools_tree_sha1: []const u8,
    output_sha256: []const u8,
    output_size_bytes: u64,
) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    updateIdentityPair(&hasher, "schema", "texflow-pdfium-build-identity-v1");
    updateIdentityPair(&hasher, "target", approved.target);
    updateIdentityPair(&hasher, "pdfium_commit", approved.pdfium_commit);
    updateIdentityPair(&hasher, "pdfium_tree_sha256", source_tree_sha256);
    updateIdentityPair(&hasher, "patched_pdfium_tree_sha256", patched_source_tree_sha256);
    updateIdentityNumber(&hasher, "patched_pdfium_files", patched_source_files);
    updateIdentityNumber(&hasher, "patched_pdfium_bytes", patched_source_bytes);
    updateIdentityPair(&hasher, "source_closure_sha256", source_closure_sha256);
    updateIdentityNumber(&hasher, "source_closure_files", approved.source_closure_files);
    updateIdentityNumber(&hasher, "source_closure_bytes", approved.source_closure_bytes);
    updateIdentityPair(&hasher, "recipe_commit", approved.recipe_commit);
    updateIdentityPair(&hasher, "recipe_archive_sha256", approved.recipe_archive_sha256);
    updateIdentityPair(&hasher, "recipe_tree_sha256", recipe_tree_sha256);
    updateIdentityPair(&hasher, "depot_tools_commit", approved.depot_tools_commit);
    updateIdentityPair(&hasher, "depot_tools_tree_sha1", depot_tools_tree_sha1);
    for (approved.gn_args) |arg| updateIdentityPair(&hasher, "gn_arg", arg);
    updateIdentityPair(&hasher, "runner_image_sha256", approved.toolchain.runner_image_sha256);
    updateIdentityPair(&hasher, "visual_studio_sha256", approved.toolchain.visual_studio_sha256);
    updateIdentityPair(&hasher, "windows_sdk_version", approved.toolchain.windows_sdk_version);
    updateIdentityPair(&hasher, "windows_sdk_sha256", approved.toolchain.windows_sdk_sha256);
    updateIdentityPair(&hasher, "toolchain_closure_sha256", approved.toolchain.toolchain_closure_sha256);
    updateIdentityPair(&hasher, "git_sha256", approved.toolchain.git_sha256);
    updateIdentityPair(&hasher, "gn_sha256", approved.toolchain.gn_sha256);
    updateIdentityPair(&hasher, "ninja_sha256", approved.toolchain.ninja_sha256);
    updateIdentityPair(&hasher, "compiler_sha256", approved.toolchain.compiler_sha256);
    updateIdentityPair(&hasher, "linker_sha256", approved.toolchain.linker_sha256);
    updateIdentityPair(&hasher, "python_sha256", approved.toolchain.python_sha256);
    updateIdentityPair(&hasher, "resource_compiler_sha256", approved.toolchain.resource_compiler_sha256);
    updateIdentityPair(&hasher, "output_sha256", output_sha256);
    updateIdentityNumber(&hasher, "output_size_bytes", output_size_bytes);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn validateStrictGnArgs(bytes: []const u8) !void {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    for (strict_required_gn_args) |expected| {
        const line = lines.next() orelse return error.UnexpectedGnArg;
        if (!std.mem.eql(u8, std.mem.trim(u8, line, " \t\r"), expected)) {
            return error.UnexpectedGnArg;
        }
    }
    const trailing = lines.next() orelse return error.UnexpectedGnArg;
    if (trailing.len != 0 or lines.next() != null) return error.UnexpectedGnArg;
}

fn strictGnArgsBytes(allocator: std.mem.Allocator) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    for (strict_required_gn_args) |arg| {
        try bytes.appendSlice(allocator, arg);
        try bytes.append(allocator, '\n');
    }
    return bytes.toOwnedSlice(allocator);
}

fn inspectStrictPe(bytes: []const u8) !StrictPeEvidence {
    if (bytes.len < 64 or !std.mem.eql(u8, bytes[0..2], "MZ")) return error.OutputIsNotPe;
    const pe_offset = @as(usize, std.mem.readInt(u32, bytes[0x3c..][0..4], .little));
    const header = std.math.add(usize, pe_offset, 24) catch return error.OutputIsNotPe;
    if (header > bytes.len or !std.mem.eql(u8, bytes[pe_offset..][0..4], "PE\x00\x00")) {
        return error.OutputIsNotPe;
    }
    const machine = std.mem.readInt(u16, bytes[pe_offset + 4 ..][0..2], .little);
    if (machine != 0x8664) return error.OutputIsNotX64Pe;
    return .{ .machine = machine, .is_64 = true };
}

fn validateOutputPathName(path: []const u8) !void {
    var lower_name_buffer: [512]u8 = undefined;
    const name = std.fs.path.basename(path);
    if (name.len > lower_name_buffer.len) return error.UnsafeControllerPath;
    const lower_name = std.ascii.lowerString(&lower_name_buffer, name);
    if (std.mem.indexOf(u8, lower_name, "fixture") != null or
        std.mem.indexOf(u8, lower_name, "sentinel") != null)
    {
        return error.SentinelOutputRejected;
    }
}

fn validateActualOutput(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    approved: StrictApprovedReceipt,
) !struct { summary: StrictFileSummary, pe: StrictPeEvidence } {
    try validateOutputPathName(path);
    const summary = try hashStrictFile(io, path, maximum_controller_input_bytes);
    if (summary.bytes != approved.output_size_bytes or
        !strictDigestMatches(summary.digest, approved.output_sha256) or
        strictDigestMatches(summary.digest, locked_reference_dll_sha256))
    {
        return error.OutputIdentityMismatch;
    }
    const bytes = try readStrictFileAlloc(allocator, io, path, maximum_controller_input_bytes);
    defer allocator.free(bytes);
    const pe = try inspectStrictPe(bytes);
    return .{ .summary = summary, .pe = pe };
}

fn writeStrictFile(io: std.Io, path: []const u8, bytes: []const u8) !void {
    const parent_path = std.fs.path.dirname(path) orelse return error.UnsafeControllerPath;
    var parent = try openStrictDirectoryNoFollow(io, parent_path, false);
    defer parent.close(io);
    const name = std.fs.path.basename(path);
    if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) {
        return error.UnsafeControllerPath;
    }
    var file = try parent.createFile(io, name, .{
        .read = true,
        .truncate = false,
        .exclusive = true,
        .resolve_beneath = true,
    });
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
    try file.sync(io);
}

fn writeStrictJson(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    value: anytype,
) !void {
    const bytes = try std.json.Stringify.valueAlloc(allocator, value, .{});
    defer allocator.free(bytes);
    try writeStrictFile(io, path, bytes);
}

fn validateStrictRetentionEvidence(retention: StrictRetentionEvidence) !void {
    if (std.mem.eql(u8, retention.status, "pending-upload")) {
        if (retention.artifact_name.len != 0 or retention.artifact_id.len != 0 or
            retention.artifact_digest.len != 0 or retention.artifact_url.len != 0 or
            retention.retention_days != 0 or retention.receipt_sha256.len != 0 or
            retention.created_at.len != 0 or retention.expires_at.len != 0)
        {
            return error.InvalidControllerReceipt;
        }
        return;
    }
    if (!std.mem.eql(u8, retention.status, "verified") or
        retention.artifact_name.len == 0 or retention.artifact_id.len == 0 or
        retention.artifact_digest.len == 0 or retention.artifact_url.len == 0 or
        retention.retention_days < 7 or retention.retention_days > 90)
    {
        return error.InvalidControllerReceipt;
    }
    try validateArtifactName(retention.artifact_name);
    try validateArtifactId(retention.artifact_id);
    try validateArtifactDigest(retention.artifact_digest);
    try validateArtifactUrl(retention.artifact_url);
    try validateLowerHex(retention.receipt_sha256, 64);
    _ = try parseStrictTimestamp(retention.created_at);
    _ = try parseStrictTimestamp(retention.expires_at);
}

fn validateStrictControllerReceipt(receipt: StrictControllerReceipt) !void {
    if (receipt.schema_version != strict_receipt_schema_version or
        !std.mem.eql(u8, receipt.receipt_kind, strict_receipt_kind) or
        (std.mem.eql(u8, receipt.status, "verified") == false and
            std.mem.eql(u8, receipt.status, "unverified") == false) or
        (std.mem.eql(u8, receipt.run_identity_status, "verified") == false and
            std.mem.eql(u8, receipt.run_identity_status, "unverified") == false))
    {
        return error.InvalidControllerReceipt;
    }
    try validateStrictText(receipt.reason);
    try validateStrictText(receipt.scope);
    if (std.mem.eql(u8, receipt.run_identity_status, "verified")) {
        try validateHostedRunIdentity(receipt.run_identity);
    }
    if (std.mem.eql(u8, receipt.status, "verified")) {
        if (!std.mem.eql(u8, receipt.run_identity_status, "verified") or
            !std.mem.eql(u8, receipt.network.mode, "detached-nic") or
            receipt.network.route_count != 0 or receipt.network.default_route_present or
            receipt.network.negative_fetch_bytes != 0 or
            !std.mem.eql(u8, receipt.network.proxy, "unset") or
            !std.mem.eql(u8, receipt.network.process_policy, "zig-owned") or
            !std.mem.eql(u8, receipt.inputs.status, "verified") or
            !std.mem.eql(u8, receipt.build.status, "verified") or
            !std.mem.eql(u8, receipt.output.status, "verified") or
            !receipt.output.actual_output or !receipt.output.pe_is_64 or
            !receipt.output.reference_digest_rejected)
        {
            return error.InvalidControllerReceipt;
        }
        try validateLowerHex(receipt.output.sha256, 64);
        try validateLowerHex(receipt.build.build_identity_sha256, 64);
    }
    if (!std.mem.eql(u8, receipt.retention.status, "pending-upload") and
        !std.mem.eql(u8, receipt.retention.status, "verified"))
    {
        return error.InvalidControllerReceipt;
    }
    try validateStrictRetentionEvidence(receipt.retention);
}

fn runRemoteProof(
    allocator: std.mem.Allocator,
    io: std.Io,
    init: std.process.Init,
    args: []const []const u8,
) !void {
    const allowed = [_][]const u8{ "--output", "--scope" };
    const output = try strictOption(args, "--output", &allowed);
    const scope = try strictOption(args, "--scope", &allowed);
    if (!std.mem.eql(u8, scope, "standard") and !std.mem.eql(u8, scope, "pdfium")) {
        return error.InvalidArguments;
    }
    try validateStrictInputPath(output);
    const workspace = try strictRequiredEnv(init.environ_map, "GITHUB_WORKSPACE");
    try validateStrictInputPath(workspace);
    try requireStrictOutside(output, workspace, null);

    const identity = try collectHostedRunIdentity(allocator, io, init.environ_map);
    defer identity.deinit(allocator);
    if (std.mem.eql(u8, scope, "standard") and
        !std.mem.eql(u8, identity.runner_environment, "github-hosted")) return error.NotHostedRunner;
    var receipt = emptyControllerReceipt(
        if (std.mem.eql(u8, scope, "standard"))
            "UNVERIFIED-PDFIUM-INDEPENDENT-RECONSTRUCTION"
        else
            "UNVERIFIED-PDFIUM-QUALIFIED-RUNNER",
        scope,
    );
    receipt.run_identity_status = "verified";
    receipt.run_identity = identity;
    receipt.output.status = "not-run";
    receipt.inputs.status = "not-run";
    receipt.build.status = "not-run";
    if (std.mem.eql(u8, scope, "pdfium") and strictEnvIsTrue(init.environ_map, "TEXFLOW_PDFIUM_QUALIFIED_RUNNER")) {
        receipt.reason = "UNVERIFIED-PDFIUM-RECONSTRUCTION-NOT-INVOKED";
    }
    try writeStrictJson(allocator, io, output, receipt);
    std.debug.print(
        "pdfium-reproduce status=unverified scope={s} run_id={s} run_attempt={s} reason={s}\n",
        .{ scope, identity.run_id, identity.run_attempt, receipt.reason },
    );
}

fn collectStrictToolPaths(environment: *const std.process.Environ.Map) !StrictToolPaths {
    const paths = StrictToolPaths{
        .git = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_GIT"),
        .gn = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_GN"),
        .ninja = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_NINJA"),
        .compiler = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_COMPILER"),
        .linker = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_LINKER"),
        .python = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_PYTHON"),
        .resource_compiler = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_RESOURCE_COMPILER"),
    };
    inline for (.{
        paths.git,
        paths.gn,
        paths.ninja,
        paths.compiler,
        paths.linker,
        paths.python,
        paths.resource_compiler,
    }) |path| {
        try validateStrictToolPath(path);
    }
    if (builtin.os.tag == .windows and
        !std.ascii.eqlIgnoreCase(std.fs.path.basename(paths.resource_compiler), "rc.exe"))
    {
        return error.ResourceCompilerPathMismatch;
    }
    return paths;
}

fn verifyStrictToolchain(
    io: std.Io,
    environment: *const std.process.Environ.Map,
    tools: StrictToolPaths,
    approved: StrictApprovedReceipt,
    identity: HostedRunIdentity,
) !void {
    const runner_image = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_RUNNER_IMAGE_SHA256");
    const visual_studio = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_VISUAL_STUDIO_SHA256");
    const sdk_version = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_WINDOWS_SDK_VERSION");
    const sdk = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_WINDOWS_SDK_SHA256");
    const closure = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_TOOLCHAIN_CLOSURE_SHA256");
    inline for (.{ runner_image, visual_studio, sdk, closure }) |digest| try validateLowerHex(digest, 64);
    if (!std.mem.eql(u8, runner_image, approved.toolchain.runner_image_sha256) or
        !std.mem.eql(u8, visual_studio, approved.toolchain.visual_studio_sha256) or
        !std.mem.eql(u8, sdk_version, approved.toolchain.windows_sdk_version) or
        !std.mem.eql(u8, sdk, approved.toolchain.windows_sdk_sha256) or
        !std.mem.eql(u8, closure, approved.toolchain.toolchain_closure_sha256) or
        !std.mem.eql(u8, identity.image_identity_sha256, runner_image))
    {
        return error.ToolchainIdentityMismatch;
    }
    try verifyStrictToolDigest(io, tools.git, approved.toolchain.git_sha256);
    try verifyStrictToolDigest(io, tools.gn, approved.toolchain.gn_sha256);
    try verifyStrictToolDigest(io, tools.ninja, approved.toolchain.ninja_sha256);
    try verifyStrictToolDigest(io, tools.compiler, approved.toolchain.compiler_sha256);
    try verifyStrictToolDigest(io, tools.linker, approved.toolchain.linker_sha256);
    try verifyStrictToolDigest(io, tools.python, approved.toolchain.python_sha256);
    try verifyStrictToolDigest(io, tools.resource_compiler, approved.toolchain.resource_compiler_sha256);
}

fn gitIdentity(
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    git: []const u8,
    repository: []const u8,
) !struct { commit: []u8, tree: []u8 } {
    var git_environment = try makeScrubbedGitEnvironment(allocator, environment);
    defer git_environment.deinit();
    const metadata = try std.fs.path.join(std.heap.page_allocator, &.{ repository, ".git" });
    defer std.heap.page_allocator.free(metadata);
    // A linked worktree's `.git` file can redirect identity resolution to an
    // arbitrary external repository. The strict inputs are independent
    // checkouts, so require an actual non-reparse `.git` directory.
    var metadata_directory = try openStrictDirectoryNoFollow(io, metadata, false);
    metadata_directory.close(io);
    try requireGitClean(allocator, io, &git_environment, git, repository);
    const commit = try runGitValue(allocator, io, &git_environment, git, repository, "HEAD");
    errdefer allocator.free(commit);
    const tree = try runGitValue(allocator, io, &git_environment, git, repository, "HEAD^{tree}");
    return .{ .commit = commit, .tree = tree };
}

fn validateStrictArchiveIdentity(
    io: std.Io,
    archive: []const u8,
) !StrictFileSummary {
    const summary = try hashStrictFile(io, archive, maximum_controller_input_bytes);
    if (summary.bytes != 142719 or !strictDigestMatches(summary.digest, locked_recipe_archive_sha256)) {
        return error.LockedPinMismatch;
    }
    return summary;
}

fn appendMeasuredToolDigest(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    owned: *std.ArrayList([]u8),
) ![]const u8 {
    const summary = try hashStrictFile(io, path, maximum_controller_input_bytes);
    const digest = try strictHexDigestAlloc(allocator, summary.digest);
    errdefer allocator.free(digest);
    try owned.append(allocator, digest);
    return digest;
}

fn appendStrictDigest(
    allocator: std.mem.Allocator,
    digest: [32]u8,
    owned: *std.ArrayList([]u8),
) ![]const u8 {
    const text = try strictHexDigestAlloc(allocator, digest);
    errdefer allocator.free(text);
    try owned.append(allocator, text);
    return text;
}

fn measureStrictToolchain(
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    tools: StrictToolPaths,
    owned: *std.ArrayList([]u8),
) !StrictToolchainExpectation {
    const runner_image = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_RUNNER_IMAGE_SHA256");
    const visual_studio = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_VISUAL_STUDIO_SHA256");
    const sdk_version = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_WINDOWS_SDK_VERSION");
    const sdk = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_WINDOWS_SDK_SHA256");
    const closure = try strictRequiredEnv(environment, "TEXFLOW_PDFIUM_TOOLCHAIN_CLOSURE_SHA256");
    inline for (.{ runner_image, visual_studio, sdk, closure }) |digest| try validateLowerHex(digest, 64);
    if (!std.mem.eql(u8, sdk_version, "10.0.28000.0")) return error.ToolchainIdentityMismatch;

    const git = try appendMeasuredToolDigest(allocator, io, tools.git, owned);
    const gn = try appendMeasuredToolDigest(allocator, io, tools.gn, owned);
    const ninja = try appendMeasuredToolDigest(allocator, io, tools.ninja, owned);
    const compiler = try appendMeasuredToolDigest(allocator, io, tools.compiler, owned);
    const linker = try appendMeasuredToolDigest(allocator, io, tools.linker, owned);
    const python = try appendMeasuredToolDigest(allocator, io, tools.python, owned);
    const resource_compiler = try appendMeasuredToolDigest(allocator, io, tools.resource_compiler, owned);
    return .{
        .runner_image_sha256 = runner_image,
        .visual_studio_sha256 = visual_studio,
        .windows_sdk_version = sdk_version,
        .windows_sdk_sha256 = sdk,
        .toolchain_closure_sha256 = closure,
        .git_sha256 = git,
        .gn_sha256 = gn,
        .ninja_sha256 = ninja,
        .compiler_sha256 = compiler,
        .linker_sha256 = linker,
        .python_sha256 = python,
        .resource_compiler_sha256 = resource_compiler,
    };
}

fn validateResolveInputs(
    io: std.Io,
    workspace: []const u8,
    repro_root: []const u8,
    source_root: []const u8,
    source_closure_root: []const u8,
    recipe_root: []const u8,
    recipe_archive: []const u8,
    depot_tools_root: []const u8,
    candidate: []const u8,
) !void {
    try validateStrictAbsolutePath(repro_root);
    try validateStrictInputPath(candidate);
    if (!strictPathWithin(repro_root, candidate)) return error.ControllerPathNotContained;
    try requireStrictOutside(candidate, workspace, null);
    if (strictPathsOverlap(workspace, repro_root)) return error.ControllerPathOverlapsRepository;
    const prepared_source = try std.fs.path.join(std.heap.page_allocator, &.{ repro_root, "source" });
    defer std.heap.page_allocator.free(prepared_source);
    if (strictPathsOverlap(candidate, prepared_source)) return error.ControllerInputsOverlap;
    try requireStrictDirectory(io, repro_root);
    try requireStrictEmptyDirectory(io, repro_root);
    inline for (.{ source_root, source_closure_root, recipe_root, depot_tools_root }) |path| {
        try validateStrictInputPath(path);
        try requireStrictOutside(path, workspace, repro_root);
        try requireStrictDirectory(io, path);
    }
    const closure_pdfium = try strictPdfiumSourcePath(std.heap.page_allocator, source_closure_root);
    defer std.heap.page_allocator.free(closure_pdfium);
    try requireStrictDirectory(io, closure_pdfium);
    try validateStrictInputPath(recipe_archive);
    try requireStrictOutside(recipe_archive, workspace, repro_root);
    try requireStrictRegularFile(io, recipe_archive);
    try requireStrictAbsent(io, candidate);
    if (strictPathsOverlap(source_root, source_closure_root) or
        strictPathsOverlap(source_root, recipe_root) or
        strictPathsOverlap(source_root, depot_tools_root) or
        strictPathsOverlap(source_closure_root, recipe_root) or
        strictPathsOverlap(source_closure_root, depot_tools_root) or
        strictPathsOverlap(recipe_root, depot_tools_root) or
        strictPathsOverlap(recipe_archive, source_root) or
        strictPathsOverlap(recipe_archive, source_closure_root) or
        strictPathsOverlap(recipe_archive, recipe_root) or
        strictPathsOverlap(recipe_archive, depot_tools_root))
    {
        return error.ControllerInputsOverlap;
    }
    try validateRecipeInputs(io, recipe_root);
}

fn runResolve(
    allocator: std.mem.Allocator,
    io: std.Io,
    init: std.process.Init,
    args: []const []const u8,
) !void {
    const allowed = [_][]const u8{"--candidate"};
    const candidate = try strictOption(args, "--candidate", &allowed);
    if (builtin.os.tag != .windows) return error.PdfiumTargetRequiresWindows;
    try validateNoProxyEnvironment(init.environ_map);

    const workspace = try strictRequiredEnv(init.environ_map, "GITHUB_WORKSPACE");
    const repro_root = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_REPRO_ROOT");
    const source_root = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_SOURCE_ROOT");
    const source_closure_root = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_SOURCE_CLOSURE_ROOT");
    const recipe_root = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_RECIPE_ROOT");
    const recipe_archive = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_RECIPE_ARCHIVE");
    const depot_tools_root = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_DEPOT_TOOLS_ROOT");
    const tools = try collectStrictToolPaths(init.environ_map);
    try validateStrictInputPath(workspace);
    try validateResolveInputs(
        io,
        workspace,
        repro_root,
        source_root,
        source_closure_root,
        recipe_root,
        recipe_archive,
        depot_tools_root,
        candidate,
    );
    inline for (.{
        tools.git,
        tools.gn,
        tools.ninja,
        tools.compiler,
        tools.linker,
        tools.python,
        tools.resource_compiler,
    }) |path| {
        try requireStrictOutside(path, workspace, repro_root);
        try requireStrictRegularFile(io, path);
    }

    const source_identity = try gitIdentity(allocator, io, init.environ_map, tools.git, source_root);
    defer allocator.free(source_identity.commit);
    defer allocator.free(source_identity.tree);
    if (!std.mem.eql(u8, source_identity.commit, locked_pdfium_commit)) return error.LockedPinMismatch;
    try validateLowerHex(source_identity.tree, 40);

    const source_summary = try hashStrictTree(allocator, io, source_root);
    if (source_summary.files == 0 or source_summary.bytes == 0 or
        !strictDigestMatches(source_summary.digest, locked_pdfium_tree_sha256))
    {
        return error.SourceIdentityMismatch;
    }
    const closure_pdfium = try strictPdfiumSourcePath(allocator, source_closure_root);
    defer allocator.free(closure_pdfium);
    const closure_source_identity = try gitIdentity(allocator, io, init.environ_map, tools.git, closure_pdfium);
    defer allocator.free(closure_source_identity.commit);
    defer allocator.free(closure_source_identity.tree);
    if (!std.mem.eql(u8, closure_source_identity.commit, source_identity.commit) or
        !std.mem.eql(u8, closure_source_identity.tree, source_identity.tree))
    {
        return error.SourceIdentityMismatch;
    }
    const closure_summary = try hashStrictTree(allocator, io, source_closure_root);
    if (closure_summary.files == 0 or closure_summary.bytes == 0) return error.SourceClosureIdentityMismatch;
    var git_environment = try makeScrubbedGitEnvironment(allocator, init.environ_map);
    defer git_environment.deinit();
    const prepared_source = try prepareStrictPdfiumSource(
        allocator,
        io,
        &git_environment,
        tools.git,
        repro_root,
        source_closure_root,
        recipe_root,
        closure_summary,
    );
    defer allocator.free(prepared_source.root_path);
    defer allocator.free(prepared_source.source_path);
    _ = try validateStrictArchiveIdentity(io, recipe_archive);
    const recipe_summary = try hashStrictTree(allocator, io, recipe_root);
    if (recipe_summary.files == 0 or recipe_summary.bytes == 0) return error.RecipeIdentityMismatch;

    const depot_identity = try gitIdentity(allocator, io, init.environ_map, tools.git, depot_tools_root);
    defer allocator.free(depot_identity.commit);
    defer allocator.free(depot_identity.tree);
    if (!std.mem.eql(u8, depot_identity.commit, locked_depot_tools_commit) or
        !std.mem.eql(u8, depot_identity.tree, locked_depot_tools_tree_sha1))
    {
        return error.LockedPinMismatch;
    }

    var owned_digests: std.ArrayList([]u8) = .empty;
    defer {
        for (owned_digests.items) |digest| allocator.free(digest);
        owned_digests.deinit(allocator);
    }
    const source_tree = try appendStrictDigest(allocator, source_summary.digest, &owned_digests);
    const patched_source_tree = try appendStrictDigest(allocator, prepared_source.summary.digest, &owned_digests);
    const closure_tree = try appendStrictDigest(allocator, closure_summary.digest, &owned_digests);
    const recipe_tree = try appendStrictDigest(allocator, recipe_summary.digest, &owned_digests);
    const toolchain = try measureStrictToolchain(allocator, io, init.environ_map, tools, &owned_digests);
    const candidate_receipt = StrictApprovedReceipt{
        .schema_version = 1,
        .receipt_kind = resolve_candidate_receipt_kind,
        .status = "candidate",
        .target = "x86_64-windows-msvc",
        .pdfium_commit = locked_pdfium_commit,
        .pdfium_tree_sha256 = source_tree,
        .patched_pdfium_tree_sha256 = patched_source_tree,
        .patched_pdfium_files = prepared_source.summary.files,
        .patched_pdfium_bytes = prepared_source.summary.bytes,
        .recipe_commit = locked_recipe_commit,
        .recipe_archive_sha256 = locked_recipe_archive_sha256,
        .recipe_tree_sha256 = recipe_tree,
        .depot_tools_commit = locked_depot_tools_commit,
        .depot_tools_tree_sha1 = locked_depot_tools_tree_sha1,
        .source_closure_sha256 = closure_tree,
        .source_closure_files = closure_summary.files,
        .source_closure_bytes = closure_summary.bytes,
        .output_sha256 = "",
        .output_size_bytes = 0,
        .build_identity_sha256 = "",
        .gn_args = &strict_required_gn_args,
        .toolchain = toolchain,
    };
    try validateResolveCandidate(candidate_receipt);
    try writeStrictJson(allocator, io, candidate, candidate_receipt);
    std.debug.print(
        "pdfium-reproduce status=candidate target=x86_64-windows-msvc candidate={s} gn_invoked=false compiler_invoked=false linker_invoked=false\n",
        .{candidate},
    );
}

fn runReproduce(
    allocator: std.mem.Allocator,
    io: std.Io,
    init: std.process.Init,
    args: []const []const u8,
) !void {
    const allowed = [_][]const u8{"--receipt"};
    const receipt_path = try strictOption(args, "--receipt", &allowed);
    try validateStrictInputPath(receipt_path);

    if (builtin.os.tag != .windows) return error.PdfiumTargetRequiresWindows;
    if (!strictEnvIsTrue(init.environ_map, "TEXFLOW_PDFIUM_QUALIFIED_RUNNER")) {
        return error.UnqualifiedPdfiumRunner;
    }
    try validateNoProxyEnvironment(init.environ_map);

    const workspace = try strictRequiredEnv(init.environ_map, "GITHUB_WORKSPACE");
    const repro_root = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_REPRO_ROOT");
    const source_root = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_SOURCE_ROOT");
    const source_closure_root = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_SOURCE_CLOSURE_ROOT");
    const recipe_root = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_RECIPE_ROOT");
    const recipe_archive = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_RECIPE_ARCHIVE");
    const depot_tools_root = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_DEPOT_TOOLS_ROOT");
    const approved_path = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_APPROVED_RECEIPT");
    const network_attestation = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_NETWORK_ATTESTATION");
    const build_root = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_BUILD_ROOT");
    const output_path = try strictRequiredEnv(init.environ_map, "TEXFLOW_PDFIUM_OUTPUT");
    const tools = try collectStrictToolPaths(init.environ_map);
    try validateStrictInputPath(workspace);
    try validateOfflineInputs(
        io,
        workspace,
        repro_root,
        source_root,
        source_closure_root,
        recipe_root,
        recipe_archive,
        depot_tools_root,
        approved_path,
        network_attestation,
        build_root,
        output_path,
    );
    try requireStrictOutside(receipt_path, workspace, repro_root);
    inline for (.{
        tools.git,
        tools.gn,
        tools.ninja,
        tools.compiler,
        tools.linker,
        tools.python,
        tools.resource_compiler,
    }) |path| {
        try requireStrictOutside(path, workspace, repro_root);
    }
    try requireStrictRegularFile(io, tools.git);
    try requireStrictRegularFile(io, tools.gn);
    try requireStrictRegularFile(io, tools.ninja);
    try requireStrictRegularFile(io, tools.compiler);
    try requireStrictRegularFile(io, tools.linker);
    try requireStrictRegularFile(io, tools.python);
    try requireStrictRegularFile(io, tools.resource_compiler);

    const identity = try collectHostedRunIdentity(allocator, io, init.environ_map);
    defer identity.deinit(allocator);
    if (!std.mem.eql(u8, identity.runner_environment, "self-hosted") or
        !std.mem.eql(u8, identity.runner_os, "Windows") or
        !std.mem.eql(u8, identity.runner_arch, "X64"))
    {
        return error.UnqualifiedPdfiumRunner;
    }

    const approved_bytes = try readStrictFileAlloc(allocator, io, approved_path, max_receipt_bytes);
    defer allocator.free(approved_bytes);
    if (!std.mem.eql(u8, approved_bytes, tracked_toolchain_lock)) {
        return error.TrackedToolchainLockMismatch;
    }
    const approved_digest = receiptDigest(approved_bytes);
    const approved_digest_hex = try strictHexDigestAlloc(allocator, approved_digest);
    defer allocator.free(approved_digest_hex);
    var approved_parsed = try std.json.parseFromSlice(StrictApprovedReceipt, allocator, approved_bytes, .{
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
    });
    defer approved_parsed.deinit();
    const approved = approved_parsed.value;
    try validateApprovedReceipt(approved);

    const resources = try probeStrictResources(io, repro_root);
    const network_digest = try validateNetworkAttestation(
        allocator,
        io,
        init.environ_map,
        network_attestation,
        identity,
        repro_root,
        workspace,
    );
    defer allocator.free(network_digest);
    const route = try probeStrictRoutes(allocator, io, init.environ_map, repro_root);
    if (route.route_count != 0 or route.default_route_present) return error.NetworkIsolationUnverified;

    try verifyStrictToolchain(io, init.environ_map, tools, approved, identity);
    const source_identity = try gitIdentity(allocator, io, init.environ_map, tools.git, source_root);
    defer allocator.free(source_identity.commit);
    defer allocator.free(source_identity.tree);
    if (!std.mem.eql(u8, source_identity.commit, locked_pdfium_commit)) return error.LockedPinMismatch;
    try validateLowerHex(source_identity.tree, 40);
    const source_summary = try hashStrictTree(allocator, io, source_root);
    if (source_summary.files != 5400 or source_summary.bytes != 40484895 or
        !strictDigestMatches(source_summary.digest, locked_pdfium_tree_sha256))
    {
        return error.SourceIdentityMismatch;
    }
    const source_tree_hex = try strictHexDigestAlloc(allocator, source_summary.digest);
    defer allocator.free(source_tree_hex);

    const closure_pdfium = try strictPdfiumSourcePath(allocator, source_closure_root);
    defer allocator.free(closure_pdfium);
    const closure_source_identity = try gitIdentity(allocator, io, init.environ_map, tools.git, closure_pdfium);
    defer allocator.free(closure_source_identity.commit);
    defer allocator.free(closure_source_identity.tree);
    if (!std.mem.eql(u8, closure_source_identity.commit, source_identity.commit) or
        !std.mem.eql(u8, closure_source_identity.tree, source_identity.tree))
    {
        return error.SourceIdentityMismatch;
    }
    const closure_summary = try hashStrictTree(allocator, io, source_closure_root);
    const closure_hex = try strictHexDigestAlloc(allocator, closure_summary.digest);
    defer allocator.free(closure_hex);
    if (closure_summary.files != approved.source_closure_files or
        closure_summary.bytes != approved.source_closure_bytes or
        !std.mem.eql(u8, closure_hex, approved.source_closure_sha256))
    {
        return error.SourceClosureIdentityMismatch;
    }

    _ = try validateStrictArchiveIdentity(io, recipe_archive);
    const recipe_tree_summary = try hashStrictTree(allocator, io, recipe_root);
    const recipe_tree_hex = try strictHexDigestAlloc(allocator, recipe_tree_summary.digest);
    defer allocator.free(recipe_tree_hex);
    if (!std.mem.eql(u8, recipe_tree_hex, approved.recipe_tree_sha256)) return error.RecipeIdentityMismatch;

    const depot_identity = try gitIdentity(allocator, io, init.environ_map, tools.git, depot_tools_root);
    defer allocator.free(depot_identity.commit);
    defer allocator.free(depot_identity.tree);
    if (!std.mem.eql(u8, depot_identity.commit, locked_depot_tools_commit) or
        !std.mem.eql(u8, depot_identity.tree, locked_depot_tools_tree_sha1))
    {
        return error.LockedPinMismatch;
    }

    const prepared_source_root_path = try std.fs.path.join(allocator, &.{ repro_root, "source" });
    defer allocator.free(prepared_source_root_path);
    if (strictPathsOverlap(prepared_source_root_path, build_root) or
        strictPathsOverlap(prepared_source_root_path, output_path))
    {
        return error.ControllerInputsOverlap;
    }
    var process_environment = try makeScrubbedBuildEnvironment(
        allocator,
        init.environ_map,
        repro_root,
        depot_tools_root,
        tools,
    );
    defer process_environment.deinit();
    try probeStrictNetworkCanary(allocator, io, &process_environment, tools.git, workspace);
    const prepared_source = try prepareStrictPdfiumSource(
        allocator,
        io,
        &process_environment,
        tools.git,
        repro_root,
        source_closure_root,
        recipe_root,
        closure_summary,
    );
    defer allocator.free(prepared_source.root_path);
    defer allocator.free(prepared_source.source_path);
    if (!std.mem.eql(u8, prepared_source.root_path, prepared_source_root_path)) return error.ControllerPathContainedMismatch;
    const patched_source_tree_hex = try strictHexDigestAlloc(allocator, prepared_source.summary.digest);
    defer allocator.free(patched_source_tree_hex);
    if (prepared_source.summary.files != approved.patched_pdfium_files or
        prepared_source.summary.bytes != approved.patched_pdfium_bytes or
        !std.mem.eql(u8, patched_source_tree_hex, approved.patched_pdfium_tree_sha256))
    {
        return error.PatchedSourceIdentityMismatch;
    }

    var build_directory = try createStrictDirectoryPath(io, repro_root, build_root);
    defer build_directory.close(io);
    if ((try build_directory.stat(io)).kind != .directory) return error.ReproBuildRootNotFresh;
    const args_path = try std.fs.path.join(allocator, &.{ build_root, "args.gn" });
    defer allocator.free(args_path);
    const args_bytes = try strictGnArgsBytes(allocator);
    defer allocator.free(args_bytes);
    try writeStrictFile(io, args_path, args_bytes);

    var gn_argv = [_][]const u8{ tools.gn, "gen", build_root, "--check" };
    const gn_output = try runStrictTool(allocator, io, &process_environment, prepared_source.source_path, &gn_argv);
    defer allocator.free(gn_output);
    const generated_args = try readStrictFileAlloc(allocator, io, args_path, 16 * 1024);
    defer allocator.free(generated_args);
    try validateStrictGnArgs(generated_args);

    var ninja_argv = [_][]const u8{ tools.ninja, "-C", build_root, "pdfium" };
    const ninja_output = try runStrictTool(allocator, io, &process_environment, prepared_source.source_path, &ninja_argv);
    defer allocator.free(ninja_output);

    const actual_output = try validateActualOutput(allocator, io, output_path, approved);
    const output_hex = try strictHexDigestAlloc(allocator, actual_output.summary.digest);
    defer allocator.free(output_hex);
    const identity_digest = strictBuildIdentityDigest(
        approved,
        source_tree_hex,
        patched_source_tree_hex,
        prepared_source.summary.files,
        prepared_source.summary.bytes,
        closure_hex,
        recipe_tree_hex,
        depot_identity.tree,
        output_hex,
        actual_output.summary.bytes,
    );
    const identity_hex = try strictHexDigestAlloc(allocator, identity_digest);
    defer allocator.free(identity_hex);
    if (!std.mem.eql(u8, identity_hex, approved.build_identity_sha256)) {
        return error.RebuildIdentityMismatch;
    }

    var receipt = emptyControllerReceipt(
        "independent-source-reconstruction-and-output-equivalence-verified",
        "pdfium-reconstruction",
    );
    receipt.status = "verified";
    receipt.run_identity_status = "verified";
    receipt.run_identity = identity;
    receipt.network = .{
        .mode = "detached-nic",
        .source = "runner-control-plane-plus-live-route-probe",
        .attestation_sha256 = network_digest,
        .route_count = route.route_count,
        .default_route_present = route.default_route_present,
        .negative_fetch_bytes = 0,
        .proxy = "unset",
        .process_policy = "zig-owned",
    };
    receipt.inputs = .{
        .status = "verified",
        .source_commit = source_identity.commit,
        .source_tree_sha256 = source_tree_hex,
        .source_files = source_summary.files,
        .source_bytes = source_summary.bytes,
        .patched_source_tree_sha256 = patched_source_tree_hex,
        .patched_source_files = prepared_source.summary.files,
        .patched_source_bytes = prepared_source.summary.bytes,
        .source_closure_sha256 = closure_hex,
        .source_closure_files = closure_summary.files,
        .source_closure_bytes = closure_summary.bytes,
        .recipe_commit = locked_recipe_commit,
        .recipe_archive_sha256 = locked_recipe_archive_sha256,
        .recipe_tree_sha256 = recipe_tree_hex,
        .depot_tools_commit = depot_identity.commit,
        .depot_tools_tree_sha1 = depot_identity.tree,
        .approved_receipt_sha256 = approved_digest_hex,
        .free_space_bytes = resources.free_space_bytes,
        .physical_memory_bytes = resources.physical_memory_bytes,
    };
    receipt.build = .{
        .status = "verified",
        .gn_args = approved.gn_args,
        .git_sha256 = approved.toolchain.git_sha256,
        .gn_sha256 = approved.toolchain.gn_sha256,
        .ninja_sha256 = approved.toolchain.ninja_sha256,
        .compiler_sha256 = approved.toolchain.compiler_sha256,
        .linker_sha256 = approved.toolchain.linker_sha256,
        .python_sha256 = approved.toolchain.python_sha256,
        .resource_compiler_sha256 = approved.toolchain.resource_compiler_sha256,
        .build_identity_sha256 = identity_hex,
    };
    receipt.output = .{
        .status = "verified",
        .path_redacted = "<redacted>",
        .size_bytes = actual_output.summary.bytes,
        .sha256 = output_hex,
        .pe_machine = actual_output.pe.machine,
        .pe_is_64 = actual_output.pe.is_64,
        .actual_output = true,
        .reference_digest_rejected = true,
    };
    try writeStrictJson(allocator, io, receipt_path, receipt);
    std.debug.print(
        "pdfium-reproduce status=verified run_id={s} run_attempt={s} output_sha256={s}\n",
        .{ identity.run_id, identity.run_attempt, output_hex },
    );
}

fn validateArtifactName(name: []const u8) !void {
    try validateStrictText(name);
    if (std.mem.indexOfAny(u8, name, "/\\") != null) return error.InvalidArtifactIdentity;
}

fn validateArtifactUrl(url: []const u8) !void {
    try validateStrictText(url);
    if (!std.mem.startsWith(u8, url, "https://github.com/") or
        std.mem.indexOfAny(u8, url, "?#@") != null)
    {
        return error.InvalidArtifactIdentity;
    }
}

fn validateArtifactId(value: []const u8) !void {
    try validateStrictNonzeroDecimal(value);
}

fn validateArtifactDigest(value: []const u8) !void {
    const hex = if (std.mem.startsWith(u8, value, "sha256:")) value["sha256:".len..] else value;
    if (hex.len != 64) {
        return error.InvalidArtifactIdentity;
    }
    try validateLowerHex(hex, 64);
}

fn metadataValue(line: []const u8, key: []const u8) ![]const u8 {
    if (!std.mem.startsWith(u8, line, key) or line.len <= key.len or line[key.len] != '=') {
        return error.InvalidArtifactMetadata;
    }
    const value = line[key.len + 1 ..];
    try validateStrictText(value);
    return value;
}

const minimum_durable_retention_age_seconds: u64 = 24 * 60 * 60;

fn parseStrictTimestamp(value: []const u8) !u64 {
    const timestamp = std.fmt.parseUnsigned(u64, value, 10) catch
        return error.InvalidArtifactMetadata;
    if (timestamp == 0) return error.InvalidArtifactMetadata;
    return timestamp;
}

fn validateArtifactRetentionWindow(
    metadata: StrictArtifactMetadata,
    now: u64,
    minimum_age_seconds: u64,
    retention_days: u16,
) !void {
    const created_at = try parseStrictTimestamp(metadata.created_at);
    const expires_at = try parseStrictTimestamp(metadata.expires_at);
    if (expires_at <= created_at or now < created_at or now >= expires_at) return error.InvalidRetentionPolicy;
    const required_retention = std.math.mul(u64, retention_days, 24 * 60 * 60) catch
        return error.InvalidRetentionPolicy;
    // GitHub calculates `expires_at` from the workflow run start, while `created_at`
    // is stamped when the artifact upload completes mid-job (typically 10-60 seconds later).
    // Allow up to 1 hour of workflow execution jitter while strictly rejecting any day-level shortfall.
    const workflow_jitter_grace_seconds: u64 = 3600;
    if (expires_at - created_at + workflow_jitter_grace_seconds < required_retention) return error.InvalidRetentionPolicy;
    const required_age = std.math.add(u64, created_at, minimum_age_seconds) catch
        return error.InvalidRetentionPolicy;
    if (now < required_age) return error.DurableRetentionNotReady;
}

fn parseArtifactMetadata(bytes: []const u8) !StrictArtifactMetadata {
    const keys = [_][]const u8{
        "schema",
        "id",
        "name",
        "digest",
        "repository",
        "run_id",
        "run_attempt",
        "head_sha",
        "size_bytes",
        "expired",
        "created_at",
        "expires_at",
    };
    var values: [keys.len][]const u8 = undefined;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    for (keys, 0..) |key, index| {
        const line = lines.next() orelse return error.InvalidArtifactMetadata;
        values[index] = try metadataValue(line, key);
    }
    if (lines.next()) |trailing| if (trailing.len != 0) return error.InvalidArtifactMetadata;
    if (!std.mem.eql(u8, values[0], "texflow-github-artifact-v1")) return error.InvalidArtifactMetadata;
    return .{
        .schema = values[0],
        .id = values[1],
        .name = values[2],
        .digest = values[3],
        .repository = values[4],
        .run_id = values[5],
        .run_attempt = values[6],
        .head_sha = values[7],
        .size_bytes = values[8],
        .expired = values[9],
        .created_at = values[10],
        .expires_at = values[11],
    };
}

fn validateArtifactMetadata(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    artifact_prefix: []const u8,
    artifact_name: []const u8,
    artifact_id: []const u8,
    artifact_digest: []const u8,
    artifact_url: []const u8,
    identity: HostedRunIdentity,
) !StrictArtifactMetadata {
    try validateStrictText(artifact_prefix);
    if (std.mem.indexOfAny(u8, artifact_prefix, "/\\") != null) return error.InvalidArtifactIdentity;
    try validateArtifactName(artifact_name);
    try validateArtifactId(artifact_id);
    try validateArtifactDigest(artifact_digest);
    try validateArtifactUrl(artifact_url);
    const metadata = try parseArtifactMetadata(bytes);
    const expected_hex = if (std.mem.startsWith(u8, artifact_digest, "sha256:")) artifact_digest["sha256:".len..] else artifact_digest;
    const actual_hex = if (std.mem.startsWith(u8, metadata.digest, "sha256:")) metadata.digest["sha256:".len..] else metadata.digest;
    if (!std.mem.eql(u8, metadata.id, artifact_id) or
        !std.mem.eql(u8, metadata.name, artifact_name) or
        !std.mem.eql(u8, actual_hex, expected_hex) or
        !std.mem.eql(u8, metadata.repository, identity.repository) or
        !std.mem.eql(u8, metadata.run_id, identity.run_id) or
        !std.mem.eql(u8, metadata.run_attempt, identity.run_attempt) or
        !std.mem.eql(u8, metadata.head_sha, identity.head_sha) or
        !std.mem.eql(u8, metadata.expired, "false"))
    {
        return error.ArtifactMetadataMismatch;
    }
    const expected_name = try std.fmt.allocPrint(
        allocator,
        "{s}-{s}-{s}",
        .{ artifact_prefix, identity.run_id, identity.run_attempt },
    );
    defer allocator.free(expected_name);
    if (!std.mem.eql(u8, artifact_name, expected_name)) return error.ArtifactMetadataMismatch;
    const expected_url = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}/actions/runs/{s}/artifacts/{s}",
        .{ identity.server_url, identity.repository, identity.run_id, artifact_id },
    );
    defer allocator.free(expected_url);
    if (!std.mem.eql(u8, artifact_url, expected_url)) return error.ArtifactMetadataMismatch;
    try validateStrictNonzeroDecimal(metadata.size_bytes);
    _ = try parseStrictTimestamp(metadata.created_at);
    _ = try parseStrictTimestamp(metadata.expires_at);
    return metadata;
}

fn validateVerifiedReconstructionReceipt(
    allocator: std.mem.Allocator,
    receipt: StrictControllerReceipt,
) !void {
    try validateStrictControllerReceipt(receipt);
    if (!std.mem.eql(u8, receipt.status, "verified") or
        !std.mem.eql(u8, receipt.scope, "pdfium-reconstruction") or
        !std.mem.eql(u8, receipt.run_identity_status, "verified") or
        !std.mem.eql(u8, receipt.run_identity.runner_environment, "self-hosted") or
        !std.mem.eql(u8, receipt.run_identity.runner_os, "Windows") or
        !std.mem.eql(u8, receipt.run_identity.runner_arch, "X64") or
        !std.mem.eql(u8, receipt.run_identity.job, "pdfium-reconstruction") or
        receipt.run_identity.image_identity_sha256.len == 0 or
        !std.mem.eql(u8, receipt.network.mode, "detached-nic") or
        !std.mem.eql(u8, receipt.network.process_policy, "zig-owned") or
        !std.mem.eql(u8, receipt.inputs.status, "verified") or
        !std.mem.eql(u8, receipt.build.status, "verified") or
        !std.mem.eql(u8, receipt.output.status, "verified") or
        !std.mem.eql(u8, receipt.retention.status, "pending-upload"))
    {
        return error.VerifiedReconstructionRequired;
    }
    try validateLowerHex(receipt.run_identity.image_identity_sha256, 64);
    try validateLowerHex(receipt.network.attestation_sha256, 64);
    try validateLowerHex(receipt.inputs.source_commit, 40);
    inline for (.{
        receipt.inputs.source_tree_sha256,
        receipt.inputs.patched_source_tree_sha256,
        receipt.inputs.source_closure_sha256,
        receipt.inputs.recipe_archive_sha256,
        receipt.inputs.recipe_tree_sha256,
        receipt.inputs.approved_receipt_sha256,
        receipt.build.git_sha256,
        receipt.build.gn_sha256,
        receipt.build.ninja_sha256,
        receipt.build.compiler_sha256,
        receipt.build.linker_sha256,
        receipt.build.python_sha256,
        receipt.build.resource_compiler_sha256,
        receipt.build.build_identity_sha256,
        receipt.output.sha256,
    }) |digest| try validateLowerHex(digest, 64);
    inline for (.{
        receipt.inputs.recipe_commit,
        receipt.inputs.depot_tools_commit,
        receipt.inputs.depot_tools_tree_sha1,
    }) |commit| {
        try validateLowerHex(commit, 40);
    }
    if (receipt.inputs.source_files == 0 or receipt.inputs.source_bytes == 0 or
        receipt.inputs.patched_source_files == 0 or receipt.inputs.patched_source_bytes == 0 or
        receipt.inputs.source_closure_files == 0 or receipt.inputs.source_closure_bytes == 0 or
        receipt.inputs.free_space_bytes < minimum_repro_disk_bytes or
        receipt.inputs.physical_memory_bytes < minimum_repro_memory_bytes or
        receipt.output.pe_machine != 0x8664 or receipt.output.size_bytes < 1024 * 1024)
    {
        return error.VerifiedReconstructionRequired;
    }
    if (receipt.build.gn_args.len != strict_required_gn_args.len) return error.VerifiedReconstructionRequired;
    for (receipt.build.gn_args, strict_required_gn_args) |actual, expected| {
        if (!std.mem.eql(u8, actual, expected)) return error.VerifiedReconstructionRequired;
    }

    var approved_parsed = std.json.parseFromSlice(StrictApprovedReceipt, allocator, tracked_toolchain_lock, .{
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
    }) catch return error.VerifiedReconstructionRequired;
    defer approved_parsed.deinit();
    const approved = approved_parsed.value;
    validateApprovedReceipt(approved) catch return error.VerifiedReconstructionRequired;
    const approved_digest = receiptDigest(tracked_toolchain_lock);
    const approved_digest_hex = std.fmt.bytesToHex(approved_digest, .lower);
    if (!std.mem.eql(u8, receipt.inputs.approved_receipt_sha256, &approved_digest_hex) or
        !std.mem.eql(u8, receipt.inputs.source_commit, locked_pdfium_commit) or
        !std.mem.eql(u8, receipt.inputs.source_tree_sha256, locked_pdfium_tree_sha256) or
        receipt.inputs.source_files != locked_pdfium_source_files or
        receipt.inputs.source_bytes != locked_pdfium_source_bytes or
        !std.mem.eql(u8, receipt.inputs.patched_source_tree_sha256, approved.patched_pdfium_tree_sha256) or
        receipt.inputs.patched_source_files != approved.patched_pdfium_files or
        receipt.inputs.patched_source_bytes != approved.patched_pdfium_bytes or
        !std.mem.eql(u8, receipt.inputs.source_closure_sha256, approved.source_closure_sha256) or
        receipt.inputs.source_closure_files != approved.source_closure_files or
        receipt.inputs.source_closure_bytes != approved.source_closure_bytes or
        !std.mem.eql(u8, receipt.inputs.recipe_commit, locked_recipe_commit) or
        !std.mem.eql(u8, receipt.inputs.recipe_archive_sha256, locked_recipe_archive_sha256) or
        !std.mem.eql(u8, receipt.inputs.recipe_tree_sha256, approved.recipe_tree_sha256) or
        !std.mem.eql(u8, receipt.inputs.depot_tools_commit, locked_depot_tools_commit) or
        !std.mem.eql(u8, receipt.inputs.depot_tools_tree_sha1, locked_depot_tools_tree_sha1) or
        !std.mem.eql(u8, receipt.build.git_sha256, approved.toolchain.git_sha256) or
        !std.mem.eql(u8, receipt.build.gn_sha256, approved.toolchain.gn_sha256) or
        !std.mem.eql(u8, receipt.build.ninja_sha256, approved.toolchain.ninja_sha256) or
        !std.mem.eql(u8, receipt.build.compiler_sha256, approved.toolchain.compiler_sha256) or
        !std.mem.eql(u8, receipt.build.linker_sha256, approved.toolchain.linker_sha256) or
        !std.mem.eql(u8, receipt.build.python_sha256, approved.toolchain.python_sha256) or
        !std.mem.eql(u8, receipt.build.resource_compiler_sha256, approved.toolchain.resource_compiler_sha256) or
        !std.mem.eql(u8, receipt.build.build_identity_sha256, approved.build_identity_sha256) or
        !std.mem.eql(u8, receipt.output.sha256, approved.output_sha256) or
        receipt.output.size_bytes != approved.output_size_bytes or
        std.mem.eql(u8, receipt.output.sha256, locked_reference_dll_sha256))
    {
        return error.VerifiedReconstructionRequired;
    }
}

fn sameRestoredBytes(
    allocator: std.mem.Allocator,
    io: std.Io,
    expected: []const u8,
    first: []const u8,
    second: []const u8,
) ![]u8 {
    try requireDistinctEvidenceFiles(io, &.{ expected, first, second });
    const expected_bytes = try readStrictFileAlloc(allocator, io, expected, max_receipt_bytes);
    defer allocator.free(expected_bytes);
    const first_bytes = try readStrictFileAlloc(allocator, io, first, max_receipt_bytes);
    defer allocator.free(first_bytes);
    const second_bytes = try readStrictFileAlloc(allocator, io, second, max_receipt_bytes);
    defer allocator.free(second_bytes);
    if (!std.mem.eql(u8, expected_bytes, first_bytes) or
        !std.mem.eql(u8, expected_bytes, second_bytes)) return error.ArtifactRestoreMismatch;
    return allocator.dupe(u8, expected_bytes);
}

fn runVerifyRestored(
    allocator: std.mem.Allocator,
    io: std.Io,
    init: std.process.Init,
    args: []const []const u8,
) !void {
    const allowed = [_][]const u8{
        "--receipt",
        "--output",
        "--restored-receipt",
        "--restored-receipt-2",
        "--artifact-prefix",
        "--artifact-name",
        "--artifact-id",
        "--artifact-digest",
        "--artifact-url",
        "--artifact-metadata",
        "--retention-days",
        "--source-run-id",
        "--source-run-attempt",
        "--source-head-sha",
        "--minimum-age-seconds",
    };
    const receipt_path = try strictOption(args, "--receipt", &allowed);
    const output_path = try strictOption(args, "--output", &allowed);
    const restored_a = try strictOption(args, "--restored-receipt", &allowed);
    const restored_b = try strictOption(args, "--restored-receipt-2", &allowed);
    const artifact_prefix = try strictOption(args, "--artifact-prefix", &allowed);
    const artifact_name = try strictOption(args, "--artifact-name", &allowed);
    const artifact_id = try strictOption(args, "--artifact-id", &allowed);
    const artifact_digest = try strictOption(args, "--artifact-digest", &allowed);
    const artifact_url = try strictOption(args, "--artifact-url", &allowed);
    const metadata_path = try strictOption(args, "--artifact-metadata", &allowed);
    const retention_text = try strictOption(args, "--retention-days", &allowed);
    const source_run_id = try strictOptionalOption(args, "--source-run-id", &allowed);
    const source_run_attempt = try strictOptionalOption(args, "--source-run-attempt", &allowed);
    const source_head_sha = try strictOptionalOption(args, "--source-head-sha", &allowed);
    const minimum_age_text = try strictOptionalOption(args, "--minimum-age-seconds", &allowed);
    const delayed_retention = source_run_id != null or source_run_attempt != null or source_head_sha != null or minimum_age_text != null;
    if (delayed_retention and (source_run_id == null or source_run_attempt == null or source_head_sha == null or minimum_age_text == null)) {
        return error.InvalidArtifactIdentity;
    }
    inline for (.{ receipt_path, output_path, restored_a, restored_b, metadata_path }) |path| {
        try validateStrictInputPath(path);
    }
    const workspace = try strictRequiredEnv(init.environ_map, "GITHUB_WORKSPACE");
    try validateStrictInputPath(workspace);
    inline for (.{ receipt_path, output_path, restored_a, restored_b, metadata_path }) |path| {
        try requireStrictOutside(path, workspace, null);
    }
    const retention_days = std.fmt.parseUnsigned(u16, retention_text, 10) catch
        return error.InvalidArtifactIdentity;
    if (retention_days < 7 or retention_days > 90) return error.InvalidRetentionPolicy;
    const minimum_age_seconds = if (delayed_retention)
        std.fmt.parseUnsigned(u64, minimum_age_text.?, 10) catch return error.InvalidRetentionPolicy
    else
        0;
    if (delayed_retention and minimum_age_seconds < minimum_durable_retention_age_seconds) {
        return error.InvalidRetentionPolicy;
    }

    const receipt_bytes = try readStrictFileAlloc(allocator, io, receipt_path, max_receipt_bytes);
    defer allocator.free(receipt_bytes);
    var parsed = try std.json.parseFromSlice(StrictControllerReceipt, allocator, receipt_bytes, .{
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
    });
    defer parsed.deinit();
    if (std.mem.eql(u8, parsed.value.scope, "pdfium-reconstruction"))
        try validateVerifiedReconstructionReceipt(allocator, parsed.value)
    else
        try validateStrictControllerReceipt(parsed.value);
    if (!std.mem.eql(u8, parsed.value.run_identity_status, "verified") or
        !std.mem.eql(u8, parsed.value.retention.status, "pending-upload"))
    {
        return error.InvalidControllerReceipt;
    }
    if (!std.mem.eql(u8, parsed.value.scope, "standard") and
        !std.mem.eql(u8, parsed.value.scope, "pdfium") and
        !std.mem.eql(u8, parsed.value.scope, "pdfium-reconstruction")) return error.InvalidControllerReceipt;

    const current_identity = try collectHostedRunIdentity(allocator, io, init.environ_map);
    defer current_identity.deinit(allocator);
    if (delayed_retention) {
        try validateDelayedRetentionRunner(current_identity, parsed.value.run_identity);
        try validateStrictNonzeroDecimal(source_run_id.?);
        try validateStrictNonzeroDecimal(source_run_attempt.?);
        try validateLowerHex(source_head_sha.?, 40);
        if (!std.mem.eql(u8, parsed.value.run_identity.run_id, source_run_id.?) or
            !std.mem.eql(u8, parsed.value.run_identity.run_attempt, source_run_attempt.?) or
            !std.mem.eql(u8, parsed.value.run_identity.head_sha, source_head_sha.?) or
            std.mem.eql(u8, current_identity.run_id, source_run_id.?))
        {
            return error.ArtifactRunIdentityMismatch;
        }
    } else if (!sameHostedRunLineage(parsed.value.run_identity, current_identity)) {
        return error.ArtifactRunIdentityMismatch;
    }
    const metadata_bytes = try readStrictFileAlloc(allocator, io, metadata_path, 16 * 1024);
    defer allocator.free(metadata_bytes);
    const metadata = try validateArtifactMetadata(
        allocator,
        metadata_bytes,
        artifact_prefix,
        artifact_name,
        artifact_id,
        artifact_digest,
        artifact_url,
        parsed.value.run_identity,
    );
    const now_timestamp = @divTrunc(std.Io.Clock.real.now(io).nanoseconds, std.time.ns_per_s);
    if (now_timestamp < 0) return error.InvalidRetentionPolicy;
    try validateArtifactRetentionWindow(metadata, @intCast(now_timestamp), minimum_age_seconds, retention_days);
    const restored_bytes = try sameRestoredBytes(allocator, io, receipt_path, restored_a, restored_b);
    defer allocator.free(restored_bytes);
    const receipt_digest = receiptDigest(receipt_bytes);
    const restored_digest = receiptDigest(restored_bytes);
    const receipt_hex = try strictHexDigestAlloc(allocator, receipt_digest);
    defer allocator.free(receipt_hex);
    const restored_hex = try strictHexDigestAlloc(allocator, restored_digest);
    defer allocator.free(restored_hex);
    const artifact = StrictRetentionEvidence{
        .status = "verified",
        .artifact_name = artifact_name,
        .artifact_id = artifact_id,
        .artifact_digest = artifact_digest,
        .artifact_url = artifact_url,
        .retention_days = retention_days,
        .receipt_sha256 = receipt_hex,
        .created_at = metadata.created_at,
        .expires_at = metadata.expires_at,
    };
    const observation = StrictRetentionObservation{
        .schema_version = strict_receipt_schema_version,
        .receipt_kind = "texflow-pdfium-retention-observation-v1",
        .status = if (std.mem.eql(u8, parsed.value.status, "verified")) "observed-verified" else "observed-unverified",
        .source_status = parsed.value.status,
        .scope = parsed.value.scope,
        .run_identity = parsed.value.run_identity,
        .revalidator_identity = current_identity,
        .artifact = artifact,
        .receipt_sha256 = receipt_hex,
        .restored_sha256_a = restored_hex,
        .restored_sha256_b = restored_hex,
        .restore_count = 2,
        .independent_runner = !sameHostedRun(parsed.value.run_identity, current_identity),
        .independent_storage = delayed_retention,
        .durable_status = if (delayed_retention) "VERIFIED-DURABLE-RETENTION" else "UNVERIFIED-DURABLE-RETENTION",
    };
    try writeStrictJson(allocator, io, output_path, observation);
}

fn runBindArtifact(
    allocator: std.mem.Allocator,
    io: std.Io,
    init: std.process.Init,
    args: []const []const u8,
) !void {
    const allowed = [_][]const u8{
        "--receipt",
        "--output",
        "--artifact-name",
        "--artifact-prefix",
        "--artifact-id",
        "--artifact-digest",
        "--artifact-url",
        "--artifact-metadata",
        "--retention-days",
        "--restored-receipt",
    };
    const receipt_path = try strictOption(args, "--receipt", &allowed);
    const output_path = try strictOption(args, "--output", &allowed);
    const artifact_name = try strictOption(args, "--artifact-name", &allowed);
    const artifact_prefix = try strictOption(args, "--artifact-prefix", &allowed);
    const artifact_id = try strictOption(args, "--artifact-id", &allowed);
    const artifact_digest = try strictOption(args, "--artifact-digest", &allowed);
    const artifact_url = try strictOption(args, "--artifact-url", &allowed);
    const metadata_path = try strictOption(args, "--artifact-metadata", &allowed);
    const retention_text = try strictOption(args, "--retention-days", &allowed);
    const restored_receipt = try strictOptionalOption(args, "--restored-receipt", &allowed) orelse
        return error.MissingRestoredReceipt;
    try validateStrictInputPath(receipt_path);
    try validateStrictInputPath(output_path);
    const workspace = try strictRequiredEnv(init.environ_map, "GITHUB_WORKSPACE");
    try validateStrictInputPath(workspace);
    try requireStrictOutside(receipt_path, workspace, null);
    try requireStrictOutside(output_path, workspace, null);
    try validateStrictInputPath(restored_receipt);
    try validateStrictInputPath(metadata_path);
    try requireStrictOutside(restored_receipt, workspace, null);
    try requireStrictOutside(metadata_path, workspace, null);
    if (!strictEnvIsTrue(init.environ_map, "TEXFLOW_PDFIUM_QUALIFIED_RUNNER")) {
        return error.UnqualifiedPdfiumRunner;
    }
    const retention_days = std.fmt.parseUnsigned(u16, retention_text, 10) catch
        return error.InvalidArtifactIdentity;
    if (retention_days < 7 or retention_days > 90) return error.InvalidRetentionPolicy;

    const receipt_bytes = try readStrictFileAlloc(allocator, io, receipt_path, max_receipt_bytes);
    defer allocator.free(receipt_bytes);
    var parsed = try std.json.parseFromSlice(StrictControllerReceipt, allocator, receipt_bytes, .{
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
    });
    defer parsed.deinit();
    try validateVerifiedReconstructionReceipt(allocator, parsed.value);
    const current_identity = try collectHostedRunIdentity(allocator, io, init.environ_map);
    defer current_identity.deinit(allocator);
    if (!std.mem.eql(u8, current_identity.job, "pdfium-retention-revalidation") or
        !std.mem.eql(u8, current_identity.runner_environment, "self-hosted") or
        !std.mem.eql(u8, current_identity.runner_os, "Windows") or
        current_identity.image_identity_sha256.len == 0 or
        !std.mem.eql(u8, current_identity.image_identity_sha256, parsed.value.run_identity.image_identity_sha256) or
        std.mem.eql(u8, parsed.value.run_identity.runner_name_sha256, current_identity.runner_name_sha256))
    {
        return error.IndependentRunnerRequired;
    }
    if (!sameHostedRunLineage(parsed.value.run_identity, current_identity)) return error.ArtifactRunIdentityMismatch;
    if (!std.mem.eql(u8, parsed.value.retention.status, "pending-upload")) {
        return error.InvalidRetentionPolicy;
    }

    const metadata_bytes = try readStrictFileAlloc(allocator, io, metadata_path, 16 * 1024);
    defer allocator.free(metadata_bytes);
    const metadata = try validateArtifactMetadata(
        allocator,
        metadata_bytes,
        artifact_prefix,
        artifact_name,
        artifact_id,
        artifact_digest,
        artifact_url,
        parsed.value.run_identity,
    );

    const receipt_digest = receiptDigest(receipt_bytes);
    const receipt_digest_hex = try strictHexDigestAlloc(allocator, receipt_digest);
    defer allocator.free(receipt_digest_hex);
    try requireDistinctEvidenceFiles(io, &.{ receipt_path, restored_receipt });
    const restored_bytes = try readStrictFileAlloc(allocator, io, restored_receipt, max_receipt_bytes);
    defer allocator.free(restored_bytes);
    if (!std.mem.eql(u8, receipt_bytes, restored_bytes) or
        !strictDigestMatches(receiptDigest(restored_bytes), receipt_digest_hex))
    {
        return error.ArtifactRestoreMismatch;
    }
    const artifact = StrictRetentionEvidence{
        .status = "verified",
        .artifact_name = artifact_name,
        .artifact_id = artifact_id,
        .artifact_digest = artifact_digest,
        .artifact_url = artifact_url,
        .retention_days = retention_days,
        .receipt_sha256 = receipt_digest_hex,
        .created_at = metadata.created_at,
        .expires_at = metadata.expires_at,
    };
    const binding = StrictArtifactBinding{
        .schema_version = strict_receipt_schema_version,
        .receipt_kind = "texflow-pdfium-artifact-binding-v1",
        .status = "verified",
        .receipt_status = parsed.value.status,
        .restore_verified = true,
        .run_identity = parsed.value.run_identity,
        .artifact = artifact,
        .receipt_sha256 = receipt_digest_hex,
    };
    try writeStrictJson(allocator, io, output_path, binding);
    std.debug.print(
        "pdfium-reproduce artifact-binding status=verified restore=verified run_id={s} artifact_id={s} retention_days={d}\n",
        .{ current_identity.run_id, artifact_id, retention_days },
    );
}

fn emitUnverifiedReceipt(
    allocator: std.mem.Allocator,
    io: std.Io,
    init: std.process.Init,
    args: []const []const u8,
    reason: []const u8,
) void {
    const option_name = if (args.len > 1 and std.mem.eql(u8, args[1], "remote-proof"))
        "--output"
    else
        "--receipt";
    const output = strictOptionalOption(args, option_name, &.{ "--receipt", "--output" }) catch null orelse return;
    if (validateStrictInputPath(output)) |_| {} else |_| return;
    const workspace = init.environ_map.get("GITHUB_WORKSPACE") orelse return;
    if (validateStrictInputPath(workspace)) |_| {} else |_| return;
    if (requireStrictOutside(output, workspace, null)) |_| {} else |_| return;
    const identity = collectHostedRunIdentity(init.arena.allocator(), io, init.environ_map) catch emptyHostedRunIdentity();
    var receipt = emptyControllerReceipt(reason, "pdfium-reconstruction");
    receipt.run_identity = identity;
    receipt.run_identity_status = if (identity.run_id.len == 0) "unverified" else "verified";
    writeStrictJson(allocator, io, output, receipt) catch {};
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.InvalidArguments;
    if (std.mem.eql(u8, args[1], "resolve")) {
        try runResolve(init.gpa, init.io, init, args);
        return;
    }
    if (std.mem.eql(u8, args[1], "remote-proof")) {
        runRemoteProof(init.gpa, init.io, init, args) catch |err| {
            emitUnverifiedReceipt(init.gpa, init.io, init, args, @errorName(err));
            std.debug.print("pdfium-reproduce status=unverified reason={s}\n", .{@errorName(err)});
            return err;
        };
        return;
    }
    if (std.mem.eql(u8, args[1], "reproduce")) {
        runReproduce(init.gpa, init.io, init, args) catch |err| {
            emitUnverifiedReceipt(init.gpa, init.io, init, args, @errorName(err));
            std.debug.print("pdfium-reproduce status=unverified reason={s}\n", .{@errorName(err)});
            return err;
        };
        return;
    }
    if (std.mem.eql(u8, args[1], "bind-artifact")) {
        try runBindArtifact(init.gpa, init.io, init, args);
        return;
    }
    if (std.mem.eql(u8, args[1], "verify-restored")) {
        try runVerifyRestored(init.gpa, init.io, init, args);
        return;
    }
    return error.InvalidArguments;
}

test "strict route evidence rejects a formatted default route" {
    try std.testing.expectError(
        error.NetworkIsolationUnverified,
        countStrictRoutes("          0.0.0.0          0.0.0.0      192.0.2.1\n", true),
    );
}

test "strict route evidence rejects non-default Windows routes" {
    try std.testing.expectError(
        error.NetworkIsolationUnverified,
        countStrictRoutes("10.0.0.0 255.0.0.0 10.0.0.1 10.0.0.2\n", true),
    );
    try std.testing.expectError(
        error.NetworkIsolationUnverified,
        countStrictRoutes("1 331 fe80::/64 fe80::1\n", true),
    );
    const loopback = try countStrictRoutes(
        "127.0.0.0 255.0.0.0 On-link 127.0.0.1\n1 331 ::1/128 ::1\n",
        true,
    );
    try std.testing.expectEqual(@as(u64, 0), loopback.route_count);
}

test "network canary accepts only a diagnostic blocked result" {
    try requireStrictNetworkBlock("", "fatal: unable to access 'https://github.com/': Could not resolve host");
    try std.testing.expectError(
        error.NetworkCanaryUnverified,
        requireStrictNetworkBlock("refs/heads/main", "fatal: unable to access"),
    );
    try std.testing.expectError(
        error.NetworkCanaryUnverified,
        requireStrictNetworkBlock("", "fatal: authentication failed"),
    );
}

test "strict relative build path cannot escape or alias its repro root" {
    try std.testing.expectEqualStrings(
        "build/output",
        strictRelativePath("C:/sealed/repro", "C:\\sealed\\repro\\build/output") orelse return error.TestExpectedEqual,
    );
    try std.testing.expect(strictRelativePath("C:/sealed/repro", "C:/sealed/repro") == null);
    try std.testing.expect(strictRelativePath("C:/sealed/repro", "C:/sealed/repro-sibling/build") == null);
    try std.testing.expect(strictRelativePath("C:/sealed/repro", "C:/sealed/other/build") == null);
}

test "strict tree paths reject Windows hazards and Unicode aliases" {
    var keys = std.StringHashMap(void).init(std.testing.allocator);
    defer {
        var iterator = keys.keyIterator();
        while (iterator.next()) |key| std.testing.allocator.free(key.*);
        keys.deinit();
    }
    try registerStrictTreePath(std.testing.allocator, &keys, "src/caf\u{e9}.cc");
    try std.testing.expectError(
        error.ControllerTreePathCollision,
        registerStrictTreePath(std.testing.allocator, &keys, "SRC/CAFE\u{301}.CC"),
    );
    try std.testing.expectError(error.UnsafeTreePath, validateStrictTreePath("src/CON.txt"));
    try std.testing.expectError(error.UnsafeTreePath, validateStrictTreePath("src/../secret"));
    try std.testing.expectError(error.UnsafeTreePath, validateStrictTreePath("src/name "));
}

test "strict controller paths reject ADS, device, and trailing-space aliases" {
    try std.testing.expectError(error.UnsafeControllerPath, validateStrictInputPath("C:/sealed/file:stream"));
    try std.testing.expectError(error.UnsafeControllerPath, validateStrictInputPath("C:/sealed/CON/output"));
    try std.testing.expectError(error.UnsafeControllerPath, validateStrictInputPath("C:/sealed/name "));
}

test "strict tree rehash reads only opened regular files" {
    var temporary = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "src", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "src/file.cc", .data = "fixture" });
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const absolute = path_buffer[0..try temporary.dir.realPath(std.testing.io, &path_buffer)];
    const summary = try hashStrictTree(std.testing.allocator, std.testing.io, absolute);
    try std.testing.expectEqual(@as(u64, 1), summary.files);
    try std.testing.expectEqual(@as(u64, 7), summary.bytes);
}

test "strict closure copy is atomic and preserves the measured tree" {
    var temporary = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "source", .default_dir);
    try temporary.dir.createDir(std.testing.io, "destination", .default_dir);
    try temporary.dir.createDir(std.testing.io, "source/build", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "source/BUILD.gn", .data = "group(\"pdfium\") {}\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "source/build/toolchain.gni", .data = "toolchain = true\n" });

    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try temporary.dir.realPath(std.testing.io, &root_buffer)];
    const source = try std.fs.path.join(std.testing.allocator, &.{ root, "source" });
    defer std.testing.allocator.free(source);
    const destination = try std.fs.path.join(std.testing.allocator, &.{ root, "destination" });
    defer std.testing.allocator.free(destination);
    const expected = try hashStrictTree(std.testing.allocator, std.testing.io, source);
    try copyStrictTree(std.testing.allocator, std.testing.io, source, destination, expected);
    const actual = try hashStrictTree(std.testing.allocator, std.testing.io, destination);
    try std.testing.expect(strictTreeSummaryEqual(expected, actual));
}

test "strict GN evidence requires both V8 and XFA disabled" {
    const valid = try strictGnArgsBytes(std.testing.allocator);
    defer std.testing.allocator.free(valid);
    try validateStrictGnArgs(valid);
    try std.testing.expectError(
        error.UnexpectedGnArg,
        validateStrictGnArgs(
            "is_component_build=false\n" ++
                "is_debug=false\n" ++
                "pdf_enable_v8=true\n" ++
                "pdf_enable_xfa=false\n" ++
                "pdf_is_standalone=true\n" ++
                "pdf_use_partition_alloc=false\n" ++
                "target_cpu=\"x64\"\n" ++
                "target_os=\"win\"\n" ++
                "treat_warnings_as_errors=false\n",
        ),
    );
}

test "strict artifact identity rejects sentinel names and malformed digests" {
    try std.testing.expectError(error.SentinelOutputRejected, validateOutputPathName("C:/repro/sentinel.dll"));
    try std.testing.expectError(
        error.InvalidArtifactIdentity,
        validateArtifactDigest("sha256:00000000000000000000000000000000000000000000000000000000000000"),
    );
}

test "hosted run identity rejects zero or forged run URLs" {
    var identity = HostedRunIdentity{
        .server_url = "https://github.com",
        .repository = "ndak79/Oleafly",
        .workflow = "TExFlow native checks",
        .workflow_ref = "ndak79/Oleafly/.github/workflows/zig.yml@refs/heads/main",
        .job = "zig-windows",
        .run_id = "123",
        .run_attempt = "1",
        .head_sha = "0123456789012345678901234567890123456789",
        .ref = "refs/heads/main",
        .run_url = "https://github.com/ndak79/Oleafly/actions/runs/123",
        .runner_environment = "github-hosted",
        .runner_os = "Windows",
        .runner_arch = "X64",
        .image_os = "win22",
        .image_version = "20260901.1",
        .runner_name_sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        .image_identity_sha256 = "",
    };
    try validateHostedRunIdentity(identity);
    identity.run_id = "0";
    try std.testing.expectError(error.InvalidRunIdentity, validateHostedRunIdentity(identity));
    identity.run_id = "123";
    identity.run_url = "https://github.com/ndak79/Oleafly/actions/runs/999";
    try std.testing.expectError(error.InvalidHostedRunIdentity, validateHostedRunIdentity(identity));
}

test "delayed retention requires a distinct qualified runner" {
    const source = HostedRunIdentity{
        .server_url = "https://github.com",
        .repository = "ndak79/Oleafly",
        .workflow = "TExFlow native checks",
        .workflow_ref = "ndak79/Oleafly/.github/workflows/zig.yml@refs/heads/main",
        .job = "pdfium-reconstruction",
        .run_id = "123",
        .run_attempt = "1",
        .head_sha = "0123456789012345678901234567890123456789",
        .ref = "refs/heads/main",
        .run_url = "https://github.com/ndak79/Oleafly/actions/runs/123",
        .runner_environment = "self-hosted",
        .runner_os = "Windows",
        .runner_arch = "X64",
        .image_os = "win22",
        .image_version = "qualified-1",
        .runner_name_sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        .image_identity_sha256 = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
    };
    var current = source;
    current.job = "pdfium-retention-delayed";
    current.run_id = "456";
    current.run_url = "https://github.com/ndak79/Oleafly/actions/runs/456";
    current.runner_name_sha256 = "1111111111111111111111111111111111111111111111111111111111111111";
    try validateDelayedRetentionRunner(current, source);
    current.runner_name_sha256 = source.runner_name_sha256;
    try std.testing.expectError(error.IndependentRunnerRequired, validateDelayedRetentionRunner(current, source));
    current.runner_name_sha256 = "1111111111111111111111111111111111111111111111111111111111111111";
    current.image_identity_sha256 = "";
    try std.testing.expectError(error.IndependentRunnerRequired, validateDelayedRetentionRunner(current, source));
}

test "strict retention evidence requires a bounded artifact and receipt digest" {
    var pending = emptyRetentionEvidence();
    pending.artifact_name = "unexpected";
    try std.testing.expectError(error.InvalidControllerReceipt, validateStrictRetentionEvidence(pending));

    const verified = StrictRetentionEvidence{
        .status = "verified",
        .artifact_name = "proof-123-1",
        .artifact_id = "456",
        .artifact_digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        .artifact_url = "https://github.com/ndak79/Oleafly/actions/runs/123/artifacts/456",
        .retention_days = 90,
        .receipt_sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        .created_at = "1700000000",
        .expires_at = "1707776000",
    };
    try validateStrictRetentionEvidence(verified);
}

test "durable retention requires a real age window" {
    const metadata = StrictArtifactMetadata{
        .schema = "texflow-github-artifact-v1",
        .id = "456",
        .name = "proof-123-1",
        .digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        .repository = "ndak79/Oleafly",
        .run_id = "123",
        .run_attempt = "1",
        .head_sha = "0123456789012345678901234567890123456789",
        .size_bytes = "1",
        .expired = "false",
        .created_at = "1700000000",
        .expires_at = "1707776000",
    };
    try validateArtifactRetentionWindow(metadata, 1700000000 + minimum_durable_retention_age_seconds, minimum_durable_retention_age_seconds, 90);
    try std.testing.expectError(
        error.DurableRetentionNotReady,
        validateArtifactRetentionWindow(metadata, 1700000000 + minimum_durable_retention_age_seconds - 1, minimum_durable_retention_age_seconds, 90),
    );
    try std.testing.expectError(
        error.InvalidRetentionPolicy,
        validateArtifactRetentionWindow(metadata, 1707776000, 0, 90),
    );
    var short_window = metadata;
    short_window.expires_at = "1701000000";
    try std.testing.expectError(
        error.InvalidRetentionPolicy,
        validateArtifactRetentionWindow(short_window, 1700000000 + minimum_durable_retention_age_seconds, minimum_durable_retention_age_seconds, 90),
    );
}

test "retention verification rejects aliased evidence files" {
    var temporary = std.testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "receipt.json", .data = "{}" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "restore-a.json", .data = "{}" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "restore-b.json", .data = "{}" });
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buffer[0..try temporary.dir.realPath(std.testing.io, &root_buffer)];
    const receipt = try std.fs.path.join(std.testing.allocator, &.{ root, "receipt.json" });
    defer std.testing.allocator.free(receipt);
    const restore_a = try std.fs.path.join(std.testing.allocator, &.{ root, "restore-a.json" });
    defer std.testing.allocator.free(restore_a);
    const restore_b = try std.fs.path.join(std.testing.allocator, &.{ root, "restore-b.json" });
    defer std.testing.allocator.free(restore_b);
    try requireDistinctEvidenceFiles(std.testing.io, &.{ receipt, restore_a, restore_b });
    try std.testing.expectError(
        error.ArtifactRestoreAlias,
        requireDistinctEvidenceFiles(std.testing.io, &.{ receipt, receipt, restore_b }),
    );
}

test "unverified PDFium receipts cannot be bound as verified" {
    try std.testing.expectError(
        error.VerifiedReconstructionRequired,
        validateVerifiedReconstructionReceipt(std.testing.allocator, emptyControllerReceipt(
            "UNVERIFIED-PDFIUM-INDEPENDENT-RECONSTRUCTION",
            "pdfium-reconstruction",
        )),
    );
}

test "resolve candidate is measured input only and never an approval" {
    const digest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const candidate = StrictApprovedReceipt{
        .schema_version = 1,
        .receipt_kind = resolve_candidate_receipt_kind,
        .status = "candidate",
        .target = "x86_64-windows-msvc",
        .pdfium_commit = locked_pdfium_commit,
        .pdfium_tree_sha256 = locked_pdfium_tree_sha256,
        .patched_pdfium_tree_sha256 = digest,
        .patched_pdfium_files = 2,
        .patched_pdfium_bytes = 2,
        .recipe_commit = locked_recipe_commit,
        .recipe_archive_sha256 = locked_recipe_archive_sha256,
        .recipe_tree_sha256 = digest,
        .depot_tools_commit = locked_depot_tools_commit,
        .depot_tools_tree_sha1 = locked_depot_tools_tree_sha1,
        .source_closure_sha256 = digest,
        .source_closure_files = 1,
        .source_closure_bytes = 1,
        .output_sha256 = "",
        .output_size_bytes = 0,
        .build_identity_sha256 = "",
        .gn_args = &strict_required_gn_args,
        .toolchain = .{
            .runner_image_sha256 = digest,
            .visual_studio_sha256 = digest,
            .windows_sdk_version = "10.0.28000.0",
            .windows_sdk_sha256 = digest,
            .toolchain_closure_sha256 = digest,
            .git_sha256 = digest,
            .gn_sha256 = digest,
            .ninja_sha256 = digest,
            .compiler_sha256 = digest,
            .linker_sha256 = digest,
            .python_sha256 = digest,
            .resource_compiler_sha256 = digest,
        },
    };
    try validateResolveCandidate(candidate);
    var promoted = candidate;
    promoted.status = "approved";
    try std.testing.expectError(error.InvalidResolveCandidate, validateResolveCandidate(promoted));
}

test "tracked PDFium lock is explicit and unverified until promotion" {
    try validateTrackedToolchainLock(std.testing.allocator, tracked_toolchain_lock);
    const promoted = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        tracked_toolchain_lock,
        "\"status\": \"unverified\"",
        "\"status\": \"approved\"",
    );
    defer std.testing.allocator.free(promoted);
    try std.testing.expectError(
        error.InvalidDigest,
        validateTrackedToolchainLock(std.testing.allocator, promoted),
    );
}

test "artifact metadata is tied to the producing run and exact artifact" {
    const identity = HostedRunIdentity{
        .server_url = "https://github.com",
        .repository = "ndak79/Oleafly",
        .workflow = "TExFlow native checks",
        .workflow_ref = "ndak79/Oleafly/.github/workflows/zig.yml@refs/heads/main",
        .job = "zig-windows",
        .run_id = "123",
        .run_attempt = "1",
        .head_sha = "0123456789012345678901234567890123456789",
        .ref = "refs/heads/main",
        .run_url = "https://github.com/ndak79/Oleafly/actions/runs/123",
        .runner_environment = "github-hosted",
        .runner_os = "Windows",
        .runner_arch = "X64",
        .image_os = "win22",
        .image_version = "20260901.1",
        .runner_name_sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        .image_identity_sha256 = "",
    };
    const metadata =
        "schema=texflow-github-artifact-v1\n" ++
        "id=456\n" ++
        "name=texflow-remote-proof-windows-123-1\n" ++
        "digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n" ++
        "repository=ndak79/Oleafly\n" ++
        "run_id=123\n" ++
        "run_attempt=1\n" ++
        "head_sha=0123456789012345678901234567890123456789\n" ++
        "size_bytes=1\n" ++
        "expired=false\n" ++
        "created_at=1700000000\n" ++
        "expires_at=1707776000\n";
    _ = try validateArtifactMetadata(
        std.testing.allocator,
        metadata,
        "texflow-remote-proof-windows",
        "texflow-remote-proof-windows-123-1",
        "456",
        "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        "https://github.com/ndak79/Oleafly/actions/runs/123/artifacts/456",
        identity,
    );
    try std.testing.expectError(
        error.ArtifactMetadataMismatch,
        validateArtifactMetadata(
            std.testing.allocator,
            metadata,
            "texflow-remote-proof-windows",
            "texflow-remote-proof-windows-123-1",
            "457",
            "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            "https://github.com/ndak79/Oleafly/actions/runs/123/artifacts/457",
            identity,
        ),
    );
}
