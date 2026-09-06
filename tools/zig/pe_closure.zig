//! Fixture-driven recursive role closure oracle.
//!
//! This is intentionally not the final shipped-image proof. It verifies the
//! shape and ownership rules that a later PE inventory producer must satisfy,
//! while reusing the offline PE parser for each supplied image. No image is
//! mapped, loaded, or executed here.
const std = @import("std");
const pe = @import("pe_audit");

pub const RoleBinary = struct {
    role: []const u8,
    path: []const u8,
    pe_bytes: []const u8,
    modules: []const []const u8 = &.{},
    imports: []const []const u8 = &.{},
    resources: []const []const u8 = &.{},
    children: []const RoleBinary = &.{},
};

pub const Manifest = struct {
    binaries: []const RoleBinary,
};

pub const RolePolicy = struct {
    name: []const u8,
    image_path: []const u8,
    pe_policy: pe.Policy,
    modules: []const []const u8 = &.{},
    imports: []const []const u8 = &.{},
    resources: []const []const u8 = &.{},
};

pub const Policy = struct {
    roles: []const RolePolicy,
    max_depth: usize = 8,
};

pub const Report = struct {
    binaries: usize = 0,
    modules: usize = 0,
    imports: usize = 0,
    resources: usize = 0,
};

pub fn auditManifest(manifest: Manifest, policy: Policy) !Report {
    if (manifest.binaries.len == 0) return error.MissingRole;
    var report = Report{};
    var seen_roles: [16][]const u8 = undefined;
    var seen_count: usize = 0;
    for (manifest.binaries) |binary| {
        try auditBinary(binary, policy, 0, &report, &seen_roles, &seen_count);
    }
    for (policy.roles) |role| {
        var found = false;
        for (seen_roles[0..seen_count]) |seen| if (std.mem.eql(u8, seen, role.name)) {
            found = true;
            break;
        };
        if (!found) return error.MissingRole;
    }
    return report;
}

fn auditBinary(
    binary: RoleBinary,
    policy: Policy,
    depth: usize,
    report: *Report,
    seen_roles: *[16][]const u8,
    seen_count: *usize,
) !void {
    if (depth > policy.max_depth) return error.ClosureTooDeep;
    if (!validRelativePath(binary.path)) return error.InvalidPath;
    const role = findRole(policy.roles, binary.role) orelse return error.UnexpectedRole;
    if (!std.mem.eql(u8, binary.path, role.image_path)) return error.UnexpectedRole;
    if (seen_count.* >= seen_roles.len) return error.TooManyBinaries;
    for (seen_roles[0..seen_count.*]) |seen| if (std.mem.eql(u8, seen, binary.role)) {
        return error.DuplicateRole;
    };
    seen_roles[seen_count.*] = binary.role;
    seen_count.* += 1;

    _ = pe.audit(binary.pe_bytes, role.pe_policy) catch return error.PeRejected;
    try verifyList(binary.modules, role.modules, .module, binary.role, report);
    try verifyList(binary.imports, role.imports, .import, binary.role, report);
    try verifyList(binary.resources, role.resources, .resource, binary.role, report);
    report.binaries += 1;
    for (binary.children) |child| {
        try auditBinary(child, policy, depth + 1, report, seen_roles, seen_count);
    }
}

const ListKind = enum { module, import, resource };

fn verifyList(
    actual: []const []const u8,
    expected: []const []const u8,
    kind: ListKind,
    role: []const u8,
    report: *Report,
) !void {
    if (actual.len != expected.len) switch (kind) {
        .module => return error.UnexpectedModulePath,
        .import => return error.UnexpectedImportPath,
        .resource => return error.UnexpectedResourcePath,
    };
    for (expected, 0..) |candidate, index| {
        for (expected[0..index]) |previous| {
            if (std.mem.eql(u8, candidate, previous)) return error.DuplicateMetadata;
        }
    }
    for (actual, 0..) |item, index| {
        for (actual[0..index]) |previous| {
            if (std.mem.eql(u8, item, previous)) return error.DuplicateMetadata;
        }
        if (!validRelativePath(item) and kind != .import) return error.InvalidPath;
        if (kind == .import and item.len == 0) return error.InvalidPath;
        if (isForbiddenCrossEdge(role, item)) return error.CrossRoleEdge;
        var found = false;
        for (expected) |candidate| {
            if (std.mem.eql(u8, item, candidate)) found = true;
        }
        if (!found) switch (kind) {
            .module => return error.UnexpectedModulePath,
            .import => return error.UnexpectedImportPath,
            .resource => return error.UnexpectedResourcePath,
        };
    }
    for (expected) |candidate| {
        var found = false;
        for (actual) |item| if (std.mem.eql(u8, item, candidate)) {
            found = true;
            break;
        };
        if (!found) switch (kind) {
            .module => return error.UnexpectedModulePath,
            .import => return error.UnexpectedImportPath,
            .resource => return error.UnexpectedResourcePath,
        };
    }
    switch (kind) {
        .module => report.modules += actual.len,
        .import => report.imports += actual.len,
        .resource => report.resources += actual.len,
    }
}

fn isForbiddenCrossEdge(role: []const u8, item: []const u8) bool {
    if (std.ascii.indexOfIgnoreCase(item, "lexilla") != null) return true;
    if (std.ascii.indexOfIgnoreCase(item, "scintilla") != null and !std.mem.eql(u8, role, "UI")) return true;
    if (std.ascii.indexOfIgnoreCase(item, "pdfium") != null and !std.mem.eql(u8, role, "PdfWorker")) return true;
    return false;
}

fn findRole(roles: []const RolePolicy, name: []const u8) ?RolePolicy {
    for (roles) |role| if (std.mem.eql(u8, role.name, name)) return role;
    return null;
}

fn validRelativePath(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or path[0] == '\\' or
        (path.len >= 2 and path[1] == ':')) return false;
    var parts = std.mem.splitAny(u8, path, "/\\");
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
        if (part[part.len - 1] == '.') return false;
        for (part) |byte| if (byte < 0x20 or byte == 0x7f or byte == '"' or byte == ':' or byte == '|' or
            byte == '*' or byte == '?' or byte == '<' or byte == '>') return false;
    }
    return true;
}
