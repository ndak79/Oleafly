const std = @import("std");
const builtin = @import("builtin");
const inventory = @import("shipped_pe_inventory");
const pe = @import("pe_audit");

const testing = std.testing;

const image_opt = 0x98;
const section_table = 0x188;

fn put(comptime T: type, bytes: []u8, offset: usize, value: T) void {
    std.mem.writeInt(T, bytes[offset..][0..@sizeOf(T)], value, .little);
}

fn directory(bytes: []u8, index: usize, rva: u32, size: u32) void {
    put(u32, bytes, image_opt + 112 + index * 8, rva);
    put(u32, bytes, image_opt + 116 + index * 8, size);
}

fn peFixture() [0xc00]u8 {
    var b = [_]u8{0} ** 0xc00;
    @memcpy(b[0..2], "MZ");
    put(u32, &b, 0x3c, 0x80);
    @memcpy(b[0x80..0x84], "PE\x00\x00");
    put(u16, &b, 0x84, 0x8664);
    put(u16, &b, 0x86, 4);
    put(u16, &b, 0x94, 240);
    put(u16, &b, 0x96, 0x22);
    put(u16, &b, image_opt, 0x20b);
    put(u32, &b, image_opt + 16, 0x1000);
    put(u64, &b, image_opt + 24, 0x140000000);
    put(u32, &b, image_opt + 32, 0x1000);
    put(u32, &b, image_opt + 36, 0x200);
    put(u32, &b, image_opt + 56, 0x5000);
    put(u32, &b, image_opt + 60, 0x400);
    put(u16, &b, image_opt + 68, 3);
    put(u16, &b, image_opt + 70, 0x160);
    put(u32, &b, image_opt + 108, 16);
    const names = [_][]const u8{ ".text", ".rdata", ".data", ".reloc" };
    const flags = [_]u32{ 0x60000020, 0x40000040, 0xc0000040, 0x42000040 };
    for (names, flags, 0..) |name, flag, i| {
        const s = section_table + i * 40;
        @memcpy(b[s..][0..name.len], name);
        put(u32, &b, s + 8, 0x200);
        put(u32, &b, s + 12, @intCast((i + 1) * 0x1000));
        put(u32, &b, s + 16, 0x200);
        put(u32, &b, s + 20, @intCast(0x400 + i * 0x200));
        put(u32, &b, s + 36, flag);
    }
    b[0x400] = 0xc3;
    directory(&b, 1, 0x2000, 40);
    directory(&b, 5, 0x4000, 12);
    directory(&b, 12, 0x3000, 16);
    put(u32, &b, 0x600, 0x2040);
    put(u32, &b, 0x60c, 0x2080);
    put(u32, &b, 0x610, 0x3000);
    put(u64, &b, 0x640, 0x20a0);
    put(u64, &b, 0x800, 0x20a0);
    @memcpy(b[0x680..][0..13], "KERNEL32.dll\x00");
    @memcpy(b[0x6a2..][0..12], "ExitProcess\x00");
    put(u64, &b, 0x820, 0x140001000);
    put(u32, &b, 0xa00, 0x3000);
    put(u32, &b, 0xa04, 12);
    put(u16, &b, 0xa08, 0xa020);
    return b;
}

const functions = [_][]const u8{"ExitProcess"};
const pe_imports = [_]pe.Import{.{ .dll = "kernel32.dll", .functions = &functions }};
const pe_policy: pe.Policy = .{ .imports = &pe_imports };

const role_specs = [_]inventory.RoleSpec{
    .{ .name = "UI", .image_path = "bin/TExFlow.exe", .pe_policy = pe_policy },
    .{ .name = "PdfWorker", .image_path = "bin/TExFlow.PdfWorker.exe", .pe_policy = pe_policy },
    .{ .name = "ScienceWorker", .image_path = "bin/TExFlow.ScienceWorker.exe", .pe_policy = pe_policy },
};

fn manifestFor(specs: []const inventory.RoleSpec) inventory.Manifest {
    return .{
        .roles = specs,
        .authenticated = true,
        .manifest_sha256 = inventory.manifestDigest(specs),
    };
}

fn limits() inventory.Limits {
    return .{ .max_depth = 8, .max_files = 8, .max_file_bytes = 1024 * 1024, .max_bytes = 4 * 1024 * 1024 };
}

fn writeImage(tmp: *std.testing.TmpDir, path: []const u8, bytes: []const u8) !void {
    const separator = std.mem.lastIndexOfScalar(u8, path, '/') orelse return error.InvalidTestPath;
    try tmp.dir.createDirPath(testing.io, path[0..separator]);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = path, .data = bytes });
}

fn rootPath(tmp: *std.testing.TmpDir, buffer: []u8) ![]const u8 {
    return buffer[0..try tmp.dir.realPath(testing.io, buffer)];
}

fn populate(tmp: *std.testing.TmpDir) !void {
    const image = peFixture();
    try writeImage(tmp, "bin/TExFlow.exe", &image);
    try writeImage(tmp, "bin/TExFlow.PdfWorker.exe", &image);
    try writeImage(tmp, "bin/TExFlow.ScienceWorker.exe", &image);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "README.txt", .data = "ignored" });
}

fn isSymlinkUnavailable(err: anyerror) bool {
    return switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.ReadOnlyFileSystem,
        error.FileSystem,
        error.SystemResources,
        error.DiskQuota,
        error.NoSpaceLeft,
        error.Unexpected,
        => true,
        else => false,
    };
}

fn audit(tmp: *std.testing.TmpDir, manifest: inventory.Manifest, configured_limits: inventory.Limits) !inventory.Result {
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try rootPath(tmp, &root_buffer);
    return inventory.audit(testing.allocator, testing.io, root, manifest, configured_limits);
}

test "inventory audits the complete three-role payload and returns sorted digest" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer tmp.cleanup();
    try populate(&tmp);

    var result = try audit(&tmp, manifestFor(&role_specs), limits());
    defer result.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 3), result.files);
    try testing.expectEqual(@as(u64, 3 * 0xc00), result.bytes);
    try testing.expectEqualStrings("bin/texflow.exe", result.entries[0].path);
    try testing.expectEqualStrings("bin/texflow.pdfworker.exe", result.entries[1].path);
    try testing.expectEqualStrings("bin/texflow.scienceworker.exe", result.entries[2].path);
    try testing.expectEqual(inventory.Role.UI, result.entries[0].role);
    try testing.expectEqual(inventory.Role.PdfWorker, result.entries[1].role);
    try testing.expectEqual(inventory.Role.ScienceWorker, result.entries[2].role);
    try testing.expect(!std.mem.allEqual(u8, &result.digest, 0));

    var reversed = testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer reversed.cleanup();
    const image = peFixture();
    try writeImage(&reversed, "bin/TExFlow.ScienceWorker.exe", &image);
    try writeImage(&reversed, "bin/TExFlow.exe", &image);
    try writeImage(&reversed, "bin/TExFlow.PdfWorker.exe", &image);
    var reversed_result = try audit(&reversed, manifestFor(&role_specs), limits());
    defer reversed_result.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &result.digest, &reversed_result.digest);
}

test "manifest omissions extras duplicate paths and unauthenticated input fail closed" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer tmp.cleanup();
    try populate(&tmp);
    var missing = role_specs;
    missing[0] = role_specs[1];
    const duplicate = manifestFor(&missing);
    try testing.expectError(error.DuplicateRole, audit(&tmp, duplicate, limits()));

    var extra = role_specs;
    extra[2].name = "Installer";
    try testing.expectError(error.UnexpectedRole, audit(&tmp, manifestFor(&extra), limits()));

    var duplicate_path = role_specs;
    duplicate_path[2].image_path = duplicate_path[1].image_path;
    try testing.expectError(error.RolePathMismatch, audit(&tmp, manifestFor(&duplicate_path), limits()));

    var unauthenticated = manifestFor(&role_specs);
    unauthenticated.authenticated = false;
    try testing.expectError(error.UnauthenticatedManifest, audit(&tmp, unauthenticated, limits()));
}

test "manifest rejects traversal and absolute image paths" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer tmp.cleanup();
    try populate(&tmp);
    var specs = role_specs;
    specs[0].image_path = "../bin/TExFlow.exe";
    try testing.expectError(error.InvalidPath, audit(&tmp, manifestFor(&specs), limits()));
    specs[0].image_path = "C:/bin/TExFlow.exe";
    try testing.expectError(error.InvalidPath, audit(&tmp, manifestFor(&specs), limits()));

    try testing.expectError(
        error.InvalidPath,
        inventory.audit(testing.allocator, testing.io, "C:\\..\\payload", manifestFor(&role_specs), limits()),
    );
}

test "missing and extra PE images are hard errors" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;
    var missing = testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer missing.cleanup();
    const image = peFixture();
    try writeImage(&missing, "bin/TExFlow.exe", &image);
    try writeImage(&missing, "bin/TExFlow.PdfWorker.exe", &image);
    try testing.expectError(error.MissingImage, audit(&missing, manifestFor(&role_specs), limits()));

    var extra = testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer extra.cleanup();
    try populate(&extra);
    try writeImage(&extra, "bin/extra.dll", &image);
    try testing.expectError(error.ExtraImage, audit(&extra, manifestFor(&role_specs), limits()));
}

test "malformed PE bytes are rejected and cross-role imports stay isolated" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;
    var malformed = testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer malformed.cleanup();
    const bad = "not a PE";
    try writeImage(&malformed, "bin/TExFlow.exe", bad);
    try writeImage(&malformed, "bin/TExFlow.PdfWorker.exe", bad);
    try writeImage(&malformed, "bin/TExFlow.ScienceWorker.exe", bad);
    try testing.expectError(error.ImageRejected, audit(&malformed, manifestFor(&role_specs), limits()));

    var cross_role = peFixture();
    @memset(cross_role[0x680..0x68d], 0);
    @memcpy(cross_role[0x680..][0..11], "pdfium.dll\x00");
    var tmp = testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer tmp.cleanup();
    try writeImage(&tmp, "bin/TExFlow.exe", &cross_role);
    try writeImage(&tmp, "bin/TExFlow.PdfWorker.exe", &cross_role);
    try writeImage(&tmp, "bin/TExFlow.ScienceWorker.exe", &cross_role);
    var permissive_specs = role_specs;
    const permissive_imports = [_]pe.Import{
        .{ .dll = "kernel32.dll", .functions = &functions },
        .{ .dll = "pdfium.dll", .functions = &functions },
    };
    const permissive_policy: pe.Policy = .{ .imports = &permissive_imports };
    for (&permissive_specs) |*spec| spec.pe_policy = permissive_policy;
    // The authenticated allow-list may contain pdfium.dll, but role policy is
    // still rejected by the intrinsic cross-role deny-list.
    try testing.expectError(error.ImageRejected, audit(&tmp, manifestFor(&permissive_specs), limits()));
}

test "inventory enforces depth file and byte bounds" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer tmp.cleanup();
    try populate(&tmp);
    var bounded = limits();
    bounded.max_files = 2;
    try testing.expectError(error.FileLimit, audit(&tmp, manifestFor(&role_specs), bounded));
    bounded = limits();
    bounded.max_bytes = 2 * 0xc00;
    try testing.expectError(error.ByteLimit, audit(&tmp, manifestFor(&role_specs), bounded));
    bounded = limits();
    bounded.max_depth = 0;
    try testing.expectError(error.DepthLimit, audit(&tmp, manifestFor(&role_specs), bounded));
}

test "symlink or reparse entries are never followed" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer tmp.cleanup();
    try populate(&tmp);
    tmp.dir.symLink(testing.io, "bin/TExFlow.exe", "bin/alias.dll", .{}) catch |err| {
        if (isSymlinkUnavailable(err)) return error.SkipZigTest;
        return err;
    };
    try testing.expectError(error.ReparsePoint, audit(&tmp, manifestFor(&role_specs), limits()));
}

test "linux target is an explicit compile-only inventory surface" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{ .iterate = true, .follow_symlinks = false });
    defer tmp.cleanup();
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try rootPath(&tmp, &root_buffer);
    try testing.expectError(
        error.WindowsRuntimeOnly,
        inventory.audit(testing.allocator, testing.io, root, manifestFor(&role_specs), limits()),
    );
}
