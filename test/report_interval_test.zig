const std = @import("std");
const timing = @import("protocol_report_timing");

test "report interval clamps to at least one second" {
    try std.testing.expectEqual(@as(u64, 1000), timing.reportIntervalMs(0));
    try std.testing.expectEqual(@as(u64, 1000), timing.reportIntervalMs(-1));
    try std.testing.expectEqual(@as(u64, 1000), timing.reportIntervalMs(0.5));
    try std.testing.expectEqual(@as(u64, 1000), timing.reportIntervalMs(1));
    try std.testing.expectEqual(@as(u64, 2500), timing.reportIntervalMs(2.5));
}

test "remaining report sleep uses elapsed work time" {
    try std.testing.expectEqual(@as(u64, 900), timing.remainingSleepMs(1000, 1000, 1100));
    try std.testing.expectEqual(@as(u64, 0), timing.remainingSleepMs(1000, 1000, 2000));
    try std.testing.expectEqual(@as(u64, 0), timing.remainingSleepMs(1000, 1000, 2500));
    try std.testing.expectEqual(@as(u64, 1000), timing.remainingSleepMs(1000, 1000, 900));
}

test "low-frequency collectors sample once every ten reports" {
    try std.testing.expectEqual(@as(u64, 10_000), timing.sampleTtlMs(1000));
    try std.testing.expectEqual(@as(u64, 30_000), timing.sampleTtlMs(3000));
    try std.testing.expectEqual(@as(u64, 50_000), timing.sampleTtlMs(5000));
    try std.testing.expectEqual(@as(u64, 300_000), timing.sampleTtlMs(30_000));
}

test "sample ttl saturates instead of overflowing" {
    try std.testing.expectEqual(std.math.maxInt(u64), timing.sampleTtlMs(std.math.maxInt(u64)));
    try std.testing.expectEqual(std.math.maxInt(u64), timing.sampleTtlMs(std.math.maxInt(u64) / 10 + 1));
}
