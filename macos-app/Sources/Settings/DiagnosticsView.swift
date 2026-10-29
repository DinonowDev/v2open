import AppKit
import CoreLocation
import CoreWLAN
import SwiftUI

final class WifiProbe: NSObject, CLLocationManagerDelegate {
    static let shared = WifiProbe()
    private let location = CLLocationManager()
    private var asked = false

    func request() {
        if asked { return }
        asked = true
        location.delegate = self
        location.requestWhenInUseAuthorization()
    }

    func ssid() -> String {
        CWWiFiClient.shared().interface()?.ssid() ?? ""
    }

    func bssid() -> String {
        CWWiFiClient.shared().interface()?.bssid() ?? ""
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject var model: Model
    @State private var data: [String: Any] = [:]

    var body: some View {
        sub(model.t("diagnostics")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        row(model.t("app"), "V2Open")
                        SettingsDivider()
                        row("SSID", liveSSID)
                        SettingsDivider()
                        row("BSSID", liveBSSID)
                        SettingsDivider()
                        row(model.t("networkSection"), str("network"))
                        SettingsDivider()
                        row("IFACE", str("interface"))
                        SettingsDivider()
                        row("Core", str("core"))
                        SettingsDivider()
                        row("Engine", str("engine"))
                        SettingsDivider()
                        row(model.t("tunnelAlive"), TunnelManager.shared.usingSystem ? model.t("connected") : model.t("disconnected"))
                        SettingsDivider()
                        row(model.t("coreReloaded"), TunnelManager.shared.lastReloaded ? model.t("coreReloaded") : "-")
                        SettingsDivider()
                        row(model.t("connected"), (data["connected"] as? Bool == true) ? "\(model.t("connected")) · \(str("profile"))" : model.t("disconnected"))
                        SettingsDivider()
                        row(model.t("deviceId"), str("hwid"))
                    }

                    SettingsSectionLabel(text: model.t("systemProxy"))
                    SettingsCard {
                        Mix(text: str("proxy").isEmpty ? "-" : str("proxy"), size: 11, color: C.muted)
                            .textSelection(.enabled)
                            .padding(14)
                    }

                    SettingsSectionLabel(text: model.t("bootstrap"))
                    SettingsCard {
                        Mix(text: str("vpn_dns").isEmpty ? "-" : str("vpn_dns"), size: 12, weight: .semibold)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                        Mix(text: str("dns").isEmpty ? "-" : str("dns"), size: 11, color: C.muted)
                            .textSelection(.enabled)
                            .padding(14)
                    }

                    SettingsSectionLabel(text: model.t("addresses"))
                    SettingsCard {
                        let rows = stringList("addresses")
                        if rows.isEmpty {
                            Mix(text: "-", size: 11, color: C.muted)
                                .padding(14)
                        } else {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, line in
                                if index > 0 { SettingsDivider() }
                                Mix(text: line, size: 11, color: C.muted)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                            }
                        }
                    }

                    SettingsSectionLabel(text: model.t("routeTable"))
                    SettingsCard {
                        let rows = stringList("route_rows")
                        if rows.isEmpty {
                            Mix(text: str("routes").isEmpty ? "-" : str("routes"), size: 11, color: C.muted)
                                .textSelection(.enabled)
                                .padding(14)
                        } else {
                            ForEach(Array(rows.prefix(24).enumerated()), id: \.offset) { index, line in
                                if index > 0 { SettingsDivider() }
                                Mix(text: line, size: 11, color: C.muted)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                            }
                        }
                    }

                    SettingsSectionLabel(text: model.t("liveConfig"))
                    SettingsCard {
                        Mix(text: str("config").isEmpty ? "-" : str("config"), size: 11, color: C.muted)
                            .textSelection(.enabled)
                            .padding(14)
                    }

                    SettingsCard {
                        Mix(text: str("config_path"), size: 12, color: C.muted)
                            .textSelection(.enabled)
                            .padding(14)
                        Mix(text: str("xray_path"), size: 12, color: C.muted)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                        Mix(text: str("log_path"), size: 12, color: C.muted)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                    }
                    SheetActionButton(title: model.t("openConfigFile"), icon: "doc") {
                        let path = str("config_path")
                        if !path.isEmpty { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
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
        }
    }

    var liveSSID: String {
        let live = WifiProbe.shared.ssid()
        return live.isEmpty ? str("ssid") : live
    }

    var liveBSSID: String {
        let live = WifiProbe.shared.bssid()
        return live.isEmpty ? "-" : live
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
            "ssid=\(liveSSID)",
            "bssid=\(liveBSSID)",
            "network=\(str("network"))",
            "iface=\(str("interface"))",
            "core=\(str("core"))",
            "engine=\(str("engine"))",
            "hwid=\(str("hwid"))",
            "config=\(str("config_path"))",
            "xray=\(str("xray_path"))",
            "log=\(str("log_path"))",
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
