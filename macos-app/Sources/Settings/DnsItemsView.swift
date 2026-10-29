import SwiftUI

struct DnsItemsView: View {
    @EnvironmentObject var model: Model
    @State private var sheetItem: [String: Any]?

    private var items: [[String: Any]] {
        model.settings["dns_items"] as? [[String: Any]] ?? []
    }

    var body: some View {
        sub(model.t("dnsServers")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionLabel(text: model.t("activeDns"))
                    SettingsCard {
                        activePicker(role: "remote", title: model.t("remoteDns"))
                        SettingsDivider(inset: 58)
                        activePicker(role: "domestic", title: model.t("domesticDns"))
                    }

                    SettingsSectionLabel(text: model.t("dnsServers"))
                    SettingsCard {
                        if items.isEmpty {
                            Mix(text: model.t("empty"), size: 13, color: C.muted)
                                .frame(maxWidth: .infinity)
                                .padding(18)
                        } else {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                if index > 0 { SettingsDivider(inset: 58) }
                                itemRow(item)
                            }
                        }
                        SettingsDivider(inset: 58)
                        SettingsNavRow(icon: "plus", title: model.t("addDnsServer"), chevron: false) {
                            sheetItem = blankItem()
                        }
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .sheet(item: Binding(
                get: { sheetItem.map { DnsItemSheetToken(value: $0) } },
                set: { sheetItem = $0?.value }
            )) { token in
                DnsItemEditorView(item: token.value) { saved in
                    saveItem(saved)
                    sheetItem = nil
                } onDelete: { id in
                    deleteItem(id)
                    sheetItem = nil
                } onCancel: {
                    sheetItem = nil
                }
                .environmentObject(model)
            }
        }
    }

    @ViewBuilder
    func activePicker(role: String, title: String) -> some View {
        let current = role == "domestic"
            ? (model.settings["domestic_dns_id"] as? String ?? "")
            : (model.settings["remote_dns_id"] as? String ?? "")
        SettingsSelectRow(
            title: title,
            icon: "checkmark.circle",
            value: current,
            options: items.compactMap { row in
                guard let id = row["id"] as? String, !id.isEmpty else { return nil }
                let name = row["name"] as? String ?? id
                return (id, name)
            }
        ) { id in
            let response = model.call("set_active_dns", ["role": role, "id": id])
            model.mergeState(from: response)
            if response["ok"] as? Bool == false {
                model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
            }
        }
    }

    func itemRow(_ item: [String: Any]) -> some View {
        let id = item["id"] as? String ?? ""
        let name = item["name"] as? String ?? id
        let kind = item["type"] as? String ?? "udp"
        let server = item["server"] as? String ?? ""
        let enabled = item["enabled"] as? Bool ?? true
        return Button {
            sheetItem = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: kind))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(enabled ? C.cyan : C.muted)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Mix(text: name, size: 15, weight: .semibold)
                    Mix(text: "\(kindLabel(kind)) · \(server)", size: 12, color: C.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(C.muted.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    func icon(for kind: String) -> String {
        switch kind {
        case "https": return "lock.shield"
        case "tls": return "lock"
        default: return "antenna.radiowaves.left.and.right"
        }
    }

    func kindLabel(_ kind: String) -> String {
        switch kind {
        case "https": return "DoH"
        case "tls": return "DoT"
        default: return "UDP"
        }
    }

    func blankItem() -> [String: Any] {
        [
            "id": UUID().uuidString.lowercased(),
            "name": "",
            "type": "https",
            "server": "1.1.1.1",
            "path": "/dns-query",
            "addresses": [] as [String],
            "enabled": true,
            "role": "remote"
        ]
    }

    func saveItem(_ item: [String: Any]) {
        let response = model.call("save_dns_item", item)
        model.mergeState(from: response)
        if response["ok"] as? Bool == false {
            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
        } else {
            model.showToast(model.t("saved"), tone: .success)
        }
    }

    func deleteItem(_ id: String) {
        guard !id.isEmpty else { return }
        let response = model.call("delete_dns_item", ["id": id])
        model.mergeState(from: response)
        if response["ok"] as? Bool == false {
            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
        }
    }
}

private struct DnsItemSheetToken: Identifiable {
    let id = UUID()
    var value: [String: Any]
}

struct DnsItemEditorView: View {
    @EnvironmentObject var model: Model
    let item: [String: Any]
    var onSave: ([String: Any]) -> Void
    var onDelete: (String) -> Void
    var onCancel: () -> Void

    @State private var id = ""
    @State private var name = ""
    @State private var kind = "https"
    @State private var server = ""
    @State private var path = "/dns-query"
    @State private var role = "remote"
    @State private var enabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Mix(text: model.t("editDnsServer"), size: 18, weight: .bold)
            V2Field(label: model.t("name"), placeholder: "Cloudflare", text: $name, icon: "tag")
            SettingsSelectRow(
                title: model.t("dnsType"),
                icon: "list.bullet",
                value: kind,
                options: [("https", "DoH"), ("tls", "DoT"), ("udp", "UDP")]
            ) { kind = $0 }
            V2Field(label: model.t("server"), placeholder: "1.1.1.1", text: $server, latin: true, icon: "server.rack")
            if kind == "https" {
                V2Field(label: model.t("dnsPath"), placeholder: "/dns-query", text: $path, latin: true, icon: "link")
            }
            SettingsSelectRow(
                title: model.t("dnsRole"),
                icon: "arrow.triangle.branch",
                value: role,
                options: [("remote", model.t("remoteDns")), ("domestic", model.t("domesticDns"))]
            ) { role = $0 }
            SettingsToggleRow(title: model.t("enabled"), isOn: enabled) { enabled = $0 }
            HStack(spacing: 10) {
                SheetActionButton(title: model.t("cancel"), icon: "xmark") { onCancel() }
                SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") { commit() }
            }
            if !id.isEmpty {
                SheetActionButton(title: model.t("deleteRule"), danger: true, icon: "trash") {
                    onDelete(id)
                }
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { load() }
    }

    func load() {
        id = item["id"] as? String ?? ""
        name = item["name"] as? String ?? ""
        kind = item["type"] as? String ?? "https"
        server = item["server"] as? String ?? ""
        path = item["path"] as? String ?? "/dns-query"
        role = item["role"] as? String ?? "remote"
        enabled = item["enabled"] as? Bool ?? true
    }

    func commit() {
        var row = item
        row["id"] = id.isEmpty ? UUID().uuidString.lowercased() : id
        row["name"] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        row["type"] = kind
        row["server"] = server.trimmingCharacters(in: .whitespacesAndNewlines)
        row["path"] = path.trimmingCharacters(in: .whitespacesAndNewlines)
        row["role"] = role
        row["enabled"] = enabled
        row["addresses"] = item["addresses"] as? [String] ?? []
        onSave(row)
    }
}
