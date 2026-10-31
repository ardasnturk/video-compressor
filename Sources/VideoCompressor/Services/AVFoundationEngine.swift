import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

/// Hardware-accelerated H.264 / HEVC encoding via AVAssetReader → AVAssetWriter.
struct AVFoundationEngine: EncodingEngine {
    func encode(
        source: URL,
        output: URL,
        settings: CompressionSettings,
        plan: EncodePlan,
        duration: Double,
        progress: @escaping ProgressHandler
    ) async throws {
        let session = try await AVEncodeSession(source: source, output: output, settings: settings, plan: plan)
        try await withTaskCancellationHandler {
            try await session.run(progress: progress)
        } onCancel: {
            session.cancel()
        }
    }
}

private final class AVEncodeSession: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let videoOutput: AVAssetReaderOutput
    private let videoInput: AVAssetWriterInput
    private let audioOutput: AVAssetReaderOutput?
    private let audioInput: AVAssetWriterInput?
    private let duration: Double
    private let output: URL
    private let flag = CancellationFlag()

    init(source: URL, output: URL, settings: CompressionSettings, plan: EncodePlan) async throws {
        self.output = output
        let asset = AVURLAsset(url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let (assetDuration, tracks) = try await asset.load(.duration, .tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw EncodingError.noVideoTrack
        }
        duration = max(assetDuration.seconds, 0.01)

        try? FileManager.default.removeItem(at: output)
        reader = try AVAssetReader(asset: asset)
        writer = try AVAssetWriter(outputURL: output, fileType: Self.fileType(for: settings.format))
        writer.shouldOptimizeForNetworkUse = true

        // MARK: Video — composition applies rotation, scaling and frame-rate in one pass.
        let (naturalSize, transform) = try await videoTrack.load(.naturalSize, .preferredTransform)
        let renderSize = CGSize(width: plan.width, height: plan.height)
        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(transform)

        var layerTransform = transform
            .concatenating(CGAffineTransform(translationX: -displayRect.minX, y: -displayRect.minY))
        layerTransform = layerTransform.concatenating(CGAffineTransform(
            scaleX: renderSize.width / abs(displayRect.width),
            y: renderSize.height / abs(displayRect.height)
        ))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layer.setTransform(layerTransform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: assetDuration)
        instruction.layerInstructions = [layer]

        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(seconds: 1 / plan.frameRate, preferredTimescale: 600_000)
        composition.instructions = [instruction]
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        let compositionOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            ]
        )
        compositionOutput.videoComposition = composition
        compositionOutput.alwaysCopiesSampleData = false
        videoOutput = compositionOutput

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: plan.videoBitrate,
            AVVideoExpectedSourceFrameRateKey: Int(plan.frameRate.rounded()),
            AVVideoMaxKeyFrameIntervalKey: max(1, Int((plan.frameRate * 2).rounded())),
            AVVideoAllowFrameReorderingKey: true,
        ]
        let codecType: AVVideoCodecType
        if settings.codec == .hevc {
            codecType = .hevc
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as String
        } else {
            codecType = .h264
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            compression[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC
        }

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codecType,
            AVVideoWidthKey: plan.width,
            AVVideoHeightKey: plan.height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = false

        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else {
            throw EncodingError.cannotCreateWriter
        }
        reader.add(videoOutput)
        writer.add(videoInput)

        // MARK: Audio — decode to PCM, re-encode as AAC (max stereo).
        if plan.includeAudio, let audioTrack = tracks.first(where: { $0.mediaType == .audio }) {
            let descriptions = try await audioTrack.load(.formatDescriptions)
            var sampleRate = 48_000.0
            var channels = 2
            if let desc = descriptions.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                sampleRate = asbd.mSampleRate >= 48_000 ? 48_000 : 44_100
                channels = asbd.mChannelsPerFrame == 1 ? 1 : 2
            }
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
            let layoutData = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)

            let pcm = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVChannelLayoutKey: layoutData,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            pcm.alwaysCopiesSampleData = false

            let maxBitrate = channels == 1 ? 160_000 : 256_000
            let aac = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVChannelLayoutKey: layoutData,
                AVEncoderBitRateKey: min(max(plan.audioBitrate, 64_000), maxBitrate),
            ])
            aac.expectsMediaDataInRealTime = false

            if reader.canAdd(pcm), writer.canAdd(aac) {
                reader.add(pcm)
                writer.add(aac)
                audioOutput = pcm
                audioInput = aac
            } else {
                audioOutput = nil
                audioInput = nil
            }
        } else {
            audioOutput = nil
            audioInput = nil
        }
    }

    /// Serialises startReading/cancelReading: AVFoundation crashes if they overlap
    /// or if a reader is cancelled before it has started.
    private let readerLock = NSLock()

    func cancel() {
        flag.cancel()
        readerLock.withLock {
            if reader.status == .reading { reader.cancelReading() }
        }
    }

    func run(progress: @escaping ProgressHandler) async throws {
        if flag.isCancelled || Task.isCancelled { throw CancellationError() }
        guard writer.startWriting() else {
            throw writer.error ?? EncodingError.cannotCreateWriter
        }
        let started = readerLock.withLock { flag.isCancelled ? false : reader.startReading() }
        if flag.isCancelled {
            writer.cancelWriting()
            throw CancellationError()
        }
        guard started else {
            writer.cancelWriting()
            throw reader.error ?? EncodingError.failed("Kaynak okunamadı.")
        }
        writer.startSession(atSourceTime: .zero)

        async let videoDone: Void = pump(videoOutput, into: videoInput, label: "video", progress: progress)
        if let audioOutput, let audioInput {
            async let audioDone: Void = pump(audioOutput, into: audioInput, label: "audio", progress: nil)
            _ = await (videoDone, audioDone)
        } else {
            await videoDone
        }

        if flag.isCancelled || Task.isCancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        }
        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw reader.error ?? EncodingError.failed("Okuma başarısız oldu.")
        }
        if writer.status == .failed {
            try? FileManager.default.removeItem(at: output)
            throw writer.error ?? EncodingError.failed("Yazma başarısız oldu.")
        }

        await writer.finishWriting()
        if writer.status != .completed {
            try? FileManager.default.removeItem(at: output)
            throw writer.error ?? EncodingError.failed("Dosya tamamlanamadı.")
        }
        progress(1)
    }

    private func pump(
        _ output: AVAssetReaderOutput,
        into input: AVAssetWriterInput,
        label: String,
        progress: ProgressHandler?
    ) async {
        let queue = DispatchQueue(label: "compressor.\(label)", qos: .userInitiated)
        let duration = self.duration
        let flag = self.flag
        let writer = self.writer
        var lastReported = -1.0

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var finished = false
            func finish() {
                guard !finished else { return }
                finished = true
                input.markAsFinished()
                continuation.resume()
            }

            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData, !finished {
                    if flag.isCancelled || writer.status != .writing {
                        finish(); return
                    }
                    guard let sample = output.copyNextSampleBuffer() else {
                        finish(); return
                    }
                    if let progress {
                        let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                        let p = min(max(t / duration, 0), 0.999)
                        if p - lastReported >= 0.005 {
                            lastReported = p
                            progress(p)
                        }
                    }
                    if !input.append(sample) {
                        finish(); return
                    }
                }
            }
        }
    }

    private static func fileType(for format: ExportFormat) -> AVFileType {
        switch format {
        case .mov: return .mov
        case .m4v: return .m4v
        default: return .mp4
        }
    }
}
