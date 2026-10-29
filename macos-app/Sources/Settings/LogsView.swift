import SwiftUI

struct LogsView: View {
    @EnvironmentObject var model: Model
    @Environment(\.themeLight) private var themeLight
    @State private var text = ""
    @State private var kind = "error"
    @State private var query = ""
    @State private var level = "all"

    var body: some View {
        let _ = themeLight
        sub(model.t("logs")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SettingsChipButton(title: model.t("logErrorTab"), filled: kind == "error") {
                            kind = "error"
                            reload()
                        }
                        SettingsChipButton(title: model.t("logAccessTab"), filled: kind == "access") {
                            kind = "access"
                            reload()
                        }
                        SettingsChipButton(title: model.t("logDnsTab"), filled: kind == "dns") {
                            kind = "dns"
                            reload()
                        }
                        Spacer()
                        SettingsChipButton(title: model.t("clearLogs")) {
                            _ = model.call("clear_logs")
                            text = ""
                            model.showToast(model.t("saved"), tone: .success)
                        }
                        SettingsChipButton(title: model.t("update")) { reload() }
                    }
                    HStack {
                        SettingsChipButton(title: model.t("sidecarLogs"), filled: kind == "sidecar") {
                            kind = "sidecar"
                            reload()
                        }
                        SettingsSelectRow(
                            title: model.t("logFilter"),
                            icon: "line.3.horizontal.decrease.circle",
                            value: level,
                            options: [
                                ("all", model.t("sortDefault")),
                                ("error", model.t("logError")),
                                ("warning", model.t("logWarning")),
                                ("info", model.t("logInfo")),
                                ("debug", model.t("logDebug"))
                            ]
                        ) { level = $0 }
                    }
                    V2Field(placeholder: model.t("search"), text: $query, latin: true, icon: "magnifyingglass")
                    SettingsCard {
                        let shown = filtered
                        if !shown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Mix(text: "\(model.t("logClassified")) · \(LogClassifier.shared.classify(shown))", size: 11, color: C.muted)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                        }
                        if shown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(C.cyan.opacity(0.14))
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(C.cyan)
                                }
                                .frame(width: 40, height: 40)
                                Mix(text: model.t("empty"), size: 13, color: C.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                        } else {
                            Text(highlight(shown))
                                .font(.custom("Inter", size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { reload() }
            .onChange(of: query) { _, _ in }
        }
    }

    var filtered: String {
        text.split(separator: "\n").filter { line in
            let raw = String(line)
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !q.isEmpty && !raw.lowercased().contains(q) { return false }
            if level != "all" && !raw.lowercased().contains(level) { return false }
            return true
        }.joined(separator: "\n")
    }

    func highlight(_ raw: String) -> AttributedString {
        var result = AttributedString(raw)
        result.foregroundColor = C.text.opacity(0.82)
        highlightPattern("\\b\\d{1,3}(?:\\.\\d{1,3}){3}(?::\\d+)?\\b", in: raw, into: &result, color: C.accent)
        highlightPattern("https?://[^\\s]+|vless://[^\\s]+|vmess://[^\\s]+|trojan://[^\\s]+|ss://[^\\s]+|ssr://[^\\s]+", in: raw, into: &result, color: C.cyan)
        highlightPattern("\"[A-Za-z0-9_\\-]+\"", in: raw, into: &result, color: C.speedUp)
        highlightPattern("\\b(error|fatal|panic|failed)\\b", in: raw, into: &result, color: C.pingBad)
        highlightPattern("\\b(warn|warning|deprecated)\\b", in: raw, into: &result, color: Color.orange)
        highlightPattern("\\b(info|started|listening)\\b", in: raw, into: &result, color: C.lime)
        highlightPattern("\\b(dns|doh|dot|query|nameserver)\\b", in: raw, into: &result, color: C.cyan)
        highlightPattern("\\b(accepted|inbound|from)\\b", in: raw, into: &result, color: C.speedUp)
        return result
    }

    func highlightPattern(_ pattern: String, in raw: String, into result: inout AttributedString, color: Color) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
        let ns = raw as NSString
        for match in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            guard let range = Range(match.range, in: raw), let attrRange = Range(range, in: result) else { continue }
            result[attrRange].foregroundColor = color
        }
    }

    func reload() {
        if kind == "sidecar" {
            text = (model.call("sidecar_logs")["data"] as? [String: Any])?["text"] as? String ?? ""
            return
        }
        text = (model.call("logs", ["kind": kind])["data"] as? [String: Any])?["text"] as? String ?? ""
    }
}
