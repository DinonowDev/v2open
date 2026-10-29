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

struct LegalView: View {
    @EnvironmentObject var model: Model
    var kind: Kind

    enum Kind { case terms, privacy }

    var body: some View {
        sub(kind == .terms ? model.t("termsOfUse") : model.t("privacyPolicy")) {
            ScrollView(.vertical, showsIndicators: false) {
                SettingsCard {
                    Mix(text: bodyText, size: 13, color: C.text)
                        .textSelection(.enabled)
                        .padding(16)
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var bodyText: String {
        if kind == .terms {
            return model.fa ? faTerms : enTerms
        }
        return model.fa ? faPrivacy : enPrivacy
    }
}

private let enTerms = """
Terms of Use — V2Open

V2Open is a local VPN/proxy client for macOS developed by Amirhossein Rezaei. By using the app you agree to these terms.

1. You are responsible for the configs you import and for complying with the laws of your country.
2. The app runs cores (sing-box / Xray) on your Mac. You must have the right to use those binaries and any servers you connect to.
3. V2Open does not sell VPN service. It does not operate the servers in your configs.
4. The software is provided as-is, without warranty. The author is not liable for downtime, blocks, or data loss.
5. Do not use the app to attack systems, hide crime, or violate others’ rights.
6. Source and updates: https://github.com/DinonowDev/v2open
"""

private let faTerms = """
شرایط استفاده — V2Open

V2Open یک کلاینت محلی VPN/پروکسی برای مک است که امیرحسین رضایی آن را توسعه داده. با استفاده از اپ با این شرایط موافقت می‌کنید.

۱. مسئولیت کانفیگ‌هایی که وارد می‌کنید و رعایت قوانین کشورتان با شماست.
۲. اپ هسته‌های sing-box و Xray را روی مک شما اجرا می‌کند. باید حق استفاده از آن باینری‌ها و سرورهایی که به آن‌ها وصل می‌شوید را داشته باشید.
۳. V2Open سرویس VPN نمی‌فروشد و سرورهای کانفیگ شما را اداره نمی‌کند.
۴. نرم‌افزار «همان‌طور که هست» ارائه می‌شود و تضمینی ندارد. نویسنده مسئول قطعی، فیلتر یا از دست رفتن داده نیست.
۵. از اپ برای حمله، پنهان کردن جرم یا نقض حقوق دیگران استفاده نکنید.
۶. منبع و به‌روزرسانی: https://github.com/DinonowDev/v2open
"""

private let enPrivacy = """
Privacy Policy — V2Open

V2Open is built to keep your library on this Mac.

1. Configs, routes, DNS items and backups stay in ~/Library/Application Support/V2Open unless you export them or turn on iCloud.
2. The app does not run an account system and does not send your configs to the developer.
3. Optional iCloud sync copies your library to your own iCloud container. That data is under your Apple ID, not a V2Open server.
4. Speed tests and Smart Connect ping the hosts you configure (or public generate_204 endpoints). Those requests go from your Mac to those hosts, not to us.
5. Crash or debug logs stay local unless you copy them yourself.
6. Questions: GitHub @DinonowDev — https://github.com/DinonowDev/v2open
"""

private let faPrivacy = """
سیاست حریم خصوصی — V2Open

V2Open طوری ساخته شده که کتابخانه روی همین مک بماند.

۱. کانفیگ‌ها، مسیرها، DNS و پشتیبان‌ها در ~/Library/Application Support/V2Open می‌مانند مگر خودتان خروجی بگیرید یا iCloud را روشن کنید.
۲. اپ حساب کاربری ندارد و کانفیگ شما را برای توسعه‌دهنده نمی‌فرستد.
۳. همگام‌سازی اختیاری iCloud کتابخانه را به کانتینر iCloud خودتان می‌فرستد؛ داده زیر اپل‌آیدی شماست، نه سرور V2Open.
۴. تست سرعت و Smart Connect به میزبان‌هایی که تنظیم کرده‌اید (یا generate_204 عمومی) پینگ می‌زنند. این درخواست‌ها از مک شما می‌روند، نه به ما.
۵. لاگ کرش و دیباگ محلی می‌ماند مگر خودتان کپی کنید.
۶. پرسش‌ها: GitHub @DinonowDev — https://github.com/DinonowDev/v2open
"""
