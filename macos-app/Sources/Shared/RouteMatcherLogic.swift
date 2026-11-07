import Foundation

enum RouteMatcherKind: String, CaseIterable, Identifiable {
    case domain, domainSuffix, domainKeyword, domainRegex, geosite, geoip, ipCidr, port, network, protocolName

    var id: String { rawValue }

    func encode(_ value: String) -> (domains: [String], ips: [String], port: String, network: String, protocolName: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .domain: return ([v], [], "", "", "")
        case .domainSuffix: return (["suffix:\(v)"], [], "", "", "")
        case .domainKeyword: return (["keyword:\(v)"], [], "", "", "")
        case .domainRegex: return (["regexp:\(v)"], [], "", "", "")
        case .geosite:
            let line = v.hasPrefix("geosite:") ? v : "geosite:\(v)"
            return ([line], [], "", "", "")
        case .geoip:
            let line = v.hasPrefix("geoip:") ? v : "geoip:\(v)"
            return ([], [line], "", "", "")
        case .ipCidr: return ([], [v], "", "", "")
        case .port: return ([], [], v, "", "")
        case .network: return ([], [], "", v.lowercased(), "")
        case .protocolName: return ([], [], "", "", v)
        }
    }

    static func rows(domains: [String], ips: [String], port: String, network: String, protocolName: String) -> [MatcherRow] {
        var out: [MatcherRow] = []
        for d in domains {
            let t = d.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if t.hasPrefix("suffix:") {
                out.append(.init(kind: .domainSuffix, value: String(t.dropFirst(7))))
            } else if t.hasPrefix("keyword:") {
                out.append(.init(kind: .domainKeyword, value: String(t.dropFirst(8))))
            } else if t.hasPrefix("regexp:") {
                out.append(.init(kind: .domainRegex, value: String(t.dropFirst(7))))
            } else if t.hasPrefix("geosite:") {
                out.append(.init(kind: .geosite, value: String(t.dropFirst(8))))
            } else if t.hasPrefix("domain:") {
                out.append(.init(kind: .domain, value: String(t.dropFirst(7))))
            } else {
                out.append(.init(kind: .domain, value: t))
            }
        }
        for ip in ips {
            let t = ip.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if t.hasPrefix("geoip:") {
                out.append(.init(kind: .geoip, value: String(t.dropFirst(6))))
            } else {
                out.append(.init(kind: .ipCidr, value: t))
            }
        }
        if !port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(.init(kind: .port, value: port))
        }
        if network == "tcp" || network == "udp" {
            out.append(.init(kind: .network, value: network))
        }
        if !protocolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(.init(kind: .protocolName, value: protocolName))
        }
        return out
    }

    static func flatten(_ rows: [MatcherRow]) -> (domains: String, ips: String, port: String, network: String, protocolName: String) {
        var domains: [String] = []
        var ips: [String] = []
        var port = ""
        var network = ""
        var proto = ""
        for row in rows {
            let enc = row.kind.encode(row.value)
            domains.append(contentsOf: enc.domains)
            ips.append(contentsOf: enc.ips)
            if !enc.port.isEmpty { port = enc.port }
            if !enc.network.isEmpty { network = enc.network }
            if !enc.protocolName.isEmpty { proto = enc.protocolName }
        }
        return (domains.joined(separator: "\n"), ips.joined(separator: "\n"), port, network, proto)
    }
}

struct MatcherRow: Identifiable, Equatable {
    var id = UUID().uuidString
    var kind: RouteMatcherKind
    var value: String
}
