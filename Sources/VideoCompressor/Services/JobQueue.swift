import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import UserNotifications

@MainActor
@Observable
final class JobQueue {
    static let shared = JobQueue()

    private(set) var jobs: [CompressionJob] = []
    private let settings = AppSettings.shared

    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "flv", "mpg", "mpeg",
        "3gp", "ts", "mts", "m2ts", "ogv", "gif", "hevc",
    ]

    private init() {}

    // MARK: - Derived state

    var runningJobs: [CompressionJob] { jobs.filter { $0.status.isRunning } }
    var isBusy: Bool { jobs.contains { $0.status.isRunning } }
    var readyCount: Int { jobs.filter { $0.status == .ready }.count }
    var hasFinishedJobs: Bool { jobs.contains { !$0.status.isActive && $0.status != .ready } }

    /// Average progress of running + queued work, for the menu bar.
    var overallProgress: Double? {
        let active = jobs.filter { $0.status.isRunning || ($0.status == .ready && $0.task != nil) }
        guard !active.isEmpty else { return nil }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }

    var totalSaved: Int64 {
        jobs.reduce(0) { sum, job in
            guard let out = job.outputSize, let input = job.info?.fileSize else { return sum }
            return sum + max(0, input - out)
        }
    }

    // MARK: - Adding

    static func isVideo(_ url: URL) -> Bool {
        if videoExtensions.contains(url.pathExtension.lowercased()) { return true }
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.conforms(to: .movie) || type.conforms(to: .video)
        }
        return false
    }

    func add(urls: [URL]) {
        let videos = urls.flatMap(expandFolders).filter(Self.isVideo)
        for url in videos where !jobs.contains(where: { $0.sourceURL == url && $0.status.isActive }) {
            let job = CompressionJob(sourceURL: url, settings: settings.compression.normalized())
            jobs.insert(job, at: 0)
            Task { await analyze(job) }
        }
    }

    private func expandFolders(_ url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return [url]
        }
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return items.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func analyze(_ job: CompressionJob) async {
        do {
            let info = try await VideoProbe.probe(job.sourceURL)
            job.info = info
            job.status = .ready
            job.thumbnail = await VideoProbe.thumbnail(for: job.sourceURL, info: info)
            if settings.autoStart { start(job) }
        } catch {
            job.status = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Settings sync

    /// Jobs that haven't started follow the current settings.
    func applySettingsToPendingJobs() {
        let current = settings.compression.normalized()
        for job in jobs where job.status == .ready && job.task == nil {
            job.settings = current
        }
    }

    // MARK: - Running

    func start(_ job: CompressionJob) {
        guard job.status == .ready || isRetryable(job), job.task == nil else { return }
        if isRetryable(job) { job.status = .ready }
        job.task = Task { [weak self] in
            await self?.waitForSlot(for: job)
            await self?.run(job)
        }
    }

    func startAll() {
        for job in jobs.reversed() where job.status == .ready && job.task == nil { start(job) }
    }

    func retry(_ job: CompressionJob) {
        job.settings = settings.compression.normalized()
        if job.info == nil {
            job.status = .analyzing
            Task { await analyze(job) }
        } else {
            job.status = .ready
            start(job)
        }
    }

    private func isRetryable(_ job: CompressionJob) -> Bool {
        switch job.status {
        case .failed, .cancelled: return job.info != nil
        default: return false
        }
    }

    private func waitForSlot(for job: CompressionJob) async {
        while !Task.isCancelled && runningJobs.count >= settings.maxConcurrentJobs {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func run(_ job: CompressionJob) async {
        defer { job.task = nil }
        guard !Task.isCancelled, let info = job.info else {
            job.status = .cancelled
            return
        }

        let jobSettings = job.settings.normalized()
        var plan = EncodePlan.make(for: info, settings: jobSettings)
        let output = uniqueOutputURL(for: job.sourceURL, format: jobSettings.format)
        let temp = output.deletingLastPathComponent()
            .appendingPathComponent(".\(output.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(6)).\(output.pathExtension)")

        job.startedAt = Date()
        job.status = .running(progress: 0)

        do {
            let engine = try EngineSelector.engine(for: jobSettings, info: info)
            var attempt = 0
            var resultSize: Int64 = 0

            // Target-size mode re-encodes once with a corrected bitrate if the first pass overshoots.
            while true {
                attempt += 1
                job.pass = attempt
                job.startedAt = Date()
                job.status = .running(progress: 0)

                try await engine.encode(
                    source: job.sourceURL, output: temp, settings: jobSettings, plan: plan,
                    duration: info.duration
                ) { [weak job] p in
                    Task { @MainActor in
                        guard let job, job.status.isRunning else { return }
                        job.status = .running(progress: p)
                    }
                }
                try Task.checkCancellation()

                resultSize = fileSize(temp)
                let target = Int64(jobSettings.targetSizeMB * 1_000_000)
                if jobSettings.sizeMode == .targetSize, resultSize > target, attempt < 2,
                   jobSettings.format != .gif {
                    let ratio = Double(target) / Double(resultSize) * 0.93
                    plan.videoBitrate = max(60_000, Int(Double(plan.videoBitrate) * ratio))
                    try? FileManager.default.removeItem(at: temp)
                    continue
                }
                break
            }

            try FileManager.default.moveItem(at: temp, to: output)
            job.finishedAt = Date()
            job.status = .finished(output: output, size: resultSize)
            finished(job, output: output)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: temp)
            job.status = .cancelled
        } catch {
            try? FileManager.default.removeItem(at: temp)
            if Task.isCancelled {
                job.status = .cancelled
            } else {
                job.status = .failed(message: error.localizedDescription)
                notify(title: "Sıkıştırma başarısız", body: "\(job.fileName): \(error.localizedDescription)")
            }
        }
    }

    func cancel(_ job: CompressionJob) {
        job.task?.cancel()
        if job.status == .ready || job.status == .analyzing { job.status = .cancelled }
    }

    func cancelAll() {
        jobs.forEach(cancel)
    }

    func remove(_ job: CompressionJob) {
        cancel(job)
        jobs.removeAll { $0.id == job.id }
    }

    func clearFinished() {
        jobs.removeAll { !$0.status.isActive && $0.status != .ready }
    }

    // MARK: - Output

    private func uniqueOutputURL(for source: URL, format: ExportFormat) -> URL {
        let dir = settings.outputDirectory(for: source)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent + settings.fileSuffix
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(format.fileExtension)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) || candidate == source {
            candidate = dir.appendingPathComponent("\(base) \(index)").appendingPathExtension(format.fileExtension)
            index += 1
        }
        return candidate
    }

    private func fileSize(_ url: URL) -> Int64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return size ?? 0
    }

    private func finished(_ job: CompressionJob, output: URL) {
        if settings.revealWhenDone {
            NSWorkspace.shared.activateFileViewerSelecting([output])
        }
        let othersPending = jobs.contains { $0.id != job.id && ($0.status.isRunning || $0.task != nil) }
        if settings.playSound, !othersPending {
            NSSound(named: "Glass")?.play()
        }
        var body = "\(output.lastPathComponent)"
        if let saved = job.savings, let size = job.outputSize {
            body += " · \(Formatters.bytes(size)) (\(Formatters.percent(max(saved, 0))) daha küçük)"
        }
        notify(title: "Sıkıştırma tamamlandı", body: body)
    }

    // MARK: - Notifications

    static func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard settings.notifyWhenDone, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
