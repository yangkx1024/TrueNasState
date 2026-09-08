import Foundation
import Testing
@testable import TrueStats

@Suite("alert.list decoding")
struct AlertDecodingTests {
    @Test("prefers the stable uuid over the string id")
    func prefersUUID() throws {
        let alert: TNAlert = try decode(from: """
        {"uuid": "stable-uuid", "id": "other", "level": "WARNING", "formatted": "hi"}
        """)
        #expect(alert.id == "stable-uuid")
    }

    @Test("falls back to id when uuid is absent")
    func fallsBackToID() throws {
        let alert: TNAlert = try decode(from: #"{"id": "only-id", "level": "INFO"}"#)
        #expect(alert.id == "only-id")
    }

    @Test("parses ISO-8601 with and without fractional seconds")
    func parsesISODates() throws {
        let withFraction: TNAlert = try decode(from: """
        {"id": "a", "datetime": "2024-01-01T12:00:00.123Z"}
        """)
        let withoutFraction: TNAlert = try decode(from: """
        {"id": "b", "datetime": "2024-01-01T12:00:00Z"}
        """)
        // Compared with a tolerance: `ISO8601FormatStyle` carries more fractional
        // precision than the literal, so exact float equality would be testing the
        // representation rather than the parse.
        #expect(abs(try #require(withFraction.datetime).timeIntervalSince1970 - 1_704_110_400.123) < 0.001)
        #expect(try #require(withoutFraction.datetime).timeIntervalSince1970 == 1_704_110_400)
    }

    @Test("parses the legacy epoch-milliseconds shapes")
    func parsesLegacyDates() throws {
        let number: TNAlert = try decode(from: #"{"id": "a", "datetime": 1704110400000}"#)
        let wrapped: TNAlert = try decode(from: #"{"id": "b", "datetime": {"$date": 1704110400000}}"#)
        #expect(try #require(number.datetime).timeIntervalSince1970 == 1_704_110_400)
        #expect(try #require(wrapped.datetime).timeIntervalSince1970 == 1_704_110_400)
    }

    @Test("only a true dismissed flag makes an alert inactive")
    func activeFlag() throws {
        #expect(try decode(TNAlert.self, from: #"{"id": "a"}"#).isActive)
        #expect(try decode(TNAlert.self, from: #"{"id": "a", "dismissed": false}"#).isActive)
        #expect(try !decode(TNAlert.self, from: #"{"id": "a", "dismissed": true}"#).isActive)
    }

    @Test("displayText prefers formatted, then text, then a placeholder")
    func displayTextPrecedence() throws {
        let both: TNAlert = try decode(from: #"{"id": "a", "formatted": "F", "text": "T"}"#)
        let textOnly: TNAlert = try decode(from: #"{"id": "b", "text": "T"}"#)
        let neither: TNAlert = try decode(from: #"{"id": "c"}"#)
        #expect(both.displayText == "F")
        #expect(textOnly.displayText == "T")
        #expect(!neither.displayText.isEmpty)
    }
}

@Suite("pool.query decoding")
struct PoolDecodingTests {
    @Test("accepts byte counts sent as JSON strings")
    func numericStrings() throws {
        let pool: Pool = try decode(from: """
        {"id": 1, "name": "tank", "status": "ONLINE", "healthy": true,
         "size": "4000000000000", "allocated": "1000000000000", "free": "3000000000000"}
        """)
        #expect(pool.size == 4_000_000_000_000)
        #expect(pool.allocated == 1_000_000_000_000)
        #expect(pool.usageFraction == 0.25)
        #expect(pool.formattedUsage != nil)
    }

    @Test("substitutes defaults for a missing id and name")
    func defaultsForMissingFields() throws {
        let pool: Pool = try decode(from: "{}")
        #expect(pool.id == 0)
        #expect(pool.name == "unknown")
        #expect(pool.usageFraction == nil)
        #expect(pool.formattedUsage == nil)
    }

    @Test("infers health from status when the healthy flag is absent")
    func healthFallback() throws {
        #expect(try decode(Pool.self, from: #"{"id": 1, "name": "a", "status": "ONLINE"}"#).isHealthy)
        #expect(try !decode(Pool.self, from: #"{"id": 1, "name": "a", "status": "DEGRADED"}"#).isHealthy)
        #expect(try !decode(Pool.self, from: #"{"id": 1, "name": "a"}"#).isHealthy)
    }

    @Test("usageFraction is nil for a zero-sized pool")
    func noFractionForEmptyPool() throws {
        let pool: Pool = try decode(from: #"{"id": 1, "name": "a", "size": 0, "allocated": 0}"#)
        #expect(pool.usageFraction == nil)
    }
}

@Suite("app.query decoding")
struct AppDecodingTests {
    @Test("lifts version and catalog name out of metadata")
    func readsMetadata() throws {
        let app: TNApp = try decode(from: """
        {"id": "plex-inst", "name": "plex-inst", "state": "RUNNING", "upgrade_available": true,
         "metadata": {"name": "plex", "app_version": "1.40.0"}}
        """)
        #expect(app.catalogName == "plex")
        #expect(app.version == "1.40.0")
        #expect(app.isRunning)
        #expect(app.hasUpgrade)
    }

    @Test("maps an unrecognized state to nil rather than failing the row")
    func unknownStateIsNil() throws {
        let app: TNApp = try decode(from: """
        {"id": "a", "name": "a", "state": "SOMETHING_NEW"}
        """)
        #expect(app.state == nil)
        #expect(!app.isRunning)
        #expect(!app.hasUpgrade)
    }

    @Test("decodes with metadata entirely absent")
    func missingMetadata() throws {
        let app: TNApp = try decode(from: #"{"id": "a", "name": "a", "state": "STOPPED"}"#)
        #expect(app.state == .stopped)
        #expect(app.catalogName == nil)
        #expect(app.version == nil)
    }
}

@Suite("system.info decoding")
struct SystemInfoDecodingTests {
    @Test("maps the snake_case keys and exposes the 1m load average")
    func mapsKeys() throws {
        let info: SystemInfo = try decode(from: """
        {"version": "TrueNAS-SCALE-24.10", "hostname": "nas", "uptime_seconds": 90061.0,
         "physmem": 34359738368, "system_product": "Box", "loadavg": [1.5, 1.2, 0.9]}
        """)
        #expect(info.hostname == "nas")
        #expect(info.physicalMemory == 34_359_738_368)
        #expect(info.loadAverage1m == 1.5)
        #expect(info.formattedUptime != nil)
    }

    @Test("formattedUptime is nil for a zero or missing uptime")
    func noUptime() throws {
        #expect(try decode(SystemInfo.self, from: #"{"uptime_seconds": 0}"#).formattedUptime == nil)
        #expect(try decode(SystemInfo.self, from: "{}").formattedUptime == nil)
    }
}

@Suite("core.get_jobs states")
struct JobTests {
    @Test("only success, failed and aborted are terminal", arguments: [
        (TNJobState.success, true), (.failed, true), (.aborted, true),
        (.running, false), (.waiting, false),
    ])
    func terminalStates(state: TNJobState, isTerminal: Bool) {
        #expect(TNJob(id: 1, state: state).isTerminal == isTerminal)
    }

    @Test("an unknown state is not treated as terminal")
    func unknownStateIsNotTerminal() {
        #expect(!TNJob(id: 1, state: nil).isTerminal)
    }
}
