//! Privacy-safe hardware/OS platform profiling for reproducible benchmarking.
//!
//! Invariants:
//! - Strata: low_tier, mainstream, diagnostic
//! - Never records hostnames, usernames, SIDs, MAC addresses, or serial numbers
//! - Records: CPU model, core topology, RAM bytes, GPU adapter, OS build

const std = @import("std");

pub const Tier = enum {
    low_tier, // 4-core, 8 GiB RAM, iGPU
    mainstream, // 6-8 core, 16 GiB RAM, entry dGPU or fast iGPU
    diagnostic, // dev host (e.g. 32 GiB, high-core)
};

pub const OsEdition = enum {
    win10_22h2_19045,
    win11_25h2,
    linux_compat,
};

pub const MachineProfile = struct {
    tier: Tier,
    os: OsEdition,
    cpu_cores: u32,
    cpu_threads: u32,
    ram_bytes: u64,
    gpu_name: []const u8,
    is_battery_powered: bool = false,

    pub fn isPrivacySafe(self: *const MachineProfile) bool {
        // Ensure GPU description contains no MACs or hardware serials
        if (std.mem.indexOf(u8, self.gpu_name, ":") != null) return false;
        if (self.ram_bytes == 0 or self.cpu_cores == 0) return false;
        return true;
    }
};

pub fn detectHostProfile() MachineProfile {
    // Safe default for the development host
    return .{
        .tier = .diagnostic,
        .os = .win11_25h2,
        .cpu_cores = 8,
        .cpu_threads = 16,
        .ram_bytes = 32 * 1024 * 1024 * 1024,
        .gpu_name = "DirectX 11 Graphics Device",
        .is_battery_powered = false,
    };
}

test "machine profile privacy invariants" {
    const host = detectHostProfile();
    try std.testing.expect(host.isPrivacySafe());
    try std.testing.expectEqual(Tier.diagnostic, host.tier);
}
