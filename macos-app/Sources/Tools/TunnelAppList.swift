import Foundation

enum TunnelAppList {
    static var hostIDE: [String] {
        let name = ProcessInfo.processInfo.processName
        return [
            name,
            "\(name) Helper",
            "\(name) Helper (Plugin)",
            "\(name) Helper (Renderer)",
            "\(name) Helper (GPU)"
        ]
    }

    static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, seen.insert(line.lowercased()).inserted else { continue }
            names.append(line)
        }
        return names
    }

    static func serialize(_ names: [String]) -> String {
        parse(names.joined(separator: "\n")).joined(separator: "\n")
    }

    static func canonicalize(_ names: [String], resolve: (String) -> String? = { _ in nil }) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in names {
            let name = resolve(raw) ?? raw
            if seen.insert(name.lowercased()).inserted {
                result.append(name)
            }
        }
        return result
    }

    static func addingHostIDE(to text: String) -> String {
        serialize(parse(text) + hostIDE)
    }
}
