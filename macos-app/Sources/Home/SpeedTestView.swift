import SwiftUI

struct SpeedTestView: View {
    @EnvironmentObject var model: Model
    @Environment(\.themeLight) private var themeLight
    @State private var running = false
    @State private var tested = false
    @State private var testPhase = ""
    @State private var liveBps: Int = 0
    @State private var tcpMs = -1
    @State private var icmpMs = -1
    @State private var jitterMs = -1
    @State private var testDown = -1
    @State private var testUp = -1
    @State private var exitIp = ""
    @State private var exitCountry = ""
    @State private var countryCode = ""
    @State private var vpnActive = false
    @AppStorage("speedUseMegabit") private var useMegabit = true

    private var warn: Color { Color(red: 1, green: 0.62, blue: 0.38) }
    private var rateUnit: String { useMegabit ? "Mbps" : "MB/s" }

    private var displayDownBps: Int {
        if running, testPhase == "download" { return liveBps >= 0 ? liveBps : -1 }
        if running, testDown >= 0 { return testDown }
        if tested || testDown >= 0 { return testDown }
        return -1
    }

    private var displayUpBps: Int {
        if running, testPhase == "upload", liveBps > 0 { return liveBps }
        if running, testUp > 0 { return testUp }
        if tested || testUp > 0 { return testUp }
        return -1
    }

    private var gaugeMbps: Double {
        let bps: Int
        if running, testPhase == "upload" {
            bps = liveBps > 0 ? liveBps : (testUp > 0 ? testUp : 0)
        } else if running {
            bps = liveBps > 0 ? liveBps : (testDown > 0 ? testDown : 0)
        } else if tested {
            bps = testDown > 0 ? testDown : (testUp > 0 ? testUp : 0)
        } else if testDown > 0 {
            bps = testDown
        } else if testUp > 0 {
            bps = testUp
        } else {
            return 0
        }
        return max(0, Double(bps)) * 8 / 1_000_000.0
    }

    private var gaugePhase: SpeedGaugePhase {
        if running, testPhase == "upload" { return .upload }
        if running, testPhase == "download" { return .download }
        if running { return .download }
        if tested { return .finished }
        return .idle
    }

    var body: some View {
        let _ = themeLight
        let gaugeIdle = !running

        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: model.t("speed")) {
                HStack(spacing: 8) {
                    Button(action: openSpeedSettings) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 12, weight: .bold))
                            Mix(text: speedMethodShort, size: 11, weight: .bold, color: C.cyan)
                        }
                        .foregroundStyle(C.cyan)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(C.cyan.opacity(0.14))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(C.cyan.opacity(0.22), lineWidth: 1)
                        )
                    }
                    .buttonStyle(QuietPressStyle())
                    .accessibilityLabel(model.t("speedTestSettings"))
                    .help(model.t("speedTestSettings"))
                    SpeedUnitSwitch(
                        useMegabit: $useMegabit,
                        mbps: model.t("unitMbps"),
                        mBps: model.t("unitMBps")
                    )
                }
            }

            speedLatencyStrip
                .padding(.top, PageLayout.headerToContent)

            if tested {
                speedLocationCard
                    .padding(.top, PageLayout.sectionGap)
            } else if !running {
                speedVpnHint
                    .padding(.top, PageLayout.sectionGap)
            }

            Spacer(minLength: 8)

            SpeedTestGoGauge(
                mbps: gaugeMbps,
                idle: gaugeIdle,
                phase: gaugePhase,
                animateLive: running,
                running: running,
                tested: tested,
                unit: rateUnit,
                caption: gaugeIdle
                    ? (tested ? model.t("speedRetry") : model.t("runSpeed"))
                    : speedRunningLabel,
                onGo: { runSpeedTest() }
            )
            .padding(.top, 4)

            Spacer(minLength: 8)

            speedThroughputPanel(
                down: formatSpeedRate(displayDownBps, megabit: useMegabit),
                up: formatSpeedRate(displayUpBps, megabit: useMegabit)
            )
                .padding(.bottom, PageLayout.tabBarClearance + 10)
        }
        .padding(.horizontal, PageLayout.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var speedRunningLabel: String {
        switch testPhase {
        case "download": return model.t("download")
        case "upload": return model.t("upload")
        case "ping": return model.t("pingLabel")
        default: return model.t("testing")
        }
    }

    var speedLatencyStrip: some View {
        let hasPing = icmpMs > 0
        let hasJitter = jitterMs >= 0 && (tested || running)
        let hasTcp = tcpMs > 0
        return HStack(spacing: 0) {
            speedStatCell(
                icon: "waveform.path.ecg",
                title: model.t("pingLabel"),
                value: hasPing ? "\(icmpMs)" : "—",
                unit: hasPing ? "ms" : nil,
                tint: C.cyan
            )
            speedStripDivider
            speedStatCell(
                icon: "chart.line.uptrend.xyaxis",
                title: model.t("jitter"),
                value: hasJitter ? "\(jitterMs)" : "—",
                unit: hasJitter ? "ms" : nil,
                tint: C.speedUp
            )
            speedStripDivider
            speedStatCell(
                icon: "timer",
                title: model.t("latency"),
                value: hasTcp ? "\(tcpMs)" : "—",
                unit: hasTcp ? "ms" : nil,
                tint: C.accent
            )
        }
        .padding(.vertical, 12)
        .background { speedCardFill(radius: 16) }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [C.hairline, C.line],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    var speedStripDivider: some View {
        Rectangle()
            .fill(C.line)
            .frame(width: 1, height: 44)
    }

    func speedStatCell(icon: String, title: String, value: String, unit: String?, tint: Color) -> some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 28, height: 28)
            Mix(text: title, size: 10, weight: .medium, color: C.muted)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.custom("Inter", size: 17).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(C.text)
                if let unit {
                    Text(unit)
                        .font(.custom("Inter", size: 10).weight(.semibold))
                        .foregroundStyle(C.muted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(unit.map { "\(title) \(value) \($0)" } ?? "\(title) \(value)")
    }

    func speedThroughputPanel(down: String, up: String) -> some View {
        let downActive = running && testPhase == "download"
        let upActive = running && testPhase == "upload"
        return HStack(spacing: 8) {
            speedFlowCell(
                icon: "arrow.down",
                title: model.t("download"),
                value: down,
                tint: C.speedDown,
                active: downActive,
                dimmed: running && testPhase == "upload"
            )
            speedFlowCell(
                icon: "arrow.up",
                title: model.t("upload"),
                value: up,
                tint: C.speedUp,
                active: upActive,
                dimmed: running && testPhase == "download"
            )
        }
    }

    func speedFlowCell(icon: String, title: String, value: String, tint: Color, active: Bool, dimmed: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(active ? 0.28 : 0.16))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Mix(text: title, size: 11, weight: .semibold, color: active ? tint : C.muted)
                Text(value)
                    .font(.custom("Inter", size: 16).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(dimmed ? C.muted : C.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                speedCardFill(radius: 16)
                if active {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(0.10))
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    active
                        ? tint.opacity(0.55)
                        : C.hairline,
                    lineWidth: active ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(dimmed ? 0.55 : 1)
        .animation(.easeOut(duration: 0.2), value: active)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    var speedVpnHint: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(C.cyan.opacity(0.16))
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(C.cyan)
            }
            .frame(width: 32, height: 32)
            Mix(text: model.t("speedOfflineHint"), size: PageLayout.captionSize, color: C.muted)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { speedCardFill(radius: 16) }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [C.hairline, C.line],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    var speedLocationCard: some View {
        let statusColor = vpnActive ? C.green : warn
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: vpnActive ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(statusColor)
                Mix(
                    text: vpnActive ? model.t("connected") : model.t("vpnNotProtected"),
                    size: PageLayout.captionSize,
                    weight: .semibold,
                    color: statusColor
                )
                .lineLimit(2)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                speedInfoTile(icon: "globe.americas.fill", title: model.t("exitIp"), value: exitIp.isEmpty ? "—" : exitIp)
                speedInfoTile(
                    icon: "mappin.circle.fill",
                    title: model.t("exitCountry"),
                    value: exitCountry.isEmpty ? "—" : (countryCode.isEmpty ? exitCountry : "\(exitCountry) (\(countryCode))")
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { speedCardFill(radius: 16) }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(statusColor.opacity(vpnActive ? 0.4 : 0.55), lineWidth: 1)
        )
    }

    func speedInfoTile(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(C.cyan)
                Mix(text: title, size: 10, weight: .medium, color: C.muted)
            }
            Text(value)
                .font(.custom("Inter", size: 12).weight(.semibold))
                .foregroundStyle(C.text)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.fieldFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(C.line, lineWidth: 1)
        )
    }

    func speedCardFill(radius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(C.cardElevated)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [C.shine, Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    func applySpeedProgress(_ data: [String: Any]) {
        let phase = data["phase"] as? String ?? testPhase
        testPhase = phase
        liveBps = jsonInt(data["live_bps"])
        let down = jsonInt(data["download_bps"])
        let up = jsonInt(data["upload_bps"])
        if down > 0 || phase == "upload" || phase == "done" {
            if down >= 0 { testDown = down }
        }
        if up > 0 || phase == "done" {
            if up >= 0 { testUp = up }
        }
        let ping = jsonInt(data["icmp_ms"])
        if ping > 0 { icmpMs = ping }
        let tcp = jsonInt(data["tcp_ms"])
        if tcp > 0 {
            tcpMs = tcp
        } else if ping > 0, tcpMs <= 0 {
            tcpMs = ping
        }
        let jit = jsonInt(data["jitter_ms"])
        if jit >= 0 { jitterMs = jit }
    }

    private var speedMethodShort: String {
        switch model.settings["speed_mode"] as? String ?? "http" {
        case "tcp": return model.t("speedModeTcp")
        case "icmp": return model.t("speedModeIcmp")
        default: return model.t("speedModeHttp")
        }
    }

    func openSpeedSettings() {
        if model.current != "speed_settings" {
            model.push("speed_settings")
        }
    }

    func applySpeedFinal(_ data: [String: Any]) {
        tested = true
        tcpMs = jsonInt(data["tcp_ms"])
        icmpMs = jsonInt(data["icmp_ms"])
        jitterMs = jsonInt(data["jitter_ms"])
        testDown = jsonInt(data["download_bps"])
        testUp = jsonInt(data["upload_bps"])
        exitIp = data["exit_ip"] as? String ?? ""
        exitCountry = data["exit_country"] as? String ?? ""
        countryCode = data["country_code"] as? String ?? ""
        vpnActive = data["vpn_active"] as? Bool ?? false
        liveBps = 0
        testPhase = ""
    }

    func runSpeedTest() {
        guard !running else { return }
        running = true
        tested = false
        liveBps = 0
        testPhase = "starting"
        testDown = -1
        testUp = -1
        tcpMs = -1
        icmpMs = -1
        jitterMs = -1
        exitIp = ""
        exitCountry = ""
        countryCode = ""

        Task {
            let start = await Task.detached(priority: .userInitiated) {
                v2RPC(method: "speed_start", args: [:])
            }.value
            if start["ok"] as? Bool != true {
                await MainActor.run {
                    running = false
                    model.showToast(model.t("speedFailed"), tone: .error)
                }
                return
            }

            var finished = false
            while !finished {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let snap = await Task.detached(priority: .userInitiated) {
                    v2RPC(method: "speed_progress", args: [:])
                }.value
                guard snap["ok"] as? Bool == true, let data = snap["data"] as? [String: Any] else {
                    continue
                }
                let phase = data["phase"] as? String ?? ""
                let stillRunning = data["running"] as? Bool ?? false
                await MainActor.run {
                    applySpeedProgress(data)
                }
                if phase == "error" {
                    await MainActor.run {
                        running = false
                        model.showToast(model.t("speedFailed"), tone: .error)
                    }
                    return
                }
                if phase == "done" || !stillRunning {
                    await MainActor.run {
                        applySpeedFinal(data)
                        running = false
                        if vpnActive {
                            model.showToast(model.t("speedDone"), tone: .success)
                        } else {
                            model.showToast(model.t("vpnNotProtected"), tone: .warning)
                        }
                    }
                    finished = true
                }
            }
        }
    }
}

enum SpeedGaugePhase {
    case idle, download, upload, finished
}
