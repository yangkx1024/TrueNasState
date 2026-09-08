import Foundation
import Testing
@testable import TrueStats

@Suite("app.stats parsing")
struct AppLiveStatTests {
    @Test("parses the fields array")
    func parsesFields() throws {
        let stats = try #require(AppLiveStat.parse(jsonValue("""
        {"fields": [{"app_name": "plex", "cpu_usage": 12.6, "memory": 1048576}]}
        """)))
        #expect(stats.count == 1)
        #expect(stats[0].appName == "plex")
        #expect(stats[0].memoryBytes == 1_048_576)
        #expect(stats[0].cpuText == "13%")
    }

    @Test("parses the nested data.fields shape")
    func parsesNestedFields() throws {
        let stats = try #require(AppLiveStat.parse(jsonValue("""
        {"data": {"fields": [{"app_name": "jellyfin", "cpu_usage": 1, "memory": 2}]}}
        """)))
        #expect(stats.map(\.appName) == ["jellyfin"])
    }

    @Test("skips entries missing required keys instead of failing the frame")
    func skipsMalformedEntries() throws {
        let stats = try #require(AppLiveStat.parse(jsonValue("""
        {"fields": [{"app_name": "ok", "cpu_usage": 1, "memory": 2},
                    {"app_name": "no-cpu", "memory": 2},
                    {"cpu_usage": 1, "memory": 2}]}
        """)))
        #expect(stats.map(\.appName) == ["ok"])
    }

    @Test("returns nil when the payload has no fields at all")
    func nilWithoutFields() throws {
        #expect(AppLiveStat.parse(try jsonValue(#"{"collection": "app.stats"}"#)) == nil)
        #expect(AppLiveStat.parse(try jsonValue("7")) == nil)
    }
}
