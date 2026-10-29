import SwiftUI
import AppKit
import CoreText

enum AppFrame {
    static let width: CGFloat = 418
    static let height: CGFloat = 684
    static let cornerRadius: CGFloat = 28
}

enum PageLayout {
    static let horizontal: CGFloat = 28
    static let titleBar: CGFloat = 28
    static let top: CGFloat = 20
    static let bottom: CGFloat = 20
    static let titleSize: CGFloat = 28
    static let subtitleSize: CGFloat = 14
    static let captionSize: CGFloat = 12
    static let titleToSubtitle: CGFloat = 4
    static let subtitleToCaption: CGFloat = 2
    static let headerToContent: CGFloat = 14
    static let sectionGap: CGFloat = 12
    static let dockClearance: CGFloat = 92
    static let tabBarClearance: CGFloat = 86
}

private struct ThemeLightKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var themeLight: Bool {
        get { self[ThemeLightKey.self] }
        set { self[ThemeLightKey.self] = newValue }
    }
}

enum C {
    static var light = false
    static var scheme: ColorScheme { light ? .light : .dark }

    static func apply(light: Bool) {
        Self.light = light
    }

    private static func ns(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua ? light : dark
        })
    }

    static let bg = adaptive(light: ns(0.945, 0.957, 0.973), dark: ns(0.059, 0.090, 0.165))
    static let bgGradientTop = adaptive(light: ns(0.973, 0.980, 0.992), dark: ns(0.059, 0.090, 0.165))
    static let bgGradientBottom = adaptive(light: ns(0.890, 0.918, 0.949), dark: ns(0.118, 0.161, 0.231))
    static let card = adaptive(light: .white, dark: ns(0.09, 0.13, 0.20))
    static let cardElevated = adaptive(light: .white, dark: ns(0.11, 0.16, 0.24))
    static let text = adaptive(light: ns(0.090, 0.130, 0.200), dark: .white)
    static let overlay = adaptive(light: .black, dark: .white)
    static let line = adaptive(light: ns(0, 0, 0, 0.08), dark: ns(1, 1, 1, 0.10))
    static let shine = adaptive(light: ns(0, 0, 0, 0.04), dark: ns(1, 1, 1, 0.06))
    static let hairline = adaptive(light: ns(0, 0, 0, 0.10), dark: ns(1, 1, 1, 0.16))

    static let cyan = Color(red: 0.243, green: 0.878, blue: 0.961)
    static let accent = Color(red: 0.133, green: 0.827, blue: 0.933)
    static let accentDeep = Color(red: 0.024, green: 0.639, blue: 0.769)
    static let speedDown = accent
    static let speedDownDeep = accentDeep
    static let speedUp = Color(red: 0.655, green: 0.545, blue: 0.980)
    static let speedUpDeep = Color(red: 0.486, green: 0.337, blue: 0.925)
    static let green = Color(red: 0.204, green: 0.780, blue: 0.349)
    static let lime = accent
    static let limeDeep = accentDeep
    static let muted = adaptive(light: ns(0.38, 0.45, 0.54), dark: ns(0.58, 0.64, 0.72))
    static let ping = Color(red: 0.169, green: 0.831, blue: 0.478)
    static let pingWarn = Color(red: 0.98, green: 0.75, blue: 0.22)
    static let pingBad = Color(red: 1, green: 0.36, blue: 0.45)
    static let pingDead = Color(red: 0.95, green: 0.40, blue: 0.58)
    static let track = adaptive(light: ns(0.82, 0.85, 0.90), dark: ns(0.902, 0.902, 0.918))
    static let fieldFill = adaptive(light: ns(0.93, 0.945, 0.965), dark: ns(0.13, 0.13, 0.15))
    static let fieldFillFocus = adaptive(light: .white, dark: ns(0.16, 0.16, 0.19))
    static let fieldStroke = adaptive(light: ns(0, 0, 0, 0.10), dark: ns(0.26, 0.26, 0.28, 1))
    static var fieldStrokeFocus: Color { cyan.opacity(0.75) }
    static var fieldGlow: Color { cyan.opacity(light ? 0.16 : 0.14) }
    static let switchOff = adaptive(light: ns(0.78, 0.81, 0.86), dark: ns(0.22, 0.22, 0.24))
    static let powerOffTop = adaptive(light: ns(0.82, 0.86, 0.92), dark: ns(0.14, 0.19, 0.28))
    static let powerOffBottom = adaptive(light: ns(0.68, 0.74, 0.82), dark: ns(0.08, 0.11, 0.17))
    static var onAccent: Color { Color(red: 0.04, green: 0.08, blue: 0.14) }

    static var windowBackground: NSColor {
        light
            ? NSColor(calibratedRed: 0.945, green: 0.957, blue: 0.973, alpha: 1)
            : NSColor(calibratedRed: 0.059, green: 0.090, blue: 0.165, alpha: 1)
    }

    static var scrollerKnob: NSColor {
        (light ? NSColor.black : NSColor.white).withAlphaComponent(light ? 0.28 : 0.32)
    }
}

enum PingMark {
    static let warnAfter = 200
    static let badAfter = 400

    static func color(_ ping: Int) -> Color {
        if ping == 0 { return C.pingDead }
        if ping > badAfter { return C.pingBad }
        if ping > warnAfter { return C.pingWarn }
        if ping > 0 { return C.ping }
        return C.muted.opacity(0.55)
    }

    static func label(_ ping: Int, timeout: String) -> String {
        if ping > 0 { return "\(ping)ms" }
        if ping == 0 { return timeout }
        return "—"
    }
}

func mixed(_ string: String, size: CGFloat, weight: Font.Weight = .regular) -> Text {
    let pattern = try! NSRegularExpression(pattern: "[\\u0600-\\u06FF\\u0750-\\u077F]+|[^\\u0600-\\u06FF\\u0750-\\u077F]+")
    let ns = string as NSString
    var result = AttributedString()
    let matches = pattern.matches(in: string, range: NSRange(location: 0, length: ns.length))
    let parts: [(String, Bool)] = matches.isEmpty ? [(string, false)] : matches.map {
        let text = ns.substring(with: $0.range)
        let persian = text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
        return (text, persian)
    }
    for (text, persian) in parts {
        var segment = AttributedString(text)
        segment.font = Font.custom(persian ? "Vazir" : "Inter", size: size).weight(weight)
        result.append(segment)
    }
    return Text(result)
}

struct Mix: View {
    @Environment(\.themeLight) private var themeLight
    var text: String
    var size: CGFloat = 16
    var weight: Font.Weight = .regular
    var color: Color? = nil

    var body: some View {
        mixed(text, size: size, weight: weight)
            .foregroundStyle(color ?? C.text)
            .transaction { $0.animation = nil }
            .id(themeLight)
    }
}
