//! Test oracle for nearest-rank percentiles, machine privacy, and campaign invariants.

const std = @import("std");
const machine = @import("bench_machine");
const workloads = @import("campaign_workloads");

const testing = std.testing;

/// Nearest-rank percentile calculation: rank = ceil(p * N) (1-based index).
pub fn nearestRankPercentile(values: []const f64, p: f64) f64 {
    std.debug.assert(values.len > 0);
    std.debug.assert(p >= 0.0 and p <= 1.0);

    const n: f64 = @floatFromInt(values.len);
    const rank_f = @ceil(p * n);
    var rank: usize = @intFromFloat(rank_f);
    if (rank == 0) rank = 1;
    if (rank > values.len) rank = values.len;

    return values[rank - 1]; // 0-based indexing into sorted array
}

test "nearest-rank percentile rule matches ceil(p*N)" {
    // Ordered array of 30 values representing trial latencies
    var samples: [30]f64 = undefined;
    for (&samples, 0..) |*s, i| {
        s.* = @as(f64, @floatFromInt(i + 1)) * 10.0; // 10.0, 20.0, ..., 300.0
    }

    // p50: ceil(0.50 * 30) = 15 -> 15th element = 150.0
    try testing.expectEqual(@as(f64, 150.0), nearestRankPercentile(&samples, 0.50));

    // p95: ceil(0.95 * 30) = 29 -> 29th element = 290.0
    try testing.expectEqual(@as(f64, 290.0), nearestRankPercentile(&samples, 0.95));

    // p99: ceil(0.99 * 30) = 30 -> 30th element = 300.0
    try testing.expectEqual(@as(f64, 300.0), nearestRankPercentile(&samples, 0.99));
}

test "machine profile rejects privacy leaks" {
    var profile = machine.MachineProfile{
        .tier = .low_tier,
        .os = .win10_22h2_19045,
        .cpu_cores = 4,
        .cpu_threads = 8,
        .ram_bytes = 8 * 1024 * 1024 * 1024,
        .gpu_name = "Intel Iris Xe Graphics",
        .is_battery_powered = false,
    };
    try testing.expect(profile.isPrivacySafe());

    // If MAC address is leaked into GPU name, it must be rejected
    profile.gpu_name = "Intel Iris 00:1A:2B:3C:4D:5E";
    try testing.expect(!profile.isPrivacySafe());
}

test "workload targets satisfy feasibility latency bounds" {
    const w0 = workloads.WorkloadId.w0_smoke;
    try testing.expect(w0.targetDurationMs() <= 250); // fast startup under 250ms

    const w2 = workloads.WorkloadId.w2_large_editor;
    try testing.expect(w2.targetDurationMs() <= 2000); // 10 MiB editor under 2000ms
}
