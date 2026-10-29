import SwiftUI

struct NetworkSettingsView: View {
    @EnvironmentObject var model: Model
    @State private var socksPort = ""
    @State private var httpPort = ""
    @State private var mtu = ""
    @State private var clashPort = ""
    @State private var memoryLimit = ""

    var body: some View {
        sub(model.t("networkSection")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionLabel(text: model.t("inbounds"))
                    SettingsCard {
                        SettingsToggleRow(title: model.t("socksEnabled"), isOn: model.settings["socks_enabled"] as? Bool ?? true) {
                            model.set("socks_enabled", $0)
                        }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("httpEnabled"), isOn: model.settings["http_enabled"] as? Bool ?? true) {
                            model.set("http_enabled", $0)
                        }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("lanSharing"), isOn: model.settings["lan_sharing"] as? Bool ?? false) {
                            model.set("lan_sharing", $0)
                        }
                    }
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            V2Field(label: model.t("socksPort"), placeholder: "10808", text: $socksPort, latin: true, icon: "number")
                            V2Field(label: model.t("httpPort"), placeholder: "10807", text: $httpPort, latin: true, icon: "number")
                            V2Field(label: "MTU", placeholder: "1500", text: $mtu, latin: true, icon: "arrow.up.arrow.down")
                            V2Field(label: model.t("clashPort"), placeholder: "9097", text: $clashPort, latin: true, icon: "number")
                            SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") { savePorts() }
                        }
                        .padding(14)
                    }

                    SettingsSectionLabel(text: model.t("mtuOptimizer"))
                    SettingsCard {
                        SettingsToggleRow(title: model.t("mtuOptimize"), isOn: model.settings["mtu_optimize"] as? Bool ?? false) {
                            model.set("mtu_optimize", $0)
                        }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("mtuOptimizeOnConnect"), isOn: model.settings["mtu_optimize_on_connect"] as? Bool ?? false) {
                            model.set("mtu_optimize_on_connect", $0)
                        }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("mtuSaveLog"), isOn: model.settings["mtu_save_log"] as? Bool ?? false) {
                            model.set("mtu_save_log", $0)
                        }
                        SettingsDivider()
                        Mix(
                            text: model.t("mtuLastResult") + ": \(model.settings["mtu_last_result"] as? Int ?? Int(model.settings["mtu_last_result"] as? Double ?? 0))",
                            size: 12,
                            color: C.muted
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        SheetActionButton(title: model.t("runMtuOptimize"), primary: true, icon: "waveform.path.ecg") { runMtu() }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                    }

                    SettingsSectionLabel(text: model.t("tunnelOptions"))
                    SettingsCard {
                        SettingsToggleRow(title: model.t("enforceRoutes"), isOn: model.settings["enforce_routes"] as? Bool ?? false) {
                            model.set("enforce_routes", $0)
                        }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("includeLocal"), isOn: model.settings["include_local"] as? Bool ?? false) {
                            model.set("include_local", $0)
                        }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("loggingEnabled"), isOn: model.settings["logging_enabled"] as? Bool ?? true) {
                            model.set("logging_enabled", $0)
                        }
                    }
                    SettingsCard {
                        V2Field(label: model.t("memoryLimit"), placeholder: "30", text: $memoryLimit, latin: true, icon: "memorychip")
                        SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") {
                            if let v = Int(memoryLimit.trimmingCharacters(in: .whitespaces)) {
                                model.set("memory_limit_mb", v)
                                model.showToast(model.t("saved"), tone: .success)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { loadFields() }
        }
    }

    func loadFields() {
        socksPort = String(model.settings["socks_port"] as? Int ?? Int(model.settings["socks_port"] as? Double ?? 10808))
        httpPort = String(model.settings["http_port"] as? Int ?? Int(model.settings["http_port"] as? Double ?? 10807))
        mtu = String(model.settings["mtu"] as? Int ?? Int(model.settings["mtu"] as? Double ?? 1500))
        clashPort = String(model.settings["clash_port"] as? Int ?? Int(model.settings["clash_port"] as? Double ?? 9097))
        memoryLimit = String(model.settings["memory_limit_mb"] as? Int ?? Int(model.settings["memory_limit_mb"] as? Double ?? 30))
    }

    func savePorts() {
        if let v = Int(socksPort) { model.set("socks_port", v) }
        if let v = Int(httpPort) { model.set("http_port", v) }
        if let v = Int(mtu) { model.set("mtu", v) }
        if let v = Int(clashPort) { model.set("clash_port", v) }
        model.showToast(model.t("saved"), tone: .success)
    }

    func runMtu() {
        let response = model.call("optimize_mtu")
        if let data = response["data"] as? [String: Any],
           let state = data["state"] as? [String: Any] {
            model.state = state
        } else {
            model.mergeState(from: response)
        }
        if response["ok"] as? Bool == false {
            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
        } else {
            loadFields()
            model.showToast(model.t("saved"), tone: .success)
        }
    }
}
