import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeoAssetsView: View {
    @EnvironmentObject var model: Model
    @State private var geoSource = ""
    @State private var geoipSource = ""
    @State private var importUrl = ""
    @State private var importName = ""
    @State private var showUrlSheet = false
    @State private var busy = ""
    @State private var showRuleSets = false

    var primaryAssets: [[String: Any]] {
        model.geoAssets.filter { asset in
            if (asset["primary"] as? Bool) == true { return true }
            return (asset["builtin"] as? Bool) == false && !isRuleSet(asset)
        }
    }

    var ruleSetAssets: [[String: Any]] {
        model.geoAssets.filter { isRuleSet($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionLabel(text: model.t("geoFilesSource"))
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            V2Field(label: model.t("geositeSource"), placeholder: "v2fly/domain-list-community", text: $geoSource, latin: true, pasteable: true, icon: "globe")
                            V2Field(label: model.t("geoipSource"), placeholder: "v2fly/geoip", text: $geoipSource, latin: true, pasteable: true, icon: "map")
                            SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") {
                                model.set("geo_files_source", geoSource.trimmingCharacters(in: .whitespacesAndNewlines))
                                model.set("geoip_source", geoipSource.trimmingCharacters(in: .whitespacesAndNewlines))
                                model.refresh()
                                model.showToast(model.t("saved"), tone: .success)
                            }
                        }
                        .padding(14)
                    }

                    SettingsSectionLabel(text: model.t("assetsSection"))
                    SettingsCard {
                        if primaryAssets.isEmpty {
                            Mix(text: model.t("empty"), size: 13, color: C.muted)
                                .frame(maxWidth: .infinity)
                                .padding(18)
                        } else {
                            ForEach(Array(primaryAssets.enumerated()), id: \.offset) { index, asset in
                                if index > 0 { SettingsDivider(inset: 58) }
                                assetRow(asset)
                            }
                        }
                    }

                    if !ruleSetAssets.isEmpty {
                        HStack {
                            SettingsSectionLabel(text: model.t("ruleSetsSection"))
                            Spacer()
                            SettingsChipButton(title: showRuleSets ? model.t("hide") : model.t("show"), filled: showRuleSets) {
                                showRuleSets.toggle()
                            }
                        }
                        if showRuleSets {
                            SettingsCard {
                                ForEach(Array(ruleSetAssets.enumerated()), id: \.offset) { index, asset in
                                    if index > 0 { SettingsDivider(inset: 58) }
                                    assetRow(asset)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            if showUrlSheet { urlImportOverlay }
        }
        .onAppear {
            geoSource = model.settings["geo_files_source"] as? String ?? "v2fly/domain-list-community"
            geoipSource = model.settings["geoip_source"] as? String ?? "v2fly/geoip"
        }
    }

    var header: some View {
        HStack(spacing: 12) {
            Button { model.pop() } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(C.cyan)
                    .frame(width: 32, height: 32)
                    .background(C.cyan.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(QuietPressStyle())
            Mix(text: model.t("geoAssets"), size: PageLayout.titleSize, weight: .bold)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Button { importFromFile() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(C.cyan)
                        .frame(width: 32, height: 32)
                        .background(C.cardElevated.opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(QuietPressStyle())
                .accessibilityLabel(model.t("importFromFile"))
                ConfigRowMoreMenu {
                    Button(model.t("importFromFile")) { importFromFile() }
                    Button(model.t("importFromUrl")) {
                        importName = ""
                        importUrl = ""
                        showUrlSheet = true
                    }
                    Button(model.t("updateAll")) { updateAll() }
                }
            }
        }
        .padding(.horizontal, PageLayout.horizontal)
        .padding(.top, PageLayout.top)
        .padding(.bottom, 8)
        .background(WindowMoveHandle())
    }

    var urlImportOverlay: some View {
        SheetBackdrop(onDismiss: { showUrlSheet = false }) {
            SheetCard {
                VStack(alignment: .leading, spacing: 12) {
                    SheetHeader(title: model.t("importFromUrl"), close: { showUrlSheet = false }, closeLabel: model.t("cancel"))
                    V2Field(label: model.t("assetName"), placeholder: "custom.dat", text: $importName, latin: true, icon: "doc")
                    V2Field(label: model.t("assetUrl"), placeholder: "https://", text: $importUrl, latin: true, pasteable: true, icon: "link")
                    SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") {
                        let response = model.call("add_geo_asset", ["name": importName, "url": importUrl])
                        if response["ok"] as? Bool == false {
                            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
                        } else {
                            model.refresh()
                            showUrlSheet = false
                            model.showToast(model.t("imported"), tone: .success)
                        }
                    }
                }
            }
        }
    }

    func isRuleSet(_ asset: [String: Any]) -> Bool {
        (asset["kind"] as? String) == "srs" || ((asset["name"] as? String)?.hasSuffix(".srs") == true)
    }

    func assetRow(_ asset: [String: Any]) -> some View {
        let file = asset["name"] as? String ?? ""
        let exists = asset["exists"] as? Bool ?? false
        let size = asset["size"] as? Int ?? Int(asset["size"] as? Double ?? 0)
        let builtin = asset["builtin"] as? Bool ?? true
        let updated = asset["updated_at"] as? Int ?? Int(asset["updated_at"] as? Double ?? 0)
        let updating = busy == file
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Mix(text: file, size: 15, weight: .semibold)
                Mix(text: subtitle(size: size, exists: exists, updated: updated), size: 12, color: C.muted)
            }
            Spacer()
            if updating {
                ProgressView().controlSize(.small)
            } else {
                SettingsChipButton(title: model.t("updateAsset")) {
                    updateOne(file)
                }
            }
            if !builtin {
                Button {
                    _ = model.call("delete_geo_asset", ["name": file])
                    model.refresh()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.36, blue: 0.45))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(QuietPressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    func updateOne(_ file: String) {
        busy = file
        DispatchQueue.global(qos: .userInitiated).async {
            let response = v2RPC(method: "update_geo_asset", args: ["name": file])
            DispatchQueue.main.async {
                busy = ""
                if response["ok"] as? Bool == false {
                    model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
                } else {
                    model.mergeState(from: response)
                    model.showToast(model.t("imported"), tone: .success)
                }
            }
        }
    }

    func subtitle(size: Int, exists: Bool, updated: Int) -> String {
        if !exists { return model.t("missingAsset") }
        let sizeText = sizeLabel(size)
        if updated <= 0 { return sizeText }
        return "\(sizeText) · \(formatAssetDate(updated))"
    }

    func sizeLabel(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f MB", Double(n) / 1_000_000) }
        if n >= 1000 { return String(format: "%.0f KB", Double(n) / 1000) }
        return "\(n) B"
    }

    func formatAssetDate(_ ts: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: model.fa ? "fa_IR" : "en_US")
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    func importFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let response = model.call("import_geo_asset_file", ["path": url.path, "name": url.lastPathComponent])
        if response["ok"] as? Bool == false {
            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
        } else {
            model.refresh()
            model.showToast(model.t("imported"), tone: .success)
        }
    }

    func updateAll() {
        busy = "all"
        DispatchQueue.global(qos: .userInitiated).async {
            let response = v2RPC(method: "update_all_geo_assets", args: [:])
            DispatchQueue.main.async {
                busy = ""
                if response["ok"] as? Bool == false {
                    model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
                } else {
                    model.mergeState(from: response)
                    model.showToast(model.t("imported"), tone: .success)
                }
            }
        }
    }
}
