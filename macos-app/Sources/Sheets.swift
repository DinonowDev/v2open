import SwiftUI

struct SheetBackdrop<Content: View>: View {
    var onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack {
                Spacer(minLength: 12)
                content()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .transition(.opacity)
    }
}

struct SheetCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 14)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(C.glassy ? Color(red: 0.06, green: 0.09, blue: 0.15).opacity(0.94) : Color(red: 0.08, green: 0.12, blue: 0.19))
                if C.glassy {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.45)
                }
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.24), C.line],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.42), radius: 24, y: 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct SheetHeader: View {
    var title: String
    var subtitle: String? = nil
    var back: (() -> Void)? = nil
    var close: (() -> Void)? = nil
    var closeLabel: String = "Cancel"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(C.cyan)
                        .frame(width: 32, height: 32)
                        .background(C.cyan.opacity(0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(QuietPressStyle())
                .accessibilityLabel("Back")
            }
            VStack(alignment: .leading, spacing: 3) {
                Mix(text: title, size: 20, weight: .bold)
                if let subtitle, !subtitle.isEmpty {
                    Mix(text: subtitle, size: 13, color: C.muted)
                }
            }
            Spacer(minLength: 8)
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(C.muted)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(QuietPressStyle())
                .accessibilityLabel(closeLabel)
            }
        }
        .padding(.bottom, 14)
    }
}

struct AddQuickTile: View {
    var icon: String
    var title: String
    var hint: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.16))
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Mix(text: title, size: 14, weight: .semibold)
                        .lineLimit(1)
                    Mix(text: hint, size: 11, color: C.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 114, alignment: .topLeading)
            .background(C.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

struct AddActionRow: View {
    var icon: String
    var title: String
    var hint: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.16))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Mix(text: title, size: 15, weight: .semibold)
                        .lineLimit(1)
                    Mix(text: hint, size: 12, color: C.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(C.muted.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

struct ScanCorners: View {
    var body: some View {
        let arm: CGFloat = 22
        VStack {
            HStack {
                corner(arm: arm)
                Spacer()
                corner(arm: arm).rotationEffect(.degrees(90))
            }
            Spacer()
            HStack {
                corner(arm: arm).rotationEffect(.degrees(270))
                Spacer()
                corner(arm: arm).rotationEffect(.degrees(180))
            }
        }
        .padding(16)
        .allowsHitTesting(false)
    }

    private func corner(arm: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: arm))
            path.addLine(to: CGPoint(x: 0, y: 6))
            path.addQuadCurve(to: CGPoint(x: 6, y: 0), control: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: arm, y: 0))
        }
        .stroke(C.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        .frame(width: arm, height: arm)
        .shadow(color: C.cyan.opacity(0.45), radius: 6)
    }
}

struct ProtocolChipPicker: View {
    var value: String
    var onSelect: (String) -> Void

    private let items: [(id: String, label: String)] = [
        ("vless", "VLESS"),
        ("vmess", "VMess"),
        ("trojan", "Trojan"),
        ("shadowsocks", "SS"),
        ("shadowsocksr", "SSR"),
        ("hysteria2", "Hy2"),
        ("wireguard", "WG"),
        ("ssh", "SSH"),
        ("socks", "SOCKS"),
        ("http", "HTTP"),
        ("dnstt", "DNSTT"),
        ("masterdns", "MDNS"),
        ("ping", "Ping")
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.id) { item in
                let on = item.id == value
                Button {
                    onSelect(item.id)
                } label: {
                    Text(item.label)
                        .font(.custom("Inter", size: 12).weight(.bold))
                        .foregroundStyle(on ? Color(red: 0.04, green: 0.08, blue: 0.14) : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(on ? AnyShapeStyle(LinearGradient(colors: [C.cyan, C.accent], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(C.fieldFill))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(on ? Color.clear : C.line, lineWidth: 1)
                        )
                }
                .buttonStyle(QuietPressStyle())
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(on ? .isSelected : AccessibilityTraits())
            }
        }
    }
}

struct EditorSection<Content: View>: View {
    var title: String
    var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(text: title)
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(14)
            }
        }
    }
}

struct SettingsSectionLabel: View {
    var text: String
    var body: some View {
        Mix(text: text, size: 12, weight: .semibold, color: C.muted)
            .padding(.leading, 4)
    }
}

struct SettingsCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(C.cardElevated)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(C.glassy ? 0.08 : 0.05), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), C.line],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SettingsDivider: View {
    var inset: CGFloat = 14
    var body: some View {
        Rectangle()
            .fill(C.line)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

struct SettingsNavRow: View {
    var icon: String
    var title: String
    var value: String = ""
    var tint: Color = C.cyan
    var chevron = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.16))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 32, height: 32)
                Mix(text: title, size: 15, weight: .semibold)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if !value.isEmpty {
                    Mix(text: value, size: 13, color: C.muted)
                        .lineLimit(1)
                }
                if chevron {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(C.muted.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(value.isEmpty ? title : "\(title), \(value)")
    }
}

struct SettingsToggleRow: View {
    var title: String
    var hint: String? = nil
    var isOn: Bool
    var action: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Mix(text: title, size: 15, weight: .medium)
                if let hint, !hint.isEmpty {
                    Mix(text: hint, size: 12, color: C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            SoftSwitch(isOn: Binding(get: { isOn }, set: action))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct SettingsSelectRow: View {
    var title: String
    var icon: String? = nil
    var value: String
    var options: [(String, String)]
    var onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Mix(text: title, size: 12, weight: .semibold, color: C.muted)
            SoftSelect(value: value, options: options, wide: true, icon: icon, onSelect: onSelect)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct SettingsChipButton: View {
    var title: String
    var tint: Color = C.cyan
    var filled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Mix(text: title, size: 12, weight: .semibold, color: filled ? Color(red: 0.04, green: 0.08, blue: 0.14) : tint)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(filled ? tint : tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(filled ? Color.clear : tint.opacity(0.28), lineWidth: 1)
                )
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(title)
    }
}
