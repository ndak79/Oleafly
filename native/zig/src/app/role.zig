const std = @import("std");

/// The process role is part of the authenticated protocol state.  It is
/// intentionally separate from the common build identity: a build identity
/// never grants permission to impersonate another role.
pub const Role = enum {
    ui,
    pdf_worker,
    science_worker,
};

// Readable aliases make call sites that describe the wire contract concise
// without changing the canonical lower-case enum tags.
pub const UI = Role.ui;
pub const PdfWorker = Role.pdf_worker;
pub const ScienceWorker = Role.science_worker;

pub const Identity = struct {
    role: Role,
    product_name: []const u8,
    file_description: []const u8,
    internal_name: []const u8,
    original_filename: []const u8,
    machine_class: []const u8,
};

pub const ui_identity = Identity{
    .role = .ui,
    .product_name = "TExFlow",
    .file_description = "TExFlow",
    .internal_name = "TExFlow",
    .original_filename = "TExFlow.exe",
    .machine_class = "texflow.main.v1",
};

pub const pdf_worker_identity = Identity{
    .role = .pdf_worker,
    .product_name = "TExFlow",
    .file_description = "TExFlow PDF Worker",
    .internal_name = "TExFlow.PdfWorker",
    .original_filename = "TExFlow.PdfWorker.exe",
    .machine_class = "texflow.pdfworker.v1",
};

pub const science_worker_identity = Identity{
    .role = .science_worker,
    .product_name = "TExFlow",
    .file_description = "TExFlow Science Worker",
    .internal_name = "TExFlow.ScienceWorker",
    .original_filename = "TExFlow.ScienceWorker.exe",
    .machine_class = "texflow.scienceworker.v1",
};

pub fn identity(role: Role) Identity {
    return switch (role) {
        .ui => ui_identity,
        .pdf_worker => pdf_worker_identity,
        .science_worker => science_worker_identity,
    };
}

pub fn executable_name(role: Role) []const u8 {
    return identity(role).original_filename;
}

pub fn internal_name(role: Role) []const u8 {
    return identity(role).internal_name;
}

pub fn role_name(role: Role) []const u8 {
    return switch (role) {
        .ui => "UI",
        .pdf_worker => "PdfWorker",
        .science_worker => "ScienceWorker",
    };
}

pub const Probe = struct {
    role: Role,
    /// The exact versioned probe string is retained as a borrowed slice.  A
    /// caller can pass it through an authenticated bootstrap without any
    /// allocation or normalization.
    nonce: []const u8,
};

pub fn parseProbe(value: []const u8) !Role {
    if (std.mem.eql(u8, value, "texflow.role.v1:PdfWorker")) return .pdf_worker;
    if (std.mem.eql(u8, value, "texflow.role.v1:ScienceWorker")) return .science_worker;
    if (std.mem.eql(u8, value, "texflow.role.v1:UI")) return error.ProbeNotAllowedForUi;
    return error.MalformedProbe;
}

pub fn validateProbe(probe: Probe) !void {
    if (probe.nonce.len == 0 or std.mem.indexOfScalar(u8, probe.nonce, 0) != null) {
        return error.MalformedProbe;
    }
    if (probe.role == .ui) return error.ProbeNotAllowedForUi;
    const parsed = parseProbe(probe.nonce) catch |err| return err;
    if (parsed != probe.role) return error.ProbeRoleMismatch;
}

pub fn role_from_name(value: []const u8) !Role {
    if (std.mem.eql(u8, value, "UI")) return .ui;
    if (std.mem.eql(u8, value, "PdfWorker")) return .pdf_worker;
    if (std.mem.eql(u8, value, "ScienceWorker")) return .science_worker;
    return error.UnknownRole;
}

pub const roleFromName = role_from_name;
pub const parse_probe = parseProbe;
