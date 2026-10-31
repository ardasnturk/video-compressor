import Foundation

/// Finds an ffmpeg/ffprobe installation (Homebrew, MacPorts or a user-chosen path).
enum FFmpegLocator {
    private static let searchDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/local/bin",
        "/usr/bin",
    ]

    static var customDirectory: String? {
        let value = UserDefaults.standard.string(forKey: "ffmpegDirectory")
        return (value?.isEmpty ?? true) ? nil : value
    }

    static var ffmpegURL: URL? { locate("ffmpeg") }
    static var ffprobeURL: URL? { locate("ffprobe") }

    static var isAvailable: Bool { ffmpegURL != nil }

    private static func locate(_ binary: String) -> URL? {
        let dirs = [customDirectory].compactMap { $0 } + searchDirectories
        for dir in dirs {
            let path = (dir as NSString).appendingPathComponent(binary)
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Encoder names compiled into the local ffmpeg build, cached after the first call.
    static let availableEncoders: Set<String> = {
        guard let url = ffmpegURL else { return [] }
        let process = Process()
        process.executableURL = url
        process.arguments = ["-hide_banner", "-encoders"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        var names = Set<String>()
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            if cols.count >= 2, cols[0].count == 6 { names.insert(String(cols[1])) }
        }
        return names
    }()

    static func supports(_ encoder: String) -> Bool { availableEncoders.contains(encoder) }
}
