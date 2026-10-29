import AppKit
import SwiftUI

struct ToolsView: View {
    @EnvironmentObject var model: Model
    @State private var demand = ""
    @State private var password = ""
    @State private var result = ""
    var body: some View {
        sub(model.t("more")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(C.cyan.opacity(0.16))
                                Image(systemName: "wifi")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(C.cyan)
                            }
                            .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Mix(text: model.runtime["ssid"] as? String ?? "-", size: 15, weight: .semibold)
                                Mix(
                                    text: [model.runtime["network"] as? String, model.runtime["tunnel"] as? String]
                                        .compactMap { $0 }
                                        .filter { !$0.isEmpty }
                                        .joined(separator: "  ·  "),
                                    size: 12,
                                    color: C.muted
                                )
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        VStack(alignment: .leading, spacing: 4) {
                            Mix(text: model.runtime["config_path"] as? String ?? "", size: 11, color: C.muted)
                            Mix(text: model.runtime["log_path"] as? String ?? "", size: 11, color: C.muted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SettingsSectionLabel(text: model.t("advanced"))
                        SettingsCard {
                            SettingsToggleRow(title: model.t("fake"), isOn: model.settings["fake_dns"] as? Bool ?? false) { model.set("fake_dns", $0) }
                            SettingsDivider()
                            SettingsToggleRow(title: model.t("kill"), isOn: model.settings["kill_switch"] as? Bool ?? false) { model.set("kill_switch", $0) }
                            SettingsDivider()
                            SettingsToggleRow(title: model.t("combiner"), hint: model.t("combinerHint"), isOn: model.settings["net_combiner"] as? Bool ?? false) { model.set("net_combiner", $0) }
                            SettingsDivider()
                            SettingsToggleRow(title: model.t("demand"), isOn: model.settings["on_demand"] as? Bool ?? false) { model.set("on_demand", $0) }
                            SettingsDivider()
                            SettingsToggleRow(title: model.t("icloud"), isOn: model.settings["icloud"] as? Bool ?? false) { model.set("icloud", $0) }
                        }
                        SettingsCard {
                            SettingsNavRow(icon: "slider.horizontal.3", title: model.t("xrayAdvanced"), action: { model.push("xray_advanced") })
                        }
                        SettingsSectionLabel(text: model.t("onDemandRules"))
                        OnDemandRulesEditor(text: $demand) {
                            model.set("on_demand_text", demand)
                            model.showToast(model.t("saved"), tone: .success)
                        }
                    }

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            V2Field(label: model.fa ? "رمز" : "Password", placeholder: "••••••••", text: $password, latin: true, secure: true, icon: "lock.fill")
                            HStack(spacing: 8) {
                                SheetActionButton(title: model.t("seal"), icon: "lock.rectangle") { seal() }
                                SheetActionButton(title: model.t("unseal"), icon: "lock.open") { unseal() }
                            }
                            HStack(spacing: 8) {
                                SheetActionButton(title: model.t("lock"), icon: "lock.fill") { lock(true) }
                                SheetActionButton(title: model.t("unlock"), icon: "lock.open.fill") { lock(false) }
                            }
                            SheetActionButton(title: model.t("xray"), icon: "doc.on.clipboard") {
                                let text = (model.call("xray_json")["data"] as? [String: Any])?["text"] as? String ?? ""
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                                result = model.fa ? "JSON کپی شد" : "Xray JSON copied"
                            }
                            if !result.isEmpty {
                                Mix(text: result, size: 13, color: C.muted)
                            }
                        }
                        .padding(14)
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            demand = model.settings["on_demand_text"] as? String ?? ""
        }
    }
    func seal() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "V2Open.v2open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let response = model.call("seal", ["password": password, "path": url.path])
        result = (response["ok"] as? Bool) == false ? (response["error"] as? String ?? "") : url.lastPathComponent
        model.refresh()
    }
    func unseal() {
        let panel = NSOpenPanel()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let response = model.call("unseal", ["password": password, "path": url.path])
        result = (response["ok"] as? Bool) == false ? (response["error"] as? String ?? "") : (model.fa ? "باز شد" : "Opened")
        model.refresh()
    }
    func lock(_ locking: Bool) {
        let id = (model.groups.first?["id"] as? String) ?? ""
        let response = model.call(locking ? "lock_group" : "unlock_group", ["id": id, "password": password])
        result = (response["ok"] as? Bool) == false ? (response["error"] as? String ?? "") : (locking ? model.t("lock") : model.t("unlock"))
        model.refresh()
    }
}

struct OnDemandRulesEditor: View {
    @EnvironmentObject var model: Model
    @Binding var text: String
    var onSave: () -> Void
    @State private var iface = "wifi"
    @State private var ssid = "*"
    @State private var action = "connect"

    private var rows: [String] {
        text.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        SettingsCard {
            if rows.isEmpty {
                Mix(text: model.t("empty"), size: 13, color: C.muted)
                    .frame(maxWidth: .infinity)
                    .padding(14)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, line in
                    if index > 0 { SettingsDivider() }
                    HStack {
                        Mix(text: line, size: 13)
                        Spacer()
                        Button {
                            var next = rows
                            next.remove(at: index)
                            text = next.joined(separator: "\n")
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(C.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            SettingsDivider()
            SettingsSelectRow(title: model.t("demandInterface"), icon: "wifi", value: iface, options: [("wifi", "Wi-Fi"), ("ethernet", "Ethernet"), ("any", "Any")]) { iface = $0 }
            V2Field(label: model.t("demandSsid"), placeholder: "*", text: $ssid, latin: true, icon: "tag")
                .padding(.horizontal, 14)
            SettingsSelectRow(title: model.t("demandAction"), icon: "bolt", value: action, options: [("connect", model.t("connect")), ("disconnect", model.t("disconnect"))]) { action = $0 }
            SheetActionButton(title: model.t("addOnDemand"), icon: "plus") {
                let line = "\(iface),\(ssid.isEmpty ? "*" : ssid),\(action)"
                var next = rows
                next.append(line)
                text = next.joined(separator: "\n")
            }
            .padding(.horizontal, 14)
            SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark", action: onSave)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
    }
}
