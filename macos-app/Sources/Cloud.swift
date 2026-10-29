import CloudKit
import Foundation

struct CloudBackupItem: Identifiable {
    var id: String
    var name: String
    var created: Date
}

final class CloudSync {
    static let shared = CloudSync()
    private let queue = DispatchQueue(label: "v2open.cloud")
    private var last = Date.distantPast
    private let container = CKContainer(identifier: "iCloud.local.v2open.desktop")

    enum AccountKind { case available, noAccount, restricted, unknown }

    func account(completion: @escaping (AccountKind) -> Void) {
        container.accountStatus { status, _ in
            let kind: AccountKind
            switch status {
            case .available: kind = .available
            case .noAccount: kind = .noAccount
            case .restricted, .temporarilyUnavailable: kind = .restricted
            default: kind = .unknown
            }
            DispatchQueue.main.async { completion(kind) }
        }
    }

    func syncServers(completion: @escaping (Bool) -> Void) {
        queue.async {
            self.syncLibrary()
            DispatchQueue.main.async { completion(true) }
        }
    }

    func localSynced(completion: @escaping (Bool) -> Void) {
        queue.async {
            let local = self.libraryURL()
            let cloud = self.driveURL()
            var synced = false
            if let local, let cloud,
               FileManager.default.fileExists(atPath: local.path),
               FileManager.default.fileExists(atPath: cloud.path) {
                let l = (try? FileManager.default.attributesOfItem(atPath: local.path)[.modificationDate] as? Date) ?? .distantPast
                let r = (try? FileManager.default.attributesOfItem(atPath: cloud.path)[.modificationDate] as? Date) ?? .distantPast
                synced = abs(l.timeIntervalSince(r)) < 5
            }
            DispatchQueue.main.async { completion(synced) }
        }
    }

    func kick(force: Bool = false) {
        queue.async { [weak self] in
            guard let self else { return }
            if !force, Date().timeIntervalSince(self.last) < 45 { return }
            self.last = Date()
            self.syncLibrary()
        }
    }

    func listNamed(completion: @escaping ([CloudBackupItem]) -> Void) {
        queue.async {
            let database = self.container.privateCloudDatabase
            let query = CKQuery(recordType: "NamedBackup", predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            database.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { result in
                let records: [CKRecord]
                switch result {
                case .success(let page):
                    records = page.matchResults.compactMap { try? $0.1.get() }
                case .failure:
                    records = []
                }
                let items = records.map { record in
                    CloudBackupItem(
                        id: record.recordID.recordName,
                        name: record["name"] as? String ?? record.recordID.recordName,
                        created: record["createdAt"] as? Date ?? Date()
                    )
                }
                DispatchQueue.main.async { completion(items) }
            }
        }
    }

    func saveNamed(name: String, completion: @escaping (Bool) -> Void) {
        queue.async {
            guard let local = self.libraryURL(), FileManager.default.fileExists(atPath: local.path) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let id = CKRecord.ID(recordName: UUID().uuidString)
            let record = CKRecord(recordType: "NamedBackup", recordID: id)
            record["name"] = name as CKRecordValue
            record["createdAt"] = Date() as CKRecordValue
            record["payload"] = CKAsset(fileURL: local)
            self.container.privateCloudDatabase.save(record) { _, error in
                DispatchQueue.main.async { completion(error == nil) }
            }
        }
    }

    func restoreNamed(id: String, completion: @escaping (Bool) -> Void) {
        queue.async {
            let recordID = CKRecord.ID(recordName: id)
            self.container.privateCloudDatabase.fetch(withRecordID: recordID) { record, _ in
                guard let asset = record?["payload"] as? CKAsset, let file = asset.fileURL, let local = self.libraryURL() else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                try? FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: local)
                try? FileManager.default.copyItem(at: file, to: local)
                DispatchQueue.main.async { completion(true) }
            }
        }
    }

    func deleteNamed(id: String, completion: @escaping (Bool) -> Void) {
        queue.async {
            self.container.privateCloudDatabase.delete(withRecordID: CKRecord.ID(recordName: id)) { _, error in
                DispatchQueue.main.async { completion(error == nil) }
            }
        }
    }

    private func syncLibrary() {
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
            next["updatedAt"] = Date() as CKRecordValue
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
