import SwiftUI
import AppKit
import CoreText
@preconcurrency import UserNotifications

final class AppTerminator: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MenuBarCenter.shared.open() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let settings = (v2RPC(method: "state")["data"] as? [String: Any])?["settings"] as? [String: Any] ?? [:]
        if settings["menu_bar"] as? Bool ?? true { return false }
        let keep = (settings["geo_auto_update"] as? Bool == true)
            || (settings["on_demand"] as? Bool == true)
            || (settings["persist_tunnel"] as? Bool == true)
            || (settings["sub_auto_update"] as? Bool == true)
        return !keep
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            MenuBarCenter.shared.open(page: "about")
        }
        completionHandler()
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .v2openOpenURLs, object: urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let settings = (v2RPC(method: "state")["data"] as? [String: Any])?["settings"] as? [String: Any] ?? [:]
        UILock.release()
        let persist = settings["persist_tunnel"] as? Bool == true
        let wake = settings["reconnect_after_wake"] as? Bool == true
        let onDemand = settings["on_demand"] as? Bool == true
        BackgroundScheduler.installIfNeeded(
            geoAuto: settings["geo_auto_update"] as? Bool == true,
            onDemand: onDemand,
            persist: persist || wake,
            groupAuto: settings["sub_auto_update"] as? Bool == true
        )
        if !persist && !onDemand {
            _ = v2RPC(method: "disconnect")
        }
        return .terminateNow
    }
}

@main
struct V2OpenApp: App {
    @NSApplicationDelegateAdaptor(AppTerminator.self) private var terminator
    @StateObject private var model = Model()
    init() {
        DevLog.install()
        if BackgroundScheduler.agentRequested {
            BackgroundScheduler.runIfRequested()
        }
        registerFonts()
    }
    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(model)
                .background(WindowBridgeInstaller())
                .background(WindowChrome(light: model.themeLight))
                .onAppear { model.boot() }
                .onReceive(NotificationCenter.default.publisher(for: .v2openOpenURLs)) { note in
                    for url in note.object as? [URL] ?? [] {
                        model.handleOpenURL(url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                    if model.settings["icloud"] as? Bool == true { CloudSync.shared.kick(force: true) }
                    if model.settings["stop_on_sleep"] as? Bool ?? true {
                        model.disconnectTunnel()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    if model.settings["reconnect_after_wake"] as? Bool == true {
                        model.connectTunnel()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    if model.settings["icloud"] as? Bool == true { CloudSync.shared.kick(force: true) }
                }
        }
        .defaultSize(width: AppFrame.width, height: AppFrame.height)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(model.t("checkForUpdates")) {
                    AppUpdater.shared.check(interactive: true)
                }
            }
        }
        Window("Logs", id: "logs-window") {
            LogsView()
                .environmentObject(model)
                .frame(minWidth: 420, minHeight: 520)
        }
        Window("Diagnostics", id: "diagnostics-window") {
            DiagnosticsView()
                .environmentObject(model)
                .frame(minWidth: 420, minHeight: 520)
        }
    }
}

struct WindowMoveHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowMoveView { WindowMoveView() }
    func updateNSView(_ nsView: WindowMoveView, context: Context) {}
}

final class WindowMoveView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

extension Notification.Name {
    static let v2openOpenURLs = Notification.Name("v2open.openURLs")
}

func registerFonts() {
    for name in ["Vazir-Regular", "Vazir-Medium", "Vazir-Bold", "Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"] {
        if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
