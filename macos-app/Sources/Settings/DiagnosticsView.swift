import AppKit
import SwiftUI

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
                        row("SSID", str("ssid"))
                        SettingsDivider()
                        row(model.t("networkSection"), str("network"))
                        SettingsDivider()
                        row("IFACE", str("interface"))
                        SettingsDivider()
                        row("Core", str("core"))
                        SettingsDivider()
                        row("Engine", str("engine"))
                        SettingsDivider()
                        row(model.t("connected"), (data["connected"] as? Bool == true) ? "\(model.t("connected")) · \(str("profile"))" : model.t("disconnected"))
                    }

                    SettingsSectionLabel(text: model.t("addresses"))
                    SettingsCard {
                        let rows = data["addresses"] as? [String] ?? []
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
                        let rows = data["route_rows"] as? [String] ?? []
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

                    SettingsSectionLabel(text: model.t("systemDns"))
                    SettingsCard {
                        let rows = data["dns_servers"] as? [String] ?? []
                        if rows.isEmpty {
                            Mix(text: str("dns").isEmpty ? "-" : str("dns"), size: 11, color: C.muted)
                                .textSelection(.enabled)
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
                        Mix(text: str("log_path"), size: 12, color: C.muted)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                    }
                    SheetActionButton(title: model.t("copyDiagnostics"), primary: true, icon: "doc.on.clipboard") { copy() }
                    SheetActionButton(title: model.t("openSupport"), icon: "folder") { openSupport() }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { load() }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                if model.current == "diagnostics" { load() }
            }
        }
    }

    func str(_ key: String) -> String {
        data[key] as? String ?? ""
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
            "ssid=\(str("ssid"))",
            "network=\(str("network"))",
            "iface=\(str("interface"))",
            "core=\(str("core"))",
            "engine=\(str("engine"))",
            "config=\(str("config_path"))",
            "log=\(str("log_path"))",
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
