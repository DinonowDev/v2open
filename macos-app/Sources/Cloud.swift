import CloudKit
import Foundation
import Security

struct CloudBackupItem: Identifiable {
    var id: String
    var name: String
    var created: Date
}

final class CloudSync {
    static let shared = CloudSync()
    private let queue = DispatchQueue(label: "v2open.cloud")
    private var last = Date.distantPast
    private let containerID = "iCloud.local.v2open.desktop"
    private let container: CKContainer?

    enum AccountKind { case available, noAccount, restricted, unknown }

    private init() {
        container = Self.makeContainer(id: containerID)
    }

    func account(completion: @escaping (AccountKind) -> Void) {
        guard let container else {
            DispatchQueue.main.async { completion(.unknown) }
            return
        }
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
        guard container != nil else {
            DispatchQueue.main.async { completion(false) }
            return
        }
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
        guard container != nil else { return }
        queue.async { [weak self] in
            guard let self else { return }
            if !force, Date().timeIntervalSince(self.last) < 45 { return }
            self.last = Date()
            self.syncLibrary()
        }
    }

    func listNamed(completion: @escaping ([CloudBackupItem]) -> Void) {
        guard let container else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        queue.async {
            let database = container.privateCloudDatabase
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
        guard let container else {
            DispatchQueue.main.async { completion(false) }
            return
        }
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
            container.privateCloudDatabase.save(record) { _, error in
                DispatchQueue.main.async { completion(error == nil) }
            }
        }
    }

    func restoreNamed(id: String, completion: @escaping (Bool) -> Void) {
        guard let container else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        queue.async {
            let recordID = CKRecord.ID(recordName: id)
            container.privateCloudDatabase.fetch(withRecordID: recordID) { record, _ in
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
        guard let container else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        queue.async {
            container.privateCloudDatabase.delete(withRecordID: CKRecord.ID(recordName: id)) { _, error in
                DispatchQueue.main.async { completion(error == nil) }
            }
        }
    }

    private func syncLibrary() {
        guard let container else { return }
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

    private static func makeContainer(id: String) -> CKContainer? {
        guard cloudKitAllowed(containerID: id) else { return nil }
        return CKContainer(identifier: id)
    }

    private static func cloudKitAllowed(containerID: String) -> Bool {
        let ents = signingEntitlements()
        guard !ents.isEmpty else { return false }
        let team = ents["com.apple.developer.team-identifier"] as? String ?? ""
        guard !team.isEmpty else { return false }
        let services = ents["com.apple.developer.icloud-services"]
        let hasCloudKit: Bool
        if let list = services as? [String] {
            hasCloudKit = list.contains("CloudKit")
        } else if let list = services as? [Any] {
            hasCloudKit = list.contains { "\($0)" == "CloudKit" }
        } else {
            hasCloudKit = false
        }
        let ids = ents["com.apple.developer.icloud-container-identifiers"] as? [String] ?? []
        return hasCloudKit && ids.contains(containerID)
    }

    private static func signingEntitlements() -> [String: Any] {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return [:] }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return [:] }
        return dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
    }
}
