import SwiftUI

extension RouteMatcherKind {
    @MainActor
    func label(_ model: Model) -> String {
        switch self {
        case .domain: return model.t("matcherDomain")
        case .domainSuffix: return model.t("matcherSuffix")
        case .domainKeyword: return model.t("matcherKeyword")
        case .domainRegex: return model.t("matcherRegex")
        case .geosite: return model.t("matcherGeosite")
        case .geoip: return model.t("matcherGeoip")
        case .ipCidr: return model.t("matcherIp")
        case .port: return model.t("port")
        case .network: return model.t("network")
        case .protocolName: return model.t("protocol")
        }
    }

    var placeholder: String {
        switch self {
        case .domain: return "google.com"
        case .domainSuffix: return "google.com"
        case .domainKeyword: return "google"
        case .domainRegex: return ".*\\.google\\..*"
        case .geosite: return "category-ads-all"
        case .geoip: return "ir"
        case .ipCidr: return "10.0.0.0/8"
        case .port: return "443"
        case .network: return "tcp"
        case .protocolName: return "bittorrent"
        }
    }
}

struct RouteMatcherEditor: View {
    @EnvironmentObject var model: Model
    @Binding var rows: [MatcherRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Mix(text: model.t("ruleMatchers"), size: 13, weight: .semibold, color: C.muted)
                Spacer()
                Button {
                    rows.append(MatcherRow(kind: .domain, value: ""))
                } label: {
                    Label(model.t("ruleAddMatcher"), systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(C.cyan)
                }
                .buttonStyle(QuietPressStyle())
            }
            ForEach($rows) { $row in
                MatcherRowView(row: $row, onDelete: { rows.removeAll { $0.id == row.id } })
            }
            if rows.isEmpty {
                Mix(text: model.t("ruleMatcherHint"), size: 12, color: C.muted)
            }
        }
    }
}

private struct MatcherRowView: View {
    @EnvironmentObject var model: Model
    @Binding var row: MatcherRow
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SoftSelect(
                title: "",
                value: row.kind.rawValue,
                options: RouteMatcherKind.allCases.map { ($0.rawValue, $0.label(model)) },
                wide: false,
                icon: "line.3.horizontal.decrease.circle",
                onSelect: { raw in
                    if let k = RouteMatcherKind(rawValue: raw) { row.kind = k }
                }
            )
            .frame(width: 148)
            V2Field(placeholder: row.kind.placeholder, text: $row.value, latin: true, icon: "text.cursor")
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color(red: 1, green: 0.36, blue: 0.45))
            }
            .buttonStyle(QuietPressStyle())
        }
    }
}

enum RouteRuleTemplates {
    @MainActor
    static func apply(_ key: String, model: Model) {
        let rule: [String: Any]
        switch key {
        case "block_ads":
            rule = [
                "remark": model.t("tplBlockAds"),
                "behavior": "block",
                "domains": ["geosite:category-ads-all"],
                "ips": [String](),
                "port": "",
                "network": "",
                "protocol": "",
                "inbounds": [String](),
                "sources": [String](),
                "source_port": "",
                "users": [String](),
                "balancer_tag": "",
                "enabled": true
            ]
        case "direct_cn":
            rule = [
                "remark": model.t("tplDirectCn"),
                "behavior": "direct",
                "domains": ["geosite:cn"],
                "ips": ["geoip:cn"],
                "port": "",
                "network": "",
                "protocol": "",
                "inbounds": [String](),
                "sources": [String](),
                "source_port": "",
                "users": [String](),
                "balancer_tag": "",
                "enabled": true
            ]
        case "proxy_google":
            rule = [
                "remark": model.t("tplProxyGoogle"),
                "behavior": "proxy",
                "domains": ["geosite:google"],
                "ips": [String](),
                "port": "",
                "network": "",
                "protocol": "",
                "inbounds": [String](),
                "sources": [String](),
                "source_port": "",
                "users": [String](),
                "balancer_tag": "",
                "enabled": true
            ]
        default:
            return
        }
        _ = model.call("save_route", ["route": rule])
        model.refresh()
        model.showToast(model.t("imported"), tone: .success)
    }
}

struct RouteMatcherChips: View {
    var rule: [String: Any]

    var body: some View {
        let domains = rule["domains"] as? [String] ?? []
        let ips = rule["ips"] as? [String] ?? []
        let port = rule["port"] as? String ?? ""
        let network = rule["network"] as? String ?? ""
        let proto = rule["protocol"] as? String ?? ""
        let rows = RouteMatcherKind.rows(domains: domains, ips: ips, port: port, network: network, protocolName: proto)
        if rows.isEmpty {
            EmptyView()
        } else {
            FlowLayout(spacing: 6) {
                ForEach(rows.prefix(6), id: \.id) { row in
                    Text(chipLabel(row))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(C.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(C.cyan.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func chipLabel(_ row: MatcherRow) -> String {
        let prefix: String
        switch row.kind {
        case .geosite: prefix = "GEOSITE"
        case .geoip: prefix = "GEOIP"
        case .ipCidr: prefix = "IP"
        case .port: prefix = "PORT"
        case .network: return row.value.uppercased()
        case .protocolName: return row.value
        default: prefix = row.kind.rawValue.uppercased()
        }
        let value = row.value
        if value.count > 18 {
            return "\(prefix) \(value.prefix(16))…"
        }
        return "\(prefix) \(value)"
    }
}

/// Simple wrapping layout for matcher chips in the rule list.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, point) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? 360
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var positions: [CGPoint] = []
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
