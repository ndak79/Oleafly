//! Allocation-free, single-owner presentation policy. This file imports no
//! Win32/D3D APIs and owns no native resources. `init` describes an already
//! created surface; bind/release acknowledgements describe the adapter's work.
//!
//! The native adapter must wait on the frame-latency handle before the first
//! and every subsequent render, draw every pixel in `draw_rect`, recheck
//! `can_present` immediately before Present1, and report its actual outcome.
//! A successful present requires a new back-buffer binding. Resize/rebuild
//! completion is admitted only after all buffer-reference releases are
//! acknowledged. The owner must serialize calls and native operations.
//! Binding state and reference ownership are separate: Present unbinds the
//! target but cannot acknowledge release of references retained by the owner.
//!
//! Two flip-sequential buffers retain conservative bounding-box scene damage;
//! repairing a buffer never propagates that repair as new scene damage. Scroll
//! copy/metadata is deliberately absent: callers mark the entire affected area
//! dirty or invalidate uncertain coverage. Flip-discard always redraws fully.
//!
//! Last-valid-frame records are logical identity only, not retained GPU pixels.
//! Preserving actual DWM-visible content, resource lifetime/COM order, thread
//! ownership, wait handles, HRESULT mapping, DPI messages, WARP creation, ETW,
//! and authoritative output capture require a later native binding and runtime
//! evidence. These tests cannot close native presentation/capture acceptance.

const std = @import("std");

/// The admitted baseline uses a single queued frame. This is the model-side
/// invariant corresponding to DXGI's maximum frame latency of one.
pub const max_frame_latency: u32 = 1;

pub const State = enum { visible, occluded, minimized, resizing, device_lost, rebuilding, ready };
pub const Visibility = enum { visible, occluded, minimized };
pub const RenderPath = enum { hardware, warp };
pub const PresentMode = enum { flip_sequential, flip_discard };
pub const WakeEvent = enum { frame, input, worker };
pub const Invalidation = enum {
    first_frame,
    resize,
    dpi_changed,
    adapter_changed,
    device_recovery,
    invalid_history,
    uncertain_coverage,
    theme_changed,
    occlusion,
    resumed,
};
pub const DeviceLoss = enum { removed, reset, hung, allocation_failed, adapter_changed, present_failed };
pub const PresentResult = union(enum) { presented, occluded, failed, device_lost: DeviceLoss };
pub const ResizeResult = union(enum) { succeeded, failed, device_lost: DeviceLoss };
pub const RebuildResult = enum { succeeded, unavailable, failed };
pub const RecoveryOutcome = enum { restored, retry_warp, failed };

pub const Extent = struct { width: u32, height: u32 };
pub const Surface = struct { extent: Extent, dpi: u16 = 96 };
pub const Config = struct {
    extent: Extent,
    dpi: u16 = 96,
    path: RenderPath = .hardware,
    mode: PresentMode = .flip_sequential,
};

/// Half-open physical-pixel bounds. Signed edges permit clipping offscreen
/// input without overflow from x + width or y + height arithmetic.
pub const Rect = struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,

    fn unite(a: Rect, b: Rect) Rect {
        return .{
            .left = @min(a.left, b.left),
            .top = @min(a.top, b.top),
            .right = @max(a.right, b.right),
            .bottom = @max(a.bottom, b.bottom),
        };
    }
};

pub const FramePlan = struct {
    token: u64,
    id: u64,
    buffer_index: u1,
    path: RenderPath,
    full_redraw: bool,
    draw_rect: Rect,
    /// null means zero dirty rectangles; no scroll metadata is ever emitted.
    dirty_rect: ?Rect,
};
pub const FrameRecord = struct { id: u64, surface: Surface, path: RenderPath };
pub const RebuildAttempt = struct { token: u64, path: RenderPath };

/// Caller-owned absolute one-shot deadlines, consumed by the input/worker
/// scheduler when due. This policy neither invents nor rearms a timer. A frame
/// waits on a latency handle, never a synthetic periodic frame deadline.
pub const Deadlines = struct { input_ms: ?u64 = null, worker_ms: ?u64 = null };
pub const WaitPlan = struct { frame: bool, input: bool = true, worker: bool = true, deadline_ms: ?u64 };

const History = struct { valid: bool = false, stale: ?Rect = null };
const Flight = struct { plan: FramePlan, scene_damage: Rect };
const Resize = struct { token: u64, target: Surface };
const Phase = union(enum) { available, resizing: Resize, device_lost: DeviceLoss, rebuilding: RebuildAttempt };

pub const Presenter = struct {
    surface: Surface,
    path: RenderPath,
    mode: PresentMode,
    phase_: Phase = .available,
    visibility_: Visibility = .visible,
    bound_: bool = false,
    references_held_: bool = false,
    frame_ready_: bool = false,
    buffer_index_: u1 = 0,
    histories_: [2]History = .{ .{}, .{} },
    dirty_: ?Rect = null,
    invalidation_: ?Invalidation = .first_frame,
    flight_: ?Flight = null,
    last_valid_: ?FrameRecord = null,
    next_token_: u64 = 1,
    recovery_path_: RenderPath,

    pub fn init(config: Config) !Presenter {
        const surface = Surface{ .extent = config.extent, .dpi = config.dpi };
        try validate_surface(surface);
        return .{ .surface = surface, .path = config.path, .mode = config.mode, .recovery_path_ = config.path };
    }

    /// `ready` means damage, a bound buffer, and an unconsumed latency signal.
    /// Resource transitions take precedence, retaining visibility for resume.
    pub fn state(self: *const Presenter) State {
        return switch (self.phase_) {
            .resizing => .resizing,
            .device_lost => .device_lost,
            .rebuilding => .rebuilding,
            .available => switch (self.visibility_) {
                .occluded => .occluded,
                .minimized => .minimized,
                .visible => if (self.frame_ready_ and self.bound_ and self.flight_ == null and self.has_damage()) .ready else .visible,
            },
        };
    }

    pub fn bind_back_buffer(self: *Presenter) !void {
        if (self.phase_ != .available) return error.NotPresentable;
        if (self.flight_ != null) return error.FrameInFlight;
        self.bound_ = true;
        self.references_held_ = true;
    }

    pub fn release_back_buffer(self: *Presenter) !void {
        if (self.flight_ != null) return error.FrameInFlight;
        self.bound_ = false;
        self.references_held_ = false;
    }

    /// Returns true only for a newly admitted frame-latency signal. Input and
    /// worker wakes are dispatched by their owners and cannot grant a frame.
    pub fn wake(self: *Presenter, event: WakeEvent) bool {
        if (event != .frame or !self.wait_plan(.{}).frame) return false;
        self.frame_ready_ = true;
        return true;
    }

    pub fn wait_plan(self: *const Presenter, deadlines: Deadlines) WaitPlan {
        return .{
            .frame = self.phase_ == .available and self.visibility_ == .visible and
                self.flight_ == null and !self.frame_ready_ and self.has_damage(),
            .deadline_ms = if (deadlines.input_ms) |input|
                if (deadlines.worker_ms) |worker| @min(input, worker) else input
            else
                deadlines.worker_ms,
        };
    }

    pub fn mark_dirty(self: *Presenter, rect: Rect) bool {
        const bounds = self.full_rect();
        const clipped = Rect{
            .left = @max(rect.left, bounds.left),
            .top = @max(rect.top, bounds.top),
            .right = @min(rect.right, bounds.right),
            .bottom = @min(rect.bottom, bounds.bottom),
        };
        if (clipped.left >= clipped.right or clipped.top >= clipped.bottom) return false;
        self.dirty_ = union_optional(self.dirty_, clipped);
        return true;
    }

    pub fn begin_frame(self: *Presenter, id: u64) !FramePlan {
        if (self.phase_ != .available or self.visibility_ != .visible) return error.NotPresentable;
        if (self.flight_ != null) return error.FrameInFlight;
        if (!self.frame_ready_) return error.FrameNotReady;
        if (!self.bound_) return error.BackBufferNotBound;
        if (!self.has_damage()) return error.NoDamage;
        const token = try self.take_token();
        const history = self.histories_[self.buffer_index_];
        const full_redraw = self.mode == .flip_discard or self.invalidation_ != null or !history.valid;
        // A full repair of an old/unknown buffer is not necessarily a new
        // full-scene change. Propagate only the actual captured scene damage.
        const scene_damage = if (self.invalidation_ != null) self.full_rect() else self.dirty_.?;
        const draw = if (full_redraw) self.full_rect() else union_optional(history.stale, scene_damage);
        const plan = FramePlan{
            .token = token,
            .id = id,
            .buffer_index = self.buffer_index_,
            .path = self.path,
            .full_redraw = full_redraw,
            .draw_rect = draw,
            .dirty_rect = if (full_redraw) null else draw,
        };
        self.flight_ = .{ .plan = plan, .scene_damage = scene_damage };
        self.dirty_ = null;
        self.invalidation_ = null;
        self.frame_ready_ = false;
        return plan;
    }

    pub fn can_present(self: *const Presenter, token: u64) bool {
        const flight = self.flight_ orelse return false;
        return flight.plan.token == token and self.phase_ == .available and
            self.visibility_ == .visible and self.bound_;
    }

    pub fn complete_frame(self: *Presenter, token: u64, result: PresentResult) !void {
        if (!self.can_present(token)) return error.StaleFrame;
        switch (result) {
            .presented => {
                const flight = self.flight_.?;
                self.histories_[self.buffer_index_] = .{ .valid = true };
                const other = &self.histories_[self.buffer_index_ ^ 1];
                if (other.valid) other.stale = union_optional(other.stale, flight.scene_damage);
                self.last_valid_ = .{ .id = flight.plan.id, .surface = self.surface, .path = self.path };
                self.flight_ = null;
                self.buffer_index_ ^= 1;
                self.bound_ = false;
            },
            .occluded => {
                // Present was submitted and consumed the latency grant even
                // though the compositor reported occlusion; cancellation of
                // the resulting flight must not replay that grant.
                self.frame_ready_ = false;
                self.set_visibility(.occluded);
                // set_visibility invalidates the submitted flight and its
                // generic same-chain cancellation path restores a grant for
                // pre-Present cancellations.  This branch is post-submit,
                // so consume the grant again after that transition.
                self.frame_ready_ = false;
            },
            // A generic failure cannot claim coherent back-buffer content.
            // Recovery requires an explicit owner action, not an automatic
            // retry on an already-signalled frame handle.
            .failed => {
                self.frame_ready_ = false;
                self.device_lost(.present_failed);
            },
            .device_lost => |reason| {
                self.frame_ready_ = false;
                self.device_lost(reason);
            },
        }
    }

    pub fn set_visibility(self: *Presenter, visibility: Visibility) void {
        if (self.visibility_ == visibility) return;
        self.visibility_ = visibility;
        self.invalidate(if (visibility == .visible) .resumed else .occlusion);
    }

    pub fn invalidate(self: *Presenter, reason: Invalidation) void {
        self.cancel_frame();
        self.histories_ = .{ .{}, .{} };
        self.invalidation_ = reason;
        // An acquired frame-latency signal is a resource grant, not a
        // periodic tick.  Invalidation before begin_frame consumes no grant;
        // dropping it would make a max-latency-one wait loop sleep forever
        // even though no Present has been queued to replenish the handle.
        // Native swap-chain recreation may explicitly clear/re-arm its new
        // handle at the adapter boundary; this pure model does not fabricate
        // that external event.
    }

    pub fn request_resize(self: *Presenter, extent: Extent) !u64 {
        return self.request_surface(.{ .extent = extent, .dpi = self.surface.dpi }, .resize);
    }

    pub fn request_dpi_change(self: *Presenter, dpi: u16, extent: Extent) !u64 {
        return self.request_surface(.{ .extent = extent, .dpi = dpi }, .dpi_changed);
    }

    fn request_surface(self: *Presenter, target: Surface, reason: Invalidation) !u64 {
        try validate_surface(target);
        if (self.phase_ != .available) return error.TransitionInProgress;
        const token = try self.take_token();
        self.invalidate(reason);
        self.phase_ = .{ .resizing = .{ .token = token, .target = target } };
        return token;
    }

    pub fn complete_resize(self: *Presenter, token: u64, result: ResizeResult) !void {
        const resize = switch (self.phase_) {
            .resizing => |resize| resize,
            else => return error.StaleTransition,
        };
        if (resize.token != token) return error.StaleTransition;
        if (self.references_held_) return error.BufferReferencesHeld;
        switch (result) {
            .succeeded, .failed => {
                if (result == .succeeded) {
                    self.surface = resize.target;
                    self.buffer_index_ = 0;
                }
                // Failure keeps the old surface. Either outcome requires
                // rebinding and a full redraw before any new frame is valid.
                self.phase_ = .available;
                self.dirty_ = null;
                self.invalidate(.resize);
            },
            .device_lost => |reason| self.device_lost(reason),
        }
    }

    pub fn device_lost(self: *Presenter, reason: DeviceLoss) void {
        self.recovery_path_ = switch (self.phase_) {
            .device_lost => self.recovery_path_,
            .rebuilding => |attempt| attempt.path,
            else => self.path,
        };
        self.invalidate(.device_recovery);
        // Device loss retires the swap chain and its frame-latency handle;
        // unlike same-chain invalidation, an acquired grant cannot cross the
        // recovery boundary.
        self.frame_ready_ = false;
        self.phase_ = .{ .device_lost = reason };
    }

    pub fn begin_rebuild(self: *Presenter) !RebuildAttempt {
        switch (self.phase_) {
            .device_lost => {},
            .resizing, .rebuilding => return error.TransitionInProgress,
            .available => return error.NotDeviceLost,
        }
        if (self.references_held_) return error.BufferReferencesHeld;
        const attempt = RebuildAttempt{ .token = try self.take_token(), .path = self.recovery_path_ };
        self.phase_ = .{ .rebuilding = attempt };
        return attempt;
    }

    pub fn complete_rebuild(self: *Presenter, attempt: RebuildAttempt, result: RebuildResult) !RecoveryOutcome {
        const active = switch (self.phase_) {
            .rebuilding => |active| active,
            else => return error.StaleTransition,
        };
        if (active.token != attempt.token or active.path != attempt.path) return error.StaleTransition;
        switch (result) {
            .succeeded => {
                self.path = active.path;
                self.phase_ = .available;
                self.buffer_index_ = 0;
                self.dirty_ = null;
                self.invalidate(.device_recovery);
                // Rebuild creates a new swap chain/waitable object.  Any
                // grant acquired from the retired chain is not transferable.
                self.frame_ready_ = false;
                return .restored;
            },
            .unavailable, .failed => {
                self.phase_ = .{ .device_lost = .allocation_failed };
                if (result == .unavailable and active.path == .hardware) {
                    self.recovery_path_ = .warp;
                    return .retry_warp;
                }
                return .failed;
            },
        }
    }

    pub fn last_valid_frame(self: *const Presenter) ?FrameRecord {
        return self.last_valid_;
    }

    pub fn buffer_history_valid(self: *const Presenter, index: u1) bool {
        return self.histories_[index].valid;
    }

    fn has_damage(self: *const Presenter) bool {
        return self.dirty_ != null or self.invalidation_ != null;
    }

    fn full_rect(self: *const Presenter) Rect {
        return .{ .left = 0, .top = 0, .right = @intCast(self.surface.extent.width), .bottom = @intCast(self.surface.extent.height) };
    }

    fn cancel_frame(self: *Presenter) void {
        if (self.flight_) |flight| {
            self.dirty_ = union_optional(self.dirty_, flight.scene_damage);
            // begin_frame consumed the signal, but no Present was submitted;
            // return that same-chain grant so invalidation cannot deadlock a
            // max-latency-one event loop.
            self.frame_ready_ = true;
        }
        self.flight_ = null;
    }

    fn take_token(self: *Presenter) !u64 {
        if (self.next_token_ == std.math.maxInt(u64)) return error.TokenExhausted;
        const token = self.next_token_;
        self.next_token_ += 1;
        return token;
    }
};

fn validate_surface(surface: Surface) !void {
    const max_extent = std.math.maxInt(i32);
    if (surface.extent.width == 0 or surface.extent.height == 0 or
        surface.extent.width > max_extent or surface.extent.height > max_extent) return error.InvalidExtent;
    if (surface.dpi == 0) return error.InvalidDpi;
}

fn union_optional(previous: ?Rect, rect: Rect) Rect {
    return if (previous) |old| Rect.unite(old, rect) else rect;
}
