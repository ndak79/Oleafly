//! Narrow product checks, not a release/security PE audit. Runtime probes own
//! and close only processes/windows they create; they never inspect other apps.
const std = @import("std");
const builtin = @import("builtin");
const contract = @import("product_contract");
const argv = @import("windows_argv");
const resources = @import("resource_assets");
const version_resource = @import("app_version_resource");
const icon = @import("texflow_icon");
const windows = std.os.windows;
const w = std.unicode.utf8ToUtf16LeStringLiteral;
const supported = builtin.os.tag == .windows and builtin.cpu.arch == .x86_64;

test "product exists only for x64 Windows and installs as TExFlow GUI" {
    try std.testing.expectEqual(supported, contract.has_product);
    if (!supported) {
        try std.testing.expect(contract.install_empty);
        return;
    }
    try std.testing.expectEqualStrings("TExFlow", contract.product_name);
    try std.testing.expectEqualStrings("TExFlow.exe", std.fs.path.basename(contract.path));
    try std.testing.expect(contract.install_reaches_product);
}

fn read(comptime T: type, bytes: []const u8, offset: usize) !T {
    if (offset > bytes.len or @sizeOf(T) > bytes.len - offset) return error.TruncatedPe;
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}

fn rvaOffset(bytes: []const u8, pe: usize, rva: u32) !usize {
    const count = try read(u16, bytes, pe + 6);
    const table = pe + 24 + try read(u16, bytes, pe + 20);
    for (0..count) |index| {
        const section = table + index * 40;
        const base = try read(u32, bytes, section + 12);
        const size = try read(u32, bytes, section + 16);
        if (rva >= base and rva - base < size) {
            const offset = @as(usize, try read(u32, bytes, section + 20)) + rva - base;
            if (offset >= bytes.len) return error.TruncatedPe;
            return offset;
        }
    }
    return error.UnmappedPeRva;
}

fn peString(bytes: []const u8, offset: usize) ![]const u8 {
    if (offset >= bytes.len) return error.TruncatedPe;
    const end = std.mem.indexOfScalar(u8, bytes[offset..], 0) orelse return error.UnterminatedPeString;
    return bytes[offset..][0..end];
}

const ResourceTarget = struct {
    relative_offset: u32,
    is_directory: bool,
};

const ResourceSpan = struct {
    root: usize,
    end: usize,
    rva: u32,
    size: u32,
};

const ResourceType = struct {
    span: ResourceSpan,
    target: ResourceTarget,
};

fn resourceSpan(bytes: []const u8, pe: usize) !ResourceSpan {
    const resource_rva = try read(u32, bytes, pe + 24 + 128);
    const resource_size = try read(u32, bytes, pe + 24 + 132);
    if (resource_rva == 0 or resource_size == 0) return error.MissingResourceDirectory;
    const root = try rvaOffset(bytes, pe, resource_rva);
    const end = std.math.add(usize, root, @as(usize, resource_size)) catch return error.InvalidResourceTree;
    if (end > bytes.len) return error.InvalidResourceTree;
    return .{ .root = root, .end = end, .rva = resource_rva, .size = resource_size };
}

fn resourceOffset(bytes: []const u8, root: usize, resource_end: usize, relative: u32) !usize {
    const offset = std.math.add(usize, root, @as(usize, relative)) catch return error.TruncatedPe;
    if (root > bytes.len or resource_end > bytes.len or offset > resource_end) return error.InvalidResourceTree;
    return offset;
}

fn resourceRead(comptime T: type, bytes: []const u8, resource_end: usize, offset: usize) !T {
    if (offset > resource_end or @sizeOf(T) > resource_end - offset) return error.InvalidResourceTree;
    return read(T, bytes, offset) catch return error.InvalidResourceTree;
}

fn resourceChild(bytes: []const u8, root: usize, resource_end: usize, directory: u32, wanted_id: u32) !ResourceTarget {
    const directory_offset = try resourceOffset(bytes, root, resource_end, directory);
    const named_count = try resourceRead(u16, bytes, resource_end, directory_offset + 12);
    const id_count = try resourceRead(u16, bytes, resource_end, directory_offset + 14);
    if (named_count != 0 or id_count != 1) return error.UnexpectedResourceCount;
    const entry = directory_offset + 16;
    const id = try resourceRead(u32, bytes, resource_end, entry);
    if ((id & 0x8000_0000) != 0) return error.UnexpectedNamedResource;
    if (id != wanted_id) return error.MissingResource;
    const target = try resourceRead(u32, bytes, resource_end, entry + 4);
    return .{
        .relative_offset = target & 0x7fff_ffff,
        .is_directory = (target & 0x8000_0000) != 0,
    };
}

fn resourceOnlyChild(bytes: []const u8, root: usize, resource_end: usize, directory: u32, wanted_id: u32) !ResourceTarget {
    const directory_offset = try resourceOffset(bytes, root, resource_end, directory);
    const named_count = try resourceRead(u16, bytes, resource_end, directory_offset + 12);
    const id_count = try resourceRead(u16, bytes, resource_end, directory_offset + 14);
    if (named_count != 0 or id_count != 1) return error.UnexpectedResourceCount;
    const entry = directory_offset + 16;
    const id = try resourceRead(u32, bytes, resource_end, entry);
    if ((id & 0x8000_0000) != 0) return error.UnexpectedNamedResource;
    if (id != wanted_id) return error.UnexpectedResourceLocale;
    const target = try resourceRead(u32, bytes, resource_end, entry + 4);
    return .{
        .relative_offset = target & 0x7fff_ffff,
        .is_directory = (target & 0x8000_0000) != 0,
    };
}

fn resourceType(bytes: []const u8, pe: usize, wanted_type: u32) !ResourceType {
    const span = try resourceSpan(bytes, pe);
    const root_named = try resourceRead(u16, bytes, span.end, span.root + 12);
    const root_ids = try resourceRead(u16, bytes, span.end, span.root + 14);
    if (root_named != 0 or root_ids != 4) return error.UnexpectedResourceCount;
    var seen_icon = false;
    var seen_group_icon = false;
    var seen_version = false;
    var seen_manifest = false;
    var wanted: ?ResourceTarget = null;
    for (0..root_ids) |index| {
        const entry = span.root + 16 + index * 8;
        const id = try resourceRead(u32, bytes, span.end, entry);
        if ((id & 0x8000_0000) != 0) return error.UnexpectedNamedResource;
        switch (id) {
            3 => {
                if (seen_icon) return error.DuplicateResource;
                seen_icon = true;
            },
            14 => {
                if (seen_group_icon) return error.DuplicateResource;
                seen_group_icon = true;
            },
            16 => {
                if (seen_version) return error.DuplicateResource;
                seen_version = true;
            },
            24 => {
                if (seen_manifest) return error.DuplicateResource;
                seen_manifest = true;
            },
            else => return error.UnexpectedResourceType,
        }
        if (id == wanted_type) {
            const target = try resourceRead(u32, bytes, span.end, entry + 4);
            wanted = .{ .relative_offset = target & 0x7fff_ffff, .is_directory = (target & 0x8000_0000) != 0 };
        }
    }
    if (!seen_icon or !seen_group_icon or !seen_version or !seen_manifest) return error.MissingResource;
    return .{ .span = span, .target = wanted orelse return error.MissingResource };
}

fn validateNamedResourceIds(wanted_type: u32, ids: []const u32) !void {
    const expected_count: usize = switch (wanted_type) {
        3 => icon.sizes.len,
        14 => 1,
        else => return error.UnexpectedResourceType,
    };
    if (ids.len != expected_count) return error.UnexpectedResourceCount;
    var seen_icons = [_]bool{false} ** icon.sizes.len;
    for (ids) |id| {
        if ((id & 0x8000_0000) != 0) return error.UnexpectedNamedResource;
        switch (wanted_type) {
            3 => {
                if (id == 0 or id > @as(u32, @intCast(icon.sizes.len))) return error.UnexpectedResourceType;
                const icon_index: usize = @intCast(id - 1);
                if (seen_icons[icon_index]) return error.DuplicateResource;
                seen_icons[icon_index] = true;
            },
            14 => if (id != 1) return error.UnexpectedResourceType,
            else => unreachable,
        }
    }
}

fn resourceData(bytes: []const u8, pe: usize, wanted_type: u32) ![]const u8 {
    const typed = try resourceType(bytes, pe, wanted_type);
    const span = typed.span;
    const resource_rva = span.rva;
    const resource_size = span.size;
    const resource_root = span.root;
    const resource_end = span.end;
    const type_target = typed.target;
    if (!type_target.is_directory) return error.InvalidResourceTree;
    const name = try resourceChild(bytes, resource_root, resource_end, type_target.relative_offset, 1);
    if (!name.is_directory) return error.InvalidResourceTree;
    const language = try resourceOnlyChild(bytes, resource_root, resource_end, name.relative_offset, version_resource.language);
    if (language.is_directory) return error.InvalidResourceTree;
    const data_entry = try resourceOffset(bytes, resource_root, resource_end, language.relative_offset);
    const data_rva = try resourceRead(u32, bytes, resource_end, data_entry);
    const data_size = try resourceRead(u32, bytes, resource_end, data_entry + 4);
    _ = try resourceRead(u32, bytes, resource_end, data_entry + 8); // code page, checked for bounds
    _ = try resourceRead(u32, bytes, resource_end, data_entry + 12); // reserved, checked for bounds
    if (data_rva < resource_rva) return error.InvalidResourceTree;
    const relative_data_rva = data_rva - resource_rva;
    if (relative_data_rva > resource_size or data_size > resource_size - relative_data_rva) return error.InvalidResourceTree;
    const data_offset = try rvaOffset(bytes, pe, data_rva);
    if (@as(usize, data_size) > bytes.len - data_offset) return error.TruncatedPe;
    return bytes[data_offset .. data_offset + @as(usize, data_size)];
}

fn resourceNamedData(bytes: []const u8, pe: usize, wanted_type: u32, wanted_name: u32) ![]const u8 {
    const typed = try resourceType(bytes, pe, wanted_type);
    const span = typed.span;
    if (!typed.target.is_directory) return error.InvalidResourceTree;
    const type_directory = try resourceOffset(bytes, span.root, span.end, typed.target.relative_offset);
    const named_count = try resourceRead(u16, bytes, span.end, type_directory + 12);
    const id_count = try resourceRead(u16, bytes, span.end, type_directory + 14);
    if (named_count != 0) return error.UnexpectedResourceCount;
    var ids = [_]u32{0} ** icon.sizes.len;
    if (id_count > ids.len) return error.UnexpectedResourceCount;
    for (0..id_count) |index| ids[index] = try resourceRead(u32, bytes, span.end, type_directory + 16 + index * 8);
    try validateNamedResourceIds(wanted_type, ids[0..id_count]);
    var selected: ?[]const u8 = null;
    for (0..id_count) |index| {
        const entry = type_directory + 16 + index * 8;
        const id = ids[index];
        const target_value = try resourceRead(u32, bytes, span.end, entry + 4);
        const target = ResourceTarget{
            .relative_offset = target_value & 0x7fff_ffff,
            .is_directory = (target_value & 0x8000_0000) != 0,
        };
        if (!target.is_directory) return error.InvalidResourceTree;
        const language = try resourceOnlyChild(bytes, span.root, span.end, target.relative_offset, version_resource.language);
        if (language.is_directory) return error.InvalidResourceTree;
        const data_entry = try resourceOffset(bytes, span.root, span.end, language.relative_offset);
        const data_rva = try resourceRead(u32, bytes, span.end, data_entry);
        const data_size = try resourceRead(u32, bytes, span.end, data_entry + 4);
        _ = try resourceRead(u32, bytes, span.end, data_entry + 8);
        _ = try resourceRead(u32, bytes, span.end, data_entry + 12);
        if (data_rva < span.rva) return error.InvalidResourceTree;
        const relative_data_rva = data_rva - span.rva;
        if (relative_data_rva > span.size or data_size > span.size - relative_data_rva) return error.InvalidResourceTree;
        const data_offset = try rvaOffset(bytes, pe, data_rva);
        if (@as(usize, data_size) > bytes.len - data_offset) return error.TruncatedPe;
        if (id == wanted_name) {
            if (selected != null) return error.DuplicateResource;
            selected = bytes[data_offset .. data_offset + @as(usize, data_size)];
        }
    }
    return selected orelse return error.MissingResource;
}

test "resource icon contracts reject extra, missing, duplicate, and named IDs" {
    const exact = [_]u32{ 1, 2, 3, 4, 5 };
    try validateNamedResourceIds(3, &exact);

    const extra = [_]u32{ 1, 2, 3, 4, 5, 6 };
    try std.testing.expectError(error.UnexpectedResourceCount, validateNamedResourceIds(3, &extra));

    const missing = [_]u32{ 1, 2, 3, 4 };
    try std.testing.expectError(error.UnexpectedResourceCount, validateNamedResourceIds(3, &missing));

    const duplicate = [_]u32{ 1, 2, 3, 4, 4 };
    try std.testing.expectError(error.DuplicateResource, validateNamedResourceIds(3, &duplicate));

    const named = [_]u32{ 1, 2, 3, 4, 0x8000_0005 };
    try std.testing.expectError(error.UnexpectedNamedResource, validateNamedResourceIds(3, &named));

    const wrong_group = [_]u32{2};
    try std.testing.expectError(error.UnexpectedResourceType, validateNamedResourceIds(14, &wrong_group));
}

fn resourceLanguageIdOffset(bytes: []const u8, pe: usize, wanted_type: u32) !usize {
    const span = try resourceSpan(bytes, pe);
    const resource_root = span.root;
    const resource_end = span.end;
    const root_named = try resourceRead(u16, bytes, resource_end, resource_root + 12);
    const root_ids = try resourceRead(u16, bytes, resource_end, resource_root + 14);
    if (root_named != 0 or root_ids != 4) return error.UnexpectedResourceCount;
    var type_target: ?ResourceTarget = null;
    for (0..root_ids) |index| {
        const entry = resource_root + 16 + index * 8;
        const id = try resourceRead(u32, bytes, resource_end, entry);
        if ((id & 0x8000_0000) != 0) return error.UnexpectedNamedResource;
        if (id == wanted_type) {
            if (type_target != null) return error.DuplicateResource;
            const target = try resourceRead(u32, bytes, resource_end, entry + 4);
            type_target = .{
                .relative_offset = target & 0x7fff_ffff,
                .is_directory = (target & 0x8000_0000) != 0,
            };
        }
    }
    const resource_type = type_target orelse return error.MissingResource;
    if (!resource_type.is_directory) return error.InvalidResourceTree;
    const type_directory = try resourceOffset(bytes, resource_root, resource_end, resource_type.relative_offset);
    if (try resourceRead(u16, bytes, resource_end, type_directory + 12) != 0 or try resourceRead(u16, bytes, resource_end, type_directory + 14) != 1) return error.UnexpectedResourceCount;
    const name_entry = type_directory + 16;
    if (try resourceRead(u32, bytes, resource_end, name_entry) != 1) return error.InvalidResourceTree;
    const name_target = try resourceRead(u32, bytes, resource_end, name_entry + 4);
    if ((name_target & 0x8000_0000) == 0) return error.InvalidResourceTree;
    const name_directory = try resourceOffset(bytes, resource_root, resource_end, name_target & 0x7fff_ffff);
    if (try resourceRead(u16, bytes, resource_end, name_directory + 12) != 0 or try resourceRead(u16, bytes, resource_end, name_directory + 14) != 1) return error.UnexpectedResourceCount;
    return name_directory + 16;
}

const VersionBlock = struct {
    end: usize,
    value_start: usize,
    value_end: usize,
    children_start: usize,
    value_length: u16,
    value_type: u16,
    key_start: usize,
    key_units: usize,
};

fn alignResource(value: usize) !usize {
    return std.math.add(usize, value, 3) catch return error.InvalidVersionResource;
}

fn validateVersionPadding(bytes: []const u8, start: usize, end: usize) !void {
    if (start > end or end - start > 3) return error.InvalidVersionResource;
    for (bytes[start..end]) |byte| {
        if (byte != 0) return error.InvalidVersionResource;
    }
}

fn parseVersionBlock(bytes: []const u8, start: usize, limit: usize) !VersionBlock {
    if (start > limit or limit - start < 6) return error.InvalidVersionResource;
    const length = try read(u16, bytes, start);
    const value_length = try read(u16, bytes, start + 2);
    const value_type = try read(u16, bytes, start + 4);
    if (length < 6 or @as(usize, length) > limit - start) return error.InvalidVersionResource;
    const end = start + @as(usize, length);
    const key_start = start + 6;
    var cursor = key_start;
    var key_units: usize = 0;
    while (cursor + 2 <= end) : ({
        cursor += 2;
        key_units += 1;
    }) {
        if (try read(u16, bytes, cursor) == 0) break;
    }
    if (cursor + 2 > end or try read(u16, bytes, cursor) != 0) return error.InvalidVersionResource;
    const value_start_unaligned = cursor + 2;
    const value_start = (try alignResource(value_start_unaligned)) & ~@as(usize, 3);
    if (value_start > end) return error.InvalidVersionResource;
    try validateVersionPadding(bytes, value_start_unaligned, value_start);
    const value_bytes = if (value_type == 1) std.math.mul(usize, @as(usize, value_length), 2) catch return error.InvalidVersionResource else @as(usize, value_length);
    if (value_bytes > end - value_start) return error.InvalidVersionResource;
    const value_end = value_start + value_bytes;
    const children_start = if (value_end == end) end else (try alignResource(value_end)) & ~@as(usize, 3);
    if (children_start > end) return error.InvalidVersionResource;
    try validateVersionPadding(bytes, value_end, children_start);
    return .{
        .end = end,
        .value_start = value_start,
        .value_end = value_end,
        .children_start = children_start,
        .value_length = value_length,
        .value_type = value_type,
        .key_start = key_start,
        .key_units = key_units,
    };
}

fn nextVersionChildOffset(bytes: []const u8, parent_end: usize, child_end: usize) !usize {
    if (child_end > parent_end) return error.InvalidVersionResource;
    if (child_end == parent_end) return parent_end;
    const aligned = (try alignResource(child_end)) & ~@as(usize, 3);
    const padding_end = @min(aligned, parent_end);
    try validateVersionPadding(bytes, child_end, padding_end);
    if (aligned > parent_end) return parent_end;
    return aligned;
}

fn utf16AsciiEqual(bytes: []const u8, start: usize, units: usize, expected: []const u8) bool {
    if (units != expected.len or start > bytes.len or units > (bytes.len - start) / 2) return false;
    for (expected, 0..) |character, index| {
        const code_unit = std.mem.readInt(u16, bytes[start + index * 2 ..][0..2], .little);
        if (code_unit != character) return false;
    }
    return true;
}

fn utf16ValueEqual(bytes: []const u8, start: usize, units: usize, expected: []const u8) bool {
    if (units != expected.len + 1 or start > bytes.len or units > (bytes.len - start) / 2) return false;
    if (!utf16AsciiEqual(bytes, start, expected.len, expected)) return false;
    return std.mem.readInt(u16, bytes[start + expected.len * 2 ..][0..2], .little) == 0;
}

fn requireVersionLeaf(block: VersionBlock) !void {
    if (block.children_start != block.end) return error.InvalidVersionResource;
}

fn expectVersionLeafRejected(block: VersionBlock) !void {
    requireVersionLeaf(block) catch return;
    return error.MutationAccepted;
}

fn findUtf16Ascii(bytes: []const u8, expected: []const u8) !usize {
    if (expected.len > bytes.len / 2) return error.MissingVersionString;
    const last = bytes.len - expected.len * 2;
    for (0..last + 1) |offset| {
        if (utf16AsciiEqual(bytes, offset, expected.len, expected)) return offset;
    }
    return error.MissingVersionString;
}

const ParsedVersionStrings = struct {
    product_name: bool = false,
    file_description: bool = false,
    internal_name: bool = false,
    original_filename: bool = false,
    file_version: bool = false,
    product_version: bool = false,
    private_build: bool = false,
};

fn parseVersionStringTable(bytes: []const u8, table: VersionBlock, strings: *ParsedVersionStrings) !void {
    if (!utf16AsciiEqual(bytes, table.key_start, table.key_units, "040904B0") or table.value_length != 0 or table.value_type != 1) return error.InvalidVersionResource;
    var child_offset = table.children_start;
    var child_count: usize = 0;
    while (child_offset < table.end) {
        if (table.end - child_offset < 6 or try read(u16, bytes, child_offset) == 0) {
            try validateVersionPadding(bytes, child_offset, table.end);
            break;
        }
        const child = try parseVersionBlock(bytes, child_offset, table.end);
        if (child.end <= child_offset or child.value_type != 1 or child.value_length == 0) return error.InvalidVersionResource;
        try requireVersionLeaf(child);
        const value_start = child.value_start;
        const value_units = @as(usize, child.value_length);
        if (utf16AsciiEqual(bytes, child.key_start, child.key_units, "ProductName")) {
            if (strings.product_name or !utf16ValueEqual(bytes, value_start, value_units, version_resource.product_name)) return error.InvalidVersionResource;
            strings.product_name = true;
        } else if (utf16AsciiEqual(bytes, child.key_start, child.key_units, "FileDescription")) {
            if (strings.file_description or !utf16ValueEqual(bytes, value_start, value_units, version_resource.file_description)) return error.InvalidVersionResource;
            strings.file_description = true;
        } else if (utf16AsciiEqual(bytes, child.key_start, child.key_units, "InternalName")) {
            if (strings.internal_name or !utf16ValueEqual(bytes, value_start, value_units, version_resource.internal_name)) return error.InvalidVersionResource;
            strings.internal_name = true;
        } else if (utf16AsciiEqual(bytes, child.key_start, child.key_units, "OriginalFilename")) {
            if (strings.original_filename or !utf16ValueEqual(bytes, value_start, value_units, version_resource.original_filename)) return error.InvalidVersionResource;
            strings.original_filename = true;
        } else if (utf16AsciiEqual(bytes, child.key_start, child.key_units, "FileVersion")) {
            if (strings.file_version or !utf16ValueEqual(bytes, value_start, value_units, version_resource.file_version)) return error.InvalidVersionResource;
            strings.file_version = true;
        } else if (utf16AsciiEqual(bytes, child.key_start, child.key_units, "ProductVersion")) {
            if (strings.product_version or !utf16ValueEqual(bytes, value_start, value_units, version_resource.product_version)) return error.InvalidVersionResource;
            strings.product_version = true;
        } else if (utf16AsciiEqual(bytes, child.key_start, child.key_units, "PrivateBuild")) {
            if (strings.private_build or !utf16ValueEqual(bytes, value_start, value_units, version_resource.private_build)) return error.InvalidVersionResource;
            strings.private_build = true;
        } else return error.UnexpectedVersionString;
        child_count += 1;
        child_offset = try nextVersionChildOffset(bytes, table.end, child.end);
    }
    if (child_count != 7 or !strings.product_name or !strings.file_description or !strings.internal_name or !strings.original_filename or !strings.file_version or !strings.product_version or !strings.private_build) return error.InvalidVersionResource;
}

fn parseVersionVarTable(bytes: []const u8, table: VersionBlock) !void {
    if (!utf16AsciiEqual(bytes, table.key_start, table.key_units, "Translation") or table.value_type != 0 or table.value_length != 4) return error.InvalidVersionResource;
    try requireVersionLeaf(table);
    if (try read(u16, bytes, table.value_start) != version_resource.language or try read(u16, bytes, table.value_start + 2) != version_resource.code_page) return error.InvalidVersionResource;
}

fn parseVersionResource(bytes: []const u8) !void {
    const root = try parseVersionBlock(bytes, 0, bytes.len);
    if (root.end != bytes.len) return error.InvalidVersionResource;
    if (!utf16AsciiEqual(bytes, root.key_start, root.key_units, "VS_VERSION_INFO") or root.value_type != 0 or root.value_length != 52 or root.value_end - root.value_start != 52) return error.InvalidVersionResource;
    if (try read(u32, bytes, root.value_start) != 0xfeef_04bd or try read(u32, bytes, root.value_start + 4) != 0x0001_0000) return error.InvalidVersionResource;
    const expected_file_ms = (@as(u32, version_resource.version.major) << 16) | version_resource.version.minor;
    const expected_file_ls = (@as(u32, version_resource.version.patch) << 16) | version_resource.version.revision;
    if (try read(u32, bytes, root.value_start + 8) != expected_file_ms or try read(u32, bytes, root.value_start + 12) != expected_file_ls or try read(u32, bytes, root.value_start + 16) != expected_file_ms or try read(u32, bytes, root.value_start + 20) != expected_file_ls) return error.InvalidVersionResource;
    if (try read(u32, bytes, root.value_start + 24) != version_resource.file_flags_mask or try read(u32, bytes, root.value_start + 28) != version_resource.file_flags or try read(u32, bytes, root.value_start + 32) != version_resource.file_os or try read(u32, bytes, root.value_start + 36) != version_resource.file_type or try read(u32, bytes, root.value_start + 40) != version_resource.file_subtype) return error.InvalidVersionResource;
    var strings: ParsedVersionStrings = .{};
    var string_info_count: usize = 0;
    var var_info_count: usize = 0;
    var child_offset = root.children_start;
    while (child_offset < root.end) {
        if (root.end - child_offset < 6 or try read(u16, bytes, child_offset) == 0) {
            try validateVersionPadding(bytes, child_offset, root.end);
            break;
        }
        const child = try parseVersionBlock(bytes, child_offset, root.end);
        if (child.end <= child_offset) return error.InvalidVersionResource;
        if (utf16AsciiEqual(bytes, child.key_start, child.key_units, "StringFileInfo")) {
            if (string_info_count != 0 or child.value_length != 0 or child.value_type != 1) return error.InvalidVersionResource;
            var table_count: usize = 0;
            var table_offset = child.children_start;
            while (table_offset < child.end) {
                if (child.end - table_offset < 6 or try read(u16, bytes, table_offset) == 0) {
                    try validateVersionPadding(bytes, table_offset, child.end);
                    break;
                }
                const table = try parseVersionBlock(bytes, table_offset, child.end);
                try parseVersionStringTable(bytes, table, &strings);
                table_count += 1;
                table_offset = try nextVersionChildOffset(bytes, child.end, table.end);
            }
            if (table_count != 1) return error.InvalidVersionResource;
            string_info_count = 1;
        } else if (utf16AsciiEqual(bytes, child.key_start, child.key_units, "VarFileInfo")) {
            if (var_info_count != 0 or child.value_length != 0 or child.value_type != 1) return error.InvalidVersionResource;
            var table_count: usize = 0;
            var table_offset = child.children_start;
            while (table_offset < child.end) {
                if (child.end - table_offset < 6 or try read(u16, bytes, table_offset) == 0) {
                    try validateVersionPadding(bytes, table_offset, child.end);
                    break;
                }
                const table = try parseVersionBlock(bytes, table_offset, child.end);
                try parseVersionVarTable(bytes, table);
                table_count += 1;
                table_offset = try nextVersionChildOffset(bytes, child.end, table.end);
            }
            if (table_count != 1) return error.InvalidVersionResource;
            var_info_count = 1;
        } else return error.UnexpectedVersionBlock;
        child_offset = try nextVersionChildOffset(bytes, root.end, child.end);
    }
    if (string_info_count != 1 or var_info_count != 1) return error.InvalidVersionResource;
}

fn expectVersionMutationRejected(bytes: []u8) !void {
    parseVersionResource(bytes) catch return;
    return error.MutationAccepted;
}

test "actual product PE is AMD64 GUI with narrow Unicode shell imports" {
    if (!supported) return error.SkipZigTest;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, contract.path, std.testing.allocator, .limited(32 * 1024 * 1024));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("MZ", bytes[0..2]);
    const pe = try read(u32, bytes, 0x3c);
    try std.testing.expectEqual(@as(u32, 0x4550), try read(u32, bytes, pe));
    try std.testing.expectEqual(@as(u16, 0x8664), try read(u16, bytes, pe + 4));
    try std.testing.expectEqual(@as(u16, 0x20b), try read(u16, bytes, pe + 24));
    try std.testing.expectEqual(@as(u16, 2), try read(u16, bytes, pe + 24 + 68));
    try std.testing.expect((try read(u32, bytes, pe + 24 + 16)) != 0);
    const required = [_][]const u8{
        "GetCommandLineW",  "CommandLineToArgvW", "SetDefaultDllDirectories", "SetProcessDpiAwarenessContext", "GetThreadDpiAwarenessContext", "AreDpiAwarenessContextsEqual",
        "CoInitializeEx",   "CoUninitialize",     "RegisterClassExW",         "CreateWindowExW",               "SetWindowTextW",               "ShowWindow",                   "GetMessageW",
        "TranslateMessage", "DispatchMessageW",   "DestroyWindow",            "UnregisterClassW",              "BCryptGenRandom",              "D3D11CreateDevice",
    };
    var found = [_]bool{false} ** required.len;
    var descriptor = try rvaOffset(bytes, pe, try read(u32, bytes, pe + 24 + 120));
    var imported_dlls: usize = 0;
    while (try read(u32, bytes, descriptor + 12) != 0) : (descriptor += 20) {
        imported_dlls += 1;
        if (imported_dlls > 16) return error.ExcessiveImports;
        const dll = try peString(bytes, try rvaOffset(bytes, pe, try read(u32, bytes, descriptor + 12)));
        var allowed = false;
        for ([_][]const u8{ "kernel32.dll", "ntdll.dll", "user32.dll", "shell32.dll", "ole32.dll", "bcrypt.dll", "d3d11.dll", "dxgi.dll" }) |name| {
            allowed = allowed or std.ascii.eqlIgnoreCase(dll, name);
        }
        try std.testing.expect(allowed);
        const original = try read(u32, bytes, descriptor);
        var thunk = try rvaOffset(bytes, pe, if (original != 0) original else try read(u32, bytes, descriptor + 16));
        while (try read(u64, bytes, thunk) != 0) : (thunk += 8) {
            const name_rva = try read(u64, bytes, thunk);
            try std.testing.expect(name_rva <= std.math.maxInt(u32));
            const name = try peString(bytes, (try rvaOffset(bytes, pe, @intCast(name_rva))) + 2);
            for (required, 0..) |expected, index| found[index] = found[index] or std.mem.eql(u8, name, expected);
            for ([_][]const u8{ "PeekMessageW", "PeekMessageA", "GetMessageA", "CreateWindowExA", "Sleep" }) |forbidden| {
                try std.testing.expect(!std.mem.eql(u8, name, forbidden));
            }
        }
    }
    for (found) |present| try std.testing.expect(present);
}

test "actual product PE round-trips the manifest and exact VERSIONINFO contract" {
    if (!supported) return error.SkipZigTest;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, contract.path, std.testing.allocator, .limited(32 * 1024 * 1024));
    defer std.testing.allocator.free(bytes);
    const pe = try read(u32, bytes, 0x3c);
    const manifest = try resourceData(bytes, pe, 24);
    try std.testing.expectEqualSlices(u8, resources.manifest_source, manifest);
    try parseVersionResource(try resourceData(bytes, pe, 16));
}

fn expectCanonicalIconImage(expected: []const u8, actual: []const u8) !void {
    if (!std.mem.eql(u8, expected, actual)) return error.NonCanonicalIcon;
}

test "actual product PE embeds the canonical multi-resolution TExFlow mark" {
    if (!supported) return error.SkipZigTest;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, contract.path, std.testing.allocator, .limited(32 * 1024 * 1024));
    defer std.testing.allocator.free(bytes);
    const pe = try read(u32, bytes, 0x3c);
    const canonical_ico = try icon.renderIco(std.testing.allocator);
    defer std.testing.allocator.free(canonical_ico);
    try icon.validateIco(canonical_ico);
    const group = try resourceNamedData(bytes, pe, 14, 1);
    try std.testing.expectEqual(6 + icon.sizes.len * 14, group.len);
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, group[0..2], .little));
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, group[2..4], .little));
    try std.testing.expectEqual(@as(u16, icon.sizes.len), std.mem.readInt(u16, group[4..6], .little));
    for (icon.sizes, 0..) |size, index| {
        const entry = group[6 + index * 14 ..][0..14];
        const width: u16 = if (entry[0] == 0) 256 else entry[0];
        const height: u16 = if (entry[1] == 0) 256 else entry[1];
        try std.testing.expectEqual(size, width);
        try std.testing.expectEqual(size, height);
        try std.testing.expectEqual(@as(u8, 0), entry[2]);
        try std.testing.expectEqual(@as(u8, 0), entry[3]);
        try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, entry[4..6], .little));
        try std.testing.expectEqual(@as(u16, 32), std.mem.readInt(u16, entry[6..8], .little));
        const bytes_in_res = std.mem.readInt(u32, entry[8..12], .little);
        const icon_id = std.mem.readInt(u16, entry[12..14], .little);
        try std.testing.expectEqual(@as(u16, @intCast(index + 1)), icon_id);
        const image = try resourceNamedData(bytes, pe, 3, icon_id);
        try std.testing.expectEqual(bytes_in_res, @as(u32, @intCast(image.len)));
        const canonical_entry = canonical_ico[6 + index * 16 ..][0..16];
        const canonical_bytes_in_res = std.mem.readInt(u32, canonical_entry[8..12], .little);
        const canonical_offset = std.mem.readInt(u32, canonical_entry[12..16], .little);
        const canonical_image = canonical_ico[canonical_offset..][0..canonical_bytes_in_res];
        try expectCanonicalIconImage(canonical_image, image);
        try std.testing.expectEqual(@as(u32, 40), std.mem.readInt(u32, image[0..4], .little));
        try std.testing.expectEqual(@as(i32, size), std.mem.readInt(i32, image[4..8], .little));
        try std.testing.expectEqual(@as(i32, @as(i32, size) * 2), std.mem.readInt(i32, image[8..12], .little));
        try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, image[12..14], .little));
        try std.testing.expectEqual(@as(u16, 32), std.mem.readInt(u16, image[14..16], .little));
        try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, image[16..20], .little));
    }
}

test "canonical icon oracle rejects a pixel mutation with an unchanged header" {
    if (!supported) return error.SkipZigTest;
    const canonical_ico = try icon.renderIco(std.testing.allocator);
    defer std.testing.allocator.free(canonical_ico);
    const first_entry = canonical_ico[6..][0..16];
    const first_bytes_in_res = std.mem.readInt(u32, first_entry[8..12], .little);
    const first_offset = std.mem.readInt(u32, first_entry[12..16], .little);
    const expected = canonical_ico[first_offset..][0..first_bytes_in_res];
    var mutant = try std.testing.allocator.dupe(u8, expected);
    defer std.testing.allocator.free(mutant);
    mutant[40 + 3] ^= 1;
    try std.testing.expectError(error.NonCanonicalIcon, expectCanonicalIconImage(expected, mutant));
}

test "VERSIONINFO parse-back rejects flag locale string and length mutations" {
    if (!supported) return error.SkipZigTest;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, contract.path, std.testing.allocator, .limited(32 * 1024 * 1024));
    defer std.testing.allocator.free(bytes);
    const pe = try read(u32, bytes, 0x3c);
    const source = try resourceData(bytes, pe, 16);
    const root = try parseVersionBlock(source, 0, source.len);

    var flags_mutant = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(flags_mutant);
    std.mem.writeInt(u32, flags_mutant[root.value_start + 28 ..][0..4], 0, .little);
    try expectVersionMutationRejected(flags_mutant);

    var locale_mutant = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(locale_mutant);
    const locale_offset = try findUtf16Ascii(locale_mutant, "040904B0");
    std.mem.writeInt(u16, locale_mutant[locale_offset..][0..2], '1', .little);
    try expectVersionMutationRejected(locale_mutant);

    var string_mutant = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(string_mutant);
    const string_offset = try findUtf16Ascii(string_mutant, version_resource.product_name);
    std.mem.writeInt(u16, string_mutant[string_offset..][0..2], 'X', .little);
    try expectVersionMutationRejected(string_mutant);

    var length_mutant = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(length_mutant);
    std.mem.writeInt(u16, length_mutant[0..2], @intCast(root.end - 1), .little);
    try expectVersionMutationRejected(length_mutant);

    const product_key_offset = try findUtf16Ascii(source, "ProductName");
    if (product_key_offset < 6) return error.InvalidVersionResource;
    const product_block_start = product_key_offset - 6;
    const product_length = try read(u16, source, product_block_start);
    var leaf_mutant = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(leaf_mutant);
    std.mem.writeInt(u16, leaf_mutant[product_block_start..][0..2], @intCast(product_length + 4), .little);
    try expectVersionLeafRejected(try parseVersionBlock(leaf_mutant, product_block_start, leaf_mutant.len));

    const translation_key_offset = try findUtf16Ascii(source, "Translation");
    if (translation_key_offset < 6) return error.InvalidVersionResource;
    const translation_block_start = translation_key_offset - 6;
    const translation_length = try read(u16, source, translation_block_start);
    var translation_leaf_mutant = try std.testing.allocator.alloc(u8, source.len + 4);
    defer std.testing.allocator.free(translation_leaf_mutant);
    @memcpy(translation_leaf_mutant[0..source.len], source);
    @memset(translation_leaf_mutant[source.len..], 0);
    std.mem.writeInt(u16, translation_leaf_mutant[translation_block_start..][0..2], @intCast(translation_length + 4), .little);
    try expectVersionLeafRejected(try parseVersionBlock(translation_leaf_mutant, translation_block_start, translation_leaf_mutant.len));

    const string_key_offset = try findUtf16Ascii(source, "StringFileInfo");
    if (string_key_offset < 6) return error.InvalidVersionResource;
    const string_block = try parseVersionBlock(source, string_key_offset - 6, source.len);
    const var_key_offset = try findUtf16Ascii(source, "VarFileInfo");
    if (var_key_offset < 6) return error.InvalidVersionResource;
    const var_block_start = var_key_offset - 6;
    try std.testing.expect(var_block_start > string_block.end);
    var padding_mutant = try std.testing.allocator.dupe(u8, source);
    defer std.testing.allocator.free(padding_mutant);
    padding_mutant[string_block.end] = 1;
    try expectVersionMutationRejected(padding_mutant);
}

test "resource tree rejects a non-US language resource" {
    if (!supported) return error.SkipZigTest;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, contract.path, std.testing.allocator, .limited(32 * 1024 * 1024));
    defer std.testing.allocator.free(bytes);
    const pe = try read(u32, bytes, 0x3c);
    const language_id_offset = try resourceLanguageIdOffset(bytes, pe, 16);
    var mutant = try std.testing.allocator.dupe(u8, bytes);
    defer std.testing.allocator.free(mutant);
    std.mem.writeInt(u32, mutant[language_id_offset..][0..4], 0x0407, .little);
    const mutated_pe = try read(u32, mutant, 0x3c);
    _ = resourceData(mutant, mutated_pe, 16) catch return;
    return error.MutationAccepted;
}

test "resource parser rejects metadata outside the declared resource span" {
    if (!supported) return error.SkipZigTest;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, contract.path, std.testing.allocator, .limited(32 * 1024 * 1024));
    defer std.testing.allocator.free(bytes);
    const pe = try read(u32, bytes, 0x3c);
    const span = try resourceSpan(bytes, pe);
    const language_entry = try resourceLanguageIdOffset(bytes, pe, 16);
    const original_data_entry_relative = try read(u32, bytes, language_entry + 4);
    const original_data_entry = try resourceOffset(bytes, span.root, span.end, original_data_entry_relative);
    const original_data_rva = try read(u32, bytes, original_data_entry);
    const original_data_size = try read(u32, bytes, original_data_entry + 4);
    var type_entry: ?usize = null;
    const root_ids = try resourceRead(u16, bytes, span.end, span.root + 14);
    for (0..root_ids) |index| {
        const entry = span.root + 16 + index * 8;
        if (try resourceRead(u32, bytes, span.end, entry) == 16) type_entry = entry;
    }
    const type_entry_offset = type_entry orelse return error.MissingResource;
    var mutant = try std.testing.allocator.dupe(u8, bytes);
    defer std.testing.allocator.free(mutant);
    const synthetic_base = span.end + 0x20;
    const synthetic_end = synthetic_base + 0x70;
    try std.testing.expect(synthetic_base > span.end);
    try std.testing.expect(synthetic_end <= mutant.len);
    @memset(mutant[synthetic_base..synthetic_end], 0);
    const synthetic_relative: u32 = @intCast(synthetic_base - span.root);
    std.mem.writeInt(u32, mutant[type_entry_offset + 4 ..][0..4], 0x8000_0000 | synthetic_relative, .little);

    const synthetic_type_entry = synthetic_base + 16;
    std.mem.writeInt(u16, mutant[synthetic_base + 12 ..][0..2], 0, .little);
    std.mem.writeInt(u16, mutant[synthetic_base + 14 ..][0..2], 1, .little);
    std.mem.writeInt(u32, mutant[synthetic_type_entry..][0..4], 1, .little);
    std.mem.writeInt(u32, mutant[synthetic_type_entry + 4 ..][0..4], 0x8000_0000 | (synthetic_relative + 0x40), .little);

    const synthetic_name = synthetic_base + 0x40;
    const synthetic_name_entry = synthetic_name + 16;
    std.mem.writeInt(u16, mutant[synthetic_name + 12 ..][0..2], 0, .little);
    std.mem.writeInt(u16, mutant[synthetic_name + 14 ..][0..2], 1, .little);
    std.mem.writeInt(u32, mutant[synthetic_name_entry..][0..4], version_resource.language, .little);
    std.mem.writeInt(u32, mutant[synthetic_name_entry + 4 ..][0..4], synthetic_relative + 0x60, .little);

    const synthetic_data = synthetic_base + 0x60;
    std.mem.writeInt(u32, mutant[synthetic_data..][0..4], original_data_rva, .little);
    std.mem.writeInt(u32, mutant[synthetic_data + 4 ..][0..4], original_data_size, .little);
    std.mem.writeInt(u32, mutant[synthetic_data + 8 ..][0..4], 1200, .little);
    std.mem.writeInt(u32, mutant[synthetic_data + 12 ..][0..4], 0, .little);
    const mutated_pe = try read(u32, mutant, 0x3c);
    _ = resourceData(mutant, mutated_pe, 16) catch return;
    return error.MutationAccepted;
}

const raw = struct {
    extern "kernel32" fn WaitForSingleObject(windows.HANDLE, u32) callconv(.winapi) u32;
    extern "kernel32" fn GetExitCodeProcess(windows.HANDLE, *u32) callconv(.winapi) i32;
    extern "kernel32" fn TerminateProcess(windows.HANDLE, u32) callconv(.winapi) i32;
    extern "user32" fn EnumWindows(*const fn (*anyopaque, isize) callconv(.winapi) i32, isize) callconv(.winapi) i32;
    extern "user32" fn GetWindowThreadProcessId(*anyopaque, *u32) callconv(.winapi) u32;
    extern "user32" fn GetClassNameW(*anyopaque, [*]u16, i32) callconv(.winapi) i32;
    extern "user32" fn GetWindowTextW(*anyopaque, [*]u16, i32) callconv(.winapi) i32;
    extern "user32" fn GetWindowLongPtrW(*anyopaque, i32) callconv(.winapi) isize;
    extern "user32" fn GetWindowDpiAwarenessContext(*anyopaque) callconv(.winapi) ?*anyopaque;
    extern "user32" fn AreDpiAwarenessContextsEqual(?*anyopaque, ?*anyopaque) callconv(.winapi) i32;
    extern "user32" fn IsWindowVisible(*anyopaque) callconv(.winapi) i32;
    extern "user32" fn PostMessageW(*anyopaque, u32, usize, isize) callconv(.winapi) i32;
};

const Child = struct {
    process: windows.PROCESS.INFORMATION,

    fn deinit(self: *Child) void {
        if (raw.WaitForSingleObject(self.process.hProcess, 0) != 0) {
            _ = raw.TerminateProcess(self.process.hProcess, 99);
            _ = raw.WaitForSingleObject(self.process.hProcess, 5_000);
        }
        windows.CloseHandle(self.process.hThread);
        windows.CloseHandle(self.process.hProcess);
    }
    fn exitCode(self: *Child) !u32 {
        if (raw.WaitForSingleObject(self.process.hProcess, 5_000) != 0) return error.ChildTimeout;
        var code: u32 = undefined;
        if (raw.GetExitCodeProcess(self.process.hProcess, &code) == 0) return error.ChildExitUnavailable;
        return code;
    }
};

fn launch(arguments: []const []const u8) !Child {
    const path = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, contract.path, std.testing.allocator);
    defer std.testing.allocator.free(path);
    var prepared = try argv.prepare(std.testing.allocator, .{
        .application_path = path,
        .arguments = arguments,
        .current_directory = std.fs.path.dirname(path).?,
        .environment = &.{},
    });
    defer prepared.deinit(std.testing.allocator);
    var startup: windows.STARTUPINFOW = std.mem.zeroes(windows.STARTUPINFOW);
    startup.cb = @sizeOf(windows.STARTUPINFOW);
    startup.dwFlags = 1; // STARTF_USESHOWWINDOW
    startup.wShowWindow = 5; // SW_SHOW, explicitly exercising a visible HWND.
    var child: Child = undefined;
    if (!windows.kernel32.CreateProcessW(prepared.application_name.ptr, prepared.command_line.ptr, null, null, .FALSE, .{ .create_unicode_environment = true, .create_no_window = true }, prepared.environment.ptr, prepared.current_directory.ptr, &startup, &child.process).toBool()) return error.ChildCreationFailed;
    return child;
}

const Search = struct {
    pid: u32,
    window: ?*anyopaque = null,

    fn callback(hwnd: *anyopaque, context: isize) callconv(.winapi) i32 {
        const self: *Search = @ptrFromInt(@as(usize, @bitCast(context)));
        var pid: u32 = 0;
        _ = raw.GetWindowThreadProcessId(hwnd, &pid);
        if (pid == self.pid and raw.IsWindowVisible(hwnd) != 0) self.window = hwnd;
        return 1;
    }
};

test "real GUI process shows exact title class standard caption PMv2 and closes" {
    if (!supported) return error.SkipZigTest;
    for ([_][]const []const u8{ &.{"--trace-trial=00112233445566778899aabbccddeeff"}, &.{} }) |arguments| {
        var child = try launch(arguments);
        defer child.deinit();
        var search: Search = .{ .pid = child.process.dwProcessId };
        for (0..250) |_| {
            _ = raw.EnumWindows(Search.callback, @bitCast(@intFromPtr(&search)));
            if (search.window != null) break;
            if (raw.WaitForSingleObject(child.process.hProcess, 20) == 0) break;
        }
        const hwnd = search.window orelse return error.NoProductWindow;
        var text: [128]u16 = undefined;
        const title_len = raw.GetWindowTextW(hwnd, &text, text.len);
        try std.testing.expect(title_len > 0);
        try std.testing.expectEqualSlices(u16, w("TExFlow"), text[0..@intCast(title_len)]);
        const class_len = raw.GetClassNameW(hwnd, &text, text.len);
        try std.testing.expect(class_len > 0);
        try std.testing.expectEqualSlices(u16, w("texflow.main.v1"), text[0..@intCast(class_len)]);
        const style = raw.GetWindowLongPtrW(hwnd, -16) & 0xcf0000;
        try std.testing.expectEqual(@as(isize, 0xcf0000), style);
        const pmv2: *anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -4))));
        const dpi_equal = raw.AreDpiAwarenessContextsEqual(raw.GetWindowDpiAwarenessContext(hwnd), pmv2);
        try std.testing.expect(dpi_equal != 0);
        try std.testing.expect(raw.PostMessageW(hwnd, 0x10, 0, 0) != 0); // WM_CLOSE
        try std.testing.expectEqual(@as(u32, 0), try child.exitCode());
    }
}

test "real product rejects worker probe bootstrap malformed and unknown arguments" {
    if (!supported) return error.SkipZigTest;
    for ([_][]const u8{ "--worker", "--probe", "--internal", "--bootstrap-handle=7", "--worker-bootstrap-handle=7", "--trace-trial=ABC", "--unknown", "--\u{1f642}" }) |argument| {
        var child = try launch(&.{argument});
        defer child.deinit();
        try std.testing.expectEqual(@as(u32, 2), try child.exitCode());
    }
}
