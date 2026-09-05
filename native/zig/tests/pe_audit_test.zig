const std = @import("std");
const pe = @import("pe_audit");
const artifact = @import("pe_artifact");
const t = std.testing;
const policy: pe.Policy = .{ .imports = &.{.{ .dll = "kernel32.dll", .functions = &.{"ExitProcess"} }} };
const opt = 0x98;
const section_table = 0x188;

fn put(comptime T: type, bytes: []u8, offset: usize, value: T) void {
    std.mem.writeInt(T, bytes[offset..][0..@sizeOf(T)], value, .little);
}

fn directory(bytes: []u8, index: usize, rva: u32, size: u32) void {
    put(u32, bytes, opt + 112 + index * 8, rva);
    put(u32, bytes, opt + 116 + index * 8, size);
}

// Independent hand-encoded PE32+ with named import, IAT and a DIR64 relocation.
// This is input data for the parser, never a runtime-loaded fixture.
fn fixture() [0xc00]u8 {
    var b = [_]u8{0} ** 0xc00;
    @memcpy(b[0..2], "MZ");
    put(u32, &b, 0x3c, 0x80);
    @memcpy(b[0x80..0x84], "PE\x00\x00");
    put(u16, &b, 0x84, 0x8664);
    put(u16, &b, 0x86, 4);
    put(u16, &b, 0x94, 240);
    put(u16, &b, 0x96, 0x22);
    put(u16, &b, opt, 0x20b);
    put(u32, &b, opt + 16, 0x1000);
    put(u64, &b, opt + 24, 0x140000000);
    put(u32, &b, opt + 32, 0x1000);
    put(u32, &b, opt + 36, 0x200);
    put(u32, &b, opt + 56, 0x5000);
    put(u32, &b, opt + 60, 0x400);
    put(u16, &b, opt + 68, 3);
    put(u16, &b, opt + 70, 0x160);
    put(u32, &b, opt + 108, 16);
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

fn cfgFixture() [0xc00]u8 {
    var b = fixture();
    put(u16, &b, opt + 70, 0x4160);
    directory(&b, 10, 0x20c0, 148);
    put(u32, &b, 0x6c0, 148);
    put(u64, &b, 0x6c0 + 112, 0x140003040);
    put(u64, &b, 0x6c0 + 120, 0x140003048);
    put(u64, &b, 0x6c0 + 128, 0x140002180);
    put(u64, &b, 0x6c0 + 136, 1);
    put(u32, &b, 0x6c0 + 144, 0x500);
    put(u32, &b, 0x780, 0x1000);
    put(u64, &b, 0x840, 0x140001000);
    put(u64, &b, 0x848, 0x140001000);
    return b;
}

test "valid PE reports exact sections imports and absent CFG honestly" {
    const report = try pe.audit(&fixture(), policy);
    try t.expectEqual(@as(usize, 4), report.sections);
    try t.expectEqual(@as(usize, 1), report.imports);
    try t.expectEqual(pe.Cfg.not_declared, report.cfg);
}

test "every truncation fails deterministically without a trap" {
    const b = fixture();
    for (0..b.len) |len| {
        if (pe.audit(b[0..len], policy)) |_| return error.AcceptedTruncation else |first| {
            try t.expectError(first, pe.audit(b[0..len], policy));
        }
    }
}

test "DOS PE architecture optional header and subsystem are mandatory" {
    for ([_]struct { offset: usize, value: u16, err: anyerror }{
        .{ .offset = 0, .value = 0, .err = error.InvalidDosHeader },
        .{ .offset = 0x80, .value = 0, .err = error.InvalidPeSignature },
        .{ .offset = 0x84, .value = 0x14c, .err = error.UnsupportedMachine },
        .{ .offset = opt, .value = 0x10b, .err = error.UnsupportedOptionalHeader },
        .{ .offset = opt + 68, .value = 2, .err = error.SubsystemMismatch },
        .{ .offset = 0x94, .value = 239, .err = error.UnsupportedOptionalHeader },
    }) |c| {
        var b = fixture();
        put(u16, &b, c.offset, c.value);
        try t.expectError(c.err, pe.audit(&b, policy));
    }
    var b = fixture();
    put(u32, &b, 0x3c, 0xfffffff0);
    try t.expectError(error.Truncated, pe.audit(&b, policy));
}

test "section W plus X unknown flags and debug sections are forbidden" {
    for ([_]u32{ 0xe0000020, 0x60000021, 0x20000020 }) |flags| {
        var b = fixture();
        put(u32, &b, section_table + 36, flags);
        try t.expectError(error.UnsafeSection, pe.audit(&b, policy));
    }
    var b = fixture();
    @memcpy(b[section_table..][0..8], ".debug\x00\x00");
    try t.expectError(error.DebugMetadata, pe.audit(&b, policy));
}

test "overlapping raw and RVA ranges are ambiguous and fail closed" {
    for ([_]usize{ 12, 20 }) |field| {
        var b = fixture();
        put(u32, &b, section_table + 40 + field, if (field == 12) 0x1000 else 0x400);
        if (field == 12) {
            try t.expectError(error.InvalidLayout, pe.audit(&b, policy));
        } else {
            try t.expectError(error.OverlappingSections, pe.audit(&b, policy));
        }
    }
}

test "overflow misalignment virtual tails and image limits fail closed" {
    for ([_]struct { offset: usize, value: u32 }{
        .{ .offset = section_table + 12, .value = 0xfffff000 },
        .{ .offset = section_table + 20, .value = 0xfffffe00 },
        .{ .offset = section_table + 20, .value = 0x401 },
        .{ .offset = opt + 32, .value = 0 },
        .{ .offset = opt + 56, .value = 0x2000 },
        .{ .offset = opt + 16, .value = 0x3000 },
    }) |c| {
        var b = fixture();
        put(u32, &b, c.offset, c.value);
        if (pe.audit(&b, policy)) |_| return error.AcceptedInvalidLayout else |_| {}
    }
    var b = fixture();
    put(u32, &b, section_table + 40 + 8, 0x400);
    directory(&b, 1, 0x2200, 40);
    try t.expectError(error.UnmappedRva, pe.audit(&b, policy));
}

test "each NX ASLR high entropy bit and actual relocations are required" {
    for ([_]u16{ 0x20, 0x40, 0x100 }) |bit| {
        var b = fixture();
        put(u16, &b, opt + 70, 0x160 & ~bit);
        try t.expectError(error.MissingMitigation, pe.audit(&b, policy));
    }
    var b = fixture();
    directory(&b, 5, 0, 0);
    try t.expectError(error.MissingRelocations, pe.audit(&b, policy));
    b = fixture();
    put(u16, &b, 0xa08, 0x3020);
    try t.expectError(error.UnsupportedRelocation, pe.audit(&b, policy));
    b = fixture();
    put(u32, &b, 0xa04, 0xfffffff0);
    try t.expectError(error.InvalidRelocations, pe.audit(&b, policy));
}

test "DLL names are case insensitive but function allowlist is exact" {
    var b = fixture();
    b[0x6a2] = 'e';
    try t.expectError(error.DisallowedImport, pe.audit(&b, policy));
    b = fixture();
    b[0x680] = 'X';
    try t.expectError(error.DisallowedImport, pe.audit(&b, policy));
    try t.expectError(error.DisallowedImport, pe.audit(&fixture(), .{ .imports = &.{} }));
}

test "PE32+ named thunk accepts only a 31-bit hint-name RVA" {
    var b = fixture();
    put(u64, &b, 0x640, 0x8000_0000);
    put(u64, &b, 0x800, 0x8000_0000);
    try t.expectError(error.InvalidImportName, pe.audit(&b, policy));
}

test "IAT storage cannot alias another descriptor's lookup table" {
    var b = fixture();
    // Add a second descriptor whose lookup table starts at the first IAT.
    // Loader binding would overwrite the bytes later interpreted as the
    // second descriptor's lookup table, so the static profile rejects it.
    directory(&b, 1, 0x2000, 60);
    directory(&b, 12, 0x3000, 32);
    put(u32, &b, 0x614, 0x3000);
    put(u32, &b, 0x620, 0x2080);
    put(u32, &b, 0x624, 0x3010);
    put(u64, &b, 0x810, 0x20a0);
    try t.expectError(error.InvalidIat, pe.audit(&b, policy));
}

test "IAT storage cannot overlap a later DLL name" {
    var b = [_]u8{0} ** 0x1000;
    @memcpy(b[0..0xc00], &fixture());
    // Keep ordered virtual sections while placing the IAT over the suffix of
    // a DLL name that a later descriptor reuses. The loader's IAT write would
    // otherwise change bytes consumed by that later import audit.
    put(u32, &b, section_table + 40 + 8, 0x6c6c4000);
    put(u32, &b, section_table + 40 + 36, 0xc0000040);
    put(u32, &b, section_table + 80 + 8, 0x600);
    put(u32, &b, section_table + 80 + 12, 0x6c6c6000);
    put(u32, &b, section_table + 80 + 16, 0x600);
    put(u32, &b, section_table + 120 + 12, 0x6c6c7000);
    put(u32, &b, section_table + 120 + 20, 0xe00);
    put(u32, &b, opt + 56, 0x6c6c8000);
    directory(&b, 1, 0x2000, 60);
    directory(&b, 12, 0x2088, 32);
    directory(&b, 5, 0x6c6c7000, 12);
    put(u32, &b, 0x610, 0x2088);
    put(u32, &b, 0x614, 0x2050);
    put(u32, &b, 0x620, 0x2080);
    put(u32, &b, 0x624, 0x2098);
    put(u64, &b, 0x640, 0x6c6c642e);
    put(u64, &b, 0x650, 0x6c6c642e);
    @memset(b[0x688..0x6a8], 0);
    put(u64, &b, 0x688, 0x6c6c642e);
    put(u64, &b, 0x698, 0x6c6c642e);
    @memcpy(b[0xc30..][0..12], "ExitProcess\x00");
    put(u32, &b, 0xe00, 0x6c6c6000);
    put(u32, &b, 0xe04, 12);
    put(u16, &b, 0xe08, 0xa020);
    try t.expectError(error.InvalidIat, pe.audit(&b, policy));
}

test "section table follows canonical ascending adjacent VAs and PE32+ size cap" {
    var b = fixture();
    var first: [40]u8 = undefined;
    @memcpy(&first, b[section_table..][0..40]);
    @memcpy(b[section_table..][0..40], b[section_table + 40 ..][0..40]);
    @memcpy(b[section_table + 40 ..][0..40], &first);
    try t.expectError(error.InvalidLayout, pe.audit(&b, policy));

    b = fixture();
    put(u32, &b, opt + 56, 0x8000_0000);
    try t.expectError(error.InvalidLayout, pe.audit(&b, policy));
}

test "ordinal bound delay imports and unsupported directories cannot bypass policy" {
    var b = fixture();
    put(u64, &b, 0x640, 0x8000000000000001);
    try t.expectError(error.OrdinalImport, pe.audit(&b, policy));
    b = fixture();
    put(u32, &b, 0x604, 1);
    try t.expectError(error.BoundImport, pe.audit(&b, policy));
    for ([_]usize{ 0, 2, 7, 8, 9, 11, 13, 14, 15 }) |index| {
        b = fixture();
        directory(&b, index, 0x2000, 16);
        try t.expectError(error.UnsupportedDirectory, pe.audit(&b, policy));
    }
}

test "import descriptor thunk name and IAT truncation is rejected" {
    var b = fixture();
    directory(&b, 1, 0x2000, 20);
    try t.expectError(error.UnterminatedImports, pe.audit(&b, policy));
    b = fixture();
    put(u32, &b, 0x600, 0x21f8);
    put(u64, &b, 0x7f8, 0x20a0);
    try t.expectError(error.UnmappedRva, pe.audit(&b, policy));
    b = fixture();
    put(u32, &b, 0x60c, 0x21f0);
    @memset(b[0x7f0..0x800], 'a');
    try t.expectError(error.UnterminatedString, pe.audit(&b, policy));
    b = fixture();
    put(u64, &b, 0x800, 0x20b0);
    try t.expectError(error.InvalidIat, pe.audit(&b, policy));
}

test "debug directory COFF symbols and trailing overlays fail closed" {
    var b = fixture();
    directory(&b, 6, 0x20c0, 28);
    try t.expectError(error.DebugMetadata, pe.audit(&b, policy));
    b = fixture();
    put(u32, &b, 0x8c, 0x600);
    try t.expectError(error.DebugMetadata, pe.audit(&b, policy));
    var overlay = [_]u8{0} ** 0xc01;
    @memcpy(overlay[0..0xc00], &fixture());
    try t.expectError(error.TrailingData, pe.audit(&overlay, policy));
}

test "recognized source debug paths and custom prefixes are absent in ASCII and UTF16" {
    for ([_][]const u8{ "C:\\dev\\main.zig", "/home/alice/main.zig", "\\\\host\\src", "foo.PDB", "RSDS", "NB10" }) |path| {
        var b = fixture();
        @memcpy(b[0x880..][0..path.len], path);
        try t.expectError(error.DebugOrSourcePath, pe.audit(&b, policy));
        b = fixture();
        for (path, 0..) |byte, i| b[0x880 + i * 2] = byte;
        try t.expectError(error.DebugOrSourcePath, pe.audit(&b, policy));
    }
    var b = fixture();
    @memcpy(b[0x880..][0..11], "private/src");
    var custom = policy;
    custom.forbidden_paths = &.{"private/src"};
    try t.expectError(error.DebugOrSourcePath, pe.audit(&b, custom));
}

test "CFG requirement does not accept header bits without metadata" {
    var required = policy;
    required.require_cfg = true;
    try t.expectError(error.MissingCfg, pe.audit(&fixture(), required));
    var b = fixture();
    put(u16, &b, opt + 70, 0x4160);
    try t.expectError(error.InvalidCfg, pe.audit(&b, policy));
    b = cfgFixture();
    try t.expectEqual(pe.Cfg.metadata_present, (try pe.audit(&b, required)).cfg);
}

test "CFG contradictory metadata unknown flags bogus pointers and invalid targets fail" {
    for ([_]struct { offset: usize, value: u32 }{
        .{ .offset = 0x6c0, .value = 147 },
        .{ .offset = 0x6c0 + 144, .value = 0x100 },
        .{ .offset = 0x6c0 + 144, .value = 0x80000500 },
        .{ .offset = 0x780, .value = 0x3000 },
    }) |c| {
        var b = cfgFixture();
        put(u32, &b, c.offset, c.value);
        try t.expectError(error.InvalidCfg, pe.audit(&b, policy));
    }
    var b = cfgFixture();
    put(u64, &b, 0x6c0 + 128, 0xffffffffffffffff);
    try t.expectError(error.InvalidCfg, pe.audit(&b, policy));
    b = cfgFixture();
    put(u16, &b, opt + 70, 0x160);
    try t.expectError(error.InvalidCfg, pe.audit(&b, policy));
}

test "unknown directory count and malformed directory pairs are rejected" {
    var b = fixture();
    put(u32, &b, opt + 108, 17);
    try t.expectError(error.UnsupportedDirectories, pe.audit(&b, policy));
    b = fixture();
    directory(&b, 1, 0, 40);
    try t.expectError(error.InvalidDirectory, pe.audit(&b, policy));
}

test "linker-produced Windows fixture is audited as bytes without launch" {
    if (comptime @import("builtin").os.tag != .windows) return error.SkipZigTest;
    if (comptime artifact.path.len == 0) return error.MissingPeFixture;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(t.io, artifact.path, t.allocator, .limited(1024 * 1024));
    defer t.allocator.free(bytes);
    const report = try pe.audit(bytes, policy);
    try t.expectEqual(@as(usize, 1), report.imports);
    try t.expectEqual(pe.Cfg.not_declared, report.cfg);
    try t.expect(report.sections >= 3);
}

test "only an empty reproducibility marker is accepted in the debug directory" {
    var b = fixture();
    directory(&b, 6, 0x20c0, 28);
    put(u32, &b, 0x6cc, 16);
    _ = try pe.audit(&b, policy);
    put(u32, &b, 0x88, 0x12345678);
    put(u32, &b, 0x6c4, 0x12345678);
    try t.expect((try pe.audit(&b, policy)).empty_repro_marker);
    for ([_]usize{ 0, 4, 8, 16, 20, 24 }) |offset| {
        var mutant = b;
        put(u32, &mutant, 0x6c0 + offset, 1);
        try t.expectError(error.DebugMetadata, pe.audit(&mutant, policy));
    }
    put(u32, &b, 0x6cc, 2);
    try t.expectError(error.DebugMetadata, pe.audit(&b, policy));
}

test "exception leaf metadata rejects unwind flags opcodes and extensions" {
    var b = fixture();
    directory(&b, 3, 0x20c0, 12);
    put(u32, &b, 0x6c0, 0x1000);
    put(u32, &b, 0x6c4, 0x1001);
    put(u32, &b, 0x6c8, 0x20d0);
    b[0x6d0] = 1;
    _ = try pe.audit(&b, policy);
    for ([_]usize{ 0, 1, 2, 3 }) |offset| {
        var mutant = b;
        mutant[0x6d0 + offset] = if (offset == 0) 9 else 1;
        try t.expectError(error.UnsupportedUnwind, pe.audit(&mutant, policy));
    }
}

test "fixed-seed hostile bytes and structured bit mutations never trap or vary" {
    // This invariant supplements named rejection oracles; it is not evidence
    // that arbitrary mutations must fail (some merely alter executable data).
    var random = std.Random.DefaultPrng.init(0x70655f6175646974);
    var bytes: [2048]u8 = undefined;
    for (0..256) |_| {
        random.random().bytes(&bytes);
        const len = random.random().uintLessThan(usize, bytes.len + 1);
        if (pe.audit(bytes[0..len], policy)) |_| return error.AcceptedRandomBytes else |err| {
            try t.expectError(err, pe.audit(bytes[0..len], policy));
        }
    }
    const original = cfgFixture();
    for (0..original.len) |offset| {
        // Cover every byte of the structured input, including populated
        // pointer/length fields deep beyond the DOS/COFF headers.
        var mutant = original;
        mutant[offset] ^= 0x80;
        if (pe.audit(&mutant, policy)) |first| {
            try t.expectEqualDeep(first, try pe.audit(&mutant, policy));
        } else |err| try t.expectError(err, pe.audit(&mutant, policy));
    }
}

test "relocations need real unique DIR64 targets and section-backed storage" {
    var b = fixture();
    put(u16, &b, 0xa08, 0);
    try t.expectError(error.MissingRelocations, pe.audit(&b, policy));
    b = fixture();
    put(u16, &b, 0xa0a, 0xa020);
    try t.expectError(error.InvalidRelocations, pe.audit(&b, policy));
    b = fixture();
    put(u16, &b, 0xa08, 0xafff);
    try t.expectError(error.InvalidRelocations, pe.audit(&b, policy));
    b = fixture();
    put(u32, &b, 0xa00, 0x7000);
    try t.expectError(error.UnmappedRva, pe.audit(&b, policy));
}

test "sparse IAT and invalid required-policy path prefixes fail closed" {
    var b = fixture();
    directory(&b, 12, 0x3000, 24);
    try t.expectError(error.InvalidIat, pe.audit(&b, policy));
    var invalid = policy;
    invalid.forbidden_paths = &.{""};
    try t.expectError(error.InvalidPolicy, pe.audit(&fixture(), invalid));
}

fn retargetRelocation(bytes: []u8, rva: u32) void {
    put(u32, bytes, 0xa00, rva & ~@as(u32, 0xfff));
    put(u16, bytes, 0xa08, 0xa000 | @as(u16, @intCast(rva & 0xfff)));
}

test "relocations cannot rewrite any exact audited import metadata or terminator" {
    var accepted: usize = 0;
    // Descriptor fields/terminator, ILT values/terminator, IAT values/terminator,
    // DLL name/NUL, function hint/name/NUL, and partial eight-byte overlaps.
    for ([_]u32{ 0x2000, 0x2008, 0x200c, 0x2010, 0x2014, 0x2027, 0x2039, 0x2040, 0x2048, 0x204f, 0x3000, 0x3008, 0x300f, 0x2079, 0x2080, 0x208c, 0x2099, 0x20a0, 0x20a2, 0x20ad }) |target| {
        var b = fixture();
        retargetRelocation(&b, target);
        if (pe.audit(&b, policy)) |_| {
            accepted += 1;
        } else |err| try t.expectEqual(error.RelocationTouchesImports, err);
    }
    try t.expectEqual(@as(usize, 0), accepted);
}

test "import envelopes conservatively protect gaps but preserve outside code and data" {
    var b = fixture();
    retargetRelocation(&b, 0x2060); // Gap between the ILT and DLL string.
    try t.expectError(error.RelocationTouchesImports, pe.audit(&b, policy));
    for ([_]u32{ 0x1008, 0x20ae, 0x3010, 0x3020 }) |target| {
        b = fixture();
        retargetRelocation(&b, target);
        _ = try pe.audit(&b, policy);
    }
}

test "relocation records cannot relocate their own headers or entries" {
    for ([_]u32{ 0x4000, 0x4004, 0x4008, 0x400b }) |target| {
        var b = fixture();
        retargetRelocation(&b, target);
        try t.expectError(error.RelocationTouchesRelocations, pe.audit(&b, policy));
    }
}

test "relocations cannot rewrite CFG fields pointer slots or function tables" {
    var accepted: usize = 0;
    for ([_]u32{ 0x20b9, 0x20c0, 0x2130, 0x2148, 0x2150, 0x2153, 0x2179, 0x2180, 0x2183, 0x3039, 0x3040, 0x3048, 0x304f }) |target| {
        var b = cfgFixture();
        retargetRelocation(&b, target);
        if (pe.audit(&b, policy)) |_| {
            accepted += 1;
        } else |err| try t.expectEqual(error.RelocationTouchesMetadata, err);
    }
    try t.expectEqual(@as(usize, 0), accepted);
    for ([_]u32{ 0x1008, 0x20ae, 0x3020, 0x3050, 0x2184 }) |target| {
        var b = cfgFixture();
        retargetRelocation(&b, target);
        try t.expectEqual(pe.Cfg.metadata_present, (try pe.audit(&b, policy)).cfg);
    }
}

test "relocations cannot rewrite exception descriptors or referenced leaf records" {
    var accepted: usize = 0;
    for ([_]u32{ 0x20b9, 0x20c0, 0x20c8, 0x20cb, 0x3039, 0x3040, 0x3043 }) |target| {
        var b = fixture();
        directory(&b, 3, 0x20c0, 12);
        put(u32, &b, 0x6c0, 0x1000);
        put(u32, &b, 0x6c4, 0x1001);
        put(u32, &b, 0x6c8, 0x3040);
        b[0x840] = 1;
        retargetRelocation(&b, target);
        if (pe.audit(&b, policy)) |_| {
            accepted += 1;
        } else |err| try t.expectEqual(error.RelocationTouchesMetadata, err);
    }
    try t.expectEqual(@as(usize, 0), accepted);
}

test "relocations cannot rewrite the empty debug reproducibility marker" {
    var accepted: usize = 0;
    for ([_]u32{ 0x20b9, 0x20c0, 0x20cc, 0x20db }) |target| {
        var b = fixture();
        directory(&b, 6, 0x20c0, 28);
        put(u32, &b, 0x6cc, 16);
        retargetRelocation(&b, target);
        if (pe.audit(&b, policy)) |_| {
            accepted += 1;
        } else |err| try t.expectEqual(error.RelocationTouchesMetadata, err);
    }
    try t.expectEqual(@as(usize, 0), accepted);
}
