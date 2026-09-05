//! Source-level contract tests for the TExFlow UI version and Win32 resources.
//! The executable/PE assertions live beside the product test; this file keeps
//! the exact declarative contract portable and deterministic on every target.
const std = @import("std");
const contract = @import("app_version_resource");
const assets = @import("resource_assets");

const rc_source = assets.rc_source;
const manifest_source = assets.manifest_source;

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

test "UI version contract exposes the exact feasibility tuple" {
    try std.testing.expectEqual(@as(u16, 0), contract.version.major);
    try std.testing.expectEqual(@as(u16, 0), contract.version.minor);
    try std.testing.expectEqual(@as(u16, 2), contract.version.patch);
    try std.testing.expectEqual(@as(u16, 0), contract.version.revision);
    try std.testing.expectEqualStrings("0.0.2.0", contract.file_version);
    try std.testing.expectEqualStrings("0.0.2-feasibility", contract.product_version);
    try std.testing.expectEqualStrings("T0.2 architecture feasibility; not release-qualified", contract.private_build);
    try std.testing.expectEqual(@as(u32, 0x0000_000a), contract.file_flags);
    try std.testing.expectEqual(@as(u32, 0x0000_003f), contract.file_flags_mask);
    try std.testing.expectEqual(@as(u32, 0x0004_0004), contract.file_os);
    try std.testing.expectEqual(@as(u32, 0x0000_0001), contract.file_type);
    try std.testing.expectEqual(@as(u32, 0x0000_0000), contract.file_subtype);
    try std.testing.expectEqual(@as(u16, 0x0409), contract.language);
    try std.testing.expectEqual(@as(u16, 0x04b0), contract.code_page);
    try std.testing.expectEqualStrings("040904B0", contract.translation);
    try std.testing.expect(contract.is_prerelease);
    try std.testing.expect(contract.is_private_build);
}

test "UI identity contract has no invented legal publisher fields" {
    try std.testing.expectEqualStrings("TExFlow", contract.product_name);
    try std.testing.expectEqualStrings("TExFlow", contract.file_description);
    try std.testing.expectEqualStrings("TExFlow", contract.internal_name);
    try std.testing.expectEqualStrings("TExFlow.exe", contract.original_filename);
    for ([_][]const u8{ "CompanyName", "LegalCopyright", "LegalTrademarks", "Publisher" }) |field| {
        try std.testing.expect(!contains(rc_source, field));
    }
}

test "tracked RC and manifest state the same explicit UI contract" {
    for ([_][]const u8{
        "FILEVERSION 0,0,2,0",
        "PRODUCTVERSION 0,0,2,0",
        "FILEFLAGSMASK 0x0000003fL",
        "FILEFLAGS VS_FF_PRERELEASE | VS_FF_PRIVATEBUILD",
        "FILEOS VOS_NT_WINDOWS32",
        "FILETYPE VFT_APP",
        "VALUE \"ProductName\", \"TExFlow\"",
        "VALUE \"FileDescription\", \"TExFlow\"",
        "VALUE \"InternalName\", \"TExFlow\"",
        "VALUE \"OriginalFilename\", \"TExFlow.exe\"",
        "VALUE \"FileVersion\", \"0.0.2.0\"",
        "VALUE \"ProductVersion\", \"0.0.2-feasibility\"",
        "VALUE \"PrivateBuild\", \"T0.2 architecture feasibility; not release-qualified\"",
        "BLOCK \"040904B0\"",
        "1 RT_MANIFEST \"TExFlow.exe.manifest\"",
    }) |literal| try std.testing.expect(contains(rc_source, literal));

    for ([_][]const u8{
        "dpiAwareness",
        "PerMonitorV2",
        "requestedExecutionLevel level=\"asInvoker\" uiAccess=\"false\"",
        "urn:schemas-microsoft-com:asm.v3",
    }) |literal| try std.testing.expect(contains(manifest_source, literal));
}
