import Foundation
import Observation
import ServiceManagement

enum OutputLocation: String, CaseIterable, Identifiable {
    case sameAsSource
    case downloads
    case movies
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sameAsSource: return String(localized: "Same folder as source")
        case .downloads: return String(localized: "Downloads")
        case .movies: return String(localized: "Movies")
        case .custom: return String(localized: "Custom folder…")
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var compression: CompressionSettings {
        didSet { save(compression, forKey: "compression") }
    }

    var outputLocation: OutputLocation {
        didSet { defaults.set(outputLocation.rawValue, forKey: "outputLocation") }
    }

    var customOutputPath: String {
        didSet { defaults.set(customOutputPath, forKey: "customOutputPath") }
    }

    var fileSuffix: String {
        didSet { defaults.set(fileSuffix, forKey: "fileSuffix") }
    }

    var autoStart: Bool {
        didSet { defaults.set(autoStart, forKey: "autoStart") }
    }

    var revealWhenDone: Bool {
        didSet { defaults.set(revealWhenDone, forKey: "revealWhenDone") }
    }

    var notifyWhenDone: Bool {
        didSet { defaults.set(notifyWhenDone, forKey: "notifyWhenDone") }
    }

    var playSound: Bool {
        didSet { defaults.set(playSound, forKey: "playSound") }
    }

    var maxConcurrentJobs: Int {
        didSet { defaults.set(maxConcurrentJobs, forKey: "maxConcurrentJobs") }
    }

    var showProgressInMenuBar: Bool {
        didSet { defaults.set(showProgressInMenuBar, forKey: "showProgressInMenuBar") }
    }

    var ffmpegDirectory: String {
        didSet { defaults.set(ffmpegDirectory, forKey: "ffmpegDirectory") }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch at login failed: \(error.localizedDescription)")
            }
            launchAtLoginRevision += 1
        }
    }

    /// Bumped to make SwiftUI re-read `launchAtLogin`.
    private(set) var launchAtLoginRevision = 0

    private init() {
        defaults.register(defaults: [
            "outputLocation": OutputLocation.sameAsSource.rawValue,
            "fileSuffix": "-compressed",
            "autoStart": true,
            "revealWhenDone": false,
            "notifyWhenDone": true,
            "playSound": true,
            "maxConcurrentJobs": 2,
            "showProgressInMenuBar": true,
        ])

        if let data = defaults.data(forKey: "compression"),
           let stored = try? JSONDecoder().decode(CompressionSettings.self, from: data) {
            compression = stored
        } else {
            compression = CompressionSettings()
        }
        outputLocation = OutputLocation(rawValue: defaults.string(forKey: "outputLocation") ?? "") ?? .sameAsSource
        customOutputPath = defaults.string(forKey: "customOutputPath") ?? ""
        fileSuffix = defaults.string(forKey: "fileSuffix") ?? "-compressed"
        autoStart = defaults.bool(forKey: "autoStart")
        revealWhenDone = defaults.bool(forKey: "revealWhenDone")
        notifyWhenDone = defaults.bool(forKey: "notifyWhenDone")
        playSound = defaults.bool(forKey: "playSound")
        maxConcurrentJobs = min(max(defaults.integer(forKey: "maxConcurrentJobs"), 1), 4)
        showProgressInMenuBar = defaults.bool(forKey: "showProgressInMenuBar")
        ffmpegDirectory = defaults.string(forKey: "ffmpegDirectory") ?? ""
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    /// Folder the output for `source` should be written to.
    func outputDirectory(for source: URL) -> URL {
        let fm = FileManager.default
        switch outputLocation {
        case .sameAsSource:
            let dir = source.deletingLastPathComponent()
            return fm.isWritableFile(atPath: dir.path) ? dir : fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        case .downloads:
            return fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        case .movies:
            return fm.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        case .custom:
            if !customOutputPath.isEmpty { return URL(fileURLWithPath: customOutputPath, isDirectory: true) }
            return source.deletingLastPathComponent()
        }
    }

    var outputLocationDescription: String {
        switch outputLocation {
        case .custom where !customOutputPath.isEmpty:
            return (customOutputPath as NSString).abbreviatingWithTildeInPath
        default:
            return outputLocation.title
        }
    }
}
