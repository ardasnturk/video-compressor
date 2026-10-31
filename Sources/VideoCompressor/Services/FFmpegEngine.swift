import Foundation

/// Encodes WebM, MKV, GIF, AV1/VP9 and anything AVFoundation can't read, using a local ffmpeg.
struct FFmpegEngine: EncodingEngine {
    func encode(
        source: URL,
        output: URL,
        settings: CompressionSettings,
        plan: EncodePlan,
        duration: Double,
        progress: @escaping ProgressHandler
    ) async throws {
        guard let ffmpeg = FFmpegLocator.ffmpegURL else { throw EncodingError.ffmpegMissing }
        let arguments = try Self.arguments(source: source, output: output, settings: settings, plan: plan)
        let runner = FFmpegRunner(executable: ffmpeg, arguments: arguments, duration: duration)

        try await withTaskCancellationHandler {
            try await runner.run(progress: progress)
        } onCancel: {
            runner.cancel()
        }

        if Task.isCancelled {
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        }
    }

    static func arguments(source: URL, output: URL, settings: CompressionSettings, plan: EncodePlan) throws -> [String] {
        var args = ["-hide_banner", "-nostdin", "-y", "-progress", "pipe:1", "-nostats",
                    "-loglevel", "error", "-i", source.path]

        let fps = String(format: "%.3f", plan.frameRate)
        let scale = "scale=\(plan.width):\(plan.height):flags=lanczos"

        if settings.format == .gif {
            let colors: Int
            let dither: String
            switch settings.quality {
            case .smallest: colors = 48; dither = "bayer:bayer_scale=5"
            case .small: colors = 96; dither = "bayer:bayer_scale=4"
            case .balanced: colors = 160; dither = "bayer:bayer_scale=3"
            case .high: colors = 256; dither = "sierra2_4a"
            case .best: colors = 256; dither = "floyd_steinberg"
            }
            let filter = "fps=\(fps),\(scale),split[a][b];" +
                "[a]palettegen=max_colors=\(colors):stats_mode=diff[p];" +
                "[b][p]paletteuse=dither=\(dither):diff_mode=rectangle"
            args += ["-filter_complex", filter, "-loop", "0", "-an", output.path]
            return args
        }

        args += ["-map", "0:v:0"]
        if plan.includeAudio { args += ["-map", "0:a:0?"] }
        args += ["-map_metadata", "0"]

        args += ["-vf", "\(scale),fps=\(fps),format=yuv420p"]

        let bitrate = "\(plan.videoBitrate)"
        let maxrate = "\(Int(Double(plan.videoBitrate) * 1.5))"
        let bufsize = "\(plan.videoBitrate * 2)"
        let gop = "\(max(1, Int((plan.frameRate * 2).rounded())))"
        let appleContainer = [.mp4, .mov, .m4v].contains(settings.format)

        switch settings.codec {
        case .h264:
            if FFmpegLocator.supports("h264_videotoolbox") {
                args += ["-c:v", "h264_videotoolbox", "-b:v", bitrate, "-maxrate", maxrate,
                         "-bufsize", bufsize, "-profile:v", "high"]
            } else if FFmpegLocator.supports("libx264") {
                args += ["-c:v", "libx264", "-preset", "medium", "-b:v", bitrate,
                         "-maxrate", maxrate, "-bufsize", bufsize]
            } else { throw EncodingError.unsupportedCodec("H.264") }
        case .hevc:
            if FFmpegLocator.supports("hevc_videotoolbox") {
                args += ["-c:v", "hevc_videotoolbox", "-b:v", bitrate, "-maxrate", maxrate, "-bufsize", bufsize]
            } else if FFmpegLocator.supports("libx265") {
                args += ["-c:v", "libx265", "-preset", "fast", "-b:v", bitrate, "-x265-params", "log-level=error"]
            } else { throw EncodingError.unsupportedCodec("HEVC") }
            if appleContainer { args += ["-tag:v", "hvc1"] }
        case .vp9:
            guard FFmpegLocator.supports("libvpx-vp9") else { throw EncodingError.unsupportedCodec("VP9") }
            args += ["-c:v", "libvpx-vp9", "-b:v", bitrate, "-maxrate", maxrate, "-bufsize", bufsize,
                     "-deadline", "good", "-cpu-used", "4", "-row-mt", "1", "-tile-columns", "2"]
        case .av1:
            if FFmpegLocator.supports("libsvtav1") {
                args += ["-c:v", "libsvtav1", "-preset", "8", "-b:v", bitrate]
            } else if FFmpegLocator.supports("libaom-av1") {
                args += ["-c:v", "libaom-av1", "-cpu-used", "6", "-row-mt", "1", "-b:v", bitrate]
            } else { throw EncodingError.unsupportedCodec("AV1") }
        }
        args += ["-g", gop]

        if plan.includeAudio {
            if settings.format == .webm {
                args += ["-c:a", "libopus", "-b:a", "\(plan.audioBitrate)"]
            } else {
                let aac = FFmpegLocator.supports("aac_at") ? "aac_at" : "aac"
                args += ["-c:a", aac, "-b:a", "\(plan.audioBitrate)", "-ac", "2"]
            }
        } else {
            args += ["-an"]
        }

        if appleContainer { args += ["-movflags", "+faststart"] }
        args += [output.path]
        return args
    }
}

private final class FFmpegRunner: @unchecked Sendable {
    private let process = Process()
    private let duration: Double
    private let lock = NSLock()
    private var stdoutBuffer = ""
    private var stderrTail = ""
    private var lastReported = -1.0

    init(executable: URL, arguments: [String], duration: Double) {
        process.executableURL = executable
        process.arguments = arguments
        self.duration = max(duration, 0.01)
    }

    func cancel() {
        if process.isRunning { process.terminate() }
    }

    func run(progress: @escaping ProgressHandler) async throws {
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consumeProgress(String(decoding: data, as: UTF8.self), progress: progress)
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            lock.lock()
            stderrTail = String((stderrTail + String(decoding: data, as: UTF8.self)).suffix(2000))
            lock.unlock()
        }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do { try process.run() } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }

        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil

        if process.terminationReason == .uncaughtSignal || Task.isCancelled {
            throw CancellationError()
        }
        guard status == 0 else {
            let tail = lock.withLock { stderrTail }
            let message = tail
                .split(separator: "\n")
                .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                .map(String.init) ?? String(localized: "ffmpeg exited with code \(status).")
            throw EncodingError.failed(message)
        }
        progress(1)
    }

    private func consumeProgress(_ chunk: String, progress: ProgressHandler) {
        lock.lock()
        stdoutBuffer += chunk
        var lines = stdoutBuffer.components(separatedBy: "\n")
        stdoutBuffer = lines.removeLast()
        var latest: Double?
        for line in lines {
            if line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") {
                if let micro = Double(line.split(separator: "=").last ?? "") {
                    latest = micro / 1_000_000
                }
            }
        }
        var report: Double?
        if let latest {
            let p = min(max(latest / duration, 0), 0.999)
            if p - lastReported >= 0.005 {
                lastReported = p
                report = p
            }
        }
        lock.unlock()
        if let report { progress(report) }
    }
}
