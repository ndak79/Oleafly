//! Static, offline PE32+ audit. The audited image is never mapped or executed.
//! Narrow admission profile based on Microsoft's PE/COFF specification:
//! https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
//! Unsupported directories/flags are rejected, not treated as audited. This
//! does not verify transitive DLLs, signatures, manifests or runtime CFG.
const std = @import("std");
pub const Import = struct { dll: []const u8, functions: []const []const u8 };
pub const Policy = struct {
    imports: []const Import,
    subsystem: u16 = 3,
    require_cfg: bool = false,
    forbidden_paths: []const []const u8 = &.{},
};
pub const Cfg = enum { not_declared, metadata_present };
pub const Report = struct { sections: usize, imports: usize, cfg: Cfg, empty_repro_marker: bool };

const max_image_bytes = 256 * 1024 * 1024;
const max_imports = 4096;
const Section = struct { rva: u64, virtual_size: u64, raw: usize, raw_size: usize, flags: u32 };
const Directory = struct { rva: u64, size: usize };

// Canonical per-section envelopes cover audited metadata, including terminators
// and gaps between related fields in one section. This bounded conservative
// profile avoids unbounded interval allocation and rejects relocation of the
// bytes on which static admission depends. Import and other metadata maintain
// separate envelopes so unrelated code/data between them remain eligible.
const MetadataEnvelopes = struct {
    const Span = struct { start: u64 = 0, end: u64 = 0 };
    spans: [96]Span = @splat(.{}),

    fn include(self: *MetadataEnvelopes, image: Image, rva: u64, size: usize) !void {
        _ = try image.map(rva, size);
        const owner = try image.section(rva, size);
        for (image.sections, 0..) |section, i| {
            if (section.rva != owner.rva) continue;
            const span = &self.spans[i];
            span.start = if (span.end == 0) rva else @min(span.start, rva);
            // map/section constrain the complete span below SizeOfImage (u32).
            span.end = @max(span.end, rva + @as(u64, size));
            return;
        }
        return error.UnmappedRva;
    }

    fn intersects(self: *const MetadataEnvelopes, target: u64) bool {
        for (self.spans) |span| {
            if (span.end != 0 and overlaps(target, 8, span.start, span.end - span.start)) return true;
        }
        return false;
    }

    fn intersectsRange(self: *const MetadataEnvelopes, start: u64, size: usize) bool {
        for (self.spans) |span| {
            if (span.end != 0 and overlaps(start, size, span.start, span.end - span.start)) return true;
        }
        return false;
    }
};

const Image = struct {
    bytes: []const u8,
    sections: []const Section,
    base: u64,
    timestamp: u32,

    fn section(self: Image, rva: u64, size: usize) !Section {
        for (self.sections) |s| {
            if (rva >= s.rva and rva - s.rva < s.virtual_size and size <= s.virtual_size - (rva - s.rva)) return s;
        }
        return error.UnmappedRva;
    }

    fn map(self: Image, rva: u64, size: usize) ![]const u8 {
        const s = try self.section(rva, size);
        const delta = rva - s.rva;
        if (delta >= s.raw_size or size > s.raw_size - delta) return error.UnmappedRva;
        return range(self.bytes, s.raw + @as(usize, @intCast(delta)), size);
    }

    fn string(self: Image, rva: u64) ![]const u8 {
        const s = try self.section(rva, 1);
        const delta: usize = @intCast(rva - s.rva);
        if (delta >= s.raw_size) return error.UnmappedRva;
        const available = @min(@min(s.raw_size - delta, s.virtual_size - delta), 4096);
        const bytes = try self.map(rva, @intCast(available));
        const end = std.mem.indexOfScalar(u8, bytes, 0) orelse return error.UnterminatedString;
        if (end == 0) return error.InvalidImportName;
        for (bytes[0..end]) |c| if (c < 0x21 or c > 0x7e) return error.InvalidImportName;
        return bytes[0..end];
    }

    fn executable(self: Image, rva: u64, size: usize) !void {
        const s = try self.section(rva, size);
        if (s.flags & 0x20000000 == 0) return error.NonExecutableAddress;
        _ = try self.map(rva, size);
    }

    fn vaRva(self: Image, va: u64) !u64 {
        if (va < self.base or va - self.base > std.math.maxInt(u32)) return error.InvalidCfg;
        return va - self.base;
    }
};

fn range(bytes: []const u8, offset: usize, size: usize) ![]const u8 {
    if (offset > bytes.len or size > bytes.len - offset) return error.Truncated;
    return bytes[offset..][0..size];
}

fn read(comptime T: type, bytes: []const u8, offset: usize) !T {
    return std.mem.readInt(T, (try range(bytes, offset, @sizeOf(T)))[0..@sizeOf(T)], .little);
}

fn overlaps(a: u64, an: u64, b: u64, bn: u64) bool {
    return an != 0 and bn != 0 and a < b + bn and b < a + an;
}

pub fn audit(bytes: []const u8, policy: Policy) !Report {
    if (bytes.len > max_image_bytes) return error.ImageTooLarge;
    if (!std.mem.eql(u8, try range(bytes, 0, 2), "MZ")) return error.InvalidDosHeader;
    const pe_offset = try read(u32, bytes, 0x3c);
    if (pe_offset < 64) return error.InvalidDosHeader;
    const header = try range(bytes, pe_offset, 24);
    if (!std.mem.eql(u8, header[0..4], "PE\x00\x00")) return error.InvalidPeSignature;
    if (try read(u16, header, 4) != 0x8664) return error.UnsupportedMachine;
    const count = try read(u16, header, 6);
    if (count == 0 or count > 96) return error.InvalidSections;
    if (try read(u32, header, 12) != 0 or try read(u32, header, 16) != 0) return error.DebugMetadata;
    if (try read(u16, header, 20) != 240) return error.UnsupportedOptionalHeader;
    const characteristics = try read(u16, header, 22);
    // Executable, large-address-aware, and the obsolete stripped flags only.
    if (characteristics & 0x22 != 0x22 or characteristics & ~@as(u16, 0x22e) != 0) return error.UnsupportedCharacteristics;
    const optional = try range(bytes, @as(usize, pe_offset) + 24, 240);
    if (try read(u16, optional, 0) != 0x20b) return error.UnsupportedOptionalHeader;
    if ((policy.subsystem != 2 and policy.subsystem != 3) or try read(u16, optional, 68) != policy.subsystem) return error.SubsystemMismatch;
    const dll_flags = try read(u16, optional, 70);
    if (dll_flags & 0x160 != 0x160) return error.MissingMitigation;
    if (dll_flags & ~@as(u16, 0xc160) != 0) return error.UnsupportedCharacteristics;
    if (try read(u32, optional, 108) != 16) return error.UnsupportedDirectories;
    if (try read(u32, optional, 52) != 0 or try read(u32, optional, 104) != 0) return error.UnsupportedOptionalHeader;
    const alignment = try read(u32, optional, 32);
    const file_alignment = try read(u32, optional, 36);
    const image_size = try read(u32, optional, 56);
    const headers_size = try read(u32, optional, 60);
    const base = try read(u64, optional, 24);
    if (alignment < 4096 or !std.math.isPowerOfTwo(alignment) or
        file_alignment < 512 or !std.math.isPowerOfTwo(file_alignment) or file_alignment > 65536 or alignment < file_alignment or
        headers_size == 0 or headers_size % file_alignment != 0 or image_size == 0 or image_size > 0x8000_0000 or image_size % alignment != 0 or
        base == 0 or base % 65536 != 0 or base > std.math.maxInt(u64) - @as(u64, image_size)) return error.InvalidLayout;
    const table_offset = @as(usize, pe_offset) + 264;
    const table = try range(bytes, table_offset, @as(usize, count) * 40);
    if (headers_size < table_offset + table.len or headers_size > bytes.len) return error.InvalidLayout;
    var sections: [96]Section = undefined;
    var last_raw: usize = headers_size;
    var expected_rva: u64 = std.mem.alignForward(u64, headers_size, alignment);
    var last_virtual: u64 = alignment;
    for (0..count) |i| {
        const row = table[i * 40 ..][0..40];
        const name = row[0..8];
        if (std.mem.startsWith(u8, name, ".debug") or std.mem.startsWith(u8, name, ".zdebug") or name[0] == '/') return error.DebugMetadata;
        if (try read(u32, row, 24) != 0 or try read(u32, row, 28) != 0 or try read(u32, row, 32) != 0) return error.UnsupportedSection;
        const flags = try read(u32, row, 36);
        if (flags & ~@as(u32, 0xe20000e0) != 0 or flags & 0x40000000 == 0 or flags & 0xa0000000 == 0xa0000000) return error.UnsafeSection;
        const s: Section = .{
            .rva = try read(u32, row, 12),
            .virtual_size = try read(u32, row, 8),
            .raw = try read(u32, row, 20),
            .raw_size = try read(u32, row, 16),
            .flags = flags,
        };
        const extent = @max(s.virtual_size, s.raw_size);
        if (s.virtual_size == 0 or s.rva != expected_rva or s.rva < headers_size or s.rva % alignment != 0 or s.rva + extent > image_size) return error.InvalidLayout;
        if (s.raw_size == 0) {
            if (s.raw != 0 or flags & 0x80 == 0 or flags & 0x20000000 != 0) return error.InvalidLayout;
        } else {
            if (s.raw < headers_size or s.raw % file_alignment != 0 or s.raw_size % file_alignment != 0) return error.InvalidLayout;
            _ = try range(bytes, s.raw, s.raw_size);
            last_raw = @max(last_raw, s.raw + s.raw_size);
        }
        for (sections[0..i]) |other| {
            if (overlaps(s.raw, s.raw_size, other.raw, other.raw_size) or overlaps(s.rva, extent, other.rva, @max(other.virtual_size, other.raw_size))) return error.OverlappingSections;
        }
        last_virtual = @max(last_virtual, s.rva + extent);
        expected_rva = std.mem.alignForward(u64, s.rva + extent, alignment);
        sections[i] = s;
    }
    if (last_raw != bytes.len) return error.TrailingData;
    if (std.mem.alignForward(u64, last_virtual, alignment) != image_size) return error.InvalidLayout;
    const image: Image = .{ .bytes = bytes, .sections = sections[0..count], .base = base, .timestamp = try read(u32, header, 8) };
    try image.executable(try read(u32, optional, 16), 1);
    var dirs: [16]Directory = undefined;
    for (&dirs, 0..) |*d, i| {
        d.* = .{ .rva = try read(u32, optional, 112 + i * 8), .size = try read(u32, optional, 116 + i * 8) };
        if ((d.rva == 0) != (d.size == 0)) return error.InvalidDirectory;
        if (d.size == 0) continue;
        switch (i) {
            1, 3, 5, 6, 10, 12 => {},
            else => return error.UnsupportedDirectory,
        }
        _ = try image.map(d.rva, d.size);
    }
    const supported_directories = [_]usize{ 1, 3, 5, 6, 10, 12 };
    for (supported_directories, 0..) |left, i| {
        if (dirs[left].size == 0) continue;
        for (supported_directories[i + 1 ..]) |right| {
            if (dirs[right].size != 0 and overlaps(dirs[left].rva, dirs[left].size, dirs[right].rva, dirs[right].size)) {
                return error.OverlappingDirectories;
            }
        }
    }
    var protected_metadata: MetadataEnvelopes = .{};
    for ([_]usize{ 3, 6, 10 }) |index| {
        if (dirs[index].size != 0) try protected_metadata.include(image, dirs[index].rva, dirs[index].size);
    }
    try debugDirectory(image, dirs[6]);
    try exceptions(image, dirs[3], &protected_metadata);
    var import_envelopes: MetadataEnvelopes = .{};
    const imports = try auditImports(image, dirs[1], dirs[12], policy.imports, &import_envelopes);
    const cfg = auditCfg(image, dirs[10], dll_flags & 0x4000 != 0, &protected_metadata) catch return error.InvalidCfg;
    if (protected_metadata.intersectsRange(dirs[12].rva, dirs[12].size)) return error.InvalidIat;
    try relocations(image, dirs[5], &import_envelopes, &protected_metadata);
    if (policy.require_cfg and cfg == .not_declared) return error.MissingCfg;
    try sourcePaths(bytes, policy.forbidden_paths);
    return .{ .sections = count, .imports = imports, .cfg = cfg, .empty_repro_marker = dirs[6].size != 0 };
}

fn debugDirectory(image: Image, dir: Directory) !void {
    if (dir.size == 0) return;
    // LLD emits this empty determinism marker even for stripped binaries.
    // It has no debug payload, filename, pointer or source path. Under REPRO,
    // Timestamp contains a content-derived value, matched to the COFF header.
    if (dir.size != 28) return error.DebugMetadata;
    const data = try image.map(dir.rva, dir.size);
    if (try read(u32, data, 12) != 16 or try read(u32, data, 0) != 0 or try read(u32, data, 4) != image.timestamp or
        try read(u32, data, 8) != 0 or !std.mem.allEqual(u8, data[16..28], 0)) return error.DebugMetadata;
}

fn relocations(image: Image, dir: Directory, imports: *const MetadataEnvelopes, metadata: *const MetadataEnvelopes) !void {
    if (dir.size == 0) return error.MissingRelocations;
    const data = try image.map(dir.rva, dir.size);
    var offset: usize = 0;
    var count: usize = 0;
    var previous_page: ?u32 = null;
    while (offset < data.len) {
        if (data.len - offset < 8) return error.InvalidRelocations;
        const page = try read(u32, data, offset);
        const size = try read(u32, data, offset + 4);
        if (page % 4096 != 0 or size < 8 or size % 4 != 0 or size > data.len - offset) return error.InvalidRelocations;
        if (previous_page) |p| if (page <= p) return error.InvalidRelocations;
        previous_page = page;
        var entry_offset = offset + 8;
        var seen = [_]bool{false} ** 4096;
        while (entry_offset < offset + size) : (entry_offset += 2) {
            const entry = try read(u16, data, entry_offset);
            if (entry == 0) continue;
            if (entry >> 12 != 10) return error.UnsupportedRelocation;
            const within = entry & 0xfff;
            if (within > 4088 or seen[within]) return error.InvalidRelocations;
            seen[within] = true;
            const target = @as(u64, page) + within;
            _ = try image.map(target, 8);
            // Check all eight written bytes, including targets that begin
            // outside a protected span. Self-modifying relocation metadata
            // could otherwise retarget a later entry into import metadata.
            if (overlaps(target, 8, dir.rva, dir.size)) return error.RelocationTouchesRelocations;
            if (imports.intersects(target)) return error.RelocationTouchesImports;
            if (metadata.intersects(target)) return error.RelocationTouchesMetadata;
            count += 1;
        }
        offset += size;
    }
    if (count == 0) return error.MissingRelocations;
}

fn exceptions(image: Image, dir: Directory, protected: *MetadataEnvelopes) !void {
    if (dir.size == 0) return;
    if (dir.size % 12 != 0) return error.InvalidExceptions;
    const data = try image.map(dir.rva, dir.size);
    var previous_end: u64 = 0;
    var offset: usize = 0;
    while (offset < data.len) : (offset += 12) {
        const begin = try read(u32, data, offset);
        const end = try read(u32, data, offset + 4);
        const unwind = try read(u32, data, offset + 8);
        if (begin < previous_end or end <= begin or unwind % 4 != 0) return error.InvalidExceptions;
        try image.executable(begin, end - begin);
        // Only canonical version-1 leaf records: no prologue, unwind opcodes,
        // frame register, handler or chaining extension. Other records need a
        // complete decoder before this narrow profile can admit them.
        const info = try image.map(unwind, 4);
        if (!std.mem.eql(u8, info, &.{ 1, 0, 0, 0 })) return error.UnsupportedUnwind;
        try protected.include(image, unwind, 4);
        previous_end = end;
    }
}

fn auditImports(image: Image, dir: Directory, iat: Directory, allow: []const Import, protected: *MetadataEnvelopes) !usize {
    if (dir.size == 0) {
        if (iat.size != 0) return error.InvalidIat;
        return 0;
    }
    if (iat.size == 0 or iat.size % 8 != 0 or dir.size % 20 != 0) return error.InvalidDirectory;
    if (overlaps(iat.rva, iat.size, dir.rva, dir.size)) return error.InvalidIat;
    const data = try image.map(dir.rva, dir.size);
    try protected.include(image, dir.rva, dir.size);
    try protected.include(image, iat.rva, iat.size);
    var offset: usize = 0;
    var count: usize = 0;
    var iat_consumed: usize = 0;
    while (offset < data.len) : (offset += 20) {
        const descriptor = data[offset..][0..20];
        if (std.mem.allEqual(u8, descriptor, 0)) {
            if (!std.mem.allEqual(u8, data[offset..], 0)) return error.InvalidDirectory;
            if (iat_consumed != iat.size) return error.InvalidIat;
            return count;
        }
        if (try read(u32, descriptor, 4) != 0 or try read(u32, descriptor, 8) != 0) return error.BoundImport;
        const lookup: u64 = try read(u32, descriptor, 0);
        const first: u64 = try read(u32, descriptor, 16);
        if (lookup == 0 or lookup % 8 != 0 or first != iat.rva + iat_consumed or overlaps(lookup, 8, iat.rva, iat.size)) return error.InvalidIat;
        const dll_rva = try read(u32, descriptor, 12);
        const dll = try image.string(dll_rva);
        if (overlaps(iat.rva, iat.size, dll_rva, dll.len + 1)) return error.InvalidIat;
        try protected.include(image, dll_rva, dll.len + 1);
        if (std.mem.indexOfAny(u8, dll, "/\\:") != null) return error.InvalidImportName;
        const allowed = for (allow) |rule| {
            if (std.ascii.eqlIgnoreCase(dll, rule.dll)) break rule.functions;
        } else return error.DisallowedImport;
        var index: usize = 0;
        while (true) : (index += 1) {
            if (index > max_imports or count > max_imports) return error.TooManyImports;
            const thunk_rva = lookup + index * 8;
            if (overlaps(thunk_rva, 8, iat.rva, iat.size)) return error.InvalidIat;
            const value = try read(u64, try image.map(thunk_rva, 8), 0);
            try protected.include(image, thunk_rva, 8);
            if (value >> 63 != 0) return error.OrdinalImport;
            if (iat_consumed > iat.size or 8 > iat.size - iat_consumed) return error.InvalidIat;
            const resolved = try read(u64, try image.map(first + index * 8, 8), 0);
            if (resolved != value) return error.InvalidIat;
            iat_consumed += 8;
            if (value == 0) break;
            // PE32+ named thunks reserve bits 62..31; only a 31-bit RVA is valid.
            if (value > 0x7fff_ffff) return error.InvalidImportName;
            _ = try image.map(value, 2);
            const name = try image.string(value + 2);
            if (overlaps(iat.rva, iat.size, value, name.len + 3)) return error.InvalidIat;
            try protected.include(image, value, name.len + 3);
            for (allowed) |function| {
                if (std.mem.eql(u8, name, function)) break;
            } else return error.DisallowedImport;
            count += 1;
        }
        if (index == 0) return error.InvalidImportName;
    }
    return error.UnterminatedImports;
}

fn auditCfg(image: Image, dir: Directory, declared: bool, protected: *MetadataEnvelopes) !Cfg {
    if (dir.size == 0) {
        if (declared) return error.InvalidCfg;
        return .not_declared;
    }
    // Deliberately only the original 148-byte AMD64 CFG layout. Extended
    // guard formats and fields require an explicit future parser/profile. This
    // static profile does not simulate valid VA fixups: even declared CFG VA
    // fields and pointer slots are protected from relocation conservatively.
    if (!declared or dir.size != 148) return error.InvalidCfg;
    const data = try image.map(dir.rva, dir.size);
    if (try read(u32, data, 0) != 148 or !std.mem.allEqual(u8, data[4..112], 0) or try read(u32, data, 144) != 0x500) return error.InvalidCfg;
    for ([_]usize{ 112, 120 }) |offset| {
        const slot = try image.vaRva(try read(u64, data, offset));
        if (slot % 8 != 0) return error.InvalidCfg;
        const target = try image.vaRva(try read(u64, try image.map(slot, 8), 0));
        try image.executable(target, 1);
        try protected.include(image, slot, 8);
    }
    const table_rva = try image.vaRva(try read(u64, data, 128));
    const count = try read(u64, data, 136);
    if (count == 0 or count > max_imports or table_rva % 4 != 0) return error.InvalidCfg;
    if ((try image.section(table_rva, 1)).flags & 0x80000000 != 0) return error.InvalidCfg;
    const entries = try image.map(table_rva, @intCast(count * 4));
    try protected.include(image, table_rva, entries.len);
    var previous: u32 = 0;
    for (0..@intCast(count)) |i| {
        const target = try read(u32, entries, i * 4);
        if (target <= previous) return error.InvalidCfg;
        try image.executable(target, 1);
        previous = target;
    }
    return .metadata_present;
}

// Byte scanning is deliberately reported only for recognized path forms and
// explicit caller prefixes: arbitrary relative/compressed paths are not proven
// absent. Scan every offset (including unaligned UTF-16LE), never execute data.
fn sourcePaths(bytes: []const u8, forbidden: []const []const u8) !void {
    for (forbidden) |prefix| if (prefix.len == 0) return error.InvalidPolicy;
    for (0..bytes.len) |offset| {
        inline for (.{ @as(usize, 1), @as(usize, 2) }) |stride| {
            const tail = bytes[offset..];
            inline for (.{ "RSDS", "NB10", ".pdb", "/home/", "/Users/", "/build/", "/workspace/", "\\\\" }) |pattern| {
                if (matches(tail, pattern, stride)) return error.DebugOrSourcePath;
            }
            for (forbidden) |prefix| if (matches(tail, prefix, stride)) return error.DebugOrSourcePath;
            if (tail.len >= 3 * stride and std.ascii.isAlphabetic(tail[0]) and
                (stride == 1 or tail[1] == 0) and
                (matches(tail[stride..], ":/", stride) or matches(tail[stride..], ":\\", stride))) return error.DebugOrSourcePath;
        }
    }
}

fn matches(bytes: []const u8, pattern: []const u8, stride: usize) bool {
    if (pattern.len > bytes.len / stride) return false;
    for (pattern, 0..) |c, i| {
        if (std.ascii.toLower(bytes[i * stride]) != std.ascii.toLower(c)) return false;
        if (stride == 2 and bytes[i * stride + 1] != 0) return false;
    }
    return true;
}

pub fn main(init: std.process.Init) void {
    run(init) catch |err| {
        std.debug.print("PE static audit rejected: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn run(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedOnePePath;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], init.gpa, .limited(max_image_bytes));
    defer init.gpa.free(bytes);
    // This CLI deliberately admits only the link fixture's fixed profile.
    // Callers for other roles must review an explicit Policy via the Zig API.
    const report = try audit(bytes, .{ .imports = &.{.{ .dll = "kernel32.dll", .functions = &.{"ExitProcess"} }} });
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    std.debug.print("PE static audit accepted: profile=fixture machine=amd64 subsystem=console sections={d} imports={d} nx=true aslr=true high_entropy=true cfg={s} empty_repro_marker={} sha256={s}\n", .{
        report.sections, report.imports, @tagName(report.cfg), report.empty_repro_marker, std.fmt.bytesToHex(digest, .lower),
    });
    std.debug.print("Scope: static single-image metadata; recognized source-path forms only; no runtime, transitive, manifest or product-closure claim.\n", .{});
}
