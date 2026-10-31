import Foundation

typealias ProgressHandler = @Sendable (Double) -> Void

enum EncodingError: LocalizedError {
    case noVideoTrack
    case cannotCreateWriter
    case ffmpegMissing
    case unsupportedCodec(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return String(localized: "The file has no video track.")
        case .cannotCreateWriter: return String(localized: "The output file couldn't be created.")
        case .ffmpegMissing:
            return String(localized: "This format needs ffmpeg. In Terminal: brew install ffmpeg")
        case .unsupportedCodec(let name):
            return String(localized: "The installed ffmpeg doesn't support the \(name) encoder.")
        case .failed(let message): return message
        }
    }
}

protocol EncodingEngine: Sendable {
    func encode(
        source: URL,
        output: URL,
        settings: CompressionSettings,
        plan: EncodePlan,
        duration: Double,
        progress: @escaping ProgressHandler
    ) async throws
}

/// Thread-safe cancellation flag shared between an engine and its callbacks.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock(); value = true; lock.unlock()
    }
}

/// Picks AVFoundation when it can do the job (fast, hardware, no dependency), ffmpeg otherwise.
enum EngineSelector {
    static func engine(for settings: CompressionSettings, info: VideoInfo) throws -> EncodingEngine {
        let nativeOK = settings.format.isNative && settings.codec.isNative && info.isNativeReadable
        if nativeOK { return AVFoundationEngine() }
        guard FFmpegLocator.isAvailable else { throw EncodingError.ffmpegMissing }
        return FFmpegEngine()
    }

    static func requiresFFmpeg(_ settings: CompressionSettings) -> Bool {
        !(settings.format.isNative && settings.codec.isNative)
    }
}
