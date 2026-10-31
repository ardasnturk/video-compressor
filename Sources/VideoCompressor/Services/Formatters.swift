import Foundation

enum Formatters {
    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: value)
    }

    static func megabytes(_ mb: Double) -> String {
        if mb < 10, mb != mb.rounded() {
            return String(format: "%.1f MB", mb)
        }
        return "\(Int(mb.rounded())) MB"
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "–" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func eta(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(max(1, Int(seconds))) sn kaldı" }
        return "\(Int(seconds / 60)) dk \(Int(seconds) % 60) sn kaldı"
    }

    static func bitrate(_ bps: Double) -> String {
        bps >= 1_000_000 ? String(format: "%.1f Mbps", bps / 1_000_000) : "\(Int(bps / 1000)) kbps"
    }

    static func percent(_ value: Double) -> String {
        "%\(Int((value * 100).rounded()))"
    }
}
