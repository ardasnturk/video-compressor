import AppKit
import AVFoundation
import Foundation

enum ProbeError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "Bu dosya okunamadı. Desteklenmeyen bir format olabilir (ffmpeg kurulumu daha fazla formatı açar)."
    }
}

/// Reads duration, size, frame rate and a thumbnail from a video file.
enum VideoProbe {
    static func probe(_ url: URL) async throws -> VideoInfo {
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        if let info = try? await probeWithAVFoundation(url, fileSize: fileSize) {
            return info
        }
        if let info = try? await probeWithFFprobe(url, fileSize: fileSize) {
            return info
        }
        throw ProbeError.unreadable
    }

    private static func probeWithAVFoundation(_ url: URL, fileSize: Int64) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        let (duration, tracks) = try await asset.load(.duration, .tracks)
        guard let video = tracks.first(where: { $0.mediaType == .video }) else {
            throw ProbeError.unreadable
        }
        let (size, transform, fps, rate, formats) = try await video.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate, .formatDescriptions
        )
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        let hasAudio = tracks.contains { $0.mediaType == .audio }

        var codecName: String?
        if let desc = formats.first {
            codecName = fourCC(CMFormatDescriptionGetMediaSubType(desc))
        }

        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw ProbeError.unreadable }

        return VideoInfo(
            duration: seconds,
            width: Int(abs(rect.width).rounded()),
            height: Int(abs(rect.height).rounded()),
            frameRate: Double(fps),
            fileSize: fileSize,
            videoBitrate: Double(rate),
            hasAudio: hasAudio,
            codecName: codecName,
            isNativeReadable: true
        )
    }

    private static func probeWithFFprobe(_ url: URL, fileSize: Int64) async throws -> VideoInfo {
        guard let ffprobe = FFmpegLocator.ffprobeURL else { throw ProbeError.unreadable }
        let process = Process()
        process.executableURL = ffprobe
        process.arguments = [
            "-v", "error", "-print_format", "json", "-show_format", "-show_streams", url.path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        struct Output: Decodable {
            struct Stream: Decodable {
                var codec_type: String?
                var codec_name: String?
                var width: Int?
                var height: Int?
                var avg_frame_rate: String?
                var r_frame_rate: String?
                var bit_rate: String?
                var side_data_list: [SideData]?
                var tags: [String: String]?
            }
            struct SideData: Decodable { var rotation: Double? }
            struct Format: Decodable { var duration: String?; var bit_rate: String? }
            var streams: [Stream]
            var format: Format?
        }

        let output = try JSONDecoder().decode(Output.self, from: data)
        guard let video = output.streams.first(where: { $0.codec_type == "video" }),
              var width = video.width, var height = video.height,
              let duration = Double(output.format?.duration ?? ""), duration > 0
        else { throw ProbeError.unreadable }

        let rotation = video.side_data_list?.compactMap(\.rotation).first
            ?? Double(video.tags?["rotate"] ?? "") ?? 0
        if Int(abs(rotation)) % 180 == 90 { swap(&width, &height) }

        let fps = parseRate(video.avg_frame_rate) ?? parseRate(video.r_frame_rate) ?? 30
        let bitrate = Double(video.bit_rate ?? "") ?? Double(output.format?.bit_rate ?? "") ?? 0

        return VideoInfo(
            duration: duration,
            width: width,
            height: height,
            frameRate: fps,
            fileSize: fileSize,
            videoBitrate: bitrate,
            hasAudio: output.streams.contains { $0.codec_type == "audio" },
            codecName: video.codec_name,
            isNativeReadable: false
        )
    }

    static func thumbnail(for url: URL, info: VideoInfo) async -> NSImage? {
        if info.isNativeReadable {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 240, height: 240)
            let time = CMTime(seconds: min(1, info.duration / 3), preferredTimescale: 600)
            if let (image, _) = try? await generator.image(at: time) {
                return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
            return nil
        }
        // ffmpeg fallback for formats AVFoundation can't decode (e.g. WebM, MKV).
        guard let ffmpeg = FFmpegLocator.ffmpegURL else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-\(UUID().uuidString).jpg")
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-v", "error", "-ss", String(format: "%.2f", min(1, info.duration / 3)),
            "-i", url.path, "-frames:v", "1", "-vf", "scale=240:-2", "-y", out.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: out) }
        return NSImage(contentsOf: out)
    }

    private static func parseRate(_ text: String?) -> Double? {
        guard let text else { return nil }
        let parts = text.split(separator: "/").compactMap { Double($0) }
        if parts.count == 2, parts[1] > 0, parts[0] > 0 { return parts[0] / parts[1] }
        if parts.count == 1, parts[0] > 0 { return parts[0] }
        return nil
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let chars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((code >> $0) & 0xFF))) }
        let raw = String(chars).trimmingCharacters(in: .whitespaces)
        switch raw {
        case "avc1": return "h264"
        case "hvc1", "hev1": return "hevc"
        case "ap4h", "apch", "apcn", "apcs", "apco": return "prores"
        default: return raw
        }
    }
}
