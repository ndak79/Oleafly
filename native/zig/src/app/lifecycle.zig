/// Pure state machine for app-owned resources.  It deliberately stores only
/// ownership and ordering; native handles are released by the owner thread
/// after the typed transition has been admitted.
pub const Owner = enum {
    ui_thread,
    database,
    worker,
    uia,
    graphics,
};

pub const Phase = enum {
    created,
    running,
    closing,
    closed,
    crashed,
};

pub const CloseOutcome = enum {
    admitted,
    already_closing,
    already_closed,
    already_crashed,
};

pub const ReleaseOutcome = enum {
    released,
    already_released,
};

pub const ExitKind = enum {
    clean,
    crashed,
};

pub const ExitOutcome = enum {
    clean,
    crashed,
    not_ready,
    already_finished,
};

pub const Lifecycle = struct {
    phase_state: Phase = .created,
    owners: [owner_count]bool = [_]bool{false} ** owner_count,
    stack: [owner_count]Owner = undefined,
    stack_len: usize = 0,
    highest_rank: ?usize = null,
    finished: bool = false,

    pub const owner_count = @typeInfo(Owner).@"enum".fields.len;

    pub fn init() Lifecycle {
        return .{};
    }

    pub fn phase(self: *const Lifecycle) Phase {
        return self.phase_state;
    }

    pub const state = phase;

    pub fn acquire(self: *Lifecycle, owner: Owner) !void {
        if (self.phase_state == .closing or self.phase_state == .closed or self.phase_state == .crashed) {
            return error.AcquireAfterClose;
        }
        const index = rank(owner);
        if (self.owners[index]) return error.DuplicateOwnership;
        if (self.highest_rank) |previous| {
            if (index <= previous) return error.NonMonotonicOwnership;
        }
        self.owners[index] = true;
        self.stack[self.stack_len] = owner;
        self.stack_len += 1;
        self.highest_rank = index;
        self.phase_state = .running;
    }

    pub const acquireOwnership = acquire;

    pub fn begin_close(self: *Lifecycle) CloseOutcome {
        return switch (self.phase_state) {
            .created, .running => blk: {
                // Startup can fail before the first owner is acquired.  An
                // empty lifecycle has nothing to drain, so close it directly
                // instead of leaving clean shutdown permanently pending.
                self.phase_state = if (self.stack_len == 0) .closed else .closing;
                break :blk .admitted;
            },
            .closing => .already_closing,
            .closed => .already_closed,
            .crashed => .already_crashed,
        };
    }

    pub const beginClose = begin_close;

    pub fn release(self: *Lifecycle, owner: Owner) !ReleaseOutcome {
        const index = rank(owner);
        if (!self.owners[index]) return .already_released;
        if (self.phase_state != .closing and self.phase_state != .crashed) return error.ReleaseBeforeClose;
        if (self.stack_len == 0 or self.stack[self.stack_len - 1] != owner) {
            return error.OutOfOrderRelease;
        }
        self.stack_len -= 1;
        self.owners[index] = false;
        self.highest_rank = if (self.stack_len == 0) null else rank(self.stack[self.stack_len - 1]);
        if (self.stack_len == 0 and self.phase_state == .closing) self.phase_state = .closed;
        return .released;
    }

    pub const releaseOwnership = release;

    pub fn finish(self: *Lifecycle, kind: ExitKind) ExitOutcome {
        if (self.finished) return .already_finished;
        return switch (kind) {
            .clean => if (self.phase_state == .closed and self.stack_len == 0) blk: {
                self.finished = true;
                break :blk .clean;
            } else .not_ready,
            .crashed => self.crash(),
        };
    }

    pub fn crash(self: *Lifecycle) ExitOutcome {
        if (self.finished) return .already_finished;
        return switch (self.phase_state) {
            .closed, .crashed => .already_finished,
            .created, .running, .closing => blk: {
                self.phase_state = .crashed;
                self.finished = true;
                break :blk .crashed;
            },
        };
    }

    pub fn owned(self: *const Lifecycle, owner: Owner) bool {
        return self.owners[rank(owner)];
    }

    pub fn outstanding(self: *const Lifecycle) usize {
        return self.stack_len;
    }
};

fn rank(owner: Owner) usize {
    return @intFromEnum(owner);
}
