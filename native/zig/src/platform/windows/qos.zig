//! Narrow, capability-tested QoS scope for the UI thread.  It never raises
//! process priority and never changes timer resolution.  Unsupported power or
//! memory-priority calls are ordinary fallbacks, not startup failures.
const builtin = @import("builtin");

pub const State = struct {
    background_power: bool = false,
    background_memory: bool = false,
    background_requested: bool = false,
    foreground_scope: bool = false,
    foreground_priority: bool = false,
    saved_priority: i32 = 0,
    saved_memory_priority: u32 = memory_priority_normal,
    saved_memory_priority_valid: bool = false,

    pub fn enterForeground(self: *State) void {
        if (self.foreground_scope) return;
        self.foreground_scope = true;
        self.clearBackground();
        if (comptime builtin.os.tag != .windows) return;
        const thread = raw.GetCurrentThread();
        const previous = raw.GetThreadPriority(thread);
        if (previous == thread_priority_error) return;
        if (raw.SetThreadPriority(thread, thread_priority_above_normal) != 0) {
            self.saved_priority = previous;
            self.foreground_priority = true;
        }
    }

    pub fn leaveForeground(self: *State) void {
        if (!self.foreground_scope) return;
        if (comptime builtin.os.tag == .windows) {
            if (self.foreground_priority) _ = raw.SetThreadPriority(raw.GetCurrentThread(), self.saved_priority);
        }
        self.foreground_priority = false;
        self.foreground_scope = false;
        if (self.background_requested) self.applyBackground();
    }

    pub fn enterBackground(self: *State) void {
        self.background_requested = true;
        if (self.foreground_scope) return;
        self.applyBackground();
    }

    pub fn leaveBackground(self: *State) void {
        self.background_requested = false;
        if (self.foreground_scope) return;
        self.clearBackground();
    }

    fn applyBackground(self: *State) void {
        if (comptime builtin.os.tag != .windows) return;
        const thread = raw.GetCurrentThread();
        if (!self.background_power) {
            var power = THREAD_POWER_THROTTLING_STATE{
                .Version = thread_power_throttling_current_version,
                .ControlMask = thread_power_throttling_execution_speed,
                .StateMask = thread_power_throttling_execution_speed,
            };
            if (raw.SetThreadInformation(thread, thread_power_throttling, &power, @sizeOf(@TypeOf(power))) != 0) {
                self.background_power = true;
            }
        }
        if (!self.background_memory) {
            if (!self.saved_memory_priority_valid) {
                var saved = MEMORY_PRIORITY_INFORMATION{ .MemoryPriority = memory_priority_normal };
                if (raw.GetProcessInformation(
                    raw.GetCurrentProcess(),
                    process_memory_priority,
                    &saved,
                    @sizeOf(@TypeOf(saved)),
                ) != 0) {
                    self.saved_memory_priority = saved.MemoryPriority;
                    self.saved_memory_priority_valid = true;
                }
            }
            var memory = MEMORY_PRIORITY_INFORMATION{ .MemoryPriority = memory_priority_low };
            if (raw.SetProcessInformation(
                raw.GetCurrentProcess(),
                process_memory_priority,
                &memory,
                @sizeOf(@TypeOf(memory)),
            ) != 0) self.background_memory = true;
        }
    }

    fn clearBackground(self: *State) void {
        if (comptime builtin.os.tag != .windows) return;
        const thread = raw.GetCurrentThread();
        if (self.background_power) {
            var power = THREAD_POWER_THROTTLING_STATE{
                .Version = thread_power_throttling_current_version,
                .ControlMask = thread_power_throttling_execution_speed,
                .StateMask = 0,
            };
            if (raw.SetThreadInformation(thread, thread_power_throttling, &power, @sizeOf(@TypeOf(power))) != 0) {
                self.background_power = false;
            }
        }
        if (self.background_memory) {
            var memory = MEMORY_PRIORITY_INFORMATION{ .MemoryPriority = if (self.saved_memory_priority_valid)
                self.saved_memory_priority
            else
                memory_priority_normal };
            if (raw.SetProcessInformation(
                raw.GetCurrentProcess(),
                process_memory_priority,
                &memory,
                @sizeOf(@TypeOf(memory)),
            ) != 0) {
                self.background_memory = false;
                self.saved_memory_priority_valid = false;
            }
        }
    }

    pub fn deinit(self: *State) void {
        self.background_requested = false;
        self.leaveForeground();
        self.clearBackground();
    }
};

const thread_priority_above_normal: i32 = 1;
const thread_priority_error: i32 = 0x7fff_ffff;
const thread_power_throttling: u32 = 9; // ThreadPowerThrottling
const thread_power_throttling_current_version: u32 = 1;
const thread_power_throttling_execution_speed: u32 = 1;
const process_memory_priority: u32 = 0; // ProcessMemoryPriority
const memory_priority_low: u32 = 2;
const memory_priority_normal: u32 = 5;

const THREAD_POWER_THROTTLING_STATE = extern struct {
    Version: u32,
    ControlMask: u32,
    StateMask: u32,
};

const MEMORY_PRIORITY_INFORMATION = extern struct { MemoryPriority: u32 };

const raw = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn GetCurrentThread() callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetCurrentProcess() callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetThreadPriority(?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn SetThreadPriority(?*anyopaque, i32) callconv(.winapi) i32;
    extern "kernel32" fn GetProcessInformation(?*anyopaque, u32, *anyopaque, usize) callconv(.winapi) i32;
    extern "kernel32" fn SetThreadInformation(?*anyopaque, u32, *anyopaque, usize) callconv(.winapi) i32;
    extern "kernel32" fn SetProcessInformation(?*anyopaque, u32, *anyopaque, usize) callconv(.winapi) i32;
} else struct {};

test "QoS state starts as an ordinary no-timer policy" {
    const state: State = .{};
    try @import("std").testing.expect(!state.background_power);
    try @import("std").testing.expect(!state.background_memory);
    try @import("std").testing.expect(!state.foreground_priority);
    try @import("std").testing.expect(!state.background_requested);
}
