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
                        row(model.t("connected"), (data["connected"] as? Bool == true) ? model.t("connected") : model.t("disconnected"))
                    }
                    block(model.t("routeTable"), str("routes"))
                    block(model.t("systemDns"), str("dns"))
                    block(model.t("liveConfig"), str("config"))
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
                    SheetActionButton(title: model.t("update"), icon: "arrow.clockwise") { load() }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { load() }
        }
    }

    func str(_ key: String) -> String {
        data[key] as? String ?? ""
    }

    func block(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(text: title)
            SettingsCard {
                Mix(text: body.isEmpty ? "-" : body, size: 11, color: C.muted)
                    .textSelection(.enabled)
                    .padding(14)
            }
        }
    }

    func row(_ title: String, _ value: String) -> some View {
        HStack {
            Mix(text: title, size: 13, color: C.muted)
            Spacer()
            Mix(text: value.isEmpty ? "-" : value, size: 13, weight: .semibold)
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
