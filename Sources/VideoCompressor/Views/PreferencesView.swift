import SwiftUI

struct PreferencesView: View {
    @Bindable var settings = AppSettings.shared

    var body: some View {
        TabView {
            general.tabItem { Label("Genel", systemImage: "gearshape") }
            output.tabItem { Label("Çıktı", systemImage: "folder") }
            engine.tabItem { Label("Motor", systemImage: "cpu") }
        }
        .frame(width: 460)
        .padding(.vertical, 6)
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Girişte otomatik aç", isOn: Binding(
                    get: { _ = settings.launchAtLoginRevision; return settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
                Toggle("Menü çubuğunda ilerlemeyi göster", isOn: $settings.showProgressInMenuBar)
            }
            Section("İş akışı") {
                Toggle("Video eklenince hemen sıkıştır", isOn: $settings.autoStart)
                Picker("Aynı anda işlenecek video", selection: $settings.maxConcurrentJobs) {
                    ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                }
            }
            Section("Bittiğinde") {
                Toggle("Bildirim göster", isOn: $settings.notifyWhenDone)
                Toggle("Ses çal", isOn: $settings.playSound)
                Toggle("Dosyayı Finder'da göster", isOn: $settings.revealWhenDone)
            }
        }
        .formStyle(.grouped)
    }

    private var output: some View {
        Form {
            Section("Kaydetme yeri") {
                Picker("Klasör", selection: $settings.outputLocation) {
                    ForEach(OutputLocation.allCases) { Text($0.title).tag($0) }
                }
                if settings.outputLocation == .custom {
                    HStack {
                        Text(settings.customOutputPath.isEmpty ? "Seçilmedi"
                             : (settings.customOutputPath as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Seç…", action: chooseFolder)
                    }
                }
            }
            Section {
                TextField("Dosya adı eki", text: $settings.fileSuffix)
                LabeledContent("Örnek") {
                    Text("tatil\(settings.fileSuffix).\(settings.compression.format.fileExtension)")
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
            } footer: {
                Text("Aynı isimde dosya varsa sonuna numara eklenir; orijinal dosyanın üzerine asla yazılmaz.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var engine: some View {
        Form {
            Section("Yerleşik motor (AVFoundation)") {
                LabeledContent("Formatlar", value: "MP4, MOV, M4V")
                LabeledContent("Codec'ler", value: "H.264, HEVC")
                LabeledContent("Hızlandırma", value: "Apple Silicon / VideoToolbox")
            }
            Section {
                if let url = FFmpegLocator.ffmpegURL {
                    LabeledContent("Durum") {
                        Label("Bulundu", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    LabeledContent("Konum", value: url.path)
                    LabeledContent("Ek formatlar", value: "WebM, MKV, GIF · VP9, AV1")
                } else {
                    LabeledContent("Durum") {
                        Label("Bulunamadı", systemImage: "xmark.circle.fill").foregroundStyle(.orange)
                    }
                    FFmpegHint()
                }
                TextField("Özel ffmpeg klasörü", text: $settings.ffmpegDirectory, prompt: Text("/opt/homebrew/bin"))
            } header: {
                Text("ffmpeg")
            } footer: {
                Text("ffmpeg; WebM, MKV, GIF ve AV1/VP9 çıktıları ile AVFoundation'ın açamadığı kaynak dosyalar için kullanılır. Değişiklik yeniden başlatınca geçerli olur.")
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
