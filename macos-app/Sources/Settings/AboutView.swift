import AppKit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject var model: Model

    private var about: [String: Any] { model.about }
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? (about["app_version"] as? String)
            ?? "1.1.0"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
    private var singBoxRaw: String {
        let value = str("sing_box")
        if !value.isEmpty { return value }
        return model.runtime["core"] as? String ?? ""
    }
    private var xrayRaw: String { str("xray") }
    private var engineName: String {
        let value = str("engine")
        if !value.isEmpty { return value }
        return model.runtime["engine"] as? String ?? "sing-box"
    }
    private var doqOn: Bool { about["doq"] as? Bool == true }

    var body: some View {
        sub(model.t("about")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle().fill(C.cyan.opacity(0.14)).frame(width: 64, height: 64)
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(C.cyan)
                            }
                            Mix(text: model.t("app"), size: 22, weight: .bold)
                            Mix(text: "v\(appVersion) (\(build))", size: 13, color: C.muted)
                            Mix(
                                text: model.fa
                                    ? "کلاینت دسکتاپ آزاد برای مک. کانفیگ‌ها روی همین دستگاه می‌مانند."
                                    : "A local macOS client. Configs stay on this Mac.",
                                size: 13,
                                color: C.muted
                            )
                            .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                    }

                    SettingsSectionLabel(text: model.t("versions"))
                    versionsCard
                    SheetActionButton(title: model.t("copyVersions"), icon: "doc.on.clipboard") {
                        let text = [
                            "V2Open v\(appVersion) (\(build))",
                            "sing-box \(singBoxRaw)",
                            "Xray \(xrayRaw)",
                            "https://github.com/DinonowDev/v2open"
                        ].joined(separator: "\n")
                        ShareKit.copy(text)
                        model.showToast(model.t("copied"), tone: .success)
                    }

                    SettingsSectionLabel(text: model.t("developer"))
                    SettingsCard {
                        row(model.t("developedBy"), "Amirhossein Rezaei")
                        SettingsDivider()
                        linkRow("GitHub", "github.com/DinonowDev", "https://github.com/DinonowDev")
                        SettingsDivider()
                        linkRow(model.t("sourceRepo"), "github.com/DinonowDev/v2open", "https://github.com/DinonowDev/v2open")
                        SettingsDivider()
                        row(model.t("copyright"), "© 2026 Amirhossein Rezaei")
                    }

                    SettingsSectionLabel(text: model.t("urlSchemes"))
                    schemesCard

                    SettingsSectionLabel(text: model.t("legal"))
                    SettingsCard {
                        SettingsNavRow(icon: "doc.text", title: model.t("termsOfUse"), action: { model.push("terms") })
                        SettingsDivider(inset: 58)
                        SettingsNavRow(icon: "hand.raised", title: model.t("privacyPolicy"), action: { model.push("privacy") })
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { model.refreshAbout() }
        }
    }

    private var versionsCard: some View {
        SettingsCard {
            VStack(spacing: 8) {
                AboutVersionPlate(
                    version: appVersion,
                    build: build,
                    caption: model.t("appVersion")
                ) {
                    copyValue("V2Open v\(appVersion) (\(build))")
                }

                AboutCoreTile(
                    title: "sing-box",
                    icon: "cube.fill",
                    tint: C.cyan,
                    parsed: AboutCoreVersion.parse(singBoxRaw, kind: .singBox)
                ) {
                    copyValue(singBoxRaw)
                }

                AboutCoreTile(
                    title: "Xray",
                    icon: "bolt.fill",
                    tint: C.speedUp,
                    parsed: AboutCoreVersion.parse(xrayRaw, kind: .xray)
                ) {
                    copyValue(xrayRaw)
                }

                HStack(spacing: 8) {
                    AboutStatusTile(
                        icon: "gearshape.2.fill",
                        title: "Engine",
                        value: engineName.isEmpty ? "—" : engineName,
                        tint: C.cyan
                    )
                    AboutStatusTile(
                        icon: doqOn ? "checkmark.seal.fill" : "xmark.seal.fill",
                        title: "DoQ",
                        value: doqOn ? model.t("supported") : model.t("notSupported"),
                        tint: doqOn ? C.green : C.muted
                    )
                }
            }
            .padding(12)
        }
    }

    private var schemesCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(C.cyan.opacity(0.14))
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(C.cyan)
                    }
                    .frame(width: 32, height: 32)
                    Mix(text: model.t("urlSchemesHint"), size: 12, color: C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(AboutSchemeItem.all) { item in
                        AboutSchemeChip(item: item) {
                            copyValue(item.scheme)
                        }
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(14)
        }
    }

    func str(_ key: String) -> String {
        about[key] as? String ?? ""
    }

    func copyValue(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "—" else { return }
        ShareKit.copy(value)
        model.showToast(model.t("copied"), tone: .success)
    }

    func row(_ title: String, _ value: String) -> some View {
        HStack {
            Mix(text: title, size: 13, color: C.muted)
            Spacer()
            Mix(text: value.isEmpty ? "—" : value, size: 13, weight: .semibold)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    func linkRow(_ title: String, _ label: String, _ url: String) -> some View {
        Button {
            if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        } label: {
            HStack {
                Mix(text: title, size: 13, color: C.muted)
                Spacer()
                Mix(text: label, size: 13, weight: .semibold, color: C.cyan)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(C.cyan)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AboutVersionPlate: View {
    @Environment(\.themeLight) private var themeLight
    var version: String
    var build: String
    var caption: String
    var onCopy: () -> Void

    var body: some View {
        let _ = themeLight
        Button(action: onCopy) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [C.cyan.opacity(0.22), C.accentDeep.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "macwindow")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(C.cyan)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("v\(version)")
                            .font(.custom("Inter", size: 22).weight(.bold))
                            .foregroundStyle(C.text)
                            .monospacedDigit()
                        Text(build)
                            .font(.custom("Inter", size: 10).weight(.bold))
                            .foregroundStyle(C.cyan)
                            .padding(.horizontal, 8)
                            .frame(height: 18)
                            .background(C.cyan.opacity(0.14))
                            .clipShape(Capsule())
                    }
                    Mix(text: caption, size: 11, weight: .medium, color: C.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(C.muted.opacity(0.7))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(C.cyan.opacity(themeLight ? 0.07 : 0.08))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(C.cyan.opacity(0.22), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel("\(caption) v\(version) (\(build))")
    }
}

private struct AboutCoreTile: View {
    @Environment(\.themeLight) private var themeLight
    var title: String
    var icon: String
    var tint: Color
    var parsed: AboutCoreVersion
    var onCopy: () -> Void

    var body: some View {
        let _ = themeLight
        Button(action: onCopy) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Mix(text: title, size: 12, weight: .semibold)
                        Spacer(minLength: 0)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(C.muted.opacity(0.55))
                    }
                    Text(parsed.headline)
                        .font(.custom("Inter", size: 13).weight(.semibold))
                        .foregroundStyle(C.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !parsed.detail.isEmpty {
                        Text(parsed.detail)
                            .font(.custom("Inter", size: 11).weight(.medium))
                            .foregroundStyle(C.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(C.overlay.opacity(themeLight ? 0.035 : 0.045))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(C.line, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel("\(title) \(parsed.headline)")
    }
}

private struct AboutStatusTile: View {
    @Environment(\.themeLight) private var themeLight
    var icon: String
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        let _ = themeLight
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Mix(text: title, size: 11, weight: .medium, color: C.muted)
            }
            Mix(text: value, size: 13, weight: .semibold)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(themeLight ? 0.07 : 0.10))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }
}

private struct AboutSchemeItem: Identifiable {
    var id: String { scheme }
    var scheme: String
    var tint: Color
    var brand: Bool = false

    static let all: [AboutSchemeItem] = [
        .init(scheme: "v2open://", tint: C.cyan, brand: true),
        .init(scheme: "vless://", tint: Color(red: 0.39, green: 0.72, blue: 1.0)),
        .init(scheme: "vmess://", tint: Color(red: 0.45, green: 0.62, blue: 1.0)),
        .init(scheme: "trojan://", tint: C.speedUp),
        .init(scheme: "ss://", tint: C.green),
        .init(scheme: "ssr://", tint: Color(red: 0.20, green: 0.72, blue: 0.58)),
        .init(scheme: "hy2://", tint: C.pingWarn),
        .init(scheme: "hysteria://", tint: Color(red: 1.0, green: 0.62, blue: 0.28)),
        .init(scheme: "wireguard://", tint: C.ping),
        .init(scheme: "v2box://", tint: C.cyan)
    ]
}

private struct AboutSchemeChip: View {
    var item: AboutSchemeItem
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(item.scheme)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(item.brand ? C.onAccent : item.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background {
                    if item.brand {
                        LinearGradient(
                            colors: [C.cyan, C.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        item.tint.opacity(hovering ? 0.20 : 0.12)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(item.brand ? Color.clear : item.tint.opacity(hovering ? 0.55 : 0.28), lineWidth: 1)
                )
                .shadow(color: item.brand ? C.cyan.opacity(0.28) : .clear, radius: item.brand ? 8 : 0, y: 1)
        }
        .buttonStyle(QuietPressStyle())
        .onHover { hovering = $0 }
        .help(item.scheme)
        .accessibilityLabel(item.scheme)
    }
}

private struct AboutCoreVersion {
    enum Kind { case singBox, xray }
    var headline: String
    var detail: String

    static func parse(_ raw: String, kind: Kind) -> AboutCoreVersion {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return AboutCoreVersion(headline: "—", detail: "") }
        switch kind {
        case .singBox:
            var text = trimmed
            let prefix = "sing-box version "
            if text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
            }
            return AboutCoreVersion(headline: text, detail: "")
        case .xray:
            let version = firstMatch(#"Xray\s+([\d.]+)"#, in: trimmed, group: 1)
            let commit = firstMatch(#"\b([0-9a-f]{7,40})\b"#, in: trimmed, group: 1)
            let runtime = firstMatch(#"\((go[^)]+)\)"#, in: trimmed, group: 1)
            let headline = version ?? trimmed
            var parts: [String] = []
            if let commit { parts.append(commit) }
            if let runtime {
                parts.append(runtime.replacingOccurrences(of: " ", with: " · "))
            }
            let detail = parts.joined(separator: " · ")
            if version == nil { return AboutCoreVersion(headline: trimmed, detail: "") }
            return AboutCoreVersion(headline: headline, detail: detail)
        }
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > group,
              let swiftRange = Range(match.range(at: group), in: text) else { return nil }
        return String(text[swiftRange])
    }
}

