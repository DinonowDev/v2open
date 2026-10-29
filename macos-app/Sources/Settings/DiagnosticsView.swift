import AppKit
import CoreLocation
import CoreWLAN
import SwiftUI

final class WifiProbe: NSObject, CLLocationManagerDelegate {
    static let shared = WifiProbe()
    private let location = CLLocationManager()
    private var asked = false

    func request() {
        asked = true
        location.delegate = self
        location.requestWhenInUseAuthorization()
    }

    var statusKey: String {
        switch location.authorizationStatus {
        case .authorized: return "locationGranted"
        case .denied, .restricted: return "locationDenied"
        default: return "locationNotDetermined"
        }
    }

    func ssid() -> String {
        CWWiFiClient.shared().interface()?.ssid() ?? ""
    }

    func bssid() -> String {
        CWWiFiClient.shared().interface()?.bssid() ?? ""
    }
}

private enum DiagnosticsSheet {
    case proxy, routes, config
}

struct DiagnosticsView: View {
    @EnvironmentObject var model: Model
    @Environment(\.themeLight) private var themeLight
    @State private var data: [String: Any] = [:]
    @State private var sheet: DiagnosticsSheet?

    var body: some View {
        let _ = themeLight
        sub(model.t("diagnostics")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    healthCard
                    snapshotStrip

                    SettingsSectionLabel(text: model.t("loggingSettings"))
                    SettingsCard {
                        SettingsToggleRow(
                            title: model.t("enableLogging"),
                            hint: model.t("loggingHint"),
                            isOn: model.settings["logging_enabled"] as? Bool ?? true
                        ) {
                            model.set("logging_enabled", $0)
                        }
                    }

                    SettingsSectionLabel(text: model.t("networkWifi"))
                    wifiCard

                    SettingsSectionLabel(text: model.t("activeInterfaces"))
                    interfacesCard

                    SettingsSectionLabel(text: model.t("systemProxy"))
                    proxyCard

                    SettingsSectionLabel(text: model.t("systemDns"))
                    dnsCard

                    SettingsSectionLabel(text: model.t("routeTable"))
                    routingCard

                    SettingsSectionLabel(text: model.t("configFiles"))
                    filesCard

                    SheetActionButton(title: model.t("copyDiagnostics"), primary: true, icon: "doc.on.clipboard") { copyReport() }
                    SheetActionButton(title: model.t("openSupport"), icon: "folder") { openSupport() }
                    SettingsNavRow(icon: "point.3.connected.trianglepath.dotted", title: model.t("clashApi"), action: { model.push("clash_status") })
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                WifiProbe.shared.request()
                load()
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                load()
            }
            .overlay {
                if let sheet {
                    DiagnosticsDetailSheet(kind: sheet, data: data, onClose: { self.sheet = nil })
                }
            }
        }
    }

    private var connected: Bool { data["connected"] as? Bool ?? (model.runtime["connected"] as? Bool ?? false) }
    private var phase: String { str("phase").isEmpty ? (model.runtime["phase"] as? String ?? "idle") : str("phase") }
    private var connecting: Bool { phase == "connecting" }

    private var healthTint: Color {
        if connected { return C.green }
        if connecting { return C.pingWarn }
        return C.muted
    }

    private var healthTitle: String {
        if connected { return model.t("connected") }
        if connecting { return model.t("connecting") }
        return model.t("disconnected")
    }

    private var healthCard: some View {
        SettingsCard {
            Button(action: copyReport) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [healthTint.opacity(0.28), healthTint.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: connected ? "checkmark.seal.fill" : (connecting ? "clock.fill" : "wifi.slash"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(healthTint)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Mix(text: healthTitle, size: 18, weight: .bold, color: healthTint)
                        Mix(text: healthSubtitle, size: 12, weight: .medium, color: C.muted)
                            .lineLimit(2)
                        if !str("core").isEmpty {
                            Mix(text: str("core"), size: 11, color: C.muted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(C.muted.opacity(0.7))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(QuietPressStyle())
            .accessibilityLabel("\(healthTitle), \(healthSubtitle)")
        }
    }

    private var healthSubtitle: String {
        let parts = [str("profile"), str("engine"), str("profile_proto")]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? model.t("diagNone") : parts.joined(separator: " · ")
    }

    private var snapshotStrip: some View {
        HStack(spacing: 8) {
            DiagStatusTile(
                icon: networkIcon,
                title: model.t("networkWifi"),
                value: networkKindLabel,
                tint: C.cyan
            )
            DiagStatusTile(
                icon: "point.3.connected.trianglepath.dotted",
                title: model.t("demandInterface"),
                value: displayOrDash(str("interface")),
                tint: C.accent
            )
            DiagStatusTile(
                icon: "arrow.triangle.branch",
                title: model.t("defaultGateway"),
                value: displayOrDash(str("gateway")),
                tint: C.speedUp
            )
        }
    }

    private var networkIcon: String {
        switch str("network") {
        case "wifi": return "wifi"
        case "ethernet": return "cable.connector"
        case "cellular": return "antenna.radiowaves.left.and.right"
        default: return "network"
        }
    }

    private var networkKindLabel: String {
        switch str("network") {
        case "wifi": return model.t("demandNetworkWifi")
        case "ethernet": return model.t("demandNetworkEthernet")
        case "cellular": return model.t("demandNetworkCellular")
        case "": return "—"
        default: return model.t("networkOther")
        }
    }

    private var wifiCard: some View {
        SettingsCard {
            HStack(spacing: 8) {
                DiagCopyTile(title: "SSID", value: ssidValue, tint: C.cyan) { copyValue(ssidValue) }
                DiagCopyTile(title: "BSSID", value: bssidValue, tint: C.speedUp) { copyValue(bssidValue) }
            }
            .padding(12)
            SettingsDivider()
            HStack(spacing: 10) {
                Mix(text: model.t("locationPermission"), size: 13, color: C.muted)
                Spacer()
                Mix(text: model.t(WifiProbe.shared.statusKey), size: 12, weight: .semibold, color: locationTint)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(locationTint.opacity(0.14))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            SettingsDivider()
            SettingsNavRow(
                icon: WifiProbe.shared.statusKey == "locationDenied" ? "gear" : "location",
                title: WifiProbe.shared.statusKey == "locationDenied" ? model.t("locationOpenSettings") : model.t("requestLocation"),
                chevron: false
            ) {
                if WifiProbe.shared.statusKey == "locationDenied" {
                    openLocationSettings()
                } else {
                    WifiProbe.shared.request()
                }
                load()
            }
        }
    }

    private var locationTint: Color {
        switch WifiProbe.shared.statusKey {
        case "locationGranted": return C.green
        case "locationDenied": return C.pingBad
        default: return C.pingWarn
        }
    }

    private var interfacesCard: some View {
        SettingsCard {
            let rows = maps("iface_rows")
            if rows.isEmpty {
                    DiagEmptyState(icon: "network", text: model.t("noInterfaces"))
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        DiagIfaceRow(row: row)
                    }
                }
                .padding(12)
            }
        }
    }

    private var proxyCard: some View {
        let info = dict("proxy_info")
        let active = info["active"] as? Bool ?? proxyActive
        return SettingsCard {
            HStack {
                Mix(text: model.t("systemProxy"), size: 13, color: C.muted)
                Spacer()
                Mix(
                    text: active ? model.t("proxyActive") : model.t("diagNone"),
                    size: 12,
                    weight: .semibold,
                    color: active ? C.green : C.muted
                )
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background((active ? C.green : C.muted).opacity(0.14))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            SettingsDivider()
            proxyLine(model.t("proxyHttp"), proxySummary(info["http"]))
            SettingsDivider()
            proxyLine(model.t("proxyHttps"), proxySummary(info["https"]))
            SettingsDivider()
            proxyLine(model.t("proxySocks"), proxySummary(info["socks"]))
            let pac = proxySummary(info["pac"], urlKey: "url")
            if !pac.isEmpty {
                SettingsDivider()
                proxyLine(model.t("proxyPac"), pac)
            }
            SettingsDivider()
            SettingsNavRow(icon: "doc.text", title: model.t("showSystemProxyDetails")) {
                sheet = .proxy
            }
        }
    }

    private var dnsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                dnsBlock(title: model.t("deviceDns"), values: stringList("dns_servers"), empty: model.t("noDnsServers"))
                DiagKeyValue(title: model.t("activeVpnDns"), value: vpnDnsValue) { copyValue(vpnDnsValue) }
                DiagKeyValue(title: model.t("serverEndpoint"), value: endpointValue) { copyValue(endpointValue) }
                dnsBlock(title: model.t("bootstrapServers"), values: stringList("bootstrap_servers"), empty: model.t("noBootstrap"))
            }
            .padding(14)
        }
    }

    private var routingCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(C.cyan.opacity(0.16))
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(C.cyan)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Mix(text: "\(routeCount) \(model.t("routesSuffix"))", size: 15, weight: .semibold)
                    Mix(
                        text: str("gateway").isEmpty ? model.t("deviceRoutingTable") : "\(model.t("defaultGateway")) · \(str("gateway"))",
                        size: 11,
                        color: C.muted
                    )
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            SettingsDivider()
            SettingsNavRow(icon: "list.bullet.rectangle", title: model.t("showRoutingTable")) {
                sheet = .routes
            }
        }
    }

    private var filesCard: some View {
        let files = maps("files")
        return SettingsCard {
            if files.isEmpty {
                SettingsNavRow(icon: "doc", title: model.t("showConfigFiles")) {
                    sheet = .config
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                        if index > 0 { SettingsDivider() }
                        DiagFileRow(file: file, missingLabel: model.t("fileMissing"), openLabel: model.t("openInFinder"))
                    }
                    SettingsDivider()
                    SettingsNavRow(icon: "doc.text.magnifyingglass", title: model.t("showLiveConfig")) {
                        sheet = .config
                    }
                }
            }
        }
    }

    private var vpnDnsValue: String {
        let name = str("vpn_dns_name")
        let uri = str("vpn_dns")
        if !name.isEmpty && !uri.isEmpty { return "\(name) · \(uri)" }
        return uri.isEmpty ? name : uri
    }

    private var endpointValue: String {
        let endpoint = str("endpoint")
        let proto = str("profile_proto")
        if endpoint.isEmpty { return str("profile") }
        return proto.isEmpty ? endpoint : "\(proto) · \(endpoint)"
    }

    var liveSSID: String {
        let live = WifiProbe.shared.ssid()
        return live.isEmpty ? str("ssid") : live
    }

    var liveBSSID: String {
        WifiProbe.shared.bssid()
    }

    var ssidValue: String {
        if !liveSSID.isEmpty { return liveSSID }
        if WifiProbe.shared.statusKey == "locationGranted" { return model.t("wifiUnavailable") }
        return "—"
    }

    var bssidValue: String {
        if !liveBSSID.isEmpty { return liveBSSID }
        if WifiProbe.shared.statusKey == "locationDenied" { return model.t("locationPermissionDenied") }
        if WifiProbe.shared.statusKey != "locationGranted" { return model.t("locationPermissionRequired") }
        return model.t("wifiUnavailable")
    }

    var proxyActive: Bool {
        if let info = data["proxy_info"] as? [String: Any], let active = info["active"] as? Bool {
            return active
        }
        let text = str("proxy").lowercased()
        return text.contains("yes") || text.contains("enabled") || text.contains(": 1")
    }

    var routeCount: Int {
        let rows = stringList("route_rows")
        if !rows.isEmpty { return rows.count }
        return str("routes").split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    func str(_ key: String) -> String {
        if let s = data[key] as? String { return s }
        return ""
    }

    func dict(_ key: String) -> [String: Any] {
        data[key] as? [String: Any] ?? [:]
    }

    func maps(_ key: String) -> [[String: Any]] {
        data[key] as? [[String: Any]] ?? []
    }

    func stringList(_ key: String) -> [String] {
        if let rows = data[key] as? [String] { return rows.filter { !$0.isEmpty } }
        if let rows = data[key] as? [Any] { return rows.compactMap { $0 as? String }.filter { !$0.isEmpty } }
        return []
    }

    func proxySummary(_ value: Any?, urlKey: String = "summary") -> String {
        let item = value as? [String: Any] ?? [:]
        if let summary = item[urlKey] as? String, !summary.isEmpty { return summary }
        if let summary = item["summary"] as? String, !summary.isEmpty { return summary }
        if item["enabled"] as? Bool == true {
            let host = item["host"] as? String ?? ""
            let port = item["port"] as? String ?? ""
            if !host.isEmpty { return port.isEmpty ? host : "\(host):\(port)" }
        }
        return ""
    }

    func proxyLine(_ title: String, _ value: String) -> some View {
        HStack {
            Mix(text: title, size: 13, color: C.muted)
            Spacer()
            Mix(
                text: value.isEmpty ? model.t("diagNone") : value,
                size: 13,
                weight: .semibold,
                color: value.isEmpty ? C.muted : C.text
            )
            .lineLimit(1)
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onTapGesture { copyValue(value) }
    }

    func dnsBlock(title: String, values: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Mix(text: title, size: 12, weight: .semibold, color: C.muted)
            if values.isEmpty {
                Mix(text: empty, size: 13, color: C.muted)
            } else {
                DiagPillWrap(values: values) { copyValue($0) }
            }
        }
    }

    func displayOrDash(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value
    }

    func copyValue(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "—", value != model.t("diagNone") else { return }
        ShareKit.copy(value)
        model.showToast(model.t("copied"), tone: .success)
    }

    func copyReport() {
        let ifaceText = maps("iface_rows").map { row in
            let name = row["name"] as? String ?? ""
            let ip = row["ipv4"] as? String ?? ""
            let v6 = row["ipv6"] as? String ?? ""
            return [name, ip, v6].filter { !$0.isEmpty }.joined(separator: " ")
        }.joined(separator: "\n")
        let filesText = maps("files").map { file in
            let name = file["name"] as? String ?? ""
            let path = file["path"] as? String ?? ""
            return "\(name)=\(path)"
        }.joined(separator: "\n")
        let text = [
            "status=\(healthTitle)",
            "profile=\(str("profile"))",
            "endpoint=\(endpointValue)",
            "engine=\(str("engine"))",
            "core=\(str("core"))",
            "ssid=\(ssidValue)",
            "bssid=\(bssidValue)",
            "network=\(str("network"))",
            "iface=\(str("interface"))",
            "gateway=\(str("gateway"))",
            "tun=\(dict("tun")["name"] as? String ?? "") \(dict("tun")["ipv4"] as? String ?? "")",
            "hwid=\(str("hwid"))",
            "vpn_dns=\(vpnDnsValue)",
            "device_dns=\(stringList("dns_servers").joined(separator: ", "))",
            "bootstrap=\(stringList("bootstrap_servers").joined(separator: ", "))",
            "proxy=\n\(str("proxy"))",
            "ifaces=\n\(ifaceText)",
            "routes=\n\(str("routes"))",
            "files=\n\(filesText)",
            "live=\n\(str("config"))"
        ].joined(separator: "\n")
        ShareKit.copy(text)
        model.showToast(model.t("copied"), tone: .success)
    }

    func openSupport() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/V2Open", isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    func openLocationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Location",
            "x-apple.systempreferences:com.apple.Location-Settings.extension"
        ]
        for item in candidates {
            if let url = URL(string: item) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    func load() {
        let response = model.call("diagnostics")
        data = response["data"] as? [String: Any] ?? [:]
    }
}

private struct DiagStatusTile: View {
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
                .environment(\.layoutDirection, .leftToRight)
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

private struct DiagCopyTile: View {
    @Environment(\.themeLight) private var themeLight
    var title: String
    var value: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        let _ = themeLight
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Mix(text: title, size: 11, weight: .medium, color: C.muted)
                Text(value)
                    .font(.custom("Inter", size: 13).weight(.semibold))
                    .foregroundStyle(C.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .environment(\.layoutDirection, .leftToRight)
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
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel("\(title) \(value)")
    }
}

private struct DiagKeyValue: View {
    var title: String
    var value: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Mix(text: title, size: 12, weight: .semibold, color: C.muted)
                Mix(text: value.isEmpty ? "—" : value, size: 13, weight: .semibold)
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietPressStyle())
    }
}

private struct DiagPillWrap: View {
    var values: [String]
    var action: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(values, id: \.self) { value in
                Button { action(value) } label: {
                    Text(value)
                        .font(.custom("Inter", size: 11).weight(.semibold))
                        .foregroundStyle(C.cyan)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(C.cyan.opacity(0.12))
                        .clipShape(Capsule())
                        .environment(\.layoutDirection, .leftToRight)
                }
                .buttonStyle(QuietPressStyle())
            }
        }
    }
}

private struct DiagIfaceRow: View {
    @EnvironmentObject var model: Model
    var row: [String: Any]

    private var name: String { row["name"] as? String ?? "" }
    private var kind: String { row["kind"] as? String ?? "" }
    private var ipv4: String { row["ipv4"] as? String ?? "" }
    private var ipv6: String { row["ipv6"] as? String ?? "" }
    private var active: Bool { (row["status"] as? String ?? "active") == "active" }

    private var tint: Color {
        switch kind {
        case "tun": return C.cyan
        case "wifi": return C.green
        default: return C.speedUp
        }
    }

    private var icon: String {
        switch kind {
        case "wifi": return "wifi"
        case "tun": return "lock.shield"
        case "ethernet": return "cable.connector"
        default: return "network"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Mix(text: name, size: 13, weight: .semibold)
                    if kind == "tun" {
                        Mix(text: "TUN", size: 10, weight: .bold, color: C.cyan)
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(C.cyan.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
                if !ipv4.isEmpty {
                    Text(ipv4)
                        .font(.custom("Inter", size: 11).weight(.medium))
                        .foregroundStyle(C.muted)
                        .environment(\.layoutDirection, .leftToRight)
                }
                if !ipv6.isEmpty {
                    Text(ipv6)
                        .font(.custom("Inter", size: 11).weight(.medium))
                        .foregroundStyle(C.muted)
                        .environment(\.layoutDirection, .leftToRight)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Circle()
                .fill(active ? C.green : C.muted)
                .frame(width: 7, height: 7)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(C.overlay.opacity(0.04))
        }
        .opacity(active ? 1 : 0.6)
        .onTapGesture {
            let text = [name, ipv4, ipv6].filter { !$0.isEmpty }.joined(separator: " ")
            ShareKit.copy(text)
            model.showToast(model.t("copied"), tone: .success)
        }
    }
}

private struct DiagFileRow: View {
    var file: [String: Any]
    var missingLabel: String
    var openLabel: String

    private var name: String { file["name"] as? String ?? "" }
    private var path: String { file["path"] as? String ?? "" }
    private var exists: Bool { file["exists"] as? Bool ?? false }
    private var size: UInt64 { jsonUInt(file["size"]) }

    var body: some View {
        Button {
            reveal()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill((exists ? C.cyan : C.muted).opacity(0.16))
                    Image(systemName: name.hasSuffix(".log") ? "doc.text" : "doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(exists ? C.cyan : C.muted)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Mix(text: name, size: 14, weight: .semibold)
                    Mix(
                        text: exists ? formatBytes(size) : missingLabel,
                        size: 11,
                        color: C.muted
                    )
                }
                Spacer(minLength: 6)
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(C.muted.opacity(0.7))
                    .accessibilityLabel(openLabel)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel("\(name), \(exists ? formatBytes(size) : missingLabel)")
    }

    func reveal() {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}

private struct DiagEmptyState: View {
    var icon: String
    var text: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(C.cyan.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(C.cyan)
            }
            .frame(width: 40, height: 40)
            Mix(text: text, size: 13, color: C.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

private struct DiagnosticsDetailSheet: View {
    @EnvironmentObject var model: Model
    var kind: DiagnosticsSheet
    var data: [String: Any]
    var onClose: () -> Void

    var body: some View {
        SheetBackdrop(onDismiss: onClose) {
            SheetCard {
                VStack(alignment: .leading, spacing: 0) {
                    SheetHeader(title: title, subtitle: "", close: onClose, closeLabel: model.t("cancel"))
                    ScrollView {
                        Text(bodyText)
                            .font(.custom("Inter", size: 12).weight(.medium))
                            .foregroundStyle(C.muted)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 12)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .frame(maxHeight: 280)
                    SheetActionButton(title: model.t("copyDiagnostics"), icon: "doc.on.clipboard") {
                        ShareKit.copy(bodyText)
                        model.showToast(model.t("copied"), tone: .success)
                    }
                    SheetActionButton(title: model.t("cancel"), quiet: true, action: onClose)
                }
            }
        }
    }

    var title: String {
        switch kind {
        case .proxy: return model.t("systemProxyDetails")
        case .routes: return model.t("deviceRoutingTable")
        case .config: return model.t("showLiveConfig")
        }
    }

    var bodyText: String {
        switch kind {
        case .proxy:
            if let info = data["proxy_info"] as? [String: Any] {
                let http = summary(info["http"])
                let https = summary(info["https"])
                let socks = summary(info["socks"])
                let pac = ((info["pac"] as? [String: Any])?["url"] as? String) ?? ""
                let formatted = [
                    "HTTP  \(http.isEmpty ? model.t("diagNone") : http)",
                    "HTTPS \(https.isEmpty ? model.t("diagNone") : https)",
                    "SOCKS \(socks.isEmpty ? model.t("diagNone") : socks)",
                    "PAC   \(pac.isEmpty ? model.t("diagNone") : pac)"
                ].joined(separator: "\n")
                let raw = data["proxy"] as? String ?? ""
                return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? formatted : formatted + "\n\n" + raw
            }
            let text = data["proxy"] as? String ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model.t("noSystemProxy") : text
        case .routes:
            if let rows = data["route_rows"] as? [String], !rows.isEmpty {
                return rows.joined(separator: "\n")
            }
            let text = data["routes"] as? String ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : text
        case .config:
            return data["config"] as? String ?? ""
        }
    }

    func summary(_ value: Any?) -> String {
        let item = value as? [String: Any] ?? [:]
        return (item["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
