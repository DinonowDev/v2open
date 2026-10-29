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
                    SettingsCard {
                        row(model.t("appVersion"), "v\(appVersion) (\(build))")
                        SettingsDivider()
                        row("sing-box", str("sing_box").isEmpty ? (model.runtime["core"] as? String ?? "—") : str("sing_box"))
                        SettingsDivider()
                        row("Xray", str("xray").isEmpty ? "—" : str("xray"))
                        SettingsDivider()
                        row("Engine", str("engine").isEmpty ? (model.runtime["engine"] as? String ?? "sing-box") : str("engine"))
                        SettingsDivider()
                        row("DoQ", (about["doq"] as? Bool == true) ? model.t("supported") : model.t("notSupported"))
                    }
                    SheetActionButton(title: model.t("copyVersions"), icon: "doc.on.clipboard") {
                        let text = [
                            "V2Open v\(appVersion) (\(build))",
                            "sing-box \(str("sing_box"))",
                            "Xray \(str("xray"))",
                            "https://github.com/DinonowDev/v2open"
                        ].joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        model.showToast(model.t("saved"), tone: .success)
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
                    SettingsCard {
                        Mix(text: model.t("urlSchemesHint"), size: 12, color: C.muted)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                        Mix(
                            text: "v2open://   vless://   vmess://   trojan://\nss://   ssr://   hy2://   hysteria://\nwireguard://   v2box://",
                            size: 12,
                            color: C.text
                        )
                        .textSelection(.enabled)
                        .padding(14)
                    }

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

    func str(_ key: String) -> String {
        about[key] as? String ?? ""
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