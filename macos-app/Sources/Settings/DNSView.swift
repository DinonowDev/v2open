import AppKit
import SwiftUI

struct DNSView: View {
    @EnvironmentObject var model: Model
    @State private var remote = ""
    @State private var domestic = ""
    @State private var hosts = ""

    var body: some View {
        sub(model.t("dns")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        SettingsNavRow(icon: "list.bullet.rectangle", title: model.t("dnsServers"), action: { model.push("dns_items") })
                        SettingsDivider(inset: 58)
                        V2Field(label: model.t("remoteDns"), placeholder: "1.1.1.1", text: $remote, latin: true, pasteable: true, icon: "globe")
                            .padding(14)
                        SettingsDivider()
                        V2Field(label: model.t("domesticDns"), placeholder: "223.5.5.5", text: $domestic, latin: true, icon: "server.rack")
                            .padding(14)
                    }
                    SettingsCard {
                        SettingsSelectRow(
                            title: model.t("queryStrategy"),
                            icon: "arrow.triangle.branch",
                            value: model.settings["query_strategy"] as? String ?? "prefer_ipv4",
                            options: [
                                ("prefer_ipv4", "prefer_ipv4"),
                                ("prefer_ipv6", "prefer_ipv6"),
                                ("ipv4_only", "ipv4_only"),
                                ("ipv6_only", "ipv6_only")
                            ]
                        ) { model.set("query_strategy", $0) }
                        SettingsDivider(inset: 58)
                        SettingsSelectRow(
                            title: model.t("dnsSplit"),
                            icon: "globe.americas.fill",
                            value: model.settings["dns_split"] as? String ?? "none",
                            options: [
                                ("none", model.t("dnsSplitNone")),
                                ("cn", "CN"),
                                ("ir", "IR"),
                                ("ru", "RU")
                            ]
                        ) { model.set("dns_split", $0) }
                        SettingsDivider(inset: 58)
                        SettingsSelectRow(
                            title: model.t("dnsFinal"),
                            icon: "arrow.triangle.turn.up.right.diamond",
                            value: model.settings["final"] as? String ?? "proxy",
                            options: [
                                ("proxy", model.t("behaviorProxy")),
                                ("direct", model.t("behaviorDirect"))
                            ]
                        ) { model.set("final", $0) }
                        SettingsDivider(inset: 58)
                        SettingsToggleRow(title: model.t("dnsCache"), isOn: model.settings["dns_cache"] as? Bool ?? true) {
                            model.set("dns_cache", $0)
                        }
                        SettingsDivider(inset: 58)
                        SettingsToggleRow(title: model.t("dnsDisableFallback"), isOn: model.settings["dns_disable_fallback"] as? Bool ?? false) {
                            model.set("dns_disable_fallback", $0)
                        }
                        SettingsDivider(inset: 58)
                        SettingsToggleRow(title: model.t("dnsDisableFallbackIfMatch"), isOn: model.settings["dns_disable_fallback_if_match"] as? Bool ?? false) {
                            model.set("dns_disable_fallback_if_match", $0)
                        }
                    }
                    SettingsSectionLabel(text: model.t("hostsSection"))
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Mix(text: model.t("hostsHint"), size: 12, color: C.muted)
                            V2Field(label: model.t("hostsSection"), placeholder: "domain ip", text: $hosts, latin: true, icon: "list.bullet", axis: .vertical)
                            SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") { saveAll() }
                        }
                        .padding(14)
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { load() }
        }
    }

    func load() {
        remote = model.settings["remote_dns"] as? String ?? ""
        domestic = model.settings["domestic_dns"] as? String ?? ""
        if let map = model.settings["hosts"] as? [String: Any] {
            hosts = map.keys.sorted().compactMap { key in
                guard let val = map[key] else { return nil }
                if let s = val as? String { return "\(key) \(s)" }
                if let arr = val as? [String] { return "\(key) \(arr.joined(separator: " "))" }
                return nil
            }.joined(separator: "\n")
        }
    }

    func saveAll() {
        model.set("remote_dns", remote.trimmingCharacters(in: .whitespacesAndNewlines))
        model.set("domestic_dns", domestic.trimmingCharacters(in: .whitespacesAndNewlines))
        let response = model.call("import_hosts", ["text": hosts])
        if response["ok"] as? Bool == false {
            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
        } else {
            model.refresh()
            model.showToast(model.t("saved"), tone: .success)
        }
    }
}
