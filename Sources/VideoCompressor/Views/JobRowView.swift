import SwiftUI

struct JobRowView: View {
    let job: CompressionJob
    let queue: JobQueue

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(job.fileName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    trailingBadge
                }
                detail
            }
            actions
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0.04))
        )
        .onHover { hovering = $0 }
        .contextMenu { contextMenu }
        .onDrag {
            // Drag the finished file straight into Slack, Mail, Finder…
            if let url = job.outputURL, let provider = NSItemProvider(contentsOf: url) {
                return provider
            }
            return NSItemProvider()
        }
        .onTapGesture(count: 2) {
            if let url = job.outputURL { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: Thumbnail

    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = job.thumbnail {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Theme.accent.opacity(0.2)
                        Image(systemName: "film").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 58, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            if let duration = job.info?.duration {
                Text(Formatters.duration(duration))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(Capsule().fill(.black.opacity(0.65)))
                    .foregroundStyle(.white)
                    .padding(2)
            }

            if job.status.isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white, Theme.success)
                    .offset(x: 5, y: -28)
            }
        }
        .frame(width: 58, height: 40)
    }

    // MARK: Status

    @ViewBuilder
    private var trailingBadge: some View {
        if let savings = job.savings {
            Text(savings >= 0 ? "−\(Formatters.percent(savings))" : "+\(Formatters.percent(-savings))")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill((savings >= 0 ? Theme.success : Color.orange).opacity(0.18)))
                .foregroundStyle(savings >= 0 ? Theme.success : .orange)
        } else if case .running(let p) = job.status {
            Text(Formatters.percent(p))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch job.status {
        case .analyzing:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Analiz ediliyor…").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        case .ready:
            HStack(spacing: 4) {
                sizeText(job.info?.fileSize)
                if let estimate = job.plan?.estimatedBytes {
                    Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                    Text("~\(Formatters.bytes(estimate))").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Text("· \(job.settings.summary)")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1)
            }
        case .running(let p):
            VStack(alignment: .leading, spacing: 3) {
                ProgressBar(value: p)
                HStack(spacing: 4) {
                    Text(job.pass > 1 ? "Hedef boyut için 2. geçiş" : job.settings.summary)
                        .lineLimit(1)
                    Spacer()
                    if let eta = job.eta { Text(Formatters.eta(eta)).monospacedDigit() }
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            }
        case .finished(let url, let size):
            HStack(spacing: 4) {
                sizeText(job.info?.fileSize).strikethrough(color: .secondary.opacity(0.6))
                Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                Text(Formatters.bytes(size)).font(.system(size: 10.5, weight: .semibold))
                Text("· \(url.pathExtension.uppercased())")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                if let start = job.startedAt, let end = job.finishedAt {
                    Text("· \(String(format: "%.1f", end.timeIntervalSince(start))) sn")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
        case .failed(let message):
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.red)
                .lineLimit(2)
                .help(message)
        case .cancelled:
            Text("İptal edildi").font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    private func sizeText(_ size: Int64?) -> Text {
        Text(size.map(Formatters.bytes) ?? "–").font(.system(size: 10.5)).foregroundColor(.secondary)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 0) {
            switch job.status {
            case .ready:
                if job.task == nil {
                    IconButton(systemName: "play.fill", help: "Başlat", tint: .accentColor) { queue.start(job) }
                } else {
                    IconButton(systemName: "xmark", help: "İptal") { queue.cancel(job) }
                }
            case .analyzing, .running:
                IconButton(systemName: "xmark", help: "İptal") { queue.cancel(job) }
            case .finished(let url, _):
                IconButton(systemName: "magnifyingglass", help: "Finder'da göster") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            case .failed, .cancelled:
                IconButton(systemName: "arrow.clockwise", help: "Yeniden dene") { queue.retry(job) }
            }
            if !job.status.isActive {
                IconButton(systemName: "minus.circle", help: "Listeden kaldır") {
                    withAnimation(.snappy) { queue.remove(job) }
                }
                .opacity(hovering ? 1 : 0)
            }
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let url = job.outputURL {
            Button("Aç") { NSWorkspace.shared.open(url) }
            Button("Finder'da Göster") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Dosyayı Kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
            }
            Divider()
        }
        Button("Orijinali Finder'da Göster") {
            NSWorkspace.shared.activateFileViewerSelecting([job.sourceURL])
        }
        if let info = job.info {
            Divider()
            Text("\(info.resolutionText) · \(String(format: "%.0f", info.frameRate)) fps · \((info.codecName ?? "?").uppercased())")
            Text("Bit hızı: \(Formatters.bitrate(info.videoBitrate))")
        }
        if !job.status.isActive {
            Divider()
            Button("Yeni ayarlarla tekrar sıkıştır") { queue.retry(job) }
            Button("Listeden Kaldır", role: .destructive) { queue.remove(job) }
        }
    }
}
