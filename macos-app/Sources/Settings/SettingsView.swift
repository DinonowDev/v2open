import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: Model
    @State private var muxConcurrency = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: model.t("settings"))

                VStack(alignment: .leading, spacing: 8) {
                    SettingsSectionLabel(text: model.t("general"))
                    SettingsCard {
                        SettingsSelectRow(
                            title: model.t("language"),
                            icon: "globe",
                            value: model.language,
                            options: LocaleStore.options
                        ) { model.set("language", $0) }
                        SettingsDivider()
                        SettingsSelectRow(
                            title: model.t("mode"),
                            icon: "network",
                            value: model.settings["mode"] as? String ?? "tun",
                            options: [("tun", model.t("vpn")), ("proxy", model.t("proxy"))]
                        ) { model.set("mode", $0) }
                        SettingsDivider()
                        SettingsSelectRow(
                            title: model.t("log"),
                            icon: "text.alignleft",
                            value: model.settings["loglevel"] as? String ?? "none",
                            options: [
                                ("none", model.t("logNone")),
                                ("error", model.t("logError")),
                                ("warning", model.t("logWarning")),
                                ("info", model.t("logInfo")),
                                ("debug", model.t("logDebug"))
                            ]
                        ) { model.set("loglevel", $0) }
                        SettingsDivider()
                        SettingsSelectRow(
                            title: model.t("theme"),
                            icon: "circle.lefthalf.filled",
                            value: model.settings["theme"] as? String ?? "dark",
                            options: [
                                ("dark", model.t("themeDark")),
                                ("light", model.t("themeLight")),
                                ("system", model.t("themeSystem"))
                            ]
                        ) { model.set("theme", $0) }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("glassy"), isOn: model.settings["glassy"] as? Bool ?? false) { model.set("glassy", $0) }
                        SettingsDivider()
                        SettingsSelectRow(
                            title: model.t("connectButtonSize"),
                            icon: "circle",
                            value: model.settings["connect_button_size"] as? String ?? "medium",
                            options: [
                                ("small", model.t("sizeSmall")),
                                ("medium", model.t("sizeMedium")),
                                ("large", model.t("sizeLarge"))
                            ]
                        ) { model.set("connect_button_size", $0) }
                    }
                    SettingsCard {
                        SettingsToggleRow(title: model.t("insecure"), isOn: model.settings["allow_insecure"] as? Bool ?? false) { model.set("allow_insecure", $0) }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("ipv6"), isOn: model.settings["prefer_ipv6"] as? Bool ?? false) { model.set("prefer_ipv6", $0) }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("sleep"), hint: model.t("sleepSub"), isOn: model.settings["stop_on_sleep"] as? Bool ?? true) { model.set("stop_on_sleep", $0) }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("persistReload"), hint: model.t("persistReloadHint"), isOn: model.settings["persist_tunnel"] as? Bool ?? false) { model.set("persist_tunnel", $0) }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("reconnectWake"), hint: model.t("reconnectWakeHint"), isOn: model.settings["reconnect_after_wake"] as? Bool ?? false) { model.set("reconnect_after_wake", $0) }
                        SettingsDivider()
                        SettingsNavRow(icon: "number.square", title: model.t("deviceId"), value: String((model.settings["hwid"] as? String ?? "").prefix(10)), chevron: false) {
                            ShareKit.copy(model.settings["hwid"] as? String ?? "")
                            model.showToast(model.t("saved"), tone: .success)
                        }
                        SettingsDivider()
                        SettingsToggleRow(title: "Mux", isOn: model.settings["mux_enabled"] as? Bool ?? false) { model.set("mux_enabled", $0) }
                        if model.settings["mux_enabled"] as? Bool == true {
                            SettingsDivider()
                            V2Field(label: model.t("muxConcurrency"), placeholder: "8", text: $muxConcurrency, latin: true, icon: "number")
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                            SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") {
                                if let v = Int(muxConcurrency) { model.set("mux_concurrency", v) }
                                model.showToast(model.t("saved"), tone: .success)
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                        }
                    }
                    .onAppear {
                        muxConcurrency = String(model.settings["mux_concurrency"] as? Int ?? Int(model.settings["mux_concurrency"] as? Double ?? 8))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SettingsSectionLabel(text: model.t("configs"))
                    SettingsCard {
                        SettingsToggleRow(
                            title: model.t("throughputTest"),
                            hint: model.t("benchHint"),
                            isOn: model.settings["throughput_test"] as? Bool ?? false
                        ) { model.set("throughput_test", $0) }
                        SettingsDivider()
                        SettingsToggleRow(
                            title: model.t("autoConnectBest"),
                            hint: model.t("autoConnectBestHint"),
                            isOn: model.settings["auto_connect_best"] as? Bool ?? false
                        ) { model.set("auto_connect_best", $0) }
                        SettingsDivider()
                        SettingsToggleRow(
                            title: model.t("smartConnect"),
                            hint: model.t("smartConnectHint"),
                            isOn: model.settings["smart_connect"] as? Bool ?? false
                        ) { model.set("smart_connect", $0) }
                        SettingsDivider()
                        SettingsSelectRow(
                            title: model.t("smartStrategy"),
                            icon: "flag.checkered",
                            value: model.settings["smart_strategy"] as? String ?? "winner",
                            options: [
                                ("winner", model.t("smartWinner")),
                                ("urltest", model.t("smartUrltest"))
                            ]
                        ) { model.set("smart_strategy", $0) }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SettingsSectionLabel(text: model.t("networkSection"))
                    SettingsCard {
                        SettingsNavRow(icon: "arrow.triangle.branch", title: model.t("routing"), action: { model.push("routing") })
                        SettingsDivider(inset: 58)
                        SettingsNavRow(icon: "server.rack", title: model.t("dns"), action: { model.push("dns") })
                        SettingsDivider(inset: 58)
                        SettingsNavRow(icon: "antenna.radiowaves.left.and.right", title: model.t("inbounds"), action: { model.push("network_settings") })
                        SettingsDivider(inset: 58)
                        SettingsNavRow(icon: "point.3.connected.trianglepath.dotted", title: model.t("clashApi"), action: { model.push("clash_status") })
                        SettingsDivider(inset: 58)
                        SettingsNavRow(icon: "square.stack.3d.up.fill", title: model.t("apps"), value: appsModeLabel, action: { model.push("apps") })
                        SettingsDivider(inset: 58)
                        SettingsToggleRow(title: model.t("proxy"), isOn: model.settings["apply_system_proxy"] as? Bool ?? true) { model.set("apply_system_proxy", $0) }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SettingsSectionLabel(text: model.t("dataSection"))
                    SettingsCard {
                    SettingsNavRow(icon: "clock.arrow.circlepath", title: model.t("backup"), action: { model.push("backup_settings") })
                    SettingsDivider(inset: 58)
                    SettingsNavRow(icon: "arrow.counterclockwise", title: model.t("reset"), tint: Color(red: 1, green: 0.72, blue: 0.38), chevron: false) {
                        _ = model.call("reset")
                        model.refresh()
                    }
                    SettingsDivider(inset: 58)
                    SettingsNavRow(icon: "trash", title: model.t("erase"), tint: Color(red: 1, green: 0.36, blue: 0.45), chevron: false) {
                        _ = model.call("erase")
                        model.refresh()
                    }
                    SettingsDivider(inset: 58)
                    SettingsNavRow(icon: "wrench.and.screwdriver", title: model.t("more"), action: { model.push("more") })
                    SettingsDivider(inset: 58)
                    SettingsNavRow(icon: "doc.text", title: model.t("logs"), action: { model.push("logs") })
                    SettingsDivider(inset: 58)
                    SettingsNavRow(icon: "stethoscope", title: model.t("diagnostics"), action: { model.push("diagnostics") })
                    SettingsDivider(inset: 58)
                    SettingsNavRow(icon: "info.circle", title: model.t("about"), action: { model.push("about") })
                    }
                }
            }
            .padding(.horizontal, PageLayout.horizontal)
            .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.trailing, 0, for: .scrollIndicators)
        .background(HairlineScrollInstaller())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var appsModeLabel: String {
        switch model.settings["per_app_mode"] as? String ?? "off" {
        case "include": return model.t("appsOnly")
        case "exclude": return model.t("appsExcept")
        default: return model.t("appsAll")
        }
    }
}
