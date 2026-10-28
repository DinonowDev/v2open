import Foundation
import NetworkExtension

@_silgen_name("NSExtensionMain")
func nsExtensionMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

@main
enum PacketTunnelMain {
    static func main() {
        _ = nsExtensionMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

@objc(PacketTunnelProvider)
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var core: Process?
    private var bridge: PacketBridge?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let path = config["configPath"] as? String ?? ""
        let socks = (config["socksPort"] as? Int) ?? 10808
        let mtu = (config["mtu"] as? Int) ?? 1500
        let includeLocal = (config["includeLocal"] as? Bool) ?? false
        let dns = config["dns"] as? String ?? "1.1.1.1"
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            completionHandler(NSError(domain: "V2Open", code: 1, userInfo: [NSLocalizedDescriptionKey: "tunnel config is missing"]))
            return
        }
        let launch = (config["launchCore"] as? Bool) ?? true
        if launch {
            do {
                try launchCore(configPath: path)
            } catch {
                completionHandler(error)
                return
            }
        }
        let settings = Self.networkSettings(mtu: mtu, includeLocal: includeLocal, dns: dns)
        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                self?.stopCore()
                completionHandler(error)
                return
            }
            let bridge = PacketBridge(socksPort: UInt16(socks))
            bridge.start(flow: self?.packetFlow)
            self?.bridge = bridge
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        bridge?.stop()
        bridge = nil
        stopCore()
        completionHandler()
    }

    private func launchCore(configPath: String) throws {
        let contents = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let binary = contents.appendingPathComponent("MacOS/sing-box")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw NSError(domain: "V2Open", code: 2, userInfo: [NSLocalizedDescriptionKey: "sing-box is missing from the app"])
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["run", "-c", configPath]
        let logURL = URL(fileURLWithPath: configPath).deletingLastPathComponent().appendingPathComponent("tunnel.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        core = process
        Thread.sleep(forTimeInterval: 0.35)
        if !process.isRunning {
            throw NSError(domain: "V2Open", code: 3, userInfo: [NSLocalizedDescriptionKey: "sing-box exited inside the packet tunnel"])
        }
    }

    private func stopCore() {
        core?.terminate()
        core = nil
    }

    private static func networkSettings(mtu: Int, includeLocal: Bool, dns: String) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "172.19.0.2")
        let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        if !includeLocal {
            ipv4.excludedRoutes = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16"].map { cidr in
                let parts = cidr.split(separator: "/")
                let route = NEIPv4Route(destinationAddress: String(parts[0]), subnetMask: mask(Int(parts[1]) ?? 8))
                return route
            }
        }
        settings.ipv4Settings = ipv4
        let ipv6 = NEIPv6Settings(addresses: ["fd00:19::1"], networkPrefixLengths: [126])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        if !includeLocal {
            ipv6.excludedRoutes = [NEIPv6Route(destinationAddress: "fc00::", networkPrefixLength: 7), NEIPv6Route(destinationAddress: "fe80::", networkPrefixLength: 10)]
        }
        settings.ipv6Settings = ipv6
        settings.mtu = NSNumber(value: mtu)
        let host = dns.replacingOccurrences(of: "https://", with: "").split(separator: "/").first.map(String.init) ?? "1.1.1.1"
        let server = host.split(separator: ":").first.map(String.init) ?? host
        settings.dnsSettings = NEDNSSettings(servers: [server.contains(".") || server.contains(":") ? server : "1.1.1.1"])
        return settings
    }

    private static func mask(_ prefix: Int) -> String {
        var value: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << (32 - prefix)
        var parts: [String] = []
        for _ in 0..<4 {
            parts.append(String((value >> 24) & 255))
            value <<= 8
        }
        return parts.joined(separator: ".")
    }
}
