import AppKit
import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        sub(model.t("diagnostics")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        row(model.t("app"), "V2Open")
                        SettingsDivider()
                        row("SSID", model.runtime["ssid"] as? String ?? "-")
                        SettingsDivider()
                        row(model.t("networkSection"), model.runtime["network"] as? String ?? "-")
                        SettingsDivider()
                        row("IFACE", model.runtime["interface"] as? String ?? "-")
                        SettingsDivider()
                        row("Core", model.runtime["core"] as? String ?? "-")
                        SettingsDivider()
                        row("DNS", (model.settings["remote_dns"] as? String ?? "-"))
                    }
                    SettingsCard {
                        Mix(text: String(describing: model.runtime["config_path"] ?? ""), size: 12, color: C.muted)
                            .textSelection(.enabled)
                            .padding(14)
                        Mix(text: String(describing: model.runtime["log_path"] ?? ""), size: 12, color: C.muted)
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
            "ssid=\(model.runtime["ssid"] as? String ?? "")",
            "network=\(model.runtime["network"] as? String ?? "")",
            "iface=\(model.runtime["interface"] as? String ?? "")",
            "core=\(model.runtime["core"] as? String ?? "")",
            "dns=\(model.settings["remote_dns"] as? String ?? "")",
            "config=\(model.runtime["config_path"] ?? "")",
            "log=\(model.runtime["log_path"] ?? "")"
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
}
