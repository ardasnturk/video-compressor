import SwiftUI

/// Root view of the menu bar popover.
struct MenuContentView: View {
    @Bindable var settings = AppSettings.shared
    var queue = JobQueue.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    DropZoneView(compact: !queue.jobs.isEmpty) { urls in
                        withAnimation(.snappy) { queue.add(urls: urls) }
                    }
                    SettingsPanelView(settings: settings) {
                        queue.applySettingsToPendingJobs()
                    }
                    if !queue.jobs.isEmpty { jobList }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 560)
            .fixedSize(horizontal: false, vertical: true)
            footer
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: 392)
        .background(hiddenShortcuts)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: 30, height: 30)
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .purple.opacity(0.35), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Video Compressor").font(.system(size: 13.5, weight: .bold))
                Text(headerSubtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            IconButton(systemName: "gearshape.fill", help: "Settings (⌘,)") { openSettings() }
            Menu {
                Button("Settings…") { openSettings() }
                Button("Open Output Folder") { openOutputFolder() }
                if UpdateController.shared.isAvailable {
                    Button("Check for Updates…") { UpdateController.shared.checkForUpdates() }
                        .disabled(!UpdateController.shared.canCheckForUpdates)
                }
                Divider()
                Button("Cancel All") { queue.cancelAll() }.disabled(!queue.isBusy)
                Button("Clear Finished") { queue.clearFinished() }.disabled(!queue.hasFinishedJobs)
                Divider()
                Text("Version \(UpdateController.currentVersion)")
                Button("Quit Video Compressor") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(width: 22)
        }
        .padding(.horizontal, 14)
    }

    private var headerSubtitle: String {
        if !queue.runningJobs.isEmpty {
            let count = queue.runningJobs.count
            let p = queue.overallProgress.map(Formatters.percent) ?? ""
            return String(localized: "Compressing \(count) videos") + " · " + p
        }
        if queue.totalSaved > 0 {
            return String(localized: "\(Formatters.bytes(queue.totalSaved)) saved this session")
        }
        return String(localized: "Drag, drop, shrink.")
    }

    // MARK: Jobs

    private var jobList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                FieldLabel(title: "Queue · \(queue.jobs.count)", icon: "list.bullet")
                Spacer()
                if queue.hasFinishedJobs {
                    Button("Clear") { withAnimation(.snappy) { queue.clearFinished() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            LazyVStack(spacing: 5) {
                ForEach(queue.jobs) { job in
                    JobRowView(job: job, queue: queue)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                removal: .opacity))
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Save to", selection: $settings.outputLocation) {
                    ForEach(OutputLocation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Choose Custom Folder…") { chooseCustomFolder() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill").font(.system(size: 10))
                    Text(settings.outputLocationDescription).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .onChange(of: settings.outputLocation) { _, newValue in
                if newValue == .custom, settings.customOutputPath.isEmpty { chooseCustomFolder() }
            }

            Spacer()

            Toggle(isOn: $settings.autoStart) {
                Text("Auto-start").font(.system(size: 10.5))
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            if queue.readyCount > 0, !settings.autoStart {
                Button {
                    queue.startAll()
                } label: {
                    Label("Compress (\(queue.readyCount))", systemImage: "bolt.fill")
                }
                .buttonStyle(GradientButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }

    /// Invisible buttons that give the popover keyboard shortcuts.
    private var hiddenShortcuts: some View {
        ZStack {
            Button(String()) { openFiles() }.keyboardShortcut("o", modifiers: .command)
            Button(String()) { openSettings() }.keyboardShortcut(",", modifiers: .command)
            Button(String()) { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: Actions

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }

    private func openFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.movie, .video, .folder]
        if panel.runModal() == .OK { queue.add(urls: panel.urls) }
    }

    private func openOutputFolder() {
        let url: URL
        switch settings.outputLocation {
        case .sameAsSource:
            url = queue.jobs.first(where: { $0.outputURL != nil })?.outputURL?.deletingLastPathComponent()
                ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        default:
            url = settings.outputDirectory(for: URL(fileURLWithPath: NSHomeDirectory()))
        }
        NSWorkspace.shared.open(url)
    }

    private func chooseCustomFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        if panel.runModal() == .OK, let url = panel.url {
            settings.customOutputPath = url.path
            settings.outputLocation = .custom
        } else if settings.customOutputPath.isEmpty {
            settings.outputLocation = .sameAsSource
        }
    }
}
