import AppKit
import Darwin
import Foundation

enum BackgroundScheduler {
    static let label = "app.v2open.scheduler"

    static var agentRequested: Bool {
        CommandLine.arguments.contains("--agent") || CommandLine.arguments.contains("--daemon")
    }

    static func runIfRequested() {
        guard agentRequested else { return }
        bootstrapCore()
        setenv("V2OPEN_DAEMON", "1", 1)
        if CommandLine.arguments.contains("--agent") {
            _ = v2RPC(method: "tick")
            Darwin.exit(0)
        }
        while true {
            if UILock.isHeldByOtherProcess() {
                Thread.sleep(forTimeInterval: 5)
                continue
            }
            _ = v2RPC(method: "tick")
            Thread.sleep(forTimeInterval: 4)
        }
    }

    static func bootstrapCore() {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/V2Open", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let rules = support.appendingPathComponent("rulesets")
        let bin = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/sing-box").path
        _ = support.path.withCString { d in
            bin.withCString { b in
                rules.path.withCString { r in v2_init(d, b, r) }
            }
        }
    }

    static func syncLaunchAgent(enabled: Bool) {
        let plist = plistURL()
        if enabled {
            writePlist(to: plist)
            _ = launchctl(["bootstrap", "gui/\(getuid())", plist.path])
        } else {
            _ = launchctl(["bootout", "gui/\(getuid())/\(label)"])
        }
    }

    static func installIfNeeded(geoAuto: Bool, onDemand: Bool, persist: Bool, groupAuto: Bool = false) {
        syncLaunchAgent(enabled: geoAuto || onDemand || persist || groupAuto)
    }

    private static func plistURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    private static func writePlist(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let exe = Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments[0]
        let body: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe, "--daemon"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 10,
            "ProcessType": "Background"
        ]
        if let data = try? PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0) {
            try? data.write(to: url)
        }
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }
}

enum UILock {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/V2Open/ui.lock")
    }

    static func acquire() {
        try? "\(ProcessInfo.processInfo.processIdentifier)\n".write(to: url, atomically: true, encoding: .utf8)
    }

    static func release() {
        try? FileManager.default.removeItem(at: url)
    }

    static func isHeldByOtherProcess() -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid != ProcessInfo.processInfo.processIdentifier else {
            return false
        }
        return kill(pid, 0) == 0
    }
}

final class TickActivity {
    private let scheduler = NSBackgroundActivityScheduler(identifier: "app.v2open.tick")

    func start(_ tick: @escaping () -> Void) {
        scheduler.repeats = true
        scheduler.interval = 30
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            tick()
            completion(.finished)
        }
    }

    func invalidate() {
        scheduler.invalidate()
    }
}
