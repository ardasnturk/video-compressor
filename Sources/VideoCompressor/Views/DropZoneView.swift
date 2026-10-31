import SwiftUI
import UniformTypeIdentifiers

/// Drag-and-drop target. Large when the queue is empty, a slim bar otherwise.
struct DropZoneView: View {
    var compact: Bool
    var onFiles: ([URL]) -> Void

    @State private var isTargeted = false
    @State private var hovering = false
    @State private var pulse = false

    var body: some View {
        Button(action: openPanel) {
            Group {
                if compact { compactContent } else { largeContent }
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(isTargeted ? AnyShapeStyle(Theme.accent.opacity(0.18))
                          : AnyShapeStyle(Color.primary.opacity(hovering ? 0.06 : 0.035)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(
                        isTargeted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.18)),
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.2, dash: [6, 4])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            onFiles(urls)
            return !urls.isEmpty
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) { isTargeted = targeted }
        }
        .animation(.snappy(duration: 0.25), value: compact)
    }

    private var largeContent: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 58, height: 58)
                    .scaleEffect(pulse ? 1.08 : 0.96)
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "film.stack.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
            }
            Group {
                if isTargeted { Text("Drop to compress") } else { Text("Drag videos here") }
            }
            .font(.system(size: 13, weight: .semibold))
            Text("or click to choose files · MP4, MOV, MKV, WebM, AVI…")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 22)
    }

    private var compactContent: some View {
        HStack(spacing: 8) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
            Group {
                if isTargeted { Text("Drop to compress") } else { Text("Add or drag videos") }
            }
            .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(verbatim: "⌘O").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func openPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose videos to compress")
        panel.prompt = String(localized: "Add")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .folder]
            + JobQueue.videoExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.level = .floating
        if panel.runModal() == .OK {
            onFiles(panel.urls)
        }
    }
}
