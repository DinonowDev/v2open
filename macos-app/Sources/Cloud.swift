import CloudKit
import Foundation

final class CloudSync {
    static let shared = CloudSync()
    private let queue = DispatchQueue(label: "v2open.cloud")
    private var last = Date.distantPast
    private let container = CKContainer(identifier: "iCloud.local.v2open.desktop")

    func kick() {
        queue.async { [weak self] in
            guard let self, Date().timeIntervalSince(self.last) > 45 else { return }
            self.last = Date()
            self.sync()
        }
    }

    private func sync() {
        let group = DispatchGroup()
        var available = false
        group.enter()
        container.accountStatus { status, _ in
            available = status == .available
            group.leave()
        }
        _ = group.wait(timeout: .now() + 3)
        guard available else { return }
        let local = libraryURL()
        let cloud = driveURL()
        guard let local, FileManager.default.fileExists(atPath: local.path) else { return }
        let database = container.privateCloudDatabase
        let id = CKRecord.ID(recordName: "library")
        let wait = DispatchGroup()
        wait.enter()
        database.fetch(withRecordID: id) { record, _ in
            if let asset = record?["payload"] as? CKAsset, let file = asset.fileURL, let cloud,
               let remote = try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date,
               let ours = try? FileManager.default.attributesOfItem(atPath: local.path)[.modificationDate] as? Date,
               remote > ours {
                try? FileManager.default.createDirectory(at: cloud.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: cloud)
                try? FileManager.default.copyItem(at: file, to: cloud)
            }
            let next = record ?? CKRecord(recordType: "Library", recordID: id)
            next["payload"] = CKAsset(fileURL: local)
            database.save(next) { _, _ in wait.leave() }
        }
        _ = wait.wait(timeout: .now() + 8)
    }

    private func libraryURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("V2Open/library.json")
    }

    private func driveURL() -> URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/V2Open/library.json")
    }
}
