import Foundation
import SwiftUI

// MARK: - Torrent Status

enum TorrentStatus: Int, Sendable, CustomStringConvertible {
    case stopped = 0, checkWait, check, downloadWait, download, seedWait, seed

    var description: String {
        switch self {
        case .stopped:      return String(localized: "Stopped")
        case .checkWait:    return String(localized: "Waiting for Verification")
        case .check:        return String(localized: "Verifying")
        case .downloadWait: return String(localized: "Waiting for Download")
        case .download:     return String(localized: "Downloading")
        case .seedWait:     return String(localized: "Waiting to Seed")
        case .seed:         return String(localized: "Seeding")
        }
    }

    var isDownloading: Bool { self == .download || self == .downloadWait }
    var isSeeding:     Bool { self == .seed     || self == .seedWait }
    var isStopped:     Bool { self == .stopped }
    var isChecking:    Bool { self == .check    || self == .checkWait }
    var isActive:      Bool { isDownloading || isSeeding }
}

extension TorrentStatus: Codable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(Int.self)
        self = TorrentStatus(rawValue: raw) ?? .stopped
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Torrent Error

enum TorrentError: Int, Sendable { case none = 0, trackerWarning, trackerError, localError }

extension TorrentError: Codable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(Int.self)
        self = TorrentError(rawValue: raw) ?? .none
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - File Priority

enum FilePriority: Int, Sendable {
    case low = -1, normal = 0, high = 1, skip = -2

    var description: String {
        switch self {
        case .low:    return String(localized: "Low")
        case .normal: return String(localized: "Normal")
        case .high:   return String(localized: "High")
        case .skip:   return String(localized: "Skip")
        }
    }
}

extension FilePriority: Codable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(Int.self)
        self = FilePriority(rawValue: raw) ?? .normal
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Torrent File

struct TorrentFile: Identifiable, @unchecked Sendable {
    var id: String { name }
    let bytesCompleted: Int64
    let length: Int64
    let name: String

    var progress: Double { length > 0 ? Double(bytesCompleted) / Double(length) : 0 }
    var isComplete: Bool { bytesCompleted >= length }
}

extension TorrentFile: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bytesCompleted = try c.decode(Int64.self,  forKey: .bytesCompleted)
        length         = try c.decode(Int64.self,  forKey: .length)
        name           = try c.decode(String.self, forKey: .name)
    }
    enum CodingKeys: String, CodingKey { case bytesCompleted, length, name }
}

// MARK: - Torrent File Stat

struct TorrentFileStat: @unchecked Sendable {
    let bytesCompleted: Int64
    let wanted: Bool
    let priority: Int
}

extension TorrentFileStat: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bytesCompleted = try c.decode(Int64.self, forKey: .bytesCompleted)
        wanted         = try c.decode(Bool.self,  forKey: .wanted)
        priority       = try c.decode(Int.self,   forKey: .priority)
    }
    enum CodingKeys: String, CodingKey { case bytesCompleted, wanted, priority }
}

// MARK: - Peer

struct Peer: Identifiable, @unchecked Sendable {
    var id: String { "\(address):\(port)" }
    let address: String
    let port: Int
    let clientName: String
    let progress: Double
    let rateToClient: Int
    let rateToPeer: Int
    let flagStr: String
    let isEncrypted: Bool
    let isUtp: Bool
}

extension Peer: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address     = try c.decode(String.self, forKey: .address)
        port        = try c.decode(Int.self,    forKey: .port)
        clientName  = try c.decodeIfPresent(String.self, forKey: .clientName) ?? ""
        progress    = try c.decode(Double.self, forKey: .progress)
        rateToClient = try c.decode(Int.self,   forKey: .rateToClient)
        rateToPeer  = try c.decode(Int.self,    forKey: .rateToPeer)
        flagStr     = try c.decodeIfPresent(String.self, forKey: .flagStr) ?? ""
        isEncrypted = try c.decodeIfPresent(Bool.self,   forKey: .isEncrypted) ?? false
        isUtp       = try c.decodeIfPresent(Bool.self,   forKey: .isUtp) ?? false
    }
    enum CodingKeys: String, CodingKey {
        case address, port, clientName, progress, rateToClient, rateToPeer, flagStr, isEncrypted, isUtp
    }
}

// MARK: - Tracker Stat

struct TrackerStat: Identifiable, @unchecked Sendable {
    let id: Int
    let host: String
    let tier: Int
    let announce: String
    let lastAnnounceResult: String
    let lastAnnounceSucceeded: Bool
    let lastAnnounceTime: Int
    let nextAnnounceTime: Int
    let seederCount: Int
    let leecherCount: Int
    let downloadCount: Int
    let isBackup: Bool
}

extension TrackerStat: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                    = try c.decode(Int.self,    forKey: .id)
        host                  = try c.decode(String.self, forKey: .host)
        tier                  = try c.decodeIfPresent(Int.self, forKey: .tier) ?? 0
        announce              = try c.decodeIfPresent(String.self, forKey: .announce) ?? ""
        lastAnnounceResult    = try c.decodeIfPresent(String.self, forKey: .lastAnnounceResult) ?? ""
        lastAnnounceSucceeded = try c.decodeIfPresent(Bool.self,   forKey: .lastAnnounceSucceeded) ?? false
        lastAnnounceTime      = try c.decodeIfPresent(Int.self,    forKey: .lastAnnounceTime) ?? 0
        nextAnnounceTime      = try c.decodeIfPresent(Int.self,    forKey: .nextAnnounceTime) ?? 0
        seederCount           = try c.decodeIfPresent(Int.self,    forKey: .seederCount) ?? -1
        leecherCount          = try c.decodeIfPresent(Int.self,    forKey: .leecherCount) ?? -1
        downloadCount         = try c.decodeIfPresent(Int.self,    forKey: .downloadCount) ?? -1
        isBackup              = try c.decodeIfPresent(Bool.self,   forKey: .isBackup) ?? false
    }
    enum CodingKeys: String, CodingKey {
        case id, host, tier, announce, lastAnnounceResult, lastAnnounceSucceeded
        case lastAnnounceTime, nextAnnounceTime, seederCount, leecherCount, downloadCount, isBackup
    }
}

// MARK: - Torrent

struct Torrent: Identifiable, @unchecked Sendable {
    let id: Int
    var name: String
    var status: TorrentStatus
    var totalSize: Int64
    var downloadedEver: Int64
    var uploadedEver: Int64
    var rateDownload: Int
    var rateUpload: Int
    var eta: Int
    var percentDone: Double
    var uploadRatio: Double
    var peersConnected: Int
    var peersSendingToUs: Int
    var peersGettingFromUs: Int
    var addedDate: Int
    var doneDate: Int
    var downloadDir: String
    var error: TorrentError
    var errorString: String
    var hashString: String
    var comment: String?
    var isPrivate: Bool
    var isFinished: Bool
    var queuePosition: Int
    var recheckProgress: Double
    var sizeWhenDone: Int64
    var leftUntilDone: Int64
    var activityDate: Int
    var files: [TorrentFile]?
    var fileStats: [TorrentFileStat]?
    var peers: [Peer]?
    var trackerStats: [TrackerStat]?
    var wanted: [Int]?
    var priorities: [Int]?

    var progress: Double { percentDone }
    var hasError: Bool { error != .none && !errorString.isEmpty }
    var downloadedSize: Int64 { Int64(Double(sizeWhenDone) * percentDone) }

    var etaDuration: String {
        guard eta >= 0 else { return "—" }
        return ETAFormatter.format(seconds: eta)
    }

    var addedDateFormatted: String {
        let date = Date(timeIntervalSince1970: TimeInterval(addedDate))
        return Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    private static let relativeFormatter = RelativeDateTimeFormatter()

    var doneDateFormatted: String? {
        guard doneDate > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(doneDate))
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    var filesWithStats: [(file: TorrentFile, stat: TorrentFileStat, index: Int)]? {
        guard let files, let stats = fileStats else { return nil }
        return zip(zip(files, stats), files.indices).map { (pair, index) in
            (file: pair.0, stat: pair.1, index: index)
        }
    }
}

extension Torrent: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(Int.self,           forKey: .id)
        name             = try c.decode(String.self,        forKey: .name)
        status           = try c.decode(TorrentStatus.self, forKey: .status)
        totalSize        = try c.decodeIfPresent(Int64.self,  forKey: .totalSize)        ?? 0
        downloadedEver   = try c.decodeIfPresent(Int64.self,  forKey: .downloadedEver)   ?? 0
        uploadedEver     = try c.decodeIfPresent(Int64.self,  forKey: .uploadedEver)     ?? 0
        rateDownload     = try c.decodeIfPresent(Int.self,    forKey: .rateDownload)     ?? 0
        rateUpload       = try c.decodeIfPresent(Int.self,    forKey: .rateUpload)       ?? 0
        eta              = try c.decodeIfPresent(Int.self,    forKey: .eta)              ?? -1
        percentDone      = try c.decodeIfPresent(Double.self, forKey: .percentDone)      ?? 0
        uploadRatio      = try c.decodeIfPresent(Double.self, forKey: .uploadRatio)      ?? 0
        peersConnected   = try c.decodeIfPresent(Int.self,    forKey: .peersConnected)   ?? 0
        peersSendingToUs = try c.decodeIfPresent(Int.self,    forKey: .peersSendingToUs) ?? 0
        peersGettingFromUs = try c.decodeIfPresent(Int.self,  forKey: .peersGettingFromUs) ?? 0
        addedDate        = try c.decodeIfPresent(Int.self,    forKey: .addedDate)        ?? 0
        doneDate         = try c.decodeIfPresent(Int.self,    forKey: .doneDate)         ?? 0
        downloadDir      = try c.decodeIfPresent(String.self, forKey: .downloadDir)      ?? ""
        error            = try c.decodeIfPresent(TorrentError.self, forKey: .error)      ?? .none
        errorString      = try c.decodeIfPresent(String.self, forKey: .errorString)      ?? ""
        hashString       = try c.decodeIfPresent(String.self, forKey: .hashString)       ?? ""
        comment          = try c.decodeIfPresent(String.self, forKey: .comment)
        isPrivate        = try c.decodeIfPresent(Bool.self,   forKey: .isPrivate)        ?? false
        isFinished       = try c.decodeIfPresent(Bool.self,   forKey: .isFinished)       ?? false
        queuePosition    = try c.decodeIfPresent(Int.self,    forKey: .queuePosition)    ?? 0
        recheckProgress  = try c.decodeIfPresent(Double.self, forKey: .recheckProgress)  ?? 0
        sizeWhenDone     = try c.decodeIfPresent(Int64.self,  forKey: .sizeWhenDone)     ?? 0
        leftUntilDone    = try c.decodeIfPresent(Int64.self,  forKey: .leftUntilDone)    ?? 0
        activityDate     = try c.decodeIfPresent(Int.self,    forKey: .activityDate)     ?? 0
        files            = try c.decodeIfPresent([TorrentFile].self,     forKey: .files)
        fileStats        = try c.decodeIfPresent([TorrentFileStat].self, forKey: .fileStats)
        peers            = try c.decodeIfPresent([Peer].self,            forKey: .peers)
        trackerStats     = try c.decodeIfPresent([TrackerStat].self,     forKey: .trackerStats)
        wanted           = try c.decodeIfPresent([Int].self,             forKey: .wanted)
        priorities       = try c.decodeIfPresent([Int].self,             forKey: .priorities)
    }
    enum CodingKeys: String, CodingKey {
        case id, name, status, totalSize, downloadedEver, uploadedEver
        case rateDownload, rateUpload, eta, percentDone, uploadRatio
        case peersConnected, peersSendingToUs, peersGettingFromUs
        case addedDate, doneDate, downloadDir, error, errorString, hashString
        case comment, isPrivate, isFinished, queuePosition, recheckProgress
        case sizeWhenDone, leftUntilDone, activityDate
        case files, fileStats, peers, trackerStats, wanted, priorities
    }
}

// MARK: - UI Helpers

extension Torrent {
    /// Couleur représentant l'état du torrent (point de statut, badge).
    var statusColor: Color {
        if hasError { return .red }
        switch status {
        case .download, .downloadWait: return .blue
        case .seed, .seedWait:         return .green
        case .check, .checkWait:       return .orange
        case .stopped:                 return .gray
        }
    }
}

// MARK: - Filter

enum TorrentFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All", downloading = "Downloading", seeding = "Seeding"
    case paused = "Paused", error = "Error", checking = "Checking"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:         return String(localized: "All")
        case .downloading: return String(localized: "Downloading")
        case .seeding:     return String(localized: "Seeding")
        case .paused:      return String(localized: "Paused")
        case .error:       return String(localized: "Error")
        case .checking:    return String(localized: "Checking")
        }
    }

    var systemImage: String {
        switch self {
        case .all:          return "list.bullet"
        case .downloading:  return "arrow.down.circle"
        case .seeding:      return "arrow.up.circle"
        case .paused:       return "pause.circle"
        case .error:        return "exclamationmark.circle"
        case .checking:     return "arrow.triangle.2.circlepath"
        }
    }

    func matches(_ t: Torrent) -> Bool {
        switch self {
        case .all:          return true
        case .downloading:  return t.status.isDownloading
        case .seeding:      return t.status.isSeeding
        case .paused:       return t.status.isStopped
        case .error:        return t.hasError
        case .checking:     return t.status.isChecking
        }
    }
}

// MARK: - Sidebar Selection

enum SidebarItem: Hashable, Sendable {
    case filter(TorrentFilter)
    case folder(String)  // downloadDir path
}

// MARK: - Sort

enum TorrentSortOrder: String, CaseIterable, Sendable {
    case name, addedDate, size, progress, downloadSpeed, uploadSpeed, ratio, eta

    func compare(_ a: Torrent, _ b: Torrent) -> Bool {
        switch self {
        case .name:          return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        case .addedDate:     return a.addedDate > b.addedDate
        case .size:          return a.totalSize > b.totalSize
        case .progress:      return a.percentDone > b.percentDone
        case .downloadSpeed: return a.rateDownload > b.rateDownload
        case .uploadSpeed:   return a.rateUpload > b.rateUpload
        case .ratio:         return a.uploadRatio > b.uploadRatio
        case .eta:           return a.eta < b.eta
        }
    }
}
