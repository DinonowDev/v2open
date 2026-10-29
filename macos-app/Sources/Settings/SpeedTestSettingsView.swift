import SwiftUI

struct SpeedTestSettingsView: View {
    @EnvironmentObject var model: Model
    @Environment(\.themeLight) private var themeLight
    @State private var timeout = ""
    @State private var endpoint = ""

    private let defaultEndpoint = "https://www.gstatic.com/generate_204"

    var body: some View {
        let _ = themeLight
        sub(model.t("speedTestSettings")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    snapshotStrip

                    SettingsSectionLabel(text: model.t("speedTestMethod"))
                    methodCards

                    SettingsSectionLabel(text: model.t("speedConcurrency"))
                    concurrencyCard

                    SettingsSectionLabel(text: model.t("speedTimeout"))
                    timeoutCard

                    SettingsSectionLabel(text: model.t("speedEndpoint"))
                    endpointCard

                    SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") { saveFields() }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { load() }
        }
    }

    private var mode: String { model.settings["speed_mode"] as? String ?? "http" }
    private var concurrency: Int {
        let value = model.settings["speed_concurrency"] as? Int ?? Int(model.settings["speed_concurrency"] as? Double ?? 2)
        return min(max(value, 1), 8)
    }

    private var methodTint: Color {
        switch mode {
        case "tcp": return C.speedUp
        case "icmp": return C.green
        default: return C.cyan
        }
    }

    private var summaryCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [methodTint.opacity(0.28), methodTint.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: methodIcon(mode))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(methodTint)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Mix(text: methodTitle(mode), size: 18, weight: .bold, color: methodTint)
                    Mix(text: model.t("speedTestSettings"), size: 12, weight: .medium, color: C.muted)
                        .lineLimit(2)
                    Mix(text: endpointHost, size: 11, color: C.muted)
                        .lineLimit(1)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    private var snapshotStrip: some View {
        HStack(spacing: 8) {
            SpeedSettingTile(
                icon: methodIcon(mode),
                title: model.t("speedTestMethod"),
                value: methodTitle(mode),
                tint: methodTint
            )
            SpeedSettingTile(
                icon: "clock",
                title: model.t("speedTimeout"),
                value: "\((timeout.isEmpty ? "8" : timeout))s",
                tint: C.accent
            )
            SpeedSettingTile(
                icon: "arrow.left.arrow.right",
                title: model.t("speedConcurrency"),
                value: "\(concurrency)×",
                tint: C.speedDown
            )
        }
    }

    private var endpointHost: String {
        let raw = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "gstatic.com" }
        return raw
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/").first
            .map(String.init) ?? raw
    }

    private var methodCards: some View {
        VStack(spacing: 8) {
            methodCard(
                id: "http",
                icon: "arrow.triangle.2.circlepath",
                title: model.t("speedModeHttp"),
                detail: model.t("speedModeHttpDesc"),
                tint: C.cyan
            )
            methodCard(
                id: "tcp",
                icon: "point.3.connected.trianglepath.dotted",
                title: model.t("speedModeTcp"),
                detail: model.t("speedModeTcpDesc"),
                tint: C.speedUp
            )
            methodCard(
                id: "icmp",
                icon: "waveform.path.ecg",
                title: model.t("speedModeIcmp"),
                detail: model.t("speedModeIcmpDesc"),
                tint: C.green
            )
        }
    }

    private var concurrencyCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Mix(text: model.t("speedConcurrencyHint"), size: 12, color: C.muted)
                HStack(spacing: 8) {
                    ForEach([1, 2, 4, 8], id: \.self) { value in
                        let on = concurrency == value
                        Button {
                            model.set("speed_concurrency", value)
                        } label: {
                            Mix(
                                text: "\(value)",
                                size: 14,
                                weight: .bold,
                                color: on ? C.onAccent : C.text
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background {
                                if on {
                                    LinearGradient(colors: [C.cyan, C.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                                } else {
                                    C.overlay.opacity(0.06)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(on ? Color.clear : C.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(QuietPressStyle())
                        .accessibilityLabel("\(model.t("speedConcurrency")) \(value)")
                    }
                }
                stepperRow(
                    value: concurrency,
                    range: 1...8,
                    unit: "×"
                ) { model.set("speed_concurrency", $0) }
            }
            .padding(14)
        }
    }

    private var timeoutCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Mix(text: model.t("speedTimeoutHint"), size: 12, color: C.muted)
                HStack(spacing: 8) {
                    ForEach([4, 8, 12, 20], id: \.self) { value in
                        let on = (Int(timeout) ?? 0) == value
                        Button {
                            timeout = String(value)
                            model.set("speed_timeout", value)
                        } label: {
                            Mix(
                                text: "\(value)s",
                                size: 13,
                                weight: .bold,
                                color: on ? C.onAccent : C.text
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background {
                                if on {
                                    LinearGradient(colors: [C.cyan, C.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                                } else {
                                    C.overlay.opacity(0.06)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(on ? Color.clear : C.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(QuietPressStyle())
                    }
                }
                V2Field(label: model.t("speedTimeout"), placeholder: "8", text: $timeout, latin: true, icon: "clock")
            }
            .padding(14)
        }
    }

    private var endpointCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Mix(text: model.t("speedEndpointHint"), size: 12, color: C.muted)
                V2Field(
                    label: model.t("speedEndpoint"),
                    placeholder: defaultEndpoint,
                    text: $endpoint,
                    latin: true,
                    pasteable: true,
                    icon: "link"
                )
                HStack(spacing: 8) {
                    SheetActionButton(title: model.t("speedResetDefault"), icon: "arrow.counterclockwise") {
                        endpoint = defaultEndpoint
                        model.set("speed_endpoint", defaultEndpoint)
                        model.set("probe_url", defaultEndpoint)
                        model.showToast(model.t("saved"), tone: .success)
                    }
                }
            }
            .padding(14)
        }
    }

    func methodCard(id: String, icon: String, title: String, detail: String, tint: Color) -> some View {
        let on = mode == id
        return Button {
            model.set("speed_mode", id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(on ? 0.22 : 0.14))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Mix(text: title, size: 15, weight: .semibold)
                        Spacer(minLength: 8)
                        if on {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(C.cyan)
                        }
                    }
                    Mix(text: detail, size: 12, color: C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(on ? tint.opacity(themeLight ? 0.08 : 0.12) : C.cardElevated)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(on ? tint.opacity(0.7) : C.line, lineWidth: on ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : AccessibilityTraits())
    }

    func stepperRow(value: Int, range: ClosedRange<Int>, unit: String, set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 12) {
            Mix(text: model.t("speedCustom"), size: 13, color: C.muted)
            Spacer()
            Button { set(max(range.lowerBound, value - 1)) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(C.cyan)
                    .frame(width: 32, height: 32)
                    .background(C.cyan.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(QuietPressStyle())
            .disabled(value <= range.lowerBound)
            Mix(text: "\(value)\(unit)", size: 15, weight: .bold)
                .frame(minWidth: 36)
            Button { set(min(range.upperBound, value + 1)) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(C.cyan)
                    .frame(width: 32, height: 32)
                    .background(C.cyan.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(QuietPressStyle())
            .disabled(value >= range.upperBound)
        }
    }

    func methodIcon(_ id: String) -> String {
        switch id {
        case "tcp": return "point.3.connected.trianglepath.dotted"
        case "icmp": return "waveform.path.ecg"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    func methodTitle(_ id: String) -> String {
        switch id {
        case "tcp": return model.t("speedModeTcp")
        case "icmp": return model.t("speedModeIcmp")
        default: return model.t("speedModeHttp")
        }
    }

    func load() {
        let timeoutValue = model.settings["speed_timeout"] as? Int ?? Int(model.settings["speed_timeout"] as? Double ?? 8)
        timeout = String(timeoutValue)
        endpoint = model.settings["speed_endpoint"] as? String
            ?? (model.settings["probe_url"] as? String ?? defaultEndpoint)
    }

    func saveFields() {
        if let value = Int(timeout.trimmingCharacters(in: .whitespaces)), value >= 2, value <= 60 {
            model.set("speed_timeout", value)
        }
        let url = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty {
            model.set("speed_endpoint", url)
            model.set("probe_url", url)
        }
        model.showToast(model.t("saved"), tone: .success)
    }
}

private struct SpeedSettingTile: View {
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
                    .lineLimit(1)
            }
            Text(value)
                .font(.custom("Inter", size: 13).weight(.semibold))
                .foregroundStyle(C.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
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
