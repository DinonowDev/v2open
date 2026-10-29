import SwiftUI
import Combine

struct HomeView: View {
    @EnvironmentObject var model: Model
    @State private var connectedSince: Date?

    var body: some View {
        let runtime = model.runtime
        let connected = runtime["connected"] as? Bool ?? false
        let phase = runtime["phase"] as? String ?? "idle"
        let connecting = phase == "connecting"
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: model.t("app"), subtitle: selectedName, caption: ssidCaption)
                if let error = runtime["error"] as? String, !error.isEmpty {
                    Mix(text: error, size: 13, color: Color(red: 1, green: 0.36, blue: 0.45))
                        .padding(.top, 10)
                }

                VStack(spacing: 14) {
                    if connected {
                        ConnectionStatusPill(text: model.t("connected"))
                        ConnectionTimer(since: connectedSince)
                    }
                    PowerConnectButton(
                        connected: connected,
                        connecting: connecting,
                        action: {
                            if connected { model.disconnectTunnel() }
                            else { model.connectTunnel() }
                        }
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: connected ? 292 : 252)
                .padding(.top, 24)

                if let profile = model.selectedProfile {
                    SelectedConfigCard(profile: profile)
                        .padding(.top, 16)
                }

                HomeStatsGrid(
                    memory: homeMemoryLabel(runtime: runtime),
                    upload: homeTrafficSpeed(runtime: runtime, kind: .upload),
                    uploadTotal: homeTrafficTotal(runtime: runtime, kind: .upload),
                    download: homeTrafficSpeed(runtime: runtime, kind: .download),
                    downloadTotal: homeTrafficTotal(runtime: runtime, kind: .download)
                )
                .padding(.top, PageLayout.headerToContent)
                .padding(.bottom, PageLayout.bottom)
            }
            .padding(.horizontal, PageLayout.horizontal)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard model.runtime["connected"] as? Bool == true else { return }
            let response = model.call("tick")
            if let data = response["data"] as? [String: Any] { model.state = data }
        }
        .onChange(of: connected) { _, now in
            connectedSince = now ? Date() : nil
        }
        .onAppear {
            if connected { connectedSince = Date() }
        }
    }

    private enum HomeTrafficKind { case upload, download }

    private func homeMemoryLabel(runtime: [String: Any]) -> String {
        let bytes = jsonInt(runtime["memory"])
        return bytes > 0 ? amount(bytes) : model.t("zero")
    }

    private func homeTrafficSpeed(runtime: [String: Any], kind: HomeTrafficKind) -> String {
        let speed = kind == .upload ? jsonInt(runtime["upload_speed"]) : jsonInt(runtime["download_speed"])
        return formatBps(speed)
    }

    private func homeTrafficTotal(runtime: [String: Any], kind: HomeTrafficKind) -> String {
        let key = kind == .upload ? "upload_total" : "download_total"
        return formatBytes(jsonUInt(runtime[key]))
    }

    var selectedName: String {
        model.selectedProfile?["remark"] as? String ?? model.t("none")
    }

    private var ssidCaption: String? {
        guard let ssid = model.runtime["ssid"] as? String, !ssid.isEmpty else { return nil }
        return "\(model.t("ssid")): \(ssid)"
    }

    func amount(_ bytes: Int) -> String {
        bytes <= 0 ? model.t("zero") : ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}

struct HomeStatsGrid: View {
    @EnvironmentObject var model: Model
    var memory: String
    var upload: String
    var uploadTotal: String
    var download: String
    var downloadTotal: String

    var body: some View {
        HStack(spacing: 0) {
            HomeStatTile(icon: "memorychip", title: model.t("memory"), value: memory, accent: C.cyan)
            statsDivider
            HomeStatTile(
                icon: "arrow.up",
                title: model.t("upload"),
                value: upload,
                detail: uploadTotal,
                accent: C.speedUp
            )
            statsDivider
            HomeStatTile(
                icon: "arrow.down",
                title: model.t("download"),
                value: download,
                detail: downloadTotal,
                accent: C.speedDown
            )
        }
        .padding(.vertical, 14)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(C.cardElevated)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [C.shine, Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(C.line, lineWidth: 1)
        )
    }

    private var statsDivider: some View {
        Rectangle()
            .fill(C.line)
            .frame(width: 1, height: 62)
    }
}

struct HomeStatTile: View {
    @Environment(\.themeLight) private var themeLight
    var icon: String
    var title: String
    var value: String
    var detail: String? = nil
    var accent: Color

    private var metric: (number: String, unit: String?) {
        guard let space = value.lastIndex(of: " ") else { return (value, nil) }
        let unit = String(value[value.index(after: space)...])
        return (String(value[..<space]), unit.isEmpty ? nil : unit)
    }

    var body: some View {
        let _ = themeLight
        VStack(spacing: 6) {
            Capsule()
                .fill(accent)
                .frame(width: 14, height: 3)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.number)
                    .font(.custom("Inter", size: 17).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(C.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let unit = metric.unit {
                    Text(unit)
                        .font(.custom("Inter", size: 10).weight(.semibold))
                        .foregroundStyle(C.muted)
                        .lineLimit(1)
                }
            }
            Group {
                if let detail {
                    Text(detail)
                        .font(.custom("Inter", size: 11).weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(accent.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Color.clear.frame(height: 13)
                }
            }
            .frame(height: 13)
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accent)
                Mix(text: title, size: 10, weight: .medium, color: C.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.map { "\(title) \(value), \($0)" } ?? "\(title) \(value)")
    }
}

struct ConnectionStatusPill: View {
    var text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(C.lime)
            Mix(text: text, size: 13, weight: .semibold, color: C.lime)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(C.lime.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(C.lime.opacity(0.35), lineWidth: 1))
    }
}

struct ConnectionTimer: View {
    @Environment(\.themeLight) private var themeLight
    var since: Date?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let _ = themeLight
            let elapsed = since.map { context.date.timeIntervalSince($0) } ?? 0
            Text(formatElapsed(elapsed))
                .font(.custom("Inter", size: 34).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(C.text)
        }
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }
}

struct PowerConnectButton: View {
    @EnvironmentObject var model: Model
    @Environment(\.themeLight) private var themeLight
    var connected: Bool
    var connecting: Bool
    var compact = false
    /// Inline power control for the configs floating dock (matches left column height).
    var dock = false
    var action: () -> Void

    private var diameter: CGFloat {
        if dock { return 34 }
        if compact { return 58 }
        return 128
    }
    private var iconSize: CGFloat {
        if dock { return 14 }
        if compact { return 22 }
        return 38
    }
    private var ringCount: Int { dock ? 0 : 3 }
    private var ringStep: CGFloat { dock ? 0 : (compact ? 14 : 22) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: (compact || dock) ? 0 : 10) {
                ZStack {
                    ForEach(0..<ringCount, id: \.self) { ring in
                        Circle()
                            .stroke(
                                (connected ? C.lime : C.muted).opacity(0.22 - Double(ring) * 0.06),
                                lineWidth: 1
                            )
                            .frame(
                                width: diameter + CGFloat(ring + 1) * ringStep,
                                height: diameter + CGFloat(ring + 1) * ringStep
                            )
                    }
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: connected
                                    ? [C.accent, C.accentDeep]
                                    : [C.powerOffTop, C.powerOffBottom],
                                center: .center,
                                startRadius: 2,
                                endRadius: diameter * 0.55
                            )
                        )
                        .frame(width: diameter, height: diameter)
                        .shadow(color: connected ? C.lime.opacity(dock ? 0.35 : 0.55) : .clear, radius: dock ? 4 : (compact ? 8 : 22))
                        .overlay(
                            Circle()
                                .stroke(
                                    (connected ? C.lime : C.overlay).opacity(dock ? 0.35 : (connected ? 0.25 : 0.08)),
                                    lineWidth: dock ? 1 : 1
                                )
                        )
                    if connecting {
                        ProgressView()
                            .controlSize(dock ? .mini : (compact ? .small : .regular))
                            .scaleEffect(dock ? 0.65 : 1)
                            .tint(connected || !themeLight ? .white : C.text)
                    } else {
                        Image(systemName: "power")
                            .font(.system(size: iconSize, weight: .bold))
                            .foregroundStyle(connected || !themeLight ? .white : C.text)
                    }
                }
                .frame(width: dock ? diameter : nil, height: dock ? diameter : nil)
                if !compact && !dock {
                    Mix(
                        text: connecting
                            ? model.t("connecting")
                            : (connected ? model.t("disconnect") : model.t("connect")),
                        size: 15,
                        weight: .semibold,
                        color: connected ? C.lime : C.muted
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(connecting)
        .animation(.easeOut(duration: 0.2), value: connected)
    }
}

struct SpeedUnitSwitch: View {
    @Binding var useMegabit: Bool
    var mbps: String
    var mBps: String
    @Namespace private var unitNS

    var body: some View {
        HStack(spacing: 0) {
            chip(mbps, megabit: true)
            chip(mBps, megabit: false)
        }
        .padding(3)
        .background(C.fieldFill)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(C.line, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func chip(_ title: String, megabit: Bool) -> some View {
        let on = useMegabit == megabit
        return Button {
            withAnimation(.easeOut(duration: 0.16)) { useMegabit = megabit }
        } label: {
            Mix(
                text: title,
                size: 12,
                weight: .bold,
                color: on ? C.onAccent : C.muted
            )
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background {
                if on {
                    Capsule()
                        .fill(LinearGradient(colors: [C.cyan, C.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .matchedGeometryEffect(id: "unitThumb", in: unitNS)
                        .shadow(color: C.cyan.opacity(0.28), radius: 6, y: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : AccessibilityTraits())
    }
}
