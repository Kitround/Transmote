import Foundation

// MARK: - Server Config

struct ServerConfig: Identifiable, Equatable, @unchecked Sendable {
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

    nonisolated var rpcURL: URL? {
        var c = URLComponents()
        c.scheme = useHTTPS ? "https" : "http"
        c.host = host; c.port = port; c.path = path
        return c.url
    }

    var displayURL: String { "\(useHTTPS ? "https" : "http")://\(host):\(port)\(path)" }

    static let localhost = ServerConfig(name: "Localhost")
}

extension ServerConfig: Codable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(UUID.self,   forKey: .id)
        name     = try c.decode(String.self, forKey: .name)
        host     = try c.decode(String.self, forKey: .host)
        port     = try c.decode(Int.self,    forKey: .port)
        path     = try c.decode(String.self, forKey: .path)
        useHTTPS = try c.decode(Bool.self,   forKey: .useHTTPS)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        password = try c.decodeIfPresent(String.self, forKey: .password)
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,       forKey: .id)
        try c.encode(name,     forKey: .name)
        try c.encode(host,     forKey: .host)
        try c.encode(port,     forKey: .port)
        try c.encode(path,     forKey: .path)
        try c.encode(useHTTPS, forKey: .useHTTPS)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(password, forKey: .password)
    }
    enum CodingKeys: String, CodingKey { case id, name, host, port, path, useHTTPS, username, password }
}

// MARK: - Session Arguments

struct SessionArguments: @unchecked Sendable {
    var downloadDir: String
    var incompleteDir: String?
    var incompleteDirEnabled: Bool?
    var speedLimitDown: Int?
    var speedLimitDownEnabled: Bool?
    var speedLimitUp: Int?
    var speedLimitUpEnabled: Bool?
    var altSpeedEnabled: Bool?
    var altSpeedDown: Int?
    var altSpeedUp: Int?
    var altSpeedTimeEnabled: Bool?
    var altSpeedTimeBegin: Int?
    var altSpeedTimeEnd: Int?
    var altSpeedTimeDayMask: Int?
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
}

extension SessionArguments: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        downloadDir            = try c.decodeIfPresent(String.self, forKey: .downloadDir) ?? ""
        incompleteDir          = try c.decodeIfPresent(String.self, forKey: .incompleteDir)
        incompleteDirEnabled   = try c.decodeIfPresent(Bool.self,   forKey: .incompleteDirEnabled)
        speedLimitDown         = try c.decodeIfPresent(Int.self,    forKey: .speedLimitDown)
        speedLimitDownEnabled  = try c.decodeIfPresent(Bool.self,   forKey: .speedLimitDownEnabled)
        speedLimitUp           = try c.decodeIfPresent(Int.self,    forKey: .speedLimitUp)
        speedLimitUpEnabled    = try c.decodeIfPresent(Bool.self,   forKey: .speedLimitUpEnabled)
        altSpeedEnabled        = try c.decodeIfPresent(Bool.self,   forKey: .altSpeedEnabled)
        altSpeedDown           = try c.decodeIfPresent(Int.self,    forKey: .altSpeedDown)
        altSpeedUp             = try c.decodeIfPresent(Int.self,    forKey: .altSpeedUp)
        altSpeedTimeEnabled    = try c.decodeIfPresent(Bool.self,   forKey: .altSpeedTimeEnabled)
        altSpeedTimeBegin      = try c.decodeIfPresent(Int.self,    forKey: .altSpeedTimeBegin)
        altSpeedTimeEnd        = try c.decodeIfPresent(Int.self,    forKey: .altSpeedTimeEnd)
        altSpeedTimeDayMask    = try c.decodeIfPresent(Int.self,    forKey: .altSpeedTimeDayMask)
        seedRatioLimit         = try c.decodeIfPresent(Double.self, forKey: .seedRatioLimit)
        seedRatioLimited       = try c.decodeIfPresent(Bool.self,   forKey: .seedRatioLimited)
        idleSeedingLimit       = try c.decodeIfPresent(Int.self,    forKey: .idleSeedingLimit)
        idleSeedingLimitEnabled = try c.decodeIfPresent(Bool.self,  forKey: .idleSeedingLimitEnabled)
        peerLimitGlobal        = try c.decodeIfPresent(Int.self,    forKey: .peerLimitGlobal)
        peerLimitPerTorrent    = try c.decodeIfPresent(Int.self,    forKey: .peerLimitPerTorrent)
        peerPort               = try c.decodeIfPresent(Int.self,    forKey: .peerPort)
        peerPortRandomOnStart  = try c.decodeIfPresent(Bool.self,   forKey: .peerPortRandomOnStart)
        portForwardingEnabled  = try c.decodeIfPresent(Bool.self,   forKey: .portForwardingEnabled)
        encryption             = try c.decodeIfPresent(String.self, forKey: .encryption)
        downloadQueueEnabled   = try c.decodeIfPresent(Bool.self,   forKey: .downloadQueueEnabled)
        downloadQueueSize      = try c.decodeIfPresent(Int.self,    forKey: .downloadQueueSize)
        seedQueueEnabled       = try c.decodeIfPresent(Bool.self,   forKey: .seedQueueEnabled)
        seedQueueSize          = try c.decodeIfPresent(Int.self,    forKey: .seedQueueSize)
        version                = try c.decodeIfPresent(String.self, forKey: .version)
        rpcVersion             = try c.decodeIfPresent(Int.self,    forKey: .rpcVersion)
    }
    enum CodingKeys: String, CodingKey {
        case downloadDir = "download-dir"
        case incompleteDir = "incomplete-dir"
        case incompleteDirEnabled = "incomplete-dir-enabled"
        case speedLimitDown = "speed-limit-down"
        case speedLimitDownEnabled = "speed-limit-down-enabled"
        case speedLimitUp = "speed-limit-up"
        case speedLimitUpEnabled = "speed-limit-up-enabled"
        case altSpeedEnabled = "alt-speed-enabled"
        case altSpeedDown = "alt-speed-down"
        case altSpeedUp = "alt-speed-up"
        case altSpeedTimeEnabled = "alt-speed-time-enabled"
        case altSpeedTimeBegin = "alt-speed-time-begin"
        case altSpeedTimeEnd = "alt-speed-time-end"
        case altSpeedTimeDayMask = "alt-speed-time-day"
        case seedRatioLimit = "seedRatioLimit"
        case seedRatioLimited = "seedRatioLimited"
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

struct SessionStats: @unchecked Sendable {
    let activeTorrentCount: Int
    let pausedTorrentCount: Int
    let torrentCount: Int
    let downloadSpeed: Int
    let uploadSpeed: Int
    let cumulativeStats: StatsData
    let currentStats: StatsData

    struct StatsData: @unchecked Sendable {
        let downloadedBytes: Int64
        let uploadedBytes: Int64
        let filesAdded: Int
        let sessionCount: Int
        let secondsActive: Int
    }
}

extension SessionStats: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeTorrentCount = try c.decode(Int.self, forKey: .activeTorrentCount)
        pausedTorrentCount = try c.decode(Int.self, forKey: .pausedTorrentCount)
        torrentCount       = try c.decode(Int.self, forKey: .torrentCount)
        downloadSpeed      = try c.decode(Int.self, forKey: .downloadSpeed)
        uploadSpeed        = try c.decode(Int.self, forKey: .uploadSpeed)
        cumulativeStats    = try c.decode(StatsData.self, forKey: .cumulativeStats)
        currentStats       = try c.decode(StatsData.self, forKey: .currentStats)
    }
    enum CodingKeys: String, CodingKey {
        case activeTorrentCount, pausedTorrentCount, torrentCount, downloadSpeed, uploadSpeed, cumulativeStats, currentStats
    }
}

extension SessionStats.StatsData: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        downloadedBytes = try c.decode(Int64.self, forKey: .downloadedBytes)
        uploadedBytes   = try c.decode(Int64.self, forKey: .uploadedBytes)
        filesAdded      = try c.decode(Int.self,   forKey: .filesAdded)
        sessionCount    = try c.decode(Int.self,   forKey: .sessionCount)
        secondsActive   = try c.decode(Int.self,   forKey: .secondsActive)
    }
    enum CodingKeys: String, CodingKey { case downloadedBytes, uploadedBytes, filesAdded, sessionCount, secondsActive }
}
