import AppKit
import SwiftUI

struct MacAppInfo: Identifiable, Hashable {
    var id: String { processName.lowercased() }
    let displayName: String
    let processName: String
    let url: URL
    let bundleIdentifier: String
}

enum MacAppIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

enum MacAppCatalog {
    private static let lock = NSLock()
    private static var cached: [MacAppInfo]?

    static func all() -> [MacAppInfo] {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let list = scan()
        cached = list
        return list
    }

    static func refresh() -> [MacAppInfo] {
        lock.lock()
        defer { lock.unlock() }
        let list = scan()
        cached = list
        return list
    }

    static func match(_ raw: String, in catalog: [MacAppInfo]) -> MacAppInfo? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        var lower = key.lowercased()
        if lower.hasSuffix(".app") { lower = String(lower.dropLast(4)) }
        return catalog.first { $0.processName.lowercased() == lower }
            ?? catalog.first { $0.displayName.lowercased() == lower }
            ?? catalog.first { $0.url.deletingPathExtension().lastPathComponent.lowercased() == lower }
    }

    static func url(forProcessName name: String, catalog: [MacAppInfo]) -> URL? {
        if let app = match(name, in: catalog) { return app.url }
        for running in NSWorkspace.shared.runningApplications {
            if running.localizedName?.caseInsensitiveCompare(name) == .orderedSame
                || running.executableURL?.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
                || running.bundleURL?.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(name) == .orderedSame {
                return running.bundleURL
            }
        }
        return nil
    }

    static func runningProcessNames() -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            let name: String
            if let url = running.bundleURL, let info = info(at: url) {
                name = info.processName
            } else if let localized = running.localizedName, !localized.isEmpty {
                name = localized
            } else {
                continue
            }
            if seen.insert(name.lowercased()).inserted {
                names.append(name)
            }
        }
        return names
    }

    private static func scan() -> [MacAppInfo] {
        var seen = Set<String>()
        var results: [MacAppInfo] = []
        for url in applicationURLs() {
            guard let app = info(at: url) else { continue }
            if seen.insert(app.processName.lowercased()).inserted {
                results.append(app)
            }
        }
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            guard let url = running.bundleURL, let app = info(at: url) else { continue }
            if seen.insert(app.processName.lowercased()).inserted {
                results.append(app)
            }
        }
        return results.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func applicationURLs() -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        for directory in roots() {
            for appURL in collectApps(from: directory, depth: 0) {
                if seen.insert(appURL.path).inserted {
                    urls.append(appURL)
                }
            }
        }
        return urls
    }

    private static func roots() -> [URL] {
        var directories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        directories.append(contentsOf: FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .systemDomainMask, .userDomainMask]))
        return directories
    }

    private static func collectApps(from directory: URL, depth: Int) -> [URL] {
        guard depth < 2 else { return [] }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var apps: [URL] = []
        for url in items {
            if url.pathExtension == "app" {
                apps.append(url)
                continue
            }
            guard depth == 0 else { continue }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                apps.append(contentsOf: collectApps(from: url, depth: depth + 1))
            }
        }
        return apps
    }

    static func info(at url: URL) -> MacAppInfo? {
        guard let bundle = Bundle(url: url), !isAgent(bundle) else { return nil }
        let executable = bundle.executableURL?.lastPathComponent
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)
        guard let processName = executable?.trimmingCharacters(in: .whitespacesAndNewlines), !processName.isEmpty else {
            return nil
        }
        let display = FileManager.default.displayName(atPath: url.path)
        let name: String
        if !display.isEmpty && display != url.lastPathComponent {
            name = display
        } else {
            name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? processName
        }
        return MacAppInfo(
            displayName: name,
            processName: processName,
            url: url,
            bundleIdentifier: bundle.bundleIdentifier ?? url.lastPathComponent
        )
    }

    private static func isAgent(_ bundle: Bundle) -> Bool {
        if flag(bundle.object(forInfoDictionaryKey: "LSUIElement")) { return true }
        if flag(bundle.object(forInfoDictionaryKey: "LSBackgroundOnly")) { return true }
        return false
    }

    private static func flag(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let num = value as? NSNumber { return num.boolValue }
        if let str = value as? String {
            return str == "1" || str.lowercased() == "true" || str.lowercased() == "yes"
        }
        return false
    }
}

struct MacAppGlyph: View {
    var url: URL?
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let url {
                Image(nsImage: MacAppIconCache.image(for: url))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(C.muted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
