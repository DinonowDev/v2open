import Foundation
import NetworkExtension

struct TunnelStartOptions {
    var configPath: String
    var socksPort: Int
    var mtu: Int
    var includeLocal: Bool
    var includeAll: Bool
    var includeApns: Bool
    var killSwitch: Bool
    var combiner: Bool
    var launchCore: Bool
    var dns: String
    var onDemand: Bool
    var rules: String
    var engine: String
    var enforceRoutes: Bool
    var includeCellular: Bool
    var useXrayTun: Bool
}

final class TunnelManager: NSObject {
    static let shared = TunnelManager()
    private var manager: NETunnelProviderManager?
    private(set) var usingSystem = false
    private(set) var lastReloaded = false

    func connect(_ options: TunnelStartOptions, completion: @escaping (Bool) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error {
                DevLog.error("tunnel", "preferences: \(error.localizedDescription)")
                completion(false)
                return
            }
            guard let self else { completion(false); return }
            let manager = managers?.first ?? NETunnelProviderManager()
            self.apply(options, to: manager)
            manager.saveToPreferences { error in
                if let error {
                    DevLog.error("tunnel", "save: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                manager.loadFromPreferences { error in
                    if let error {
                        DevLog.error("tunnel", "load: \(error.localizedDescription)")
                        completion(false)
                        return
                    }
                    do {
                        try manager.connection.startVPNTunnel()
                        self.manager = manager
                        self.usingSystem = true
                        self.lastReloaded = false
                        completion(true)
                    } catch {
                        DevLog.error("tunnel", "start: \(error.localizedDescription)")
                        self.usingSystem = false
                        completion(false)
                    }
                }
            }
        }
    }

    func reload(_ options: TunnelStartOptions, completion: @escaping (Bool) -> Void) {
        guard usingSystem, let session = (manager?.connection as? NETunnelProviderSession) else {
            connect(options, completion: completion)
            return
        }
        let payload: [String: Any] = [
            "op": "reload",
            "path": options.configPath,
            "socksPort": options.socksPort,
            "mtu": options.mtu,
            "includeLocal": options.includeLocal,
            "dns": options.dns,
            "launchCore": options.launchCore,
            "engine": options.engine,
            "useXrayTun": options.useXrayTun
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            connect(options, completion: completion)
            return
        }
        do {
            try session.sendProviderMessage(data) { [weak self] response in
                let ok = Self.messageOK(response)
                DispatchQueue.main.async {
                    self?.lastReloaded = ok
                    self?.usingSystem = ok || (self?.usingSystem ?? false)
                    completion(ok)
                }
            }
        } catch {
            DevLog.error("tunnel", "reload: \(error.localizedDescription)")
            connect(options, completion: completion)
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
        usingSystem = false
        lastReloaded = false
    }

    func resetConfiguration(completion: @escaping (Bool) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            let group = DispatchGroup()
            for item in managers ?? [] {
                group.enter()
                item.removeFromPreferences { _ in group.leave() }
            }
            group.notify(queue: .main) { [weak self] in
                self?.manager = nil
                self?.usingSystem = false
                completion(true)
            }
        }
    }

    func armOnDemand(enabled: Bool, rules: String) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            let manager = managers?.first ?? NETunnelProviderManager()
            if manager.protocolConfiguration == nil {
                let proto = NETunnelProviderProtocol()
                proto.providerBundleIdentifier = Self.providerId
                proto.serverAddress = "V2Open"
                manager.protocolConfiguration = proto
                manager.localizedDescription = "V2Open"
            }
            manager.onDemandRules = Self.demandRules(rules)
            manager.isOnDemandEnabled = enabled && !(manager.onDemandRules ?? []).isEmpty
            manager.isEnabled = true
            manager.saveToPreferences { _ in
                manager.loadFromPreferences { _ in }
            }
        }
    }

    private func apply(_ options: TunnelStartOptions, to manager: NETunnelProviderManager) {
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.providerId
        proto.serverAddress = "V2Open"
        proto.providerConfiguration = [
            "configPath": options.configPath,
            "socksPort": options.socksPort,
            "mtu": options.mtu,
            "includeLocal": options.includeLocal,
            "dns": options.dns,
            "launchCore": options.launchCore,
            "engine": options.engine,
            "useXrayTun": options.useXrayTun
        ]
        proto.includeAllNetworks = options.killSwitch || options.combiner || options.includeAll
        proto.excludeLocalNetworks = !options.includeLocal
        proto.enforceRoutes = options.killSwitch || options.enforceRoutes
        applyIncludeAPNs(proto, enabled: options.includeApns)
        applyIncludeCellular(proto, enabled: options.includeCellular)
        manager.protocolConfiguration = proto
        manager.localizedDescription = "V2Open"
        manager.isEnabled = true
        manager.onDemandRules = Self.demandRules(options.rules)
        manager.isOnDemandEnabled = options.onDemand && !(manager.onDemandRules ?? []).isEmpty
    }

    private func applyIncludeAPNs(_ proto: NETunnelProviderProtocol, enabled: Bool) {
        let setter = NSSelectorFromString("setExcludeAPNs:")
        if proto.responds(to: setter) {
            proto.perform(setter, with: NSNumber(value: !enabled))
        }
    }

    private func applyIncludeCellular(_ proto: NETunnelProviderProtocol, enabled: Bool) {
        let setter = NSSelectorFromString("setIncludeCellularServices:")
        if proto.responds(to: setter) {
            proto.perform(setter, with: NSNumber(value: enabled))
        }
    }

    static var providerId: String {
        (Bundle.main.bundleIdentifier ?? "local.v2open.desktop") + ".PacketTunnel"
    }

    private static func messageOK(_ data: Data?) -> Bool {
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return obj["ok"] as? Bool == true
    }

    static func demandRules(_ text: String) -> [NEOnDemandRule] {
        var rules: [NEOnDemandRule] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { continue }
            let interface: NEOnDemandRuleInterfaceType
            switch parts[0].lowercased() {
            case "wifi": interface = .wiFi
            case "ethernet": interface = .ethernet
            case "cellular": continue
            default: interface = .any
            }
            let ssids = parts[1]
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0 != "*" }
            let action = parts[2].lowercased()
            let rule: NEOnDemandRule
            switch action {
            case "disconnect":
                rule = NEOnDemandRuleDisconnect()
            case "ignore":
                rule = NEOnDemandRuleIgnore()
            default:
                rule = NEOnDemandRuleConnect()
            }
            rule.interfaceTypeMatch = interface
            if !ssids.isEmpty { rule.ssidMatch = ssids }
            rules.append(rule)
        }
        if rules.isEmpty {
            let connect = NEOnDemandRuleConnect()
            connect.interfaceTypeMatch = .any
            rules.append(connect)
        }
        let evaluate = NEOnDemandRuleEvaluateConnection()
        evaluate.interfaceTypeMatch = .any
        let probe = NEEvaluateConnectionRule(
            matchDomains: ["www.gstatic.com", "connectivitycheck.gstatic.com", "captive.apple.com"],
            andAction: .connectIfNeeded
        )
        probe.useDNSServers = ["1.1.1.1"]
        evaluate.connectionRules = [probe]
        rules.append(evaluate)
        return rules
    }
}
