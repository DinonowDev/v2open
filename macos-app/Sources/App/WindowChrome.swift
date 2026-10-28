import SwiftUI
import AppKit

final class HairlineScroller: NSScroller {
    static let thickness: CGFloat = 2

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        0
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func draw(_ dirtyRect: NSRect) {
        drawKnob()
    }

    override func drawKnob() {
        let knob = rect(for: .knob)
        let width = Self.thickness
        let body = NSRect(
            x: max(knob.maxX - width - 1, knob.minX),
            y: knob.minY + 2,
            width: width,
            height: max(knob.height - 4, 12)
        )
        NSColor.white.withAlphaComponent(0.32).setFill()
        NSBezierPath(roundedRect: body, xRadius: width / 2, yRadius: width / 2).fill()
    }
}

enum HairlineScrollbars {
    private static var applying = false

    static func apply(in window: NSWindow?) {
        guard !applying, let root = window?.contentView else { return }
        applying = true
        defer { applying = false }
        walk(root)
    }

    private static func walk(_ view: NSView) {
        if let scroll = view as? NSScrollView {
            configure(scroll)
        }
        for child in view.subviews { walk(child) }
    }

    private static func configure(_ scroll: NSScrollView) {
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.scrollerKnobStyle = .light
        scroll.hasHorizontalScroller = false
        scroll.horizontalScroller?.alphaValue = 0
        scroll.horizontalScroller?.isHidden = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets()
        scroll.scrollerInsets = NSEdgeInsets()
        scroll.contentView.automaticallyAdjustsContentInsets = false
        scroll.contentView.contentInsets = NSEdgeInsets()
        if !(scroll.verticalScroller is HairlineScroller) {
            let mini = HairlineScroller()
            mini.controlSize = .mini
            mini.scrollerStyle = .overlay
            mini.knobStyle = .light
            if let current = scroll.verticalScroller {
                mini.floatValue = current.floatValue
                mini.knobProportion = current.knobProportion
            }
            scroll.verticalScroller = mini
        }
        scroll.hasVerticalScroller = true
        scroll.verticalScroller?.scrollerStyle = .overlay
        scroll.verticalScroller?.knobStyle = .light
        scroll.verticalScroller?.controlSize = .mini
        scroll.verticalScroller?.alphaValue = 1
        reclaimGutter(scroll)
    }

    private static func reclaimGutter(_ scroll: NSScrollView) {
        let gutter = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        guard gutter > 0 else { return }
        scroll.contentInsets.right = 0
        scroll.scrollerInsets.right = 0
        scroll.contentView.contentInsets.right = 0
        let clip = scroll.contentView.bounds.width
        guard let document = scroll.documentView else { return }
        if document.frame.width + 0.5 < clip {
            var frame = document.frame
            frame.size.width = clip
            document.frame = frame
        }
    }
}

final class HairlineScrollHost: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isMovableByWindowBackground = true
        HairlineScrollbars.apply(in: window)
    }

    override func layout() {
        super.layout()
        HairlineScrollbars.apply(in: window)
    }
}

struct HairlineScrollInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> HairlineScrollHost { HairlineScrollHost() }
    func updateNSView(_ nsView: HairlineScrollHost, context: Context) {
        HairlineScrollbars.apply(in: nsView.window)
    }
}

struct WindowChrome: NSViewRepresentable {
    var glassy: Bool

    func makeNSView(context: Context) -> NSView { HairlineScrollHost() }

    private static func roundCorners(_ window: NSWindow, radius: CGFloat) {
        if window.responds(to: NSSelectorFromString("setCornerRadius:")) {
            window.setValue(radius, forKey: "cornerRadius")
        }
        window.invalidateShadow()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.title = "V2Open"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = true
            window.backgroundColor = NSColor(calibratedRed: 0.059, green: 0.09, blue: 0.165, alpha: 1)
            window.hasShadow = true
            window.isMovableByWindowBackground = true
            let fixed = NSSize(width: AppFrame.width, height: AppFrame.height)
            window.minSize = fixed
            window.maxSize = fixed
            Self.roundCorners(window, radius: AppFrame.cornerRadius)
            HairlineScrollbars.apply(in: window)
        }
    }
}
