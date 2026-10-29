import SwiftUI

struct XrayAdvancedView: View {
    @EnvironmentObject var model: Model
    @State private var policyLevel = ""
    @State private var uplinkOnly = ""
    @State private var downlinkOnly = ""
    @State private var sheetBalancer: [String: Any]?

    private var balancers: [[String: Any]] {
        model.settings["xray_balancers"] as? [[String: Any]] ?? []
    }

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
                    SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") { savePolicy() }

                    SettingsSectionLabel(text: model.t("xrayBalancer"))
                    SettingsCard {
                        if balancers.isEmpty {
                            Mix(text: model.t("empty"), size: 13, color: C.muted)
                                .frame(maxWidth: .infinity)
                                .padding(18)
                        } else {
                            ForEach(Array(balancers.enumerated()), id: \.offset) { index, row in
                                if index > 0 { SettingsDivider(inset: 58) }
                                balancerRow(row)
                            }
                        }
                        SettingsDivider(inset: 58)
                        SettingsNavRow(icon: "plus", title: model.t("addBalancer"), chevron: false) {
                            sheetBalancer = blankBalancer()
                        }
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { loadFields() }
            .sheet(item: Binding(
                get: { sheetBalancer.map { BalancerSheetToken(value: $0) } },
                set: { sheetBalancer = $0?.value }
            )) { token in
                XrayBalancerEditorView(row: token.value) { saved in
                    saveBalancer(saved)
                    sheetBalancer = nil
                } onDelete: { id in
                    deleteBalancer(id)
                    sheetBalancer = nil
                } onCancel: {
                    sheetBalancer = nil
                }
                .environmentObject(model)
            }
        }
    }

    func balancerRow(_ row: [String: Any]) -> some View {
        let tag = row["tag"] as? String ?? ""
        let strategy = row["strategy"] as? String ?? "random"
        let enabled = row["enabled"] as? Bool ?? true
        return Button {
            sheetBalancer = row
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shuffle")
                    .foregroundStyle(enabled ? C.cyan : C.muted)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Mix(text: tag, size: 15, weight: .semibold)
                    Mix(text: strategy, size: 12, color: C.muted)
                }
                Spacer(minLength: 0)
                if row["default"] as? Bool == true {
                    Mix(text: model.t("balancerDefault"), size: 11, color: C.cyan)
                }
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(C.muted.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    func blankBalancer() -> [String: Any] {
        [
            "id": UUID().uuidString.lowercased(),
            "enabled": true,
            "tag": "balancer",
            "strategy": "random",
            "selector": ["proxy"],
            "domains": [] as [String],
            "ips": [] as [String],
            "networks": "tcp,udp",
            "default": balancers.isEmpty
        ]
    }

    func loadFields() {
        policyLevel = stringInt("xray_policy_level", default: 0)
        uplinkOnly = stringInt("xray_policy_uplink_only", default: 0)
        downlinkOnly = stringInt("xray_policy_downlink_only", default: 0)
    }

    func stringInt(_ key: String, default def: Int) -> String {
        if let v = model.settings[key] as? Int { return String(v) }
        if let v = model.settings[key] as? Double { return String(Int(v)) }
        return String(def)
    }

    func savePolicy() {
        let payload: [String: Any] = [
            "xray_policy_level": Int(policyLevel) ?? 0,
            "xray_policy_uplink_only": Int(uplinkOnly) ?? 0,
            "xray_policy_downlink_only": Int(downlinkOnly) ?? 0,
            "xray_policy_stats_user_uplink": model.settings["xray_policy_stats_user_uplink"] as? Bool ?? false,
            "xray_policy_stats_user_downlink": model.settings["xray_policy_stats_user_downlink"] as? Bool ?? false
        ]
        let response = model.call("save_xray_advanced", payload)
        model.mergeState(from: response)
        model.showToast(response["ok"] as? Bool == false ? (response["error"] as? String ?? model.t("failed")) : model.t("saved"), tone: response["ok"] as? Bool == false ? .error : .success)
    }

    func saveBalancer(_ row: [String: Any]) {
        let response = model.call("save_xray_balancer", row)
        model.mergeState(from: response)
        model.showToast(response["ok"] as? Bool == false ? (response["error"] as? String ?? model.t("failed")) : model.t("saved"), tone: response["ok"] as? Bool == false ? .error : .success)
    }

    func deleteBalancer(_ id: String) {
        guard !id.isEmpty else { return }
        let response = model.call("delete_xray_balancer", ["id": id])
        model.mergeState(from: response)
    }
}

private struct BalancerSheetToken: Identifiable {
    let id = UUID()
    var value: [String: Any]
}

struct XrayBalancerEditorView: View {
    @EnvironmentObject var model: Model
    let row: [String: Any]
    var onSave: ([String: Any]) -> Void
    var onDelete: (String) -> Void
    var onCancel: () -> Void

    @State private var id = ""
    @State private var tag = ""
    @State private var strategy = "random"
    @State private var selectorText = "proxy"
    @State private var domainsText = ""
    @State private var ipsText = ""
    @State private var networks = "tcp,udp"
    @State private var enabled = true
    @State private var isDefault = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Mix(text: model.t("editBalancer"), size: 18, weight: .bold)
                V2Field(label: model.t("balancerTag"), placeholder: "balancer", text: $tag, latin: true, icon: "tag")
                SettingsSelectRow(
                    title: model.t("balancerStrategy"),
                    icon: "shuffle",
                    value: strategy,
                    options: [
                        ("random", "random"),
                        ("roundRobin", "roundRobin"),
                        ("leastPing", "leastPing")
                    ]
                ) { strategy = $0 }
                V2Field(label: model.t("balancerSelector"), placeholder: "proxy", text: $selectorText, latin: true, icon: "list.bullet")
                V2Field(label: model.t("balancerDomains"), placeholder: "domain:google.com", text: $domainsText, latin: true, icon: "globe", axis: .vertical)
                V2Field(label: model.t("balancerIps"), placeholder: "geoip:us", text: $ipsText, latin: true, icon: "map", axis: .vertical)
                V2Field(label: model.t("balancerNetworks"), placeholder: "tcp,udp", text: $networks, latin: true, icon: "network")
                SettingsToggleRow(title: model.t("enabled"), isOn: enabled) { enabled = $0 }
                SettingsToggleRow(title: model.t("balancerDefault"), isOn: isDefault) { isDefault = $0 }
                HStack(spacing: 10) {
                    SheetActionButton(title: model.t("cancel"), icon: "xmark") { onCancel() }
                    SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") { commit() }
                }
                if !id.isEmpty {
                    SheetActionButton(title: model.t("deleteRule"), danger: true, icon: "trash") { onDelete(id) }
                }
            }
            .padding(20)
        }
        .frame(width: 380, height: 520)
        .onAppear { load() }
    }

    func load() {
        id = row["id"] as? String ?? ""
        tag = row["tag"] as? String ?? ""
        strategy = row["strategy"] as? String ?? "random"
        if let arr = row["selector"] as? [String] { selectorText = arr.joined(separator: ", ") }
        if let arr = row["domains"] as? [String] { domainsText = arr.joined(separator: "\n") }
        if let arr = row["ips"] as? [String] { ipsText = arr.joined(separator: "\n") }
        networks = row["networks"] as? String ?? "tcp,udp"
        enabled = row["enabled"] as? Bool ?? true
        isDefault = row["default"] as? Bool ?? false
    }

    func commit() {
        let selector = selectorText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let domains = domainsText.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let ips = ipsText.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var payload = row
        payload["id"] = id.isEmpty ? UUID().uuidString.lowercased() : id
        payload["tag"] = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        payload["strategy"] = strategy
        payload["selector"] = selector.isEmpty ? ["proxy"] : selector
        payload["domains"] = domains
        payload["ips"] = ips
        payload["networks"] = networks.trimmingCharacters(in: .whitespacesAndNewlines)
        payload["enabled"] = enabled
        payload["default"] = isDefault
        onSave(payload)
    }
}
