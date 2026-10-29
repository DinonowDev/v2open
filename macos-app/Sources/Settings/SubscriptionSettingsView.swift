import SwiftUI

struct SubscriptionSettingsView: View {
    @EnvironmentObject var model: Model
    @State private var userAgent = ""
    @State private var speedEndpoint = ""
    @State private var speedTimeout = ""
    @State private var throughputDuration = ""
    @State private var subInterval = ""

    var body: some View {
        sub(model.t("subscriptionSection")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        SettingsToggleRow(title: model.t("sendHwid"), isOn: model.settings["send_hwid"] as? Bool ?? false) {
                            model.set("send_hwid", $0)
                        }
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("subAutoUpdate"), isOn: model.settings["sub_auto_update"] as? Bool ?? false) {
                            model.set("sub_auto_update", $0)
                        }
                        SettingsDivider()
                        V2Field(
                            label: model.t("subAutoInterval"),
                            placeholder: "24",
                            text: $subInterval,
                            latin: true,
                            icon: "clock"
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        Mix(
                            text: model.t("subLastUpdate") + ": \(model.settings["sub_last_auto_update"] as? Int ?? Int(model.settings["sub_last_auto_update"] as? Double ?? 0))",
                            size: 12,
                            color: C.muted
                        )
                        .padding(.horizontal, 14)
                        SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") {
                            if let h = Int(subInterval.trimmingCharacters(in: .whitespaces)), h > 0 {
                                model.set("sub_auto_interval_hours", h)
                                model.showToast(model.t("saved"), tone: .success)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("showAnnouncements"), isOn: model.settings["show_announcements"] as? Bool ?? true) {
                            model.set("show_announcements", $0)
                        }
                    }
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            V2Field(label: model.t("userAgent"), placeholder: "Mozilla/5.0", text: $userAgent, latin: true, pasteable: true, icon: "person.text.rectangle")
                            V2Field(label: model.t("speedEndpoint"), placeholder: "https://", text: $speedEndpoint, latin: true, pasteable: true, icon: "bolt")
                            SettingsSelectRow(
                                title: model.t("speedMode"),
                                icon: "gauge",
                                value: model.settings["speed_mode"] as? String ?? "http",
                                options: [("http", model.t("speedModeHttp")), ("tcp", model.t("speedModeTcp"))]
                            ) { model.set("speed_mode", $0) }
                            V2Field(label: model.t("speedTimeout"), placeholder: "8", text: $speedTimeout, latin: true, icon: "clock")
                            V2Field(label: model.t("throughputDuration"), placeholder: "10", text: $throughputDuration, latin: true, icon: "timer")
                            SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") { save() }
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
        userAgent = model.settings["user_agent"] as? String ?? ""
        speedEndpoint = model.settings["speed_endpoint"] as? String ?? ""
        speedTimeout = String(model.settings["speed_timeout"] as? Int ?? Int(model.settings["speed_timeout"] as? Double ?? 8))
        throughputDuration = String(model.settings["throughput_duration"] as? Int ?? Int(model.settings["throughput_duration"] as? Double ?? 10))
        subInterval = String(model.settings["sub_auto_interval_hours"] as? Int ?? Int(model.settings["sub_auto_interval_hours"] as? Double ?? 24))
    }

    func save() {
        model.set("user_agent", userAgent.trimmingCharacters(in: .whitespacesAndNewlines))
        model.set("speed_endpoint", speedEndpoint.trimmingCharacters(in: .whitespacesAndNewlines))
        if let v = Int(speedTimeout) { model.set("speed_timeout", v) }
        if let v = Int(throughputDuration) { model.set("throughput_duration", v) }
        model.showToast(model.t("saved"), tone: .success)
    }
}
