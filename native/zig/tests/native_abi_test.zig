const std = @import("std");
const pdfium = @import("pdfium");

test "PDFium pinned Windows scalar widths and opaque handles" {
    if (comptime @hasDecl(pdfium, "Table")) {
        try std.testing.expect(pdfium.FPDF_BOOL == i32);
        try std.testing.expect(pdfium.FPDF_DWORD == u32);
        try std.testing.expect(pdfium.FPDF_WCHAR == u16);
        inline for (.{ pdfium.FPDF_DOCUMENT, pdfium.FPDF_PAGE, pdfium.FPDF_BITMAP, pdfium.FPDF_TEXTPAGE, pdfium.FPDF_SCHHANDLE, pdfium.FPDF_LINK }) |Handle| {
            const pointer = @typeInfo(@typeInfo(Handle).optional.child).pointer;
            try std.testing.expect(@typeInfo(pointer.child) == .@"opaque");
            try std.testing.expectEqual(@as(usize, 8), @sizeOf(Handle));
            try std.testing.expectEqual(@as(usize, 8), @alignOf(Handle));
        }
        try std.testing.expect(pdfium.FPDF_DOCUMENT != pdfium.FPDF_PAGE);
        try std.testing.expect(pdfium.FPDF_PAGE != pdfium.FPDF_BITMAP);
        try std.testing.expect(pdfium.FPDF_TEXTPAGE != pdfium.FPDF_SCHHANDLE);
    } else return error.MissingPdfiumTable;
}

test "pinned public structs retain complete Windows x64 size alignment and field offsets" {
    if (comptime @hasDecl(pdfium, "Table")) {
        try std.testing.expectEqual(@as(usize, 56), @sizeOf(pdfium.FPDF_LIBRARY_CONFIG));
        try std.testing.expectEqual(@as(usize, 8), @alignOf(pdfium.FPDF_LIBRARY_CONFIG));
        inline for (.{ "version", "m_pUserFontPaths", "m_pIsolate", "m_v8EmbedderSlot", "m_pPlatform", "m_RendererType", "m_FontLibraryType", "m_BrotliEnabled" }, .{ 0, 8, 16, 24, 32, 40, 44, 48 }) |name, offset| {
            try std.testing.expectEqual(@as(usize, offset), @offsetOf(pdfium.FPDF_LIBRARY_CONFIG, name));
        }
        try std.testing.expect(@FieldType(pdfium.FPDF_LIBRARY_CONFIG, "m_BrotliEnabled") == i32);
        try std.testing.expect(@FieldType(pdfium.FPDF_LIBRARY_CONFIG, "m_pUserFontPaths") == ?[*:null]?[*:0]const u8);
        try std.testing.expectEqual(@as(usize, 24), @sizeOf(pdfium.IFSDK_PAUSE));
        try std.testing.expectEqual(@as(usize, 8), @alignOf(pdfium.IFSDK_PAUSE));
        inline for (.{ "version", "NeedToPauseNow", "user" }, .{ 0, 8, 16 }) |name, offset| {
            try std.testing.expectEqual(@as(usize, offset), @offsetOf(pdfium.IFSDK_PAUSE, name));
        }
        // This callback has no FPDF_CALLCONV in fpdf_progressive.h.
        try std.testing.expect(@FieldType(pdfium.IFSDK_PAUSE, "NeedToPauseNow") == *const fn (*pdfium.IFSDK_PAUSE) callconv(.c) i32);
        try std.testing.expectEqual(@as(usize, 16), @sizeOf(pdfium.FS_RECTF));
        try std.testing.expectEqual(@as(usize, 4), @alignOf(pdfium.FS_RECTF));
        inline for (.{ "left", "top", "right", "bottom" }, .{ 0, 4, 8, 12 }) |name, offset| {
            try std.testing.expectEqual(@as(usize, offset), @offsetOf(pdfium.FS_RECTF, name));
            try std.testing.expect(@FieldType(pdfium.FS_RECTF, name) == f32);
        }
    } else return error.MissingPdfiumTable;
}

test "every exported signature matches the pinned public C declaration" {
    if (comptime @hasDecl(pdfium, "Table")) {
        // Independent transcription of fpdfview.h, fpdf_progressive.h,
        // fpdf_text.h and fpdf_doc.h at 6f2272e1f3aaa141305475b83ef4eac2c1f527b8.
        // Windows unsigned long is u32, including error codes and search flags.
        const D = pdfium.FPDF_DOCUMENT;
        const P = pdfium.FPDF_PAGE;
        const B = pdfium.FPDF_BITMAP;
        const T = pdfium.FPDF_TEXTPAGE;
        const S = pdfium.FPDF_SCHHANDLE;
        const L = pdfium.FPDF_LINK;
        const Expected = struct {
            FPDF_InitLibraryWithConfig: *const fn (*const pdfium.FPDF_LIBRARY_CONFIG) callconv(.winapi) void,
            FPDF_DestroyLibrary: *const fn () callconv(.winapi) void,
            FPDF_SetSandBoxPolicy: *const fn (u32, i32) callconv(.winapi) void,
            FPDF_LoadMemDocument: *const fn (?*const anyopaque, i32, ?[*:0]const u8) callconv(.winapi) D,
            FPDF_GetLastError: *const fn () callconv(.winapi) u32,
            FPDF_CloseDocument: *const fn (D) callconv(.winapi) void,
            FPDF_GetPageCount: *const fn (D) callconv(.winapi) i32,
            FPDF_LoadPage: *const fn (D, i32) callconv(.winapi) P,
            FPDF_ClosePage: *const fn (P) callconv(.winapi) void,
            FPDF_GetPageWidth: *const fn (P) callconv(.winapi) f64,
            FPDF_GetPageHeight: *const fn (P) callconv(.winapi) f64,
            FPDFBitmap_CreateEx: *const fn (i32, i32, i32, ?*anyopaque, i32) callconv(.winapi) B,
            FPDFBitmap_FillRect: *const fn (B, i32, i32, i32, i32, u32) callconv(.winapi) i32,
            FPDFBitmap_GetBuffer: *const fn (B) callconv(.winapi) ?*anyopaque,
            FPDFBitmap_GetWidth: *const fn (B) callconv(.winapi) i32,
            FPDFBitmap_GetHeight: *const fn (B) callconv(.winapi) i32,
            FPDFBitmap_GetStride: *const fn (B) callconv(.winapi) i32,
            FPDFBitmap_Destroy: *const fn (B) callconv(.winapi) void,
            FPDF_RenderPageBitmap_Start: *const fn (B, P, i32, i32, i32, i32, i32, i32, ?*pdfium.IFSDK_PAUSE) callconv(.winapi) i32,
            FPDF_RenderPage_Continue: *const fn (P, ?*pdfium.IFSDK_PAUSE) callconv(.winapi) i32,
            FPDF_RenderPage_Close: *const fn (P) callconv(.winapi) void,
            FPDFText_LoadPage: *const fn (P) callconv(.winapi) T,
            FPDFText_ClosePage: *const fn (T) callconv(.winapi) void,
            FPDFText_CountChars: *const fn (T) callconv(.winapi) i32,
            FPDFText_GetUnicode: *const fn (T, i32) callconv(.winapi) u32,
            FPDFText_GetCharBox: *const fn (T, i32, *f64, *f64, *f64, *f64) callconv(.winapi) i32,
            FPDFText_GetText: *const fn (T, i32, i32, [*]u16) callconv(.winapi) i32,
            FPDFText_FindStart: *const fn (T, [*:0]const u16, u32, i32) callconv(.winapi) S,
            FPDFText_FindNext: *const fn (S) callconv(.winapi) i32,
            FPDFText_FindPrev: *const fn (S) callconv(.winapi) i32,
            FPDFText_GetSchResultIndex: *const fn (S) callconv(.winapi) i32,
            FPDFText_GetSchCount: *const fn (S) callconv(.winapi) i32,
            FPDFText_FindClose: *const fn (S) callconv(.winapi) void,
            FPDFLink_Enumerate: *const fn (P, *i32, *L) callconv(.winapi) i32,
            FPDFLink_GetAnnotRect: *const fn (L, *pdfium.FS_RECTF) callconv(.winapi) i32,
        };
        const fields = @typeInfo(Expected).@"struct".fields;
        try std.testing.expectEqual(fields.len, @typeInfo(pdfium.Table).@"struct".fields.len);
        try std.testing.expectEqual(fields.len * 8, @sizeOf(pdfium.Table));
        try std.testing.expectEqual(@as(usize, 8), @alignOf(pdfium.Table));
        inline for (fields, 0..) |field, index| {
            try std.testing.expect(field.type == @FieldType(pdfium.Table, field.name));
            try std.testing.expectEqual(index * 8, @offsetOf(pdfium.Table, field.name));
        }
    } else return error.MissingPdfiumTable;
}
