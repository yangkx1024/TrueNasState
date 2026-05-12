import Foundation

enum AppState: String, Decodable, Equatable {
    case crashed = "CRASHED"
    case deploying = "DEPLOYING"
    case running = "RUNNING"
    case stopped = "STOPPED"
    case stopping = "STOPPING"
}

struct TNApp: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let version: String?
    let state: AppState?
    let upgradeAvailable: Bool?
    /// Upstream catalog app name (e.g. "plex"), used to look up icons in `catalog.apps`.
    /// May differ from `name`/`id`, which are the user-chosen instance slug.
    let catalogName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, state, metadata
        case upgradeAvailable = "upgrade_available"
    }

    private enum MetadataKeys: String, CodingKey {
        case name
        case appVersion = "app_version"
    }

    init(id: String, name: String, version: String?, state: AppState?,
         upgradeAvailable: Bool?, catalogName: String?) {
        self.id = id
        self.name = name
        self.version = version
        self.state = state
        self.upgradeAvailable = upgradeAvailable
        self.catalogName = catalogName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.state = (try? c.decode(String.self, forKey: .state)).flatMap(AppState.init(rawValue:))
        self.upgradeAvailable = try? c.decode(Bool.self, forKey: .upgradeAvailable)
        let metadata = try? c.nestedContainer(keyedBy: MetadataKeys.self, forKey: .metadata)
        self.catalogName = try? metadata?.decode(String.self, forKey: .name)
        self.version = try? metadata?.decode(String.self, forKey: .appVersion)
    }

    var isRunning: Bool { state == .running }
    var hasUpgrade: Bool { upgradeAvailable == true }
}
