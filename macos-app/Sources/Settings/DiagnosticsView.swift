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
    @State private var data: [String: Any] = [:]
    @State private var sheet: DiagnosticsSheet?

    var body: some View {
        sub(model.t("diagnostics")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionLabel(text: model.t("loggingSettings"))
                    SettingsCard {
                        SettingsToggleRow(title: model.t("enableLogging"), isOn: model.settings["logging_enabled"] as? Bool ?? true) {
                            model.set("logging_enabled", $0)
                        }
                    }

                    SettingsSectionLabel(text: model.t("networkWifi"))
                    SettingsCard {
                        row("SSID", ssidValue)
                        SettingsDivider()
                        row("BSSID", bssidValue)
                        SettingsDivider()
                        row(model.t("locationPermission"), model.t(WifiProbe.shared.statusKey))
                        SettingsDivider()
                        SettingsNavRow(icon: "location", title: model.t("requestLocation"), chevron: false) {
                            if WifiProbe.shared.statusKey == "locationDenied" {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Location") {
                                    NSWorkspace.shared.open(url)
                                }
                            } else {
                                WifiProbe.shared.request()
                            }
                            load()
                        }
                    }

                    SettingsSectionLabel(text: model.t("activeInterfaces"))
                    SettingsCard {
                        let ifaces = stringList("ifaces")
                        if ifaces.isEmpty {
                            Mix(text: model.t("noInterfaces"), size: 13, color: C.muted)
                                .padding(14)
                        } else {
                            ForEach(Array(ifaces.enumerated()), id: \.offset) { index, name in
                                if index > 0 { SettingsDivider() }
                                Mix(text: name, size: 13, weight: .semibold)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                            }
                        }
                    }

                    SettingsSectionLabel(text: model.t("systemProxy"))
                    SettingsCard {
                        row(model.t("systemProxy"), proxyActive ? model.t("proxyActive") : model.t("none"))
                        SettingsDivider()
                        SettingsNavRow(icon: "doc.text", title: model.t("showSystemProxyDetails")) {
                            sheet = .proxy
                        }
                    }

                    SettingsSectionLabel(text: model.t("systemDns"))
                    SettingsCard {
                        Mix(text: model.t("deviceDns"), size: 12, weight: .semibold, color: C.muted)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                        Mix(text: str("dns").isEmpty ? "-" : str("dns"), size: 11, color: C.muted)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                        Mix(text: model.t("activeVpnDns"), size: 12, weight: .semibold, color: C.muted)
                            .padding(.horizontal, 14)
                        Mix(text: str("vpn_dns").isEmpty ? "-" : str("vpn_dns"), size: 13, weight: .semibold)
                            .padding(.horizontal, 14)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                        Mix(text: model.t("serverEndpoint"), size: 12, weight: .semibold, color: C.muted)
                            .padding(.horizontal, 14)
                        Mix(text: endpoint.isEmpty ? "-" : endpoint, size: 12)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.top, 4)
                        Mix(text: model.t("bootstrapServers"), size: 12, weight: .semibold, color: C.muted)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                        Mix(text: bootstrapText, size: 11, color: C.muted)
                            .textSelection(.enabled)
                            .padding(14)
                    }

                    SettingsSectionLabel(text: model.t("routeTable"))
                    SettingsCard {
                        row(model.t("deviceRoutingTable"), "\(routeCount) \(model.t("routesSuffix"))")
                        SettingsDivider()
                        SettingsNavRow(icon: "point.topleft.down.to.point.bottomright.curvepath", title: model.t("showRoutingTable")) {
                            sheet = .routes
                        }
                    }

                    SettingsSectionLabel(text: model.t("configFiles"))
                    SettingsCard {
                        SettingsNavRow(icon: "doc", title: model.t("showConfigFiles")) {
                            sheet = .config
                        }
                    }

                    SheetActionButton(title: model.t("copyDiagnostics"), primary: true, icon: "doc.on.clipboard") { copy() }
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
                if model.current == "diagnostics" { load() }
            }
            .overlay {
                if let sheet {
                    DiagnosticsDetailSheet(kind: sheet, data: data, onClose: { self.sheet = nil })
                }
            }
        }
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
        return "-"
    }

    var bssidValue: String {
        if !liveBSSID.isEmpty { return liveBSSID }
        if WifiProbe.shared.statusKey == "locationDenied" { return model.t("locationPermissionDenied") }
        if WifiProbe.shared.statusKey != "locationGranted" { return model.t("locationPermissionRequired") }
        return model.t("wifiUnavailable")
    }

    var proxyActive: Bool {
        let text = str("proxy").lowercased()
        return text.contains("yes") || text.contains("enabled") || text.contains(": 1")
    }

    var routeCount: Int {
        let rows = stringList("route_rows")
        if !rows.isEmpty { return rows.count }
        return str("routes").split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    var endpoint: String {
        let profile = str("profile")
        let core = str("core")
        return [profile, core].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var bootstrapText: String {
        let rows = stringList("dns_servers")
        if !rows.isEmpty { return rows.joined(separator: "\n") }
        let vpn = str("vpn_dns")
        return vpn.isEmpty ? "-" : vpn
    }

    func str(_ key: String) -> String {
        if let s = data[key] as? String { return s }
        return ""
    }

    func stringList(_ key: String) -> [String] {
        if let rows = data[key] as? [String] { return rows }
        if let rows = data[key] as? [Any] { return rows.compactMap { $0 as? String } }
        return []
    }

    func row(_ title: String, _ value: String) -> some View {
        HStack {
            Mix(text: title, size: 13, color: C.muted)
            Spacer()
            Mix(text: value.isEmpty ? "-" : value, size: 13, weight: .semibold)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    func copy() {
        let text = [
            "ssid=\(ssidValue)",
            "bssid=\(bssidValue)",
            "network=\(str("network"))",
            "iface=\(str("interface"))",
            "core=\(str("core"))",
            "engine=\(str("engine"))",
            "hwid=\(str("hwid"))",
            "config=\(str("config_path"))",
            "xray=\(str("xray_path"))",
            "log=\(str("log_path"))",
            "error=\(str("error_log"))",
            "proxy=\n\(str("proxy"))",
            "routes=\n\(str("routes"))",
            "dns=\n\(str("dns"))",
            "live=\n\(str("config"))"
        ].joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.showToast(model.t("saved"), tone: .success)
    }

    func openSupport() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/V2Open", isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    func load() {
        let response = model.call("diagnostics")
        data = response["data"] as? [String: Any] ?? [:]
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
                        Mix(text: bodyText, size: 12, color: C.muted)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 12)
                    }
                    .frame(maxHeight: 280)
                    SheetActionButton(title: model.t("save"), icon: "doc.on.clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(bodyText, forType: .string)
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
        case .config: return model.t("configFiles")
        }
    }

    var bodyText: String {
        switch kind {
        case .proxy:
            let text = data["proxy"] as? String ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model.t("noSystemProxy") : text
        case .routes:
            if let rows = data["route_rows"] as? [String], !rows.isEmpty {
                return rows.joined(separator: "\n")
            }
            let text = data["routes"] as? String ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : text
        case .config:
            let labeled = [
                ("config.json", data["config_path"] as? String ?? ""),
                ("xray.json", data["xray_path"] as? String ?? ""),
                ("error.log", data["error_log"] as? String ?? ""),
                ("access.log", data["access_log"] as? String ?? ""),
                ("dns.log", data["dns_log"] as? String ?? ""),
                ("core.log", data["log_path"] as? String ?? "")
            ]
            .filter { !$0.1.isEmpty }
            .map { "\($0.0)\n\($0.1)" }
            let live = data["config"] as? String ?? ""
            return (labeled + (live.isEmpty ? [] : [live])).joined(separator: "\n\n")
        }
    }
}
