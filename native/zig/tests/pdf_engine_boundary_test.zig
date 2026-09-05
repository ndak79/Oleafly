const std = @import("std");
const pdfium = @import("pdfium");
const contract = @import("pdfium_contract");

const required_symbols = [_][]const u8{
    "FPDF_InitLibraryWithConfig",  "FPDF_DestroyLibrary",      "FPDF_SetSandBoxPolicy",
    "FPDF_LoadMemDocument",        "FPDF_GetLastError",        "FPDF_CloseDocument",
    "FPDF_GetPageCount",           "FPDF_LoadPage",            "FPDF_ClosePage",
    "FPDF_GetPageWidth",           "FPDF_GetPageHeight",       "FPDFBitmap_CreateEx",
    "FPDFBitmap_FillRect",         "FPDFBitmap_GetBuffer",     "FPDFBitmap_GetWidth",
    "FPDFBitmap_GetHeight",        "FPDFBitmap_GetStride",     "FPDFBitmap_Destroy",
    "FPDF_RenderPageBitmap_Start", "FPDF_RenderPage_Continue", "FPDF_RenderPage_Close",
    "FPDFText_LoadPage",           "FPDFText_ClosePage",       "FPDFText_CountChars",
    "FPDFText_GetUnicode",         "FPDFText_GetCharBox",      "FPDFText_GetText",
    "FPDFText_FindStart",          "FPDFText_FindNext",        "FPDFText_FindPrev",
    "FPDFText_GetSchResultIndex",  "FPDFText_GetSchCount",     "FPDFText_FindClose",
    "FPDFLink_Enumerate",          "FPDFLink_GetAnnotRect",
};

test "table and allowlist contain every required symbol exactly once and nothing else" {
    if (comptime @hasDecl(pdfium, "Table")) {
        const fields = @typeInfo(pdfium.Table).@"struct".fields;
        try std.testing.expectEqual(required_symbols.len, fields.len);
        try std.testing.expectEqual(required_symbols.len, pdfium.required_symbols.len);
        inline for (fields) |field| {
            var required_count: usize = 0;
            var admitted_count: usize = 0;
            for (required_symbols) |name| {
                if (std.mem.eql(u8, name, field.name)) required_count += 1;
            }
            for (pdfium.required_symbols) |name| {
                if (std.mem.eql(u8, name, field.name)) admitted_count += 1;
            }
            try std.testing.expectEqual(@as(usize, 1), required_count);
            try std.testing.expectEqual(@as(usize, 1), admitted_count);
            try std.testing.expect(field.default_value_ptr == null);
        }
    } else return error.MissingPdfiumTable;
}

test "active content file loading and unreviewed experimental symbols are absent" {
    if (comptime @hasDecl(pdfium, "Table")) {
        inline for (.{
            "FPDFDOC_InitFormFillEnvironment",  "FPDFDOC_ExitFormFillEnvironment",
            "FORM_DoDocumentJSAction",          "FORM_DoDocumentOpenAction",
            "FORM_DoPageAAction",               "FPDF_LoadXFA",
            "FPDF_GetXFAPacketCount",           "FPDF_GetXFAPacketContent",
            "FPDFDoc_GetJavaScriptActionCount", "FPDFDoc_GetJavaScriptAction",
            "FPDFJavaScriptAction_GetScript",   "FPDF_SetSystemFontInfo",
            "FPDF_LoadDocument",                "FPDF_LoadCustomDocument",
            "FPDFAvail_Create",                 "FPDF_LoadMemDocument64",
            "FPDF_GetPageWidthF",               "FPDF_GetPageHeightF",
            "FPDFPage_GetAnnot",                "FPDFAnnot_GetRect",
            "FPDF_RenderPageBitmap",
        }) |symbol| {
            try std.testing.expect(!@hasField(pdfium.Table, symbol));
        }
        inline for (.{ "FPDF_FORMHANDLE", "FPDF_FORMFILLINFO", "FPDF_FILEHANDLER", "FPDF_FILEACCESS", "FPDF_SYSTEMFONTINFO" }) |name| {
            try std.testing.expect(!@hasDecl(pdfium, name));
        }
    } else return error.MissingPdfiumTable;
}

// Parse code, not comments: declarations can describe the later worker, but
// imports, callable bodies, external functions and mutable state cannot enter
// this static-only module. Only layout-check builtins are admitted.
fn expectDeclarativeSource(source: [:0]const u8) !void {
    var tree = try std.zig.Ast.parse(std.testing.allocator, source, .zig);
    defer tree.deinit(std.testing.allocator);
    if (tree.errors.len != 0) return error.InvalidSource;
    for (tree.nodes.items(.tag)) |tag| switch (tag) {
        .fn_decl, .call, .call_comma, .call_one, .call_one_comma => return error.ExecutableSource,
        else => {},
    };
    var tokenizer = std.zig.Tokenizer.init(source);
    var previous: std.zig.Token.Tag = .eof;
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) break;
        const spelling = source[token.loc.start..token.loc.end];
        if (token.tag == .doc_comment or token.tag == .container_doc_comment) continue;
        if (previous == .keyword_extern and token.tag != .keyword_struct) return error.ExternalBinding;
        switch (token.tag) {
            .keyword_export, .keyword_var, .keyword_threadlocal, .keyword_asm, .keyword_test => return error.ExecutableSource,
            .builtin => {
                var admitted = false;
                for ([_][]const u8{ "@sizeOf", "@alignOf", "@offsetOf", "@compileError" }) |name| {
                    admitted = admitted or std.mem.eql(u8, spelling, name);
                }
                if (!admitted) return error.ImportOrExecutableBuiltin;
            },
            else => {},
        }
        previous = token.tag;
    }
}

test "PDFium module is declarative with no import loader or function execution" {
    try expectDeclarativeSource(contract.source ++ "");
    if (!@hasDecl(pdfium, "Table")) return error.MissingPdfiumTable;
}

test "static-only source guard rejects plausible loader and execution mutations" {
    try std.testing.expectError(error.ImportOrExecutableBuiltin, expectDeclarativeSource("const os = @import(\"std\");"));
    try std.testing.expectError(error.ImportOrExecutableBuiltin, expectDeclarativeSource("const c = @cImport({});"));
    try std.testing.expectError(error.ImportOrExecutableBuiltin, expectDeclarativeSource("const f = @extern(*const fn () void, .{ .name = \"FPDF_DestroyLibrary\" });"));
    try std.testing.expectError(error.ExternalBinding, expectDeclarativeSource("extern fn FPDF_DestroyLibrary() void;"));
    try std.testing.expectError(error.ExecutableSource, expectDeclarativeSource("fn load() void {}"));
    try std.testing.expectError(error.ExecutableSource, expectDeclarativeSource("var loaded: bool = false;"));
    try std.testing.expectError(error.ExecutableSource, expectDeclarativeSource("const loaded = load();"));
    try expectDeclarativeSource("// @import and LoadLibraryExW in comments are not code.\npub const F = *const fn () callconv(.winapi) void;");
}
