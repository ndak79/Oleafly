//! Bounded resident LRU tile cache.
//!
//! Tiles are 1 MiB (512x512 BGRx). Cache capacity is bounded by memory:
//! - 32 MiB (32 tiles) default
//! - 48 MiB or 64 MiB configured
//! Eviction policy is strict LRU.

const std = @import("std");
const protocol = @import("protocol.zig");

pub const default_capacity_tiles: usize = 32; // 32 MiB
pub const max_capacity_tiles: usize = 64; // 64 MiB

pub const TileKey = struct {
    doc_id: u64,
    page_index: u32,
    tile_x: u16,
    tile_y: u16,
    dpi_bucket: u16,

    pub fn eql(self: TileKey, other: TileKey) bool {
        return self.doc_id == other.doc_id and
            self.page_index == other.page_index and
            self.tile_x == other.tile_x and
            self.tile_y == other.tile_y and
            self.dpi_bucket == other.dpi_bucket;
    }
};

pub const TileEntry = struct {
    key: TileKey,
    pixels: []u8,
    digest: [32]u8,
    last_access_tick: u64,
};

pub const TileCache = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(TileEntry) = .empty,
    capacity_tiles: usize,
    access_counter: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, capacity_tiles: usize) TileCache {
        const cap = @min(@max(capacity_tiles, 1), max_capacity_tiles);
        return .{
            .allocator = allocator,
            .capacity_tiles = cap,
        };
    }

    pub fn deinit(self: *TileCache) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.pixels);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn get(self: *TileCache, key: TileKey) ?[]const u8 {
        self.access_counter +%= 1;
        for (self.entries.items) |*entry| {
            if (entry.key.eql(key)) {
                entry.last_access_tick = self.access_counter;
                return entry.pixels;
            }
        }
        return null;
    }

    pub fn put(self: *TileCache, key: TileKey, pixels: []const u8, digest: [32]u8) !void {
        if (pixels.len != protocol.tile_byte_size) return error.InvalidTileSize;
        self.access_counter +%= 1;

        // If key already exists, update in-place
        for (self.entries.items) |*entry| {
            if (entry.key.eql(key)) {
                @memcpy(entry.pixels, pixels);
                entry.digest = digest;
                entry.last_access_tick = self.access_counter;
                return;
            }
        }

        // If at capacity, evict LRU entry
        if (self.entries.items.len >= self.capacity_tiles) {
            var oldest_idx: usize = 0;
            var oldest_tick: u64 = std.math.maxInt(u64);
            for (self.entries.items, 0..) |entry, i| {
                if (entry.last_access_tick < oldest_tick) {
                    oldest_tick = entry.last_access_tick;
                    oldest_idx = i;
                }
            }
            const evicted = self.entries.swapRemove(oldest_idx);
            self.allocator.free(evicted.pixels);
        }

        // Allocate and insert new tile
        const owned_pixels = try self.allocator.dupe(u8, pixels);
        errdefer self.allocator.free(owned_pixels);

        try self.entries.append(self.allocator, .{
            .key = key,
            .pixels = owned_pixels,
            .digest = digest,
            .last_access_tick = self.access_counter,
        });
    }

    pub fn count(self: *const TileCache) usize {
        return self.entries.items.len;
    }

    pub fn residentBytes(self: *const TileCache) usize {
        return self.entries.items.len * protocol.tile_byte_size;
    }
};
