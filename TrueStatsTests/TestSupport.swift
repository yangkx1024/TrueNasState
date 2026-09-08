import Foundation
import Testing
@testable import TrueStats

/// Decodes a model straight from a JSON literal, the way the client decodes an
/// RPC result.
func decode<T: Decodable>(_ type: T.Type = T.self, from json: String) throws -> T {
    try JSONDecoder.truenas.decode(T.self, from: Data(json.utf8))
}

/// Builds the untyped `JSONValue` tree that notification payloads arrive as.
func jsonValue(_ json: String) throws -> JSONValue {
    try JSONDecoder.truenas.decode(JSONValue.self, from: Data(json.utf8))
}
