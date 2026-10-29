import Foundation

enum LocaleStore {
    static let options: [(String, String)] = [
        ("en", "English"),
        ("fa", "فارسی"),
        ("ar", "العربية"),
        ("id", "Indonesia"),
        ("ru", "Русский"),
        ("tr", "Türkçe"),
        ("uk", "Українська"),
        ("vi", "Tiếng Việt"),
        ("zh", "中文")
    ]

    private static var cache: [String: [String: String]] = [:]

    static func string(_ key: String, language: String) -> String {
        if language == "fa" { return faText[key] ?? enText[key] ?? key }
        if language == "en" { return table("en")[key] ?? enText[key] ?? key }
        return table(language)[key] ?? table("en")[key] ?? enText[key] ?? key
    }

    private static func table(_ code: String) -> [String: String] {
        if let cached = cache[code] { return cached }
        let loaded = load(code)
        cache[code] = loaded
        return loaded
    }

    private static func load(_ code: String) -> [String: String] {
        let bundle = Bundle.main
        let url = bundle.url(forResource: code, withExtension: "json", subdirectory: "Locales")
            ?? bundle.resourceURL?.appendingPathComponent("Locales/\(code).json")
        guard let url, let data = try? Data(contentsOf: url),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return code == "fa" ? faText : enText
        }
        return map
    }
}
