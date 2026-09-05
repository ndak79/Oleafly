const std = @import("std");

pub const digest_bytes = 32;
pub const identity_domain = "texflow:build:v1\x00";

pub const version_flags = struct {
    pub const prerelease: u32 = 0x00000002;
    pub const private_build: u32 = 0x00000008;
};

pub const VersionInfo = struct {
    major: u16,
    minor: u16,
    patch: u16,
    revision: u16,
    file_version: []const u8,
    product_version: []const u8,
    private_build: []const u8,
    translation: []const u8,
    is_prerelease: bool,
    is_private_build: bool,
    windows_version: []const u8,
    application_type: []const u8,
    internal_name: []const u8,
};

pub const version_info = VersionInfo{
    .major = 0,
    .minor = 0,
    .patch = 2,
    .revision = 0,
    .file_version = "0.0.2.0",
    .product_version = "0.0.2-feasibility",
    .private_build = "T0.2 architecture feasibility; not release-qualified",
    .translation = "040904B0",
    .is_prerelease = true,
    .is_private_build = true,
    .windows_version = "VOS_NT_WINDOWS32",
    .application_type = "VFT_APP",
    .internal_name = "TExFlow",
};

/// Return the common role-neutral version tuple with the role-specific
/// InternalName.  `anytype` keeps this portable: callers may pass the role
/// enum from role.zig without making this digest module own that dependency.
pub fn version_info_for(role: anytype) VersionInfo {
    var result = version_info;
    const tag = @tagName(role);
    if (std.mem.eql(u8, tag, "pdf_worker")) {
        result.internal_name = "TExFlow.PdfWorker";
    } else if (std.mem.eql(u8, tag, "science_worker")) {
        result.internal_name = "TExFlow.ScienceWorker";
    } else {
        result.internal_name = "TExFlow";
    }
    return result;
}

/// Compute the exact common identity:
/// SHA-256("texflow:build:v1\\0" || source_set_sha256[32] ||
/// dependency_lock_sha256[32]).
pub fn compute(source_set_sha256: [digest_bytes]u8, dependency_lock_sha256: [digest_bytes]u8) [digest_bytes]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(identity_domain);
    hasher.update(&source_set_sha256);
    hasher.update(&dependency_lock_sha256);
    var digest: [digest_bytes]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

pub const build_identity = compute;

pub fn hex(digest: [digest_bytes]u8) [digest_bytes * 2]u8 {
    return std.fmt.bytesToHex(digest, .lower);
}
