import SwiftUI

struct ClashStatusView: View {
    @EnvironmentObject var model: Model
    @State private var data: [String: Any] = [:]

    var body: some View {
        sub(model.t("clashApi")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        row("Port", "\(jsonInt(data["port"]))")
                        SettingsDivider()
                        row(model.t("connected"), (data["connected"] as? Bool == true) ? model.t("connected") : model.t("disconnected"))
                        SettingsDivider()
                        row(model.t("upload"), formatBytes(jsonUInt(data["upload_total"])))
                        SettingsDivider()
                        row(model.t("download"), formatBytes(jsonUInt(data["download_total"])))
                    }

                    SettingsSectionLabel(text: model.t("clashProxies"))
                    SettingsCard {
                        let proxies = data["proxies"] as? [String: Any] ?? [:]
                        if proxies.isEmpty {
                            Mix(text: model.t("empty"), size: 13, color: C.muted)
                                .padding(14)
                        } else {
                            ForEach(Array(proxies.keys.sorted().enumerated()), id: \.offset) { index, name in
                                if index > 0 { SettingsDivider() }
                                let item = proxies[name] as? [String: Any] ?? [:]
                                VStack(alignment: .leading, spacing: 4) {
                                    Mix(text: name, size: 13, weight: .semibold)
                                    Mix(text: "\(item["type"] as? String ?? "")  ·  \(item["now"] as? String ?? "")", size: 11, color: C.muted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                            }
                        }
                    }

                    SettingsSectionLabel(text: model.t("clashConnections"))
                    SettingsCard {
                        let rows = data["connections"] as? [[String: Any]] ?? []
                        if rows.isEmpty {
                            Mix(text: model.t("empty"), size: 13, color: C.muted)
                                .padding(14)
                        } else {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, item in
                                if index > 0 { SettingsDivider() }
                                let metadata = item["metadata"] as? [String: Any] ?? [:]
                                let host = metadata["host"] as? String ?? metadata["destinationIP"] as? String ?? "-"
                                Mix(text: "\(host)  ·  \(metadata["network"] as? String ?? "")", size: 12)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                            }
                        }
                    }

                    SheetActionButton(title: model.t("update"), primary: true, icon: "arrow.clockwise") { load() }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { load() }
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

    func load() {
        let response = model.call("clash_status")
        data = response["data"] as? [String: Any] ?? [:]
    }
}
