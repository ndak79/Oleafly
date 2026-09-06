//! Offline schema and admission validator for the future PDFium reconstruction receipt.
//!
//! This module intentionally stops at typed receipt validation. It does not
//! spawn a process, access the network, inspect a host, mutate a cache, or
//! claim that PDFium was reconstructed. A later controller may consume this
//! contract only after a separately reviewed receipt exists.
const std = @import("std");

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
