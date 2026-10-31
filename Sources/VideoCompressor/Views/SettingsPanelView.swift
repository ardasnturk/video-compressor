import SwiftUI

/// Format, codec, quality / target size and resolution controls.
struct SettingsPanelView: View {
    @Bindable var settings: AppSettings
    var onChange: () -> Void

    @State private var showAdvanced = false
    private let ffmpegAvailable = FFmpegLocator.isAvailable

    private var compression: Binding<CompressionSettings> {
        Binding(
            get: { settings.compression },
            set: { newValue in
                var value = newValue
                value.normalize()
                settings.compression = value
                onChange()
            }
        )
    }

    var body: some View {
        Card {
            presets
            Divider().opacity(0.5)
            formatPicker
            if settings.compression.format != .gif { codecPicker }
            if settings.compression.format != .gif { sizeModeSection } else { gifQuality }
            advanced
        }
    }

    // MARK: Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: "Presets", icon: "bolt.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(CompressionPreset.all) { preset in
                        Chip(
                            title: preset.title, icon: preset.icon,
                            isSelected: settings.compression == preset.settings.normalized(),
                            compact: true
                        ) {
                            compression.wrappedValue = preset.settings
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: Format & codec

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: "Format", icon: "doc.fill")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 6), spacing: 5) {
                ForEach(ExportFormat.allCases) { format in
                    Chip(
                        title: format.title,
                        isSelected: settings.compression.format == format,
                        badge: !ffmpegAvailable && !format.isNative ? "FF" : nil
                    ) {
                        compression.wrappedValue.format = format
                    }
                    .help(format.subtitle + (!format.isNative && !ffmpegAvailable ? " — " + String(localized: "requires ffmpeg") : ""))
                }
            }
            if !ffmpegAvailable, EngineSelector.requiresFFmpeg(settings.compression) {
                FFmpegHint()
            }
        }
    }

    private var codecPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: "Codec", icon: "cpu")
            HStack(spacing: 5) {
                ForEach(settings.compression.format.supportedCodecs) { codec in
                    Chip(title: codec.shortTitle, isSelected: settings.compression.codec == codec) {
                        compression.wrappedValue.codec = codec
                    }
                    .help(codec.detail)
                }
            }
            Text(settings.compression.codec.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Size

    private var sizeModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                FieldLabel(title: "Compression", icon: "arrow.down.right.and.arrow.up.left")
                Spacer()
                Picker(String(), selection: compression.sizeMode) {
                    ForEach(SizeMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 170)
            }

            switch settings.compression.sizeMode {
            case .quality:
                qualityPills
            case .targetSize:
                targetSize
            }
        }
    }

    private var qualityPills: some View {
        HStack(spacing: 4) {
            ForEach(QualityLevel.allCases) { level in
                Chip(title: level.title, isSelected: settings.compression.quality == level) {
                    compression.wrappedValue.quality = level
                }
            }
        }
    }

    private var targetSize: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Slider(value: logTarget, in: log(1)...log(500))
                    .controlSize(.small)
                HStack(spacing: 2) {
                    TextField(String(), value: compression.targetSizeMB, format: .number.precision(.fractionLength(0...1)))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 42)
                    Text(verbatim: "MB").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            }
            HStack(spacing: 4) {
                ForEach([8.0, 10, 16, 25, 50, 100], id: \.self) { mb in
                    Chip(title: "\(Int(mb))", isSelected: settings.compression.targetSizeMB == mb, compact: true) {
                        compression.wrappedValue.targetSizeMB = mb
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var logTarget: Binding<Double> {
        Binding(
            get: { log(max(1, settings.compression.targetSizeMB)) },
            set: { value in
                let mb = exp(value)
                compression.wrappedValue.targetSizeMB = mb < 10 ? (mb * 2).rounded() / 2 : mb.rounded()
            }
        )
    }

    private var gifQuality: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: "Color quality", icon: "paintpalette.fill")
            qualityPills
        }
    }

    // MARK: Advanced

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { showAdvanced.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                    Text("Resolution, FPS and audio").font(.system(size: 11, weight: .medium))
                    Spacer()
                    if !showAdvanced {
                        Text(advancedSummary).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAdvanced {
                HStack(alignment: .top, spacing: 8) {
                    MenuPicker(
                        label: "Resolution", icon: "rectangle.expand.vertical",
                        options: ResolutionLimit.allCases, selection: compression.resolution,
                        title: { $0.title }
                    )
                    MenuPicker(
                        label: "Frame rate", icon: "speedometer",
                        options: FrameRateLimit.allCases, selection: compression.frameRate,
                        title: { $0.title }
                    )
                }
                if settings.compression.format.hasAudio {
                    Toggle(isOn: compression.removeAudio) {
                        Label("Remove audio", systemImage: "speaker.slash.fill")
                            .font(.system(size: 11.5))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }
        }
    }

    private var advancedSummary: String {
        let c = settings.compression
        var parts = [
            c.resolution == .original ? String(localized: "Full resolution") : c.resolution.shortTitle,
            c.frameRate == .original ? String(localized: "Source FPS") : c.frameRate.title,
        ]
        if settings.compression.removeAudio && settings.compression.format.hasAudio { parts.append(String(localized: "Muted")) }
        return parts.joined(separator: " · ")
    }
}

struct FFmpegHint: View {
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("This format requires ffmpeg").font(.system(size: 10.5))
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew install ffmpeg", forType: .string)
                copied = true
            } label: {
                if copied { Text("Copied") } else { Text(verbatim: "brew install ffmpeg") }
            }
            .font(.system(size: 10, design: .monospaced))
            .buttonStyle(.plain)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.orange.opacity(0.15)))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
    }
}
