import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    @EnvironmentObject var model: Model
    @State private var renameId = ""
    @State private var renameText = ""
    @State private var packagePassword = ""
    @State private var allowForeign = false
    @State private var shareNote = ""
    @State private var allowedIds = ""
    @State private var expiresAt = ""
    @State private var cloudName = ""
    @State private var cloudItems: [CloudBackupItem] = []

    var body: some View {
        sub(model.t("backup")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        V2Field(label: model.t("filePassword"), placeholder: "••••••••", text: $packagePassword, latin: true, secure: true, icon: "key.fill")
                            .padding(14)
                        Mix(text: model.t("v2boxPasswordHint"), size: 11, color: C.muted)
                            .padding(.horizontal, 14)
                        V2Field(label: model.t("shareNote"), placeholder: "", text: $shareNote, icon: "text.quote")
                            .padding(.horizontal, 14)
                        V2Field(label: model.t("allowedIds"), placeholder: "id1,id2", text: $allowedIds, latin: true, icon: "person.crop.circle")
                            .padding(.horizontal, 14)
                        V2Field(label: model.t("expiresAt"), placeholder: "unix", text: $expiresAt, latin: true, icon: "calendar")
                            .padding(.horizontal, 14)
                        SettingsToggleRow(title: model.t("allowForeignDevice"), isOn: allowForeign) { allowForeign = $0 }
                            .padding(.bottom, 6)
                    }
                    SettingsCard {
                        SettingsNavRow(icon: "square.and.arrow.up", title: model.t("backupNow"), chevron: false) {
                            _ = model.call("backup")
                            model.refresh()
                            model.showToast(model.t("saved"), tone: .success)
                        }
                        SettingsDivider(inset: 58)
                        SettingsNavRow(icon: "square.and.arrow.up.on.square", title: model.t("exportPackage"), chevron: false) {
                            exportPackage()
                        }
                        SettingsDivider(inset: 58)
                        SettingsNavRow(icon: "square.and.arrow.down", title: model.t("importPackage"), chevron: false) {
                            importPackage()
                        }
                        SettingsDivider(inset: 58)
                        SettingsNavRow(icon: "tray.and.arrow.down", title: model.t("importBackup"), chevron: false) {
                            importBackup()
                        }
                    }
                    if model.backups.isEmpty {
                        SettingsCard {
                            Mix(text: model.t("empty"), size: 13, color: C.muted)
                                .frame(maxWidth: .infinity)
                                .padding(18)
                        }
                    } else {
                        SettingsCard {
                            ForEach(Array(model.backups.enumerated()), id: \.offset) { index, item in
                                if index > 0 { SettingsDivider(inset: 58) }
                                backupRow(item)
                            }
                        }
                    }
                    SettingsSectionLabel(text: model.t("icloud"))
                    SettingsCard {
                        V2Field(label: model.t("cloudNamed"), placeholder: "mac-home", text: $cloudName, icon: "icloud")
                            .padding(14)
                        SheetActionButton(title: model.t("backupNow"), primary: true, icon: "icloud.and.arrow.up") {
                            let name = cloudName.isEmpty ? Date().description : cloudName
                            CloudSync.shared.saveNamed(name: name) { ok in
                                model.showToast(ok ? model.t("saved") : model.t("failed"), tone: ok ? .success : .error)
                                reloadCloud()
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                        Mix(text: model.t("autoIcloud"), size: 11, color: C.muted)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                    }
                    if !cloudItems.isEmpty {
                        SettingsCard {
                            ForEach(Array(cloudItems.enumerated()), id: \.offset) { index, item in
                                if index > 0 { SettingsDivider() }
                                VStack(alignment: .leading, spacing: 8) {
                                    Mix(text: item.name, size: 15, weight: .semibold)
                                    Mix(text: item.created.formatted(), size: 11, color: C.muted)
                                    HStack {
                                        SettingsChipButton(title: model.t("restore")) {
                                            CloudSync.shared.restoreNamed(id: item.id) { ok in
                                                model.refresh()
                                                model.showToast(ok ? model.t("imported") : model.t("failed"), tone: ok ? .success : .error)
                                            }
                                        }
                                        SettingsChipButton(title: model.t("deleteBackup")) {
                                            CloudSync.shared.deleteNamed(id: item.id) { _ in reloadCloud() }
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                        }
                    }
                    if !renameId.isEmpty {
                        SettingsCard {
                            V2Field(label: model.t("renameBackup"), placeholder: "", text: $renameText, icon: "pencil")
                                .padding(14)
                            SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") {
                                _ = model.call("rename_backup", ["id": renameId, "name": renameText])
                                renameId = ""
                                model.refresh()
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                        }
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { reloadCloud() }
        }
    }

    func reloadCloud() {
        CloudSync.shared.listNamed { cloudItems = $0 }
    }

    func backupRow(_ item: [String: Any]) -> some View {
        let id = item["id"] as? String ?? ""
        let name = item["name"] as? String ?? id
        return VStack(alignment: .leading, spacing: 8) {
            Mix(text: name, size: 15, weight: .semibold)
            Mix(text: id, size: 11, color: C.muted).lineLimit(1)
            HStack(spacing: 8) {
                SettingsChipButton(title: model.t("restore")) {
                    _ = model.call("restore", ["id": id])
                    model.refresh()
                    model.showToast(model.t("imported"), tone: .success)
                }
                SettingsChipButton(title: model.t("renameBackup")) {
                    renameId = id
                    renameText = name
                }
                SettingsChipButton(title: model.t("exportBackup")) { exportBackup(id: id) }
                SettingsChipButton(title: model.t("deleteBackup")) {
                    _ = model.call("delete_backup", ["id": id])
                    model.refresh()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    func exportBackup(id: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "V2Open-backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let response = model.call("export_backup", ["id": id, "path": url.path])
        if response["ok"] as? Bool == false {
            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
        } else {
            model.showToast(model.t("saved"), tone: .success)
        }
    }

    func exportPackage() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "V2Open.v2box"
        panel.allowedContentTypes = [UTType(filenameExtension: "v2box") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var args: [String: Any] = ["path": url.path, "password": packagePassword, "note": shareNote, "allowed_ids": allowedIds]
        if let n = UInt64(expiresAt.trimmingCharacters(in: .whitespaces)) { args["expires_at"] = n }
        let response = model.call("export_package", args)
        model.showToast(response["ok"] as? Bool == false ? (response["error"] as? String ?? model.t("failed")) : model.t("saved"), tone: response["ok"] as? Bool == false ? .error : .success)
    }

    func importPackage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "v2box") ?? .data, .json, .item]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let response = model.call("import_package", ["path": url.path, "password": packagePassword, "allow_foreign": allowForeign])
        model.mergeState(from: response)
        model.showToast(response["ok"] as? Bool == false ? (response["error"] as? String ?? model.t("failed")) : model.t("imported"), tone: response["ok"] as? Bool == false ? .error : .success)
    }

    func importBackup() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let response = model.call("import_backup", ["path": url.path])
        model.mergeState(from: response)
        model.refresh()
    }
}
