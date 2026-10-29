import SwiftUI

struct XrayAdvancedView: View {
    @EnvironmentObject var model: Model
    @State private var policyLevel = ""
    @State private var uplinkOnly = ""
    @State private var downlinkOnly = ""
    @State private var balancerTag = ""
    @State private var selectorText = "proxy"

    var body: some View {
        sub(model.t("xrayAdvanced")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionLabel(text: model.t("xrayPolicy"))
                    SettingsCard {
                        V2Field(label: model.t("policyLevel"), placeholder: "0", text: $policyLevel, latin: true, icon: "number")
                            .padding(14)
                        SettingsDivider()
                        V2Field(label: model.t("policyUplinkOnly"), placeholder: "0", text: $uplinkOnly, latin: true, icon: "arrow.up")
                            .padding(14)
                        SettingsDivider()
                        V2Field(label: model.t("policyDownlinkOnly"), placeholder: "0", text: $downlinkOnly, latin: true, icon: "arrow.down")
                            .padding(14)
                        SettingsDivider()
                        SettingsToggleRow(
                            title: model.t("policyStatsUplink"),
                            isOn: model.settings["xray_policy_stats_user_uplink"] as? Bool ?? false
                        ) { model.set("xray_policy_stats_user_uplink", $0) }
                        SettingsDivider()
                        SettingsToggleRow(
                            title: model.t("policyStatsDownlink"),
                            isOn: model.settings["xray_policy_stats_user_downlink"] as? Bool ?? false
                        ) { model.set("xray_policy_stats_user_downlink", $0) }
                    }

                    SettingsSectionLabel(text: model.t("xrayBalancer"))
                    SettingsCard {
                        SettingsToggleRow(
                            title: model.t("balancerEnabled"),
                            isOn: model.settings["xray_balancer_enabled"] as? Bool ?? false
                        ) { model.set("xray_balancer_enabled", $0) }
                        SettingsDivider()
                        V2Field(label: model.t("balancerTag"), placeholder: "balancer", text: $balancerTag, latin: true, icon: "tag")
                            .padding(14)
                        SettingsDivider()
                        SettingsSelectRow(
                            title: model.t("balancerStrategy"),
                            icon: "shuffle",
                            value: model.settings["xray_balancer_strategy"] as? String ?? "random",
                            options: [
                                ("random", "random"),
                                ("roundRobin", "roundRobin"),
                                ("leastPing", "leastPing")
                            ]
                        ) { model.set("xray_balancer_strategy", $0) }
                        SettingsDivider()
                        V2Field(
                            label: model.t("balancerSelector"),
                            placeholder: "proxy",
                            text: $selectorText,
                            latin: true,
                            icon: "list.bullet"
                        )
                        .padding(14)
                    }

                    SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") { saveAll() }
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
        policyLevel = stringInt("xray_policy_level", default: 0)
        uplinkOnly = stringInt("xray_policy_uplink_only", default: 0)
        downlinkOnly = stringInt("xray_policy_downlink_only", default: 0)
        balancerTag = model.settings["xray_balancer_tag"] as? String ?? "balancer"
        if let arr = model.settings["xray_balancer_selector"] as? [String] {
            selectorText = arr.joined(separator: ", ")
        }
    }

    func stringInt(_ key: String, default def: Int) -> String {
        if let v = model.settings[key] as? Int { return String(v) }
        if let v = model.settings[key] as? Double { return String(Int(v)) }
        return String(def)
    }

    func saveAll() {
        let selector = selectorText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let payload: [String: Any] = [
            "xray_policy_level": Int(policyLevel) ?? 0,
            "xray_policy_uplink_only": Int(uplinkOnly) ?? 0,
            "xray_policy_downlink_only": Int(downlinkOnly) ?? 0,
            "xray_balancer_tag": balancerTag.trimmingCharacters(in: .whitespacesAndNewlines),
            "xray_balancer_selector": selector.isEmpty ? ["proxy"] : selector,
            "xray_balancer_enabled": model.settings["xray_balancer_enabled"] as? Bool ?? false,
            "xray_policy_stats_user_uplink": model.settings["xray_policy_stats_user_uplink"] as? Bool ?? false,
            "xray_policy_stats_user_downlink": model.settings["xray_policy_stats_user_downlink"] as? Bool ?? false,
            "xray_balancer_strategy": model.settings["xray_balancer_strategy"] as? String ?? "random"
        ]
        let response = model.call("save_xray_advanced", payload)
        model.mergeState(from: response)
        if response["ok"] as? Bool == false {
            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
        } else {
            model.showToast(model.t("saved"), tone: .success)
        }
    }
}
