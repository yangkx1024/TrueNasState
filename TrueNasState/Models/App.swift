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
    let state: AppState?
    let upgradeAvailable: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, state
        case upgradeAvailable = "upgrade_available"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.state = (try? c.decode(String.self, forKey: .state)).flatMap(AppState.init(rawValue:))
        self.upgradeAvailable = try? c.decode(Bool.self, forKey: .upgradeAvailable)
    }

    var isRunning: Bool { state == .running }
    var hasUpgrade: Bool { upgradeAvailable == true }
}
