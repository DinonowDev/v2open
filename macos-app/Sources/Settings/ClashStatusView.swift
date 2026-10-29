import SwiftUI

struct ClashStatusView: View {
    @EnvironmentObject var model: Model
    @State private var data: [String: Any] = [:]
    @State private var delays: [String: Int] = [:]
    @State private var busy = ""

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
                        let names = proxies.keys.sorted()
                        if names.isEmpty {
                            Mix(text: model.t("empty"), size: 13, color: C.muted)
                                .padding(14)
                        } else {
                            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                                if index > 0 { SettingsDivider() }
                                proxyRow(name: name, item: proxies[name] as? [String: Any] ?? [:])
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
                                connectionRow(item)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        SheetActionButton(title: model.t("update"), primary: true, icon: "arrow.clockwise") { load() }
                        SheetActionButton(title: model.t("closeAll"), danger: true, icon: "xmark.circle") {
                            _ = model.call("clash_close", ["id": ""])
                            load()
                        }
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { load() }
            .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                if model.current == "clash_status" { load() }
            }
        }
    }

    func proxyRow(name: String, item: [String: Any]) -> some View {
        let kind = item["type"] as? String ?? ""
        let now = item["now"] as? String ?? ""
        let all = item["all"] as? [String] ?? []
        let history = item["history"] as? [[String: Any]] ?? []
        let delay = delays[name] ?? jsonInt(history.last?["delay"])
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Mix(text: name, size: 13, weight: .semibold)
                    Mix(text: [kind, now].filter { !$0.isEmpty }.joined(separator: "  ·  "), size: 11, color: C.muted)
                }
                Spacer()
                if delay > 0 {
                    Mix(text: "\(delay) ms", size: 11, weight: .semibold, color: C.cyan)
                }
                Button {
                    busy = name
                    let response = model.call("clash_delay", ["name": name])
                    if let ms = (response["data"] as? [String: Any]).flatMap({ jsonInt($0["delay"]) }), ms > 0 {
                        delays[name] = ms
                    }
                    busy = ""
                } label: {
                    Image(systemName: busy == name ? "hourglass" : "timer")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(C.cyan)
                }
                .buttonStyle(.plain)
            }
            if !all.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(all, id: \.self) { option in
                            Button {
                                _ = model.call("clash_select", ["group": name, "name": option])
                                load()
                            } label: {
                                Mix(text: option, size: 11, weight: option == now ? .bold : .medium, color: option == now ? C.onAccent : C.text)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(option == now ? C.cyan : C.overlay.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    func connectionRow(_ item: [String: Any]) -> some View {
        let metadata = item["metadata"] as? [String: Any] ?? [:]
        let host = metadata["host"] as? String ?? metadata["destinationIP"] as? String ?? "-"
        let id = item["id"] as? String ?? ""
        return HStack {
            Mix(text: "\(host)  ·  \(metadata["network"] as? String ?? "")", size: 12)
            Spacer()
            Button {
                _ = model.call("clash_close", ["id": id])
                load()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(C.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
