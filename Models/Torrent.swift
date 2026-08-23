import Foundation
import SwiftUI

// MARK: - Torrent Status

nonisolated enum TorrentStatus: Int, Sendable, CustomStringConvertible {
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

// An unknown raw value from a newer Transmission must not fail the whole
// torrent-get decode, hence the fallback instead of synthesised decoding.
nonisolated extension TorrentStatus: Decodable {
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = TorrentStatus(rawValue: raw) ?? .stopped
    }
}

// MARK: - Torrent Error

nonisolated enum TorrentError: Int, Sendable { case none = 0, trackerWarning, trackerError, localError }

nonisolated extension TorrentError: Decodable {
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = TorrentError(rawValue: raw) ?? .none
    }
}

// MARK: - File Priority

nonisolated enum FilePriority: Int, Sendable {
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

// MARK: - Torrent File

nonisolated struct TorrentFile: Identifiable, Decodable, Sendable {
    var id: String { name }
    let bytesCompleted: Int64
    let length: Int64
    let name: String

    var progress: Double { length > 0 ? Double(bytesCompleted) / Double(length) : 0 }
}

// MARK: - Torrent File Stat

nonisolated struct TorrentFileStat: Decodable, Sendable {
    let bytesCompleted: Int64
    let wanted: Bool
    let priority: Int
}

// MARK: - Peer

nonisolated struct Peer: Identifiable, Sendable {
    var id: String { "\(address):\(port)" }
    let address: String
    let port: Int
    let clientName: String
    let progress: Double
    let rateToClient: Int
    let rateToPeer: Int
}

nonisolated extension Peer: Decodable {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address      = try c.decode(String.self, forKey: .address)
        port         = try c.decode(Int.self,    forKey: .port)
        clientName   = try c.decodeIfPresent(String.self, forKey: .clientName) ?? ""
        progress     = try c.decode(Double.self, forKey: .progress)
        rateToClient = try c.decode(Int.self,    forKey: .rateToClient)
        rateToPeer   = try c.decode(Int.self,    forKey: .rateToPeer)
    }
    enum CodingKeys: String, CodingKey {
        case address, port, clientName, progress, rateToClient, rateToPeer
    }
}

// MARK: - Tracker Stat

nonisolated struct TrackerStat: Identifiable, Sendable {
    let id: Int
    let host: String
    let lastAnnounceResult: String
    let lastAnnounceSucceeded: Bool
    let nextAnnounceTime: Int
    let seederCount: Int
    let leecherCount: Int
}

nonisolated extension TrackerStat: Decodable {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                    = try c.decode(Int.self,    forKey: .id)
        host                  = try c.decode(String.self, forKey: .host)
        lastAnnounceResult    = try c.decodeIfPresent(String.self, forKey: .lastAnnounceResult) ?? ""
        lastAnnounceSucceeded = try c.decodeIfPresent(Bool.self,   forKey: .lastAnnounceSucceeded) ?? false
        nextAnnounceTime      = try c.decodeIfPresent(Int.self,    forKey: .nextAnnounceTime) ?? 0
        seederCount           = try c.decodeIfPresent(Int.self,    forKey: .seederCount) ?? -1
        leecherCount          = try c.decodeIfPresent(Int.self,    forKey: .leecherCount) ?? -1
    }
    enum CodingKeys: String, CodingKey {
        case id, host, lastAnnounceResult, lastAnnounceSucceeded
        case nextAnnounceTime, seederCount, leecherCount
    }
}

// MARK: - Torrent

nonisolated struct Torrent: Identifiable, Sendable {
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
    var recheckProgress: Double
    var sizeWhenDone: Int64
    var leftUntilDone: Int64
    var files: [TorrentFile]?
    var fileStats: [TorrentFileStat]?
    var peers: [Peer]?
    var trackerStats: [TrackerStat]?

    var progress: Double { percentDone }
    var hasError: Bool { error != .none && !errorString.isEmpty }
    var downloadedSize: Int64 { max(0, sizeWhenDone - leftUntilDone) }

    var etaDuration: String {
        guard eta >= 0 else { return "—" }
        return ETAFormatter.format(seconds: eta)
    }

    var addedDateFormatted: String {
        Date(timeIntervalSince1970: TimeInterval(addedDate))
            .formatted(.relative(presentation: .numeric))
    }

    var doneDateFormatted: String? {
        guard doneDate > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(doneDate))
            .formatted(date: .abbreviated, time: .shortened)
    }

    var filesWithStats: [(file: TorrentFile, stat: TorrentFileStat, index: Int)]? {
        guard let files, let fileStats else { return nil }
        return zip(files, fileStats).enumerated().map { (file: $1.0, stat: $1.1, index: $0) }
    }
}

nonisolated extension Torrent: Decodable {
    init(from decoder: any Decoder) throws {
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
        recheckProgress  = try c.decodeIfPresent(Double.self, forKey: .recheckProgress)  ?? 0
        sizeWhenDone     = try c.decodeIfPresent(Int64.self,  forKey: .sizeWhenDone)     ?? 0
        leftUntilDone    = try c.decodeIfPresent(Int64.self,  forKey: .leftUntilDone)    ?? 0
        files            = try c.decodeIfPresent([TorrentFile].self,     forKey: .files)
        fileStats        = try c.decodeIfPresent([TorrentFileStat].self, forKey: .fileStats)
        peers            = try c.decodeIfPresent([Peer].self,            forKey: .peers)
        trackerStats     = try c.decodeIfPresent([TrackerStat].self,     forKey: .trackerStats)
    }
    enum CodingKeys: String, CodingKey {
        case id, name, status, totalSize, downloadedEver, uploadedEver
        case rateDownload, rateUpload, eta, percentDone, uploadRatio
        case peersConnected, peersSendingToUs, peersGettingFromUs
        case addedDate, doneDate, downloadDir, error, errorString, hashString
        case comment, isPrivate, isFinished, recheckProgress
        case sizeWhenDone, leftUntilDone
        case files, fileStats, peers, trackerStats
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

nonisolated enum TorrentFilter: String, CaseIterable, Identifiable, Sendable {
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

nonisolated enum SidebarItem: Hashable, Sendable {
    case filter(TorrentFilter)
    case folder(String)  // downloadDir path
}

// MARK: - Sort

nonisolated enum TorrentSortOrder: String, CaseIterable, Sendable {
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
