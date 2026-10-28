import Foundation
import AppKit

enum DevLog {
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static var enabled: Bool {
        Bundle.main.bundleIdentifier == "local.v2open.dev"
            || Bundle.main.bundleURL.path.contains("V2Open-Dev.app")
            || ProcessInfo.processInfo.environment["V2OPEN_DEV_LOG"] == "1"
    }

    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.prefix(12).joined(separator: " | ")
            DevLog.error("exception", "\(exception.name.rawValue): \(exception.reason ?? "") \(stack)")
        }
    }

    static func event(_ category: String, _ message: String) {
        write(category, message)
    }

    static func error(_ category: String, _ message: String) {
        write(category, message)
    }

    private static func write(_ category: String, _ message: String) {
        guard enabled else { return }
        let line = "\(stamp.string(from: Date())) [\(category)] \(message)\n"
        fputs(line, stderr)
        append(line, to: supportLogURL)
        if let repo = repoLogURL {
            append(line, to: repo)
        }
    }

    private static var supportLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/V2Open/core.log", isDirectory: false)
    }

    private static var repoLogURL: URL? {
        let parent = Bundle.main.bundleURL.deletingLastPathComponent()
        let marker = parent.appendingPathComponent("dev-macos.sh")
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        return parent.appendingPathComponent("dev-logs/runtime.log")
    }

    private static func append(_ line: String, to url: URL) {
        guard let data = line.data(using: .utf8) else { return }
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            fputs("devlog write failed \(url.path): \(error)\n", stderr)
        }
    }
}
