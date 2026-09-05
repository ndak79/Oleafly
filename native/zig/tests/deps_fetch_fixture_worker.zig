const std = @import("std");
const builtin = @import("builtin");
const deps = @import("deps");
const deps_fetch = @import("deps_fetch");
const fixture_zip = @import("deps_fetch_fixture_archive.zig");

const root_sentinel_name = ".texflow-deps-fixture-root";
const root_sentinel_prefix = "texflow-deps-fixture-v1:";
const fixture_v1 = "fixture dependency payload version one\n";
const fixture_v2 = "fixture dependency payload version two\n";
// The process fixture is executed only by Windows ACL/reparse tests, but the
// test executable is still compiled on the Linux portability lane. Keep the
// handle-shaped API portable and make every Win32 mutation helper compile out
// on non-Windows targets.
const FixtureHandle = if (builtin.os.tag == .windows) std.os.windows.HANDLE else std.Io.File.Handle;

const Pause = enum {
    none,
    lock,
    stage_created,
    source,
    archive,
    payload_materialized,
    stage_validated,
    stage_children_frozen,
    stage_frozen,
    stage_pins_released,
    generation,
    selector,
    quarantine,
    quarantine_evidence,
};

const SeedFault = enum {
    none,
    selected_payload_tamper,
    selected_archive_acl,
    selected_payload_acl,
    inactive_payload_reparse,
    inactive_payload_acl,
    inactive_archive_acl,
    inactive_payload_tamper,
    inactive_archive_tamper,
    inactive_receipt_tamper,
    inactive_unexpected_child,
};

const ObserverContext = struct {
    io: std.Io,
    pause: Pause,
    forbid_source: bool,
    paused: bool = false,
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 5) return error.UnsafeFixtureRoot;
    const command = args[1];
    const cache_root_path = args[2];
    const pause = std.meta.stringToEnum(Pause, args[3]) orelse return error.InvalidArguments;
    const nonce = args[4];
    try validateFixtureRoot(init.gpa, init.io, cache_root_path, nonce);
    if (std.mem.startsWith(u8, command, "tamper-quarantine-")) {
        try tamperQuarantineEvidence(init.gpa, init.io, cache_root_path, command);
        return;
    }
    if (seedFaultForCommand(command)) |seed_fault| {
        try seedFixtureCache(init.gpa, init.io, cache_root_path, nonce, seed_fault);
        return;
    }
    if (std.mem.startsWith(u8, command, "withhold-marker-")) {
        var input_buffer: [1]u8 = undefined;
        var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
        _ = try input.interface.takeByte();
        return;
    }

    const is_v2 = std.mem.endsWith(u8, command, "-v2");
    const nested = std.mem.indexOf(u8, command, "nested") != null;
    const nested_bytes = if (nested) try fixture_zip.makeStoredZip(init.gpa, &.{
        .{ .name = "nested/deep/data.bin", .data = fixture_v1 },
    }) else null;
    defer if (nested_bytes) |archive| init.gpa.free(archive);
    const bytes = nested_bytes orelse if (is_v2) fixture_v2 else fixture_v1;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    var artifact = fixtureArtifact(
        if (nested) "fixture-nested-v1" else if (is_v2) "fixture-v2" else "fixture-v1",
        bytes,
        &digest_hex,
    );
    const nested_members = [_]deps.MemberLock{.{ .path = "nested/deep/data.bin", .size_bytes = fixture_v1.len }};
    if (nested) {
        artifact.archive_format = .restricted_zip;
        artifact.expected_expanded_bytes = fixture_v1.len;
        artifact.inventory = &nested_members;
        artifact.retained_members = &nested_members;
    }

    if (std.mem.startsWith(u8, command, "contend-fetch-")) {
        try observeExclusiveContention(init.gpa, init.io, cache_root_path);
    }

    const operation: deps_fetch.FixtureOperation = if (std.mem.startsWith(u8, command, "bootstrap-"))
        .bootstrap
    else if (std.mem.startsWith(u8, command, "fetch-") or
        std.mem.startsWith(u8, command, "contend-fetch-"))
        .fetch
    else if (std.mem.startsWith(u8, command, "audit-"))
        .audit
    else
        return error.InvalidArguments;
    var observer_context: ObserverContext = .{
        .io = init.io,
        .pause = pause,
        .forbid_source = std.mem.indexOf(u8, command, "no-source") != null,
    };
    deps_fetch.runFixtureCacheOperation(
        init.gpa,
        init.io,
        cache_root_path,
        artifact,
        bytes,
        operation,
        .{
            .context = &observer_context,
            .callback = observe,
        },
    ) catch |err| return deps_fetch.reportFixtureCacheError(operation, err);
}

fn seedFaultForCommand(command: []const u8) ?SeedFault {
    if (std.mem.eql(u8, command, "seed-valid-v1")) return .none;
    if (std.mem.startsWith(u8, command, "seed-selected-payload-tamper-"))
        return .selected_payload_tamper;
    if (std.mem.startsWith(u8, command, "seed-selected-archive-acl-"))
        return .selected_archive_acl;
    if (std.mem.startsWith(u8, command, "seed-selected-payload-acl-"))
        return .selected_payload_acl;
    if (std.mem.startsWith(u8, command, "seed-inactive-payload-reparse-"))
        return .inactive_payload_reparse;
    if (std.mem.startsWith(u8, command, "seed-inactive-payload-acl-"))
        return .inactive_payload_acl;
    if (std.mem.startsWith(u8, command, "seed-inactive-archive-acl-"))
        return .inactive_archive_acl;
    if (std.mem.startsWith(u8, command, "seed-inactive-payload-tamper-"))
        return .inactive_payload_tamper;
    if (std.mem.startsWith(u8, command, "seed-inactive-archive-tamper-"))
        return .inactive_archive_tamper;
    if (std.mem.startsWith(u8, command, "seed-inactive-receipt-tamper-"))
        return .inactive_receipt_tamper;
    if (std.mem.startsWith(u8, command, "seed-inactive-unexpected-child-"))
        return .inactive_unexpected_child;
    return null;
}

const seed_selected_generation = "g-222222222222222222222222";
const seed_inactive_generation = "g-333333333333333333333333";

fn seedFixtureCache(
    allocator: std.mem.Allocator,
    io: std.Io,
    absolute_cache_root: []const u8,
    nonce: []const u8,
    fault: SeedFault,
) !void {
    if (comptime builtin.os.tag != .windows) return error.UnsupportedPlatform;
    _ = nonce; // main already validated the fixture root and its nonce.
    // Acquire the baseline through production, then clone its verified bytes
    // into an unpublished fixture-owned generation. No descendant handle is
    // retained across a production rename, and no scratch cache is needed.
    const v1_digest = fixtureDigest(fixture_v1);
    const v1_artifact = fixtureArtifact("fixture-v1", fixture_v1, &v1_digest);
    try deps_fetch.runFixtureCacheOperation(
        allocator,
        io,
        absolute_cache_root,
        v1_artifact,
        fixture_v1,
        .fetch,
        .{},
    );
    var target = try std.Io.Dir.openDirAbsolute(io, absolute_cache_root, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer target.close(io);
    const source_name = try currentGenerationAlloc(allocator, io, target);
    defer allocator.free(source_name);

    if (!isSelectedSeedFault(fault)) {
        const v2_digest = fixtureDigest(fixture_v2);
        try deps_fetch.runFixtureCacheOperation(
            allocator,
            io,
            absolute_cache_root,
            fixtureArtifact("fixture-v2", fixture_v2, &v2_digest),
            fixture_v2,
            .fetch,
            .{},
        );
    }
    var store = try target.openDir(io, ".v2/presentmon", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer store.close(io);
    var generations = try store.openDir(io, deps.cache_generations_directory, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer generations.close(io);
    var source = try generations.openDir(io, source_name, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer source.close(io);
    const generation_name = if (isSelectedSeedFault(fault))
        seed_selected_generation
    else
        seed_inactive_generation;
    try copySeedGeneration(
        allocator,
        io,
        source,
        generations,
        generation_name,
        fault,
        absolute_cache_root,
    );
    if (isSelectedSeedFault(fault)) {
        try writeSeedSelector(io, store, generation_name);
    }
}

fn fixtureDigest(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

fn tamperQuarantineEvidence(
    allocator: std.mem.Allocator,
    io: std.Io,
    absolute_root: []const u8,
    command: []const u8,
) !void {
    if (comptime builtin.os.tag != .windows) return error.UnsupportedPlatform;
    var root = try std.Io.Dir.openDirAbsolute(io, absolute_root, .{ .iterate = true, .follow_symlinks = false });
    defer root.close(io);
    var quarantine = try root.openDir(io, ".v2/presentmon/quarantine", .{ .iterate = true, .follow_symlinks = false });
    defer quarantine.close(io);
    const sidecar = seed_selected_generation ++ ".json";
    const bytes = try quarantine.readFileAlloc(io, sidecar, allocator, .limited(4096));
    defer allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    if (std.mem.eql(u8, command, "tamper-quarantine-hash")) {
        const hash = parsed.value.object.getPtr("archive_sha256") orelse return error.InvalidArguments;
        hash.array.items[0].integer ^= 1;
    } else if (std.mem.eql(u8, command, "tamper-quarantine-identity")) {
        const version = parsed.value.object.getPtr("artifact_version") orelse return error.InvalidArguments;
        version.* = .{ .string = "another-version" };
    } else if (std.mem.eql(u8, command, "tamper-quarantine-schema")) {
        const schema = parsed.value.object.getPtr("schema_version") orelse return error.InvalidArguments;
        schema.* = .{ .integer = 2 };
    } else if (!std.mem.eql(u8, command, "tamper-quarantine-malformed") and
        !std.mem.eql(u8, command, "tamper-quarantine-acl")) return error.InvalidArguments;
    const modified = try std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
    defer allocator.free(modified);
    try quarantine.deleteFile(io, sidecar);
    var file: std.Io.File = .{
        .handle = try createChildHandle(quarantine.handle, sidecar, false),
        .flags = .{ .nonblocking = false },
    };
    defer file.close(io);
    try file.writeStreamingAll(io, if (std.mem.eql(u8, command, "tamper-quarantine-malformed")) "{}" else modified);
    try file.sync(io);
    try setOwnerAcl(file.handle, false, !std.mem.eql(u8, command, "tamper-quarantine-acl"));
}

fn isSelectedSeedFault(fault: SeedFault) bool {
    return switch (fault) {
        .none, .selected_payload_tamper, .selected_archive_acl, .selected_payload_acl => true,
        else => false,
    };
}

fn currentGenerationAlloc(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
) ![]u8 {
    var store = try root.openDir(io, ".v2/presentmon", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer store.close(io);
    const bytes = try store.readFileAlloc(
        io,
        deps.cache_selector_file,
        allocator,
        .limited(deps.cache_selector_max_bytes + 1),
    );
    defer allocator.free(bytes);
    return allocator.dupe(u8, try deps.parseCacheSelector(bytes));
}

fn copySeedGeneration(
    allocator: std.mem.Allocator,
    io: std.Io,
    source: std.Io.Dir,
    generations: std.Io.Dir,
    name: []const u8,
    fault: SeedFault,
    reparse_target: []const u8,
) !void {
    if (comptime builtin.os.tag != .windows) return error.UnsupportedPlatform;
    try deps.validateCacheGenerationName(name);
    var generation: std.Io.Dir = .{
        .handle = try createChildHandle(generations.handle, name, true),
    };
    defer generation.close(io);
    var payload: std.Io.Dir = .{
        .handle = try createChildHandle(generation.handle, "payload", true),
    };
    defer payload.close(io);
    try copySeedFile(
        allocator,
        io,
        source,
        "archive.bin",
        generation,
        "archive.bin",
        fault == .inactive_archive_tamper,
        fault == .selected_archive_acl or fault == .inactive_archive_acl,
    );
    try copySeedFile(
        allocator,
        io,
        source,
        ".complete.json",
        generation,
        ".complete.json",
        fault == .inactive_receipt_tamper,
        false,
    );
    try copySeedFile(
        allocator,
        io,
        source,
        "payload/PresentMon-2.5.1-x64.exe",
        payload,
        "PresentMon-2.5.1-x64.exe",
        fault == .selected_payload_tamper or fault == .inactive_payload_tamper,
        fault == .selected_payload_acl or fault == .inactive_payload_acl,
    );
    if (fault == .inactive_payload_reparse) {
        try injectPayloadReparse(allocator, payload.handle, reparse_target);
    } else if (fault == .inactive_unexpected_child) {
        try injectUnexpectedChild(generation.handle);
    }

    // Every handle was created with WRITE_DAC while the tree was mutable.
    // Seal leaves before parents; closing them ends the fixture's write grants.
    try setOwnerAcl(payload.handle, true, true);
    try setOwnerAcl(generation.handle, true, true);
}

fn copySeedFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    source: std.Io.Dir,
    source_path: []const u8,
    destination: std.Io.Dir,
    destination_name: []const u8,
    tamper: bool,
    broad_acl: bool,
) !void {
    if (comptime builtin.os.tag != .windows) return error.UnsupportedPlatform;
    const bytes = try source.readFileAlloc(io, source_path, allocator, .limited(4096));
    defer allocator.free(bytes);
    if (tamper) {
        if (bytes.len == 0) return error.EmptySeedFile;
        bytes[0] ^= 1;
    }
    var file: std.Io.File = .{
        .handle = try createChildHandle(destination.handle, destination_name, false),
        .flags = .{ .nonblocking = false },
    };
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
    try file.sync(io);
    if (broad_acl) {
        try applyBroadAcl(file.handle);
    } else {
        try setOwnerAcl(file.handle, false, true);
    }
}

fn writeSeedSelector(
    io: std.Io,
    store: std.Io.Dir,
    generation: []const u8,
) !void {
    var buffer: [deps.cache_selector_max_bytes]u8 = undefined;
    const selector = try deps.formatCacheSelector(&buffer, generation);
    try store.deleteFile(io, deps.cache_selector_file);
    var file: std.Io.File = .{
        .handle = try createChildHandle(store.handle, deps.cache_selector_file, false),
        .flags = .{ .nonblocking = false },
    };
    defer file.close(io);
    try file.writeStreamingAll(io, selector);
    try file.sync(io);
}

fn fixtureArtifact(
    version: []const u8,
    bytes: []const u8,
    digest_hex: []const u8,
) deps.Artifact {
    return .{
        .id = "presentmon",
        .version = version,
        .purpose = "deterministic dependency-cache integration fixture",
        .source_url = "https://example.invalid/fixture",
        .license_spdx = "MIT",
        .license_url = "https://example.invalid/fixture/LICENSE",
        .url = "https://example.invalid/fixture.bin",
        .allowed_path_prefix = "/fixture.bin",
        .integrity = .byte_archive,
        .archive_format = .direct_file,
        .archive_root = "",
        .archive_size_bytes = bytes.len,
        .archive_sha256 = digest_hex,
        .expected_entries = 1,
        .expected_regular_files = 1,
        .download_limit_bytes = 4096,
        .expanded_limit_bytes = 4096,
        .expected_expanded_bytes = bytes.len,
        .dependencies = &.{},
        .build_switches = &.{},
    };
}

fn validateFixtureRoot(
    _: std.mem.Allocator,
    io: std.Io,
    absolute_path: []const u8,
    nonce: []const u8,
) !void {
    if (!std.Io.Dir.path.isAbsolute(absolute_path)) return error.UnsafeFixtureRoot;
    if (nonce.len != 32) return error.UnsafeFixtureRoot;
    for (nonce) |byte| {
        if (!std.ascii.isDigit(byte) and !(byte >= 'a' and byte <= 'f')) {
            return error.UnsafeFixtureRoot;
        }
    }
    var root = try std.Io.Dir.openDirAbsolute(io, absolute_path, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer root.close(io);
    if ((try root.stat(io)).kind != .directory) return error.UnsafeFixtureRoot;
    var sentinel_identity = try root.openFile(io, root_sentinel_name, .{
        .path_only = true,
        .follow_symlinks = false,
        .resolve_beneath = true,
    });
    defer sentinel_identity.close(io);
    var expected_buffer: [root_sentinel_prefix.len + 32 + 1]u8 = undefined;
    const expected = try std.fmt.bufPrint(
        &expected_buffer,
        "{s}{s}\n",
        .{ root_sentinel_prefix, nonce },
    );
    const expected_stat = try sentinel_identity.stat(io);
    if (expected_stat.kind != .file or expected_stat.size != expected.len) {
        return error.UnsafeFixtureRoot;
    }
    var sentinel = try root.openFile(io, root_sentinel_name, .{
        .allow_directory = false,
        .follow_symlinks = true,
        .resolve_beneath = true,
    });
    defer sentinel.close(io);
    const actual_stat = try sentinel.stat(io);
    if (actual_stat.kind != .file or actual_stat.inode != expected_stat.inode or
        actual_stat.size != expected_stat.size)
    {
        return error.UnsafeFixtureRoot;
    }
    var contents: [root_sentinel_prefix.len + 32 + 1]u8 = undefined;
    var reader = sentinel.reader(io, &.{});
    reader.interface.readSliceAll(&contents) catch return error.UnsafeFixtureRoot;
    if (!std.mem.eql(u8, &contents, expected)) {
        return error.UnsafeFixtureRoot;
    }
}

fn observe(context_opaque: ?*anyopaque, event: deps_fetch.FixtureEvent) !void {
    const context: *ObserverContext = @ptrCast(@alignCast(context_opaque orelse
        return error.MissingObserverContext));
    if (event == .source_opened and context.forbid_source) return error.SourceUnexpected;
    if (context.paused or !eventMatchesPause(event, context.pause)) return;
    context.paused = true;
    var output_buffer: [64]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(context.io, &output_buffer);
    try output.interface.writeAll(switch (event) {
        .lock_acquired => "LOCK_ACQUIRED\n",
        .stage_created_pinned => "STAGE_CREATED_PINNED\n",
        .source_opened => "SOURCE_OPENED\n",
        .archive_materialized => "ARCHIVE_MATERIALIZED\n",
        .payload_materialization_started => unreachable,
        .payload_materialized => "PAYLOAD_MATERIALIZED\n",
        .stage_validated => "STAGE_VALIDATED\n",
        .stage_children_frozen => "STAGE_CHILDREN_FROZEN\n",
        .stage_frozen => "STAGE_FROZEN\n",
        .stage_pins_released => "STAGE_PINS_RELEASED\n",
        .generation_published => "GENERATION_PUBLISHED\n",
        .generation_quarantined => "GENERATION_QUARANTINED\n",
        .quarantine_evidence_started => "QUARANTINE_EVIDENCE_STARTED\n",
        .selector_published => "SELECTOR_PUBLISHED\n",
    });
    try output.interface.flush();

    var input_buffer: [1]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(context.io, &input_buffer);
    _ = try input.interface.takeByte();
}

fn applyBroadAcl(handle: FixtureHandle) !void {
    if (comptime builtin.os.tag != .windows) return error.TestAclWriteFailed;
    var descriptor: ?*anyopaque = null;
    if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
        std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;;FA;;;OW)(A;;GW;;;WD)"),
        1,
        &descriptor,
        null,
    ) == 0 or descriptor == null) {
        return error.TestAclDescriptorFailed;
    }
    defer _ = LocalFree(descriptor);
    if (NtSetSecurityObject(
        handle,
        dacl_security_information | protected_dacl_security_information,
        descriptor.?,
    ) != .SUCCESS) return error.TestAclWriteFailed;
}

fn setOwnerAcl(
    handle: FixtureHandle,
    directory: bool,
    read_execute: bool,
) !void {
    if (comptime builtin.os.tag != .windows) return error.TestAclWriteFailed;
    const sddl = if (read_execute)
        if (directory)
            std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;OICI;FRGX;;;OW)")
        else
            std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;;FRGX;;;OW)")
    else if (directory)
        std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;OICI;FA;;;OW)")
    else
        std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;;FA;;;OW)");
    var descriptor: ?*anyopaque = null;
    if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
        sddl,
        1,
        &descriptor,
        null,
    ) == 0 or descriptor == null) return error.TestAclWriteFailed;
    defer _ = LocalFree(descriptor);
    if (NtSetSecurityObject(
        handle,
        dacl_security_information | protected_dacl_security_information,
        descriptor.?,
    ) != .SUCCESS) return error.TestAclWriteFailed;
}

fn createChildHandle(
    parent: FixtureHandle,
    name: []const u8,
    directory: bool,
) !FixtureHandle {
    if (comptime builtin.os.tag != .windows) return error.TestFileMutationFailed;
    const windows = std.os.windows;
    const name_w = try std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, name);
    defer std.heap.page_allocator.free(name_w);
    var descriptor: ?*anyopaque = null;
    const sddl = if (directory)
        std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;OICI;FA;;;OW)")
    else
        std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;;FA;;;OW)");
    if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
        sddl,
        1,
        &descriptor,
        null,
    ) == 0 or descriptor == null) return error.TestAclWriteFailed;
    defer _ = LocalFree(descriptor);

    var object_name = windows.UNICODE_STRING.init(name_w[0..name.len]);
    const attributes: windows.OBJECT.ATTRIBUTES = .{
        .RootDirectory = parent,
        .Attributes = .{ .CASE_INSENSITIVE = true },
        .ObjectName = &object_name,
        .SecurityDescriptor = descriptor,
        .SecurityQualityOfService = null,
    };
    const desired: windows.ACCESS_MASK = @bitCast(
        // NtCreateFile validates synchronous I/O before mapping generic rights.
        generic_read | generic_write | delete_access | read_control | write_dac | synchronize,
    );
    var handle: windows.HANDLE = undefined;
    var io_status: windows.IO_STATUS_BLOCK = undefined;
    const status = windows.ntdll.NtCreateFile(
        &handle,
        desired,
        &attributes,
        &io_status,
        null,
        .{ .NORMAL = true },
        .{ .READ = true, .WRITE = true, .DELETE = true },
        .CREATE,
        .{
            .DIRECTORY_FILE = directory,
            .NON_DIRECTORY_FILE = !directory,
            .IO = .SYNCHRONOUS_NONALERT,
            .OPEN_FOR_BACKUP_INTENT = true,
        },
        null,
        0,
    );
    return switch (status) {
        .SUCCESS => handle,
        else => {
            std.debug.print("fixture create failed name={s} status=0x{x}\n", .{ name, @intFromEnum(status) });
            return error.TestFileMutationFailed;
        },
    };
}

fn injectUnexpectedChild(parent: FixtureHandle) !void {
    if (comptime builtin.os.tag != .windows) return error.TestFileMutationFailed;
    try setOwnerAcl(parent, true, false);
    var restored = false;
    defer if (!restored) setOwnerAcl(parent, true, true) catch {};
    const child = try createChildHandle(parent, "unexpected", false);
    defer std.os.windows.CloseHandle(child);
    try setOwnerAcl(child, false, true);
    try setOwnerAcl(parent, true, true);
    restored = true;
}

fn injectPayloadReparse(
    allocator: std.mem.Allocator,
    payload: FixtureHandle,
    target_path: []const u8,
) !void {
    if (comptime builtin.os.tag != .windows) return error.TestFileMutationFailed;
    try setOwnerAcl(payload, true, false);
    var restored = false;
    defer if (!restored) setOwnerAcl(payload, true, true) catch {};
    const child = try createChildHandle(payload, "junction", true);
    defer std.os.windows.CloseHandle(child);
    try setDirectoryJunction(allocator, child, target_path);
    try setOwnerAcl(child, true, true);
    try setOwnerAcl(payload, true, true);
    restored = true;
}

fn setDirectoryJunction(
    allocator: std.mem.Allocator,
    handle: FixtureHandle,
    target_path: []const u8,
) !void {
    if (comptime builtin.os.tag != .windows) return error.TestFileMutationFailed;
    const substitute_utf8 = try std.fmt.allocPrint(allocator, "\\??\\{s}", .{target_path});
    defer allocator.free(substitute_utf8);
    const substitute = try std.unicode.utf8ToUtf16LeAlloc(allocator, substitute_utf8);
    defer allocator.free(substitute);
    const display = try std.unicode.utf8ToUtf16LeAlloc(allocator, target_path);
    defer allocator.free(display);
    const substitute_bytes = substitute.len * @sizeOf(u16);
    const display_bytes = display.len * @sizeOf(u16);
    const path_bytes = substitute_bytes + 2 + display_bytes + 2;
    const reparse_data_length = 8 + path_bytes;
    const total_bytes = 8 + reparse_data_length;
    const buffer = try allocator.alloc(u8, total_bytes);
    defer allocator.free(buffer);
    @memset(buffer, 0);
    std.mem.writeInt(u32, buffer[0..4], io_reparse_tag_mount_point, .little);
    std.mem.writeInt(u16, buffer[4..6], @intCast(reparse_data_length), .little);
    std.mem.writeInt(u16, buffer[8..10], 0, .little);
    std.mem.writeInt(u16, buffer[10..12], @intCast(substitute_bytes), .little);
    std.mem.writeInt(u16, buffer[12..14], @intCast(substitute_bytes + 2), .little);
    std.mem.writeInt(u16, buffer[14..16], @intCast(display_bytes), .little);
    @memcpy(buffer[16 .. 16 + substitute_bytes], std.mem.sliceAsBytes(substitute));
    const display_start = 16 + substitute_bytes + 2;
    @memcpy(buffer[display_start .. display_start + display_bytes], std.mem.sliceAsBytes(display));
    var returned: u32 = 0;
    if (DeviceIoControl(
        handle,
        fsctl_set_reparse_point,
        buffer.ptr,
        @intCast(buffer.len),
        null,
        0,
        &returned,
        null,
    ) == 0) return error.TestFileMutationFailed;
}

fn eventMatchesPause(event: deps_fetch.FixtureEvent, pause: Pause) bool {
    return switch (pause) {
        .none => false,
        .lock => event == .lock_acquired,
        .stage_created => event == .stage_created_pinned,
        .source => event == .source_opened,
        .archive => event == .archive_materialized,
        .payload_materialized => event == .payload_materialized,
        .stage_validated => event == .stage_validated,
        .stage_children_frozen => event == .stage_children_frozen,
        .stage_frozen => event == .stage_frozen,
        .stage_pins_released => event == .stage_pins_released,
        .generation => event == .generation_published,
        .selector => event == .selector_published,
        .quarantine => event == .generation_quarantined,
        .quarantine_evidence => event == .quarantine_evidence_started,
    };
}

fn observeExclusiveContention(
    allocator: std.mem.Allocator,
    io: std.Io,
    absolute_path: []const u8,
) !void {
    if (comptime builtin.os.tag != .windows) return error.UnsupportedPlatform;
    const lock_path = try std.fs.path.join(allocator, &.{ absolute_path, ".lock" });
    defer allocator.free(lock_path);
    const lock_path_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, lock_path);
    defer allocator.free(lock_path_w);
    const handle = CreateFileW(
        lock_path_w.ptr,
        generic_read,
        file_share_read | file_share_write | file_share_delete,
        null,
        open_existing,
        file_attribute_normal | file_flag_open_reparse_point,
        null,
    );
    if (handle == std.os.windows.INVALID_HANDLE_VALUE) return error.LockProbeOpenFailed;
    defer std.os.windows.CloseHandle(handle);
    var io_status: std.os.windows.IO_STATUS_BLOCK = undefined;
    const offset: std.os.windows.LARGE_INTEGER = 0;
    const length: std.os.windows.LARGE_INTEGER = 1;
    switch (std.os.windows.ntdll.NtLockFile(
        handle,
        null,
        null,
        null,
        &io_status,
        &offset,
        &length,
        null,
        .fromBool(true),
        .fromBool(true),
    )) {
        .FILE_LOCK_CONFLICT, .LOCK_NOT_GRANTED => {},
        .SUCCESS => return error.ExpectedExclusiveLockContention,
        else => return error.UnexpectedLockStatus,
    }
    var output_buffer: [64]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(io, &output_buffer);
    try output.interface.writeAll("CONTENDED\n");
    try output.interface.flush();
}

const generic_read: u32 = 0x80000000;
const generic_write: u32 = 0x40000000;
const read_control: u32 = 0x00020000;
const write_dac: u32 = 0x00040000;
const synchronize: u32 = 0x00100000;
const delete_access: u32 = 0x00010000;
const file_share_read: u32 = 0x00000001;
const file_share_write: u32 = 0x00000002;
const file_share_delete: u32 = 0x00000004;
const open_existing: u32 = 3;
const file_attribute_normal: u32 = 0x00000080;
const file_flag_open_reparse_point: u32 = 0x00200000;
const file_flag_backup_semantics: u32 = 0x02000000;
const io_reparse_tag_mount_point: u32 = 0xa0000003;
const fsctl_set_reparse_point: u32 = 0x000900a4;

extern "kernel32" fn CreateFileW(
    file_name: [*:0]const u16,
    desired_access: u32,
    share_mode: u32,
    security_attributes: ?*const anyopaque,
    creation_disposition: u32,
    flags_and_attributes: u32,
    template_file: ?std.os.windows.HANDLE,
) callconv(.winapi) std.os.windows.HANDLE;

extern "advapi32" fn ConvertStringSecurityDescriptorToSecurityDescriptorW(
    string_security_descriptor: [*:0]const u16,
    string_sd_revision: u32,
    security_descriptor: *?*anyopaque,
    security_descriptor_size: ?*u32,
) callconv(.winapi) i32;

extern "kernel32" fn DeviceIoControl(
    device: std.os.windows.HANDLE,
    control_code: u32,
    input: ?*const anyopaque,
    input_size: u32,
    output: ?*anyopaque,
    output_size: u32,
    bytes_returned: *u32,
    overlapped: ?*anyopaque,
) callconv(.winapi) i32;

extern "kernel32" fn LocalFree(memory: ?*anyopaque) callconv(.winapi) ?*anyopaque;

extern "ntdll" fn NtSetSecurityObject(
    handle: std.os.windows.HANDLE,
    security_information: u32,
    security_descriptor: *anyopaque,
) callconv(.winapi) std.os.windows.NTSTATUS;

const dacl_security_information: u32 = 0x00000004;
const protected_dacl_security_information: u32 = 0x80000000;
