import Foundation
import UserNotifications

enum AppNotificationKind: String {
    case update
    case disconnect
    case error
    case subscription
}

@MainActor
enum AppNotifications {
    private static let center = UNUserNotificationCenter.current()
    private static var authorized = false

    static func prepare() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                authorized = granted
            }
        }
    }

    static func settingEnabled(_ key: String, default defaultValue: Bool = true) -> Bool {
        let settings = (v2RPC(method: "state")["data"] as? [String: Any])?["settings"] as? [String: Any] ?? [:]
        return settings[key] as? Bool ?? defaultValue
    }

    static func post(
        kind: AppNotificationKind,
        title: String,
        body: String,
        identifier: String,
        userInfo: [String: Any] = [:]
    ) {
        let allowed: Bool
        switch kind {
        case .update:
            allowed = settingEnabled("app_update_check", default: true)
        case .disconnect:
            allowed = settingEnabled("notify_disconnect", default: true)
        case .error:
            allowed = settingEnabled("notify_errors", default: true)
        case .subscription:
            allowed = settingEnabled("notify_subscription", default: true)
        }
        guard allowed else { return }

        let deliver = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            var info = userInfo
            info["kind"] = kind.rawValue
            content.userInfo = info
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }

        if authorized {
            deliver()
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                authorized = granted
                if granted { deliver() }
            }
        }
    }
}
