import Foundation
import Testing
@testable import TrueStats

@Suite("WebSocket URL construction")
struct WebSocketURLTests {
    @Test("upgrades https to wss and points at /api/current")
    func httpsBecomesWSS() throws {
        let url = try TrueNASClient.makeWebSocketURL(from: #require(URL(string: "https://nas.local")))
        #expect(url.absoluteString == "wss://nas.local/api/current")
    }

    @Test("maps http to ws")
    func httpBecomesWS() throws {
        let url = try TrueNASClient.makeWebSocketURL(from: #require(URL(string: "http://nas.local")))
        #expect(url.absoluteString == "ws://nas.local/api/current")
    }

    @Test("keeps an explicit port")
    func preservesPort() throws {
        let url = try TrueNASClient.makeWebSocketURL(from: #require(URL(string: "https://nas.local:8443")))
        #expect(url.absoluteString == "wss://nas.local:8443/api/current")
    }

    @Test("replaces any existing path and drops query and fragment")
    func stripsPathQueryFragment() throws {
        let url = try TrueNASClient.makeWebSocketURL(
            from: #require(URL(string: "https://nas.local/ui/dashboard?a=1#frag")))
        #expect(url.absoluteString == "wss://nas.local/api/current")
    }

    @Test("passes through wss and ws unchanged")
    func acceptsWebSocketSchemes() throws {
        let secure = try TrueNASClient.makeWebSocketURL(from: #require(URL(string: "wss://nas.local")))
        let plain = try TrueNASClient.makeWebSocketURL(from: #require(URL(string: "ws://nas.local")))
        #expect(secure.absoluteString == "wss://nas.local/api/current")
        #expect(plain.absoluteString == "ws://nas.local/api/current")
    }

    @Test("rejects a scheme it can't speak")
    func rejectsUnsupportedScheme() throws {
        #expect(throws: TrueNASClientError.self) {
            _ = try TrueNASClient.makeWebSocketURL(from: #require(URL(string: "ftp://nas.local")))
        }
    }
}

@Suite("endpoint normalization")
@MainActor
struct EndpointNormalizationTests {
    @Test("assumes https for a bare host")
    func bareHostGetsHTTPS() throws {
        let url = try #require(DashboardViewModel.normalizeEndpoint("nas.local"))
        #expect(url.absoluteString == "https://nas.local")
    }

    @Test("trims surrounding whitespace")
    func trimsWhitespace() throws {
        let url = try #require(DashboardViewModel.normalizeEndpoint("  nas.local \n"))
        #expect(url.absoluteString == "https://nas.local")
    }

    @Test("strips trailing path, query and fragment")
    func stripsExtras() throws {
        let url = try #require(DashboardViewModel.normalizeEndpoint("https://nas.local/ui/?x=1#y"))
        #expect(url.absoluteString == "https://nas.local")
    }

    @Test("keeps an explicit port")
    func keepsPort() throws {
        let url = try #require(DashboardViewModel.normalizeEndpoint("nas.local:8443"))
        #expect(url.absoluteString == "https://nas.local:8443")
    }

    @Test("preserves an explicit scheme so the caller can reject it")
    func preservesExplicitScheme() throws {
        let url = try #require(DashboardViewModel.normalizeEndpoint("http://nas.local"))
        #expect(url.scheme == "http")
    }

    @Test("returns nil for input with no host", arguments: ["", "   ", "https://", "/just/a/path"])
    func rejectsHostlessInput(raw: String) {
        #expect(DashboardViewModel.normalizeEndpoint(raw) == nil)
    }
}

@Suite("demo mode matching")
struct DemoModeTests {
    @Test("matches the reserved demo host case-insensitively")
    func matchesDemoHost() throws {
        #expect(DemoMode.matches(endpoint: try #require(URL(string: "https://DEMO.truenas.example")),
                                 apiKey: "demo"))
    }

    @Test("does not match a real host or a different key")
    func rejectsOtherCredentials() throws {
        #expect(!DemoMode.matches(endpoint: try #require(URL(string: "https://nas.local")),
                                  apiKey: "demo"))
        #expect(!DemoMode.matches(endpoint: try #require(URL(string: "https://demo.truenas.example")),
                                  apiKey: "not-demo"))
    }
}

@Suite("JSONValue")
struct JSONValueTests {
    @Test("round-trips a nested payload through encode and decode")
    func roundTrip() throws {
        let source = """
        {"s": "x", "i": 3, "d": 1.5, "b": true, "n": null, "a": [1, "two"], "o": {"k": "v"}}
        """
        let value = try jsonValue(source)
        let reencoded = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: reencoded) == value)
    }

    @Test("accessors coerce between int and double but not from strings")
    func accessors() throws {
        let value = try jsonValue(#"{"i": 3, "d": 1.5, "s": "7"}"#)
        let object = try #require(value.objectValue)
        #expect(object["i"]?.intValue == 3)
        #expect(object["i"]?.doubleValue == 3.0)
        #expect(object["d"]?.intValue == 1)
        #expect(object["s"]?.stringValue == "7")
        #expect(object["s"]?.intValue == nil)
    }

    @Test("array and object accessors return nil for the wrong shape")
    func mismatchedAccessors() throws {
        #expect(try jsonValue("[1,2]").objectValue == nil)
        #expect(try jsonValue(#"{"a": 1}"#).arrayValue == nil)
        #expect(try jsonValue("null").stringValue == nil)
    }
}
