import AppKit
import SwiftUI

struct SubscriptionQuotaView: View {
    @EnvironmentObject var model: Model
    var group: [String: Any]

    var body: some View {
        let upload = jsonUInt(group["upload"])
        let download = jsonUInt(group["download"])
        let total = jsonUInt(group["total"])
        let expire = jsonUInt(group["expire"])
        let used = upload + download
        let announce = (group["announcement"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let showTraffic = total > 0
        let showExpire = expire > 0
        if !showTraffic && !showExpire && announce.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if showExpire || showTraffic {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if showExpire {
                            Mix(text: expireLabel(expire), size: 11, weight: .semibold, color: expireColor(expire))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if showTraffic {
                            Mix(
                                text: "\(formatBytes(used)) / \(formatBytes(total))",
                                size: 11,
                                weight: .medium,
                                color: C.muted
                            )
                            .lineLimit(1)
                        } else if showExpire {
                            Mix(text: model.t("unlimitedTraffic"), size: 11, color: C.muted)
                                .lineLimit(1)
                        }
                    }
                }
                if showTraffic {
                    let ratio = min(1, Double(used) / Double(max(total, 1)))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(C.line.opacity(0.9))
                            Capsule()
                                .fill(barColor(ratio: ratio))
                                .frame(width: max(4, geo.size.width * ratio))
                        }
                    }
                    .frame(height: 5)
                }
                if !announce.isEmpty {
                    Mix(text: announce, size: 11, color: C.muted.opacity(0.95))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    func expireSeconds(_ raw: UInt64) -> TimeInterval {
        if raw > 1_000_000_000_000 { return TimeInterval(raw / 1000) }
        return TimeInterval(raw)
    }

    func expireLabel(_ raw: UInt64) -> String {
        let exp = expireSeconds(raw)
        if exp <= 0 { return "" }
        let now = Date().timeIntervalSince1970
        if exp < now { return model.t("expired") }
        let days = Int(ceil((exp - now) / 86400))
        if days <= 0 { return model.t("expiresToday") }
        if model.fa { return "\(days) \(model.t("daysLeft"))" }
        return "\(days) \(model.t("daysLeft"))"
    }

    func expireColor(_ raw: UInt64) -> Color {
        let exp = expireSeconds(raw)
        if exp < Date().timeIntervalSince1970 { return Color(red: 1, green: 0.36, blue: 0.45) }
        let days = (exp - Date().timeIntervalSince1970) / 86400
        if days <= 3 { return Color(red: 1, green: 0.72, blue: 0.28) }
        return C.cyan
    }

    func barColor(ratio: Double) -> Color {
        if ratio >= 0.95 { return Color(red: 1, green: 0.36, blue: 0.45) }
        if ratio >= 0.8 { return Color(red: 1, green: 0.72, blue: 0.28) }
        return C.cyan
    }
}
