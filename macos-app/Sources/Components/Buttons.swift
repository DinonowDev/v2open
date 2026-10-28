import SwiftUI

struct QuietPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SheetActionButton: View {
    var title: String
    var compact = false
    var primary = false
    var quiet = false
    var danger = false
    var icon: String? = nil
    var action: () -> Void

    private var height: CGFloat { compact ? 38 : (quiet ? 40 : 46) }
    private var radius: CGFloat { compact ? 14 : 16 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: compact ? 15 : 14, weight: .bold))
                }
                Mix(
                    text: title,
                    size: compact ? 16 : 15,
                    weight: primary || quiet ? .bold : .semibold,
                    color: labelColor
                )
            }
            .foregroundStyle(labelColor)
            .frame(maxWidth: compact ? nil : .infinity)
            .frame(minWidth: compact ? 38 : nil)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(height: height)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: primary || quiet ? 0 : 1)
            )
            .shadow(color: primary ? C.cyan.opacity(0.28) : .clear, radius: primary ? 10 : 0, y: primary ? 3 : 0)
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(title)
    }

    private var labelColor: Color {
        if primary { return Color(red: 0.04, green: 0.08, blue: 0.14) }
        if danger { return Color(red: 1, green: 0.36, blue: 0.45) }
        if quiet { return C.muted }
        return .white
    }

    @ViewBuilder private var fill: some View {
        if primary {
            LinearGradient(colors: [C.cyan, C.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if quiet {
            Color.clear
        } else if danger {
            Color(red: 1, green: 0.36, blue: 0.45).opacity(0.14)
        } else {
            C.cardElevated
        }
    }

    private var border: Color {
        if quiet { return .clear }
        if danger { return Color(red: 1, green: 0.36, blue: 0.45).opacity(0.35) }
        return C.line
    }
}

struct AppToastView: View {
    var item: AppToastItem

    private var accent: Color {
        switch item.tone {
        case .success: return C.green
        case .warning: return Color(red: 1, green: 0.62, blue: 0.28)
        case .error: return Color(red: 1, green: 0.36, blue: 0.45)
        case .info: return C.cyan
        }
    }

    private var icon: String {
        switch item.tone {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
            Mix(text: item.text, size: 14, weight: .semibold, color: .white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.07, green: 0.09, blue: 0.15).opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
    }
}
