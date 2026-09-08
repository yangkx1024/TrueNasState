import os

/// Shared `os.Logger` categories. `print` writes to stdout, which is invisible for a
/// GUI app and still executes in release builds; these show up in Console.app and are
/// compiled out when the level is disabled.
///
/// Interpolations are marked `.public` deliberately: app ids, RPC method names and
/// error descriptions are diagnostic and carry no credentials — the API key never
/// reaches a log site.
enum Log {
    private static let subsystem = "net.yangkx.truestate"

    static let dashboard = Logger(subsystem: subsystem, category: "dashboard")
    static let client = Logger(subsystem: subsystem, category: "client")
    static let credentials = Logger(subsystem: subsystem, category: "credentials")
}
