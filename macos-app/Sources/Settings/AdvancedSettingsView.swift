import AppKit
import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var model: Model
    @Environment(\.themeLight) private var themeLight
    @State private var socksPort = ""
    @State private var httpPort = ""
    @State private var lanIface = ""
    @State private var lanIfaces: [String] = []
    @State private var muxConcurrency = ""
    @State private var cloudKind: CloudSync.AccountKind = .unknown
    @State private var cloudSynced = false
    @State private var cloudItems: [CloudBackupItem] = []

    var body: some View {
        let _ = themeLight
        sub(model.t("advancedTitle")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    snapshotStrip

                    SettingsSectionLabel(text: model.t("proxyShareTitle"))
                    proxyShareCard

                    SettingsSectionLabel(text: model.t("onDemandTitle"))
                    onDemandCard

                    SettingsSectionLabel(text: model.t("icloudTitle"))
                    iCloudCard

                    SettingsSectionLabel(text: model.t("tunnelTitle"))
                    tunnelCard

                    SettingsSectionLabel(text: model.t("connectionSection"))
                    connectionCard

                    SettingsSectionLabel(text: model.t("coreSection"))
                    coreCard
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 4)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                loadFields()
                reloadCloud()
            }
        }
    }

    private var shareProxyOn: Bool {
        (model.settings["socks_enabled"] as? Bool ?? true) && (model.settings["http_enabled"] as? Bool ?? true)
    }

    private var demandOn: Bool { model.settings["on_demand"] as? Bool ?? false }
    private var lanOn: Bool { model.settings["lan_sharing"] as? Bool ?? false }
    private var ruleCount: Int {
        (model.settings["on_demand_text"] as? String ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .count
    }

    private var iCloudShort: String {
        switch cloudKind {
        case .available: return cloudSynced ? model.t("iCloudStatusCloud") : model.t("iCloudAvailable")
        default: return model.t("iCloudStatusLocal")
        }
    }

    private var heroTint: Color {
        if lanOn || demandOn || cloudKind == .available { return C.cyan }
        return C.muted
    }

    private var heroCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [heroTint.opacity(0.28), heroTint.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(heroTint)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Mix(text: model.t("advancedTitle"), size: 18, weight: .bold)
                    Mix(text: model.t("advancedHint"), size: 12, color: C.muted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    private var snapshotStrip: some View {
        HStack(spacing: 8) {
            AdvancedStatusTile(
                icon: "antenna.radiowaves.left.and.right",
                title: model.t("lanSharing"),
                value: lanOn ? model.t("proxyActive") : model.t("diagNone"),
                tint: lanOn ? C.green : C.muted
            )
            AdvancedStatusTile(
                icon: "bolt.horizontal.circle",
                title: model.t("demand"),
                value: demandOn ? "\(ruleCount)" : model.t("diagNone"),
                tint: demandOn ? C.cyan : C.muted
            )
            AdvancedStatusTile(
                icon: "icloud",
                title: model.t("icloud"),
                value: iCloudShort,
                tint: cloudKind == .available ? C.speedUp : C.muted
            )
        }
    }

    private var proxyShareCard: some View {
        SettingsCard {
            Mix(text: model.t("proxyShareDesc"), size: 12, color: C.muted)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            SettingsToggleRow(title: model.t("lanSharing"), hint: model.t("proxyShareDesc"), isOn: lanOn) {
                model.set("lan_sharing", $0)
            }
            SettingsDivider()
            SettingsToggleRow(title: model.t("shareProxy"), isOn: shareProxyOn) {
                model.set("socks_enabled", $0)
                model.set("http_enabled", $0)
            }
            SettingsDivider()
            SettingsSelectRow(
                title: model.t("selectInterface"),
                icon: "cable.connector",
                value: lanIface,
                options: [("", model.t("sortDefault"))] + lanIfaces.map { ($0, $0) }
            ) { lanIface = $0 }
            V2Field(label: model.t("socksPort"), placeholder: "10808", text: $socksPort, latin: true, icon: "number")
                .padding(.horizontal, 14)
            V2Field(label: model.t("httpPort"), placeholder: "10807", text: $httpPort, latin: true, icon: "number")
                .padding(.horizontal, 14)
            SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") {
                model.set("lan_iface", lanIface.trimmingCharacters(in: .whitespaces))
                if let v = Int(socksPort) { model.set("socks_port", v) }
                if let v = Int(httpPort) { model.set("http_port", v) }
                model.showToast(model.t("saved"), tone: .success)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private var onDemandCard: some View {
        SettingsCard {
            Mix(text: model.t("onDemandDesc"), size: 12, color: C.muted)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            SettingsToggleRow(title: model.t("demand"), hint: model.t("onDemandEmpty"), isOn: demandOn) {
                model.set("on_demand", $0)
            }
            SettingsDivider()
            SettingsNavRow(
                icon: "list.bullet.rectangle",
                title: model.t("onDemandRules"),
                value: ruleCount == 0 ? model.t("diagNone") : "\(ruleCount)",
                action: { model.push("on_demand") }
            )
        }
    }

    private var iCloudCard: some View {
        SettingsCard {
            Mix(text: model.t("icloudDesc"), size: 12, color: C.muted)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            HStack {
                Mix(text: model.t("iCloudStatus"), size: 13, color: C.muted)
                Spacer()
                Mix(text: iCloudShort, size: 12, weight: .semibold, color: cloudKind == .available ? C.green : C.muted)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background((cloudKind == .available ? C.green : C.muted).opacity(0.14))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            SettingsDivider()
            SettingsToggleRow(
                title: model.t("icloudAutoSync"),
                hint: model.t("icloudAutoSyncDesc"),
                isOn: model.settings["icloud"] as? Bool ?? false
            ) { model.set("icloud", $0) }
            SettingsDivider()
            SettingsNavRow(icon: "arrow.triangle.2.circlepath", title: model.t("syncServers"), chevron: false) {
                CloudSync.shared.syncServers { ok in
                    model.showToast(ok ? model.t("icloudSyncSuccess") : model.t("failed"), tone: ok ? .success : .error)
                    reloadCloud()
                }
            }
            SettingsDivider()
            SettingsNavRow(icon: "icloud.and.arrow.up", title: model.t("icloudManualBackup"), chevron: false) {
                CloudSync.shared.saveNamed(name: Date().formatted(date: .abbreviated, time: .shortened)) { ok in
                    model.showToast(ok ? model.t("icloudBackupSuccess") : model.t("failed"), tone: ok ? .success : .error)
                    reloadCloud()
                }
            }
            SettingsDivider()
            SettingsNavRow(icon: "clock.arrow.circlepath", title: model.t("backupCatalog"), action: { model.push("backup_settings") })
            SettingsDivider()
            Mix(text: model.t("icloudBackups"), size: 12, weight: .semibold, color: C.muted)
                .padding(.horizontal, 14)
                .padding(.top, 8)
            if cloudItems.isEmpty {
                Mix(text: model.t("noCloudBackups"), size: 12, color: C.muted)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .padding(.top, 6)
            } else {
                ForEach(cloudItems.prefix(6)) { item in
                    SettingsDivider()
                    HStack(alignment: .center, spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(C.cyan.opacity(0.16))
                            Image(systemName: "icloud")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(C.cyan)
                        }
                        .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Mix(text: item.name, size: 13, weight: .semibold)
                                .lineLimit(1)
                            Mix(text: item.created.formatted(date: .abbreviated, time: .shortened), size: 11, color: C.muted)
                        }
                        Spacer(minLength: 0)
                        SettingsChipButton(title: model.t("restore")) {
                            confirmRestore(item)
                        }
                        SettingsChipButton(title: model.t("deleteBackup"), tint: C.pingBad) {
                            confirmDelete(item)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .padding(.bottom, 6)
            }
        }
    }

    private var tunnelCard: some View {
        SettingsCard {
            SettingsToggleRow(
                title: model.t("enforceRoutes"),
                hint: model.t("enforceRoutesHint"),
                isOn: model.settings["enforce_routes"] as? Bool ?? false
            ) { model.set("enforce_routes", $0) }
            SettingsDivider()
            SettingsToggleRow(
                title: model.t("includeAllNetworks"),
                hint: model.t("includeAllHint"),
                isOn: model.settings["include_all_networks"] as? Bool ?? false
            ) { model.set("include_all_networks", $0) }
            SettingsDivider()
            SettingsToggleRow(
                title: model.t("includeLocal"),
                hint: model.t("includeLocalHint"),
                isOn: model.settings["include_local"] as? Bool ?? false
            ) { model.set("include_local", $0) }
            SettingsDivider()
            SettingsToggleRow(
                title: model.t("includeApns"),
                hint: model.t("includeApnsHint"),
                isOn: model.settings["include_apns"] as? Bool ?? false
            ) { model.set("include_apns", $0) }
            SettingsDivider()
            SettingsToggleRow(
                title: model.t("includeCellular"),
                hint: model.t("includeCellularHint"),
                isOn: model.settings["include_cellular_services"] as? Bool ?? false
            ) { model.set("include_cellular_services", $0) }
        }
    }

    private var connectionCard: some View {
        SettingsCard {
            SettingsToggleRow(title: model.t("fake"), hint: model.t("fakeHint"), isOn: model.settings["fake_dns"] as? Bool ?? false) {
                model.set("fake_dns", $0)
            }
            SettingsDivider()
            SettingsToggleRow(title: model.t("kill"), hint: model.t("killHint"), isOn: model.settings["kill_switch"] as? Bool ?? false) {
                model.set("kill_switch", $0)
            }
            SettingsDivider()
            SettingsToggleRow(title: model.t("combiner"), hint: model.t("combinerHint"), isOn: model.settings["net_combiner"] as? Bool ?? false) {
                model.set("net_combiner", $0)
            }
            Mix(text: model.t("combinerNotAvailable"), size: 11, color: C.muted)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
    }

    private var coreCard: some View {
        SettingsCard {
            SettingsToggleRow(title: "Mux", hint: model.t("muxHint"), isOn: model.settings["mux_enabled"] as? Bool ?? false) {
                model.set("mux_enabled", $0)
            }
            if model.settings["mux_enabled"] as? Bool == true {
                V2Field(label: model.t("muxConcurrency"), placeholder: "8", text: $muxConcurrency, latin: true, icon: "number")
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                SheetActionButton(title: model.t("save"), icon: "checkmark") {
                    if let v = Int(muxConcurrency) { model.set("mux_concurrency", v) }
                    model.showToast(model.t("saved"), tone: .success)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
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
            Mix(text: model.t("xhttpHint"), size: 11, color: C.muted)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            SettingsDivider()
            SettingsToggleRow(title: model.t("useXrayTun"), hint: model.t("useXrayTunHint"), isOn: model.settings["use_xray_tun"] as? Bool ?? false) {
                model.set("use_xray_tun", $0)
            }
            SettingsDivider()
            SettingsToggleRow(title: model.t("persistReload"), hint: model.t("persistReloadHint"), isOn: model.settings["persist_tunnel"] as? Bool ?? false) {
                model.set("persist_tunnel", $0)
            }
            SettingsDivider()
            SettingsNavRow(icon: "slider.horizontal.3", title: model.t("xrayAdvanced"), action: { model.push("xray_advanced") })
        }
    }

    func loadFields() {
        socksPort = String(model.settings["socks_port"] as? Int ?? Int(model.settings["socks_port"] as? Double ?? 10808))
        httpPort = String(model.settings["http_port"] as? Int ?? Int(model.settings["http_port"] as? Double ?? 10807))
        lanIface = model.settings["lan_iface"] as? String ?? ""
        muxConcurrency = String(model.settings["mux_concurrency"] as? Int ?? Int(model.settings["mux_concurrency"] as? Double ?? 8))
        let diag = model.call("diagnostics")["data"] as? [String: Any] ?? [:]
        var names: [String] = []
        if let rows = diag["ifaces"] as? [String] {
            names = rows
        }
        if names.isEmpty, let rows = diag["iface_rows"] as? [[String: Any]] {
            names = rows.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
        }
        lanIfaces = names
    }

    func reloadCloud() {
        DispatchQueue.main.async {
            CloudSync.shared.listNamed { cloudItems = $0 }
            CloudSync.shared.account { cloudKind = $0 }
            CloudSync.shared.localSynced { cloudSynced = $0 }
        }
    }

    func confirm(_ title: String, _ body: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: model.t("save"))
        alert.addButton(withTitle: model.t("cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func confirmRestore(_ item: CloudBackupItem) {
        guard confirm(model.t("restore"), model.t("icloudRestoreConfirm")) else { return }
        CloudSync.shared.restoreNamed(id: item.id) { ok in
            model.refresh()
            model.showToast(ok ? model.t("icloudRestoreSuccess") : model.t("failed"), tone: ok ? .success : .error)
        }
    }

    func confirmDelete(_ item: CloudBackupItem) {
        guard confirm(model.t("deleteBackup"), model.t("icloudDeleteConfirm")) else { return }
        CloudSync.shared.deleteNamed(id: item.id) { ok in
            reloadCloud()
            model.showToast(ok ? model.t("icloudDeleteSuccess") : model.t("failed"), tone: ok ? .success : .error)
        }
    }
}

private struct AdvancedStatusTile: View {
    @Environment(\.themeLight) private var themeLight
    var icon: String
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        let _ = themeLight
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Mix(text: title, size: 11, weight: .medium, color: C.muted)
                    .lineLimit(1)
            }
            Mix(text: value, size: 12, weight: .semibold)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(themeLight ? 0.07 : 0.10))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }
}
