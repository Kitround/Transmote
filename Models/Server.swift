import Foundation

// MARK: - Server Config

nonisolated struct ServerConfig: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var path: String
    var useHTTPS: Bool
    var username: String?
    var password: String?

    init(id: UUID = UUID(), name: String = "Mon serveur", host: String = "localhost",
         port: Int = 9091, path: String = "/transmission/rpc",
         useHTTPS: Bool = false, username: String? = nil, password: String? = nil) {
        self.id = id; self.name = name; self.host = host; self.port = port
        self.path = path; self.useHTTPS = useHTTPS
        self.username = username; self.password = password
    }

    var rpcURL: URL? {
        var c = URLComponents()
        c.scheme = useHTTPS ? "https" : "http"
        c.host = host; c.port = port; c.path = path
        return c.url
    }

    var displayURL: String { "\(useHTTPS ? "https" : "http")://\(host):\(port)\(path)" }

    static let localhost = ServerConfig(name: "Localhost")
}

// MARK: - Session Arguments

nonisolated struct SessionArguments: Decodable, Sendable {
    var downloadDir: String?
    var speedLimitDown: Int?
    var speedLimitDownEnabled: Bool?
    var speedLimitUp: Int?
    var speedLimitUpEnabled: Bool?
    var altSpeedEnabled: Bool?
    var altSpeedDown: Int?
    var altSpeedUp: Int?
    var seedRatioLimit: Double?
    var seedRatioLimited: Bool?
    var idleSeedingLimit: Int?
    var idleSeedingLimitEnabled: Bool?
    var peerLimitGlobal: Int?
    var peerLimitPerTorrent: Int?
    var peerPort: Int?
    var peerPortRandomOnStart: Bool?
    var portForwardingEnabled: Bool?
    var encryption: String?
    var downloadQueueEnabled: Bool?
    var downloadQueueSize: Int?
    var seedQueueEnabled: Bool?
    var seedQueueSize: Int?
    var version: String?
    var rpcVersion: Int?

    // Transmission mixes kebab-case and camelCase keys; both are left
    // untouched by the decoder's .convertFromSnakeCase strategy.
    enum CodingKeys: String, CodingKey {
        case downloadDir = "download-dir"
        case speedLimitDown = "speed-limit-down"
        case speedLimitDownEnabled = "speed-limit-down-enabled"
        case speedLimitUp = "speed-limit-up"
        case speedLimitUpEnabled = "speed-limit-up-enabled"
        case altSpeedEnabled = "alt-speed-enabled"
        case altSpeedDown = "alt-speed-down"
        case altSpeedUp = "alt-speed-up"
        case seedRatioLimit, seedRatioLimited
        case idleSeedingLimit = "idle-seeding-limit"
        case idleSeedingLimitEnabled = "idle-seeding-limit-enabled"
        case peerLimitGlobal = "peer-limit-global"
        case peerLimitPerTorrent = "peer-limit-per-torrent"
        case peerPort = "peer-port"
        case peerPortRandomOnStart = "peer-port-random-on-start"
        case portForwardingEnabled = "port-forwarding-enabled"
        case encryption
        case downloadQueueEnabled = "download-queue-enabled"
        case downloadQueueSize = "download-queue-size"
        case seedQueueEnabled = "seed-queue-enabled"
        case seedQueueSize = "seed-queue-size"
        case version
        case rpcVersion = "rpc-version"
    }
}

// MARK: - Session Stats

nonisolated struct SessionStats: Decodable, Sendable {
    let downloadSpeed: Int
    let uploadSpeed: Int
    let currentStats: StatsData

    struct StatsData: Decodable, Sendable {
        let downloadedBytes: Int64
        let uploadedBytes: Int64
    }

    // "current-stats" is hyphenated in the RPC spec — .convertFromSnakeCase
    // does not touch hyphens, so the key must be spelled out.
    enum CodingKeys: String, CodingKey {
        case downloadSpeed, uploadSpeed
        case currentStats = "current-stats"
    }
}
