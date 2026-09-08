//! Dedicated COM STA thread for the UIA text provider.
//!
//! The UI thread publishes immutable, revision-stamped snapshots.  The
//! provider STA owns those references and never reads Scintilla, a raw
//! HWND, or mutable UI storage directly.
//!
//! Mutating UIA operations (SetFocus, Select, ScrollIntoView) are routed
//! through a bounded typed command to the UI owner thread with a request
//! ID, snapshot revision, arguments, and deadline.  The UI rejects stale
//! revisions.
//!
//! On non-Windows targets this module compiles but provides no runtime
//! functionality.

const builtin = @import("builtin");
const std = @import("std");
const snapshot_mod = @import("uia_snapshot");
const range_mod = @import("uia_range");

pub const Mutex = struct {
    state: std.atomic.Mutex = .unlocked,

    pub fn lock(self: *Mutex) void {
        while (!self.state.tryLock()) {
            std.atomic.spinLoopHint();
        }
    }

    pub fn unlock(self: *Mutex) void {
        self.state.unlock();
    }
};

pub const max_mutation_commands = 64;

/// A mutation request from the provider STA to the UI owner thread.
pub const MutationCommand = struct {
    kind: MutationKind,
    request_id: u64,
    /// Snapshot revision at the time the command was created.
    revision: u64,
    /// Arguments depend on `kind`.
    arg0: usize = 0,
    arg1: usize = 0,
};

pub const MutationKind = enum {
    set_focus,
    select_range,
    add_to_selection,
    remove_from_selection,
    scroll_into_view,
    move_caret,
};

pub const MutationResult = struct {
    request_id: u64,
    accepted: bool,
    revision: u64,
};

pub const ProviderThread = struct {
    allocator: std.mem.Allocator,
    /// The latest snapshot published by the UI thread.
    current_snapshot: std.atomic.Value(?*snapshot_mod.Snapshot),
    /// Range pool for live ITextRangeProvider objects.
    range_pool: range_mod.RangePool,
    /// Mutation command queue (provider STA -> UI thread).
    mutation_queue: [max_mutation_commands]MutationCommand = undefined,
    mutation_head: usize = 0,
    mutation_tail: usize = 0,
    mutation_mutex: Mutex = .{},
    /// Result queue (UI thread -> provider STA).
    result_queue: [max_mutation_commands]MutationResult = undefined,
    result_head: usize = 0,
    result_tail: usize = 0,
    result_mutex: Mutex = .{},
    /// Next request ID for correlation.
    next_request_id: std.atomic.Value(u64),
    /// Shutdown flag.
    shutdown: std.atomic.Value(bool),
    /// Edit journal for anchor transforms.
    journal: [snapshot_mod.max_edit_journal]snapshot_mod.EditRecord = undefined,
    journal_head: usize = 0,
    journal_tail: usize = 0,
    journal_generation: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) ProviderThread {
        return .{
            .allocator = allocator,
            .current_snapshot = std.atomic.Value(?*snapshot_mod.Snapshot).init(null),
            .range_pool = range_mod.RangePool.init(allocator),
            .next_request_id = std.atomic.Value(u64).init(1),
            .shutdown = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *ProviderThread) void {
        self.range_pool.invalidateAll();
        self.range_pool.deinit();
        if (self.current_snapshot.load(.acquire)) |snap| {
            snap.release();
        }
    }

    /// Called by the UI thread to publish a new snapshot.
    pub fn publishSnapshot(self: *ProviderThread, snap: *snapshot_mod.Snapshot) void {
        snap.acquire();
        const old = self.current_snapshot.swap(snap, .acq_rel);
        if (old) |prev| prev.release();
    }

    /// Called by the UI thread to record an edit for range transforms.
    pub fn recordEdit(self: *ProviderThread, edit: snapshot_mod.EditRecord) void {
        const next = (self.journal_tail + 1) % snapshot_mod.max_edit_journal;
        if (next == self.journal_head) {
            // Journal full: wrap generation, invalidate all ranges.
            self.journal_generation += 1;
            self.journal_head = 0;
            self.journal_tail = 0;
            self.range_pool.invalidateAll();
        }
        self.journal[self.journal_tail] = edit;
        self.journal_tail = next;
        self.range_pool.applyEdit(edit, self.journal_generation);
    }

    /// Get the current snapshot (provider STA only).
    pub fn getSnapshot(self: *ProviderThread) ?*snapshot_mod.Snapshot {
        return self.current_snapshot.load(.acquire);
    }

    /// Enqueue a mutation command from the provider STA.
    pub fn postMutation(self: *ProviderThread, cmd: MutationCommand) bool {
        self.mutation_mutex.lock();
        defer self.mutation_mutex.unlock();
        const next = (self.mutation_tail + 1) % max_mutation_commands;
        if (next == self.mutation_head) return false;
        self.mutation_queue[self.mutation_tail] = cmd;
        self.mutation_tail = next;
        return true;
    }

    /// Drain pending mutations (UI thread).
    pub fn drainMutations(self: *ProviderThread, out: []MutationCommand) usize {
        self.mutation_mutex.lock();
        defer self.mutation_mutex.unlock();
        var count: usize = 0;
        while (self.mutation_head != self.mutation_tail and count < out.len) {
            out[count] = self.mutation_queue[self.mutation_head];
            self.mutation_head = (self.mutation_head + 1) % max_mutation_commands;
            count += 1;
        }
        return count;
    }

    /// Post a mutation result from the UI thread.
    pub fn postResult(self: *ProviderThread, result: MutationResult) void {
        self.result_mutex.lock();
        defer self.result_mutex.unlock();
        const next = (self.result_tail + 1) % max_mutation_commands;
        if (next == self.result_head) return;
        self.result_queue[self.result_tail] = result;
        self.result_tail = next;
    }

    /// Poll for mutation results (provider STA).
    pub fn pollResult(self: *ProviderThread) ?MutationResult {
        self.result_mutex.lock();
        defer self.result_mutex.unlock();
        if (self.result_head == self.result_tail) return null;
        const r = self.result_queue[self.result_head];
        self.result_head = (self.result_head + 1) % max_mutation_commands;
        return r;
    }

    pub fn requestShutdown(self: *ProviderThread) void {
        self.shutdown.store(true, .release);
    }

    pub fn isShutdownRequested(self: *ProviderThread) bool {
        return self.shutdown.load(.acquire);
    }

    pub fn allocateRequestId(self: *ProviderThread) u64 {
        return self.next_request_id.fetchAdd(1, .monotonic);
    }
};
