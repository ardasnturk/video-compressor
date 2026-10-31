import Foundation

// MARK: - Format

enum ExportFormat: String, CaseIterable, Codable, Identifiable {
    case mp4, mov, m4v, webm, mkv, gif

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }

    var fileExtension: String { rawValue }

    var subtitle: String {
        switch self {
        case .mp4: return "Her yerde çalışır"
        case .mov: return "Apple / QuickTime"
        case .m4v: return "iTunes / Apple TV"
        case .webm: return "Web için hafif"
        case .mkv: return "Esnek konteyner"
        case .gif: return "Animasyonlu görsel"
        }
    }

    /// Codecs the container can carry, in order of preference.
    var supportedCodecs: [VideoCodec] {
        switch self {
        case .mp4: return [.h264, .hevc, .av1]
        case .mov, .m4v: return [.h264, .hevc]
        case .webm: return [.vp9, .av1]
        case .mkv: return [.h264, .hevc, .av1, .vp9]
        case .gif: return []
        }
    }

    /// Formats AVFoundation can write itself (no ffmpeg needed).
    var isNative: Bool { [.mp4, .mov, .m4v].contains(self) }

    var hasAudio: Bool { self != .gif }
}

// MARK: - Codec

enum VideoCodec: String, CaseIterable, Codable, Identifiable {
    case h264, hevc, av1, vp9

    var id: String { rawValue }

    var title: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC (H.265)"
        case .av1: return "AV1"
        case .vp9: return "VP9"
        }
    }

    var shortTitle: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        case .av1: return "AV1"
        case .vp9: return "VP9"
        }
    }

    var detail: String {
        switch self {
        case .h264: return "En uyumlu, donanım hızlandırmalı"
        case .hevc: return "~%40 daha küçük, donanım hızlandırmalı"
        case .av1: return "En küçük dosya, yavaş kodlama"
        case .vp9: return "Web standardı, iyi sıkıştırma"
        }
    }

    var isNative: Bool { self == .h264 || self == .hevc }

    /// Relative efficiency compared to H.264 (bits needed for equal quality).
    var efficiency: Double {
        switch self {
        case .h264: return 1.0
        case .hevc: return 0.62
        case .vp9: return 0.68
        case .av1: return 0.5
        }
    }
}

// MARK: - Quality

enum QualityLevel: String, CaseIterable, Codable, Identifiable {
    case smallest, small, balanced, high, best

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smallest: return "En küçük"
        case .small: return "Küçük"
        case .balanced: return "Dengeli"
        case .high: return "Yüksek"
        case .best: return "En iyi"
        }
    }

    /// Bits per pixel per frame for H.264. Other codecs are scaled by `VideoCodec.efficiency`.
    var bitsPerPixel: Double {
        switch self {
        case .smallest: return 0.035
        case .small: return 0.055
        case .balanced: return 0.08
        case .high: return 0.12
        case .best: return 0.18
        }
    }

    var audioBitrate: Int {
        switch self {
        case .smallest: return 64_000
        case .small: return 96_000
        case .balanced: return 128_000
        case .high: return 160_000
        case .best: return 192_000
        }
    }
}

// MARK: - Resolution

enum ResolutionLimit: Int, CaseIterable, Codable, Identifiable {
    case original = 0
    case p2160 = 2160
    case p1440 = 1440
    case p1080 = 1080
    case p720 = 720
    case p540 = 540
    case p480 = 480
    case p360 = 360

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .original: return "Orijinal"
        case .p2160: return "4K (2160p)"
        default: return "\(rawValue)p"
        }
    }

    var shortTitle: String {
        switch self {
        case .original: return "Orijinal"
        case .p2160: return "4K"
        default: return "\(rawValue)p"
        }
    }
}

enum FrameRateLimit: Int, CaseIterable, Codable, Identifiable {
    case original = 0
    case fps60 = 60
    case fps30 = 30
    case fps24 = 24
    case fps15 = 15
    case fps10 = 10

    var id: Int { rawValue }

    var title: String { self == .original ? "Orijinal" : "\(rawValue) fps" }
}

// MARK: - Size mode

enum SizeMode: String, Codable, CaseIterable, Identifiable {
    case quality
    case targetSize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quality: return "Kalite"
        case .targetSize: return "Hedef boyut"
        }
    }
}

// MARK: - Settings

struct CompressionSettings: Codable, Equatable {
    var format: ExportFormat = .mp4
    var codec: VideoCodec = .hevc
    var sizeMode: SizeMode = .quality
    var quality: QualityLevel = .balanced
    var targetSizeMB: Double = 25
    var resolution: ResolutionLimit = .original
    var frameRate: FrameRateLimit = .original
    var removeAudio: Bool = false

    /// Keeps the codec valid for the chosen container.
    mutating func normalize() {
        let codecs = format.supportedCodecs
        if !codecs.isEmpty, !codecs.contains(codec) {
            codec = codecs[0]
        }
        if format == .gif {
            if frameRate == .original || frameRate.rawValue > 30 { frameRate = .fps15 }
            if resolution == .original || resolution.rawValue > 720 { resolution = .p480 }
            sizeMode = .quality
        }
        targetSizeMB = max(0.5, targetSizeMB)
    }

    func normalized() -> CompressionSettings {
        var copy = self
        copy.normalize()
        return copy
    }

    var summary: String {
        if format == .gif {
            return "GIF · \(resolution.shortTitle) · \(frameRate.title)"
        }
        var parts = ["\(format.title)", codec.shortTitle]
        switch sizeMode {
        case .quality: parts.append(quality.title)
        case .targetSize: parts.append("≤ \(Formatters.megabytes(targetSizeMB))")
        }
        if resolution != .original { parts.append(resolution.shortTitle) }
        if removeAudio { parts.append("Sessiz") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Presets

struct CompressionPreset: Identifiable {
    let id: String
    let title: String
    let icon: String
    let settings: CompressionSettings

    static let all: [CompressionPreset] = [
        CompressionPreset(
            id: "discord", title: "Discord", icon: "bubble.left.and.bubble.right.fill",
            settings: CompressionSettings(format: .mp4, codec: .h264, sizeMode: .targetSize,
                                          targetSizeMB: 10, resolution: .p1080)
        ),
        CompressionPreset(
            id: "whatsapp", title: "WhatsApp", icon: "phone.bubble.fill",
            settings: CompressionSettings(format: .mp4, codec: .h264, sizeMode: .targetSize,
                                          targetSizeMB: 16, resolution: .p720)
        ),
        CompressionPreset(
            id: "mail", title: "E-posta", icon: "envelope.fill",
            settings: CompressionSettings(format: .mp4, codec: .h264, sizeMode: .targetSize,
                                          targetSizeMB: 24, resolution: .p1080)
        ),
        CompressionPreset(
            id: "web", title: "Web", icon: "globe",
            settings: CompressionSettings(format: .webm, codec: .vp9, quality: .balanced,
                                          resolution: .p1080)
        ),
        CompressionPreset(
            id: "archive", title: "Arşiv", icon: "archivebox.fill",
            settings: CompressionSettings(format: .mp4, codec: .hevc, quality: .high)
        ),
        CompressionPreset(
            id: "gif", title: "GIF", icon: "photo.stack.fill",
            settings: CompressionSettings(format: .gif, codec: .h264, quality: .balanced,
                                          resolution: .p480, frameRate: .fps15)
        ),
    ]
}
