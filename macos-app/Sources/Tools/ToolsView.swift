import AppKit
import SwiftUI

struct ToolsView: View {
    @EnvironmentObject var model: Model
    @Environment(\.themeLight) private var themeLight
    @State private var password = ""
    @State private var result = ""

    var body: some View {
        let _ = themeLight
        sub(model.t("more")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    snapshotStrip

                    SettingsSectionLabel(text: model.t("shortcuts"))
                    navGrid

                    SettingsSectionLabel(text: model.t("catalogTools"))
                    catalogCard
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 4)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var connected: Bool { model.runtime["connected"] as? Bool ?? false }
    private var ssid: String { model.runtime["ssid"] as? String ?? "" }
    private var network: String { model.runtime["network"] as? String ?? "" }
    private var tunnel: String { model.runtime["tunnel"] as? String ?? "" }
    private var lanOn: Bool { model.settings["lan_sharing"] as? Bool ?? false }
    private var loggingOn: Bool { model.settings["logging_enabled"] as? Bool ?? true }

    private var heroTint: Color { connected ? C.green : C.cyan }

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
                    Image(systemName: connected ? "lock.shield.fill" : "wrench.and.screwdriver")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(heroTint)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Mix(text: ssid.isEmpty ? model.t("more") : ssid, size: 18, weight: .bold)
                    Mix(text: model.t("toolsHint"), size: 12, color: C.muted)
                        .lineLimit(2)
                    Mix(
                        text: connected ? model.t("connected") : model.t("disconnected"),
                        size: 12,
                        weight: .semibold,
                        color: connected ? C.green : C.muted
                    )
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            if let path = model.runtime["config_path"] as? String, !path.isEmpty {
                pathRow("config.json", path)
            }
            if let path = model.runtime["log_path"] as? String, !path.isEmpty {
                pathRow("core.log", path)
            }
        }
    }

    private var snapshotStrip: some View {
        HStack(spacing: 8) {
            toolTile(
                icon: networkIcon,
                title: model.t("networkWifi"),
                value: networkLabel ?? "—",
                tint: C.cyan
            )
            toolTile(
                icon: "antenna.radiowaves.left.and.right",
                title: model.t("lanSharing"),
                value: lanOn ? model.t("proxyActive") : model.t("diagNone"),
                tint: lanOn ? C.green : C.muted
            )
            toolTile(
                icon: "doc.text",
                title: model.t("logs"),
                value: loggingOn ? logLevelLabel : model.t("diagNone"),
                tint: loggingOn ? C.speedUp : C.muted
            )
        }
    }

    private var networkIcon: String {
        switch network {
        case "wifi": return "wifi"
        case "ethernet": return "cable.connector"
        case "cellular": return "antenna.radiowaves.left.and.right"
        default: return "network"
        }
    }

    private var networkLabel: String? {
        switch network {
        case "wifi": return model.t("demandNetworkWifi")
        case "ethernet": return model.t("demandNetworkEthernet")
        case "cellular": return model.t("demandNetworkCellular")
        case "": return tunnel.isEmpty ? nil : tunnel
        default: return model.t("networkOther")
        }
    }

    private var logLevelLabel: String {
        switch model.settings["loglevel"] as? String ?? "none" {
        case "error": return model.t("logError")
        case "warning": return model.t("logWarning")
        case "info": return model.t("logInfo")
        case "debug": return model.t("logDebug")
        default: return model.t("logNone")
        }
    }

    private var navGrid: some View {
        let items: [(icon: String, title: String, tint: Color, action: () -> Void)] = [
            ("slider.horizontal.3", model.t("advancedTitle"), C.cyan, { model.push("advanced") }),
            ("doc.text", model.t("logs"), C.speedUp, { model.push("logs") }),
            ("stethoscope", model.t("diagnostics"), C.green, { model.push("diagnostics") }),
            ("point.3.connected.trianglepath.dotted", model.t("clashApi"), C.accent, { model.push("clash_status") }),
            ("square.stack.3d.up.fill", model.t("apps"), C.pingWarn, { model.push("apps") }),
            ("bolt.horizontal.circle", model.t("onDemandTitle"), C.cyan, { model.push("on_demand") }),
            ("icloud", model.t("icloudTitle"), C.speedUp, { model.push("backup_settings") }),
            ("antenna.radiowaves.left.and.right", model.t("inbounds"), C.green, { model.push("network_settings") })
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button(action: item.action) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(item.tint.opacity(0.16))
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(item.tint)
                        }
                        .frame(width: 32, height: 32)
                        Mix(text: item.title, size: 13, weight: .semibold)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .background(C.cardElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(C.hairline, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(QuietPressStyle())
            }
        }
    }

    private var catalogCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Mix(text: model.t("filePassword"), size: 12, color: C.muted)
                V2Field(placeholder: "••••••••", text: $password, latin: true, secure: true, icon: "lock.fill")
                HStack(spacing: 8) {
                    SheetActionButton(title: model.t("seal"), icon: "lock.rectangle") { seal() }
                    SheetActionButton(title: model.t("unseal"), icon: "lock.open") { unseal() }
                }
                HStack(spacing: 8) {
                    SheetActionButton(title: model.t("lock"), icon: "lock.fill") { lock(true) }
                    SheetActionButton(title: model.t("unlock"), icon: "lock.open.fill") { lock(false) }
                }
                SheetActionButton(title: model.t("xray"), primary: true, icon: "doc.on.clipboard") {
                    let text = (model.call("xray_json")["data"] as? [String: Any])?["text"] as? String ?? ""
                    ShareKit.copy(text)
                    result = model.t("copied")
                    model.showToast(model.t("copied"), tone: .success)
                }
                if !result.isEmpty {
                    Mix(text: result, size: 13, color: C.muted)
                }
            }
            .padding(14)
        }
    }

    func toolTile(icon: String, title: String, value: String, tint: Color) -> some View {
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

    func pathRow(_ name: String, _ path: String) -> some View {
        Button {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(url.deletingLastPathComponent())
            }
        } label: {
            HStack(spacing: 10) {
                Mix(text: name, size: 12, weight: .semibold, color: C.cyan)
                Mix(text: path, size: 11, color: C.muted)
                    .lineLimit(1)
                    .environment(\.layoutDirection, .leftToRight)
                Spacer(minLength: 0)
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(C.muted)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietPressStyle())
    }

    func seal() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "V2Open.v2open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let response = model.call("seal", ["password": password, "path": url.path])
        result = (response["ok"] as? Bool) == false ? (response["error"] as? String ?? "") : url.lastPathComponent
        if response["ok"] as? Bool == false {
            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
        } else {
            model.showToast(model.t("saved"), tone: .success)
        }
        model.refresh()
    }

    func unseal() {
        let panel = NSOpenPanel()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let response = model.call("unseal", ["password": password, "path": url.path])
        result = (response["ok"] as? Bool) == false ? (response["error"] as? String ?? "") : model.t("imported")
        if response["ok"] as? Bool == false {
            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
        } else {
            model.showToast(model.t("imported"), tone: .success)
        }
        model.refresh()
    }

    func lock(_ locking: Bool) {
        let id = (model.groups.first?["id"] as? String) ?? ""
        let response = model.call(locking ? "lock_group" : "unlock_group", ["id": id, "password": password])
        result = (response["ok"] as? Bool) == false ? (response["error"] as? String ?? "") : (locking ? model.t("lock") : model.t("unlock"))
        if response["ok"] as? Bool == false {
            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
        } else {
            model.showToast(model.t("saved"), tone: .success)
        }
        model.refresh()
    }
}
