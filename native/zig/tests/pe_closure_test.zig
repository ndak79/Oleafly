const std = @import("std");
const closure = @import("pe_closure");
const pe = @import("pe_audit");

const t = std.testing;
const opt = 0x98;
const section_table = 0x188;

fn put(comptime T: type, bytes: []u8, offset: usize, value: T) void {
    std.mem.writeInt(T, bytes[offset..][0..@sizeOf(T)], value, .little);
}

fn directory(bytes: []u8, index: usize, rva: u32, size: u32) void {
    put(u32, bytes, opt + 112 + index * 8, rva);
    put(u32, bytes, opt + 116 + index * 8, size);
}

// Independent hand-encoded PE32+ input. It is parsed as bytes and never
// mapped, launched, or treated as shipped-image evidence.
fn peFixture() [0xc00]u8 {
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

const image = peFixture();
const functions = [_][]const u8{"ExitProcess"};
const pe_imports = [_]pe.Import{.{ .dll = "kernel32.dll", .functions = &functions }};
const pe_policy: pe.Policy = .{ .imports = &pe_imports };

const ui_modules = [_][]const u8{"bin/scintilla.dll"};
const empty_modules = [_][]const u8{};
const imports = [_][]const u8{"kernel32.dll!ExitProcess"};
const ui_resources = [_][]const u8{"resources/TExFlow.exe.manifest"};
const pdf_resources = [_][]const u8{"resources/TExFlow.PdfWorker.exe.manifest"};
const science_resources = [_][]const u8{"resources/TExFlow.ScienceWorker.exe.manifest"};
const pdf_modules = [_][]const u8{"bin/pdfium.dll"};

const audit_policy: closure.Policy = .{ .roles = &.{
    .{
        .name = "UI",
        .image_path = "bin/TExFlow.exe",
        .pe_policy = pe_policy,
        .modules = &ui_modules,
        .imports = &imports,
        .resources = &ui_resources,
    },
    .{
        .name = "PdfWorker",
        .image_path = "bin/TExFlow.PdfWorker.exe",
        .pe_policy = pe_policy,
        .modules = &pdf_modules,
        .imports = &imports,
        .resources = &pdf_resources,
    },
    .{
        .name = "ScienceWorker",
        .image_path = "bin/TExFlow.ScienceWorker.exe",
        .pe_policy = pe_policy,
        .modules = &empty_modules,
        .imports = &imports,
        .resources = &science_resources,
    },
} };

fn roleNode(role: []const u8, path: []const u8, modules: []const []const u8, resources: []const []const u8) closure.RoleBinary {
    return .{
        .role = role,
        .path = path,
        .pe_bytes = &image,
        .modules = modules,
        .imports = &imports,
        .resources = resources,
    };
}

test "fixture closure recursively audits the exact role set" {
    const pdf = roleNode("PdfWorker", "bin/TExFlow.PdfWorker.exe", &pdf_modules, &pdf_resources);
    const science = roleNode("ScienceWorker", "bin/TExFlow.ScienceWorker.exe", &empty_modules, &science_resources);
    const children = [_]closure.RoleBinary{ pdf, science };
    var ui = roleNode("UI", "bin/TExFlow.exe", &ui_modules, &ui_resources);
    ui.children = &children;
    const roots = [_]closure.RoleBinary{ui};

    const report = try closure.auditManifest(.{ .binaries = &roots }, audit_policy);
    try t.expectEqual(@as(usize, 3), report.binaries);
    try t.expectEqual(@as(usize, 2), report.modules);
    try t.expectEqual(@as(usize, 3), report.imports);
    try t.expectEqual(@as(usize, 3), report.resources);
}

test "role inventory rejects missing extra and duplicate roles" {
    const ui = roleNode("UI", "bin/TExFlow.exe", &ui_modules, &ui_resources);
    const pdf = roleNode("PdfWorker", "bin/TExFlow.PdfWorker.exe", &pdf_modules, &pdf_resources);
    const science = roleNode("ScienceWorker", "bin/TExFlow.ScienceWorker.exe", &empty_modules, &science_resources);

    const missing = [_]closure.RoleBinary{ ui, pdf };
    try t.expectError(error.MissingRole, closure.auditManifest(.{ .binaries = &missing }, audit_policy));

    const extra_node = roleNode("Installer", "bin/Installer.exe", &empty_modules, &empty_modules);
    const extra = [_]closure.RoleBinary{ ui, pdf, science, extra_node };
    try t.expectError(error.UnexpectedRole, closure.auditManifest(.{ .binaries = &extra }, audit_policy));

    const duplicate = [_]closure.RoleBinary{ ui, pdf, science, ui };
    try t.expectError(error.DuplicateRole, closure.auditManifest(.{ .binaries = &duplicate }, audit_policy));
}

test "module import and resource paths must match the role policy" {
    const pdf = roleNode("PdfWorker", "bin/TExFlow.PdfWorker.exe", &pdf_modules, &pdf_resources);
    const science = roleNode("ScienceWorker", "bin/TExFlow.ScienceWorker.exe", &empty_modules, &science_resources);

    var bad_module = roleNode("UI", "bin/TExFlow.exe", &ui_modules, &ui_resources);
    bad_module.modules = &.{"bin/unexpected.dll"};
    const module_nodes = [_]closure.RoleBinary{ bad_module, pdf, science };
    try t.expectError(error.UnexpectedModulePath, closure.auditManifest(.{ .binaries = &module_nodes }, audit_policy));

    var bad_import = roleNode("UI", "bin/TExFlow.exe", &ui_modules, &ui_resources);
    bad_import.imports = &.{"advapi32.dll!RegOpenKeyW"};
    const import_nodes = [_]closure.RoleBinary{ bad_import, pdf, science };
    try t.expectError(error.UnexpectedImportPath, closure.auditManifest(.{ .binaries = &import_nodes }, audit_policy));

    var bad_resource = roleNode("UI", "bin/TExFlow.exe", &ui_modules, &ui_resources);
    bad_resource.resources = &.{"resources/other.manifest"};
    const resource_nodes = [_]closure.RoleBinary{ bad_resource, pdf, science };
    try t.expectError(error.UnexpectedResourcePath, closure.auditManifest(.{ .binaries = &resource_nodes }, audit_policy));
}

test "metadata comparison is a true set equality check" {
    const pair_modules = [_][]const u8{ "bin/a.dll", "bin/b.dll" };
    const pair_roles = [_]closure.RolePolicy{.{
        .name = "UI",
        .image_path = "bin/TExFlow.exe",
        .pe_policy = pe_policy,
        .modules = &pair_modules,
        .imports = &imports,
        .resources = &ui_resources,
    }};
    const pair_policy: closure.Policy = .{ .roles = &pair_roles };

    var duplicate = roleNode("UI", "bin/TExFlow.exe", &pair_modules, &ui_resources);
    const duplicate_modules = [_][]const u8{ "bin/a.dll", "bin/a.dll" };
    duplicate.modules = &duplicate_modules;
    const duplicate_nodes = [_]closure.RoleBinary{duplicate};
    try t.expectError(error.DuplicateMetadata, closure.auditManifest(.{ .binaries = &duplicate_nodes }, pair_policy));

    var omission = roleNode("UI", "bin/TExFlow.exe", &pair_modules, &ui_resources);
    const omission_modules = [_][]const u8{"bin/a.dll"};
    omission.modules = &omission_modules;
    const omission_nodes = [_]closure.RoleBinary{omission};
    try t.expectError(error.UnexpectedModulePath, closure.auditManifest(.{ .binaries = &omission_nodes }, pair_policy));
}

test "Scintilla PDFium and Lexilla cannot cross role boundaries" {
    const science = roleNode("ScienceWorker", "bin/TExFlow.ScienceWorker.exe", &empty_modules, &science_resources);
    const ui = roleNode("UI", "bin/TExFlow.exe", &ui_modules, &ui_resources);

    var pdf_scintilla = roleNode("PdfWorker", "bin/TExFlow.PdfWorker.exe", &pdf_modules, &pdf_resources);
    pdf_scintilla.modules = &.{"bin/scintilla.dll"};
    const scintilla_nodes = [_]closure.RoleBinary{ ui, pdf_scintilla, science };
    try t.expectError(error.CrossRoleEdge, closure.auditManifest(.{ .binaries = &scintilla_nodes }, audit_policy));

    var ui_pdfium = roleNode("UI", "bin/TExFlow.exe", &ui_modules, &ui_resources);
    ui_pdfium.modules = &.{"bin/pdfium.dll"};
    const pdfium_nodes = [_]closure.RoleBinary{ ui_pdfium, roleNode("PdfWorker", "bin/TExFlow.PdfWorker.exe", &pdf_modules, &pdf_resources), science };
    try t.expectError(error.CrossRoleEdge, closure.auditManifest(.{ .binaries = &pdfium_nodes }, audit_policy));

    var ui_lexilla = roleNode("UI", "bin/TExFlow.exe", &ui_modules, &ui_resources);
    ui_lexilla.resources = &.{"resources/lexilla.catalog"};
    const lexilla_nodes = [_]closure.RoleBinary{ ui_lexilla, roleNode("PdfWorker", "bin/TExFlow.PdfWorker.exe", &pdf_modules, &pdf_resources), science };
    try t.expectError(error.CrossRoleEdge, closure.auditManifest(.{ .binaries = &lexilla_nodes }, audit_policy));

    var mixed_case = roleNode("PdfWorker", "bin/TExFlow.PdfWorker.exe", &pdf_modules, &pdf_resources);
    mixed_case.modules = &.{"bin/SCINTILLA.DLL"};
    const mixed_case_nodes = [_]closure.RoleBinary{ ui, mixed_case, science };
    try t.expectError(error.CrossRoleEdge, closure.auditManifest(.{ .binaries = &mixed_case_nodes }, audit_policy));
}

test "closure audit rejects malformed paths and PE bytes" {
    const pdf = roleNode("PdfWorker", "bin/TExFlow.PdfWorker.exe", &pdf_modules, &pdf_resources);
    const science = roleNode("ScienceWorker", "bin/TExFlow.ScienceWorker.exe", &empty_modules, &science_resources);
    const bad_path = roleNode("UI", "bin/../TExFlow.exe", &ui_modules, &ui_resources);
    const bad_path_nodes = [_]closure.RoleBinary{ bad_path, pdf, science };
    try t.expectError(error.InvalidPath, closure.auditManifest(.{ .binaries = &bad_path_nodes }, audit_policy));

    var bad_bytes = image;
    bad_bytes[0] = 'X';
    var bad_pe = roleNode("UI", "bin/TExFlow.exe", &ui_modules, &ui_resources);
    bad_pe.pe_bytes = &bad_bytes;
    const bad_pe_nodes = [_]closure.RoleBinary{ bad_pe, pdf, science };
    try t.expectError(error.PeRejected, closure.auditManifest(.{ .binaries = &bad_pe_nodes }, audit_policy));
}

test "closure traversal is bounded" {
    const pdf = roleNode("PdfWorker", "bin/TExFlow.PdfWorker.exe", &pdf_modules, &pdf_resources);
    const science = roleNode("ScienceWorker", "bin/TExFlow.ScienceWorker.exe", &empty_modules, &science_resources);
    const children = [_]closure.RoleBinary{ pdf, science };
    var ui = roleNode("UI", "bin/TExFlow.exe", &ui_modules, &ui_resources);
    ui.children = &children;
    const roots = [_]closure.RoleBinary{ui};
    var bounded = audit_policy;
    bounded.max_depth = 0;
    try t.expectError(error.ClosureTooDeep, closure.auditManifest(.{ .binaries = &roots }, bounded));
}
