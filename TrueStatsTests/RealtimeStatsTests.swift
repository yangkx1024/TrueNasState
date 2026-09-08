import Foundation
import Testing
@testable import TrueStats

@Suite("reporting.realtime parsing")
struct RealtimeStatsTests {
    @Test("reads the aggregate at fields.cpu.cpu.usage")
    func aggregateCPU() throws {
        let stats = try #require(RealtimeStats(jsonValue: jsonValue("""
        {"fields": {"cpu": {"cpu": {"usage": 12.5, "temp": 40}, "cpu0": {"usage": 99}}}}
        """)))
        #expect(stats.cpuUsagePercent == 12.5)
    }

    @Test("falls back to the flat cpu.usage shape")
    func flatCPUShape() throws {
        let stats = try #require(RealtimeStats(jsonValue: jsonValue("""
        {"fields": {"cpu": {"usage": 7}}}
        """)))
        #expect(stats.cpuUsagePercent == 7)
    }

    @Test("falls back to cpu.average.usage")
    func averageCPUShape() throws {
        let stats = try #require(RealtimeStats(jsonValue: jsonValue("""
        {"fields": {"cpu": {"average": {"usage": 21}}}}
        """)))
        #expect(stats.cpuUsagePercent == 21)
    }

    @Test("averages per-core usage while the aggregate is still null")
    func perCoreFallback() throws {
        let stats = try #require(RealtimeStats(jsonValue: jsonValue("""
        {"fields": {"cpu": {"cpu0": {"usage": 10}, "cpu1": {"usage": 20}, "cpu2": {"usage": 30}}}}
        """)))
        #expect(stats.cpuUsagePercent == 20)
    }

    @Test("derives used memory as total minus available")
    func memoryMath() throws {
        let stats = try #require(RealtimeStats(jsonValue: jsonValue("""
        {"fields": {"memory": {"physical_memory_total": 1000, "physical_memory_available": 400}}}
        """)))
        #expect(stats.memoryTotalBytes == 1000)
        #expect(stats.memoryUsedBytes == 600)
        #expect(stats.memoryFraction == 0.6)
    }

    @Test("clamps negative used memory to zero")
    func memoryNeverNegative() throws {
        let stats = try #require(RealtimeStats(jsonValue: jsonValue("""
        {"fields": {"memory": {"physical_memory_total": 100, "physical_memory_available": 500}}}
        """)))
        #expect(stats.memoryUsedBytes == 0)
    }

    @Test("accepts a payload with no fields wrapper")
    func unwrappedPayload() throws {
        let stats = try #require(RealtimeStats(jsonValue: jsonValue("""
        {"cpu": {"cpu": {"usage": 3}}}
        """)))
        #expect(stats.cpuUsagePercent == 3)
    }

    @Test("returns nil when nothing recognizable decoded")
    func nilWhenEmpty() throws {
        #expect(RealtimeStats(jsonValue: try jsonValue(#"{"fields": {}}"#)) == nil)
        #expect(RealtimeStats(jsonValue: try jsonValue("[]")) == nil)
    }

    @Test("merge overlays only non-nil fields")
    func mergeKeepsKnownFields() {
        var stats = RealtimeStats(cpuUsagePercent: 10, memoryUsedBytes: 5, memoryTotalBytes: 20)
        stats.merge(RealtimeStats(cpuUsagePercent: 40))
        #expect(stats.cpuUsagePercent == 40)
        #expect(stats.memoryUsedBytes == 5)
        #expect(stats.memoryTotalBytes == 20)
    }

    @Test("memoryFraction is nil when the total is zero")
    func noFractionWithoutTotal() {
        #expect(RealtimeStats(memoryUsedBytes: 5, memoryTotalBytes: 0).memoryFraction == nil)
    }
}
