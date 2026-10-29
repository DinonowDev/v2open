import AppKit
import SwiftUI

struct LegalView: View {
    @EnvironmentObject var model: Model
    var kind: Kind

    enum Kind { case terms, privacy }

    private var doc: LegalDocument {
        kind == .terms ? .terms(fa: model.fa) : .privacy(fa: model.fa)
    }

    var body: some View {
        sub(kind == .terms ? model.t("termsOfUse") : model.t("privacyPolicy")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    introCard
                    clausesCard
                    sourceCard
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var introCard: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(C.cyan)
                    .frame(width: 3)
                    .padding(.vertical, 1)
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(C.cyan.opacity(0.16))
                    Image(systemName: doc.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(C.cyan)
                }
                .frame(width: 36, height: 36)
                LegalBody(text: doc.intro, size: 14, weight: .medium, color: C.text, spacing: 5)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private var clausesCard: some View {
        SettingsCard {
            ForEach(Array(doc.clauses.enumerated()), id: \.element.id) { index, clause in
                if index > 0 { SettingsDivider(inset: 16) }
                LegalClauseRow(index: index + 1, fa: model.fa, clause: clause)
            }
        }
    }

    private var sourceCard: some View {
        SettingsCard {
            Button {
                if let url = URL(string: doc.sourceURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(C.cyan.opacity(0.16))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(C.cyan)
                    }
                    .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Mix(text: doc.sourceTitle, size: 15, weight: .semibold)
                        Mix(text: "DinonowDev/v2open", size: 12, color: C.cyan)
                    }
                    Spacer(minLength: 6)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(QuietPressStyle())
            .accessibilityLabel(doc.sourceTitle)
        }
    }
}

private struct LegalClauseRow: View {
    var index: Int
    var fa: Bool
    var clause: LegalClause

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Mix(text: legalIndex(index, fa: fa), size: 13, weight: .bold, color: C.cyan)
                .frame(width: 22, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Mix(text: clause.title, size: 15, weight: .semibold)
                LegalBody(text: clause.body, size: 13.5, color: C.text, spacing: 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(legalIndex(index, fa: fa)). \(clause.title). \(clause.body)")
    }
}

private struct LegalBody: View {
    var text: String
    var size: CGFloat
    var weight: Font.Weight = .regular
    var color: Color
    var spacing: CGFloat

    var body: some View {
        mixed(text, size: size, weight: weight)
            .foregroundStyle(color)
            .lineSpacing(spacing)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func legalIndex(_ n: Int, fa: Bool) -> String {
    guard fa else { return "\(n)" }
    let digits: [Character] = Array("۰۱۲۳۴۵۶۷۸۹")
    return String(n).compactMap { ch -> Character? in
        guard let value = ch.wholeNumberValue, digits.indices.contains(value) else { return nil }
        return digits[value]
    }.map(String.init).joined()
}

private struct LegalDocument {
    var icon: String
    var intro: String
    var clauses: [LegalClause]
    var sourceTitle: String
    var sourceURL: String

    static func terms(fa: Bool) -> LegalDocument {
        LegalDocument(
            icon: "doc.text.fill",
            intro: fa
                ? "V2Open یک کلاینت محلی VPN/پروکسی برای مک است که امیرحسین رضایی آن را توسعه داده. با استفاده از اپ با این شرایط موافقت می‌کنید."
                : "V2Open is a local VPN/proxy client for macOS developed by Amirhossein Rezaei. By using the app you agree to these terms.",
            clauses: [
                LegalClause(
                    title: fa ? "مسئولیت کانفیگ‌ها با شماست" : "Your configs, your laws",
                    body: fa
                        ? "مسئولیت کانفیگ‌هایی که وارد می‌کنید و رعایت قوانین کشورتان با شماست."
                        : "You are responsible for the configs you import and for complying with the laws of your country."
                ),
                LegalClause(
                    title: fa ? "هسته‌ها روی همین مک اجرا می‌شوند" : "Cores run on this Mac",
                    body: fa
                        ? "اپ هسته‌های sing-box و Xray را روی مک شما اجرا می‌کند. باید حق استفاده از آن باینری‌ها و سرورهایی که به آن‌ها وصل می‌شوید را داشته باشید."
                        : "The app runs cores (sing-box / Xray) on your Mac. You must have the right to use those binaries and any servers you connect to."
                ),
                LegalClause(
                    title: fa ? "سرویس VPN نمی‌فروشد" : "Not a VPN service",
                    body: fa
                        ? "V2Open سرویس VPN نمی‌فروشد و سرورهای کانفیگ شما را اداره نمی‌کند."
                        : "V2Open does not sell VPN service. It does not operate the servers in your configs."
                ),
                LegalClause(
                    title: fa ? "بدون تضمین ارائه می‌شود" : "Provided as-is",
                    body: fa
                        ? "نرم‌افزار «همان‌طور که هست» ارائه می‌شود و تضمینی ندارد. نویسنده مسئول قطعی، فیلتر یا از دست رفتن داده نیست."
                        : "The software is provided as-is, without warranty. The author is not liable for downtime, blocks, or data loss."
                ),
                LegalClause(
                    title: fa ? "سوءاستفاده ممنوع است" : "No abuse",
                    body: fa
                        ? "از اپ برای حمله، پنهان کردن جرم یا نقض حقوق دیگران استفاده نکنید."
                        : "Do not use the app to attack systems, hide crime, or violate others’ rights."
                )
            ],
            sourceTitle: fa ? "منبع و به‌روزرسانی" : "Source and updates",
            sourceURL: "https://github.com/DinonowDev/v2open"
        )
    }

    static func privacy(fa: Bool) -> LegalDocument {
        LegalDocument(
            icon: "hand.raised.fill",
            intro: fa
                ? "V2Open طوری ساخته شده که کتابخانه روی همین مک بماند."
                : "V2Open is built to keep your library on this Mac.",
            clauses: [
                LegalClause(
                    title: fa ? "داده روی همین مک می‌ماند" : "Data stays on this Mac",
                    body: fa
                        ? "کانفیگ‌ها، مسیرها، DNS و پشتیبان‌ها در ~/Library/Application Support/V2Open می‌مانند مگر خودتان خروجی بگیرید یا iCloud را روشن کنید."
                        : "Configs, routes, DNS items and backups stay in ~/Library/Application Support/V2Open unless you export them or turn on iCloud."
                ),
                LegalClause(
                    title: fa ? "بدون حساب کاربری" : "No accounts",
                    body: fa
                        ? "اپ حساب کاربری ندارد و کانفیگ شما را برای توسعه‌دهنده نمی‌فرستد."
                        : "The app does not run an account system and does not send your configs to the developer."
                ),
                LegalClause(
                    title: fa ? "همگام‌سازی اختیاری iCloud" : "Optional iCloud sync",
                    body: fa
                        ? "همگام‌سازی اختیاری iCloud کتابخانه را به کانتینر iCloud خودتان می‌فرستد؛ داده زیر اپل‌آیدی شماست، نه سرور V2Open."
                        : "Optional iCloud sync copies your library to your own iCloud container. That data is under your Apple ID, not a V2Open server."
                ),
                LegalClause(
                    title: fa ? "تست‌ها از مک شما می‌روند" : "Tests leave from your Mac",
                    body: fa
                        ? "تست سرعت و Smart Connect به میزبان‌هایی که تنظیم کرده‌اید (یا generate_204 عمومی) پینگ می‌زنند. این درخواست‌ها از مک شما می‌روند، نه به ما."
                        : "Speed tests and Smart Connect ping the hosts you configure (or public generate_204 endpoints). Those requests go from your Mac to those hosts, not to us."
                ),
                LegalClause(
                    title: fa ? "لاگ‌ها محلی می‌مانند" : "Logs stay local",
                    body: fa
                        ? "لاگ کرش و دیباگ محلی می‌ماند مگر خودتان کپی کنید."
                        : "Crash or debug logs stay local unless you copy them yourself."
                )
            ],
            sourceTitle: fa ? "پرسش‌ها روی GitHub" : "Questions on GitHub",
            sourceURL: "https://github.com/DinonowDev/v2open"
        )
    }
}

private struct LegalClause: Identifiable {
    var title: String
    var body: String
    var id: String { title }
}
