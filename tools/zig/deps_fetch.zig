const std = @import("std");
const builtin = @import("builtin");
const deps = @import("deps");
const collision = @import("collision");

const cache_schema_version: u16 = 2;
const user_agent = "TExFlow-deps/0.2";
const max_cache_generations: usize = 64;

const Mode = enum {
    bootstrap,
    all,
    audit,
    export_ucd,
    export_zigwin32,
    export_attestation_inputs,
};

const CacheRootPolicy = enum {
    create_or_open,
    existing_only,
};

const CacheAclPolicy = enum {
    secure_and_verify,
    verify_only,
};

const CacheLockPolicy = enum {
    exclusive_create,
    shared_existing,
};

const InterruptedStagePolicy = enum {
    clean_safe,
    reject,
};

const ModePolicy = struct {
    cache_root: CacheRootPolicy,
    cache_acl: CacheAclPolicy,
    cache_lock: CacheLockPolicy,
    interrupted_stages: InterruptedStagePolicy,
};

fn policyForMode(mode: Mode) ModePolicy {
    return switch (mode) {
        .bootstrap, .all => .{
            .cache_root = .create_or_open,
            .cache_acl = .secure_and_verify,
            .cache_lock = .exclusive_create,
            .interrupted_stages = .clean_safe,
        },
        .audit, .export_ucd, .export_zigwin32, .export_attestation_inputs => .{
            .cache_root = .existing_only,
            .cache_acl = .verify_only,
            .cache_lock = .shared_existing,
            .interrupted_stages = .reject,
        },
    };
}

const Receipt = struct {
    schema_version: u16,
    artifact_id: []const u8,
    artifact_version: []const u8,
    archive_bytes: u64,
    archive_sha256: []const u8,
    payload_files: u32,
    payload_bytes: u64,
    payload_sha256: []const u8,
};

const CacheValidationErrorKind = enum {
    invalid,
    operational,
};

const CacheProbeState = enum {
    valid,
    invalid,
};

fn classifyCacheValidationError(err: anyerror) CacheValidationErrorKind {
    return switch (err) {
        // Only errors that deterministically describe bytes or structure in an
        // already-selected cache entry may trigger repair. Unknown errors are
        // operational by default so a new or platform-specific I/O failure can
        // never be mistaken for evidence that the cache is corrupt.
        error.ArchiveCompressedTooLarge,
        error.ArchiveEntryCountMismatch,
        error.ArchiveExpandedSizeMismatch,
        error.ArchiveExpandedTooLarge,
        error.ArchiveMemberTooLarge,
        error.ArchiveRegularFileCountMismatch,
        error.ArchiveRetainedMemberMismatch,
        error.AmbiguousZipDataDescriptor,
        error.CacheReparsePoint,
        error.CanonicalTreeDigestMismatch,
        error.CanonicalTreeFileCountMismatch,
        error.CompressionRatioExceeded,
        error.ContentLengthMismatch,
        error.DigestMismatch,
        error.DownloadIncomplete,
        error.DownloadLimitExceeded,
        error.DownloadSizeMismatch,
        error.DuplicateMemberPath,
        error.DuplicateZipExtraField,
        error.DuplicateZipRecord,
        error.EndOfStream,
        error.ExtractionEntryTypeMismatch,
        error.ExtractionReparsePoint,
        error.ExtractionSizeMismatch,
        error.FileNotFound,
        error.InvalidCacheContainer,
        error.InvalidCacheFile,
        error.InvalidCacheGenerationName,
        error.InvalidCacheReceipt,
        error.InvalidCacheRootContainer,
        error.InvalidCacheSelector,
        error.InvalidCachedPayload,
        error.InvalidV2CacheContainer,
        error.InvalidQuarantine,
        error.QuarantineEvidenceMismatch,
        error.InvalidGzip,
        error.InvalidTarChecksum,
        error.InvalidTarNumber,
        error.InvalidZipDeflate,
        error.InvalidZipDirectory,
        error.InventoryByteCountMismatch,
        error.InterruptedStagePresent,
        error.MalformedZipExtraField,
        error.MultiDiskZip,
        error.OverlappingZipRange,
        error.OwnerOnlyAclVerificationFailed,
        error.PathCollision,
        error.TooManyArchiveEntries,
        error.TooManyCacheGenerations,
        error.TooManyZipExtraFields,
        error.TrailingGzipData,
        error.TrailingTarData,
        error.TruncatedGzip,
        error.TruncatedTar,
        error.TruncatedZip,
        error.UnapprovedArchiveMember,
        error.UnapprovedPath,
        error.UnexpectedArchiveRoot,
        error.UnexpectedEmptyDirectory,
        error.UnknownZipExtraField,
        error.UnreferencedZipLocalData,
        error.UnsafeArchivePath,
        error.UnsafeGnuLongName,
        error.UnsafePaxMetadata,
        error.UnsupportedTarEntry,
        error.UnsupportedZipFlags,
        error.UnsupportedZipMethod,
        error.Zip64Unsupported,
        error.ZipCentralDirectoryMismatch,
        error.ZipCommentOrTrailingData,
        error.ZipCrcMismatch,
        error.ZipDirectoryAttributeMismatch,
        error.ZipExtraFieldMismatch,
        error.ZipHeaderMismatch,
        error.ZipInventoryMismatch,
        error.ZipLinkOrSpecialEntry,
        error.ZipNameMismatch,
        error.ZipReparsePoint,
        error.ZipSizeMismatch,
        => .invalid,
        else => .operational,
    };
}

fn cacheProbeStateFromValidation(validation: anyerror!void) !CacheProbeState {
    validation catch |err| switch (classifyCacheValidationError(err)) {
        .invalid => return .invalid,
        .operational => return err,
    };
    return .valid;
}

const cache_remediation_line =
    "dependency cache is missing or invalid; run `zig build deps-fetch --summary all`\n";

fn shouldReportCacheRemediation(mode: Mode, err: anyerror) bool {
    const read_only = switch (mode) {
        .audit, .export_ucd, .export_zigwin32, .export_attestation_inputs => true,
        .bootstrap, .all => false,
    };
    return read_only and classifyCacheValidationError(err) == .invalid;
}

fn reportCacheAccessError(mode: Mode, err: anyerror) anyerror {
    if (!shouldReportCacheRemediation(mode, err)) return err;
    std.debug.print(cache_remediation_line, .{});
    return error.DependencyCacheUnavailable;
}

pub fn reportFixtureCacheError(operation: FixtureOperation, err: anyerror) anyerror {
    return reportCacheAccessError(switch (operation) {
        .bootstrap => .bootstrap,
        .fetch => .all,
        .audit => .audit,
    }, err);
}

const V2ArtifactStore = struct {
    v2: std.Io.Dir,
    artifact: std.Io.Dir,
    generations: std.Io.Dir,

    fn close(store: *V2ArtifactStore, io: std.Io) void {
        store.generations.close(io);
        store.artifact.close(io);
        store.v2.close(io);
        store.* = undefined;
    }
};

const CacheLayout = enum {
    legacy,
    generation,
};

const SelectedCacheDirectory = struct {
    dir: std.Io.Dir,
    layout: CacheLayout,
    generation_name: ?[deps.cache_generation_name_bytes]u8 = null,

    fn close(selected: *SelectedCacheDirectory, io: std.Io) void {
        selected.dir.close(io);
        selected.* = undefined;
    }
};

const CacheProbe = enum {
    valid,
    missing,
    invalid,
};

const ArchiveSource = union(enum) {
    http: *std.http.Client,
    transport: DownloadTransport,
    bytes: []const u8,
};

const production_download_timeout_ms: i64 = 10 * 60 * 1000;

const DownloadTransport = struct {
    context: *anyopaque,
    open_request: *const fn (
        *anyopaque,
        std.mem.Allocator,
        std.Io,
        []const u8,
    ) anyerror!DownloadRequest,
    timeout_ms: i64 = production_download_timeout_ms,
};

const DownloadRequest = struct {
    context: *anyopaque,
    receive_head: *const fn (*anyopaque) anyerror!DownloadResponse,
    deinit_request: *const fn (*anyopaque) void,

    fn deinit(request: DownloadRequest) void {
        request.deinit_request(request.context);
    }
};

const DownloadResponse = struct {
    context: *anyopaque,
    status: std.http.Status,
    location: ?[]const u8,
    content_length: ?u64,
    content_encoding: std.http.ContentEncoding,
    read_body: *const fn (*anyopaque, []u8) anyerror!usize,
    body_error: *const fn (*anyopaque) ?anyerror,
};

const RealHttpRequest = struct {
    allocator: std.mem.Allocator,
    request: std.http.Client.Request,
    response: ?std.http.Client.Response = null,
    body_reader: ?*std.Io.Reader = null,
    transfer_buffer: [64 * 1024]u8 = undefined,
};

const DownloadDeadlineOutcome = union(enum) {
    operation: anyerror!void,
    timeout: anyerror!void,
};

pub const FixtureEvent = enum {
    lock_acquired,
    stage_created_pinned,
    source_opened,
    archive_materialized,
    payload_materialization_started,
    payload_materialized,
    stage_validated,
    stage_children_frozen,
    stage_frozen,
    stage_pins_released,
    generation_published,
    generation_quarantined,
    quarantine_evidence_started,
    selector_published,
};

pub const AcquireObserver = struct {
    context: ?*anyopaque = null,
    callback: ?*const fn (?*anyopaque, FixtureEvent) anyerror!void = null,
    // Test-only seam used by the process fixture to exercise publication and
    // post-publication fault injection even when the requested artifact is
    // already valid. Production callers leave this false; no CLI flag or
    // dependency path can enable it.
    force_rebuild: bool = false,

    fn notify(observer: AcquireObserver, event: FixtureEvent) !void {
        if (observer.callback) |callback| try callback(observer.context, event);
    }
};

pub const FixtureOperation = enum {
    bootstrap,
    fetch,
    audit,
};

/// Deterministic process-level test seam. The caller supplies an already
/// existing absolute root and verified fixture bytes, so this exercises the
/// production lock, stage, validation, and publication paths without exposing
/// a production CLI mode or touching the real dependency cache.
pub fn runFixtureCacheOperation(
    allocator: std.mem.Allocator,
    io: std.Io,
    absolute_cache_root: []const u8,
    artifact: deps.Artifact,
    archive_bytes: []const u8,
    operation: FixtureOperation,
    observer: AcquireObserver,
) !void {
    if (!std.Io.Dir.path.isAbsolute(absolute_cache_root)) return error.InvalidCacheRoot;
    var cache_root = try std.Io.Dir.openDirAbsolute(io, absolute_cache_root, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer cache_root.close(io);
    try requireOrdinaryDirectory(io, cache_root);

    switch (operation) {
        .fetch, .bootstrap => {
            try ensureOwnerOnlyAcl(allocator, io, cache_root);
            var lock = try acquireCacheLock(allocator, io, cache_root);
            defer lock.close(io);
            try observer.notify(.lock_acquired);
            try recoverFrozenInterruptedStages(allocator, io, cache_root, &.{artifact}, observer);
            try handleInterruptedStages(allocator, io, cache_root, .clean_safe);
            if (operation == .bootstrap) {
                try acquireBootstrapArtifact(allocator, io, .{ .bytes = archive_bytes }, cache_root, &.{artifact}, artifact, true, observer);
                return;
            }
            try cleanInvalidInactiveGenerations(allocator, io, cache_root, &.{artifact}, observer);
            try validateCacheSchema(
                allocator,
                io,
                cache_root,
                &.{artifact},
                true,
                .secure_and_verify,
            );
            try acquireArtifact(
                allocator,
                io,
                .{ .bytes = archive_bytes },
                cache_root,
                artifact,
                collision.foldNfd,
                observer,
            );
            try cleanInvalidInactiveGenerations(allocator, io, cache_root, &.{artifact}, observer);
        },
        .audit => {
            try verifyOwnerOnlyAcl(cache_root.handle, .directory);
            var lock = try acquireReadOnlyCacheLock(io, cache_root);
            defer lock.close(io);
            try observer.notify(.lock_acquired);
            try handleInterruptedStages(allocator, io, cache_root, .reject);
            try validateCacheSchema(
                allocator,
                io,
                cache_root,
                &.{artifact},
                true,
                .verify_only,
            );
            try validateCachedArtifact(
                allocator,
                io,
                cache_root,
                artifact,
                collision.foldNfd,
            );
        },
    }
}

fn openSelectedCacheDirectory(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    artifact_id: []const u8,
) !SelectedCacheDirectory {
    try validateCacheComponent(artifact_id);
    var v2 = cache_root.openDir(io, deps.cache_v2_directory, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => return openLegacyCacheDirectory(io, cache_root, artifact_id),
        else => |e| return e,
    };
    defer v2.close(io);
    try requireOrdinaryDirectory(io, v2);
    try verifyOwnerOnlyAcl(v2.handle, .directory);

    var artifact_store = v2.openDir(io, artifact_id, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => return openLegacyCacheDirectory(io, cache_root, artifact_id),
        else => |e| return e,
    };
    defer artifact_store.close(io);
    try requireOrdinaryDirectory(io, artifact_store);
    try verifyOwnerOnlyAcl(artifact_store.handle, .directory);

    const generation_name = readCurrentSelector(allocator, io, artifact_store) catch |err| switch (err) {
        error.FileNotFound => return error.InvalidCacheSelector,
        else => |e| return e,
    };
    defer allocator.free(generation_name);
    var generation_copy: [deps.cache_generation_name_bytes]u8 = undefined;
    @memcpy(&generation_copy, generation_name);

    var generations = artifact_store.openDir(io, deps.cache_generations_directory, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.InvalidCacheSelector,
        else => |e| return e,
    };
    defer generations.close(io);
    try requireOrdinaryDirectory(io, generations);
    try verifyOwnerOnlyAcl(generations.handle, .directory);
    var generation = generations.openDir(io, generation_name, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.InvalidCacheSelector,
        else => |e| return e,
    };
    errdefer generation.close(io);
    try requireOrdinaryDirectory(io, generation);
    try verifyOwnerOnlyAcl(generation.handle, .directory);
    return .{
        .dir = generation,
        .layout = .generation,
        .generation_name = generation_copy,
    };
}

fn openLegacyCacheDirectory(
    io: std.Io,
    cache_root: std.Io.Dir,
    artifact_id: []const u8,
) !SelectedCacheDirectory {
    var legacy = try cache_root.openDir(io, artifact_id, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    errdefer legacy.close(io);
    try requireOrdinaryDirectory(io, legacy);
    try verifyOwnerOnlyAcl(legacy.handle, .directory);
    return .{ .dir = legacy, .layout = .legacy };
}

fn openOrCreateV2ArtifactStore(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    artifact_id: []const u8,
) !V2ArtifactStore {
    try validateCacheComponent(artifact_id);
    var v2 = try openOrCreateChildDirectory(allocator, io, cache_root, deps.cache_v2_directory);
    errdefer v2.close(io);
    var artifact = try openOrCreateChildDirectory(allocator, io, v2, artifact_id);
    errdefer artifact.close(io);
    const generations = try openOrCreateChildDirectory(
        allocator,
        io,
        artifact,
        deps.cache_generations_directory,
    );
    return .{ .v2 = v2, .artifact = artifact, .generations = generations };
}

fn openOrCreateChildDirectory(
    allocator: std.mem.Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    name: []const u8,
) !std.Io.Dir {
    try validateCacheComponent(name);
    parent.createDir(io, name, privateDirPermissions()) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    };
    var child = try parent.openDir(io, name, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    errdefer child.close(io);
    try requireOrdinaryDirectory(io, child);
    try ensureOwnerOnlyAcl(allocator, io, child);
    return child;
}

fn validateCacheComponent(name: []const u8) !void {
    if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) {
        return error.InvalidCachePath;
    }
    for (name) |byte| {
        if (byte == '/' or byte == '\\' or byte == ':' or byte == 0) {
            return error.InvalidCachePath;
        }
    }
}

fn publishStagedGeneration(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    generations: std.Io.Dir,
    staged: std.Io.Dir,
    stage_name: []const u8,
    generation_name: []const u8,
) !void {
    try deps.validateCacheGenerationName(generation_name);
    try requireOrdinaryDirectory(io, staged);
    try validateTreeNoReparse(allocator, io, staged);
    if (builtin.os.tag == .windows) {
        try renameDirectoryHandleWindows(staged.handle, generations, generation_name);
    } else {
        try cache_root.renamePreserve(stage_name, generations, generation_name, io);
    }
}

/// Creates the random stage and returns the same kernel object that remains
/// held through validation and publication. On Windows the protected DACL is
/// supplied to NtCreateFile as part of creation, and DELETE sharing is denied,
/// so no same-user process can replace or rename the stage name while this
/// handle is live.
fn createPinnedStageDirectory(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    stage_name: []const u8,
) !std.Io.Dir {
    try validateCacheComponent(stage_name);
    if (builtin.os.tag != .windows) {
        try cache_root.createDir(io, stage_name, privateDirPermissions());
        var stage = try cache_root.openDir(io, stage_name, .{
            .iterate = true,
            .follow_symlinks = false,
        });
        errdefer stage.close(io);
        try requireOrdinaryDirectory(io, stage);
        try applyOwnerOnlyAcl(allocator, io, stage);
        return stage;
    }

    const windows = std.os.windows;
    const name_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, stage_name);
    defer allocator.free(name_w);
    var descriptor: ?*anyopaque = null;
    if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
        std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;OICI;FA;;;OW)"),
        1,
        &descriptor,
        null,
    ) == 0 or descriptor == null) return error.OwnerOnlyAclFailed;
    defer _ = LocalFree(descriptor);

    var object_name = windows.UNICODE_STRING.init(name_w[0..stage_name.len]);
    const attributes: windows.OBJECT.ATTRIBUTES = .{
        .RootDirectory = cache_root.handle,
        .Attributes = .{ .CASE_INSENSITIVE = true },
        .ObjectName = &object_name,
        .SecurityDescriptor = descriptor,
        .SecurityQualityOfService = null,
    };
    var handle: windows.HANDLE = undefined;
    var io_status: windows.IO_STATUS_BLOCK = undefined;
    const status = windows.ntdll.NtCreateFile(
        &handle,
        .{
            .SPECIFIC = .{ .FILE_DIRECTORY = .{
                .LIST = true,
                .ADD_FILE = true,
                .ADD_SUBDIRECTORY = true,
                .READ_EA = true,
                .WRITE_EA = true,
                .TRAVERSE = true,
                .DELETE_CHILD = true,
                .READ_ATTRIBUTES = true,
                .WRITE_ATTRIBUTES = true,
            } },
            .STANDARD = .{
                .RIGHTS = .{
                    .DELETE = true,
                    .READ_CONTROL = true,
                    .WRITE_DAC = true,
                },
                .SYNCHRONIZE = true,
            },
        },
        &attributes,
        &io_status,
        null,
        .{ .NORMAL = true },
        .{ .READ = true, .WRITE = false, .DELETE = false },
        .CREATE,
        .{
            .DIRECTORY_FILE = true,
            .IO = .SYNCHRONOUS_NONALERT,
            .OPEN_FOR_BACKUP_INTENT = true,
            .OPEN_REPARSE_POINT = false,
        },
        null,
        0,
    );
    switch (status) {
        .SUCCESS => {},
        .OBJECT_NAME_COLLISION => return error.PathAlreadyExists,
        .OBJECT_NAME_INVALID => return error.BadPathName,
        .OBJECT_NAME_NOT_FOUND, .OBJECT_PATH_NOT_FOUND => return error.FileNotFound,
        .ACCESS_DENIED => return error.AccessDenied,
        .DISK_FULL => return error.NoSpaceLeft,
        else => return windows.unexpectedStatus(status),
    }
    var stage: std.Io.Dir = .{ .handle = handle };
    errdefer stage.close(io);
    try requireOrdinaryDirectory(io, stage);
    try verifyOwnerOnlyAcl(stage.handle, .directory);
    return stage;
}

const PinnedStageEntry = struct {
    handle: std.os.windows.HANDLE,
    target: AclTarget,
};

const FrozenStageTree = struct {
    allocator: std.mem.Allocator,
    // std.Io.Dir.Handle is a POSIX fd on Linux but a Win32 HANDLE on
    // Windows. Keep the Windows-only pin handle optional so the portable
    // build never coerces an i32 fd into a pointer-shaped HANDLE.
    root_handle: ?std.os.windows.HANDLE,
    entries: std.ArrayList(PinnedStageEntry) = .empty,

    fn restoreFull(tree: *FrozenStageTree) !void {
        if (comptime builtin.os.tag != .windows) return;
        const root_handle = tree.root_handle orelse return error.OwnerOnlyAclFailed;
        try setOwnerRightsAclByHandle(root_handle, .directory, .full);
        try verifyOwnerOnlyAclExact(root_handle, .directory, file_all_access);
        for (tree.entries.items) |entry| {
            try setOwnerRightsAclByHandle(entry.handle, entry.target, .full);
            try verifyOwnerOnlyAclExact(entry.handle, entry.target, file_all_access);
        }
    }

    fn deinit(tree: *FrozenStageTree) void {
        if (comptime builtin.os.tag == .windows) {
            for (tree.entries.items) |entry| std.os.windows.CloseHandle(entry.handle);
        }
        tree.entries.deinit(tree.allocator);
        tree.* = undefined;
    }
};

const OwnerRightsAclMode = enum { full, read_execute };

/// Converts the validated stage into an immutable transaction object. The
/// stage root was created with no WRITE/DELETE sharing; each descendant is now
/// opened with the same exclusion, its exact OWNER RIGHTS DACL is reduced to
/// read/execute. Child handles close for native rename; their ACLs remain RX.
/// A pre-existing writer makes the pin fail with a sharing violation. A race
/// before the last pin is detected by the caller's final digest validation.
fn freezeAndPinStagedTree(
    allocator: std.mem.Allocator,
    io: std.Io,
    stage: std.Io.Dir,
    observer: AcquireObserver,
) !FrozenStageTree {
    var frozen: FrozenStageTree = .{
        .allocator = allocator,
        .root_handle = windowsHandleOrNull(stage),
    };
    errdefer {
        frozen.restoreFull() catch {};
        frozen.deinit();
    }
    if (builtin.os.tag != .windows) return frozen;

    // Keep the already-pinned construction handle's full DACL while walking
    // so each child can be opened with WRITE_DAC. Its no-write/no-delete share
    // mode already blocks new mutation handles and name replacement; reduce
    // the root only after every descendant has its own pinned handle.
    var walker = try stage.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        const target: AclTarget = switch (entry.kind) {
            .directory => .directory,
            .file => .file,
            else => return error.InvalidV2CacheContainer,
        };
        const handle = try openPinnedStageChildWindows(
            allocator,
            stage,
            entry.path,
            target,
        );
        frozen.entries.append(allocator, .{ .handle = handle, .target = target }) catch |err| {
            std.os.windows.CloseHandle(handle);
            return err;
        };
    }
    // Pin every descendant while the stage still has its full construction
    // ACL. Reducing a parent directory before opening a nested child can make
    // Windows reject the child's DELETE/WRITE_DAC open as ACCESS_DENIED; the
    // two-phase order keeps allocation failures typed as OutOfMemory and
    // avoids a partially frozen traversal.
    for (frozen.entries.items) |entry| {
        try setOwnerRightsAclByHandle(entry.handle, entry.target, .read_execute);
        try verifyOwnerOnlyAclExact(entry.handle, entry.target, owner_rights_read_execute_access);
    }
    try observer.notify(.stage_children_frozen);
    // The root's already-granted DELETE right survives this DACL reduction,
    // allowing native rename without thawing the root or any descendant.
    const root_handle = frozen.root_handle orelse return error.OwnerOnlyAclFailed;
    try setOwnerRightsAclByHandle(root_handle, .directory, .read_execute);
    try verifyOwnerOnlyAclExact(
        root_handle,
        .directory,
        owner_rights_read_execute_access,
    );
    return frozen;
}

fn windowsHandleOrNull(dir: std.Io.Dir) ?std.os.windows.HANDLE {
    if (comptime builtin.os.tag == .windows) return dir.handle;
    return null;
}

fn openPinnedStageChildWindows(
    allocator: std.mem.Allocator,
    stage: std.Io.Dir,
    relative_path: []const u8,
    target: AclTarget,
) !std.os.windows.HANDLE {
    const windows = std.os.windows;
    const path_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, relative_path);
    defer allocator.free(path_w);
    var object_name = windows.UNICODE_STRING.init(path_w[0..path_w.len]);
    const attributes: windows.OBJECT.ATTRIBUTES = .{
        .RootDirectory = stage.handle,
        .Attributes = .{ .CASE_INSENSITIVE = true },
        .ObjectName = &object_name,
        .SecurityDescriptor = null,
        .SecurityQualityOfService = null,
    };
    var handle: windows.HANDLE = undefined;
    var io_status: windows.IO_STATUS_BLOCK = undefined;
    const desired: windows.ACCESS_MASK = switch (target) {
        .directory => .{
            .SPECIFIC = .{ .FILE_DIRECTORY = .{
                .LIST = true,
                .READ_EA = true,
                .TRAVERSE = true,
                .READ_ATTRIBUTES = true,
            } },
            .STANDARD = .{
                .RIGHTS = .{ .DELETE = true, .READ_CONTROL = true, .WRITE_DAC = true },
                .SYNCHRONIZE = true,
            },
        },
        .file => .{
            .SPECIFIC = .{ .FILE = .{
                .READ_DATA = true,
                .READ_EA = true,
                .READ_ATTRIBUTES = true,
            } },
            .STANDARD = .{
                .RIGHTS = .{ .DELETE = true, .READ_CONTROL = true, .WRITE_DAC = true },
                .SYNCHRONIZE = true,
            },
        },
    };
    const status = windows.ntdll.NtCreateFile(
        &handle,
        desired,
        &attributes,
        &io_status,
        null,
        .{ .NORMAL = true },
        // Child pins must permit the enclosing directory rename. WRITE sharing
        // remains denied, so a new writer cannot obtain a mutation handle while
        // this pin lives; ACL reduction happens after every descendant is held.
        .{ .READ = true, .WRITE = false, .DELETE = true },
        .OPEN,
        .{
            .DIRECTORY_FILE = target == .directory,
            .NON_DIRECTORY_FILE = target == .file,
            .IO = .SYNCHRONOUS_NONALERT,
            .OPEN_REPARSE_POINT = true,
        },
        null,
        0,
    );
    switch (status) {
        .SUCCESS => return handle,
        .ACCESS_DENIED, .SHARING_VIOLATION => {
            return error.StageMutationConflict;
        },
        .OBJECT_NAME_NOT_FOUND, .OBJECT_PATH_NOT_FOUND => return error.CacheIdentityChanged,
        else => return windows.unexpectedStatus(status),
    }
}

fn renameDirectoryHandleWindows(
    stage_handle: std.os.windows.HANDLE,
    generations: std.Io.Dir,
    generation_name: []const u8,
) !void {
    const windows = std.os.windows;
    try validateCacheComponent(generation_name);
    if (generation_name.len > 160) return error.InvalidCachePath;
    var name_w: [160]u16 = undefined;
    const name_len = try std.unicode.wtf8ToWtf16Le(&name_w, generation_name);
    var rename_info: windows.FILE.RENAME_INFORMATION = .init(.{
        .Flags = .{},
        .RootDirectory = generations.handle,
        .FileName = name_w[0..name_len],
    });
    const buffer = rename_info.toBuffer();
    var io_status: windows.IO_STATUS_BLOCK = undefined;
    const status = windows.ntdll.NtSetInformationFile(
        stage_handle,
        &io_status,
        buffer.ptr,
        @intCast(buffer.len),
        .Rename,
    );
    switch (status) {
        .SUCCESS => {},
        .ACCESS_DENIED, .SHARING_VIOLATION => {
            return error.AccessDenied;
        },
        .OBJECT_NAME_COLLISION => return error.PathAlreadyExists,
        .OBJECT_NAME_NOT_FOUND, .OBJECT_PATH_NOT_FOUND => return error.FileNotFound,
        .NOT_SAME_DEVICE => return error.CrossDevice,
        .DIRECTORY_NOT_EMPTY => return error.DirNotEmpty,
        else => return windows.unexpectedStatus(status),
    }
}

fn writeCurrentSelector(
    allocator: std.mem.Allocator,
    io: std.Io,
    artifact_store: std.Io.Dir,
    generation_name: []const u8,
    temporary_name: []const u8,
) !void {
    try validateCacheComponent(temporary_name);
    var selector_buffer: [deps.cache_selector_max_bytes]u8 = undefined;
    const selector = try deps.formatCacheSelector(&selector_buffer, generation_name);
    var file = try artifact_store.createFile(io, temporary_name, .{
        .read = true,
        .exclusive = true,
        .permissions = privateFilePermissions(),
        .resolve_beneath = true,
    });
    var file_open = true;
    defer if (file_open) file.close(io);
    errdefer artifact_store.deleteFile(io, temporary_name) catch {};
    var writer_buffer: [128]u8 = undefined;
    var writer = file.writerStreaming(io, &writer_buffer);
    try writer.interface.writeAll(selector);
    try writer.interface.flush();
    try file.sync(io);
    if (builtin.os.tag == .windows) {
        try setAclFromSddl(
            allocator,
            io,
            artifact_store,
            temporary_name,
            std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;;FA;;;OW)"),
        );
        try verifyOwnerOnlyAcl(file.handle, .file);
    }
    file.close(io);
    file_open = false;
    try artifact_store.rename(temporary_name, artifact_store, deps.cache_selector_file, io);

    const selected = try readCurrentSelector(allocator, io, artifact_store);
    defer allocator.free(selected);
    if (!std.mem.eql(u8, selected, generation_name)) return error.CacheSelectorIdentityChanged;
}

fn readCurrentSelector(
    allocator: std.mem.Allocator,
    io: std.Io,
    artifact_store: std.Io.Dir,
) ![]u8 {
    var verification = try artifact_store.openFile(io, deps.cache_selector_file, .{
        .path_only = true,
        .follow_symlinks = false,
        .resolve_beneath = true,
    });
    defer verification.close(io);
    const stat = try verification.stat(io);
    if (stat.kind != .file or stat.size != deps.cache_selector_max_bytes) {
        return error.InvalidCacheSelector;
    }
    try verifyOwnerOnlyAcl(verification.handle, .file);
    const bytes = try readVerifiedFileAlloc(
        allocator,
        io,
        artifact_store,
        deps.cache_selector_file,
        deps.cache_selector_max_bytes,
    );
    defer allocator.free(bytes);
    return allocator.dupe(u8, try deps.parseCacheSelector(bytes));
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.InvalidArguments;
    const mode: Mode = if (std.mem.eql(u8, args[1], "bootstrap"))
        .bootstrap
    else if (std.mem.eql(u8, args[1], "all"))
        .all
    else if (std.mem.eql(u8, args[1], "audit"))
        .audit
    else if (std.mem.eql(u8, args[1], "export-ucd"))
        .export_ucd
    else if (std.mem.eql(u8, args[1], "export-zigwin32"))
        .export_zigwin32
    else if (std.mem.eql(u8, args[1], "export-attestation-inputs"))
        .export_attestation_inputs
    else
        return error.InvalidArguments;
    const expected_args: usize = switch (mode) {
        .export_ucd, .export_zigwin32, .export_attestation_inputs => 4,
        else => 3,
    };
    if (args.len != expected_args) return error.InvalidArguments;

    try validateCacheRootPath(args[2]);
    var manifest = try deps.parseLockedManifest(allocator);
    defer manifest.deinit();

    const policy = policyForMode(mode);
    var cache_root = openCacheRoot(
        init.io,
        std.Io.Dir.cwd(),
        args[2],
        policy.cache_root,
    ) catch |err| return reportCacheAccessError(mode, err);
    defer cache_root.close(init.io);
    requireOrdinaryDirectory(init.io, cache_root) catch |err|
        return reportCacheAccessError(mode, err);
    switch (policy.cache_acl) {
        .secure_and_verify => ensureOwnerOnlyAcl(allocator, init.io, cache_root) catch |err|
            return reportCacheAccessError(mode, err),
        .verify_only => verifyOwnerOnlyAcl(cache_root.handle, .directory) catch |err|
            return reportCacheAccessError(mode, err),
    }

    var lock = (switch (policy.cache_lock) {
        .exclusive_create => acquireCacheLock(allocator, init.io, cache_root),
        .shared_existing => acquireReadOnlyCacheLock(init.io, cache_root),
    }) catch |err| return reportCacheAccessError(mode, err);
    defer lock.close(init.io);
    if (mode == .bootstrap or mode == .all) {
        recoverFrozenInterruptedStages(allocator, init.io, cache_root, manifest.value.artifacts, .{}) catch |err|
            return reportCacheAccessError(mode, err);
    }
    handleInterruptedStages(
        allocator,
        init.io,
        cache_root,
        policy.interrupted_stages,
    ) catch |err| return reportCacheAccessError(mode, err);
    if (mode == .all) {
        cleanInvalidInactiveGenerations(
            allocator,
            init.io,
            cache_root,
            manifest.value.artifacts,
            .{},
        ) catch |err| return reportCacheAccessError(mode, err);
    }
    // Bootstrap performs its reconciliation before schema validation in the
    // shared acquisition path below; export and audit remain strictly read-only.
    if (mode != .bootstrap) {
        validateCacheSchema(
            allocator,
            init.io,
            cache_root,
            manifest.value.artifacts,
            false,
            policy.cache_acl,
        ) catch |err| return reportCacheAccessError(mode, err);
    }

    switch (mode) {
        .bootstrap => {
            var client: std.http.Client = .{ .allocator = allocator, .io = init.io };
            defer client.deinit();
            const artifact = deps.findArtifact(manifest.value, "unicode-ucd") orelse
                return error.MissingUnicodeArtifact;
            try acquireBootstrapArtifact(
                allocator,
                init.io,
                .{ .http = &client },
                cache_root,
                manifest.value.artifacts,
                artifact,
                false,
                .{},
            );
        },
        .all => {
            var client: std.http.Client = .{ .allocator = allocator, .io = init.io };
            defer client.deinit();
            for (manifest.value.artifacts) |artifact| {
                if (artifact.fetch_policy == .operator_provisioned or
                    std.mem.eql(u8, artifact.id, "unicode-ucd"))
                {
                    continue;
                }
                try acquireArtifact(
                    allocator,
                    init.io,
                    .{ .http = &client },
                    cache_root,
                    artifact,
                    collision.foldNfd,
                    .{},
                );
                try cleanInvalidInactiveGenerations(
                    allocator,
                    init.io,
                    cache_root,
                    manifest.value.artifacts,
                    .{},
                );
            }
        },
        .audit => {
            for (manifest.value.artifacts) |artifact| {
                if (artifact.fetch_policy == .operator_provisioned) continue;
                validateCachedArtifact(
                    allocator,
                    init.io,
                    cache_root,
                    artifact,
                    if (std.mem.eql(u8, artifact.id, "unicode-ucd"))
                        deps.asciiCollisionFold
                    else
                        collision.foldNfd,
                ) catch |err| return reportCacheAccessError(mode, err);
            }
        },
        .export_ucd => {
            const artifact = deps.findArtifact(manifest.value, "unicode-ucd") orelse
                return error.MissingUnicodeArtifact;
            try exportUcdInputs(
                allocator,
                init.io,
                cache_root,
                artifact,
                args[3],
            );
        },
        .export_zigwin32 => {
            const artifact = deps.findArtifact(manifest.value, "zigwin32") orelse
                return error.MissingZigwin32Artifact;
            try exportZigwin32(
                allocator,
                init.io,
                cache_root,
                artifact,
                args[3],
            );
        },
        .export_attestation_inputs => {
            const github = deps.findArtifact(manifest.value, "github-cli") orelse
                return error.MissingGithubCliArtifact;
            const pdfium = deps.findArtifact(manifest.value, "pdfium-reference") orelse
                return error.MissingPdfiumReferenceArtifact;
            try exportAttestationInputs(
                allocator,
                init.io,
                cache_root,
                github,
                pdfium,
                args[3],
            );
        },
    }
}

/// Called with the exclusive cache lock held. Bootstrap must reconcile stale
/// retained inputs before schema/export validation, and reconcile the replaced
/// selection afterward. Unsafe metadata continues to fail closed.
fn acquireBootstrapArtifact(
    allocator: std.mem.Allocator,
    io: std.Io,
    source: ArchiveSource,
    cache_root: std.Io.Dir,
    artifacts: []const deps.Artifact,
    artifact: deps.Artifact,
    allow_fixture_sentinel: bool,
    observer: AcquireObserver,
) !void {
    try cleanInvalidInactiveGenerations(allocator, io, cache_root, artifacts, observer);
    try validateCacheSchema(allocator, io, cache_root, artifacts, allow_fixture_sentinel, .secure_and_verify);
    try acquireArtifact(allocator, io, source, cache_root, artifact, deps.asciiCollisionFold, observer);
    try cleanInvalidInactiveGenerations(allocator, io, cache_root, artifacts, observer);
}

fn acquireArtifact(
    allocator: std.mem.Allocator,
    io: std.Io,
    source: ArchiveSource,
    cache_root: std.Io.Dir,
    artifact: deps.Artifact,
    fold: deps.CollisionFoldFn,
    observer: AcquireObserver,
) !void {
    if (!observer.force_rebuild) {
        switch (try probeCachedArtifact(allocator, io, cache_root, artifact, fold)) {
            .valid => {
                std.debug.print("deps-fetch cached {s}@{s}\n", .{ artifact.id, artifact.version });
                return;
            },
            .missing => std.debug.print("deps-fetch cache-miss {s} reason=missing\n", .{artifact.id}),
            .invalid => std.debug.print("deps-fetch cache-miss {s} reason=invalid\n", .{artifact.id}),
        }
    } else {
        std.debug.print("deps-fetch test-fixture force-rebuild {s}@{s}\n", .{ artifact.id, artifact.version });
    }
    var random_bytes: [12]u8 = undefined;
    io.random(&random_bytes);
    const random_hex = std.fmt.bytesToHex(random_bytes, .lower);
    var stage_name_buffer: [160]u8 = undefined;
    const stage_name = try std.fmt.bufPrint(
        &stage_name_buffer,
        ".stage-{s}-{s}",
        .{ artifact.id, random_hex },
    );
    var stage = try createPinnedStageDirectory(allocator, io, cache_root, stage_name);
    var stage_open = true;
    defer if (stage_open) stage.close(io);
    var stage_at_root = true;
    errdefer {
        if (stage_open) {
            stage.close(io);
            stage_open = false;
        }
        if (stage_at_root) cache_root.deleteTree(io, stage_name) catch {};
    }
    try observer.notify(.stage_created_pinned);

    try observer.notify(.source_opened);
    try downloadArtifact(allocator, io, source, artifact, stage, "archive.bin");
    try observer.notify(.archive_materialized);
    const archive = try readVerifiedFileAlloc(
        allocator,
        io,
        stage,
        "archive.bin",
        artifact.download_limit_bytes,
    );
    defer allocator.free(archive);
    var verifier = try deps.DownloadVerifier.init(artifact, archive.len);
    try verifier.feed(archive);
    try verifier.finish();
    if (!verifier.mayActivate()) return error.DownloadIncomplete;

    try stage.createDir(io, "payload", privateDirPermissions());
    var payload = stage.openDir(io, "payload", .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch |err| {
        return err;
    };
    var payload_open = true;
    defer if (payload_open) payload.close(io);
    try requireOrdinaryDirectory(io, payload);
    try observer.notify(.payload_materialization_started);
    const expected = try deps.materializeArtifact(
        allocator,
        io,
        artifact,
        archive,
        payload,
        fold,
    );
    try observer.notify(.payload_materialized);
    const actual = deps.hashMaterializedDirectory(
        allocator,
        io,
        payload,
        artifact.expanded_limit_bytes,
    ) catch |err| {
        return err;
    };
    if (expected.payload_files != actual.files or
        expected.payload_bytes != actual.bytes or
        !std.mem.eql(u8, &expected.payload_sha256, &actual.digest))
    {
        return error.MaterializedPayloadMismatch;
    }
    payload.close(io);
    payload_open = false;
    var archive_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(archive, &archive_digest, .{});
    try writeReceipt(io, stage, artifact, archive.len, archive_digest, expected);
    try validateCacheDirectory(allocator, io, stage, artifact, fold);
    try validateGenerationTreeNoReparse(allocator, io, stage, .secure_and_verify);
    try observer.notify(.stage_validated);
    // The observer is an adversarial test seam. Revalidate after it so any
    // same-user mutation of a child that was attempted at the boundary fails
    // closed before the selector can change.
    try validateCacheDirectory(allocator, io, stage, artifact, fold);
    try validateGenerationTreeNoReparse(allocator, io, stage, .secure_and_verify);
    var frozen = freezeAndPinStagedTree(allocator, io, stage, observer) catch |err| {
        return err;
    };
    var frozen_open = true;
    defer if (frozen_open) {
        frozen.restoreFull() catch {};
        frozen.deinit();
    };
    try observer.notify(.stage_frozen);
    // Every admitted object has an exact OWNER RIGHTS read/execute DACL and
    // a live handle denying WRITE sharing. Recheck before releasing children.
    try validateCacheDirectory(allocator, io, stage, artifact, fold);
    try validateGenerationTreeNoReparse(allocator, io, stage, .verify_only);

    var generation_name_buffer: [deps.cache_generation_name_bytes]u8 = undefined;
    const generation_name = try std.fmt.bufPrint(
        &generation_name_buffer,
        "g-{s}",
        .{random_hex},
    );
    var store = try openOrCreateV2ArtifactStore(allocator, io, cache_root, artifact.id);
    defer store.close(io);
    // Windows requires descendant handles to close before directory rename.
    // Keep every exact RX DACL intact: the root handle already holds DELETE,
    // and no new writer or OWNER RIGHTS WRITE_DAC open may enter this window.
    // The native rename uses fixed storage, so allocation failure cannot strand
    // the sealed stage between child release and generation publication.
    frozen.deinit();
    frozen_open = false;
    try observer.notify(.stage_pins_released);
    if (builtin.os.tag == .windows) {
        try renameDirectoryHandleWindows(stage.handle, store.generations, generation_name);
    } else {
        try publishStagedGeneration(allocator, io, cache_root, store.generations, stage, stage_name, generation_name);
    }
    stage_at_root = false;
    try observer.notify(.generation_published);
    // Validate through the held root identity after rename and before selector
    // activation. Sealed descendants need read access only, never WRITE_DAC.
    try validateGenerationTreeNoReparse(allocator, io, stage, .verify_only);
    try verifyTreeAclExact(allocator, io, stage, owner_rights_read_execute_access);
    try validateCacheDirectory(allocator, io, stage, artifact, fold);

    var selector_temp_buffer: [64]u8 = undefined;
    const selector_temp = try std.fmt.bufPrint(
        &selector_temp_buffer,
        ".stage-current-{s}",
        .{random_hex},
    );
    try writeCurrentSelector(
        allocator,
        io,
        store.artifact,
        generation_name,
        selector_temp,
    );
    try observer.notify(.selector_published);
    try validateCachedArtifact(allocator, io, cache_root, artifact, fold);
    stage.close(io);
    stage_open = false;
    std.debug.print("deps-fetch acquired {s}@{s}\n", .{ artifact.id, artifact.version });
}

fn probeCachedArtifact(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    artifact: deps.Artifact,
    fold: deps.CollisionFoldFn,
) !CacheProbe {
    var selected = openSelectedCacheDirectory(allocator, io, cache_root, artifact.id) catch |err| {
        if (err == error.FileNotFound) return .missing;
        return switch (classifyCacheValidationError(err)) {
            .invalid => .invalid,
            .operational => err,
        };
    };
    defer selected.close(io);
    return switch (try cacheProbeStateFromValidation(
        validateCacheDirectory(allocator, io, selected.dir, artifact, fold),
    )) {
        .valid => .valid,
        .invalid => .invalid,
    };
}

fn validateCachedArtifact(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    artifact: deps.Artifact,
    fold: deps.CollisionFoldFn,
) !void {
    var selected = try openSelectedCacheDirectory(allocator, io, cache_root, artifact.id);
    defer selected.close(io);
    try validateCacheDirectory(allocator, io, selected.dir, artifact, fold);
    // Content validation alone is not sufficient for the read-only audit
    // boundary. Walk the exact selected tree with reparse points disabled and
    // verify every object has the immutable OWNER RIGHTS ACL. This call is
    // deliberately verify-only: audit/export paths must never repair cache
    // metadata while proving a selected artifact is safe to consume.
    try validateGenerationTreeNoReparse(allocator, io, selected.dir, .verify_only);
}

fn exportZigwin32(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    artifact: deps.Artifact,
    output_path: []const u8,
) !void {
    const archive = readValidatedArchiveAlloc(
        allocator,
        io,
        cache_root,
        artifact,
        collision.foldNfd,
    ) catch |err| return reportCacheAccessError(.export_zigwin32, err);
    defer allocator.free(archive);
    var output = try openEmptyExportDirectory(io, cache_root, output_path);
    defer output.close(io);
    const actual = try materializeVerifiedPayload(
        allocator,
        io,
        artifact,
        archive,
        output,
        collision.foldNfd,
    );
    std.debug.print(
        "deps-fetch exported {s}@{s} files={d} bytes={d}\n",
        .{ artifact.id, artifact.version, actual.payload_files, actual.payload_bytes },
    );
}

fn exportUcdInputs(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    artifact: deps.Artifact,
    output_path: []const u8,
) !void {
    const archive = readValidatedArchiveAlloc(
        allocator,
        io,
        cache_root,
        artifact,
        deps.asciiCollisionFold,
    ) catch |err| return reportCacheAccessError(.export_ucd, err);
    defer allocator.free(archive);
    var output = try openEmptyExportDirectory(io, cache_root, output_path);
    defer output.close(io);
    var payload = try createExportDirectory(io, output, "payload");
    defer payload.close(io);
    const actual = try materializeVerifiedPayload(
        allocator,
        io,
        artifact,
        archive,
        payload,
        deps.asciiCollisionFold,
    );
    try writeArchiveBytes(io, artifact, output, "archive.bin", archive);
    try verifyExportedArchive(allocator, io, output, artifact, "archive.bin");
    std.debug.print(
        "deps-fetch exported {s}@{s} files={d} bytes={d} with-archive\n",
        .{ artifact.id, artifact.version, actual.payload_files, actual.payload_bytes },
    );
}

fn exportAttestationInputs(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    github: deps.Artifact,
    pdfium: deps.Artifact,
    output_path: []const u8,
) !void {
    const github_archive = readValidatedArchiveAlloc(
        allocator,
        io,
        cache_root,
        github,
        collision.foldNfd,
    ) catch |err| return reportCacheAccessError(.export_attestation_inputs, err);
    defer allocator.free(github_archive);
    const pdfium_archive = readValidatedArchiveAlloc(
        allocator,
        io,
        cache_root,
        pdfium,
        collision.foldNfd,
    ) catch |err| return reportCacheAccessError(.export_attestation_inputs, err);
    defer allocator.free(pdfium_archive);

    var output = try openEmptyExportDirectory(io, cache_root, output_path);
    defer output.close(io);
    var github_dir = try createExportDirectory(io, output, "github-cli");
    defer github_dir.close(io);
    var github_payload = try createExportDirectory(io, github_dir, "payload");
    defer github_payload.close(io);
    _ = try materializeVerifiedPayload(
        allocator,
        io,
        github,
        github_archive,
        github_payload,
        collision.foldNfd,
    );
    var pdfium_dir = try createExportDirectory(io, output, "pdfium-reference");
    defer pdfium_dir.close(io);
    try writeArchiveBytes(io, pdfium, pdfium_dir, "archive.bin", pdfium_archive);
    try verifyExportedArchive(allocator, io, pdfium_dir, pdfium, "archive.bin");
    std.debug.print(
        "deps-fetch exported attestation inputs {s}@{s} and {s}@{s}\n",
        .{ github.id, github.version, pdfium.id, pdfium.version },
    );
}

fn readValidatedArchiveAlloc(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    artifact: deps.Artifact,
    fold: deps.CollisionFoldFn,
) ![]u8 {
    var selected = try openSelectedCacheDirectory(allocator, io, cache_root, artifact.id);
    defer selected.close(io);
    try validateCacheDirectory(allocator, io, selected.dir, artifact, fold);
    const archive = try readVerifiedFileAlloc(
        allocator,
        io,
        selected.dir,
        "archive.bin",
        artifact.download_limit_bytes,
    );
    errdefer allocator.free(archive);
    var verifier = try deps.DownloadVerifier.init(artifact, archive.len);
    try verifier.feed(archive);
    try verifier.finish();
    if (!verifier.mayActivate()) return error.DownloadIncomplete;
    return archive;
}

fn openEmptyExportDirectory(
    io: std.Io,
    cache_root: std.Io.Dir,
    output_path: []const u8,
) !std.Io.Dir {
    var output = if (std.Io.Dir.path.isAbsolute(output_path))
        try std.Io.Dir.openDirAbsolute(io, output_path, .{
            .iterate = true,
            .follow_symlinks = false,
        })
    else
        try std.Io.Dir.cwd().openDir(io, output_path, .{
            .iterate = true,
            .follow_symlinks = false,
        });
    errdefer output.close(io);
    try requireOrdinaryDirectory(io, output);
    try ensureExportOutsideCache(io, cache_root, output);
    try requireEmptyDirectory(io, output);
    return output;
}

fn createExportDirectory(io: std.Io, parent: std.Io.Dir, name: []const u8) !std.Io.Dir {
    try validateCacheComponent(name);
    try parent.createDir(io, name, privateDirPermissions());
    var child = try parent.openDir(io, name, .{
        .iterate = true,
        .follow_symlinks = false,
    });
    errdefer child.close(io);
    try requireOrdinaryDirectory(io, child);
    try requireEmptyDirectory(io, child);
    return child;
}

fn materializeVerifiedPayload(
    allocator: std.mem.Allocator,
    io: std.Io,
    artifact: deps.Artifact,
    archive: []const u8,
    output: std.Io.Dir,
    fold: deps.CollisionFoldFn,
) !deps.MaterializedArchive {
    const expected = try deps.materializeArtifact(
        allocator,
        io,
        artifact,
        archive,
        output,
        fold,
    );
    const actual = try deps.hashMaterializedDirectory(
        allocator,
        io,
        output,
        artifact.expanded_limit_bytes,
    );
    if (actual.files != expected.payload_files or
        actual.bytes != expected.payload_bytes or
        !std.mem.eql(u8, &actual.digest, &expected.payload_sha256))
    {
        return error.ExportedPayloadMismatch;
    }
    return expected;
}

fn verifyExportedArchive(
    allocator: std.mem.Allocator,
    io: std.Io,
    output: std.Io.Dir,
    artifact: deps.Artifact,
    name: []const u8,
) !void {
    const bytes = try readVerifiedFileAlloc(
        allocator,
        io,
        output,
        name,
        artifact.download_limit_bytes,
    );
    defer allocator.free(bytes);
    var verifier = try deps.DownloadVerifier.init(artifact, bytes.len);
    try verifier.feed(bytes);
    try verifier.finish();
    if (!verifier.mayActivate()) return error.DownloadIncomplete;
}

fn requireEmptyDirectory(io: std.Io, dir: std.Io.Dir) !void {
    try requireOrdinaryDirectory(io, dir);
    var iterator = dir.iterate();
    if (try iterator.next(io) != null) return error.ExportDestinationNotEmpty;
}

fn ensureExportOutsideCache(
    io: std.Io,
    cache_root: std.Io.Dir,
    output: std.Io.Dir,
) !void {
    var cache_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var output_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cache_path = cache_path_buffer[0..try cache_root.realPath(io, &cache_path_buffer)];
    const output_path = output_path_buffer[0..try output.realPath(io, &output_path_buffer)];
    if (pathIsEqualOrDescendant(cache_path, output_path) or
        pathIsEqualOrDescendant(output_path, cache_path))
    {
        return error.ExportDestinationOverlapsCache;
    }
}

fn pathIsEqualOrDescendant(candidate_raw: []const u8, root_raw: []const u8) bool {
    const candidate = trimTrailingSeparators(candidate_raw);
    const root = trimTrailingSeparators(root_raw);
    if (candidate.len < root.len or !pathPrefixEqual(candidate[0..root.len], root)) {
        return false;
    }
    return candidate.len == root.len or isPathSeparator(candidate[root.len]);
}

fn trimTrailingSeparators(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 0 and isPathSeparator(path[end - 1])) end -= 1;
    return path[0..end];
}

fn pathPrefixEqual(actual: []const u8, expected: []const u8) bool {
    if (actual.len != expected.len) return false;
    for (actual, expected) |actual_byte, expected_byte| {
        const equal = if (builtin.os.tag == .windows)
            std.ascii.toLower(actual_byte) == std.ascii.toLower(expected_byte)
        else
            actual_byte == expected_byte;
        if (!equal) return false;
    }
    return true;
}

fn isPathSeparator(byte: u8) bool {
    return byte == '/' or (builtin.os.tag == .windows and byte == '\\');
}

fn validateCacheDirectory(
    allocator: std.mem.Allocator,
    io: std.Io,
    artifact_dir: std.Io.Dir,
    artifact: deps.Artifact,
    fold: deps.CollisionFoldFn,
) !void {
    try requireOrdinaryDirectory(io, artifact_dir);
    try validateCacheContainer(io, artifact_dir);
    const receipt_bytes = try readVerifiedFileAlloc(
        allocator,
        io,
        artifact_dir,
        ".complete.json",
        4096,
    );
    defer allocator.free(receipt_bytes);
    var receipt = try parseCacheReceipt(allocator, receipt_bytes);
    defer receipt.deinit();
    if (receipt.value.schema_version != cache_schema_version or
        !std.mem.eql(u8, receipt.value.artifact_id, artifact.id) or
        !std.mem.eql(u8, receipt.value.artifact_version, artifact.version) or
        !isLowerSha256(receipt.value.archive_sha256) or
        !isLowerSha256(receipt.value.payload_sha256))
    {
        return error.InvalidCacheReceipt;
    }

    const archive = try readVerifiedFileAlloc(
        allocator,
        io,
        artifact_dir,
        "archive.bin",
        artifact.download_limit_bytes,
    );
    defer allocator.free(archive);
    if (receipt.value.archive_bytes != archive.len) return error.InvalidCacheReceipt;
    deps.verifySha256(archive, receipt.value.archive_sha256) catch
        return error.InvalidCacheReceipt;
    var verifier = try deps.DownloadVerifier.init(artifact, archive.len);
    try verifier.feed(archive);
    try verifier.finish();
    const expected = try deps.materializeArtifact(
        allocator,
        io,
        artifact,
        archive,
        null,
        fold,
    );

    var payload = try artifact_dir.openDir(io, "payload", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer payload.close(io);
    try requireOrdinaryDirectory(io, payload);
    const actual = try deps.hashMaterializedDirectory(
        allocator,
        io,
        payload,
        artifact.expanded_limit_bytes,
    );
    var receipt_digest: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&receipt_digest, receipt.value.payload_sha256) catch
        return error.InvalidCacheReceipt;
    if (receipt.value.payload_files != expected.payload_files or
        receipt.value.payload_bytes != expected.payload_bytes or
        actual.files != expected.payload_files or
        actual.bytes != expected.payload_bytes or
        !std.mem.eql(u8, &receipt_digest, &expected.payload_sha256) or
        !std.mem.eql(u8, &actual.digest, &expected.payload_sha256))
    {
        return error.InvalidCachedPayload;
    }
}

fn parseCacheReceipt(
    allocator: std.mem.Allocator,
    receipt_bytes: []const u8,
) !std.json.Parsed(Receipt) {
    return std.json.parseFromSlice(
        Receipt,
        allocator,
        receipt_bytes,
        .{ .duplicate_field_behavior = .@"error", .ignore_unknown_fields = false },
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidCacheReceipt,
    };
}

fn downloadArtifact(
    allocator: std.mem.Allocator,
    io: std.Io,
    source: ArchiveSource,
    artifact: deps.Artifact,
    destination: std.Io.Dir,
    destination_name: []const u8,
) !void {
    return switch (source) {
        .http => |client| downloadHttpArtifact(
            allocator,
            io,
            realHttpTransport(client),
            artifact,
            destination,
            destination_name,
        ),
        .transport => |transport| downloadHttpArtifact(
            allocator,
            io,
            transport,
            artifact,
            destination,
            destination_name,
        ),
        .bytes => |bytes| writeArchiveBytes(
            io,
            artifact,
            destination,
            destination_name,
            bytes,
        ),
    };
}

fn writeArchiveBytes(
    io: std.Io,
    artifact: deps.Artifact,
    destination: std.Io.Dir,
    destination_name: []const u8,
    bytes: []const u8,
) !void {
    var verifier = try deps.DownloadVerifier.init(artifact, bytes.len);
    try verifier.feed(bytes);
    try verifier.finish();
    if (!verifier.mayActivate()) return error.DownloadIncomplete;
    var file = try destination.createFile(io, destination_name, .{
        .read = true,
        .exclusive = true,
        .permissions = privateFilePermissions(),
        .resolve_beneath = true,
    });
    defer file.close(io);
    var writer_buffer: [64 * 1024]u8 = undefined;
    var writer = file.writerStreaming(io, &writer_buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
    try file.sync(io);
}

fn downloadHttpArtifact(
    allocator: std.mem.Allocator,
    io: std.Io,
    transport: DownloadTransport,
    artifact: deps.Artifact,
    destination: std.Io.Dir,
    destination_name: []const u8,
) !void {
    if (transport.timeout_ms <= 0) return error.InvalidDownloadTimeout;
    var outcomes: [2]DownloadDeadlineOutcome = undefined;
    var selection = std.Io.Select(DownloadDeadlineOutcome).init(io, &outcomes);
    defer selection.cancelDiscard();
    try selection.concurrent(.operation, downloadHttpArtifactWithinDeadline, .{
        allocator,
        io,
        transport,
        artifact,
        destination,
        destination_name,
    });
    try selection.concurrent(.timeout, waitForDownloadDeadline, .{ io, transport.timeout_ms });
    switch (try selection.await()) {
        .operation => |result| return result,
        .timeout => |result| {
            try result;
            // This synchronously cancels and joins the transport operation, so
            // its request/file defers have completed before acquisition removes
            // the enclosing stage.
            selection.cancelDiscard();
            return error.DownloadTimeout;
        },
    }
}

fn waitForDownloadDeadline(io: std.Io, timeout_ms: i64) !void {
    try std.Io.Clock.Duration.sleep(.{
        .clock = .awake,
        .raw = .fromMilliseconds(timeout_ms),
    }, io);
}

fn downloadHttpArtifactWithinDeadline(
    allocator: std.mem.Allocator,
    io: std.Io,
    transport: DownloadTransport,
    artifact: deps.Artifact,
    destination: std.Io.Dir,
    destination_name: []const u8,
) !void {
    var current_url = try allocator.dupe(u8, artifact.url);
    defer allocator.free(current_url);
    var redirects = deps.RedirectTracker.init(current_url);

    while (true) {
        try deps.validateDownloadTarget(artifact.id, current_url);
        std.debug.print("deps-fetch transport=request artifact={s}\n", .{artifact.id});
        const request = try transport.open_request(
            transport.context,
            allocator,
            io,
            current_url,
        );
        defer request.deinit();
        std.debug.print("deps-fetch transport=connected artifact={s}\n", .{artifact.id});
        std.debug.print("deps-fetch transport=request-sent artifact={s}\n", .{artifact.id});
        const response = try request.receive_head(request.context);
        std.debug.print(
            "deps-fetch transport=response-head artifact={s} status={d}\n",
            .{ artifact.id, @intFromEnum(response.status) },
        );

        if (isAllowedRedirect(response.status)) {
            const location = response.location orelse
                return error.DownloadRedirectMissingLocation;
            if (location.len == 0 or location.len > 8192) {
                return error.DownloadRedirectLocationTooLarge;
            }
            const next_url = try allocator.dupe(u8, location);
            errdefer allocator.free(next_url);
            try deps.validateDownloadTarget(artifact.id, next_url);
            try redirects.follow(next_url);
            // keep_alive=false makes deinit close this response. Do not drain a
            // redirect body: an approved-but-compromised origin could otherwise
            // stream unbounded bytes or stall before the next allowlisted hop.
            allocator.free(current_url);
            current_url = next_url;
            continue;
        }
        if (response.status != .ok) return error.DownloadHttpStatus;
        if (response.content_encoding != .identity) {
            return error.DownloadContentEncoding;
        }

        var verifier = try deps.DownloadVerifier.init(artifact, response.content_length);
        std.debug.print("deps-fetch transport=create-stage-file artifact={s}\n", .{artifact.id});
        var file = try destination.createFile(io, destination_name, .{
            .read = true,
            .exclusive = true,
            .permissions = privateFilePermissions(),
            .resolve_beneath = true,
        });
        defer file.close(io);
        std.debug.print("deps-fetch transport=stream-body artifact={s}\n", .{artifact.id});
        var file_buffer: [64 * 1024]u8 = undefined;
        var writer = file.writerStreaming(io, &file_buffer);
        var chunk: [64 * 1024]u8 = undefined;
        var chunks: usize = 0;
        while (true) {
            const count = response.read_body(response.context, &chunk) catch {
                verifier.markTransportFailure();
                const detail = response.body_error(response.context) orelse error.DownloadReadFailed;
                std.debug.print("deps-fetch transport=body-read-failed error={t}\n", .{detail});
                return detail;
            };
            if (count == 0) break;
            try verifier.feed(chunk[0..count]);
            writer.interface.writeAll(chunk[0..count]) catch |err| {
                std.debug.print("deps-fetch transport=file-write-failed error={t}\n", .{err});
                return err;
            };
            chunks += 1;
        }
        std.debug.print("deps-fetch transport=body-complete chunks={d}\n", .{chunks});
        try verifier.finish();
        if (!verifier.mayActivate()) return error.DownloadIncomplete;
        writer.interface.flush() catch |err| {
            std.debug.print("deps-fetch transport=file-flush-failed error={t}\n", .{err});
            return err;
        };
        file.sync(io) catch |err| {
            std.debug.print("deps-fetch transport=file-sync-failed error={t}\n", .{err});
            return err;
        };
        return;
    }
}

fn realHttpTransport(client: *std.http.Client) DownloadTransport {
    return .{
        .context = client,
        .open_request = openRealHttpRequest,
    };
}

fn openRealHttpRequest(
    context: *anyopaque,
    allocator: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
) !DownloadRequest {
    _ = io;
    const client: *std.http.Client = @ptrCast(@alignCast(context));
    const uri = std.Uri.parse(url) catch return error.InvalidDownloadUrl;
    const state = try allocator.create(RealHttpRequest);
    errdefer allocator.destroy(state);
    state.* = .{
        .allocator = allocator,
        .request = try client.request(.GET, uri, .{
            .keep_alive = false,
            .redirect_behavior = .unhandled,
            .headers = .{
                .authorization = .omit,
                .user_agent = .{ .override = user_agent },
                .accept_encoding = .{ .override = "identity" },
            },
            .extra_headers = &.{},
            .privileged_headers = &.{},
        }),
    };
    errdefer state.request.deinit();
    try state.request.sendBodiless();
    return .{
        .context = state,
        .receive_head = receiveRealHttpHead,
        .deinit_request = deinitRealHttpRequest,
    };
}

fn receiveRealHttpHead(context: *anyopaque) !DownloadResponse {
    const state: *RealHttpRequest = @ptrCast(@alignCast(context));
    if (state.response != null) return error.DownloadHeadAlreadyReceived;
    state.response = try state.request.receiveHead(&.{});
    const head = state.response.?.head;
    return .{
        .context = state,
        .status = head.status,
        .location = head.location,
        .content_length = head.content_length,
        .content_encoding = head.content_encoding,
        .read_body = readRealHttpBody,
        .body_error = realHttpBodyError,
    };
}

fn readRealHttpBody(context: *anyopaque, buffer: []u8) !usize {
    const state: *RealHttpRequest = @ptrCast(@alignCast(context));
    if (state.body_reader == null) {
        state.body_reader = state.response.?.reader(&state.transfer_buffer);
    }
    return state.body_reader.?.readSliceShort(buffer);
}

fn realHttpBodyError(context: *anyopaque) ?anyerror {
    const state: *RealHttpRequest = @ptrCast(@alignCast(context));
    return state.response.?.bodyErr();
}

fn deinitRealHttpRequest(context: *anyopaque) void {
    const state: *RealHttpRequest = @ptrCast(@alignCast(context));
    state.request.deinit();
    state.allocator.destroy(state);
}

fn isAllowedRedirect(status: std.http.Status) bool {
    return switch (status) {
        .moved_permanently,
        .found,
        .see_other,
        .temporary_redirect,
        .permanent_redirect,
        => true,
        else => false,
    };
}

fn writeReceipt(
    io: std.Io,
    dir: std.Io.Dir,
    artifact: deps.Artifact,
    archive_bytes: usize,
    archive_digest: [32]u8,
    summary: deps.MaterializedArchive,
) !void {
    const archive_digest_hex = std.fmt.bytesToHex(archive_digest, .lower);
    const digest_hex = std.fmt.bytesToHex(summary.payload_sha256, .lower);
    var file = try dir.createFile(io, ".complete.json", .{
        .read = true,
        .exclusive = true,
        .permissions = privateFilePermissions(),
        .resolve_beneath = true,
    });
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var writer = file.writerStreaming(io, &buffer);
    try writer.interface.print(
        "{{\n  \"schema_version\": {d},\n  \"artifact_id\": \"{s}\",\n" ++
            "  \"artifact_version\": \"{s}\",\n  \"archive_bytes\": {d},\n" ++
            "  \"archive_sha256\": \"{s}\",\n" ++
            "  \"payload_files\": {d},\n  \"payload_bytes\": {d},\n" ++
            "  \"payload_sha256\": \"{s}\"\n}}\n",
        .{
            cache_schema_version,
            artifact.id,
            artifact.version,
            archive_bytes,
            archive_digest_hex,
            summary.payload_files,
            summary.payload_bytes,
            digest_hex,
        },
    );
    try writer.interface.flush();
    try file.sync(io);
}

fn validateCacheContainer(io: std.Io, dir: std.Io.Dir) !void {
    var seen_archive = false;
    var seen_payload = false;
    var seen_receipt = false;
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (std.mem.eql(u8, entry.name, "archive.bin") and entry.kind == .file) {
            if (seen_archive) return error.InvalidCacheContainer;
            seen_archive = true;
        } else if (std.mem.eql(u8, entry.name, "payload") and entry.kind == .directory) {
            if (seen_payload) return error.InvalidCacheContainer;
            seen_payload = true;
        } else if (std.mem.eql(u8, entry.name, ".complete.json") and entry.kind == .file) {
            if (seen_receipt) return error.InvalidCacheContainer;
            seen_receipt = true;
        } else {
            return error.InvalidCacheContainer;
        }
    }
    if (!seen_archive or !seen_payload or !seen_receipt) return error.InvalidCacheContainer;
}

fn readVerifiedFileAlloc(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    path: []const u8,
    limit: u64,
) ![]u8 {
    var verification = try dir.openFile(io, path, .{
        .path_only = true,
        .follow_symlinks = false,
        .resolve_beneath = true,
    });
    defer verification.close(io);
    const expected_stat = try verification.stat(io);
    if (expected_stat.kind != .file or expected_stat.size > limit) {
        return error.InvalidCacheFile;
    }
    var file = try dir.openFile(io, path, .{
        .follow_symlinks = true,
        .resolve_beneath = true,
    });
    defer file.close(io);
    const actual_stat = try file.stat(io);
    if (actual_stat.kind != .file or actual_stat.inode != expected_stat.inode or
        actual_stat.size != expected_stat.size)
    {
        return error.CacheIdentityChanged;
    }
    var reader_buffer: [64 * 1024]u8 = undefined;
    var reader = file.reader(io, &reader_buffer);
    const bytes = try reader.interface.allocRemaining(
        allocator,
        .limited(std.math.cast(usize, limit + 1) orelse std.math.maxInt(usize)),
    );
    errdefer allocator.free(bytes);
    if (bytes.len != expected_stat.size) return error.CacheIdentityChanged;
    return bytes;
}

/// A crash after freezing cannot be recovered by deleteTree: RX descendants
/// deliberately deny deletion. Preserve the complete sealed transaction in
/// quarantine through a parent-granted DELETE handle, without changing ACLs.
fn recoverFrozenInterruptedStages(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    artifacts: []const deps.Artifact,
    observer: AcquireObserver,
) !void {
    if (builtin.os.tag != .windows) return;
    var names: [64][160]u8 = undefined;
    var lengths: [64]u8 = undefined;
    var count: usize = 0;
    var iterator = cache_root.iterate();
    while (try iterator.next(io)) |entry| {
        if (!std.mem.startsWith(u8, entry.name, ".stage-")) continue;
        if (entry.kind != .directory or entry.name.len > 160) return error.InterruptedStageUnsafe;
        if (count == names.len) return error.TooManyInterruptedStages;
        @memcpy(names[count][0..entry.name.len], entry.name);
        lengths[count] = @intCast(entry.name.len);
        count += 1;
    }
    for (names[0..count], lengths[0..count]) |name, length| {
        const path = name[0..length];
        var stage = try cache_root.openDir(io, path, .{ .iterate = true, .follow_symlinks = false });
        var stage_open = true;
        defer if (stage_open) stage.close(io);
        try requireOrdinaryDirectory(io, stage);
        verifyOwnerOnlyAclExact(stage.handle, .directory, owner_rights_read_execute_access) catch |err| {
            if (err != error.OwnerOnlyAclVerificationFailed) return err;
            // The root must retain its protected exact construction ACL.
            // Descendants may still carry the single inherited OWNER RIGHTS
            // full grant from creation, before final ACL normalization. Verify
            // the entire tree before cleanup; RX/mixed/unknown grants fail.
            try validateTreeNoReparse(allocator, io, stage);
            try verifyTreeAclPolicy(allocator, io, stage, file_all_access, .mutable_stage_descendant);
            continue;
        };
        const artifact = for (artifacts) |candidate| {
            if (path.len != ".stage-".len + candidate.id.len + 1 + 24) continue;
            if (!std.mem.eql(u8, path[".stage-".len..][0..candidate.id.len], candidate.id)) continue;
            if (path[".stage-".len + candidate.id.len] != '-') continue;
            break candidate;
        } else return error.InterruptedStageUnsafe;
        var generation_buffer: [deps.cache_generation_name_bytes]u8 = undefined;
        const generation = try std.fmt.bufPrint(&generation_buffer, "g-{s}", .{path[path.len - 24 ..]});
        try deps.validateCacheGenerationName(generation);
        // Establish safe, complete receipt/tree evidence before creating a store.
        const evidence = try snapshotQuarantineGeneration(allocator, io, stage, generation, artifact);
        defer allocator.free(evidence.artifact_version);
        stage.close(io);
        stage_open = false;
        var store = try openOrCreateV2ArtifactStore(allocator, io, cache_root, artifact.id);
        defer store.close(io);
        try quarantineDirectory(allocator, io, store.artifact, cache_root, path, generation, artifact, observer);
    }
}

fn cleanInterruptedStages(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
) !void {
    var names: [64][160]u8 = undefined;
    var lengths: [64]u8 = undefined;
    var count: usize = 0;
    var iterator = cache_root.iterate();
    while (try iterator.next(io)) |entry| {
        if (!std.mem.startsWith(u8, entry.name, ".stage-")) continue;
        if (entry.kind != .directory or entry.name.len > 160) {
            return error.InterruptedStageUnsafe;
        }
        if (count == names.len) return error.TooManyInterruptedStages;
        @memcpy(names[count][0..entry.name.len], entry.name);
        lengths[count] = @intCast(entry.name.len);
        count += 1;
    }
    for (names[0..count], lengths[0..count]) |name, length| {
        const path = name[0..length];
        {
            var stage = try cache_root.openDir(io, path, .{
                .iterate = true,
                .follow_symlinks = false,
            });
            defer stage.close(io);
            try validateTreeNoReparse(allocator, io, stage);
        }
        try cache_root.deleteTree(io, path);
    }
}

fn handleInterruptedStages(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    policy: InterruptedStagePolicy,
) !void {
    switch (policy) {
        .clean_safe => try cleanInterruptedStages(allocator, io, cache_root),
        .reject => {
            var iterator = cache_root.iterate();
            while (try iterator.next(io)) |entry| {
                if (std.mem.startsWith(u8, entry.name, ".stage-")) {
                    return error.InterruptedStagePresent;
                }
            }
        },
    }
    try handleInterruptedSelectorStages(io, cache_root, policy);
}

/// Quarantine invalid retained generations only after validating their frozen
/// ordinary tree. Unsafe reparse/ACL/receipt metadata remains fail-closed; sealed
/// descendants are never made writable or recursively deleted.
fn cleanInvalidInactiveGenerations(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    artifacts: []const deps.Artifact,
    observer: AcquireObserver,
) !void {
    var v2 = cache_root.openDir(io, deps.cache_v2_directory, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => |e| return e,
    };
    defer v2.close(io);
    try requireOrdinaryDirectory(io, v2);

    var stores = v2.iterate();
    while (try stores.next(io)) |store_entry| {
        if (store_entry.kind != .directory) return error.InvalidV2CacheContainer;
        const artifact = findArtifactById(artifacts, store_entry.name) orelse continue;
        var store = try v2.openDir(io, store_entry.name, .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer store.close(io);
        try requireOrdinaryDirectory(io, store);
        try validateQuarantine(allocator, io, store, artifact, true, observer);
        var generations = store.openDir(io, deps.cache_generations_directory, .{
            .iterate = true,
            .follow_symlinks = false,
        }) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => |e| return e,
        };
        defer generations.close(io);
        try requireOrdinaryDirectory(io, generations);
        const selected = readCurrentSelector(allocator, io, store) catch |err| switch (classifyCacheValidationError(err)) {
            .invalid => null,
            .operational => return err,
        };
        defer if (selected) |name| allocator.free(name);

        var names: [max_cache_generations][deps.cache_generation_name_bytes]u8 = undefined;
        var lengths: [max_cache_generations]u8 = undefined;
        var count: usize = 0;
        var entries = generations.iterate();
        while (try entries.next(io)) |entry| {
            if (count == names.len) return error.TooManyCacheGenerations;
            deps.validateCacheGenerationName(entry.name) catch
                return error.InvalidV2CacheContainer;
            if (entry.kind != .directory) return error.InvalidV2CacheContainer;
            @memcpy(names[count][0..entry.name.len], entry.name);
            lengths[count] = @intCast(entry.name.len);
            count += 1;
        }

        for (names[0..count], lengths[0..count]) |name, length| {
            const generation_name = name[0..length];
            if (selected) |selected_name| {
                if (std.mem.eql(u8, generation_name, selected_name)) continue;
            }
            var generation = generations.openDir(io, generation_name, .{
                .iterate = true,
                .follow_symlinks = false,
            }) catch return error.InvalidV2CacheContainer;
            // First establish that the complete tree is ordinary and safely
            // traversable. Reparse points and ACL failures are never deleted.
            validateGenerationTreeNoReparse(
                allocator,
                io,
                generation,
                .verify_only,
            ) catch |err| {
                generation.close(io);
                return err;
            };
            const validation = validateRetainedGeneration(
                allocator,
                io,
                generation,
                artifact,
                .verify_only,
            );
            generation.close(io);
            validation catch |err| switch (classifyCacheValidationError(err)) {
                .invalid => try quarantineGeneration(allocator, io, store, generations, generation_name, artifact, observer),
                .operational => return err,
            };
        }
    }
}

const QuarantineEvidence = struct {
    schema_version: u32,
    artifact_id: []const u8,
    artifact_version: []const u8,
    generation: []const u8,
    archive_bytes: u64,
    archive_sha256: [32]u8,
    payload_files: u64,
    payload_bytes: u64,
    payload_sha256: [32]u8,
    receipt_bytes: u64,
    receipt_sha256: [32]u8,
};

fn snapshotQuarantineGeneration(
    allocator: std.mem.Allocator,
    io: std.Io,
    generation: std.Io.Dir,
    name: []const u8,
    artifact: deps.Artifact,
) !QuarantineEvidence {
    try validateCacheContainer(io, generation);
    try validateGenerationTreeNoReparse(allocator, io, generation, .verify_only);
    try verifyTreeAclExact(allocator, io, generation, owner_rights_read_execute_access);
    const receipt_bytes = try readVerifiedFileAlloc(allocator, io, generation, ".complete.json", 4096);
    defer allocator.free(receipt_bytes);
    var receipt = try parseCacheReceipt(allocator, receipt_bytes);
    defer receipt.deinit();
    if (receipt.value.schema_version != cache_schema_version or
        !std.mem.eql(u8, receipt.value.artifact_id, artifact.id) or
        receipt.value.artifact_version.len == 0 or receipt.value.artifact_version.len > 256 or
        !isLowerSha256(receipt.value.archive_sha256) or !isLowerSha256(receipt.value.payload_sha256))
        return error.InvalidCacheReceipt;
    const archive = try readVerifiedFileAlloc(allocator, io, generation, "archive.bin", artifact.download_limit_bytes);
    defer allocator.free(archive);
    var payload = try generation.openDir(io, "payload", .{ .iterate = true, .follow_symlinks = false });
    defer payload.close(io);
    const actual = try deps.hashMaterializedDirectory(allocator, io, payload, artifact.expanded_limit_bytes);
    var evidence: QuarantineEvidence = .{
        .schema_version = 1,
        .artifact_id = artifact.id,
        .artifact_version = try allocator.dupe(u8, receipt.value.artifact_version),
        .generation = name,
        .archive_bytes = archive.len,
        .archive_sha256 = undefined,
        .payload_files = actual.files,
        .payload_bytes = actual.bytes,
        .payload_sha256 = actual.digest,
        .receipt_bytes = receipt_bytes.len,
        .receipt_sha256 = undefined,
    };
    std.crypto.hash.sha2.Sha256.hash(archive, &evidence.archive_sha256, .{});
    std.crypto.hash.sha2.Sha256.hash(receipt_bytes, &evidence.receipt_sha256, .{});
    return evidence;
}

fn quarantineEvidenceEqual(a: QuarantineEvidence, b: QuarantineEvidence) bool {
    return a.schema_version == 1 and b.schema_version == 1 and
        std.mem.eql(u8, a.artifact_id, b.artifact_id) and
        std.mem.eql(u8, a.artifact_version, b.artifact_version) and
        std.mem.eql(u8, a.generation, b.generation) and
        a.archive_bytes == b.archive_bytes and a.payload_files == b.payload_files and
        a.payload_bytes == b.payload_bytes and a.receipt_bytes == b.receipt_bytes and
        std.mem.eql(u8, &a.archive_sha256, &b.archive_sha256) and
        std.mem.eql(u8, &a.payload_sha256, &b.payload_sha256) and
        std.mem.eql(u8, &a.receipt_sha256, &b.receipt_sha256);
}

fn createQuarantineEvidenceFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    quarantine: std.Io.Dir,
    name: []const u8,
) !std.Io.File {
    if (builtin.os.tag != .windows) return quarantine.createFile(io, name, .{
        .exclusive = true,
        .permissions = privateFilePermissions(),
        .resolve_beneath = true,
    });
    const windows = std.os.windows;
    const name_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, name);
    defer allocator.free(name_w);
    var descriptor: ?*anyopaque = null;
    if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
        std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;;FA;;;OW)"),
        1,
        &descriptor,
        null,
    ) == 0 or descriptor == null) return error.OwnerOnlyAclFailed;
    defer _ = LocalFree(descriptor);
    var object_name = windows.UNICODE_STRING.init(name_w[0..name_w.len]);
    const attributes: windows.OBJECT.ATTRIBUTES = .{
        .RootDirectory = quarantine.handle,
        .Attributes = .{ .CASE_INSENSITIVE = true },
        .ObjectName = &object_name,
        .SecurityDescriptor = descriptor,
        .SecurityQualityOfService = null,
    };
    var handle: windows.HANDLE = undefined;
    var io_status: windows.IO_STATUS_BLOCK = undefined;
    const status = windows.ntdll.NtCreateFile(
        &handle,
        .{
            .SPECIFIC = .{ .FILE = .{ .READ_DATA = true, .WRITE_DATA = true, .READ_ATTRIBUTES = true } },
            .STANDARD = .{ .RIGHTS = .{ .DELETE = true, .READ_CONTROL = true, .WRITE_DAC = true }, .SYNCHRONIZE = true },
        },
        &attributes,
        &io_status,
        null,
        .{ .NORMAL = true },
        .{ .READ = true, .WRITE = false, .DELETE = false },
        .CREATE,
        .{ .NON_DIRECTORY_FILE = true, .IO = .SYNCHRONOUS_NONALERT, .OPEN_REPARSE_POINT = true },
        null,
        0,
    );
    switch (status) {
        .SUCCESS => {},
        .OBJECT_NAME_COLLISION => return error.PathAlreadyExists,
        .ACCESS_DENIED, .SHARING_VIOLATION => return error.AccessDenied,
        else => return windows.unexpectedStatus(status),
    }
    errdefer windows.CloseHandle(handle);
    try verifyOwnerOnlyAclExact(handle, .file, file_all_access);
    return .{ .handle = handle, .flags = .{ .nonblocking = false } };
}

fn writeQuarantineEvidence(
    allocator: std.mem.Allocator,
    io: std.Io,
    quarantine: std.Io.Dir,
    evidence: QuarantineEvidence,
    observer: AcquireObserver,
) !void {
    var name_buffer: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buffer, "{s}.json", .{evidence.generation});
    var stage_buffer: [64]u8 = undefined;
    const stage = try std.fmt.bufPrint(&stage_buffer, ".stage-{s}.json", .{evidence.generation});
    const bytes = try std.json.Stringify.valueAlloc(allocator, evidence, .{});
    defer allocator.free(bytes);
    if (bytes.len > 4096) return error.InvalidQuarantine;
    // Protection is supplied during creation, so even a crash during the first
    // write leaves a known owner-only stage that exclusive recovery can remove.
    var file = try createQuarantineEvidenceFile(allocator, io, quarantine, stage);
    defer file.close(io);
    try file.writeStreamingAll(io, bytes[0 .. bytes.len / 2]);
    try observer.notify(.quarantine_evidence_started);
    try file.writeStreamingAll(io, bytes[bytes.len / 2 ..]);
    try file.sync(io);
    if (builtin.os.tag == .windows) {
        try setOwnerRightsAclByHandle(file.handle, .file, .read_execute);
        try verifyOwnerOnlyAclExact(file.handle, .file, owner_rights_read_execute_access);
        try renameDirectoryHandleWindows(file.handle, quarantine, name);
    } else {
        try quarantine.renamePreserve(stage, quarantine, name, io);
    }
}

/// Quarantine is evidence storage, never a selector or rollback search path.
/// Audit rejects incomplete transactions; exclusive fetch reconciles only the
/// orphan-directory state produced by rename-before-evidence publication.
fn validateQuarantine(
    allocator: std.mem.Allocator,
    io: std.Io,
    store: std.Io.Dir,
    artifact: deps.Artifact,
    reconcile: bool,
    observer: AcquireObserver,
) !void {
    var quarantine = store.openDir(io, deps.cache_quarantine_directory, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer quarantine.close(io);
    try requireOrdinaryDirectory(io, quarantine);
    try verifyOwnerOnlyAclExact(quarantine.handle, .directory, file_all_access);
    var names: [max_cache_generations][deps.cache_generation_name_bytes]u8 = undefined;
    var count: usize = 0;
    var total: usize = 0;
    var staged_names: [max_cache_generations][deps.cache_generation_name_bytes]u8 = undefined;
    var staged_count: usize = 0;
    var entries = quarantine.iterate();
    while (try entries.next(io)) |entry| {
        total += 1;
        if (total > max_cache_generations * 3) return error.TooManyCacheGenerations;
        if (entry.kind == .directory) {
            try deps.validateCacheGenerationName(entry.name);
            if (count == names.len) return error.TooManyCacheGenerations;
            @memcpy(&names[count], entry.name);
            count += 1;
            continue;
        }
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".json"))
            return error.InvalidQuarantine;
        const staged = std.mem.startsWith(u8, entry.name, ".stage-");
        const name = entry.name[if (staged) 7 else 0 .. entry.name.len - 5];
        try deps.validateCacheGenerationName(name);
        var generation = quarantine.openDir(io, name, .{ .iterate = true, .follow_symlinks = false }) catch
            return error.InvalidQuarantine;
        generation.close(io);
        var file = try quarantine.openFile(io, entry.name, .{
            .path_only = true,
            .follow_symlinks = false,
            .resolve_beneath = true,
        });
        defer file.close(io);
        if ((try file.stat(io)).kind != .file) return error.InvalidQuarantine;
        if (staged) {
            try verifyOwnerOnlyAcl(file.handle, .file);
            if (!reconcile) return error.InterruptedStagePresent;
            if (staged_count == staged_names.len) return error.TooManyCacheGenerations;
            @memcpy(&staged_names[staged_count], name);
            staged_count += 1;
        } else {
            try verifyOwnerOnlyAclExact(file.handle, .file, owner_rights_read_execute_access);
        }
    }
    for (staged_names[0..staged_count]) |name| {
        var stage_buffer: [64]u8 = undefined;
        const stage = try std.fmt.bufPrint(&stage_buffer, ".stage-{s}.json", .{name});
        try quarantine.deleteFile(io, stage);
    }
    for (names[0..count]) |name| {
        var generation = try quarantine.openDir(io, &name, .{ .iterate = true, .follow_symlinks = false });
        defer generation.close(io);
        const actual = try snapshotQuarantineGeneration(allocator, io, generation, &name, artifact);
        defer allocator.free(actual.artifact_version);
        var sidecar_buffer: [64]u8 = undefined;
        const sidecar = try std.fmt.bufPrint(&sidecar_buffer, "{s}.json", .{name});
        const bytes = readVerifiedFileAlloc(allocator, io, quarantine, sidecar, 4096) catch |err| switch (err) {
            error.FileNotFound => {
                if (!reconcile) return error.InvalidQuarantine;
                try writeQuarantineEvidence(allocator, io, quarantine, actual, observer);
                continue;
            },
            else => return err,
        };
        defer allocator.free(bytes);
        var evidence = std.json.parseFromSlice(QuarantineEvidence, allocator, bytes, .{}) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return error.InvalidQuarantine,
        };
        defer evidence.deinit();
        if (!quarantineEvidenceEqual(evidence.value, actual)) return error.QuarantineEvidenceMismatch;
    }
}

fn quarantineGeneration(
    allocator: std.mem.Allocator,
    io: std.Io,
    store: std.Io.Dir,
    generations: std.Io.Dir,
    name: []const u8,
    artifact: deps.Artifact,
    observer: AcquireObserver,
) !void {
    return quarantineDirectory(allocator, io, store, generations, name, name, artifact, observer);
}

fn quarantineDirectory(
    allocator: std.mem.Allocator,
    io: std.Io,
    store: std.Io.Dir,
    source: std.Io.Dir,
    source_name: []const u8,
    name: []const u8,
    artifact: deps.Artifact,
    observer: AcquireObserver,
) !void {
    // Verify a complete frozen ordinary tree and its original receipt metadata
    // before moving anything. A malformed receipt, ACL or reparse point remains
    // a fail-closed error, not permission to discard or bless unknown data.
    {
        var generation = try source.openDir(io, source_name, .{ .iterate = true, .follow_symlinks = false });
        defer generation.close(io);
        const evidence = try snapshotQuarantineGeneration(allocator, io, generation, name, artifact);
        defer allocator.free(evidence.artifact_version);
    }
    var quarantine = try openOrCreateChildDirectory(allocator, io, store, deps.cache_quarantine_directory);
    defer quarantine.close(io);
    var count: usize = 0;
    var entries = quarantine.iterate();
    while (try entries.next(io)) |entry| {
        if (entry.kind == .directory) count += 1;
    }
    if (count >= max_cache_generations) return error.TooManyCacheGenerations;
    // All descendant handles are closed. Same-volume rename needs only the
    // generation's delete grant from its writable parent, never WRITE_DAC on
    // frozen descendants, and does not overwrite an existing quarantine item.
    if (builtin.os.tag == .windows) {
        const windows = std.os.windows;
        const name_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, source_name);
        defer allocator.free(name_w);
        var object_name = windows.UNICODE_STRING.init(name_w[0..name_w.len]);
        const attributes: windows.OBJECT.ATTRIBUTES = .{
            .RootDirectory = source.handle,
            .Attributes = .{ .CASE_INSENSITIVE = true },
            .ObjectName = &object_name,
            .SecurityDescriptor = null,
            .SecurityQualityOfService = null,
        };
        var handle: windows.HANDLE = undefined;
        var io_status: windows.IO_STATUS_BLOCK = undefined;
        const status = windows.ntdll.NtCreateFile(
            &handle,
            .{
                .SPECIFIC = .{ .FILE_DIRECTORY = .{ .LIST = true, .TRAVERSE = true, .READ_ATTRIBUTES = true } },
                .STANDARD = .{ .RIGHTS = .{ .DELETE = true, .READ_CONTROL = true }, .SYNCHRONIZE = true },
            },
            &attributes,
            &io_status,
            null,
            .{ .NORMAL = true },
            .{ .READ = true, .WRITE = false, .DELETE = false },
            .OPEN,
            .{ .DIRECTORY_FILE = true, .IO = .SYNCHRONOUS_NONALERT, .OPEN_REPARSE_POINT = true },
            null,
            0,
        );
        if (status != .SUCCESS) return windows.unexpectedStatus(status);
        defer windows.CloseHandle(handle);
        // Revalidate through the pinned identity that will be renamed. Zig's
        // general rename helper asks for GENERIC_WRITE, which sealed objects
        // correctly deny; this open requests only read plus parent-granted DELETE.
        const evidence = try snapshotQuarantineGeneration(allocator, io, .{ .handle = handle }, name, artifact);
        defer allocator.free(evidence.artifact_version);
        try renameDirectoryHandleWindows(handle, quarantine, name);
    } else {
        try source.renamePreserve(source_name, quarantine, name, io);
    }
    try observer.notify(.generation_quarantined);
    try validateQuarantine(allocator, io, store, artifact, true, observer);
}

fn handleInterruptedSelectorStages(
    io: std.Io,
    cache_root: std.Io.Dir,
    policy: InterruptedStagePolicy,
) !void {
    var v2 = cache_root.openDir(io, deps.cache_v2_directory, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => |e| return e,
    };
    defer v2.close(io);
    try requireOrdinaryDirectory(io, v2);
    var artifacts = v2.iterate();
    while (try artifacts.next(io)) |entry| {
        if (entry.kind != .directory) return error.InvalidV2CacheContainer;
        var artifact = try v2.openDir(io, entry.name, .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer artifact.close(io);
        try requireOrdinaryDirectory(io, artifact);
        var names: [64][160]u8 = undefined;
        var lengths: [64]u8 = undefined;
        var count: usize = 0;
        var children = artifact.iterate();
        while (try children.next(io)) |child| {
            if (!std.mem.startsWith(u8, child.name, ".stage-current-")) continue;
            if (policy == .reject) return error.InterruptedStagePresent;
            if (child.kind != .file or child.name.len > names[0].len) {
                return error.InterruptedStageUnsafe;
            }
            if (count == names.len) return error.TooManyInterruptedStages;
            @memcpy(names[count][0..child.name.len], child.name);
            lengths[count] = @intCast(child.name.len);
            count += 1;
        }
        for (names[0..count], lengths[0..count]) |name, length| {
            const path = name[0..length];
            var file = try artifact.openFile(io, path, .{
                .path_only = true,
                .follow_symlinks = false,
                .resolve_beneath = true,
            });
            const stat = try file.stat(io);
            file.close(io);
            if (stat.kind != .file) return error.InterruptedStageUnsafe;
            try artifact.deleteFile(io, path);
        }
    }
}

fn validateCacheSchema(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    artifacts: []const deps.Artifact,
    allow_fixture_marker: bool,
    acl_policy: CacheAclPolicy,
) !void {
    var entries = cache_root.iterate();
    while (try entries.next(io)) |entry| {
        if (std.mem.eql(u8, entry.name, ".lock")) {
            if (entry.kind != .file) return error.InvalidCacheRootContainer;
            var lock = try cache_root.openFile(io, entry.name, .{
                .path_only = true,
                .allow_directory = false,
                .follow_symlinks = false,
                .resolve_beneath = true,
            });
            defer lock.close(io);
            if ((try lock.stat(io)).kind != .file) return error.InvalidCacheRootContainer;
            try enforceFileAclPolicy(allocator, io, cache_root, entry.name, lock.handle, acl_policy);
        } else if (std.mem.eql(u8, entry.name, deps.cache_v2_directory)) {
            if (entry.kind != .directory) return error.InvalidCacheRootContainer;
        } else if (allow_fixture_marker and
            std.mem.eql(u8, entry.name, ".texflow-deps-fixture-root"))
        {
            if (entry.kind != .file) return error.InvalidCacheRootContainer;
            var marker = try cache_root.openFile(io, entry.name, .{
                .path_only = true,
                .allow_directory = false,
                .follow_symlinks = false,
                .resolve_beneath = true,
            });
            defer marker.close(io);
            if ((try marker.stat(io)).kind != .file) return error.InvalidCacheRootContainer;
        } else if (artifactIdAllowed(artifacts, entry.name)) {
            if (entry.kind != .directory) return error.InvalidCacheRootContainer;
            var legacy = try cache_root.openDir(io, entry.name, .{
                .iterate = true,
                .follow_symlinks = false,
            });
            defer legacy.close(io);
            try requireOrdinaryDirectory(io, legacy);
            try enforceDirectoryAclPolicy(allocator, io, legacy, acl_policy);
            // A legacy directory is the live selection. Its exact-content
            // validation below may classify it as repairable corruption, but
            // traversal must still be structurally safe before that probe.
            try validateGenerationTreeNoReparse(allocator, io, legacy, acl_policy);
        } else {
            return error.InvalidCacheRootContainer;
        }
    }
    try validateV2CacheSchema(allocator, io, cache_root, artifacts, acl_policy);
}

fn validateV2CacheSchema(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
    artifacts: []const deps.Artifact,
    acl_policy: CacheAclPolicy,
) !void {
    var v2 = cache_root.openDir(io, deps.cache_v2_directory, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => |e| return e,
    };
    defer v2.close(io);
    try requireOrdinaryDirectory(io, v2);
    try enforceDirectoryAclPolicy(allocator, io, v2, acl_policy);

    var artifact_entries = v2.iterate();
    while (try artifact_entries.next(io)) |entry| {
        if (entry.kind != .directory or !artifactIdAllowed(artifacts, entry.name)) {
            return error.InvalidV2CacheContainer;
        }
        var artifact_store = try v2.openDir(io, entry.name, .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer artifact_store.close(io);
        try requireOrdinaryDirectory(io, artifact_store);
        try enforceDirectoryAclPolicy(allocator, io, artifact_store, acl_policy);

        var children = artifact_store.iterate();
        while (try children.next(io)) |child| {
            if (std.mem.eql(u8, child.name, deps.cache_selector_file)) {
                if (child.kind != .file) return error.InvalidV2CacheContainer;
                var selector = try artifact_store.openFile(io, child.name, .{
                    .path_only = true,
                    .allow_directory = false,
                    .follow_symlinks = false,
                    .resolve_beneath = true,
                });
                defer selector.close(io);
                if ((try selector.stat(io)).kind != .file) return error.InvalidV2CacheContainer;
                try enforceFileAclPolicy(
                    allocator,
                    io,
                    artifact_store,
                    child.name,
                    selector.handle,
                    acl_policy,
                );
            } else if (std.mem.eql(u8, child.name, deps.cache_generations_directory)) {
                if (child.kind != .directory) return error.InvalidV2CacheContainer;
                var generations = try artifact_store.openDir(io, child.name, .{
                    .iterate = true,
                    .follow_symlinks = false,
                });
                defer generations.close(io);
                try requireOrdinaryDirectory(io, generations);
                try enforceDirectoryAclPolicy(allocator, io, generations, acl_policy);
                const selected = readCurrentSelector(
                    allocator,
                    io,
                    artifact_store,
                ) catch |err| switch (classifyCacheValidationError(err)) {
                    .invalid => null,
                    .operational => return err,
                };
                defer if (selected) |name| allocator.free(name);
                const locked_artifact = findArtifactById(artifacts, entry.name) orelse
                    return error.InvalidV2CacheContainer;
                try validateGenerationContainers(
                    allocator,
                    io,
                    generations,
                    locked_artifact,
                    selected,
                    acl_policy,
                );
            } else if (std.mem.eql(u8, child.name, deps.cache_quarantine_directory)) {
                if (child.kind != .directory) return error.InvalidQuarantine;
                const locked_artifact = findArtifactById(artifacts, entry.name) orelse
                    return error.InvalidQuarantine;
                try validateQuarantine(allocator, io, artifact_store, locked_artifact, false, .{});
            } else if (std.mem.startsWith(u8, child.name, ".stage-current-")) {
                // The stage policy runs first. A surviving selector stage is
                // either an unsafe kind or a concurrent/uncooperative write.
                return error.InterruptedStagePresent;
            } else {
                return error.InvalidV2CacheContainer;
            }
        }
    }
}

fn artifactIdAllowed(artifacts: []const deps.Artifact, id: []const u8) bool {
    return findArtifactById(artifacts, id) != null;
}

fn findArtifactById(artifacts: []const deps.Artifact, id: []const u8) ?deps.Artifact {
    for (artifacts) |artifact| {
        if (std.mem.eql(u8, artifact.id, id)) return artifact;
    }
    return null;
}

fn validateGenerationContainers(
    allocator: std.mem.Allocator,
    io: std.Io,
    generations: std.Io.Dir,
    artifact: deps.Artifact,
    selected_name: ?[]const u8,
    acl_policy: CacheAclPolicy,
) !void {
    var generation_count: usize = 0;
    var entries = generations.iterate();
    while (try entries.next(io)) |entry| {
        generation_count += 1;
        if (generation_count > max_cache_generations) {
            return error.TooManyCacheGenerations;
        }
        deps.validateCacheGenerationName(entry.name) catch
            return error.InvalidV2CacheContainer;
        if (entry.kind != .directory) return error.InvalidV2CacheContainer;
        var generation = try generations.openDir(io, entry.name, .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer generation.close(io);
        try requireOrdinaryDirectory(io, generation);
        try enforceDirectoryAclPolicy(allocator, io, generation, acl_policy);
        if (selected_name) |selected| {
            if (std.mem.eql(u8, entry.name, selected)) {
                // Content validation of the selected generation is performed
                // by acquireArtifact/validateCachedArtifact. Keeping that
                // probe separate lets a fetch repair a corrupt selection;
                // schema traversal still verifies its complete tree and ACLs.
                try validateGenerationTreeNoReparse(allocator, io, generation, acl_policy);
                continue;
            }
        }
        // A retained generation may have been produced by an earlier locked
        // artifact version. Validate its own receipt, archive digest, payload
        // digest, and exact tree without comparing its version to today's
        // manifest entry.
        try validateRetainedGeneration(allocator, io, generation, artifact, acl_policy);
    }
}

fn validateRetainedGeneration(
    allocator: std.mem.Allocator,
    io: std.Io,
    generation: std.Io.Dir,
    artifact: deps.Artifact,
    acl_policy: CacheAclPolicy,
) !void {
    try validateCacheContainer(io, generation);
    const receipt_bytes = try readVerifiedFileAlloc(
        allocator,
        io,
        generation,
        ".complete.json",
        4096,
    );
    defer allocator.free(receipt_bytes);
    var receipt = try parseCacheReceipt(allocator, receipt_bytes);
    defer receipt.deinit();
    if (receipt.value.schema_version != cache_schema_version or
        !std.mem.eql(u8, receipt.value.artifact_id, artifact.id) or
        receipt.value.artifact_version.len == 0 or
        !isLowerSha256(receipt.value.archive_sha256) or
        !isLowerSha256(receipt.value.payload_sha256))
    {
        return error.InvalidCacheReceipt;
    }

    const archive = try readVerifiedFileAlloc(
        allocator,
        io,
        generation,
        "archive.bin",
        artifact.download_limit_bytes,
    );
    defer allocator.free(archive);
    if (receipt.value.archive_bytes != archive.len) return error.InvalidCacheReceipt;
    deps.verifySha256(archive, receipt.value.archive_sha256) catch
        return error.InvalidCacheReceipt;

    var payload = try generation.openDir(io, "payload", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer payload.close(io);
    try requireOrdinaryDirectory(io, payload);
    const actual = try deps.hashMaterializedDirectory(
        allocator,
        io,
        payload,
        artifact.expanded_limit_bytes,
    );
    var receipt_digest: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&receipt_digest, receipt.value.payload_sha256) catch
        return error.InvalidCacheReceipt;
    if (receipt.value.payload_files != actual.files or
        receipt.value.payload_bytes != actual.bytes or
        !std.mem.eql(u8, &actual.digest, &receipt_digest))
    {
        return error.InvalidCachedPayload;
    }
    try validateGenerationTreeNoReparse(allocator, io, generation, acl_policy);
}

fn validateGenerationTreeNoReparse(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
    acl_policy: CacheAclPolicy,
) !void {
    try enforceDirectoryAclPolicy(allocator, io, root, acl_policy);
    var walker = try root.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                var child = entry.dir.openDir(io, entry.basename, .{
                    .iterate = true,
                    .follow_symlinks = false,
                }) catch return error.InvalidV2CacheContainer;
                defer child.close(io);
                requireOrdinaryDirectory(io, child) catch return error.InvalidV2CacheContainer;
                try enforceDirectoryAclPolicy(allocator, io, child, acl_policy);
            },
            .file => {
                var file = entry.dir.openFile(io, entry.basename, .{
                    .path_only = true,
                    .allow_directory = false,
                    .follow_symlinks = false,
                    .resolve_beneath = true,
                }) catch return error.InvalidV2CacheContainer;
                defer file.close(io);
                if ((file.stat(io) catch return error.InvalidV2CacheContainer).kind != .file) {
                    return error.InvalidV2CacheContainer;
                }
                try enforceFileAclPolicy(
                    allocator,
                    io,
                    entry.dir,
                    entry.basename,
                    file.handle,
                    acl_policy,
                );
            },
            else => return error.InvalidV2CacheContainer,
        }
    }
}

fn validateTreeNoReparse(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
) !void {
    var walker = try root.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| switch (entry.kind) {
        .directory, .file => {},
        else => return error.InterruptedStageUnsafe,
    };
}

fn acquireCacheLock(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_root: std.Io.Dir,
) !std.Io.File {
    if (cache_root.createFile(io, ".lock", .{
        .read = true,
        .exclusive = true,
        .permissions = privateFilePermissions(),
    })) |created| {
        created.close(io);
    } else |err| switch (err) {
        error.PathAlreadyExists => {},
        error.IsDir => return error.InvalidCacheLock,
        else => |e| return e,
    }
    const lock = cache_root.openFile(io, ".lock", .{
        .mode = .read_write,
        .allow_directory = false,
        // Linux cannot apply flock/fcntl locks to an O_PATH descriptor;
        // Windows keeps the path-only handle because LockFileEx accepts it
        // and the ACL verifier needs the already-pinned identity.
        .path_only = builtin.os.tag == .windows,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch |err| switch (err) {
        error.IsDir => return error.InvalidCacheLock,
        else => |e| return e,
    };
    errdefer lock.close(io);
    const stat = try lock.stat(io);
    if (stat.kind != .file) {
        return error.InvalidCacheLock;
    }
    try ensureOwnerOnlyFileAcl(allocator, io, cache_root, ".lock", lock.handle);
    _ = try lockCacheFile(io, lock, .exclusive, false);
    return lock;
}

fn acquireReadOnlyCacheLock(
    io: std.Io,
    cache_root: std.Io.Dir,
) !std.Io.File {
    const lock = cache_root.openFile(io, ".lock", .{
        .mode = .read_only,
        .allow_directory = false,
        // See acquireCacheLock: POSIX flock requires a real file descriptor,
        // while the Windows path-only identity remains valid for LockFileEx.
        .path_only = builtin.os.tag == .windows,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch |err| switch (err) {
        error.IsDir => return error.InvalidCacheLock,
        else => |e| return e,
    };
    errdefer lock.close(io);
    const stat = try lock.stat(io);
    if (stat.kind != .file) return error.InvalidCacheLock;
    try verifyOwnerOnlyAcl(lock.handle, .file);
    _ = try lockCacheFile(io, lock, .shared, false);
    return lock;
}

fn lockCacheFile(
    io: std.Io,
    file: std.Io.File,
    mode: std.Io.File.Lock,
    nonblocking: bool,
) !bool {
    if (builtin.os.tag == .windows) {
        var overlapped: WindowsOverlapped = .{};
        var flags: u32 = if (nonblocking) lockfile_fail_immediately else 0;
        if (mode == .exclusive) flags |= lockfile_exclusive_lock;
        if (LockFileEx(file.handle, flags, 0, 1, 0, &overlapped) != 0) return true;
        const win32_error = GetLastError();
        if (nonblocking and win32_error == error_lock_violation) return false;
        if (!nonblocking and win32_error == error_io_pending) {
            var transferred: u32 = 0;
            if (GetOverlappedResult(file.handle, &overlapped, &transferred, 1) != 0) return true;
        }
        return error.CacheLockFailed;
    }
    if (nonblocking) return file.tryLock(io, mode);
    try file.lock(io, mode);
    return true;
}

fn openOrCreateRelativeDirectory(
    io: std.Io,
    root: std.Io.Dir,
    path: []const u8,
) !std.Io.Dir {
    var current = try root.openDir(io, ".", .{ .follow_symlinks = false });
    errdefer current.close(io);
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or
            std.mem.eql(u8, component, ".."))
        {
            return error.InvalidCacheRoot;
        }
        current.createDir(io, component, privateDirPermissions()) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => |e| return e,
        };
        var next = try current.openDir(io, component, .{
            .iterate = true,
            .follow_symlinks = false,
        });
        errdefer next.close(io);
        try requireOrdinaryDirectory(io, next);
        current.close(io);
        current = next;
    }
    return current;
}

fn openCacheRoot(
    io: std.Io,
    root: std.Io.Dir,
    path: []const u8,
    policy: CacheRootPolicy,
) !std.Io.Dir {
    if (std.Io.Dir.path.isAbsolute(path)) {
        if (policy == .create_or_open) {
            // An explicitly supplied absolute root is useful for CI caches
            // whose parent is owned by the runner account rather than the
            // checkout service. The cache root itself is still opened without
            // reparse following and is secured/verified by the caller.
            std.Io.Dir.cwd().createDirPath(io, path) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => |e| return e,
            };
        }
        return std.Io.Dir.openDirAbsolute(io, path, .{
            .iterate = true,
            .follow_symlinks = false,
        });
    }
    return switch (policy) {
        .create_or_open => openOrCreateRelativeDirectory(io, root, path),
        .existing_only => openExistingRelativeDirectory(io, root, path),
    };
}

fn validateCacheRootPath(path: []const u8) !void {
    if (path.len == 0 or path.len > 4096 or !std.unicode.utf8ValidateSlice(path)) {
        return error.InvalidCacheRoot;
    }
    if (!std.Io.Dir.path.isAbsolute(path)) {
        deps.validateArchivePath(path) catch return error.InvalidCacheRoot;
        return;
    }
    if (path[path.len - 1] == '/' or path[path.len - 1] == '\\') {
        return error.InvalidCacheRoot;
    }

    const drive_prefix = path.len >= 2 and
        ((path[0] >= 'a' and path[0] <= 'z') or (path[0] >= 'A' and path[0] <= 'Z')) and
        path[1] == ':';
    var component_start: usize = if (drive_prefix) 2 else 0;
    var index: usize = 0;
    while (index < path.len) : (index += 1) {
        const byte = path[index];
        if (byte < 0x20 or byte == 0x7f or byte == '"' or byte == '*' or
            byte == '?' or byte == '<' or byte == '>' or byte == '|')
        {
            return error.InvalidCacheRoot;
        }
        if (byte == ':' and !(drive_prefix and index == 1)) {
            // Reject alternate data streams and malformed drive prefixes.
            return error.InvalidCacheRoot;
        }
        if (byte != '/' and byte != '\\') continue;
        if (index > component_start) {
            const component = path[component_start..index];
            if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) {
                return error.InvalidCacheRoot;
            }
        }
        component_start = index + 1;
    }
    if (component_start >= path.len or
        std.mem.eql(u8, path[component_start..], ".") or
        std.mem.eql(u8, path[component_start..], ".."))
    {
        return error.InvalidCacheRoot;
    }
}

fn openExistingRelativeDirectory(
    io: std.Io,
    root: std.Io.Dir,
    path: []const u8,
) !std.Io.Dir {
    var current = try root.openDir(io, ".", .{ .follow_symlinks = false });
    errdefer current.close(io);
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or
            std.mem.eql(u8, component, ".."))
        {
            return error.InvalidCacheRoot;
        }
        var next = try current.openDir(io, component, .{
            .iterate = true,
            .follow_symlinks = false,
        });
        errdefer next.close(io);
        try requireOrdinaryDirectory(io, next);
        current.close(io);
        current = next;
    }
    return current;
}

fn requireOrdinaryDirectory(io: std.Io, dir: std.Io.Dir) !void {
    const stat = try dir.stat(io);
    if (stat.kind != .directory) return error.CacheReparsePoint;
}

fn privateDirPermissions() std.Io.Dir.Permissions {
    return if (builtin.os.tag == .windows) .default_dir else .fromMode(0o700);
}

fn privateFilePermissions() std.Io.Dir.Permissions {
    return if (builtin.os.tag == .windows) .default_file else .fromMode(0o600);
}

fn isLowerSha256(value: []const u8) bool {
    if (value.len != 64) return false;
    for (value) |byte| {
        if (!std.ascii.isDigit(byte) and !(byte >= 'a' and byte <= 'f')) return false;
    }
    return true;
}

const AclTarget = enum {
    directory,
    file,
};

const dacl_security_information: u32 = 0x0000_0004;
const owner_security_information: u32 = 0x0000_0001;
const protected_dacl_security_information: u32 = 0x8000_0000;
const se_file_object: u32 = 1;
const se_dacl_protected: u16 = 0x1000;
const access_allowed_ace_type: u8 = 0;
const object_inherit_ace: u8 = 0x01;
const container_inherit_ace: u8 = 0x02;
const file_all_access: u32 = 0x001f_01ff;
// FILE_GENERIC_READ | FILE_GENERIC_EXECUTE. The explicit OWNER RIGHTS ACE
// suppresses the object's otherwise-implicit owner WRITE_DAC right.
// Exact mask produced by the reviewed SDDL token "FRGX".
const owner_rights_read_execute_access: u32 = 0x0012_00a9;
const win_creator_owner_rights_sid: u32 = 71;
const win_builtin_users_sid: u32 = 27;
const token_query: u32 = 0x0008;
const token_user_information_class: u32 = 1;

const AclSizeInformation = extern struct {
    ace_count: u32,
    acl_bytes_in_use: u32,
    acl_bytes_free: u32,
};

const AceHeader = extern struct {
    ace_type: u8,
    ace_flags: u8,
    ace_size: u16,
};

const AccessAllowedAce = extern struct {
    header: AceHeader,
    mask: u32,
    sid_start: u32,
};

fn aclControlIsProtected(control: u16) bool {
    return control & se_dacl_protected != 0;
}

/// Fingerprints the owner and DACL fields read directly from an already-open
/// handle. Audit integration snapshots use this to detect ACL-only mutation.
pub fn aclFingerprint(handle: std.Io.File.Handle) ![32]u8 {
    var digest = [_]u8{0} ** 32;
    if (builtin.os.tag != .windows) return digest;

    var owner: ?*anyopaque = null;
    var reported_dacl: ?*anyopaque = null;
    var descriptor: ?*anyopaque = null;
    if (GetSecurityInfo(
        handle,
        se_file_object,
        owner_security_information | dacl_security_information,
        &owner,
        null,
        &reported_dacl,
        null,
        &descriptor,
    ) != 0 or descriptor == null or owner == null) {
        return error.AclFingerprintFailed;
    }
    defer _ = LocalFree(descriptor);
    if (IsValidSecurityDescriptor(descriptor.?) == 0 or IsValidSid(owner.?) == 0) {
        return error.AclFingerprintFailed;
    }

    var control: u16 = 0;
    var revision: u32 = 0;
    if (GetSecurityDescriptorControl(descriptor.?, &control, &revision) == 0) {
        return error.AclFingerprintFailed;
    }
    var dacl_present: i32 = 0;
    var dacl: ?*anyopaque = null;
    var dacl_defaulted: i32 = 0;
    if (GetSecurityDescriptorDacl(
        descriptor.?,
        &dacl_present,
        &dacl,
        &dacl_defaulted,
    ) == 0 or reported_dacl != dacl) {
        return error.AclFingerprintFailed;
    }

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("texflow-cache-acl-v1\x00");
    hasher.update(std.mem.asBytes(&control));
    hasher.update(std.mem.asBytes(&revision));
    hasher.update(std.mem.asBytes(&dacl_present));
    hasher.update(std.mem.asBytes(&dacl_defaulted));
    const owner_bytes = @as([*]const u8, @ptrCast(owner.?))[0..GetLengthSid(owner.?)];
    const owner_length: u32 = @intCast(owner_bytes.len);
    hasher.update(std.mem.asBytes(&owner_length));
    hasher.update(owner_bytes);
    if (dacl_present != 0) {
        if (dacl == null or IsValidAcl(dacl.?) == 0) return error.AclFingerprintFailed;
        var acl_info: AclSizeInformation = undefined;
        if (GetAclInformation(
            dacl.?,
            &acl_info,
            @sizeOf(AclSizeInformation),
            2,
        ) == 0) {
            return error.AclFingerprintFailed;
        }
        hasher.update(std.mem.asBytes(&acl_info.ace_count));
        hasher.update(std.mem.asBytes(&acl_info.acl_bytes_in_use));
        const acl_bytes = @as([*]const u8, @ptrCast(dacl.?))[0..acl_info.acl_bytes_in_use];
        hasher.update(acl_bytes);
    }
    hasher.final(&digest);
    return digest;
}

/// Verifies the exact OWNER RIGHTS read/execute DACL used for published cache
/// objects. This narrow read-only oracle is exposed for integration fixtures;
/// production validation continues to select the policy internally.
pub fn verifyOwnerRightsReadExecuteAcl(
    handle: std.Io.File.Handle,
    directory: bool,
) !void {
    if (builtin.os.tag != .windows) return;
    try verifyOwnerOnlyAclExact(
        handle,
        if (directory) .directory else .file,
        owner_rights_read_execute_access,
    );
}

fn verifyOwnerOnlyAcl(handle: std.Io.File.Handle, target: AclTarget) !void {
    return verifyOwnerOnlyAclMasks(
        handle,
        target,
        &.{ file_all_access, owner_rights_read_execute_access },
    );
}

fn verifyOwnerOnlyAclExact(
    handle: anytype,
    target: AclTarget,
    expected_mask: u32,
) !void {
    return verifyOwnerOnlyAclMasks(handle, target, &.{expected_mask});
}

fn verifyTreeAclExact(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
    expected_mask: u32,
) !void {
    return verifyTreeAclPolicy(allocator, io, root, expected_mask, .protected_only);
}

const AclProtectionPolicy = enum { protected_only, mutable_stage_descendant };

fn verifyTreeAclPolicy(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
    expected_mask: u32,
    descendant_policy: AclProtectionPolicy,
) !void {
    if (builtin.os.tag != .windows) return;
    try requireOrdinaryDirectory(io, root);
    try verifyOwnerOnlyAclExact(root.handle, .directory, expected_mask);
    var walker = try root.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        var identity = try entry.dir.openFile(io, entry.basename, .{
            .path_only = true,
            .allow_directory = true,
            .follow_symlinks = false,
            .resolve_beneath = true,
        });
        defer identity.close(io);
        const target: AclTarget = switch ((try identity.stat(io)).kind) {
            .file => .file,
            .directory => .directory,
            else => return error.InvalidV2CacheContainer,
        };
        try verifyOwnerOnlyAclMasksPolicy(identity.handle, target, &.{expected_mask}, descendant_policy);
    }
}

fn verifyOwnerOnlyAclMasks(
    handle: anytype,
    target: AclTarget,
    allowed_masks: []const u32,
) !void {
    return verifyOwnerOnlyAclMasksPolicy(handle, target, allowed_masks, .protected_only);
}

fn verifyOwnerOnlyAclMasksPolicy(
    handle: anytype,
    target: AclTarget,
    allowed_masks: []const u32,
    protection_policy: AclProtectionPolicy,
) !void {
    if (builtin.os.tag != .windows) return;

    var owner: ?*anyopaque = null;
    var reported_dacl: ?*anyopaque = null;
    var descriptor: ?*anyopaque = null;
    if (GetSecurityInfo(
        handle,
        se_file_object,
        owner_security_information | dacl_security_information,
        &owner,
        null,
        &reported_dacl,
        null,
        &descriptor,
    ) != 0 or descriptor == null or owner == null) {
        return error.OwnerOnlyAclVerificationFailed;
    }
    defer _ = LocalFree(descriptor);
    if (IsValidSecurityDescriptor(descriptor.?) == 0) {
        return error.OwnerOnlyAclVerificationFailed;
    }
    if (!ownerSidMatchesCurrentToken(owner.?)) {
        return error.OwnerOnlyAclVerificationFailed;
    }

    var control: u16 = 0;
    var revision: u32 = 0;
    if (GetSecurityDescriptorControl(descriptor.?, &control, &revision) == 0) {
        return error.OwnerOnlyAclVerificationFailed;
    }
    const protected = aclControlIsProtected(control);
    if (!protected and protection_policy == .protected_only) return error.OwnerOnlyAclVerificationFailed;

    var dacl_present: i32 = 0;
    var dacl: ?*anyopaque = null;
    var dacl_defaulted: i32 = 0;
    if (GetSecurityDescriptorDacl(
        descriptor.?,
        &dacl_present,
        &dacl,
        &dacl_defaulted,
    ) == 0 or dacl_present == 0 or dacl == null or dacl_defaulted != 0 or
        reported_dacl == null or reported_dacl.? != dacl.? or IsValidAcl(dacl.?) == 0)
    {
        return error.OwnerOnlyAclVerificationFailed;
    }

    var acl_info: AclSizeInformation = undefined;
    if (GetAclInformation(
        dacl.?,
        &acl_info,
        @sizeOf(AclSizeInformation),
        2,
    ) == 0 or acl_info.ace_count != 1) {
        return error.OwnerOnlyAclVerificationFailed;
    }

    var ace_ptr: ?*anyopaque = null;
    if (GetAce(dacl.?, 0, &ace_ptr) == 0 or ace_ptr == null) {
        return error.OwnerOnlyAclVerificationFailed;
    }
    const ace: *const AccessAllowedAce = @ptrCast(@alignCast(ace_ptr.?));
    const inherited_ace: u8 = 0x10;
    // The only unprotected form admitted is a construction descendant's
    // inherited full OWNER RIGHTS ACE. Inheritance never permits an RX grant,
    // an explicit unprotected ACL, an extra trustee, or a different owner.
    if (!protected and (ace.mask != file_all_access or
        ace.header.ace_flags & inherited_ace == 0))
    {
        return error.OwnerOnlyAclVerificationFailed;
    }
    const allowed_flags = object_inherit_ace | container_inherit_ace | inherited_ace;
    const flags_valid = switch (target) {
        .directory => ace.header.ace_flags & (object_inherit_ace | container_inherit_ace) ==
            object_inherit_ace | container_inherit_ace and
            ace.header.ace_flags & ~allowed_flags == 0,
        .file => ace.header.ace_flags & ~allowed_flags == 0,
    };
    const sid_offset: u16 = @intCast(@offsetOf(AccessAllowedAce, "sid_start"));
    const minimum_sid_size: u16 = 8;
    var mask_allowed = false;
    for (allowed_masks) |allowed_mask| {
        if (ace.mask == allowed_mask) {
            mask_allowed = true;
            break;
        }
    }
    if (ace.header.ace_type != access_allowed_ace_type or
        !flags_valid or
        ace.header.ace_size < sid_offset + minimum_sid_size or
        !mask_allowed)
    {
        return error.OwnerOnlyAclVerificationFailed;
    }

    const sid: *const anyopaque = @ptrCast(&ace.sid_start);
    if (IsValidSid(sid) == 0 or
        IsWellKnownSid(sid, win_creator_owner_rights_sid) == 0 or
        @as(u32, ace.header.ace_size) != @as(u32, sid_offset) + GetLengthSid(sid))
    {
        return error.OwnerOnlyAclVerificationFailed;
    }
}

const SidAndAttributes = extern struct {
    sid: *anyopaque,
    attributes: u32,
};

const TokenUser = extern struct {
    user: SidAndAttributes,
};

fn ownerSidMatchesCurrentToken(owner: *const anyopaque) bool {
    if (builtin.os.tag != .windows) return true;
    var token: std.os.windows.HANDLE = undefined;
    if (OpenProcessToken(GetCurrentProcess(), token_query, &token) == 0) return false;
    defer std.os.windows.CloseHandle(token);
    var buffer: [256]u8 align(@alignOf(TokenUser)) = undefined;
    var required: u32 = 0;
    if (GetTokenInformation(
        token,
        token_user_information_class,
        &buffer,
        buffer.len,
        &required,
    ) == 0 or required > buffer.len) {
        return false;
    }
    const token_user: *const TokenUser = @ptrCast(@alignCast(&buffer));
    return IsValidSid(token_user.user.sid) != 0 and EqualSid(owner, token_user.user.sid) != 0;
}

fn applyOwnerOnlyAcl(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
) !void {
    if (builtin.os.tag != .windows) return;
    try setAclFromSddl(
        allocator,
        io,
        dir,
        ".",
        std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;OICI;FA;;;OW)"),
    );
    try verifyOwnerOnlyAcl(dir.handle, .directory);
}

fn setOwnerRightsAclByHandle(
    handle: std.os.windows.HANDLE,
    target: AclTarget,
    mode: OwnerRightsAclMode,
) !void {
    if (builtin.os.tag != .windows) return;
    const sddl = switch (mode) {
        .full => switch (target) {
            .directory => std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;OICI;FA;;;OW)"),
            .file => std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;;FA;;;OW)"),
        },
        .read_execute => switch (target) {
            .directory => std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;OICI;FRGX;;;OW)"),
            .file => std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;;FRGX;;;OW)"),
        },
    };
    var descriptor: ?*anyopaque = null;
    if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
        sddl,
        1,
        &descriptor,
        null,
    ) == 0 or descriptor == null) return error.OwnerOnlyAclFailed;
    defer _ = LocalFree(descriptor);
    var dacl_present: i32 = 0;
    var dacl: ?*anyopaque = null;
    var dacl_defaulted: i32 = 0;
    if (GetSecurityDescriptorDacl(
        descriptor.?,
        &dacl_present,
        &dacl,
        &dacl_defaulted,
    ) == 0 or dacl_present == 0 or dacl == null) {
        return error.OwnerOnlyAclFailed;
    }
    // SetSecurityInfo accepts the DACL but silently drops the protected bit on
    // Windows file handles. NtSetSecurityObject consumes the same self-relative
    // descriptor and preserves PROTECTED_DACL_SECURITY_INFORMATION while using
    // the already-pinned handle, so neither a path lookup nor a second open can
    // race the freeze. The handle was opened with WRITE_DAC and retains that
    // granted right even after the OWNER RIGHTS DACL becomes read/execute.
    const status = NtSetSecurityObject(
        handle,
        dacl_security_information | protected_dacl_security_information,
        descriptor.?,
    );
    if (status != .SUCCESS) {
        return error.OwnerOnlyAclFailed;
    }
}

fn ensureOwnerOnlyAcl(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
) !void {
    verifyOwnerOnlyAcl(dir.handle, .directory) catch |err| switch (err) {
        error.OwnerOnlyAclVerificationFailed => try applyOwnerOnlyAcl(allocator, io, dir),
        else => |e| return e,
    };
}

fn ensureOwnerOnlyFileAcl(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    path: []const u8,
    handle: std.Io.File.Handle,
) !void {
    if (builtin.os.tag != .windows) return;
    verifyOwnerOnlyAcl(handle, .file) catch |err| switch (err) {
        error.OwnerOnlyAclVerificationFailed => {
            try setAclFromSddl(
                allocator,
                io,
                dir,
                path,
                std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;;FA;;;OW)"),
            );
            try verifyOwnerOnlyAcl(handle, .file);
        },
        else => |e| return e,
    };
}

fn enforceDirectoryAclPolicy(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    policy: CacheAclPolicy,
) !void {
    switch (policy) {
        .secure_and_verify => try ensureOwnerOnlyAcl(allocator, io, dir),
        .verify_only => try verifyOwnerOnlyAcl(dir.handle, .directory),
    }
}

fn enforceFileAclPolicy(
    allocator: std.mem.Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    name: []const u8,
    handle: std.Io.File.Handle,
    policy: CacheAclPolicy,
) !void {
    switch (policy) {
        .secure_and_verify => try ensureOwnerOnlyFileAcl(allocator, io, parent, name, handle),
        .verify_only => try verifyOwnerOnlyAcl(handle, .file),
    }
}

fn setAclFromSddl(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    path: []const u8,
    sddl: [*:0]const u16,
) !void {
    const absolute = try dir.realPathFileAlloc(io, path, allocator);
    defer allocator.free(absolute);
    const path_w = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, absolute);
    defer allocator.free(path_w);
    var descriptor: ?*anyopaque = null;
    if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
        sddl,
        1,
        &descriptor,
        null,
    ) == 0) return error.OwnerOnlyAclFailed;
    defer _ = LocalFree(descriptor);
    const set_result = SetFileSecurityW(
        path_w,
        dacl_security_information | protected_dacl_security_information,
        descriptor.?,
    );
    if (set_result == 0) {
        return error.OwnerOnlyAclFailed;
    }
}

extern "advapi32" fn ConvertStringSecurityDescriptorToSecurityDescriptorW(
    string_security_descriptor: [*:0]const u16,
    string_sd_revision: u32,
    security_descriptor: *?*anyopaque,
    security_descriptor_size: ?*u32,
) callconv(.winapi) i32;

extern "advapi32" fn SetFileSecurityW(
    file_name: [*:0]const u16,
    security_information: u32,
    security_descriptor: *anyopaque,
) callconv(.winapi) i32;

extern "advapi32" fn SetNamedSecurityInfoW(
    object_name: [*:0]u16,
    object_type: u32,
    security_information: u32,
    owner: ?*anyopaque,
    group: ?*anyopaque,
    dacl: ?*anyopaque,
    sacl: ?*anyopaque,
) callconv(.winapi) u32;

extern "ntdll" fn NtSetSecurityObject(
    handle: std.os.windows.HANDLE,
    security_information: u32,
    security_descriptor: *anyopaque,
) callconv(.winapi) std.os.windows.NTSTATUS;

extern "advapi32" fn SetSecurityInfo(
    handle: std.os.windows.HANDLE,
    object_type: u32,
    security_information: u32,
    owner: ?*anyopaque,
    group: ?*anyopaque,
    dacl: ?*anyopaque,
    sacl: ?*anyopaque,
) callconv(.winapi) u32;

extern "kernel32" fn GetFinalPathNameByHandleW(
    handle: std.os.windows.HANDLE,
    path: [*]u16,
    path_capacity: u32,
    flags: u32,
) callconv(.winapi) u32;

extern "advapi32" fn GetSecurityInfo(
    handle: std.os.windows.HANDLE,
    object_type: u32,
    security_information: u32,
    owner: ?*?*anyopaque,
    group: ?*?*anyopaque,
    dacl: ?*?*anyopaque,
    sacl: ?*?*anyopaque,
    security_descriptor: *?*anyopaque,
) callconv(.winapi) u32;

extern "advapi32" fn IsValidSecurityDescriptor(
    security_descriptor: *anyopaque,
) callconv(.winapi) i32;

extern "advapi32" fn GetSecurityDescriptorControl(
    security_descriptor: *anyopaque,
    control: *u16,
    revision: *u32,
) callconv(.winapi) i32;

extern "advapi32" fn GetSecurityDescriptorDacl(
    security_descriptor: *anyopaque,
    dacl_present: *i32,
    dacl: *?*anyopaque,
    dacl_defaulted: *i32,
) callconv(.winapi) i32;

extern "advapi32" fn IsValidAcl(acl: *anyopaque) callconv(.winapi) i32;

extern "advapi32" fn GetAclInformation(
    acl: *anyopaque,
    acl_information: *anyopaque,
    acl_information_length: u32,
    acl_information_class: u32,
) callconv(.winapi) i32;

extern "advapi32" fn GetAce(
    acl: *anyopaque,
    ace_index: u32,
    ace: *?*anyopaque,
) callconv(.winapi) i32;

extern "advapi32" fn IsValidSid(sid: *const anyopaque) callconv(.winapi) i32;

extern "advapi32" fn IsWellKnownSid(
    sid: *const anyopaque,
    sid_type: u32,
) callconv(.winapi) i32;

extern "advapi32" fn GetLengthSid(sid: *const anyopaque) callconv(.winapi) u32;

extern "advapi32" fn CreateWellKnownSid(
    sid_type: u32,
    domain_sid: ?*const anyopaque,
    sid: *anyopaque,
    sid_size: *u32,
) callconv(.winapi) i32;

extern "advapi32" fn EqualSid(
    first: *const anyopaque,
    second: *const anyopaque,
) callconv(.winapi) i32;

extern "advapi32" fn OpenProcessToken(
    process: std.os.windows.HANDLE,
    desired_access: u32,
    token: *std.os.windows.HANDLE,
) callconv(.winapi) i32;

extern "advapi32" fn GetTokenInformation(
    token: std.os.windows.HANDLE,
    information_class: u32,
    information: *anyopaque,
    information_length: u32,
    return_length: *u32,
) callconv(.winapi) i32;

extern "kernel32" fn LocalFree(memory: ?*anyopaque) callconv(.winapi) ?*anyopaque;

extern "kernel32" fn GetCurrentProcess() callconv(.winapi) std.os.windows.HANDLE;

const WindowsOverlapped = extern struct {
    internal: usize = 0,
    internal_high: usize = 0,
    offset: u32 = 0,
    offset_high: u32 = 0,
    event: ?std.os.windows.HANDLE = null,
};

const lockfile_fail_immediately: u32 = 0x00000001;
const lockfile_exclusive_lock: u32 = 0x00000002;
const error_lock_violation: u32 = 33;
const error_io_pending: u32 = 997;

extern "kernel32" fn LockFileEx(
    file: std.os.windows.HANDLE,
    flags: u32,
    reserved: u32,
    bytes_low: u32,
    bytes_high: u32,
    overlapped: *WindowsOverlapped,
) callconv(.winapi) i32;

extern "kernel32" fn GetLastError() callconv(.winapi) u32;

extern "kernel32" fn GetOverlappedResult(
    file: std.os.windows.HANDLE,
    overlapped: *WindowsOverlapped,
    transferred: *u32,
    wait: i32,
) callconv(.winapi) i32;

test "redirect status allowlist is exact" {
    try std.testing.expect(isAllowedRedirect(.moved_permanently));
    try std.testing.expect(isAllowedRedirect(.permanent_redirect));
    try std.testing.expect(!isAllowedRedirect(.not_modified));
    try std.testing.expect(!isAllowedRedirect(.use_proxy));
}

test "cache receipts accept lowercase SHA-256 only" {
    try std.testing.expect(isLowerSha256(
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    ));
    try std.testing.expect(!isLowerSha256(
        "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF",
    ));
}

test "cache root path accepts a safe absolute runner path" {
    const path = if (builtin.os.tag == .windows)
        "C:\\Users\\runner\\TExFlow-native-deps"
    else
        "/tmp/TExFlow-native-deps";
    try validateCacheRootPath(path);
}

test "cache root path rejects traversal and root-only paths" {
    const traversal = if (builtin.os.tag == .windows)
        "C:\\Users\\runner\\..\\TExFlow-native-deps"
    else
        "/tmp/../TExFlow-native-deps";
    const trailing = if (builtin.os.tag == .windows)
        "C:\\Users\\runner\\TExFlow-native-deps\\"
    else
        "/tmp/TExFlow-native-deps/";
    try std.testing.expectError(error.InvalidCacheRoot, validateCacheRootPath(traversal));
    try std.testing.expectError(error.InvalidCacheRoot, validateCacheRootPath(trailing));
}

test "audit mode policy is strictly read only" {
    const policy = policyForMode(.audit);
    try std.testing.expectEqual(CacheRootPolicy.existing_only, policy.cache_root);
    try std.testing.expectEqual(CacheAclPolicy.verify_only, policy.cache_acl);
    try std.testing.expectEqual(CacheLockPolicy.shared_existing, policy.cache_lock);
    try std.testing.expectEqual(InterruptedStagePolicy.reject, policy.interrupted_stages);
}

test "export mode policies are strictly read only" {
    for ([_]Mode{ .export_ucd, .export_zigwin32, .export_attestation_inputs }) |mode| {
        const policy = policyForMode(mode);
        try std.testing.expectEqual(CacheRootPolicy.existing_only, policy.cache_root);
        try std.testing.expectEqual(CacheAclPolicy.verify_only, policy.cache_acl);
        try std.testing.expectEqual(CacheLockPolicy.shared_existing, policy.cache_lock);
        try std.testing.expectEqual(InterruptedStagePolicy.reject, policy.interrupted_stages);
    }
}

test "fetch mode policies may prepare and lock the cache" {
    for ([_]Mode{ .bootstrap, .all }) |mode| {
        const policy = policyForMode(mode);
        try std.testing.expectEqual(CacheRootPolicy.create_or_open, policy.cache_root);
        try std.testing.expectEqual(CacheAclPolicy.secure_and_verify, policy.cache_acl);
        try std.testing.expectEqual(CacheLockPolicy.exclusive_create, policy.cache_lock);
        try std.testing.expectEqual(InterruptedStagePolicy.clean_safe, policy.interrupted_stages);
    }
}

test "audit refuses a stale stage without deleting it" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "cache", privateDirPermissions());
    var cache = try tmp.dir.openDir(io, "cache", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer cache.close(io);
    try cache.createDir(io, ".stage-interrupted", privateDirPermissions());
    var stage = try cache.openDir(io, ".stage-interrupted", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    var sentinel = try stage.createFile(io, "sentinel", .{
        .exclusive = true,
        .permissions = privateFilePermissions(),
    });
    sentinel.close(io);
    stage.close(io);

    try std.testing.expectError(
        error.InterruptedStagePresent,
        handleInterruptedStages(
            std.testing.allocator,
            io,
            cache,
            policyForMode(.audit).interrupted_stages,
        ),
    );

    var retained = try cache.openDir(io, ".stage-interrupted", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer retained.close(io);
    var retained_sentinel = try retained.openFile(io, "sentinel", .{
        .follow_symlinks = false,
    });
    retained_sentinel.close(io);
}

test "fetch cleanup removes a reparse-free interrupted stage" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDir(io, ".stage-interrupted", privateDirPermissions());
    var stage = try tmp.dir.openDir(io, ".stage-interrupted", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    var sentinel = try stage.createFile(io, "sentinel", .{
        .exclusive = true,
        .permissions = privateFilePermissions(),
    });
    sentinel.close(io);
    stage.close(io);

    try handleInterruptedStages(
        std.testing.allocator,
        io,
        tmp.dir,
        policyForMode(.all).interrupted_stages,
    );
    try std.testing.expectError(
        error.FileNotFound,
        tmp.dir.openDir(io, ".stage-interrupted", .{ .follow_symlinks = false }),
    );
}

test "audit retains and fetch cleans an interrupted selector publication" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try applyOwnerOnlyAcl(std.testing.allocator, io, tmp.dir);
    var store = try openOrCreateV2ArtifactStore(
        std.testing.allocator,
        io,
        tmp.dir,
        "artifact",
    );
    defer store.close(io);
    var interrupted = try store.artifact.createFile(io, ".stage-current-deadbeef", .{
        .exclusive = true,
        .permissions = privateFilePermissions(),
    });
    interrupted.close(io);

    try std.testing.expectError(
        error.InterruptedStagePresent,
        handleInterruptedStages(
            std.testing.allocator,
            io,
            tmp.dir,
            policyForMode(.audit).interrupted_stages,
        ),
    );
    var retained = try store.artifact.openFile(io, ".stage-current-deadbeef", .{
        .follow_symlinks = false,
    });
    retained.close(io);

    try handleInterruptedStages(
        std.testing.allocator,
        io,
        tmp.dir,
        policyForMode(.all).interrupted_stages,
    );
    try std.testing.expectError(
        error.FileNotFound,
        store.artifact.openFile(io, ".stage-current-deadbeef", .{
            .follow_symlinks = false,
        }),
    );
}

test "audit refuses a missing cache root without creating ancestors" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.testing.expectError(
        error.FileNotFound,
        openCacheRoot(io, tmp.dir, "missing/cache", policyForMode(.audit).cache_root),
    );
    try std.testing.expectError(
        error.FileNotFound,
        tmp.dir.openDir(io, "missing", .{ .follow_symlinks = false }),
    );
}

test "ACL verifier policy requires DACL protection" {
    try std.testing.expect(!aclControlIsProtected(0));
    try std.testing.expect(aclControlIsProtected(se_dacl_protected));
}

test "Windows cache owner predicate rejects a known group SID" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var sid_buffer: [128]u8 align(@alignOf(usize)) = undefined;
    var sid_size: u32 = sid_buffer.len;
    if (CreateWellKnownSid(
        win_builtin_users_sid,
        null,
        &sid_buffer,
        &sid_size,
    ) == 0) {
        return error.GroupSidCreationFailed;
    }
    try std.testing.expect(!ownerSidMatchesCurrentToken(@ptrCast(&sid_buffer)));
}

test "Windows ACL verifier rejects additional trustees" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try setAclFromSddl(
        std.testing.allocator,
        io,
        tmp.dir,
        ".",
        std.unicode.utf8ToUtf16LeStringLiteral(
            "D:P(A;OICI;FA;;;OW)(A;OICI;FR;;;WD)",
        ),
    );
    try std.testing.expectError(
        error.OwnerOnlyAclVerificationFailed,
        verifyOwnerOnlyAcl(tmp.dir.handle, .directory),
    );
}

test "mutable stage inheritance keeps strict root and descendant ACL boundaries" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try applyOwnerOnlyAcl(std.testing.allocator, io, tmp.dir);
    try tmp.dir.createDir(io, "payload", privateDirPermissions());
    var payload = try tmp.dir.openDir(io, "payload", .{ .iterate = true, .follow_symlinks = false });
    defer payload.close(io);
    var file = try payload.createFile(io, "data.bin", .{ .exclusive = true });
    file.close(io);
    const pinned_file = try openPinnedStageChildWindows(std.testing.allocator, payload, "data.bin", .file);
    defer std.os.windows.CloseHandle(pinned_file);
    try verifyTreeAclPolicy(std.testing.allocator, io, tmp.dir, file_all_access, .mutable_stage_descendant);
    // The same inherited directory can never serve as a mutable stage root.
    try std.testing.expectError(error.OwnerOnlyAclVerificationFailed, verifyTreeAclPolicy(
        std.testing.allocator,
        io,
        payload,
        file_all_access,
        .mutable_stage_descendant,
    ));
    try std.testing.expectError(error.OwnerOnlyAclVerificationFailed, verifyTreeAclExact(
        std.testing.allocator,
        io,
        tmp.dir,
        file_all_access,
    ));
    inline for (.{
        std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;;FRGX;;;OW)"),
        std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;;FA;;;OW)(A;;GR;;;WD)"),
        std.unicode.utf8ToUtf16LeStringLiteral("D:P(A;IO;FA;;;OW)"),
    }) |unsafe_acl| {
        try setAclFromSddl(std.testing.allocator, io, payload, "data.bin", unsafe_acl);
        try std.testing.expectError(error.OwnerOnlyAclVerificationFailed, verifyOwnerOnlyAclMasksPolicy(
            pinned_file,
            .file,
            &.{file_all_access},
            .mutable_stage_descendant,
        ));
        try setOwnerRightsAclByHandle(pinned_file, .file, .full);
    }
}

test "Windows cache lock has a protected owner-only file DACL" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try applyOwnerOnlyAcl(std.testing.allocator, io, tmp.dir);

    var lock = try acquireCacheLock(std.testing.allocator, io, tmp.dir);
    defer lock.close(io);
    const stat = try lock.stat(io);
    try std.testing.expectEqual(std.Io.File.Kind.file, stat.kind);
    try verifyOwnerOnlyAcl(lock.handle, .file);
}

test "frozen stage uses exact OWNER RIGHTS read execute ACLs and denies new writers" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try applyOwnerOnlyAcl(std.testing.allocator, io, tmp.dir);
    var stage = try createPinnedStageDirectory(
        std.testing.allocator,
        io,
        tmp.dir,
        ".stage-freeze-test",
    );
    defer stage.close(io);
    var file = try stage.createFile(io, "archive.bin", .{ .exclusive = true });
    try ensureOwnerOnlyFileAcl(std.testing.allocator, io, stage, "archive.bin", file.handle);
    file.close(io);
    try stage.createDir(io, "payload", privateDirPermissions());
    var payload = try stage.openDir(io, "payload", .{ .iterate = true, .follow_symlinks = false });
    var payload_file = try payload.createFile(io, "data.bin", .{ .exclusive = true });
    try ensureOwnerOnlyFileAcl(std.testing.allocator, io, payload, "data.bin", payload_file.handle);
    payload_file.close(io);
    payload.close(io);
    var receipt = try stage.createFile(io, ".complete.json", .{ .exclusive = true });
    try receipt.writeStreamingAll(io, "{}\n");
    receipt.close(io);
    try validateGenerationTreeNoReparse(std.testing.allocator, io, stage, .secure_and_verify);
    try validateGenerationTreeNoReparse(std.testing.allocator, io, stage, .secure_and_verify);

    var frozen = try freezeAndPinStagedTree(std.testing.allocator, io, stage, .{});
    defer frozen.deinit();
    try verifyOwnerOnlyAclExact(
        stage.handle,
        .directory,
        owner_rights_read_execute_access,
    );
    var reopened_stage = try tmp.dir.openDir(io, ".stage-freeze-test", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer reopened_stage.close(io);
    try verifyOwnerOnlyAclExact(
        reopened_stage.handle,
        .directory,
        owner_rights_read_execute_access,
    );
    var reopened_archive = try tmp.dir.openFile(io, ".stage-freeze-test/archive.bin", .{
        .mode = .read_only,
        .follow_symlinks = false,
    });
    defer reopened_archive.close(io);
    try verifyOwnerOnlyAclExact(
        reopened_archive.handle,
        .file,
        owner_rights_read_execute_access,
    );
    try std.testing.expectError(
        error.AccessDenied,
        tmp.dir.createFile(io, ".stage-freeze-test/unexpected", .{ .exclusive = true }),
    );
    try std.testing.expectError(
        error.AccessDenied,
        tmp.dir.openFile(io, ".stage-freeze-test/archive.bin", .{
            .mode = .read_write,
            .follow_symlinks = false,
        }),
    );
    try frozen.restoreFull();
    try verifyOwnerOnlyAclExact(stage.handle, .directory, file_all_access);
}

test "ensuring an already-secure cache directory does not rewrite metadata" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try applyOwnerOnlyAcl(std.testing.allocator, io, tmp.dir);
    const before = try tmp.dir.stat(io);
    try ensureOwnerOnlyAcl(std.testing.allocator, io, tmp.dir);
    const after = try tmp.dir.stat(io);
    try std.testing.expectEqual(before.inode, after.inode);
    try std.testing.expectEqual(before.mtime, after.mtime);
    try std.testing.expectEqual(before.ctime, after.ctime);
}

test "cache lock rejects a directory without replacing it" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try applyOwnerOnlyAcl(std.testing.allocator, io, tmp.dir);
    try tmp.dir.createDir(io, ".lock", privateDirPermissions());

    try std.testing.expectError(
        error.InvalidCacheLock,
        acquireCacheLock(std.testing.allocator, io, tmp.dir),
    );
    var retained = try tmp.dir.openDir(io, ".lock", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    retained.close(io);
}

test "read-only cache lock refuses a missing lock without creating it" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try applyOwnerOnlyAcl(std.testing.allocator, io, tmp.dir);

    try std.testing.expectError(
        error.FileNotFound,
        acquireReadOnlyCacheLock(io, tmp.dir),
    );
    try std.testing.expectError(
        error.FileNotFound,
        tmp.dir.openFile(io, ".lock", .{ .follow_symlinks = false }),
    );
}

test "read-only cache locks share while excluding a fetch lock" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try applyOwnerOnlyAcl(std.testing.allocator, io, tmp.dir);

    var prepared = try acquireCacheLock(std.testing.allocator, io, tmp.dir);
    prepared.close(io);
    var first = try acquireReadOnlyCacheLock(io, tmp.dir);
    defer first.close(io);
    var second = try acquireReadOnlyCacheLock(io, tmp.dir);
    defer second.close(io);
    var excluded = try tmp.dir.openFile(io, ".lock", .{
        .mode = .read_write,
        .allow_directory = false,
        .path_only = builtin.os.tag == .windows,
        .follow_symlinks = false,
        .resolve_beneath = true,
    });
    defer excluded.close(io);
    try std.testing.expect(!try lockCacheFile(io, excluded, .exclusive, true));
}

test "export destination must be outside the dependency cache" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.testing.expectError(
        error.ExportDestinationOverlapsCache,
        ensureExportOutsideCache(io, tmp.dir, tmp.dir),
    );
}

test "export refuses a nonempty output directory without changing it" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var sentinel = try tmp.dir.createFile(io, "sentinel", .{
        .exclusive = true,
        .permissions = privateFilePermissions(),
    });
    sentinel.close(io);

    try std.testing.expectError(error.ExportDestinationNotEmpty, requireEmptyDirectory(io, tmp.dir));
    var retained = try tmp.dir.openFile(io, "sentinel", .{ .follow_symlinks = false });
    retained.close(io);
}

test "cache validation errors distinguish corrupt content from operational failures" {
    try std.testing.expectEqual(
        CacheValidationErrorKind.invalid,
        classifyCacheValidationError(error.InvalidCachedPayload),
    );
    try std.testing.expectEqual(
        CacheValidationErrorKind.operational,
        classifyCacheValidationError(error.AccessDenied),
    );
    try std.testing.expectEqual(
        CacheValidationErrorKind.operational,
        classifyCacheValidationError(error.OutOfMemory),
    );
    try std.testing.expectEqual(
        CacheValidationErrorKind.operational,
        classifyCacheValidationError(error.ReadFailed),
    );
    try std.testing.expectEqual(
        CacheValidationErrorKind.operational,
        classifyCacheValidationError(error.UnknownCacheIoFailure),
    );
    try std.testing.expectEqual(
        CacheProbeState.invalid,
        try cacheProbeStateFromValidation(error.InvalidCachedPayload),
    );
    try std.testing.expectError(
        error.AccessDenied,
        cacheProbeStateFromValidation(error.AccessDenied),
    );
    try std.testing.expectError(
        error.UnknownCacheIoFailure,
        cacheProbeStateFromValidation(error.UnknownCacheIoFailure),
    );
}

test "read-only remediation classifier is narrow and sanitized" {
    for ([_]Mode{ .audit, .export_ucd, .export_zigwin32, .export_attestation_inputs }) |mode| {
        try std.testing.expect(shouldReportCacheRemediation(mode, error.FileNotFound));
        try std.testing.expect(shouldReportCacheRemediation(mode, error.InvalidCachedPayload));
        try std.testing.expect(!shouldReportCacheRemediation(mode, error.AccessDenied));
        try std.testing.expect(!shouldReportCacheRemediation(mode, error.RemediationSentinel));
    }
    try std.testing.expect(!shouldReportCacheRemediation(.bootstrap, error.FileNotFound));
    try std.testing.expect(!shouldReportCacheRemediation(.all, error.InvalidCachedPayload));
    try std.testing.expect(std.mem.indexOf(u8, cache_remediation_line, "https://") == null);
    try std.testing.expect(std.mem.indexOf(u8, cache_remediation_line, "proxy") == null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(
        u8,
        cache_remediation_line,
        "zig build deps-fetch --summary all",
    ));
}

test "cache selection is lazy legacy compatible and v2 is authoritative per artifact" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try applyOwnerOnlyAcl(std.testing.allocator, io, tmp.dir);

    try tmp.dir.createDir(io, "artifact", privateDirPermissions());
    var legacy = try tmp.dir.openDir(io, "artifact", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    try applyOwnerOnlyAcl(std.testing.allocator, io, legacy);
    legacy.close(io);

    var selected_legacy = try openSelectedCacheDirectory(
        std.testing.allocator,
        io,
        tmp.dir,
        "artifact",
    );
    try std.testing.expectEqual(CacheLayout.legacy, selected_legacy.layout);
    selected_legacy.close(io);

    var store = try openOrCreateV2ArtifactStore(
        std.testing.allocator,
        io,
        tmp.dir,
        "artifact",
    );
    try std.testing.expectError(
        error.InvalidCacheSelector,
        openSelectedCacheDirectory(std.testing.allocator, io, tmp.dir, "artifact"),
    );
    try store.generations.createDir(
        io,
        "g-222222222222222222222222",
        privateDirPermissions(),
    );
    var generation = try store.generations.openDir(
        io,
        "g-222222222222222222222222",
        .{ .iterate = true, .follow_symlinks = false },
    );
    try applyOwnerOnlyAcl(std.testing.allocator, io, generation);
    generation.close(io);
    try writeCurrentSelector(
        std.testing.allocator,
        io,
        store.artifact,
        "g-222222222222222222222222",
        ".stage-current-selection",
    );
    store.close(io);

    var selected_v2 = try openSelectedCacheDirectory(
        std.testing.allocator,
        io,
        tmp.dir,
        "artifact",
    );
    defer selected_v2.close(io);
    try std.testing.expectEqual(CacheLayout.generation, selected_v2.layout);
}

test "generation publication leaves the old selector live until atomic replacement" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try applyOwnerOnlyAcl(std.testing.allocator, io, tmp.dir);
    var store = try openOrCreateV2ArtifactStore(
        std.testing.allocator,
        io,
        tmp.dir,
        "artifact",
    );
    defer store.close(io);
    try writeCurrentSelector(
        std.testing.allocator,
        io,
        store.artifact,
        "g-000000000000000000000000",
        ".stage-current-old",
    );

    var stage = try createPinnedStageDirectory(
        std.testing.allocator,
        io,
        tmp.dir,
        ".stage-artifact-new",
    );
    defer stage.close(io);
    var new_file = try stage.createFile(io, "new", .{ .exclusive = true });
    new_file.close(io);

    try publishStagedGeneration(
        std.testing.allocator,
        io,
        tmp.dir,
        store.generations,
        stage,
        ".stage-artifact-new",
        "g-111111111111111111111111",
    );
    const before = try readCurrentSelector(std.testing.allocator, io, store.artifact);
    defer std.testing.allocator.free(before);
    try std.testing.expectEqualStrings("g-000000000000000000000000", before);

    try writeCurrentSelector(
        std.testing.allocator,
        io,
        store.artifact,
        "g-111111111111111111111111",
        ".stage-current-new",
    );
    const after = try readCurrentSelector(std.testing.allocator, io, store.artifact);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualStrings("g-111111111111111111111111", after);
    var installed = try store.generations.openDir(io, "g-111111111111111111111111", .{
        .iterate = true,
        .follow_symlinks = false,
    });
    defer installed.close(io);
    var installed_file = try installed.openFile(io, "new", .{ .follow_symlinks = false });
    installed_file.close(io);
}

const FakeTransportScenario = enum {
    redirect_then_body,
    hostile_redirect,
    request_name_failure,
    head_tls_failure,
    never_head,
    stalled_body,
};

const FakeDownloadTransport = struct {
    scenario: FakeTransportScenario,
    io: std.Io,
    body: []const u8,
    open_calls: usize = 0,
    head_calls: usize = 0,
    deinit_calls: usize = 0,
    redirect_body_calls: usize = 0,
    accepted_body_calls: usize = 0,
    body_offset: usize = 0,
    active_hop: usize = 0,

    fn transport(fake: *FakeDownloadTransport, timeout_ms: i64) DownloadTransport {
        return .{
            .context = fake,
            .open_request = open,
            .timeout_ms = timeout_ms,
        };
    }

    fn open(
        context: *anyopaque,
        allocator: std.mem.Allocator,
        io: std.Io,
        url: []const u8,
    ) !DownloadRequest {
        _ = allocator;
        _ = io;
        _ = url;
        const fake: *FakeDownloadTransport = @ptrCast(@alignCast(context));
        fake.open_calls += 1;
        if (fake.scenario == .request_name_failure) return error.NameResolutionFailed;
        fake.active_hop = fake.open_calls;
        return .{
            .context = fake,
            .receive_head = receiveHead,
            .deinit_request = deinitRequest,
        };
    }

    fn receiveHead(context: *anyopaque) !DownloadResponse {
        const fake: *FakeDownloadTransport = @ptrCast(@alignCast(context));
        fake.head_calls += 1;
        switch (fake.scenario) {
            .head_tls_failure => return error.TlsInitializationFailed,
            .never_head => try std.Io.Clock.Duration.sleep(.{
                .clock = .awake,
                .raw = .fromSeconds(30),
            }, fake.io),
            else => {},
        }
        if ((fake.scenario == .redirect_then_body or fake.scenario == .hostile_redirect) and
            fake.active_hop == 1)
        {
            return fake.response(
                .found,
                if (fake.scenario == .hostile_redirect)
                    "https://attacker.invalid/poison"
                else
                    "https://codeload.github.com/marlersoft/zigwin32/tar.gz/9f15c276b4e9d05afd34a10d8662a7dfc34647ea",
            );
        }
        return fake.response(.ok, null);
    }

    fn response(
        fake: *FakeDownloadTransport,
        status: std.http.Status,
        location: ?[]const u8,
    ) DownloadResponse {
        return .{
            .context = fake,
            .status = status,
            .location = location,
            .content_length = if (status == .ok) fake.body.len else null,
            .content_encoding = .identity,
            .read_body = readBody,
            .body_error = bodyError,
        };
    }

    fn readBody(context: *anyopaque, buffer: []u8) !usize {
        const fake: *FakeDownloadTransport = @ptrCast(@alignCast(context));
        if ((fake.scenario == .redirect_then_body or fake.scenario == .hostile_redirect) and
            fake.active_hop == 1)
        {
            fake.redirect_body_calls += 1;
            return error.BodyTouched;
        }
        fake.accepted_body_calls += 1;
        if (fake.scenario == .stalled_body) {
            try std.Io.Clock.Duration.sleep(.{
                .clock = .awake,
                .raw = .fromSeconds(30),
            }, fake.io);
        }
        const remaining = fake.body[fake.body_offset..];
        const count = @min(buffer.len, remaining.len);
        @memcpy(buffer[0..count], remaining[0..count]);
        fake.body_offset += count;
        return count;
    }

    fn bodyError(context: *anyopaque) ?anyerror {
        _ = context;
        return null;
    }

    fn deinitRequest(context: *anyopaque) void {
        const fake: *FakeDownloadTransport = @ptrCast(@alignCast(context));
        fake.deinit_calls += 1;
    }
};

const TransportPublicationTrace = struct {
    generation_published: bool = false,
    selector_published: bool = false,

    fn observe(context: ?*anyopaque, event: FixtureEvent) !void {
        const trace: *TransportPublicationTrace = @ptrCast(@alignCast(context.?));
        switch (event) {
            .generation_published => trace.generation_published = true,
            .selector_published => trace.selector_published = true,
            else => {},
        }
    }
};

const transport_fixture_bytes = "fixture dependency payload version one\n";
const transport_fixture_sha256 =
    "d87a1a2c28b4acfabf164c0bb987e8750fa85a717047d6328457dd85be3553bd";

fn transportFixtureArtifact(id: []const u8, url: []const u8) deps.Artifact {
    return .{
        .id = id,
        .version = "fixture-transport",
        .purpose = "production transport capability fixture",
        .source_url = "https://example.invalid/fixture",
        .license_spdx = "MIT",
        .license_url = "https://example.invalid/fixture/LICENSE",
        .url = url,
        .allowed_path_prefix = "/fixture",
        .integrity = .byte_archive,
        .archive_format = .direct_file,
        .archive_root = "",
        .archive_size_bytes = transport_fixture_bytes.len,
        .archive_sha256 = transport_fixture_sha256,
        .expected_entries = 1,
        .expected_regular_files = 1,
        .download_limit_bytes = 4096,
        .expanded_limit_bytes = 4096,
        .expected_expanded_bytes = transport_fixture_bytes.len,
        .dependencies = &.{},
        .build_switches = &.{},
    };
}

fn expectEmptyCacheRoot(io: std.Io, root: std.Io.Dir) !void {
    var iterator = root.iterate();
    if (try iterator.next(io)) |_| return error.UnexpectedCacheResidue;
}

fn expectAcquireTransportFailure(
    expected_error: anyerror,
    scenario: FakeTransportScenario,
) !void {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try applyOwnerOnlyAcl(std.testing.allocator, io, tmp.dir);

    var fake: FakeDownloadTransport = .{
        .scenario = scenario,
        .io = io,
        .body = transport_fixture_bytes,
    };
    var trace: TransportPublicationTrace = .{};
    const artifact = transportFixtureArtifact(
        "presentmon",
        "https://github.com/GameTechDev/PresentMon/releases/download/v2.5.1/PresentMon-2.5.1-x64.exe?download=1",
    );
    const before = std.Io.Clock.awake.now(io);
    try std.testing.expectError(expected_error, acquireArtifact(
        std.testing.allocator,
        io,
        .{ .transport = fake.transport(25) },
        tmp.dir,
        artifact,
        collision.foldNfd,
        .{ .context = &trace, .callback = TransportPublicationTrace.observe },
    ));
    const elapsed = before.durationTo(std.Io.Clock.awake.now(io));
    try std.testing.expect(elapsed.nanoseconds < std.time.ns_per_s);
    try std.testing.expect(!trace.generation_published);
    try std.testing.expect(!trace.selector_published);
    const expected_deinit_calls: usize = if (scenario == .request_name_failure) 0 else fake.open_calls;
    try std.testing.expectEqual(expected_deinit_calls, fake.deinit_calls);
    try expectEmptyCacheRoot(io, tmp.dir);
}

test "production redirect control never reads the first-hop body" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var fake: FakeDownloadTransport = .{
        .scenario = .redirect_then_body,
        .io = io,
        .body = transport_fixture_bytes,
    };
    const artifact = transportFixtureArtifact(
        "zigwin32",
        "https://github.com/marlersoft/zigwin32/archive/9f15c276b4e9d05afd34a10d8662a7dfc34647ea.tar.gz?download=1",
    );
    try downloadArtifact(
        std.testing.allocator,
        io,
        .{ .transport = fake.transport(1000) },
        artifact,
        tmp.dir,
        "archive.bin",
    );
    try std.testing.expectEqual(@as(usize, 2), fake.open_calls);
    try std.testing.expectEqual(@as(usize, 2), fake.head_calls);
    try std.testing.expectEqual(@as(usize, 0), fake.redirect_body_calls);
    try std.testing.expect(fake.accepted_body_calls > 0);
    const bytes = try tmp.dir.readFileAlloc(
        io,
        "archive.bin",
        std.testing.allocator,
        .limited(4096),
    );
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings(transport_fixture_bytes, bytes);

    var hostile: FakeDownloadTransport = .{
        .scenario = .hostile_redirect,
        .io = io,
        .body = transport_fixture_bytes,
    };
    try std.testing.expectError(error.UnapprovedDownloadTarget, downloadArtifact(
        std.testing.allocator,
        io,
        .{ .transport = hostile.transport(1000) },
        artifact,
        tmp.dir,
        "hostile.bin",
    ));
    try std.testing.expectEqual(@as(usize, 0), hostile.redirect_body_calls);
    try std.testing.expectEqual(@as(usize, 1), hostile.open_calls);
    try std.testing.expectEqual(@as(usize, 1), hostile.deinit_calls);
    try std.testing.expectError(
        error.FileNotFound,
        tmp.dir.openFile(io, "hostile.bin", .{ .follow_symlinks = false }),
    );
}

test "production acquisition propagates request and head transport failures" {
    try expectAcquireTransportFailure(error.NameResolutionFailed, .request_name_failure);
    try expectAcquireTransportFailure(error.TlsInitializationFailed, .head_tls_failure);
}

test "production acquisition bounds a missing head and stalled body" {
    try expectAcquireTransportFailure(error.DownloadTimeout, .never_head);
    try expectAcquireTransportFailure(error.DownloadTimeout, .stalled_body);
}
