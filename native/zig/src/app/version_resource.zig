//! Pure data contract shared by the tracked Windows VERSIONINFO resource and
//! the product/resource tests.  It deliberately has no Windows imports.

pub const NumericVersion = struct {
    major: u16,
    minor: u16,
    patch: u16,
    revision: u16,
};

pub const version = NumericVersion{
    .major = 0,
    .minor = 0,
    .patch = 2,
    .revision = 0,
};

pub const version_flags = struct {
    pub const prerelease: u32 = 0x0000_0002;
    pub const private_build: u32 = 0x0000_0008;
};

pub const file_flags_mask: u32 = 0x0000_003f;
pub const file_flags: u32 = version_flags.prerelease | version_flags.private_build;
pub const file_os: u32 = 0x0004_0004; // VOS_NT_WINDOWS32
pub const file_type: u32 = 0x0000_0001; // VFT_APP
pub const file_subtype: u32 = 0x0000_0000; // VFT2_UNKNOWN

pub const file_version = "0.0.2.0";
pub const product_version = "0.0.2-feasibility";
pub const private_build = "T0.2 architecture feasibility; not release-qualified";
pub const is_prerelease = true;
pub const is_private_build = true;

pub const language: u16 = 0x0409; // English (United States)
pub const code_page: u16 = 0x04b0; // Unicode UTF-16
pub const translation = "040904B0";
pub const windows_version = "VOS_NT_WINDOWS32";
pub const application_type = "VFT_APP";

pub const product_name = "TExFlow";
pub const file_description = "TExFlow";
pub const internal_name = "TExFlow";
pub const original_filename = "TExFlow.exe";

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
    .major = version.major,
    .minor = version.minor,
    .patch = version.patch,
    .revision = version.revision,
    .file_version = file_version,
    .product_version = product_version,
    .private_build = private_build,
    .translation = translation,
    .is_prerelease = is_prerelease,
    .is_private_build = is_private_build,
    .windows_version = windows_version,
    .application_type = application_type,
    .internal_name = internal_name,
};
