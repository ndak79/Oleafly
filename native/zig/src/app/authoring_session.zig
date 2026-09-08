const std = @import("std");
const workspace = @import("workspace");
const editor_buffer = @import("editor_buffer");
const atomic_save = @import("atomic_save");

pub const SessionState = enum {
    idle,
    workspace_opened,
    needs_main_choice,
    active,
    conflicted,
    missing,
};

pub const EditEvent = struct {
    sequence: u64,
    start: usize,
    deleted_len: usize,
    inserted_text: []const u8,
};

pub const SaveStatus = enum {
    clean,
    external_change_refused,
    recovery_retained,
    failed,
};

pub const SaveOutcome = struct {
    allocator: std.mem.Allocator,
    status: SaveStatus,
    target_hash: [32]u8,
    recovery_path: ?[]u8 = null,

    pub fn deinit(self: *SaveOutcome) void {
        if (self.recovery_path) |p| self.allocator.free(p);
        self.recovery_path = null;
    }
};

pub const ExternalChange = enum {
    file_changed,
    file_deleted,
    watch_overflow,
    rescan_complete,
};

pub const SessionEvent = union(enum) {
    folder_opened: struct { root_path: []const u8 },
    main_chosen: struct { relative_path: []const u8 },
    edit_applied: EditEvent,
    saved: SaveOutcome,
    external: ExternalChange,
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    workspace_val: ?workspace.Workspace = null,
    buffer_val: ?editor_buffer.Buffer = null,
    active_rel_path: ?[]u8 = null,
    state_val: SessionState = .idle,
    next_sequence: u64 = 1,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Session {
        return .{
            .allocator = allocator,
            .io = io,
        };
    }

    pub fn deinit(self: *Session) void {
        if (self.buffer_val) |*b| b.deinit();
        self.buffer_val = null;
        if (self.workspace_val) |*w| w.deinit();
        self.workspace_val = null;
        if (self.active_rel_path) |p| self.allocator.free(p);
        self.active_rel_path = null;
        self.state_val = .idle;
        self.* = undefined;
    }

    pub fn openFolder(self: *Session, folder_path: []const u8) !void {
        if (self.buffer_val) |*b| {
            b.deinit();
            self.buffer_val = null;
        }
        if (self.active_rel_path) |p| {
            self.allocator.free(p);
            self.active_rel_path = null;
        }
        if (self.workspace_val) |*w| {
            w.deinit();
            self.workspace_val = null;
        }

        var ws = try workspace.Workspace.open(self.allocator, self.io, folder_path);
        errdefer ws.deinit();
        self.workspace_val = ws;

        const decision = self.workspace_val.?.rootDecision();
        switch (decision.status) {
            .selected => {
                if (decision.selected_index) |idx| {
                    const files = self.workspace_val.?.files();
                    if (idx < files.len) {
                        try self.attachMain(files[idx].relative_path);
                        return;
                    }
                }
                self.state_val = .workspace_opened;
            },
            .needs_main_choice => {
                self.state_val = .needs_main_choice;
            },
            .no_candidate => {
                self.state_val = .workspace_opened;
            },
        }
    }

    pub fn attachMain(self: *Session, relative_path: []const u8) !void {
        const ws = self.workspace_val orelse return error.NoWorkspaceOpen;

        if (std.mem.indexOf(u8, relative_path, "..") != null or
            std.fs.path.isAbsolute(relative_path))
        {
            return error.InvalidPath;
        }

        var file_found = false;
        for (ws.files()) |f| {
            if (std.mem.eql(u8, f.relative_path, relative_path)) {
                file_found = true;
                break;
            }
        }
        if (!file_found) return error.FileNotFoundInWorkspace;

        if (self.buffer_val) |*b| {
            b.deinit();
            self.buffer_val = null;
        }
        if (self.active_rel_path) |p| {
            self.allocator.free(p);
            self.active_rel_path = null;
        }

        const abs_path = try std.fs.path.join(self.allocator, &.{ ws.rootPath(), relative_path });
        defer self.allocator.free(abs_path);

        var root_dir = try std.Io.Dir.openDirAbsolute(self.io, ws.rootPath(), .{
            .iterate = false,
            .follow_symlinks = false,
        });
        defer root_dir.close(self.io);

        const bytes = try root_dir.readFileAlloc(self.io, relative_path, self.allocator, .limited(workspace.max_source_bytes));
        defer self.allocator.free(bytes);

        var buf = try editor_buffer.Buffer.attach(self.allocator, abs_path, bytes);
        errdefer buf.deinit();

        self.buffer_val = buf;
        self.active_rel_path = try self.allocator.dupe(u8, relative_path);
        self.state_val = .active;
        self.next_sequence = 1;
    }

    pub fn applyEdit(self: *Session, edit: EditEvent) !void {
        var buf = &(self.buffer_val orelse return error.NoActiveBuffer);
        if (self.state_val == .conflicted or self.state_val == .missing) {
            return error.BufferInUnresolvedState;
        }

        if (edit.sequence != self.next_sequence) {
            buf.markConflicted();
            self.state_val = .conflicted;
            return error.SequenceMismatch;
        }

        buf.applyEdit(edit.sequence, edit.start, edit.deleted_len, edit.inserted_text) catch |err| {
            buf.markConflicted();
            self.state_val = .conflicted;
            return err;
        };

        self.next_sequence += 1;
        self.state_val = .active;
    }

    pub fn save(self: *Session) !SaveOutcome {
        var buf = &(self.buffer_val orelse return error.NoActiveBuffer);
        const ws = self.workspace_val orelse return error.NoWorkspaceOpen;
        const rel_path = self.active_rel_path orelse return error.NoActiveBuffer;

        if (self.state_val == .conflicted) {
            return error.BufferConflicted;
        }
        if (self.state_val == .missing) {
            return error.BufferMissing;
        }

        const abs_path = try std.fs.path.join(self.allocator, &.{ ws.rootPath(), rel_path });
        defer self.allocator.free(abs_path);

        const materialized_bytes = try buf.materialize(self.allocator);
        defer self.allocator.free(materialized_bytes);

        const expected_saved_hash = buf.savedHash();
        const current_rev = buf.revision();

        const save_res = atomic_save.save(
            self.allocator,
            self.io,
            abs_path,
            expected_saved_hash,
            materialized_bytes,
            current_rev,
        ) catch |err| switch (err) {
            error.ExternalChange => {
                buf.markConflicted();
                self.state_val = .conflicted;
                return .{
                    .allocator = self.allocator,
                    .status = .external_change_refused,
                    .target_hash = expected_saved_hash,
                    .recovery_path = null,
                };
            },
            else => return err,
        };

        const outcome: SaveOutcome = .{
            .allocator = self.allocator,
            .status = switch (save_res.status) {
                .replaced => .clean,
                .recovery_retained => .recovery_retained,
            },
            .target_hash = save_res.target_hash,
            .recovery_path = save_res.recovery_path,
        };

        if (outcome.status == .clean) {
            try buf.markSaved(outcome.target_hash);
            self.state_val = .active;
        } else if (outcome.status == .recovery_retained) {
            buf.markConflicted();
            self.state_val = .conflicted;
        }

        return outcome;
    }

    pub fn handleExternalEvent(
        self: *Session,
        event: ExternalChange,
        rel_path: ?[]const u8,
        new_hash: ?[32]u8,
    ) !void {
        _ = new_hash;
        switch (event) {
            .file_changed => {
                if (rel_path) |target| {
                    if (self.active_rel_path) |active| {
                        if (std.mem.eql(u8, target, active)) {
                            if (self.buffer_val) |*buf| {
                                if (buf.state() == .clean) {
                                    const ws = self.workspace_val orelse return;
                                    var root_dir = try std.Io.Dir.openDirAbsolute(self.io, ws.rootPath(), .{
                                        .iterate = false,
                                        .follow_symlinks = false,
                                    });
                                    defer root_dir.close(self.io);
                                    const bytes = try root_dir.readFileAlloc(self.io, active, self.allocator, .limited(workspace.max_source_bytes));
                                    defer self.allocator.free(bytes);
                                    const abs_path = try std.fs.path.join(self.allocator, &.{ ws.rootPath(), active });
                                    defer self.allocator.free(abs_path);

                                    buf.deinit();
                                    self.buffer_val = try editor_buffer.Buffer.attach(self.allocator, abs_path, bytes);
                                    self.state_val = .active;
                                } else {
                                    buf.markConflicted();
                                    self.state_val = .conflicted;
                                }
                            }
                        }
                    }
                }
            },
            .file_deleted => {
                if (rel_path) |target| {
                    if (self.active_rel_path) |active| {
                        if (std.mem.eql(u8, target, active)) {
                            if (self.buffer_val) |*buf| {
                                buf.markMissing();
                                self.state_val = .missing;
                            }
                        }
                    }
                }
            },
            .watch_overflow => {
                if (self.workspace_val) |*ws| {
                    try ws.rescan();
                }
            },
            .rescan_complete => {
                if (self.workspace_val) |*ws| {
                    try ws.rescan();
                }
            },
        }
    }

    pub fn state(self: *const Session) SessionState {
        return self.state_val;
    }

    pub fn getWorkspace(self: *const Session) ?*const workspace.Workspace {
        if (self.workspace_val) |*ws| return ws;
        return null;
    }

    pub fn getBuffer(self: *const Session) ?*const editor_buffer.Buffer {
        if (self.buffer_val) |*b| return b;
        return null;
    }
};
