import Foundation

// MARK: - Byte Formatter

/// Tailles et débits. La stdlib fournit l'unité et le séparateur décimal
/// localisés (« 1,4 Mo/s » en français, « 1.4 MB/s » en anglais).
nonisolated enum ByteFormatter {
    static func size(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "—" }
        return bytes.formatted(.byteCount(style: .binary, spellsOutZero: false))
    }

    static func size(_ bytes: Int) -> String {
        size(Int64(bytes))
    }

    static func transferRate(_ bytesPerSecond: Int) -> String {
        "\(size(Int64(max(0, bytesPerSecond))))/s"
    }
}

// MARK: - ETA Formatter

nonisolated enum ETAFormatter {
    static func format(seconds: Int) -> String {
        guard seconds >= 0 else { return "—" }
        guard seconds < 365 * 24 * 3600 else { return "∞" }
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.days, .hours, .minutes, .seconds],
                   width: .narrow,
                   maximumUnitCount: 2)
        )
    }
}

// MARK: - Ratio Formatter

nonisolated enum RatioFormatter {
    static func format(_ ratio: Double) -> String {
        guard ratio >= 0 else { return "—" }
        return ratio.formatted(.number.precision(.fractionLength(2)))
    }
}

// MARK: - Progress Formatter

nonisolated enum ProgressFormatter {
    static func format(_ progress: Double, fractionDigits: Int = 1) -> String {
        let style = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(fractionDigits))
        let text = progress.formatted(style)
        // Rounding up to "100%" would make an unfinished torrent look done.
        guard progress < 1, text == 1.0.formatted(style) else { return text }
        return min(progress, 0.9999).formatted(.percent.precision(.fractionLength(2)))
    }
}
