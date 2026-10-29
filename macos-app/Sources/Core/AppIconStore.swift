import AppKit

enum AppIconStore {
    static let options: [(String, String)] = [
        ("default", "iconDefault"),
        ("lime", "iconLime"),
        ("violet", "iconViolet")
    ]

    static func apply(_ name: String) {
        DispatchQueue.main.async {
            if name.isEmpty || name == "default" {
                NSApp.applicationIconImage = nil
                return
            }
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "AppIcons"),
               let image = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = image
            }
        }
    }
}
