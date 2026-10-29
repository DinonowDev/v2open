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
    private var lastMTU = 0
    private var lastDNS = ""
    private var lastIncludeLocal = false
    private var lastPath = ""
    private var lastEngine = "sing-box"
    private var lastSocks = 10808
    private var lastLaunch = true
    private var lastUseXrayTun = false

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        apply(config: config)
        guard !lastPath.isEmpty, FileManager.default.fileExists(atPath: lastPath) else {
            completionHandler(NSError(domain: "V2Open", code: 1, userInfo: [NSLocalizedDescriptionKey: "tunnel config is missing"]))
            return
        }
        if lastLaunch {
            do {
                try launchCore(configPath: lastPath, engine: lastEngine)
            } catch {
                completionHandler(error)
                return
            }
        }
        let settings = Self.networkSettings(mtu: lastMTU, includeLocal: lastIncludeLocal, dns: lastDNS)
        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                self?.stopCore()
                completionHandler(error)
                return
            }
            self?.startPacketPath()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        bridge?.stop()
        bridge = nil
        stopCore()
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let obj = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any] else {
            completionHandler?(Self.reply(ok: false))
            return
        }
        let op = obj["op"] as? String ?? ""
        if op == "status" {
            completionHandler?(Self.reply(ok: true, extra: ["alive": core?.isRunning == true, "path": lastPath]))
            return
        }
        guard op == "reload" else {
            completionHandler?(Self.reply(ok: false))
            return
        }
        let path = obj["path"] as? String ?? lastPath
        let engine = obj["engine"] as? String ?? lastEngine
        let socks = obj["socksPort"] as? Int ?? lastSocks
        let mtu = obj["mtu"] as? Int ?? lastMTU
        let includeLocal = obj["includeLocal"] as? Bool ?? lastIncludeLocal
        let dns = obj["dns"] as? String ?? lastDNS
        let launch = obj["launchCore"] as? Bool ?? lastLaunch
        lastUseXrayTun = obj["useXrayTun"] as? Bool ?? lastUseXrayTun
        lastPath = path
        lastEngine = engine
        lastSocks = socks
        lastLaunch = launch
        if launch {
            stopCore()
            do {
                try launchCore(configPath: path, engine: engine)
            } catch {
                completionHandler?(Self.reply(ok: false, extra: ["error": error.localizedDescription]))
                return
            }
        }
        let settingsChanged = mtu != lastMTU || dns != lastDNS || includeLocal != lastIncludeLocal
        lastMTU = mtu
        lastDNS = dns
        lastIncludeLocal = includeLocal
        if settingsChanged {
            let settings = Self.networkSettings(mtu: mtu, includeLocal: includeLocal, dns: dns)
            setTunnelNetworkSettings(settings) { [weak self] error in
                if error == nil {
                    self?.startPacketPath()
                }
                completionHandler?(Self.reply(ok: error == nil, extra: ["reloaded": true, "settings": error == nil]))
            }
        } else {
            startPacketPath()
            completionHandler?(Self.reply(ok: true, extra: ["reloaded": true, "settings": false]))
        }
    }

    private func apply(config: [String: Any]) {
        lastPath = config["configPath"] as? String ?? ""
        lastSocks = (config["socksPort"] as? Int) ?? 10808
        lastMTU = (config["mtu"] as? Int) ?? 1500
        lastIncludeLocal = (config["includeLocal"] as? Bool) ?? false
        lastDNS = config["dns"] as? String ?? "1.1.1.1"
        lastLaunch = (config["launchCore"] as? Bool) ?? true
        lastEngine = config["engine"] as? String ?? "sing-box"
        lastUseXrayTun = (config["useXrayTun"] as? Bool) ?? (lastEngine == "xray")
    }

    /// V2Box PacketTunnel always runs a userspace (gVisor-like) stack that
    /// feeds NE packets into Xray/sing-box over SOCKS — 10809 when Xray TUN.
    private func startPacketPath() {
        bridge?.stop()
        bridge = nil
        let port = (lastEngine == "xray" && lastUseXrayTun) ? 10809 : lastSocks
        let next = PacketBridge(socksPort: UInt16(port))
        next.start(flow: packetFlow)
        bridge = next
    }

    private func launchCore(configPath: String, engine: String) throws {
        let contents = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let binaryName = engine == "xray" ? "xray" : "sing-box"
        let binary = contents.appendingPathComponent("MacOS/\(binaryName)")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw NSError(domain: "V2Open", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(binaryName) is missing from the app"])
        }
        let workDir = URL(fileURLWithPath: configPath).deletingLastPathComponent()
        seedGeo(into: workDir, from: contents.appendingPathComponent("Resources"))
        let process = Process()
        process.executableURL = binary
        process.currentDirectoryURL = workDir
        process.arguments = ["run", "-c", configPath]
        var env = ProcessInfo.processInfo.environment
        env["XRAY_LOCATION_ASSET"] = workDir.path
        process.environment = env
        let logURL = workDir.appendingPathComponent("tunnel.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        core = process
        Thread.sleep(forTimeInterval: 0.35)
        if !process.isRunning {
            throw NSError(domain: "V2Open", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(binaryName) exited inside the packet tunnel"])
        }
    }

    private func seedGeo(into dir: URL, from resources: URL) {
        let fm = FileManager.default
        for name in ["geoip.dat", "geosite.dat"] {
            let dest = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: dest.path) { continue }
            let src = resources.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: dest)
            }
        }
    }

    private func stopCore() {
        core?.terminate()
        core = nil
    }

    private static func reply(ok: Bool, extra: [String: Any] = [:]) -> Data {
        var payload = extra
        payload["ok"] = ok
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
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
