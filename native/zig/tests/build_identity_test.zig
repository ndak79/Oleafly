const std = @import("std");
const identity = @import("app_build_identity");

test "build identity is the domain-separated SHA-256 known answer" {
    const source = [_]u8{0} ** 32;
    const lock = [_]u8{0} ** 32;
    const digest = identity.compute(source, lock);
    const encoded = identity.hex(digest);
    try std.testing.expectEqualStrings(
        "662fd4c8a81ddaf913bb6a6663f3733ffb75e969bb86970a100759d61d983c64",
        &encoded,
    );
}

test "build identity changes for each source or lock bit" {
    const source = [_]u8{0} ** 32;
    const lock = [_]u8{0} ** 32;
    const baseline = identity.compute(source, lock);
    var changed_source = source;
    changed_source[0] = 1;
    var changed_lock = lock;
    changed_lock[31] = 1;
    try std.testing.expect(!std.mem.eql(u8, &baseline, &identity.compute(changed_source, lock)));
    try std.testing.expect(!std.mem.eql(u8, &baseline, &identity.compute(source, changed_lock)));
}

test "version info is explicitly non-release private feasibility metadata" {
    const version = identity.version_info;
    try std.testing.expectEqual(@as(u16, 0), version.major);
    try std.testing.expectEqual(@as(u16, 0), version.minor);
    try std.testing.expectEqual(@as(u16, 2), version.patch);
    try std.testing.expectEqual(@as(u16, 0), version.revision);
    try std.testing.expectEqualStrings("0.0.2.0", version.file_version);
    try std.testing.expectEqualStrings("0.0.2-feasibility", version.product_version);
    try std.testing.expectEqualStrings("T0.2 architecture feasibility; not release-qualified", version.private_build);
    try std.testing.expect(version.is_prerelease);
    try std.testing.expect(version.is_private_build);
    try std.testing.expectEqualStrings("040904B0", version.translation);
    try std.testing.expectEqualStrings("TExFlow", identity.version_info_for(.ui).internal_name);
    try std.testing.expectEqualStrings("TExFlow.PdfWorker", identity.version_info_for(.pdf_worker).internal_name);
}
