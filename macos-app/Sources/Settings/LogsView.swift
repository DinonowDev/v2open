import AppKit
import SwiftUI

struct LogsView: View {
    @EnvironmentObject var model: Model
    @Environment(\.themeLight) private var themeLight
    @State private var text = ""
    @State private var kind = "error"
    @State private var query = ""
    @State private var level = "all"
    @State private var live = true
    @State private var path = ""
    @State private var size: UInt64 = 0
    @State private var lines = 0
    @State private var exists = false

    private let tabs: [(id: String, titleKey: String, icon: String)] = [
        ("error", "logErrorTab", "exclamationmark.triangle.fill"),
        ("access", "logAccessTab", "arrow.left.arrow.right"),
        ("dns", "logDnsTab", "globe"),
        ("sidecar", "sidecarLogs", "waveform.path.ecg")
    ]

    var body: some View {
        let _ = themeLight
        sub(model.t("logs")) {
            VStack(alignment: .leading, spacing: 12) {
                heroCard
                loggingCard
                tabStrip
                levelChips
                toolbar
                V2Field(placeholder: model.t("search"), text: $query, latin: true, icon: "magnifyingglass")
                logCard
            }
            .padding(.horizontal, PageLayout.horizontal)
            .padding(.top, 4)
            .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            .onAppear { reload() }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                if live { reload() }
            }
        }
    }

    private var shown: String { filtered }
    private var empty: Bool { shown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var classified: String { empty ? "—" : LogClassifier.shared.classify(shown) }
    private var loggingOn: Bool { model.settings["logging_enabled"] as? Bool ?? true }

    private var heroTint: Color {
        if !loggingOn { return C.muted }
        switch kind {
        case "error": return C.pingBad
        case "access": return C.speedUp
        case "dns": return C.cyan
        default: return C.green
        }
    }

    private var heroCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [heroTint.opacity(0.28), heroTint.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: tabs.first(where: { $0.id == kind })?.icon ?? "doc.text")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(heroTint)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Mix(text: model.t(tabs.first(where: { $0.id == kind })?.titleKey ?? "logs"), size: 18, weight: .bold)
                    Mix(
                        text: empty
                            ? model.t("logEmptyHint")
                            : "\(model.t("logClassified")) · \(classified)",
                        size: 12,
                        color: C.muted
                    )
                    .lineLimit(2)
                }
                Spacer(minLength: 0)
                Mix(
                    text: exists ? model.t("fileExists") : model.t("fileMissing"),
                    size: 11,
                    weight: .semibold,
                    color: exists ? C.green : C.muted
                )
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background((exists ? C.green : C.muted).opacity(0.14))
                .clipShape(Capsule())
            }
            .padding(14)
            HStack(spacing: 8) {
                logStat(icon: "text.alignleft", title: model.t("logLines"), value: "\(lines)", tint: C.cyan)
                logStat(icon: "internaldrive", title: model.t("memory"), value: size == 0 ? "—" : formatBytes(size), tint: C.speedUp)
                logStat(icon: "slider.horizontal.3", title: model.t("log"), value: logLevelLabel, tint: C.accent)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var loggingCard: some View {
        SettingsCard {
            SettingsToggleRow(
                title: model.t("enableLogging"),
                hint: model.t("loggingHint"),
                isOn: loggingOn
            ) { model.set("logging_enabled", $0) }
            SettingsDivider()
            SettingsSelectRow(
                title: model.t("log"),
                icon: "text.alignleft",
                value: model.settings["loglevel"] as? String ?? "none",
                options: [
                    ("none", model.t("logNone")),
                    ("error", model.t("logError")),
                    ("warning", model.t("logWarning")),
                    ("info", model.t("logInfo")),
                    ("debug", model.t("logDebug"))
                ]
            ) { model.set("loglevel", $0) }
        }
    }

    private var logLevelLabel: String {
        switch model.settings["loglevel"] as? String ?? "none" {
        case "error": return model.t("logError")
        case "warning": return model.t("logWarning")
        case "info": return model.t("logInfo")
        case "debug": return model.t("logDebug")
        default: return model.t("logNone")
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.id) { tab in
                let on = kind == tab.id
                Button {
                    kind = tab.id
                    reload()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(on ? C.cyan : C.muted)
                        Mix(text: model.t(tab.titleKey), size: 10, weight: .semibold, color: on ? C.cyan : C.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(on ? C.cyan.opacity(themeLight ? 0.10 : 0.12) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(QuietPressStyle())
            }
        }
        .background(C.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(C.hairline, lineWidth: 1)
        )
    }

    private var levelChips: some View {
        let options = [
            ("all", model.t("sortDefault")),
            ("error", model.t("logError")),
            ("warning", model.t("logWarning")),
            ("info", model.t("logInfo")),
            ("debug", model.t("logDebug"))
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Mix(text: model.t("logFilter"), size: 11, color: C.muted)
                ForEach(options, id: \.0) { option in
                    SettingsChipButton(title: option.1, filled: level == option.0) {
                        level = option.0
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            SettingsChipButton(title: model.t("logAutoRefresh"), tint: live ? C.green : C.muted, filled: live) {
                live.toggle()
            }
            Spacer(minLength: 0)
            iconTool("square.and.arrow.up", model.t("exportLog"), enabled: !empty) { exportLog() }
            iconTool("doc.on.doc", model.t("copyLogs"), enabled: !empty) { copyLog() }
            iconTool("folder", model.t("logOpenFile"), enabled: !path.isEmpty) { reveal() }
            iconTool("trash", model.t("clearLogs"), enabled: true) {
                _ = model.call("clear_logs")
                text = ""
                lines = 0
                size = 0
                exists = false
                model.showToast(model.t("saved"), tone: .success)
            }
        }
    }

    private var logCard: some View {
        SettingsCard {
            if empty {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(C.cyan.opacity(0.14))
                        Image(systemName: "doc.text")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(C.cyan)
                    }
                    .frame(width: 40, height: 40)
                    Mix(text: model.t("logEmptyHint"), size: 13, color: C.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollView {
                    Text(highlight(shown))
                        .font(.custom("Inter", size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .textSelection(.enabled)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func logStat(icon: String, title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Mix(text: title, size: 10, weight: .medium, color: C.muted)
                    .lineLimit(1)
            }
            Mix(text: value, size: 13, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(themeLight ? 0.07 : 0.10))
        }
    }

    func iconTool(_ system: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? C.cyan : C.muted.opacity(0.45))
                .frame(width: 34, height: 34)
                .background(C.cyan.opacity(enabled ? 0.14 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(QuietPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
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

    func copyLog() {
        ShareKit.copy(shown)
        model.showToast(model.t("copied"), tone: .success)
    }

    func exportLog() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(kind).log"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try shown.write(to: url, atomically: true, encoding: .utf8)
            model.showToast(model.t("saved"), tone: .success)
        } catch {
            model.showToast(model.t("failed"), tone: .error)
        }
    }

    func reveal() {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    func reload() {
        let data = model.call("logs", ["kind": kind])["data"] as? [String: Any] ?? [:]
        text = data["text"] as? String ?? ""
        path = data["path"] as? String ?? ""
        size = jsonUInt(data["size"])
        exists = data["exists"] as? Bool ?? false
        if let count = data["lines"] as? Int {
            lines = count
        } else if let count = data["lines"] as? NSNumber {
            lines = count.intValue
        } else {
            lines = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        }
    }
}
