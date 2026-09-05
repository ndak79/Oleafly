//! Offline, in-memory T0.2b compression oracle. This module neither discovers
//! the product payload nor proves its 90/30 MiB gates. The caller supplies the
//! complete regular-file inventory; no file is excluded or transformed.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Sha256 = std.crypto.hash.sha2.Sha256;
const block_size = 512;
const end_bytes = block_size * 2;
const inventory_domain = "texflow-package-inventory-v1\x00";
const gzip_header = [_]u8{ 0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3 };

pub const File = struct {
    /// Exact UTF-8 path relative to the inventory root, using '/' separators.
    path: []const u8,
    bytes: []const u8,
    kind: enum { regular, directory, symlink, hardlink, device, fifo, socket } = .regular,
    // Source metadata is deliberately ignored; canonical mode is always 0644.
    source_mode: u32 = 0,
    source_uid: u64 = 0,
    source_gid: u64 = 0,
    source_mtime: i64 = 0,
    source_uname: []const u8 = "",
    source_gname: []const u8 = "",
};

pub const Receipt = struct {
    file_count: usize,
    payload_bytes: usize,
    inventory_bytes: usize,
    tar_bytes: usize,
    gzip_bytes: usize,
    inventory_sha256: [32]u8,
    tar_sha256: [32]u8,
    gzip_sha256: [32]u8,
};

pub const Result = struct {
    /// Domain, LE-u64 count, then repeated LE-u64 path length, UTF-8 path,
    /// LE-u64 original byte length, and raw SHA-256, in unsigned-byte order.
    inventory: []u8,
    tar: []u8,
    gzip: []u8,
    receipt: Receipt,

    pub fn deinit(self: *Result, allocator: Allocator) void {
        allocator.free(self.inventory);
        allocator.free(self.tar);
        allocator.free(self.gzip);
        self.* = undefined;
    }
};

const Prepared = struct {
    files: []File,
    payload_bytes: usize,
    tar_bytes: usize,
    inventory_bytes: usize,
};

/// Returns independently owned canonical outputs; input storage is never kept.
pub fn generate(allocator: Allocator, files: []const File) !Result {
    const prepared = try prepare(allocator, files);
    defer allocator.free(prepared.files);
    const inventory = try makeInventory(allocator, prepared);
    errdefer allocator.free(inventory);
    const tar = try makeTar(allocator, prepared);
    errdefer allocator.free(tar);
    const gzip = try compress(allocator, tar);
    errdefer allocator.free(gzip);
    return .{
        .inventory = inventory,
        .tar = tar,
        .gzip = gzip,
        .receipt = .{
            .file_count = prepared.files.len,
            .payload_bytes = prepared.payload_bytes,
            .inventory_bytes = inventory.len,
            .tar_bytes = tar.len,
            .gzip_bytes = gzip.len,
            .inventory_sha256 = hash(inventory),
            .tar_sha256 = hash(tar),
            .gzip_sha256 = hash(gzip),
        },
    };
}

/// Regenerates in separate live in-memory roots, including fresh input names
/// and bytes. Both complete outputs and both round-trips must agree. Physical
/// filesystem roots and the real runtime-payload inventory are later gates.
pub fn reproduce(allocator: Allocator, files: []const File) !Result {
    var first = try generate(allocator, files);
    errdefer first.deinit(allocator);
    const copied = try allocator.alloc(File, files.len);
    defer allocator.free(copied);
    var initialized: usize = 0;
    defer for (copied[0..initialized]) |file| {
        allocator.free(file.path);
        allocator.free(file.bytes);
    };
    for (files, copied) |file, *copy| {
        const path = try allocator.dupe(u8, file.path);
        errdefer allocator.free(path);
        const bytes = try allocator.dupe(u8, file.bytes);
        copy.* = .{ .path = path, .bytes = bytes, .kind = file.kind };
        initialized += 1;
    }
    var second = try generate(allocator, copied);
    defer second.deinit(allocator);
    if (!std.mem.eql(u8, first.inventory, second.inventory) or
        !std.mem.eql(u8, first.tar, second.tar) or
        !std.mem.eql(u8, first.gzip, second.gzip) or
        !std.meta.eql(first.receipt, second.receipt)) return error.NonDeterministicPackage;
    try verifyRoundTrip(allocator, files, first.gzip);
    try verifyRoundTrip(allocator, copied, second.gzip);
    return first;
}

/// An exact canonical-byte oracle, not a permissive general tar extractor.
/// Rebuilding from the expected manifest rejects altered content, metadata,
/// extensions, padding, ordering, member count, and missing/extra end blocks.
pub fn validateTar(allocator: Allocator, files: []const File, tar: []const u8) !void {
    const prepared = try prepare(allocator, files);
    defer allocator.free(prepared.files);
    const expected = try makeTar(allocator, prepared);
    defer allocator.free(expected);
    if (!std.mem.eql(u8, expected, tar)) return error.InvalidTar;
}

/// Bounded decompression with independent CRC32 and ISIZE checks: Zig 0.16
/// Decompress records its footer metadata but does not validate the checksum.
pub fn verifyRoundTrip(allocator: Allocator, files: []const File, gzip: []const u8) !void {
    if (gzip.len < gzip_header.len + 8 or !std.mem.eql(u8, &gzip_header, gzip[0..gzip_header.len])) return error.InvalidGzip;
    const prepared = try prepare(allocator, files);
    defer allocator.free(prepared.files);
    const expected = try makeTar(allocator, prepared);
    defer allocator.free(expected);
    const decoded = try allocator.alloc(u8, expected.len);
    defer allocator.free(decoded);
    var reader = std.Io.Reader.fixed(gzip);
    var writer = std.Io.Writer.fixed(decoded);
    var history: [std.compress.flate.max_window_len]u8 = undefined;
    var decompressor = std.compress.flate.Decompress.init(&reader, .gzip, &history);
    _ = decompressor.reader.streamRemaining(&writer) catch return error.InvalidGzip;
    if (decompressor.err != null or reader.bufferedLen() != 0) return error.InvalidGzip;
    const actual = writer.buffered();
    const footer = decompressor.container_metadata.gzip;
    if (footer.crc != std.hash.Crc32.hash(actual) or footer.count != @as(u32, @truncate(actual.len))) return error.InvalidGzip;
    if (!std.mem.eql(u8, expected, actual)) return error.InvalidTar;
    // A valid alternate deflate representation is not this fixed level-9 oracle.
    const canonical_gzip = try compress(allocator, expected);
    defer allocator.free(canonical_gzip);
    if (!std.mem.eql(u8, canonical_gzip, gzip)) return error.InvalidGzip;
}

fn prepare(allocator: Allocator, files: []const File) !Prepared {
    var prepared = Prepared{
        .files = try allocator.dupe(File, files),
        .payload_bytes = 0,
        .tar_bytes = end_bytes,
        .inventory_bytes = inventory_domain.len + 8,
    };
    errdefer allocator.free(prepared.files);
    for (files) |file| {
        if (file.kind != .regular) return error.NonRegularFile;
        try validatePath(file.path);
        _ = try splitName(file.path);
        if (file.bytes.len > 0o77777777777) return error.UnrepresentableSize;
        prepared.payload_bytes = try add(prepared.payload_bytes, file.bytes.len);
        prepared.tar_bytes = try add(prepared.tar_bytes, try add(block_size, try paddedSize(file.bytes.len)));
        prepared.inventory_bytes = try add(prepared.inventory_bytes, try add(48, file.path.len));
    }
    std.mem.sort(File, prepared.files, {}, lessThan);
    for (prepared.files, 0..) |file, index| {
        if (index != 0 and std.mem.eql(u8, prepared.files[index - 1].path, file.path)) return error.DuplicatePath;
    }
    try validateWindowsCollisions(allocator, prepared.files);
    return prepared;
}

fn lessThan(_: void, left: File, right: File) bool {
    return std.mem.order(u8, left.path, right.path) == .lt;
}

const Component = struct { path: []const u8, file: bool };

fn validateWindowsCollisions(allocator: Allocator, files: []const File) !void {
    var components: std.ArrayList(Component) = .empty;
    defer components.deinit(allocator);
    for (files) |file| {
        // Include every directory prefix so "Bin/a" and "bin/b" cannot
        // introduce two different spellings for the same Windows directory.
        for (file.path, 0..) |byte, end| {
            if (byte == '/') try components.append(allocator, .{ .path = file.path[0..end], .file = false });
        }
        try components.append(allocator, .{ .path = file.path, .file = true });
    }
    // Sort only preflight references: tar and inventory retain byte order.
    std.mem.sort(Component, components.items, {}, componentLessThan);
    var start: usize = 0;
    var case_collision = false;
    while (start < components.items.len) {
        const first = components.items[start];
        var has_file = first.file;
        var has_directory = !first.file;
        var end = start + 1;
        while (end < components.items.len and windowsOrder(first.path, components.items[end].path) == .eq) : (end += 1) {
            const other = components.items[end];
            has_file = has_file or other.file;
            has_directory = has_directory or !other.file;
            if (!std.mem.eql(u8, first.path, other.path)) case_collision = true;
        }
        // Prioritize file/directory conflicts even if an earlier prefix group
        // also used different casing. Both are prohibited before serialization.
        if (has_file and has_directory) return error.PathConflict;
        start = end;
    }
    if (case_collision) return error.WindowsPathCollision;
}

fn componentLessThan(_: void, left: Component, right: Component) bool {
    return windowsOrder(left.path, right.path) == .lt;
}

fn windowsOrder(left: []const u8, right: []const u8) std.math.Order {
    var left_it = std.unicode.Utf8View.initUnchecked(left).iterator();
    var right_it = std.unicode.Utf8View.initUnchecked(right).iterator();
    while (true) {
        const left_cp = left_it.nextCodepoint() orelse return if (right_it.nextCodepoint() == null) .eq else .lt;
        const right_cp = right_it.nextCodepoint() orelse return .gt;
        const order = std.math.order(windowsUpper(left_cp), windowsUpper(right_cp));
        if (order != .eq) return order;
    }
}

fn windowsUpper(codepoint: u21) u21 {
    // Match Zig's eqlIgnoreCaseWtf8 equivalence without its Windows runtime
    // ntdll call: use the pinned NLS table on every target. Like Windows, this
    // mapping preserves non-BMP codepoints and does not apply Unicode NFC or
    // expanding full case folding. UTF-8 byte lengths can change when uppercased.
    return if (codepoint <= std.math.maxInt(u16)) std.os.windows.nls.upcaseW(@intCast(codepoint)) else codepoint;
}

fn validatePath(path: []const u8) !void {
    if (path.len == 0 or !std.unicode.utf8ValidateSlice(path)) return error.UnsafePath;
    for (path) |byte| {
        if (byte < 32 or byte == 127 or std.mem.indexOfScalar(u8, "\\:*?\"<>|", byte) != null) return error.UnsafePath;
    }
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..") or
            component[component.len - 1] == '.' or component[component.len - 1] == ' ') return error.UnsafePath;
        if (reservedDevice(component)) return error.UnsafePath;
    }
}

fn reservedDevice(component: []const u8) bool {
    const end = std.mem.indexOfScalar(u8, component, '.') orelse component.len;
    const stem = std.mem.trimEnd(u8, component[0..end], " ");
    for ([_][]const u8{ "CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$" }) |device| {
        if (std.ascii.eqlIgnoreCase(stem, device)) return true;
    }
    if (stem.len < 4) return false;
    if (!std.ascii.eqlIgnoreCase(stem[0..3], "COM") and !std.ascii.eqlIgnoreCase(stem[0..3], "LPT")) return false;
    const number = stem[3..];
    if (number.len == 1 and number[0] >= '1' and number[0] <= '9') return true;
    for ([_][]const u8{ "\u{b9}", "\u{b2}", "\u{b3}" }) |superscript| {
        if (std.mem.eql(u8, number, superscript)) return true;
    }
    return false;
}

const Name = struct { prefix: []const u8, name: []const u8 };

fn splitName(path: []const u8) !Name {
    if (path.len <= 100) return .{ .prefix = "", .name = path };
    // The full 155-byte prefix and 100-byte name fields may be non-NUL-terminated.
    var split = @min(path.len, 156);
    while (split != 0) {
        split -= 1;
        if (path[split] == '/' and path.len - split - 1 <= 100) return .{ .prefix = path[0..split], .name = path[split + 1 ..] };
    }
    return error.UnrepresentablePath;
}

fn makeInventory(allocator: Allocator, prepared: Prepared) ![]u8 {
    const bytes = try allocator.alloc(u8, prepared.inventory_bytes);
    errdefer allocator.free(bytes);
    var writer = std.Io.Writer.fixed(bytes);
    try writer.writeAll(inventory_domain);
    try writer.writeInt(u64, prepared.files.len, .little);
    for (prepared.files) |file| {
        try writer.writeInt(u64, file.path.len, .little);
        try writer.writeAll(file.path);
        try writer.writeInt(u64, file.bytes.len, .little);
        try writer.writeAll(&hash(file.bytes));
    }
    std.debug.assert(writer.buffered().len == bytes.len);
    return bytes;
}

fn makeTar(allocator: Allocator, prepared: Prepared) ![]u8 {
    const bytes = try allocator.alloc(u8, prepared.tar_bytes);
    errdefer allocator.free(bytes);
    @memset(bytes, 0);
    var offset: usize = 0;
    for (prepared.files) |file| {
        const header = bytes[offset..][0..block_size];
        const name = try splitName(file.path);
        @memcpy(header[0..name.name.len], name.name);
        @memcpy(header[345..][0..name.prefix.len], name.prefix);
        try octal(header[100..108], 0o644);
        try octal(header[108..116], 0);
        try octal(header[116..124], 0);
        try octal(header[124..136], file.bytes.len);
        try octal(header[136..148], 0);
        @memset(header[148..156], ' ');
        header[156] = '0';
        @memcpy(header[257..263], "ustar\x00");
        @memcpy(header[263..265], "00");
        var checksum: u64 = 0;
        for (header) |byte| checksum += byte;
        try octal(header[148..155], checksum);
        header[155] = ' ';
        offset += block_size;
        @memcpy(bytes[offset..][0..file.bytes.len], file.bytes);
        offset += try paddedSize(file.bytes.len);
    }
    std.debug.assert(offset + end_bytes == bytes.len);
    return bytes;
}

fn octal(field: []u8, value: u64) !void {
    @memset(field, '0');
    field[field.len - 1] = 0;
    var remaining = value;
    var index = field.len - 1;
    while (index != 0) {
        index -= 1;
        field[index] = @as(u8, @intCast(remaining & 7)) + '0';
        remaining >>= 3;
    }
    if (remaining != 0) return error.UnrepresentableSize;
}

fn compress(allocator: Allocator, bytes: []const u8) ![]u8 {
    var output = try std.Io.Writer.Allocating.initCapacity(allocator, 4096);
    defer output.deinit();
    var history: [std.compress.flate.max_window_len * 2]u8 = undefined;
    // Fresh compressor and history; no external dictionary or preprocessing.
    var compressor = std.compress.flate.Compress.init(&output.writer, &history, .gzip, .level_9) catch return error.OutOfMemory;
    compressor.writer.writeAll(bytes) catch return error.OutOfMemory;
    compressor.finish() catch return error.OutOfMemory;
    return output.toOwnedSlice();
}

fn hash(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    Sha256.hash(bytes, &digest, .{});
    return digest;
}

fn paddedSize(size: usize) !usize {
    return (try add(size, block_size - 1)) / block_size * block_size;
}

fn add(left: usize, right: usize) !usize {
    return std.math.add(usize, left, right) catch error.InputTooLarge;
}
