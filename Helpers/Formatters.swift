import Foundation

// MARK: - Byte Formatter

enum ByteFormatter {
    private static let formatter = ByteCountFormatter()

    static func size(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "—" }
        formatter.allowedUnits = [.useGB, .useMB, .useKB, .useBytes]
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    static func size(_ bytes: Int) -> String {
        size(Int64(bytes))
    }

    static func transferRate(_ bytesPerSecond: Int) -> String {
        guard bytesPerSecond > 0 else { return "0 Ko/s" }
        let kbps = Double(bytesPerSecond) / 1024
        if kbps < 1024 {
            return String(format: "%.1f Ko/s", kbps)
        }
        let mbps = kbps / 1024
        if mbps < 1024 {
            return String(format: "%.2f Mo/s", mbps)
        }
        return String(format: "%.2f Go/s", mbps / 1024)
    }

    static func transferRateShort(_ bytesPerSecond: Int) -> String {
        guard bytesPerSecond > 0 else { return "—" }
        let kbps = Double(bytesPerSecond) / 1024
        if kbps < 1024 {
            return String(format: "%.0f K", kbps)
        }
        let mbps = kbps / 1024
        return String(format: "%.1f M", mbps)
    }
}

// MARK: - ETA Formatter

enum ETAFormatter {
    static func format(seconds: Int) -> String {
        guard seconds >= 0 else { return "—" }
        guard seconds < 365 * 24 * 3600 else { return "∞" }

        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let m = seconds / 60
            let s = seconds % 60
            return s == 0 ? "\(m)min" : "\(m)min \(s)s"
        } else if seconds < 86400 {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)min"
        } else {
            let d = seconds / 86400
            let h = (seconds % 86400) / 3600
            return h == 0 ? "\(d)j" : "\(d)j \(h)h"
        }
    }
}

// MARK: - Ratio Formatter

enum RatioFormatter {
    static func format(_ ratio: Double) -> String {
        guard ratio >= 0 else { return "—" }
        if ratio >= 100 { return "∞" }
        return String(format: "%.2f", ratio)
    }
}

// MARK: - Progress Formatter

enum ProgressFormatter {
    static func format(_ progress: Double) -> String {
        String(format: "%.1f%%", progress * 100)
    }

    static func formatDetailed(downloaded: Int64, total: Int64, progress: Double) -> String {
        let dl = ByteFormatter.size(downloaded)
        let tot = ByteFormatter.size(total)
        let pct = format(progress)
        return "\(dl) sur \(tot) (\(pct))"
    }
}

// MARK: - Date Formatter

extension DateFormatter {
    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

extension Int {
    var dateFromTimestamp: Date {
        Date(timeIntervalSince1970: TimeInterval(self))
    }
}
