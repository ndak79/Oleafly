//! Immutable accessible representation of a rendered PDF document.
//!
//! Pure Zig data structures for UIA accessibility tree:
//! - Document -> Pages -> Text runs / Annotations / Links
//! - Zero raw PDFium handles, engine memory, or cross-process pointers.

const std = @import("std");

pub const Rect = struct {
    left: f32,
    top: f32,
    right: f32,
    bottom: f32,
};

pub const Link = struct {
    bounds: Rect,
    target_page: u32,
    uri: []const u8 = "",
};

pub const TextRun = struct {
    bounds: Rect,
    text: []const u8,
    char_index: u32,
};

pub const AccessiblePage = struct {
    page_index: u32,
    width_pt: f32,
    height_pt: f32,
    text_runs: []TextRun = &.{},
    links: []Link = &.{},
};

pub const AccessibleDocument = struct {
    allocator: std.mem.Allocator,
    doc_id: u64,
    page_count: u32,
    pages: []AccessiblePage,

    pub fn init(allocator: std.mem.Allocator, doc_id: u64, page_count: u32) !*AccessibleDocument {
        const doc = try allocator.create(AccessibleDocument);
        errdefer allocator.destroy(doc);

        const pages = try allocator.alloc(AccessiblePage, page_count);
        errdefer allocator.free(pages);

        for (pages, 0..) |*page, i| {
            page.* = AccessiblePage{
                .page_index = @intCast(i),
                .width_pt = 612.0, // standard letter width
                .height_pt = 792.0, // standard letter height
            };
        }

        doc.* = .{
            .allocator = allocator,
            .doc_id = doc_id,
            .page_count = page_count,
            .pages = pages,
        };
        return doc;
    }

    pub fn deinit(self: *AccessibleDocument) void {
        const alloc = self.allocator;
        for (self.pages) |*page| {
            for (page.text_runs) |run| {
                alloc.free(run.text);
            }
            if (page.text_runs.len > 0) alloc.free(page.text_runs);
            if (page.links.len > 0) alloc.free(page.links);
        }
        alloc.free(self.pages);
        alloc.destroy(self);
    }

    pub fn getPage(self: *const AccessibleDocument, page_index: u32) ?*const AccessiblePage {
        if (page_index >= self.page_count) return null;
        return &self.pages[page_index];
    }
};
