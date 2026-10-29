import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension ConfigsView {

    func profileIds(in group: [String: Any]) -> Set<String> {
        Set((group["profiles"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
    }

    func pingArgs(groupId: String? = nil, profileId: String? = nil) -> [String: Any] {
        var args: [String: Any] = [:]
        if let groupId { args["group_id"] = groupId }
        if let profileId { args["id"] = profileId }
        if model.settings["throughput_test"] as? Bool == true {
            args["throughput"] = true
        }
        return args
    }

    func runPing(profileIds: Set<String>, args: [String: Any]) {
        let throughput = args["throughput"] as? Bool == true
        Task { await model.pingProfiles(profileIds, throughput: throughput, toast: true) }
    }

    func sortLabel() -> String {
        switch model.settings["sort_by"] as? String ?? "default" {
        case "name": return model.t("sortName")
        case "ping": return model.t("sortPing")
        case "download": return model.t("sortDownload")
        case "upload": return model.t("sortUpload")
        case "time": return model.t("sortTime")
        default: return model.t("sortDefault")
        }
    }

    func cycleSort() {
        let order = ["default", "name", "ping", "download", "upload", "time"]
        let current = model.settings["sort_by"] as? String ?? "default"
        let index = order.firstIndex(of: current) ?? 0
        model.set("sort_by", order[(index + 1) % order.count])
    }

    func filteredGroups() -> [[String: Any]] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.groups.compactMap { group in
            var profiles = sortedProfiles(group["profiles"] as? [[String: Any]] ?? [])
            if !q.isEmpty {
                profiles = profiles.filter { profile in
                    let hay = "\(profile["remark"] as? String ?? "") \(profile["address"] as? String ?? "") \(profile["protocol"] as? String ?? "")".lowercased()
                    return hay.contains(q)
                }
                let name = (group["name"] as? String ?? model.t("local")).lowercased()
                if profiles.isEmpty && !name.contains(q) { return nil }
            }
            var copy = group
            copy["profiles"] = profiles
            return copy
        }
    }

    func sortedProfiles(_ profiles: [[String: Any]]) -> [[String: Any]] {
        var copy = profiles
        switch model.settings["sort_by"] as? String ?? "default" {
        case "name":
            copy.sort { ($0["remark"] as? String ?? "").localizedCompare($1["remark"] as? String ?? "") == .orderedAscending }
        case "ping":
            copy.sort {
                let av = jsonInt($0["ping"])
                let bv = jsonInt($1["ping"])
                return (av > 0 ? av : 99999) < (bv > 0 ? bv : 99999)
            }
        case "download":
            copy.sort { jsonInt($0["download_bps"]) > jsonInt($1["download_bps"]) }
        case "upload":
            copy.sort { jsonInt($0["upload_bps"]) > jsonInt($1["upload_bps"]) }
        case "time":
            copy.sort { ($0["created_at"] as? Int ?? 0) > ($1["created_at"] as? Int ?? 0) }
        default: break
        }
        return copy
    }

    func openManualEditor() {
        addStep = .none
        model.draft = ["protocol": "vless", "remark": "", "address": "", "port": 443, "uuid": "", "network": "tcp", "tls": "reality", "encryption": "none"]
        model.push("editor")
    }

    func importClipboard() {
        addStep = .none
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.showToast(model.t("clipboardEmpty"), tone: .warning)
            return
        }
        finishImport(text: text)
    }

    func importClashFile() {
        addStep = .none
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "yaml") ?? .plainText, .plainText, .item]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            model.showToast(model.t("wrong"), tone: .warning)
            return
        }
        finishImport(text: text)
    }

    func finishImport(text: String) {
        if let err = model.invoke("import", ["text": text]) {
            model.showToast(err, tone: .error)
            return
        }
        addStep = .none
        model.showToast(model.t("imported"), tone: .success)
    }

    func importQRImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        guard let text = PhotoQRPicker.decode(image) else {
            model.showToast(model.t("wrong"), tone: .warning)
            return
        }
        finishImport(text: text)
    }

    func importQRFromPhotos() {
        PhotoQRPicker.shared.present { text in
            guard let text, !text.isEmpty else {
                model.showToast(model.t("wrong"), tone: .warning)
                return
            }
            finishImport(text: text)
        }
    }

    func importFile() {
        addStep = .none
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            model.showToast(model.t("wrong"), tone: .warning)
            return
        }
        if data.starts(with: [0x56, 0x32, 0x4F, 0x50, 0x45, 0x4E, 0x31]) || data.starts(with: [0x50, 0x4B]) {
            filePassword = ""
            lockedImportB64 = data.base64EncodedString()
            return
        }
        if let text = String(data: data, encoding: .utf8) {
            finishImport(text: text)
            return
        }
        model.showToast(model.t("wrong"), tone: .warning)
    }

    func confirmLockedImport() {
        guard let b64 = lockedImportB64 else { return }
        if let err = model.invoke("unseal", ["text": b64, "password": filePassword]) {
            model.showToast(err, tone: .error)
            return
        }
        lockedImportB64 = nil
        filePassword = ""
        model.showToast(model.t("imported"), tone: .success)
    }
}
