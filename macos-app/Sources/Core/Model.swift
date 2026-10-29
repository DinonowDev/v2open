import Foundation
import SwiftUI

@MainActor
final class Model: ObservableObject {
    @Published var state: [String: Any] = [:]
    @Published var page = "home"
    @Published var stack: [String] = []
    @Published var draft: [String: Any] = [:]
    @Published var toast: AppToastItem?
    @Published var pingingIds: Set<String> = []
    @Published var about: [String: Any] = [:]

    private var booted = false
    private var pingLoopTask: Task<Void, Never>?
    private let tickActivity = TickActivity()
    private static let autoPingInterval: TimeInterval = 60

    @Published var systemLight = false

    var language: String { settings["language"] as? String ?? "en" }
    var fa: Bool { language == "fa" }
    var rtl: Bool { language == "fa" || language == "ar" }
    var themeLight: Bool {
        switch settings["theme"] as? String ?? "dark" {
        case "light": return true
        case "system": return systemLight
        default: return false
        }
    }
    var glassy: Bool { settings["glassy"] as? Bool == true }
    var settings: [String: Any] { state["settings"] as? [String: Any] ?? [:] }
    var groups: [[String: Any]] { state["groups"] as? [[String: Any]] ?? [] }
    var routes: [[String: Any]] { state["routes"] as? [[String: Any]] ?? [] }
    var geoAssets: [[String: Any]] { state["geo_assets"] as? [[String: Any]] ?? [] }
    var backups: [[String: Any]] { state["backups"] as? [[String: Any]] ?? [] }
    var runtime: [String: Any] { state["runtime"] as? [String: Any] ?? [:] }

    func t(_ key: String) -> String {
        LocaleStore.string(key, language: language)
    }

    func showToast(_ text: String, tone: ToastTone = .info) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = AppToastItem(text: trimmed, tone: tone)
        toast = item
        let token = item.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if toast?.id == token { toast = nil }
        }
    }

    func boot() {
        guard !booted else { return }
        booted = true
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/V2Open", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let rules = support.appendingPathComponent("rulesets")
        let bin = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/sing-box").path
        let code: Int32 = support.path.withCString { d in
            bin.withCString { b in
                rules.path.withCString { r in v2_init(d, b, r) }
            }
        }
        if code != 0 { DevLog.error("boot", "init failed: \(code)") }
        UILock.acquire()
        systemLight = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.systemLight = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
            }
        }
        refresh()
        refreshAbout()
        syncBackgroundScheduler()
        armSystemOnDemand()
        startAutoPing()
        tickActivity.start { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let response = self.call("tick")
                if let data = response["data"] as? [String: Any] { self.state = data }
            }
        }
        DevLog.event("boot", "ready")
    }

    func call(_ method: String, _ args: [String: Any] = [:]) -> [String: Any] {
        v2RPC(method: method, args: args)
    }

    func refresh() {
        let response = call("state")
        state = response["data"] as? [String: Any] ?? [:]
    }

    func mergeState(from response: [String: Any]) {
        if let data = response["data"] as? [String: Any] {
            state = data
        } else if response["ok"] as? Bool != false {
            refresh()
        }
    }

    func pingRPC(_ args: [String: Any]) async -> String? {
        let response = await Task.detached(priority: .userInitiated) {
            v2RPC(method: "ping", args: args)
        }.value
        mergeState(from: response)
        guard response["ok"] as? Bool != false else {
            return response["error"] as? String ?? t("failed")
        }
        return nil
    }

    func allProfileIds() -> [String] {
        groups.flatMap { ($0["profiles"] as? [[String: Any]]) ?? [] }.compactMap { $0["id"] as? String }.filter { !$0.isEmpty }
    }

    func pingProfiles(_ ids: Set<String>, throughput: Bool, toast: Bool) async {
        let selected = settings["selected_id"] as? String ?? ""
        var ordered = allProfileIds().filter { ids.contains($0) && !pingingIds.contains($0) }
        if ordered.isEmpty { return }
        if !selected.isEmpty, let index = ordered.firstIndex(of: selected) {
            ordered.remove(at: index)
            ordered.insert(selected, at: 0)
        }
        if toast { showToast(t("pinging"), tone: .info) }
        var failed: String?
        for id in ordered {
            if Task.isCancelled { break }
            pingingIds.insert(id)
            var args: [String: Any] = ["id": id]
            if throughput { args["throughput"] = true }
            if let err = await pingRPC(args) { failed = err }
            pingingIds.remove(id)
        }
        if toast {
            if let failed { showToast(failed, tone: .error) }
            else { showToast(t("pingDone"), tone: .success) }
        }
    }

    private func startAutoPing() {
        pingLoopTask?.cancel()
        pingLoopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let started = Date()
                await self.pingProfiles(Set(self.allProfileIds()), throughput: false, toast: false)
                let elapsed = Date().timeIntervalSince(started)
                let wait = max(0, Self.autoPingInterval - elapsed)
                let ns = UInt64(wait * 1_000_000_000)
                if ns > 0 {
                    try? await Task.sleep(nanoseconds: ns)
                }
            }
        }
    }

    @discardableResult
    func invoke(_ method: String, _ args: [String: Any] = [:]) -> String? {
        let response = call(method, args)
        guard response["ok"] as? Bool != false else {
            return response["error"] as? String ?? t("failed")
        }
        refresh()
        return nil
    }

    func set(_ key: String, _ value: Any) {
        _ = call("set", ["key": key, "value": value])
        refresh()
        if ["geo_auto_update", "on_demand", "persist_tunnel", "reconnect_after_wake", "on_demand_text"].contains(key) {
            syncBackgroundScheduler()
            armSystemOnDemand()
        }
    }

    func refreshAbout() {
        about = call("about")["data"] as? [String: Any] ?? [:]
    }

    func syncBackgroundScheduler() {
        BackgroundScheduler.installIfNeeded(
            geoAuto: settings["geo_auto_update"] as? Bool == true,
            onDemand: settings["on_demand"] as? Bool == true,
            persist: (settings["persist_tunnel"] as? Bool == true) || (settings["reconnect_after_wake"] as? Bool == true)
        )
    }

    func armSystemOnDemand() {
        guard Self.hasPacketTunnelExtension else { return }
        TunnelManager.shared.armOnDemand(
            enabled: settings["on_demand"] as? Bool == true,
            rules: settings["on_demand_text"] as? String ?? ""
        )
    }

    func handleOpenURL(_ url: URL) {
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url) else { return }
            if data.starts(with: [0x56, 0x32, 0x4F, 0x50, 0x45, 0x4E, 0x31]) || data.starts(with: [0x50, 0x4B]) || url.pathExtension.lowercased() == "v2box" {
                showToast(t("filePassword"), tone: .warning)
                push("backup_settings")
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                if let err = invoke("import", ["text": text]) {
                    showToast(err, tone: .error)
                } else {
                    showToast(t("imported"), tone: .success)
                }
            }
            return
        }
        var text = url.absoluteString
        if url.scheme == "v2open", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            if let payload = items.first(where: { $0.name == "text" })?.value { text = payload }
        }
        if let err = invoke("import", ["text": text]) {
            showToast(err, tone: .error)
        } else {
            showToast(t("imported"), tone: .success)
        }
    }

    func go(_ name: String) {
        page = name
        stack.removeAll()
    }

    func push(_ name: String) { stack.append(name) }
    func pop() { if !stack.isEmpty { stack.removeLast() } }
    var current: String { stack.last ?? page }

    func profile(id: String) -> [String: Any]? {
        guard !id.isEmpty else { return nil }
        for group in groups {
            for profile in group["profiles"] as? [[String: Any]] ?? [] {
                if profile["id"] as? String == id { return profile }
            }
        }
        return nil
    }

    var selectedProfile: [String: Any]? {
        profile(id: settings["selected_id"] as? String ?? "")
    }

    func profile(matchingRemark remark: String) -> [String: Any]? {
        guard !remark.isEmpty else { return nil }
        for group in groups {
            for profile in group["profiles"] as? [[String: Any]] ?? [] {
                if profile["remark"] as? String == remark { return profile }
            }
        }
        return nil
    }

    func activeConnectionProfile() -> [String: Any]? {
        if runtime["connected"] as? Bool == true,
           let remark = runtime["profile_name"] as? String,
           let match = profile(matchingRemark: remark) {
            return match
        }
        return selectedProfile
    }

    private static var hasPacketTunnelExtension: Bool {
        FileManager.default.fileExists(
            atPath: Bundle.main.bundleURL
                .appendingPathComponent("Contents/PlugIns/PacketTunnel.appex")
                .path
        )
    }

    func connectTunnel(id: String? = nil, groupId: String = "", smart: Bool? = nil) {
        var id = id ?? (settings["selected_id"] as? String ?? "")
        let smart = smart ?? (settings["smart_connect"] as? Bool == true) || !groupId.isEmpty
        if !smart, settings["auto_connect_best"] as? Bool == true {
            let pick = call("pick_best")
            if pick["ok"] as? Bool != false, let best = (pick["data"] as? [String: Any])?["id"] as? String, !best.isEmpty {
                id = best
                refresh()
            }
        }
        if id.isEmpty, smart {
            id = firstProfileId(in: groupId)
        }
        if !smart, id.isEmpty {
            DevLog.error("connect", "no config selected")
            showToast(t("none"), tone: .warning)
            refresh()
            return
        }

        // Dev / unsigned builds have no PacketTunnel; NE "connected" would not run sing-box.
        guard Self.hasPacketTunnelExtension else {
            startCoreConnect(id: id, smart: smart, groupId: groupId)
            return
        }

        let persist = settings["persist_tunnel"] as? Bool == true
        var args: [String: Any] = ["id": id, "smart": smart, "keep_alive": persist && TunnelManager.shared.usingSystem]
        if !groupId.isEmpty { args["group_id"] = groupId }
        let prepared = call("prepare", args)
        let data = prepared["data"] as? [String: Any] ?? [:]
        let path = data["path"] as? String ?? ""
        guard (prepared["ok"] as? Bool) == true, !path.isEmpty else {
            if let err = prepared["error"] as? String, !err.isEmpty {
                DevLog.error("connect", "prepare: \(err)")
            }
            startCoreConnect(id: id, smart: smart, groupId: groupId)
            return
        }
        let options = TunnelStartOptions(
            configPath: path,
            socksPort: data["socks_port"] as? Int ?? 10808,
            mtu: data["mtu"] as? Int ?? 1500,
            includeLocal: data["include_local"] as? Bool ?? false,
            includeAll: data["include_all_networks"] as? Bool ?? false,
            includeApns: data["include_apns"] as? Bool ?? false,
            killSwitch: data["kill_switch"] as? Bool ?? false,
            combiner: data["combiner"] as? Bool ?? false,
            launchCore: data["launch_core"] as? Bool ?? true,
            dns: data["dns"] as? String ?? "1.1.1.1",
            onDemand: data["on_demand"] as? Bool ?? false,
            rules: data["on_demand_text"] as? String ?? "",
            engine: data["engine"] as? String ?? "sing-box",
            enforceRoutes: settings["enforce_routes"] as? Bool ?? false
        )
        let tunnel = TunnelManager.shared
        let finish: (Bool) -> Void = { [weak self] system in
            Task { @MainActor in
                self?.finishTunnelConnect(id: id, smart: smart, groupId: groupId, system: system)
            }
        }
        if persist && tunnel.usingSystem {
            tunnel.reload(options, completion: finish)
        } else {
            tunnel.connect(options, completion: finish)
        }
    }

    private func firstProfileId(in groupId: String) -> String {
        if !groupId.isEmpty, let group = groups.first(where: { ($0["id"] as? String) == groupId }) {
            let profiles = group["profiles"] as? [[String: Any]] ?? []
            return profiles.first?["id"] as? String ?? ""
        }
        return allProfileIds().first ?? ""
    }

    private func startCoreConnect(id: String, smart: Bool, groupId: String = "") {
        var args: [String: Any] = ["id": id, "smart": smart]
        if !groupId.isEmpty { args["group_id"] = groupId }
        let response = call("connect", args)
        refresh()
        if response["ok"] as? Bool == false {
            let err = response["error"] as? String ?? t("failed")
            DevLog.error("connect", err)
            showToast(err, tone: .error)
        } else if runtime["connected"] as? Bool == true {
            showToast(t("connected"), tone: .success)
        }
    }

    private func finishTunnelConnect(id: String, smart: Bool, groupId: String, system: Bool) {
        if system {
            _ = call("mark_connected", ["id": id])
            refresh()
            if TunnelManager.shared.lastReloaded {
                showToast(t("coreReloaded"), tone: .success)
            } else if runtime["connected"] as? Bool == true {
                showToast(t("connected"), tone: .success)
            }
        } else {
            startCoreConnect(id: id, smart: smart, groupId: groupId)
        }
    }

    func disconnectTunnel() {
        if TunnelManager.shared.usingSystem { TunnelManager.shared.disconnect() }
        _ = call("disconnect")
        refresh()
        showToast(t("disconnected"), tone: .info)
    }
}
