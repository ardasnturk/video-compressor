import AppKit
import Foundation
import Observation

enum JobStatus: Equatable {
    case analyzing
    case ready
    case running(progress: Double)
    case finished(output: URL, size: Int64)
    case failed(message: String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .analyzing, .running: return true
        default: return false
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }
}

@MainActor
@Observable
final class CompressionJob: Identifiable {
    let id = UUID()
    let sourceURL: URL
    var settings: CompressionSettings
    var info: VideoInfo?
    var thumbnail: NSImage?
    var status: JobStatus = .analyzing
    var startedAt: Date?
    var finishedAt: Date?
    /// 2 when target-size mode re-encodes to hit the limit.
    var pass = 1

    var task: Task<Void, Never>?

    init(sourceURL: URL, settings: CompressionSettings) {
        self.sourceURL = sourceURL
        self.settings = settings
    }

    var fileName: String { sourceURL.lastPathComponent }

    var plan: EncodePlan? {
        guard let info else { return nil }
        return EncodePlan.make(for: info, settings: settings)
    }

    var progress: Double {
        switch status {
        case .running(let p): return p
        case .finished: return 1
        default: return 0
        }
    }

    var outputSize: Int64? {
        if case .finished(_, let size) = status { return size }
        return nil
    }

    var outputURL: URL? {
        if case .finished(let url, _) = status { return url }
        return nil
    }

    /// Fraction saved, e.g. 0.73 = 73% smaller.
    var savings: Double? {
        guard let out = outputSize, let input = info?.fileSize, input > 0 else { return nil }
        return 1 - Double(out) / Double(input)
    }

    /// Remaining time estimate while running.
    var eta: TimeInterval? {
        guard case .running(let p) = status, p > 0.03, let startedAt else { return nil }
        let elapsed = Date().timeIntervalSince(startedAt)
        return elapsed / p * (1 - p)
    }
}
