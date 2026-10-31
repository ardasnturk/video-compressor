import SwiftUI

enum Theme {
    static let accent = LinearGradient(
        colors: [Color(red: 0.47, green: 0.36, blue: 1.0), Color(red: 0.16, green: 0.62, blue: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let success = Color(red: 0.2, green: 0.78, blue: 0.47)
    static let cardRadius: CGFloat = 12
}

/// Rounded translucent card used for each popover section.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
    }
}

/// Small uppercase caption above a control.
struct FieldLabel: View {
    let title: String
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(title.uppercased(with: Locale(identifier: "tr_TR")))
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
        }
        .foregroundStyle(.secondary)
    }
}

/// Selectable pill. Used for formats, quality levels and presets.
struct Chip: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var isSelected: Bool
    var badge: String?
    var compact = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
                    Text(title).font(.system(size: compact ? 11 : 11.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if let subtitle {
                    Text(subtitle).font(.system(size: 8.5)).opacity(0.75).lineLimit(1)
                }
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, subtitle == nil ? 5 : 5)
            .frame(maxWidth: compact ? nil : .infinity)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Theme.accent)
                          : AnyShapeStyle(Color.primary.opacity(hovering ? 0.1 : 0.06)))
            }
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 7, weight: .heavy))
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                        .foregroundStyle(.white)
                        .offset(x: 3, y: -4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

/// Compact menu-style picker that shows the current value.
struct MenuPicker<Value: Hashable & Identifiable>: View {
    let label: String
    let icon: String
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var detail: ((Value) -> String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(title: label, icon: icon)
            Menu {
                ForEach(options) { option in
                    Button {
                        selection = option
                    } label: {
                        if let detail {
                            Text(title(option)) + Text("  ") + Text(detail(option)).foregroundColor(.secondary)
                        } else {
                            Text(title(option))
                        }
                        if option == selection { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text(title(selection)).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Thin gradient progress bar.
struct ProgressBar: View {
    var value: Double
    var tint: AnyShapeStyle = AnyShapeStyle(Theme.accent)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(tint)
                    .frame(width: max(4, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 5)
        .animation(.linear(duration: 0.25), value: value)
    }
}

/// Icon-only button with a hover highlight.
struct IconButton: View {
    let systemName: String
    var help: String
    var tint: Color = .secondary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? .primary : tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// Primary call-to-action button with the accent gradient.
struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
