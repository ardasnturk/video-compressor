import AppKit
import SwiftUI

@main
struct VideoCompressorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window("Video Compressor Ayarları", id: "settings") {
            PreferencesView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Menu bar icon; shows live progress while compressing.
struct MenuBarLabel: View {
    var queue = JobQueue.shared
    var settings = AppSettings.shared

    var body: some View {
        if settings.showProgressInMenuBar, queue.isBusy, let progress = queue.overallProgress {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.right.and.arrow.up.left.circle.fill")
                Text(Formatters.percent(progress)).monospacedDigit()
            }
        } else {
            Image(systemName: "arrow.down.right.and.arrow.up.left.circle")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon even when launched via `swift run`.
        NSApp.setActivationPolicy(.accessory)
        JobQueue.requestNotificationPermission()
        _ = UpdateController.shared
        showDebugWindowIfRequested()
    }

    private var debugWindow: NSWindow?

    /// `VC_DEBUG_WINDOW=1` shows the popover content in a normal window (UI previews / screenshots).
    /// `VC_DEBUG_FILES=a.mov:b.mp4` queues files on launch.
    private func showDebugWindowIfRequested() {
        let env = ProcessInfo.processInfo.environment
        if let files = env["VC_DEBUG_FILES"] {
            let urls = files.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
            Task { @MainActor in JobQueue.shared.add(urls: urls) }
        }
        guard env["VC_DEBUG_WINDOW"] == "1" else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 392, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.title = "Video Compressor (Önizleme)"
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: MenuContentView().background(.regularMaterial))
        window.makeKeyAndOrderFront(nil)
        debugWindow = window
    }

    /// Finder "Open With…" and dropping files on the app icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in JobQueue.shared.add(urls: urls) }
    }
}
