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
        case .noVideoTrack: return "Dosyada video izi bulunamadı."
        case .cannotCreateWriter: return "Çıktı dosyası oluşturulamadı."
        case .ffmpegMissing:
            return "Bu format için ffmpeg gerekli. Terminal'de: brew install ffmpeg"
        case .unsupportedCodec(let name):
            return "Kurulu ffmpeg \(name) kodlayıcısını desteklemiyor."
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
