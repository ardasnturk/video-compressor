import AppKit
import Foundation

/// Metadata about a source video, gathered by `VideoProbe`.
struct VideoInfo {
    var duration: Double
    /// Display size (rotation already applied).
    var width: Int
    var height: Int
    var frameRate: Double
    var fileSize: Int64
    var videoBitrate: Double
    var hasAudio: Bool
    var codecName: String?
    /// AVFoundation can read this file directly.
    var isNativeReadable: Bool

    var resolutionText: String { "\(width)×\(height)" }
}

/// The concrete numbers an engine uses for one job.
struct EncodePlan {
    var width: Int
    var height: Int
    var frameRate: Double
    var videoBitrate: Int
    var audioBitrate: Int
    var includeAudio: Bool

    var estimatedBytes: Int64? = nil

    static func make(for info: VideoInfo, settings: CompressionSettings) -> EncodePlan {
        let settings = settings.normalized()

        // Resolution: limit the short edge, never upscale, keep dimensions even.
        var width = Double(max(info.width, 2))
        var height = Double(max(info.height, 2))
        let shortEdge = min(width, height)
        if settings.resolution != .original, shortEdge > Double(settings.resolution.rawValue) {
            let scale = Double(settings.resolution.rawValue) / shortEdge
            width *= scale
            height *= scale
        }
        let w = max(2, Int(width.rounded()) & ~1)
        let h = max(2, Int(height.rounded()) & ~1)

        let sourceFps = info.frameRate > 0 ? info.frameRate : 30
        var fps = sourceFps
        if settings.frameRate != .original {
            fps = min(sourceFps, Double(settings.frameRate.rawValue))
        }

        let includeAudio = info.hasAudio && !settings.removeAudio && settings.format.hasAudio
        let duration = max(info.duration, 0.1)

        var audioBitrate = includeAudio ? settings.quality.audioBitrate : 0
        var videoBitrate: Double

        switch settings.sizeMode {
        case .quality:
            let bpp = settings.quality.bitsPerPixel * settings.codec.efficiency
            videoBitrate = Double(w * h) * fps * bpp
            // Don't spend more bits than the source had (scaled to the new pixel count).
            if info.videoBitrate > 0 {
                let pixelRatio = Double(w * h) / Double(max(info.width * info.height, 1))
                let fpsRatio = fps / sourceFps
                let ceiling = info.videoBitrate * pixelRatio * fpsRatio * 0.9
                videoBitrate = min(videoBitrate, max(ceiling, 150_000))
            }
        case .targetSize:
            // Leave ~4% for container overhead.
            let totalBits = settings.targetSizeMB * 1_000_000 * 8 * 0.96
            let totalBitrate = totalBits / duration
            if includeAudio {
                // Small targets get a leaner audio track.
                audioBitrate = min(audioBitrate, max(64_000, Int(totalBitrate * 0.12)))
            }
            videoBitrate = totalBitrate - Double(audioBitrate)
        }

        videoBitrate = max(videoBitrate, 80_000)

        var plan = EncodePlan(
            width: w, height: h, frameRate: fps,
            videoBitrate: Int(videoBitrate), audioBitrate: audioBitrate,
            includeAudio: includeAudio
        )
        if settings.format != .gif {
            plan.estimatedBytes = Int64((videoBitrate + Double(audioBitrate)) * duration / 8 * 1.02)
        }
        return plan
    }
}
