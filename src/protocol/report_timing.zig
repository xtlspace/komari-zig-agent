const std = @import("std");

/// Interval helpers for pacing periodic reports.
pub fn reportIntervalMs(interval: f64) u64 {
    if (interval <= 0) return 1000;
    const ms: u64 = @intFromFloat(interval * 1000);
    return if (ms < 1000) 1000 else ms;
}

pub fn remainingSleepMs(start_ms: i64, interval_ms: u64, now_ms: i64) u64 {
    const elapsed_ms: u64 = @intCast(@max(now_ms - start_ms, 0));
    return if (elapsed_ms >= interval_ms) 0 else interval_ms - elapsed_ms;
}

/// TTL for low-frequency collectors: one sample every ten reports.
pub fn sampleTtlMs(report_interval_ms: u64) u64 {
    return std.math.mul(u64, report_interval_ms, 10) catch std.math.maxInt(u64);
}
