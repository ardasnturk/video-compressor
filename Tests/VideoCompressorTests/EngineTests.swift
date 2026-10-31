import XCTest
@testable import VideoCompressor

/// End-to-end encodes of a generated clip. Needs ffmpeg to create the fixture.
final class EngineTests: XCTestCase {
    static var fixture: URL!
    static var workDir: URL!

    override class func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory.appendingPathComponent("vc-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        fixture = workDir.appendingPathComponent("source.mov")
        let p = Process()
        p.executableURL = FFmpegLocator.ffmpegURL
        // 8 s, 1080p60, high bitrate, stereo audio
        p.arguments = ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=60:duration=8",
                       "-f", "lavfi", "-i", "sine=frequency=440:duration=8:sample_rate=48000",
                       "-ac", "2", "-c:v", "libx264", "-preset", "ultrafast", "-b:v", "30M", "-c:a", "aac", "-b:a", "256k",
                       "-y", fixture.path]
        try! p.run(); p.waitUntilExit()
    }

    private func encode(_ settings: CompressionSettings, name: String) async throws -> (URL, Int64, VideoInfo) {
        let info = try await VideoProbe.probe(Self.fixture)
        let plan = EncodePlan.make(for: info, settings: settings)
        let out = Self.workDir.appendingPathComponent(name).appendingPathExtension(settings.format.fileExtension)
        let engine = try EngineSelector.engine(for: settings.normalized(), info: info)
        let start = Date()
        try await engine.encode(source: Self.fixture, output: out, settings: settings.normalized(),
                                plan: plan, duration: info.duration) { _ in }
        let size = (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as! NSNumber).int64Value
        let outInfo = try await VideoProbe.probe(out)
        print("[\(name)] \(type(of: engine)) \(Formatters.bytes(info.fileSize)) → \(Formatters.bytes(size)) "
              + "\(outInfo.resolutionText) \(Int(outInfo.frameRate))fps audio=\(outInfo.hasAudio) "
              + String(format: "%.2fs", Date().timeIntervalSince(start)))
        return (out, size, outInfo)
    }

    func testNativeHEVC() async throws {
        var s = CompressionSettings(); s.format = .mp4; s.codec = .hevc; s.resolution = .p720; s.frameRate = .fps30
        let (_, size, info) = try await encode(s, name: "hevc720")
        XCTAssertEqual(info.width, 1280); XCTAssertEqual(info.height, 720)
        XCTAssertEqual(info.frameRate, 30, accuracy: 1)
        XCTAssertTrue(info.hasAudio)
        XCTAssertLessThan(size, Self.sourceSize / 3)
    }

    func testNativeH264MOVNoAudio() async throws {
        var s = CompressionSettings(); s.format = .mov; s.codec = .h264; s.removeAudio = true
        let (_, _, info) = try await encode(s, name: "h264mov")
        XCTAssertFalse(info.hasAudio)
        XCTAssertEqual(info.width, 1920)
    }

    func testTargetSize() async throws {
        var s = CompressionSettings(); s.format = .mp4; s.codec = .h264; s.sizeMode = .targetSize; s.targetSizeMB = 3
        let (_, size, _) = try await encode(s, name: "target3mb")
        XCTAssertLessThan(Double(size), 3_000_000 * 1.08)
    }

    func testWebM() async throws {
        var s = CompressionSettings(); s.format = .webm; s.codec = .vp9; s.resolution = .p480; s.quality = .small
        let (_, _, info) = try await encode(s, name: "vp9")
        XCTAssertEqual(info.height, 480)
        XCTAssertEqual(info.codecName, "vp9")
    }

    func testAV1MKV() async throws {
        var s = CompressionSettings(); s.format = .mkv; s.codec = .av1; s.resolution = .p360
        let (_, _, info) = try await encode(s, name: "av1")
        XCTAssertEqual(info.codecName, "av1")
    }

    func testGIF() async throws {
        var s = CompressionSettings(); s.format = .gif
        let (_, _, info) = try await encode(s, name: "anim")
        XCTAssertEqual(info.height, 480)
    }

    func testCancellation() async throws {
        var s = CompressionSettings(); s.format = .mp4; s.codec = .hevc; s.quality = .best
        let info = try await VideoProbe.probe(Self.fixture)
        let out = Self.workDir.appendingPathComponent("cancel.mp4")
        let task = Task {
            try await AVFoundationEngine().encode(source: Self.fixture, output: out, settings: s,
                                                  plan: .make(for: info, settings: s), duration: info.duration) { _ in }
        }
        try await Task.sleep(for: .milliseconds(150))
        if ProcessInfo.processInfo.environment["NOCANCEL"] == nil { task.cancel() }
        do { try await task.value; XCTFail("should throw") } catch is CancellationError {} catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testPlanNeverUpscales() {
        let info = VideoInfo(duration: 10, width: 640, height: 360, frameRate: 30, fileSize: 1, videoBitrate: 1_000_000,
                             hasAudio: true, codecName: "h264", isNativeReadable: true)
        var s = CompressionSettings(); s.resolution = .p1080
        let plan = EncodePlan.make(for: info, settings: s)
        XCTAssertEqual(plan.width, 640); XCTAssertEqual(plan.height, 360)
        XCTAssertLessThanOrEqual(Double(plan.videoBitrate), 1_000_000)
    }

    static var sourceSize: Int64 {
        (try! FileManager.default.attributesOfItem(atPath: fixture.path)[.size] as! NSNumber).int64Value
    }
}
