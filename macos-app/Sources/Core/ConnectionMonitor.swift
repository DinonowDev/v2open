import Foundation

@MainActor
final class ConnectionMonitor {
    private weak var model: Model?
    private var userDisconnect = false
    private var lastErrorNotified = ""
    private let subscriptionKey = "v2open.notify.subscription.sent"

    init(model: Model) {
        self.model = model
    }

    func markUserDisconnect() {
        userDisconnect = true
    }

    func afterTick(wasConnected: Bool) {
        guard let model else { return }
        let connected = model.runtime["connected"] as? Bool == true
        let error = (model.runtime["error"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let phase = model.runtime["phase"] as? String ?? ""

        if wasConnected && !connected {
            if userDisconnect {
                userDisconnect = false
            } else {
                postDisconnect(model: model)
            }
        }

        if AppNotifications.settingEnabled("notify_errors", default: true) {
            let showError = !error.isEmpty && (phase == "error" || phase == "killswitch")
            if showError, error != lastErrorNotified {
                lastErrorNotified = error
                postError(model: model, error: error, identifier: "v2open-error-\(error.hashValue)")
            }
            if error.isEmpty {
                lastErrorNotified = ""
            }
        }

        if connected && error.isEmpty {
            lastErrorNotified = ""
        }

        checkSubscriptions()
    }

    func tunnelDroppedExternally() {
        guard let model else { return }
        if userDisconnect {
            userDisconnect = false
            return
        }
        _ = model.call("disconnect")
        model.refresh()
        postDisconnect(model: model)
    }

    private func postDisconnect(model: Model) {
        guard AppNotifications.settingEnabled("notify_disconnect", default: true) else { return }
        AppNotifications.post(
            kind: .disconnect,
            title: model.t("notifyDisconnectedTitle"),
            body: model.t("notifyDisconnectedBody"),
            identifier: "v2open-disconnect-\(Int(Date().timeIntervalSince1970))"
        )
    }

    private func postError(model: Model, error: String, identifier: String) {
        AppNotifications.post(
            kind: .error,
            title: model.t("notifyErrorTitle"),
            body: model.t("notifyErrorBody", vars: ["error": error]),
            identifier: identifier
        )
    }

    func notifyConnectFailure(_ message: String) {
        guard let model, AppNotifications.settingEnabled("notify_errors", default: true) else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        postError(model: model, error: trimmed, identifier: "v2open-connect-\(trimmed.hashValue)")
    }

    private func checkSubscriptions() {
        guard let model, AppNotifications.settingEnabled("notify_subscription", default: true) else { return }
        var sent = UserDefaults.standard.stringArray(forKey: subscriptionKey) ?? []
        let now = Int64(Date().timeIntervalSince1970)

        for group in model.groups {
            let gid = group["id"] as? String ?? ""
            let name = (group["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? model.t("remoteGroup")
            let url = (group["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { continue }

            let expire = jsonUInt(group["expire"])
            if expire > 0 {
                let left = Int64(expire) - now
                let days = max(0, left / 86_400)
                if left <= 0 {
                    let key = "exp:\(gid)"
                    if !sent.contains(key) {
                        AppNotifications.post(
                            kind: .subscription,
                            title: model.t("notifyExpiredTitle"),
                            body: model.t("notifyExpiredBody", vars: ["name": name]),
                            identifier: key,
                            userInfo: ["group_id": gid]
                        )
                        sent.append(key)
                    }
                } else if days <= 3 {
                    let key = "soon:\(gid):\(days)"
                    if !sent.contains(key) {
                        AppNotifications.post(
                            kind: .subscription,
                            title: model.t("notifyExpireTitle"),
                            body: model.t("notifyExpireBody", vars: ["name": name, "days": "\(days)"]),
                            identifier: key,
                            userInfo: ["group_id": gid]
                        )
                        sent.append(key)
                    }
                }
            }

            let total = jsonUInt(group["total"])
            let upload = jsonUInt(group["upload"])
            let download = jsonUInt(group["download"])
            if total > 0 {
                let used = upload &+ download
                let percent = Int(min(100, used * 100 / max(total, 1)))
                if percent >= 90 {
                    let key = "quota:\(gid):\(percent / 10)"
                    if !sent.contains(key) {
                        AppNotifications.post(
                            kind: .subscription,
                            title: model.t("notifyQuotaTitle"),
                            body: model.t("notifyQuotaBody", vars: ["name": name, "percent": "\(percent)"]),
                            identifier: key,
                            userInfo: ["group_id": gid]
                        )
                        sent.append(key)
                    }
                }
            }
        }

        if sent.count > 200 {
            sent = Array(sent.suffix(120))
        }
        UserDefaults.standard.set(sent, forKey: subscriptionKey)
    }
}

extension Notification.Name {
    static let v2openTunnelDropped = Notification.Name("v2open.tunnelDropped")
}
