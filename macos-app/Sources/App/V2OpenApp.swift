import SwiftUI
import AppKit
import CoreText

final class AppTerminator: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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
        registerFonts()
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .background(WindowChrome(glassy: (model.settings["appearance"] as? String) == "glassy"))
                .onAppear { model.boot() }
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
