import AppKit
import CryptoKit
import Foundation
import SwiftUI
@preconcurrency import UserNotifications

struct RemoteRelease: Equatable {
    var version: AppVersion
    var notes: String
    var page: URL?
    var assetURL: URL?
    var sha256: String?

    var display: String { version.display }
}

enum UpdatePhase: Equatable {
    case idle
    case checking
    case upToDate
    case available
    case downloading(Double)
    case failed(String)
}

@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    @Published private(set) var phase: UpdatePhase = .idle
    @Published private(set) var release: RemoteRelease?
    @Published private(set) var dismissedDisplay = ""

    var onToast: ((String, ToastTone) -> Void)?
    private var autoCheck = true
    private var loop: Task<Void, Never>?
    private var busy = false
    private let repo = "DinonowDev/v2open"
    private let dismissedKey = "v2open.update.dismissed"
    private let notifiedKey = "v2open.update.notified"

    private init() {
        dismissedDisplay = UserDefaults.standard.string(forKey: dismissedKey) ?? ""
    }

    var isDownloading: Bool {
        if case .downloading = phase { return true }
        return false
    }

    var showsBanner: Bool {
        guard let release, phase == .available || isDownloading || isFailed else { return false }
        return dismissedDisplay != release.display
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    func start(auto: Bool) {
        autoCheck = auto
        guard loop == nil else { return }
        loop = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            while !Task.isCancelled {
                if self.autoCheck {
                    await self.runCheck(interactive: false)
                }
                try? await Task.sleep(nanoseconds: 6 * 60 * 60 * 1_000_000_000)
            }
        }
    }

    func setAutoCheck(_ on: Bool) {
        autoCheck = on
        if on {
            Task { await runCheck(interactive: false) }
        }
    }

    func check(interactive: Bool) {
        Task { await runCheck(interactive: interactive) }
    }

    func dismiss() {
        guard let release else { return }
        dismissedDisplay = release.display
        UserDefaults.standard.set(release.display, forKey: dismissedKey)
    }

    func downloadAndInstall() {
        guard let release else { return }
        guard let assetURL = release.assetURL else {
            if let page = release.page { NSWorkspace.shared.open(page) }
            return
        }
        guard !busy else { return }
        busy = true
        phase = .downloading(0)
        Task {
            defer { busy = false }
            do {
                let zip = try await download(assetURL)
                if let want = release.sha256, !want.isEmpty {
                    let got = try sha256(of: zip)
                    if got != want.lowercased() {
                        phase = .failed(text("updateChecksum"))
                        return
                    }
                }
                let app = try unzip(zip)
                try validateSignature(of: app)
                try install(app)
            } catch {
                phase = .failed(error.localizedDescription)
                DevLog.error("update", error.localizedDescription)
            }
        }
    }

    private func runCheck(interactive: Bool) async {
        if isDevBuild {
            if interactive { toast(text("updateDevSkipped"), .info) }
            return
        }
        if busy || isDownloading { return }
        busy = true
        phase = .checking
        defer {
            if case .checking = phase { phase = release == nil ? .idle : .available }
            busy = false
        }
        do {
            let found = try await fetchLatest()
            let current = currentVersion()
            guard found.version.isNewer(than: current) else {
                release = nil
                phase = .upToDate
                if interactive { toast(text("upToDate"), .success) }
                return
            }
            release = found
            phase = .available
            if dismissedDisplay != found.display {
                notify(found)
            }
            if found.assetURL == nil, interactive {
                toast(text("updateNoAsset"), .warning)
            }
        } catch {
            phase = .failed(error.localizedDescription)
            if interactive { toast(text("updateFailed"), .error) }
            DevLog.error("update", error.localizedDescription)
            if !interactive, release == nil { phase = .idle }
        }
    }

    private var isDevBuild: Bool {
        let id = Bundle.main.bundleIdentifier ?? ""
        if id.contains(".dev") { return true }
        return Bundle.main.bundleURL.lastPathComponent.contains("V2Open-Dev")
    }

    private func currentVersion() -> AppVersion {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
        return AppVersion.parse(short, build: build)
    }

    private func fetchLatest() async throws -> RemoteRelease {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("V2Open", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw UpdateError(text("updateFailed") + " (HTTP \(code))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UpdateError(text("updateFailed"))
        }
        var tag = json["tag_name"] as? String ?? ""
        if tag.hasPrefix("v") || tag.hasPrefix("V") { tag = String(tag.dropFirst()) }
        let notes = json["body"] as? String ?? ""
        let page = URL(string: json["html_url"] as? String ?? "")
        let assets = json["assets"] as? [[String: Any]] ?? []
        let names = assets.compactMap { $0["name"] as? String }
        let picked = v2openPickReleaseAsset(names: names, arch: v2openMacArch())
        let asset = assets.first { ($0["name"] as? String) == picked }
        let assetURL = URL(string: asset?["browser_download_url"] as? String ?? "")
        var sha = ""
        if let digest = asset?["digest"] as? String {
            let lower = digest.lowercased()
            if lower.hasPrefix("sha256:") { sha = String(lower.dropFirst("sha256:".count)) }
        }
        let build = v2openAssetBuild(picked ?? "")
        return RemoteRelease(
            version: AppVersion.parse(tag, build: build),
            notes: String(notes.prefix(4000)),
            page: page,
            assetURL: assetURL,
            sha256: sha.isEmpty ? nil : sha
        )
    }

    private func download(_ url: URL) async throws -> URL {
        let fetcher = UpdateFetcher()
        fetcher.onProgress = { [weak self] value in
            self?.phase = .downloading(value)
        }
        return try await fetcher.download(url)
    }

    private func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func unzip(_ zip: URL) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("V2Open-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-x", "-k", zip.path, root.path]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw UpdateError(text("updateFailed")) }
        try? FileManager.default.removeItem(at: zip)
        guard let app = findApp(in: root) else { throw UpdateError(text("updateFailed")) }
        return app
    }

    private func findApp(in root: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == "V2Open.app" {
                enumerator?.skipDescendants()
                return url
            }
        }
        return nil
    }

    private func validateSignature(of app: URL) throws {
        let current = teamIdentifier(Bundle.main.bundleURL)
        let incoming = teamIdentifier(app)
        if !current.isEmpty, current != "not set", incoming != current {
            throw UpdateError(text("updateSignature"))
        }
    }

    private func teamIdentifier(_ app: URL) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", "--verbose=4", app.path]
        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = pipe
        do { try task.run() } catch { return "" }
        task.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in text.split(separator: "\n") {
            if line.hasPrefix("TeamIdentifier=") {
                return String(line.dropFirst("TeamIdentifier=".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private func install(_ app: URL) throws {
        guard let dest = installDestination() else {
            NSWorkspace.shared.activateFileViewerSelecting([app])
            phase = .available
            toast(text("updateReady", vars: ["version": release?.display ?? ""]), .info)
            return
        }
        let script = try writeInstallScript()
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("v2open-update.log")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-c", #"nohup /bin/bash "$V2OPEN_UPDATE_SCRIPT" "$V2OPEN_UPDATE_PID" "$V2OPEN_UPDATE_SRC" "$V2OPEN_UPDATE_DEST" >>"$V2OPEN_UPDATE_LOG" 2>&1 &"#]
        var env = ProcessInfo.processInfo.environment
        env["V2OPEN_UPDATE_SCRIPT"] = script.path
        env["V2OPEN_UPDATE_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        env["V2OPEN_UPDATE_SRC"] = app.path
        env["V2OPEN_UPDATE_DEST"] = dest.path
        env["V2OPEN_UPDATE_LOG"] = log.path
        proc.environment = env
        try proc.run()
        proc.waitUntilExit()
        toast(text("installAndRestart"), .success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    private func installDestination() -> URL? {
        let bundle = Bundle.main.bundleURL
        if bundle.lastPathComponent == "V2Open.app" {
            let parent = bundle.deletingLastPathComponent()
            if FileManager.default.isWritableFile(atPath: parent.path) { return bundle }
        }
        let apps = URL(fileURLWithPath: "/Applications")
        if FileManager.default.isWritableFile(atPath: apps.path) {
            return apps.appendingPathComponent("V2Open.app")
        }
        return nil
    }

    private func writeInstallScript() throws -> URL {
        let script = """
        #!/bin/bash
        set -euo pipefail
        PARENT="$1"
        SRC="$2"
        DEST="$3"
        for _ in $(seq 1 200); do
          if ! kill -0 "$PARENT" 2>/dev/null; then
            break
          fi
          sleep 0.2
        done
        sleep 0.4
        rm -rf "$DEST"
        ditto "$SRC" "$DEST"
        if ! spctl --assess --type execute "$DEST" >/dev/null 2>&1; then
          xattr -cr "$DEST" || true
        fi
        open "$DEST"
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("v2open-install-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func notify(_ release: RemoteRelease) {
        let marker = release.display
        if UserDefaults.standard.string(forKey: notifiedKey) == marker { return }
        UserDefaults.standard.set(marker, forKey: notifiedKey)
        let body = text("updateReady", vars: ["version": release.display])
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "V2Open"
            content.body = body
            content.sound = .default
            content.userInfo = ["kind": "update"]
            center.add(UNNotificationRequest(identifier: "v2open-update-\(marker)", content: content, trigger: nil))
        }
    }

    private func text(_ key: String, vars: [String: String] = [:]) -> String {
        let language = MenuBarCenter.shared.language
        var value = LocaleStore.string(key, language: language)
        for (name, replacement) in vars {
            value = value.replacingOccurrences(of: "{\(name)}", with: replacement)
        }
        return value
    }

    private func toast(_ message: String, _ tone: ToastTone) {
        onToast?(message, tone)
    }
}

private struct UpdateError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private final class UpdateFetcher: NSObject, URLSessionDownloadDelegate {
    var onProgress: @MainActor (Double) -> Void = { _ in }
    private var continuation: CheckedContinuation<URL, Error>?
    private var finished = false

    func download(_ url: URL) async throws -> URL {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor in self.onProgress(min(max(fraction, 0), 1)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            finish(.failure(UpdateError("HTTP \(http.statusCode)")))
            return
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("V2Open-\(UUID().uuidString).zip")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            finish(.success(dest))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !finished else { return }
        finished = true
        continuation?.resume(with: result)
        continuation = nil
    }
}

struct UpdateBanner: View {
    @ObservedObject private var updater = AppUpdater.shared
    @EnvironmentObject private var model: Model

    var body: some View {
        if updater.showsBanner, let release = updater.release {
            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(C.cyan)
                        Mix(text: model.t("updateAvailable"), size: 14, weight: .semibold)
                        Spacer(minLength: 0)
                        Button(model.t("later")) { updater.dismiss() }
                            .buttonStyle(.plain)
                            .foregroundStyle(C.muted)
                    }
                    Mix(text: model.t("updateReady", vars: ["version": release.display]), size: 12, color: C.muted)
                    if case .downloading(let progress) = updater.phase {
                        Mix(text: model.t("downloadingUpdate", vars: ["percent": "\(Int(progress * 100))%"]), size: 12, color: C.cyan)
                    }
                    if case .failed(let message) = updater.phase {
                        Mix(text: message, size: 12, color: Color(red: 1, green: 0.36, blue: 0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        SheetActionButton(
                            title: actionTitle,
                            compact: true,
                            primary: true,
                            icon: "arrow.down.circle"
                        ) {
                            updater.downloadAndInstall()
                        }
                        if let page = release.page {
                            SheetActionButton(title: model.t("viewRelease"), compact: true, icon: "safari") {
                                NSWorkspace.shared.open(page)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .padding(.top, 8)
        }
    }

    private var actionTitle: String {
        if case .downloading(let progress) = updater.phase {
            return model.t("downloadingUpdate", vars: ["percent": "\(Int(progress * 100))%"])
        }
        if updater.release?.assetURL == nil { return model.t("viewRelease") }
        return model.t("downloadAndInstall")
    }
}
