import SwiftUI
import AppKit
import CoreText

final class AppTerminator: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let settings = (v2RPC(method: "state")["data"] as? [String: Any])?["settings"] as? [String: Any] ?? [:]
        let keep = (settings["geo_auto_update"] as? Bool == true)
            || (settings["on_demand"] as? Bool == true)
            || (settings["persist_tunnel"] as? Bool == true)
        return !keep
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let settings = (v2RPC(method: "state")["data"] as? [String: Any])?["settings"] as? [String: Any] ?? [:]
        UILock.release()
        BackgroundScheduler.installIfNeeded(
            geoAuto: settings["geo_auto_update"] as? Bool == true,
            onDemand: settings["on_demand"] as? Bool == true,
            persist: settings["persist_tunnel"] as? Bool == true
        )
        _ = v2RPC(method: "disconnect")
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
        WindowGroup {
            RootView()
                .environmentObject(model)
                .background(WindowChrome(light: model.themeLight))
                .onAppear { model.boot() }
                .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                    if model.settings["stop_on_sleep"] as? Bool ?? true {
                        model.disconnectTunnel()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    if model.settings["persist_tunnel"] as? Bool == true {
                        model.connectTunnel()
                    }
                }
        }
        .defaultSize(width: AppFrame.width, height: AppFrame.height)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
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

func registerFonts() {
    for name in ["Vazir-Regular", "Vazir-Medium", "Vazir-Bold", "Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"] {
        if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
