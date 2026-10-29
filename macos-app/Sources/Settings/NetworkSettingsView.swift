import SwiftUI

struct NetworkSettingsView: View {
    @EnvironmentObject var model: Model
    @State private var socksPort = ""
    @State private var httpPort = ""
    @State private var mtu = ""
    @State private var clashPort = ""
    @State private var memoryLimit = ""
    @State private var minUp = ""
    @State private var maxUp = ""
    @State private var minDown = ""
    @State private var maxDown = ""
    @State private var mtuParallel = ""
    @State private var mtuRetries = ""
    @State private var mtuTimeout = ""
    @State private var speedConcurrency = ""
    @State private var lanIface = ""

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
                        SettingsDivider()
                        V2Field(label: model.t("lanIface"), placeholder: "en0", text: $lanIface, latin: true, icon: "cable.connector")
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                        SheetActionButton(title: model.t("save"), icon: "checkmark") {
                            model.set("lan_iface", lanIface.trimmingCharacters(in: .whitespaces))
                            model.showToast(model.t("saved"), tone: .success)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
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
                        Mix(text: model.t("mtuBounds"), size: 12, color: C.muted)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
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
                        V2Field(label: model.t("minUploadMtu"), placeholder: "38", text: $minUp, latin: true, icon: "arrow.up")
                            .padding(.horizontal, 14)
                        V2Field(label: model.t("maxUploadMtu"), placeholder: "150", text: $maxUp, latin: true, icon: "arrow.up")
                            .padding(.horizontal, 14)
                        V2Field(label: model.t("minDownloadMtu"), placeholder: "100", text: $minDown, latin: true, icon: "arrow.down")
                            .padding(.horizontal, 14)
                        V2Field(label: model.t("maxDownloadMtu"), placeholder: "500", text: $maxDown, latin: true, icon: "arrow.down")
                            .padding(.horizontal, 14)
                        V2Field(label: model.t("mtuParallelism"), placeholder: "16", text: $mtuParallel, latin: true, icon: "square.grid.2x2")
                            .padding(.horizontal, 14)
                        V2Field(label: model.t("mtuRetries"), placeholder: "2", text: $mtuRetries, latin: true, icon: "arrow.clockwise")
                            .padding(.horizontal, 14)
                        V2Field(label: model.t("mtuTimeout"), placeholder: "2", text: $mtuTimeout, latin: true, icon: "clock")
                            .padding(.horizontal, 14)
                        SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") { saveMtuBounds() }
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                        Mix(text: model.t("tunMtuProbe"), size: 12, color: C.muted)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                        SheetActionButton(title: model.t("runMtuOptimize"), primary: true, icon: "waveform.path.ecg") { runMtu() }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                    }

                    SettingsSectionLabel(text: model.t("speedMode"))
                    SettingsCard {
                        SettingsSelectRow(
                            title: model.t("speedMode"),
                            icon: "gauge",
                            value: model.settings["speed_mode"] as? String ?? "http",
                            options: [
                                ("http", model.t("speedModeHttp")),
                                ("tcp", model.t("speedModeTcp")),
                                ("icmp", model.t("speedModeIcmp"))
                            ]
                        ) { model.set("speed_mode", $0) }
                        SettingsDivider()
                        V2Field(label: model.t("speedConcurrency"), placeholder: "2", text: $speedConcurrency, latin: true, icon: "square.stack.3d.up")
                            .padding(.horizontal, 14)
                        SheetActionButton(title: model.t("save"), icon: "checkmark") {
                            if let v = Int(speedConcurrency), v >= 1, v <= 8 { model.set("speed_concurrency", v) }
                            model.showToast(model.t("saved"), tone: .success)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
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
                        SettingsToggleRow(title: model.t("includeAllNetworks"), isOn: model.settings["include_all_networks"] as? Bool ?? false) {
                            model.set("include_all_networks", $0)
                        }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("includeApns"), hint: model.t("includeApnsHint"), isOn: model.settings["include_apns"] as? Bool ?? false) {
                            model.set("include_apns", $0)
                        }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("useXrayTun"), isOn: model.settings["use_xray_tun"] as? Bool ?? false) {
                            model.set("use_xray_tun", $0)
                        }
                        SettingsDivider()
                        SettingsSelectRow(
                            title: model.t("xhttpOpt"),
                            icon: "bolt.horizontal",
                            value: model.settings["xhttp_optimization"] as? String ?? "none",
                            options: [
                                ("none", model.t("xhttpNone")),
                                ("normal", model.t("xhttpNormal")),
                                ("aggressive", model.t("xhttpAggressive"))
                            ]
                        ) { model.set("xhttp_optimization", $0) }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("loggingEnabled"), isOn: model.settings["logging_enabled"] as? Bool ?? true) {
                            model.set("logging_enabled", $0)
                        }
                        SettingsDivider()
                        SettingsNavRow(icon: "arrow.counterclockwise", title: model.t("resetTunnel"), chevron: false) {
                            TunnelManager.shared.resetConfiguration { _ in
                                model.showToast(model.t("saved"), tone: .success)
                            }
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
        minUp = num("min_upload_mtu", 38)
        maxUp = num("max_upload_mtu", 150)
        minDown = num("min_download_mtu", 100)
        maxDown = num("max_download_mtu", 500)
        mtuParallel = num("mtu_test_parallelism", 16)
        mtuRetries = num("mtu_test_retries", 2)
        mtuTimeout = num("mtu_test_timeout", 2)
        speedConcurrency = num("speed_concurrency", 2)
        lanIface = model.settings["lan_iface"] as? String ?? ""
    }

    func num(_ key: String, _ def: Int) -> String {
        if let v = model.settings[key] as? Int { return String(v) }
        if let v = model.settings[key] as? Double { return String(Int(v)) }
        return String(def)
    }

    func saveMtuBounds() {
        if let v = Int(minUp) { model.set("min_upload_mtu", v) }
        if let v = Int(maxUp) { model.set("max_upload_mtu", v) }
        if let v = Int(minDown) { model.set("min_download_mtu", v) }
        if let v = Int(maxDown) { model.set("max_download_mtu", v) }
        if let v = Int(mtuParallel) { model.set("mtu_test_parallelism", v) }
        if let v = Int(mtuRetries) { model.set("mtu_test_retries", v) }
        if let v = Int(mtuTimeout) { model.set("mtu_test_timeout", v) }
        model.showToast(model.t("saved"), tone: .success)
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
