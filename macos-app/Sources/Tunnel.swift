import Foundation
import NetworkExtension

final class TunnelManager: NSObject {
    static let shared = TunnelManager()
    private var manager: NETunnelProviderManager?
    private(set) var usingSystem = false

    func connect(configPath: String, socksPort: Int, mtu: Int, includeLocal: Bool, killSwitch: Bool, combiner: Bool, launchCore: Bool, dns: String, onDemand: Bool, rules: String, completion: @escaping (Bool) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error {
                DevLog.error("tunnel", "preferences: \(error.localizedDescription)")
                completion(false)
                return
            }
            guard let self else { completion(false); return }
            let manager = managers?.first ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "local.v2open.desktop.PacketTunnel"
            proto.serverAddress = "V2Open"
            proto.providerConfiguration = [
                "configPath": configPath,
                "socksPort": socksPort,
                "mtu": mtu,
                "includeLocal": includeLocal,
                "dns": dns,
                "launchCore": launchCore
            ]
            proto.includeAllNetworks = killSwitch || combiner
            proto.excludeLocalNetworks = !includeLocal
            proto.enforceRoutes = killSwitch
            manager.protocolConfiguration = proto
            manager.localizedDescription = "V2Open"
            manager.isEnabled = true
            manager.onDemandRules = Self.demandRules(rules)
            manager.isOnDemandEnabled = onDemand && !(manager.onDemandRules ?? []).isEmpty
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

    func disconnect() {
        manager?.connection.stopVPNTunnel()
        usingSystem = false
    }

    private static func demandRules(_ text: String) -> [NEOnDemandRule] {
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
            if parts[2].lowercased() == "disconnect" {
                let rule = NEOnDemandRuleDisconnect()
                rule.interfaceTypeMatch = interface
                if parts[1] != "*" && !parts[1].isEmpty { rule.ssidMatch = [parts[1]] }
                rules.append(rule)
            } else {
                let rule = NEOnDemandRuleConnect()
                rule.interfaceTypeMatch = interface
                if parts[1] != "*" && !parts[1].isEmpty { rule.ssidMatch = [parts[1]] }
                rules.append(rule)
            }
        }
        return rules
    }
}
