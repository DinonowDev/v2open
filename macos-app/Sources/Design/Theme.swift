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

enum C {
    static var glassy = false

    private static let navyDeep = Color(red: 0.043, green: 0.071, blue: 0.125)
    private static let navyMid = Color(red: 0.059, green: 0.090, blue: 0.165)
    private static let navyLift = Color(red: 0.118, green: 0.161, blue: 0.231)

    static var bg: Color { glassy ? navyDeep : navyMid }
    static var bgGradientTop: Color { glassy ? Color(red: 0.02, green: 0.05, blue: 0.12) : navyMid }
    static var bgGradientBottom: Color { glassy ? Color(red: 0.06, green: 0.14, blue: 0.24) : navyLift }
    static var card: Color { glassy ? Color.white.opacity(0.08) : Color(red: 0.09, green: 0.13, blue: 0.20) }
    static var cardElevated: Color { glassy ? Color.white.opacity(0.11) : Color(red: 0.11, green: 0.16, blue: 0.24) }
    static var line: Color { glassy ? Color.white.opacity(0.14) : Color.white.opacity(0.10) }

    static let cyan = Color(red: 0.243, green: 0.878, blue: 0.961)
    static let accent = Color(red: 0.133, green: 0.827, blue: 0.933)
    static let accentDeep = Color(red: 0.024, green: 0.639, blue: 0.769)
    static let speedDown = accent
    static let speedDownDeep = accentDeep
    static let speedUp = Color(red: 0.655, green: 0.545, blue: 0.980)
    static let speedUpDeep = Color(red: 0.486, green: 0.337, blue: 0.925)
    static let green = Color(red: 0.204, green: 0.780, blue: 0.349)
    /// Legacy alias — use `accent` for primary highlights.
    static let lime = accent
    static let limeDeep = accentDeep
    static var muted: Color { glassy ? Color(red: 0.72, green: 0.80, blue: 0.88) : Color(red: 0.58, green: 0.64, blue: 0.72) }
    static let ping = Color(red: 0.169, green: 0.831, blue: 0.478)
    static let pingWarn = Color(red: 0.98, green: 0.75, blue: 0.22)
    static let pingBad = Color(red: 1, green: 0.36, blue: 0.45)
    static let pingDead = Color(red: 0.95, green: 0.40, blue: 0.58)
    static var track: Color { glassy ? Color.white.opacity(0.22) : Color(red: 0.902, green: 0.902, blue: 0.918) }
    static var fieldFill: Color { glassy ? Color.white.opacity(0.07) : Color(red: 0.13, green: 0.13, blue: 0.15) }
    static var fieldFillFocus: Color { glassy ? Color.white.opacity(0.11) : Color(red: 0.16, green: 0.16, blue: 0.19) }
    static var fieldStroke: Color { glassy ? Color.white.opacity(0.14) : Color(red: 0.26, green: 0.26, blue: 0.28) }
    static var fieldStrokeFocus: Color { cyan.opacity(0.75) }
    static var fieldGlow: Color { cyan.opacity(glassy ? 0.22 : 0.14) }
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

func mixed(_ string: String, size: CGFloat, weight: Font.Weight = .regular, color: Color = .white) -> Text {
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
        segment.foregroundColor = color
        result.append(segment)
    }
    return Text(result)
}

struct Mix: View {
    var text: String
    var size: CGFloat = 16
    var weight: Font.Weight = .regular
    var color: Color = .white
    var body: some View { mixed(text, size: size, weight: weight, color: color) }
}
