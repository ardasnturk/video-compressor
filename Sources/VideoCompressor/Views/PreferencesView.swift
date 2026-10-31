import SwiftUI

struct PreferencesView: View {
    @Bindable var settings = AppSettings.shared
    private let updater = UpdateController.shared

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            output.tabItem { Label("Output", systemImage: "folder") }
            engine.tabItem { Label("Engine", systemImage: "cpu") }
        }
        .frame(width: 460)
        .padding(.vertical, 6)
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { _ = settings.launchAtLoginRevision; return settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
                Toggle("Show progress in the menu bar", isOn: $settings.showProgressInMenuBar)
            }
            Section("Workflow") {
                Toggle("Start compressing as soon as a video is added", isOn: $settings.autoStart)
                Picker("Videos processed at once", selection: $settings.maxConcurrentJobs) {
                    ForEach(1...4, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                }
            }
            Section("When Finished") {
                Toggle("Show a notification", isOn: $settings.notifyWhenDone)
                Toggle("Play a sound", isOn: $settings.playSound)
                Toggle("Reveal the file in Finder", isOn: $settings.revealWhenDone)
            }
            updates
        }
        .formStyle(.grouped)
    }

    private var updates: some View {
        Section("Updates") {
            LabeledContent("Version", value: UpdateController.currentVersion)
            if updater.isAvailable {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { _ = updater.revision; return updater.automaticallyChecks },
                    set: { updater.automaticallyChecks = $0 }
                ))
                HStack {
                    if let last = updater.lastCheck {
                        Text("Last checked: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            } else {
                Text("Update checks only work in the packaged app.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var output: some View {
        Form {
            Section("Save Location") {
                Picker("Folder", selection: $settings.outputLocation) {
                    ForEach(OutputLocation.allCases) { Text($0.title).tag($0) }
                }
                if settings.outputLocation == .custom {
                    HStack {
                        Group {
                            if settings.customOutputPath.isEmpty {
                                Text("Not selected")
                            } else {
                                Text(verbatim: (settings.customOutputPath as NSString).abbreviatingWithTildeInPath)
                            }
                        }
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…", action: chooseFolder)
                    }
                }
            }
            Section {
                TextField("File name suffix", text: $settings.fileSuffix)
                LabeledContent("Example") {
                    Text("holiday\(settings.fileSuffix).\(settings.compression.format.fileExtension)")
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
            } footer: {
                Text("If a file with the same name exists, a number is appended. The original is never overwritten.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var engine: some View {
        Form {
            Section("Built-in Engine (AVFoundation)") {
                LabeledContent("Formats", value: "MP4, MOV, M4V")
                LabeledContent("Codecs", value: "H.264, HEVC")
                LabeledContent("Acceleration", value: "Apple Silicon / VideoToolbox")
            }
            Section {
                if let url = FFmpegLocator.ffmpegURL {
                    LabeledContent("Status") {
                        Label("Found", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    LabeledContent("Location", value: url.path)
                    LabeledContent("Extra formats", value: "WebM, MKV, GIF · VP9, AV1")
                } else {
                    LabeledContent("Status") {
                        Label("Not found", systemImage: "xmark.circle.fill").foregroundStyle(.orange)
                    }
                    FFmpegHint()
                }
                TextField("Custom ffmpeg folder", text: $settings.ffmpegDirectory, prompt: Text(verbatim: "/opt/homebrew/bin"))
            } header: {
                Text(verbatim: "ffmpeg")
            } footer: {
                Text("ffmpeg is used for WebM, MKV, GIF and AV1/VP9 output, and for source files AVFoundation can't open. Changes take effect after a restart.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.customOutputPath = url.path
        }
    }
}
