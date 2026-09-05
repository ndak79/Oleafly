const std = @import("std");

pub const min_auto_delay_ms: u64 = 220;
pub const max_auto_delay_ms: u64 = 750;
pub const superseded_grace_ms: u64 = 75;

pub const Mode = enum {
    auto,
    on_save,
    manual,
};

pub const RenderMode = Mode;
pub const Auto = Mode.auto;
pub const OnSave = Mode.on_save;
pub const Manual = Mode.manual;

pub const Observation = struct {
    /// Time since the previous source-affecting edit.  Null means this is the
    /// first edit in the trace and contributes no cadence signal.
    edit_interval_ms: ?u64 = null,
    /// Most recent compile duration.  Zero means no completed job is known.
    job_cost_ms: u64 = 0,
    /// Whether the preceding interactive job was cancelled by supersession.
    was_cancelled: bool = false,
};

pub const Request = struct {
    revision: u64,
    due_ms: u64,
};

pub const CancelDecision = struct {
    cancel_revision: ?u64 = null,
    cancel_deadline_ms: ?u64 = null,
    ignored_edit: bool = false,
};

pub const CancellationRequest = struct {
    revision: u64,
    due_ms: u64,
};

pub const Completion = struct {
    revision: u64,
    artifact_id: u64,
    succeeded: bool,
};

pub const CompletionResult = enum {
    accepted,
    stale,
    failed,
    /// The result was for the latest revision, but no admitted worker was
    /// running for it.  Such a result cannot publish an unrequested artifact.
    not_started,
};

/// A deterministic scheduler model.  It never owns a timer or starts a
/// thread: the host waits for `next_deadline()` together with input/worker
/// events, then calls `take_due()` when that deadline is signalled.
pub const Scheduler = struct {
    mode: Mode,
    delay_ms: u64,
    latest_revision: u64 = 0,
    scheduled: ?Request = null,
    active_revision: ?u64 = null,
    active_started_ms: ?u64 = null,
    cancel_deadline_ms: ?u64 = null,
    /// Set once a cancellation request has been issued for the active job.
    /// Keeping this after the deadline event is consumed prevents an edit
    /// storm from reissuing cancellation for the same worker revision.
    cancel_requested_revision: ?u64 = null,
    current_revision: ?u64 = null,
    current_artifact: ?u64 = null,
    last_good_revision: ?u64 = null,
    last_good_artifact: ?u64 = null,
    last_edit_ms: ?u64 = null,
    cancellation_count: u32 = 0,

    pub fn init(mode: Mode) Scheduler {
        return .{ .mode = mode, .delay_ms = min_auto_delay_ms };
    }

    pub fn set_mode(self: *Scheduler, mode: Mode) void {
        self.mode = mode;
        if (mode != .auto) self.scheduled = null;
    }

    pub const setMode = set_mode;

    /// Record an edit and, in Auto mode, arrange one latest-only deadline.
    /// A stale edit is ignored rather than resurrecting old work.  Callers
    /// that need an error union can use `edit_checked`.
    pub fn edit(self: *Scheduler, revision: u64, at_ms: u64, observation: Observation) CancelDecision {
        if (revision <= self.latest_revision) return .{ .ignored_edit = true };
        self.latest_revision = revision;
        self.last_edit_ms = at_ms;
        self.adapt(observation);

        // The previous artifact remains available through the explicit
        // last-good accessors, but it is no longer current once source has
        // changed.
        self.current_revision = null;
        self.current_artifact = null;

        var decision: CancelDecision = .{};
        if (self.active_revision) |active| {
            if (active < revision) {
                if (self.cancel_requested_revision == active) {
                    // Cancellation was already admitted for this worker.  A
                    // subsequent edit may observe the same pending deadline,
                    // but must not extend it or issue another request.
                    decision.cancel_deadline_ms = self.cancel_deadline_ms;
                } else {
                    const proposed_deadline = at_ms +| superseded_grace_ms;
                    const deadline = if (self.cancel_deadline_ms) |existing|
                        @min(existing, proposed_deadline)
                    else
                        proposed_deadline;
                    self.cancel_deadline_ms = deadline;
                    self.cancel_requested_revision = active;
                    decision.cancel_revision = active;
                    decision.cancel_deadline_ms = deadline;
                    self.cancellation_count +|= 1;
                }
            }
        }

        if (self.mode == .auto) {
            self.scheduled = .{ .revision = revision, .due_ms = at_ms +| self.delay_ms };
        } else {
            self.scheduled = null;
        }
        return decision;
    }

    pub fn edit_checked(self: *Scheduler, revision: u64, at_ms: u64, observation: Observation) !CancelDecision {
        if (revision <= self.latest_revision) return error.RevisionNotMonotonic;
        return self.edit(revision, at_ms, observation);
    }

    pub const editChecked = edit_checked;

    pub fn next_deadline(self: *const Scheduler) ?u64 {
        // A due request stays queued while another revision is still active;
        // suppress its already-expired timestamp until the cancellation or
        // stale-completion event retires that worker, avoiding a busy loop.
        var next: ?u64 = if (self.scheduled) |request| blk: {
            if (self.active_revision) |active| {
                if (active != request.revision) break :blk null;
            }
            break :blk request.due_ms;
        } else null;
        if (self.cancel_deadline_ms) |deadline| {
            if (next == null or deadline < next.?) next = deadline;
        }
        return next;
    }

    pub const nextDeadline = next_deadline;

    /// Consume the one pending deadline when the host's event wait reports
    /// that it has elapsed.  This is intentionally not a periodic tick.
    pub fn take_due(self: *Scheduler, now_ms: u64) ?Request {
        const request = self.scheduled orelse return null;
        if (now_ms < request.due_ms) return null;
        if (request.revision != self.latest_revision) {
            self.scheduled = null;
            return null;
        }
        if (self.active_revision) |active| {
            // Keep the latest request queued for a deterministic hand-off;
            // the host retries after stale completion/acknowledged cancel.
            if (active != request.revision) return null;
        }
        self.scheduled = null;
        return request;
    }

    pub const takeDue = take_due;

    /// Consume the single cancellation deadline event, if it has elapsed.
    /// The active worker remains tracked until its completion arrives; the
    /// retained request marker prevents later edits from reissuing it.
    pub fn take_cancellation_due(self: *Scheduler, now_ms: u64) ?CancellationRequest {
        const deadline = self.cancel_deadline_ms orelse return null;
        if (now_ms < deadline) return null;
        const revision = self.active_revision orelse {
            self.cancel_deadline_ms = null;
            return null;
        };
        self.cancel_deadline_ms = null;
        return .{ .revision = revision, .due_ms = deadline };
    }

    pub const takeCancellationDue = take_cancellation_due;

    pub fn mark_started(self: *Scheduler, revision: u64, at_ms: u64) bool {
        if (revision != self.latest_revision) return false;
        if (self.active_revision) |active| {
            // A newer request cannot erase the older worker's cancellation
            // deadline.  The host must observe its stale completion or
            // explicitly acknowledge cancellation before admitting another
            // active job.
            if (active != revision) return false;
            return true;
        }
        self.active_revision = revision;
        self.active_started_ms = at_ms;
        self.cancel_deadline_ms = null;
        self.cancel_requested_revision = null;
        if (self.scheduled) |request| {
            if (request.revision == revision) self.scheduled = null;
        }
        return true;
    }

    pub const markStarted = mark_started;

    /// Retire a worker that acknowledged a cancellation request without
    /// producing a completion payload.  This is the explicit hand-off point
    /// that allows the latest request to start while keeping stale results
    /// non-publishable.
    pub fn acknowledge_cancelled(self: *Scheduler, revision: u64) bool {
        if (self.active_revision != revision) return false;
        self.retire_active();
        return true;
    }

    pub const acknowledgeCancelled = acknowledge_cancelled;

    /// Schedule an accepted save revision at the event's timestamp.  OnSave
    /// never compiles ordinary edits and rejects a save for an old revision.
    pub fn save(self: *Scheduler, revision: u64, at_ms: u64) ?Request {
        if (self.mode != .on_save or revision != self.latest_revision) return null;
        const request = Request{ .revision = revision, .due_ms = at_ms };
        self.scheduled = request;
        return request;
    }

    pub const on_save = save;
    pub const onSave = save;

    /// Manual mode responds only to an explicit command and schedules it at
    /// exactly that command time.
    pub fn request_manual(self: *Scheduler, revision: u64, at_ms: u64) ?Request {
        if (self.mode != .manual or revision != self.latest_revision) return null;
        const request = Request{ .revision = revision, .due_ms = at_ms };
        self.scheduled = request;
        return request;
    }

    pub const requestManual = request_manual;
    pub const manual = request_manual;

    pub fn supersession_expired(self: *const Scheduler, now_ms: u64) bool {
        return if (self.cancel_deadline_ms) |deadline| now_ms >= deadline else false;
    }

    pub const supersessionExpired = supersession_expired;

    /// A completion can publish only if its revision is still the latest
    /// source revision.  Failed or stale results never replace last-good.
    pub fn complete(self: *Scheduler, completion: Completion) CompletionResult {
        const was_active = self.active_revision == completion.revision;
        if (was_active) self.retire_active();
        if (completion.revision != self.latest_revision) return .stale;
        if (!was_active) return .not_started;
        if (!completion.succeeded) {
            return .failed;
        }
        self.current_revision = completion.revision;
        self.current_artifact = completion.artifact_id;
        self.last_good_revision = completion.revision;
        self.last_good_artifact = completion.artifact_id;
        return .accepted;
    }

    pub const completeRevision = complete;

    pub fn current_artifact_id(self: *const Scheduler) ?u64 {
        return self.current_artifact;
    }

    pub const currentArtifactId = current_artifact_id;

    pub fn last_good_artifact_id(self: *const Scheduler) ?u64 {
        return self.last_good_artifact;
    }

    pub const lastGoodArtifactId = last_good_artifact_id;

    pub fn last_good_revision_id(self: *const Scheduler) ?u64 {
        return self.last_good_revision;
    }

    pub const lastGoodRevisionId = last_good_revision_id;

    fn retire_active(self: *Scheduler) void {
        self.active_revision = null;
        self.active_started_ms = null;
        self.cancel_deadline_ms = null;
        self.cancel_requested_revision = null;
    }

    fn adapt(self: *Scheduler, observation: Observation) void {
        var next = self.delay_ms;
        if (observation.edit_interval_ms) |interval| {
            if (interval < min_auto_delay_ms) {
                next +|= (min_auto_delay_ms - interval) / 2;
            } else if (interval > next) {
                next -|= @min((interval - next) / 4, 80);
            }
        }
        if (observation.job_cost_ms > next) {
            next +|= @min((observation.job_cost_ms - next) / 3 + 1, 120);
        } else if (observation.job_cost_ms != 0 and next > min_auto_delay_ms) {
            next -|= @min((next - observation.job_cost_ms) / 8 + 1, 40);
        }
        if (observation.was_cancelled) next +|= 35;
        self.delay_ms = std.math.clamp(next, min_auto_delay_ms, max_auto_delay_ms);
    }
};
