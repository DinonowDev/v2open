import AppKit
import Combine
import SwiftUI

enum WindowBridge {
    static var openMain: (() -> Void)?
}

enum AppChrome {
    static func apply(_ settings: [String: Any]) {
        let menu = settings["menu_bar"] as? Bool ?? true
        let hide = menu && (settings["hide_dock_icon"] as? Bool == true)
        let policy: NSApplication.ActivationPolicy = hide ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct WindowBridgeInstaller: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                WindowBridge.openMain = { openWindow(id: "main") }
            }
    }
}

@MainActor
final class MenuBarCenter: NSObject, NSMenuDelegate {
    static let shared = MenuBarCenter()

    private var item: NSStatusItem?
    private var menu: NSMenu?
    private weak var model: Model?
    var language: String { model?.language ?? "en" }
    private var stateWatch: AnyCancellable?
    private var runtimeWatch: AnyCancellable?
    private var actions: [MenuAction] = []
    private var iconConnected: Bool?

    func attach(_ model: Model) {
        self.model = model
        stateWatch = model.$state.sink { [weak self] _ in
            self?.sync()
        }
        runtimeWatch = model.liveRuntime.objectWillChange.sink { [weak self] _ in
            self?.sync()
        }
        sync()
    }

    func ensureVisible() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        item.button?.image = icon(connected: false)
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "V2Open"
        self.item = item
        self.menu = menu
    }

    func sync() {
        guard let model else {
            ensureVisible()
            return
        }
        let show = model.settings["menu_bar"] as? Bool ?? true
        if !show {
            if let item {
                NSStatusBar.system.removeStatusItem(item)
            }
            item = nil
            menu = nil
            iconConnected = nil
            AppChrome.apply(model.settings)
            return
        }
        ensureVisible()
        let connected = model.runtime["connected"] as? Bool == true
        if iconConnected != connected {
            iconConnected = connected
            item?.button?.image = icon(connected: connected)
        }
        if connected, let name = model.runtime["profile_name"] as? String, !name.isEmpty {
            item?.button?.toolTip = name
        } else {
            item?.button?.toolTip = "V2Open"
        }
        AppChrome.apply(model.settings)
    }

    func open(page: String? = nil) {
        if let page, let model {
            if page == "about" {
                model.go("settings")
                model.push("about")
            } else {
                model.go(page)
            }
        }
        let visible = NSApp.windows.contains { $0.canBecomeMain && $0.isVisible }
        if !visible {
            WindowBridge.openMain?()
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        rebuild(menu)
    }

    private func icon(connected: Bool) -> NSImage? {
        let name = connected ? "lock.shield.fill" : "lock.shield"
        let base = NSImage(systemSymbolName: name, accessibilityDescription: "V2Open")
        let sized = base?.withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        sized?.isTemplate = true
        return sized
    }

    private func rebuild(_ menu: NSMenu) {
        actions.removeAll()
        menu.removeAllItems()
        guard let model else {
            add(menu, "Open V2Open") { [weak self] in self?.open() }
            add(menu, "Quit V2Open") { NSApp.terminate(nil) }
            return
        }
        let connected = model.runtime["connected"] as? Bool == true
        let phase = model.runtime["phase"] as? String ?? ""
        if connected {
            let name = (model.runtime["profile_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (model.selectedProfile?["remark"] as? String)
                ?? ""
            disabled(menu, name.isEmpty ? model.t("connected") : model.t("menuConnectedTo", vars: ["name": name]))
            let up = formatBps(jsonInt(model.runtime["upload_speed"]))
            let down = formatBps(jsonInt(model.runtime["download_speed"]))
            disabled(menu, "↑ \(up)    ↓ \(down)")
        } else if phase == "connecting" {
            disabled(menu, model.t("connecting"))
        } else {
            disabled(menu, model.t("menuDisconnected"))
        }

        if connected {
            add(menu, model.t("disconnect")) { model.disconnectTunnel() }
        } else if phase != "connecting" {
            add(menu, model.t("connect")) { model.connectTunnel() }
        }

        menu.addItem(.separator())
        let groups = serverGroups(model)
        if groups.isEmpty {
            disabled(menu, model.t("noServers"))
        } else {
            let header = NSMenuItem(title: model.t("serversMenu"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            let selected = model.settings["selected_id"] as? String ?? ""
            for group in groups {
                let parent = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
                let sub = NSMenu()
                sub.autoenablesItems = false
                let shown = group.profiles.prefix(40)
                for profile in shown {
                    let item = NSMenuItem(title: profile.title, action: nil, keyEquivalent: "")
                    item.state = profile.id == selected ? .on : .off
                    let action = MenuAction { [weak model] in
                        guard let model else { return }
                        let live = model.runtime["connected"] as? Bool == true
                        let current = model.settings["selected_id"] as? String ?? ""
                        if live && current == profile.id { return }
                        model.connectTunnel(id: profile.id)
                    }
                    actions.append(action)
                    item.target = action
                    item.action = #selector(MenuAction.fire(_:))
                    sub.addItem(item)
                }
                if group.profiles.count > shown.count {
                    let more = NSMenuItem(title: model.t("moreInApp"), action: nil, keyEquivalent: "")
                    let action = MenuAction { [weak self] in self?.open(page: "configs") }
                    actions.append(action)
                    more.target = action
                    more.action = #selector(MenuAction.fire(_:))
                    sub.addItem(.separator())
                    sub.addItem(more)
                }
                parent.submenu = sub
                menu.addItem(parent)
            }
        }

        menu.addItem(.separator())
        updateItems(menu, model: model)
        add(menu, model.t("openApp")) { [weak self] in self?.open() }
        add(menu, model.t("quitApp")) { NSApp.terminate(nil) }
    }

    private func updateItems(_ menu: NSMenu, model: Model) {
        let updater = AppUpdater.shared
        switch updater.phase {
        case .checking:
            disabled(menu, model.t("checkingUpdates"))
        case .downloading(let progress):
            disabled(menu, model.t("downloadingUpdate", vars: ["percent": "\(Int(progress * 100))%"]))
        case .available:
            if let release = updater.release {
                add(menu, model.t("updateReady", vars: ["version": release.display])) {
                    updater.downloadAndInstall()
                }
            }
        default:
            break
        }
        let check = NSMenuItem(title: model.t("checkForUpdates"), action: nil, keyEquivalent: "")
        check.isEnabled = updater.phase != .checking && !updater.isDownloading
        let action = MenuAction { updater.check(interactive: true) }
        actions.append(action)
        check.target = action
        check.action = #selector(MenuAction.fire(_:))
        menu.addItem(check)
        menu.addItem(.separator())
    }

    private func serverGroups(_ model: Model) -> [MenuServerGroup] {
        let sorted = model.groups.sorted { a, b in
            let ap = a["pinned"] as? Bool == true
            let bp = b["pinned"] as? Bool == true
            if ap != bp { return ap && !bp }
            let an = a["name"] as? String ?? ""
            let bn = b["name"] as? String ?? ""
            return an.localizedCaseInsensitiveCompare(bn) == .orderedAscending
        }
        return sorted.compactMap { group in
            let profiles = (group["profiles"] as? [[String: Any]] ?? []).compactMap { profile -> MenuServer? in
                guard let id = profile["id"] as? String, !id.isEmpty else { return nil }
                let remark = (profile["remark"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let address = profile["address"] as? String ?? ""
                var title = remark.isEmpty ? address : remark
                if title.isEmpty { title = id }
                if title.count > 48 { title = String(title.prefix(47)) + "…" }
                let ping = jsonInt(profile["ping"])
                if ping >= 0 { title += "  \(ping) ms" }
                return MenuServer(id: id, title: title)
            }
            if profiles.isEmpty { return nil }
            let name = (group["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? model.t("local")
            return MenuServerGroup(name: name, profiles: profiles)
        }
    }

    private func add(_ menu: NSMenu, _ title: String, _ run: @escaping () -> Void) {
        let action = MenuAction(run)
        actions.append(action)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire(_:)), keyEquivalent: "")
        item.target = action
        menu.addItem(item)
    }

    private func disabled(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }
}

private struct MenuServerGroup {
    var name: String
    var profiles: [MenuServer]
}

private struct MenuServer {
    var id: String
    var title: String
}

private final class MenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire(_ sender: Any?) { run() }
}
