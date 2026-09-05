//! Declarative Windows x64 public-C ABI for the locked PDFium root commit
//! 6f2272e1f3aaa141305475b83ef4eac2c1f527b8 (Chromium 8035).
//! Source: public/fpdfview.h, fpdf_progressive.h, fpdf_text.h, fpdf_doc.h.
//!
//! This module neither imports bindings nor declares external linked functions.
//! It owns no library/table instance and cannot initialize or execute an engine.
//! T0.2e must separately establish the authenticated isolated worker, sealed
//! reconstructed binary identity, owner thread and lifecycle before populating
//! or using this table. Linux builds only check this Windows ABI declaration;
//! this is not a Linux PDFium binding or evidence of runtime compatibility.
//!
//! Only stable APIs needed for memory documents, progressive external bitmaps,
//! text/search and inert link rectangles are admitted. The stable int-sized
//! memory loader covers the planned <=128 MiB input bound; its backing bytes
//! must outlive the document. Legacy double page-size APIs preserve the
//! stable surface; experimental float/64-bit-load and general annotation APIs
//! require separate admission. There are no form-fill, JS, XFA, file-access,
//! font-provider, availability or network callback interfaces here.

// Windows uses LLP64: int and unsigned long remain 32 bits on x64. Never use
// Zig c_ulong here: the Linux compile-only lane would silently widen it.
pub const FPDF_BOOL = i32;
pub const FPDF_DWORD = u32;
pub const FPDF_WCHAR = u16;
pub const FPDF_RENDERER_TYPE = i32;
pub const FPDF_FONT_BACKEND_TYPE = i32;

// Distinct incomplete pointee types match the public header's type safety.
// Nullable handles preserve the documented C null/failure representation.
pub const FPDF_DOCUMENT = ?*opaque {};
pub const FPDF_PAGE = ?*opaque {};
pub const FPDF_BITMAP = ?*opaque {};
pub const FPDF_TEXTPAGE = ?*opaque {};
pub const FPDF_SCHHANDLE = ?*opaque {};
pub const FPDF_LINK = ?*opaque {};

// Full pinned header layout, including its version-6 experimental tail. Having
// these fields does not admit V8 or experimental configuration: later worker
// code must choose the reviewed version and inert/null settings explicitly.
pub const FPDF_LIBRARY_CONFIG = extern struct {
    version: i32,
    m_pUserFontPaths: ?[*:null]?[*:0]const u8,
    m_pIsolate: ?*anyopaque,
    m_v8EmbedderSlot: u32,
    m_pPlatform: ?*anyopaque,
    m_RendererType: FPDF_RENDERER_TYPE,
    m_FontLibraryType: FPDF_FONT_BACKEND_TYPE,
    m_BrotliEnabled: FPDF_BOOL,
};

// The only callback is a cooperative pause query. Upstream does NOT apply
// FPDF_CALLCONV to it: preserve the C convention, not the exports' winapi alias.
// It is a scheduling hook, not an OS sandbox or a bound on parse/load time.
pub const IFSDK_PAUSE = extern struct {
    version: i32,
    NeedToPauseNow: *const fn (*IFSDK_PAUSE) callconv(.c) FPDF_BOOL,
    user: ?*anyopaque,
};

pub const FS_RECTF = extern struct {
    left: f32,
    top: f32,
    right: f32,
    bottom: f32,
};

// A complete, non-null export inventory is required before any future engine
// use; there are deliberately no default function pointers or table value.
pub const Table = extern struct {
    FPDF_InitLibraryWithConfig: *const fn (*const FPDF_LIBRARY_CONFIG) callconv(.winapi) void,
    FPDF_DestroyLibrary: *const fn () callconv(.winapi) void,
    FPDF_SetSandBoxPolicy: *const fn (FPDF_DWORD, FPDF_BOOL) callconv(.winapi) void,
    FPDF_LoadMemDocument: *const fn (?*const anyopaque, i32, ?[*:0]const u8) callconv(.winapi) FPDF_DOCUMENT,
    // Read immediately on the engine thread only after a documented failure.
    FPDF_GetLastError: *const fn () callconv(.winapi) u32,
    FPDF_CloseDocument: *const fn (FPDF_DOCUMENT) callconv(.winapi) void,
    FPDF_GetPageCount: *const fn (FPDF_DOCUMENT) callconv(.winapi) i32,
    FPDF_LoadPage: *const fn (FPDF_DOCUMENT, i32) callconv(.winapi) FPDF_PAGE,
    FPDF_ClosePage: *const fn (FPDF_PAGE) callconv(.winapi) void,
    FPDF_GetPageWidth: *const fn (FPDF_PAGE) callconv(.winapi) f64,
    FPDF_GetPageHeight: *const fn (FPDF_PAGE) callconv(.winapi) f64,
    FPDFBitmap_CreateEx: *const fn (i32, i32, i32, ?*anyopaque, i32) callconv(.winapi) FPDF_BITMAP,
    // In this pin FillRect returns FPDF_BOOL, not void.
    FPDFBitmap_FillRect: *const fn (FPDF_BITMAP, i32, i32, i32, i32, FPDF_DWORD) callconv(.winapi) FPDF_BOOL,
    FPDFBitmap_GetBuffer: *const fn (FPDF_BITMAP) callconv(.winapi) ?*anyopaque,
    FPDFBitmap_GetWidth: *const fn (FPDF_BITMAP) callconv(.winapi) i32,
    FPDFBitmap_GetHeight: *const fn (FPDF_BITMAP) callconv(.winapi) i32,
    FPDFBitmap_GetStride: *const fn (FPDF_BITMAP) callconv(.winapi) i32,
    FPDFBitmap_Destroy: *const fn (FPDF_BITMAP) callconv(.winapi) void,
    FPDF_RenderPageBitmap_Start: *const fn (FPDF_BITMAP, FPDF_PAGE, i32, i32, i32, i32, i32, i32, ?*IFSDK_PAUSE) callconv(.winapi) i32,
    FPDF_RenderPage_Continue: *const fn (FPDF_PAGE, ?*IFSDK_PAUSE) callconv(.winapi) i32,
    FPDF_RenderPage_Close: *const fn (FPDF_PAGE) callconv(.winapi) void,
    FPDFText_LoadPage: *const fn (FPDF_PAGE) callconv(.winapi) FPDF_TEXTPAGE,
    FPDFText_ClosePage: *const fn (FPDF_TEXTPAGE) callconv(.winapi) void,
    FPDFText_CountChars: *const fn (FPDF_TEXTPAGE) callconv(.winapi) i32,
    FPDFText_GetUnicode: *const fn (FPDF_TEXTPAGE, i32) callconv(.winapi) u32,
    FPDFText_GetCharBox: *const fn (FPDF_TEXTPAGE, i32, *f64, *f64, *f64, *f64) callconv(.winapi) FPDF_BOOL,
    FPDFText_GetText: *const fn (FPDF_TEXTPAGE, i32, i32, [*]u16) callconv(.winapi) i32,
    FPDFText_FindStart: *const fn (FPDF_TEXTPAGE, [*:0]const FPDF_WCHAR, u32, i32) callconv(.winapi) FPDF_SCHHANDLE,
    FPDFText_FindNext: *const fn (FPDF_SCHHANDLE) callconv(.winapi) FPDF_BOOL,
    FPDFText_FindPrev: *const fn (FPDF_SCHHANDLE) callconv(.winapi) FPDF_BOOL,
    FPDFText_GetSchResultIndex: *const fn (FPDF_SCHHANDLE) callconv(.winapi) i32,
    FPDFText_GetSchCount: *const fn (FPDF_SCHHANDLE) callconv(.winapi) i32,
    FPDFText_FindClose: *const fn (FPDF_SCHHANDLE) callconv(.winapi) void,
    FPDFLink_Enumerate: *const fn (FPDF_PAGE, *i32, *FPDF_LINK) callconv(.winapi) FPDF_BOOL,
    FPDFLink_GetAnnotRect: *const fn (FPDF_LINK, *FS_RECTF) callconv(.winapi) FPDF_BOOL,
};

// Exact case-sensitive public symbol spellings, suitable for the future
// authenticated resolver. Tests require a bijection with the table fields.
pub const required_symbols = [_][:0]const u8{
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

comptime {
    if (@sizeOf(usize) != 8) @compileError("PDFium contract is qualified for x64 only");
    if (@sizeOf(FPDF_LIBRARY_CONFIG) != 56 or @alignOf(FPDF_LIBRARY_CONFIG) != 8 or
        @offsetOf(FPDF_LIBRARY_CONFIG, "version") != 0 or
        @offsetOf(FPDF_LIBRARY_CONFIG, "m_pUserFontPaths") != 8 or
        @offsetOf(FPDF_LIBRARY_CONFIG, "m_pIsolate") != 16 or
        @offsetOf(FPDF_LIBRARY_CONFIG, "m_v8EmbedderSlot") != 24 or
        @offsetOf(FPDF_LIBRARY_CONFIG, "m_pPlatform") != 32 or
        @offsetOf(FPDF_LIBRARY_CONFIG, "m_RendererType") != 40 or
        @offsetOf(FPDF_LIBRARY_CONFIG, "m_FontLibraryType") != 44 or
        @offsetOf(FPDF_LIBRARY_CONFIG, "m_BrotliEnabled") != 48)
        @compileError("FPDF_LIBRARY_CONFIG differs from the pinned Windows x64 C ABI");
    if (@sizeOf(IFSDK_PAUSE) != 24 or @alignOf(IFSDK_PAUSE) != 8 or
        @offsetOf(IFSDK_PAUSE, "version") != 0 or
        @offsetOf(IFSDK_PAUSE, "NeedToPauseNow") != 8 or
        @offsetOf(IFSDK_PAUSE, "user") != 16)
        @compileError("IFSDK_PAUSE differs from the pinned Windows x64 C ABI");
    if (@sizeOf(FS_RECTF) != 16 or @alignOf(FS_RECTF) != 4 or
        @offsetOf(FS_RECTF, "left") != 0 or @offsetOf(FS_RECTF, "top") != 4 or
        @offsetOf(FS_RECTF, "right") != 8 or @offsetOf(FS_RECTF, "bottom") != 12)
        @compileError("FS_RECTF differs from the pinned C ABI");
    if (@sizeOf(Table) != 280 or @alignOf(Table) != 8)
        @compileError("PDFium table must contain exactly 35 Windows x64 function pointers");
}
