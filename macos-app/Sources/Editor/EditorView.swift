import SwiftUI

struct EditorView: View {
    @EnvironmentObject var model: Model

    private var proto: String { model.draft["protocol"] as? String ?? "vless" }
    private var isProxy: Bool { ["vless", "vmess", "trojan", "hysteria", "hysteria2"].contains(proto) }
    private var tlsOnly: Bool { ["tuic", "anytls", "naive"].contains(proto) }
    private static let awgKeys = ["jc", "jmin", "jmax", "s1", "s2", "s3", "s4", "h1", "h2", "h3", "h4", "i1", "i2", "i3", "i4", "i5"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackTitle(title: model.t("manual"))
            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        EditorSection(title: model.t("protocol")) {
                            ProtocolChipPicker(value: proto) { model.draft["protocol"] = $0 }
                        }
                        EditorSection(title: model.t("server")) {
                            serverFields
                        }
                        if hasCredentials {
                            EditorSection(title: model.t("identity")) {
                                credentialFields
                            }
                        }
                        if isProxy {
                            EditorSection(title: model.t("transport")) {
                                transportFields
                            }
                            EditorSection(title: model.t("security")) {
                                securityFields
                            }
                        }
                        if tlsOnly {
                            EditorSection(title: model.t("security")) {
                                tlsOnlyFields
                            }
                        }
                        if proto == "shadowsocks" {
                            EditorSection(title: model.t("ssPlugin")) {
                                ssPluginFields
                            }
                        }
                        if proto == "wireguard" || proto == "warp" {
                            EditorSection(title: model.t("amneziaWg")) {
                                amneziaFields
                            }
                        }
                    }
                    .padding(.horizontal, PageLayout.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 92 + PageLayout.tabBarClearance)
                }
                .scrollIndicators(.hidden)

                VStack(spacing: 0) {
                    LinearGradient(colors: [C.bgGradientBottom.opacity(0), C.bgGradientBottom], startPoint: .top, endPoint: .bottom)
                        .frame(height: 18)
                    SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") {
                        if let err = model.invoke("save_profile", ["profile": model.draft]) {
                            model.showToast(err, tone: .error)
                            return
                        }
                        model.pop()
                    }
                    .padding(.horizontal, PageLayout.horizontal)
                    .padding(.bottom, 16 + PageLayout.tabBarClearance)
                    .background(C.bgGradientBottom)
                }
            }
        }
    }

    @ViewBuilder private var serverFields: some View {
        edit("remark", model.fa ? "نام" : "Name", latin: false, icon: "textformat")
        if proto == "dnstt" || proto == "masterdns" {
            edit("domain", "Domain", latin: true, icon: "globe")
            edit("dns_server", proto == "masterdns" ? "Resolver" : "DNS", latin: true, icon: "server.rack")
        } else {
            edit("address", model.fa ? "آدرس" : "Address", latin: true, icon: "network")
            edit("port", model.fa ? "پورت" : "Port", latin: true, icon: "number")
        }
    }

    @ViewBuilder private var credentialFields: some View {
        if proto == "vless" || proto == "vmess" {
            edit("uuid", "UUID", latin: true, icon: "key.fill")
            edit("flow", "Flow", latin: true, icon: "wind")
        }
        if proto == "tuic" {
            edit("uuid", "UUID", latin: true, icon: "key.fill")
        }
        if proto == "naive" {
            edit("username", "User", latin: true, icon: "person.fill")
        }
        if ["trojan", "shadowsocks", "hysteria2", "hysteria", "ssh", "socks", "http", "ping", "tuic", "anytls", "naive"].contains(proto) {
            edit("password", "Password", latin: true, secure: true, icon: "lock.fill")
        }
        if proto == "tuic" {
            SoftSelect(
                title: model.t("congestion"),
                value: model.draft["congestion_control"] as? String ?? "bbr",
                options: ["bbr", "cubic", "new_reno"].map { ($0, $0) },
                wide: true,
                icon: "speedometer"
            ) { model.draft["congestion_control"] = $0 }
            SoftSelect(
                title: model.t("udpRelay"),
                value: model.draft["udp_relay_mode"] as? String ?? "native",
                options: ["native", "quic"].map { ($0, $0) },
                wide: true,
                icon: "arrow.left.arrow.right"
            ) { model.draft["udp_relay_mode"] = $0 }
            edit("heartbeat", "Heartbeat (ms)", latin: true, icon: "waveform.path.ecg")
            toggle("zero_rtt", model.t("zeroRtt"))
        }
        if proto == "naive" {
            toggle("naive_quic", model.t("naiveQuic"))
            edit("insecure_concurrency", model.t("concurrency"), latin: true, icon: "square.stack.3d.up")
            edit("extra_headers", model.t("extraHeaders"), latin: true, icon: "list.bullet.rectangle")
        }
        if proto == "shadowsocks" {
            edit("method", "Method", latin: true, icon: "lock.rotation")
        }
        if proto == "shadowsocksr" {
            edit("method", "Method", latin: true, icon: "lock.rotation")
            edit("password", "Password", latin: true, secure: true, icon: "lock.fill")
            edit("ssr_protocol", "Protocol", latin: true, icon: "point.3.connected.trianglepath.dotted")
            edit("obfs", "Obfs", latin: true, icon: "eye.slash")
        }
        if proto == "dnstt" {
            edit("pubkey", "Public key", latin: true, icon: "key.fill")
        }
        if proto == "masterdns" {
            edit("key", "Key", latin: true, icon: "key.fill")
            edit("encryption_method", "Encryption 0-5", latin: true, icon: "lock.rotation")
            edit("arq_window_size", "ARQ window", latin: true, icon: "square.grid.3x3")
            edit("arq_initial_rto_seconds", "ARQ initial RTO", latin: true, icon: "timer")
            edit("arq_max_rto_seconds", "ARQ max RTO", latin: true, icon: "timer")
            edit("arq_max_data_retries", "ARQ data retries", latin: true, icon: "arrow.clockwise")
            edit("arq_inactivity_timeout_seconds", "ARQ inactivity", latin: true, icon: "clock")
        }
        if proto == "hysteria" || proto == "hysteria2" {
            edit("up_mbps", "Up Mbps", latin: true, icon: "arrow.up")
            edit("down_mbps", "Down Mbps", latin: true, icon: "arrow.down")
            edit("obfs", "Obfs", latin: true, icon: "eye.slash")
            edit("obfs_password", "Obfs password", latin: true, secure: true, icon: "lock")
        }
        if proto == "hysteria2" {
            edit("hop_port", model.t("hopPorts"), latin: true, icon: "arrow.triangle.swap")
        }
        if proto == "chain" {
            chainHopsEditor
        }
        if proto == "wireguard" {
            edit("private_key", "Private key", latin: true, secure: true, icon: "key.fill")
            edit("peer_public_key", "Public key", latin: true, icon: "key")
            edit("preshared_key", "Pre-shared key", latin: true, secure: true, icon: "key.horizontal")
            edit("local_address", "Local address", latin: true, icon: "internaldrive")
            edit("allowed_ips", "Allowed IPs", latin: true, icon: "line.3.horizontal.decrease")
            edit("reserved", "Reserved", latin: true, icon: "number")
            edit("mtu", "MTU", latin: true, icon: "ruler")
            edit("keepalive", "Keepalive (s)", latin: true, icon: "heart")
        }
        if proto == "warp" {
            warpFields
        }
    }

    @ViewBuilder private var warpFields: some View {
        let registered = !((model.draft["private_key"] as? String ?? "").isEmpty)
        let kind = model.draft["account_type"] as? String ?? ""
        Mix(text: registered ? "\(model.t("warpRegistered"))\(kind.isEmpty ? "" : " · \(kind)")" : model.t("warpNotRegistered"), size: 12, color: registered ? C.cyan : C.muted)
        edit("license", model.t("warpLicense"), latin: true, icon: "key.fill")
        toggle("warp_wow", model.t("warpWow"), hint: model.t("warpWowInfo"))
        edit("mtu", "MTU", latin: true, icon: "ruler")
        if let id = model.draft["id"] as? String, !id.isEmpty {
            HStack(spacing: 10) {
                SheetActionButton(title: model.t("warpApplyLicense"), icon: "checkmark.seal") {
                    let license = (model.draft["license"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    warpAction("warp_license", ["id": id, "license": license])
                }
                SheetActionButton(title: model.t("warpReregister"), icon: "arrow.clockwise") {
                    warpAction("warp_register", ["id": id])
                }
            }
        }
    }

    private func warpAction(_ method: String, _ args: [String: Any]) {
        let id = args["id"] as? String ?? ""
        let response = model.call(method, args)
        guard response["ok"] as? Bool != false else {
            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
            return
        }
        model.mergeState(from: response)
        for group in model.groups {
            if let profile = (group["profiles"] as? [[String: Any]] ?? []).first(where: { $0["id"] as? String == id }) {
                model.draft = (profile["data"] as? [String: Any]) ?? profile
                model.draft["id"] = id
            }
        }
        model.showToast(model.t("saved"), tone: .success)
    }

    @ViewBuilder private var tlsOnlyFields: some View {
        edit("sni", "SNI", latin: true, icon: "text.alignleft")
        edit("alpn", "ALPN", latin: true, icon: "textformat")
        if proto != "naive" {
            edit("fp", "Fingerprint", latin: true, icon: "touchid")
        }
        if proto == "tuic" {
            toggle("disable_sni", "Disable SNI")
        }
        toggle("insecure", model.t("insecure"))
        echFields
    }

    @ViewBuilder private var echFields: some View {
        toggle("ech", model.t("ech"), hint: model.t("echInfo"))
        if truthy("ech") {
            edit("ech_config", model.t("echConfig"), latin: true, icon: "lock.doc")
            edit("ech_query_server_name", model.t("echQueryName"), latin: true, icon: "magnifyingglass")
        }
    }

    private var ssPluginKind: String {
        if !((model.draft["shadowtls_version"] as? String ?? "").isEmpty) { return "shadow-tls" }
        let plugin = model.draft["plugin"] as? String ?? ""
        return plugin.isEmpty ? "none" : plugin
    }

    @ViewBuilder private var ssPluginFields: some View {
        SoftSelect(
            title: model.t("ssPlugin"),
            value: ssPluginKind,
            options: [("none", "—"), ("shadow-tls", "ShadowTLS"), ("obfs-local", "simple-obfs"), ("v2ray-plugin", "v2ray-plugin")],
            wide: true,
            icon: "puzzlepiece.extension"
        ) { kind in
            switch kind {
            case "shadow-tls":
                model.draft["plugin"] = ""
                model.draft["plugin_opts"] = ""
                if (model.draft["shadowtls_version"] as? String ?? "").isEmpty { model.draft["shadowtls_version"] = "3" }
            case "none":
                model.draft["plugin"] = ""
                model.draft["plugin_opts"] = ""
                model.draft["shadowtls_version"] = ""
            default:
                model.draft["plugin"] = kind
                model.draft["shadowtls_version"] = ""
            }
        }
        if ssPluginKind == "shadow-tls" {
            SoftSelect(
                title: "ShadowTLS",
                value: model.draft["shadowtls_version"] as? String ?? "3",
                options: [("3", "v3"), ("2", "v2"), ("1", "v1")],
                wide: true,
                icon: "number"
            ) { model.draft["shadowtls_version"] = $0 }
            edit("shadowtls_password", "ShadowTLS password", latin: true, secure: true, icon: "lock.fill")
            edit("shadowtls_sni", "ShadowTLS SNI", latin: true, icon: "text.alignleft")
            edit("fp", "Fingerprint", latin: true, icon: "touchid")
        } else if ssPluginKind != "none" {
            edit("plugin_opts", model.t("pluginOpts"), latin: true, icon: "slider.horizontal.3")
        }
    }

    @ViewBuilder private var amneziaFields: some View {
        Mix(text: model.t("amneziaInfo"), size: 12, color: C.muted)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Self.awgKeys.filter { !$0.hasPrefix("i") }, id: \.self) { key in
                edit("awg_\(key)", key.capitalized, latin: true)
            }
        }
        if proto == "wireguard" {
            ForEach(Self.awgKeys.filter { $0.hasPrefix("i") }, id: \.self) { key in
                edit("awg_\(key)", key.uppercased(), latin: true, icon: "waveform")
            }
        }
    }

    @ViewBuilder private var transportFields: some View {
        SoftSelect(
            title: model.t("network"),
            value: model.draft["network"] as? String ?? "tcp",
            options: ["tcp", "ws", "grpc", "h2", "httpupgrade", "xhttp", "quic"].map { ($0, $0) },
            wide: true,
            icon: "antenna.radiowaves.left.and.right"
        ) { model.draft["network"] = $0 }
        SoftSelect(
            title: "TLS",
            value: model.draft["tls"] as? String ?? "none",
            options: ["none", "tls", "reality"].map { ($0, $0) },
            wide: true,
            icon: "checkmark.shield"
        ) { model.draft["tls"] = $0 }
        if (model.draft["network"] as? String) == "xhttp" {
            SoftSelect(
                title: "Mode",
                value: model.draft["mode"] as? String ?? "auto",
                options: ["auto", "packet-up", "stream-up", "stream-one"].map { ($0, $0) },
                wide: true
            ) { model.draft["mode"] = $0 }
            edit("x_padding", "XHTTP padding", latin: true, icon: "arrow.left.and.right")
            edit("xhttp_extra", "XHTTP extra JSON", latin: true, icon: "curlybraces")
        }
        edit("host", "Host", latin: true, icon: "globe")
        edit("path", "Path", latin: true, icon: "slash.forward")
    }

    @ViewBuilder private var securityFields: some View {
        if (model.draft["tls"] as? String) == "tls" || proto == "hysteria" || proto == "hysteria2" {
            echFields
        }
        edit("alpn", "ALPN", latin: true, icon: "textformat")
        edit("sni", "SNI", latin: true, icon: "text.alignleft")
        edit("fp", "Fingerprint", latin: true, icon: "touchid")
        edit("pbk", "Reality public key", latin: true, icon: "key")
        edit("sid", "Short ID", latin: true, icon: "number")
        if (model.draft["tls"] as? String) == "reality" {
            edit("spx", "SpiderX", latin: true, icon: "ant")
            edit("pqv", "ML-DSA verify", latin: true, icon: "checkmark.seal")
        }
    }

    @ViewBuilder private var chainHopsEditor: some View {
        let hops = hopsList()
        ForEach(hops.indices, id: \.self) { index in
            hopCard(index)
        }
        SheetActionButton(title: model.t("addHop"), icon: "plus") {
            var next = hopsList()
            next.append(["protocol": "vless", "address": "", "port": 443, "uuid": "", "password": "", "network": "tcp", "tls": "none"])
            model.draft["chain"] = next
        }
    }

    @ViewBuilder private func hopCard(_ index: Int) -> some View {
        let proto = hopValue(index, "protocol", "vless")
        let network = hopValue(index, "network", "tcp")
        let tls = hopValue(index, "tls", "none")
        let proxy = ["vless", "vmess", "trojan", "hysteria", "hysteria2", "tuic", "anytls"].contains(proto)
        let tlsOnly = ["tuic", "anytls", "naive"].contains(proto)
        let hopProtocols: [(String, String)] = [
            ("vless", "VLESS"), ("vmess", "VMess"), ("trojan", "Trojan"), ("shadowsocks", "SS"),
            ("tuic", "TUIC"), ("anytls", "AnyTLS"), ("naive", "Naive"),
            ("hysteria2", "Hy2"), ("hysteria", "Hy1"),
            ("wireguard", "WG"), ("warp", "WARP"), ("socks", "SOCKS"), ("http", "HTTP"), ("ssh", "SSH")
        ]
        VStack(alignment: .leading, spacing: 10) {
            Mix(text: "\(model.t("hop")) \(index + 1)", size: 13, weight: .bold)
            SoftSelect(
                title: model.t("protocol"),
                value: proto,
                options: hopProtocols,
                wide: true
            ) { setHop(index, "protocol", $0) }

            if proto != "warp" {
                Mix(text: model.t("server"), size: 11, color: C.muted)
                hopField(index, "address", model.fa ? "آدرس" : "Address")
                hopField(index, "port", model.fa ? "پورت" : "Port")
            }

            Mix(text: model.t("identity"), size: 11, color: C.muted)
            if proto == "vless" || proto == "vmess" || proto == "tuic" {
                hopField(index, "uuid", "UUID")
                if proto == "vless" { hopField(index, "flow", "Flow") }
            }
            if proto == "tuic" {
                hopField(index, "congestion_control", model.t("congestion"))
                hopField(index, "udp_relay_mode", model.t("udpRelay"))
                hopField(index, "heartbeat", "Heartbeat (ms)")
                toggleHop(index, "zero_rtt", model.t("zeroRtt"))
                toggleHop(index, "disable_sni", "Disable SNI")
            }
            if proto == "naive" {
                hopField(index, "username", "User")
                toggleHop(index, "naive_quic", model.t("naiveQuic"))
            }
            if ["trojan", "shadowsocks", "hysteria2", "hysteria", "socks", "http", "ssh", "tuic", "anytls", "naive"].contains(proto) {
                hopField(index, "password", "Password")
            }
            if proto == "shadowsocks" {
                hopField(index, "method", "Method")
                hopField(index, "plugin", model.t("ssPlugin"))
                hopField(index, "shadowtls_version", "ShadowTLS v")
                hopField(index, "shadowtls_password", "ShadowTLS password")
                hopField(index, "shadowtls_sni", "ShadowTLS SNI")
            }
            if proto == "ssh" {
                hopField(index, "username", "User")
            }
            if proto == "hysteria" || proto == "hysteria2" {
                hopField(index, "up_mbps", "Up Mbps")
                hopField(index, "down_mbps", "Down Mbps")
                hopField(index, "obfs", "Obfs")
                hopField(index, "obfs_password", "Obfs password")
            }
            if proto == "hysteria2" {
                hopField(index, "hop_port", model.t("hopPorts"))
            }
            if proto == "wireguard" || proto == "warp" {
                hopField(index, "private_key", "Private key")
                hopField(index, "peer_public_key", "Peer public key")
                hopField(index, "local_address", "Local address")
                hopField(index, "reserved", "Reserved")
                hopField(index, "mtu", "MTU")
                ForEach(Self.awgKeys.filter { !$0.hasPrefix("i") || proto == "wireguard" }, id: \.self) { key in
                    hopField(index, "awg_\(key)", key.hasPrefix("i") ? key.uppercased() : key.capitalized)
                }
            }
            if proto == "warp" {
                Mix(text: model.t("warpChainHopHint"), size: 11, color: C.muted)
                    .fixedSize(horizontal: false, vertical: true)
                hopField(index, "license", model.t("warpLicense"))
            }

            if proxy && !tlsOnly {
                Mix(text: model.t("transport"), size: 11, color: C.muted)
                SoftSelect(
                    title: model.t("network"),
                    value: network,
                    options: ["tcp", "ws", "grpc", "h2", "httpupgrade", "xhttp", "quic"].map { ($0, $0) },
                    wide: true
                ) { setHop(index, "network", $0) }
                hopField(index, "host", "Host")
                hopField(index, "path", "Path")
                if network == "grpc" {
                    hopField(index, "service_name", "gRPC service")
                }
                if network == "xhttp" {
                    hopField(index, "mode", "XHTTP mode")
                    hopField(index, "x_padding", "XHTTP padding")
                    hopField(index, "xhttp_extra", "XHTTP extra JSON")
                }
            }

            if proxy || tlsOnly {
                Mix(text: model.t("security"), size: 11, color: C.muted)
                if !tlsOnly {
                    SoftSelect(
                        title: "TLS",
                        value: tls,
                        options: ["none", "tls", "reality"].map { ($0, $0) },
                        wide: true
                    ) { setHop(index, "tls", $0) }
                }
                hopField(index, "sni", "SNI")
                hopField(index, "alpn", "ALPN")
                if !tlsOnly { hopField(index, "fp", "Fingerprint") }
                if tls == "reality" && !tlsOnly {
                    hopField(index, "pbk", "Reality public key")
                    hopField(index, "sid", "Short ID")
                    hopField(index, "spx", "SpiderX")
                    hopField(index, "pqv", "ML-DSA verify")
                }
                hopField(index, "ech_config", model.t("echConfig"))
                hopField(index, "ech_query_server_name", model.t("echQueryName"))
            }

            SheetActionButton(title: model.t("deleteRule"), danger: true, icon: "trash") {
                var next = hopsList()
                if next.indices.contains(index) {
                    next.remove(at: index)
                    model.draft["chain"] = next
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func hopsList() -> [[String: Any]] {
        if let arr = model.draft["chain"] as? [[String: Any]] { return arr }
        if let arr = model.draft["chain"] as? [Any] {
            return arr.compactMap { $0 as? [String: Any] }
        }
        if let text = model.draft["chain"] as? String, let data = text.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr
        }
        return []
    }

    func hopValue(_ index: Int, _ key: String, _ fallback: String) -> String {
        let hops = hopsList()
        guard hops.indices.contains(index) else { return fallback }
        let value = "\(hops[index][key] ?? "")"
        return value.isEmpty ? fallback : value
    }

    func setHop(_ index: Int, _ key: String, _ value: String) {
        var hops = hopsList()
        guard hops.indices.contains(index) else { return }
        hops[index][key] = value
        model.draft["chain"] = hops
    }

    func hopField(_ index: Int, _ key: String, _ title: String) -> some View {
        V2Field(
            label: title,
            placeholder: title,
            text: Binding(
                get: {
                    let hops = hopsList()
                    guard hops.indices.contains(index) else { return "" }
                    return "\(hops[index][key] ?? "")"
                },
                set: { value in
                    var hops = hopsList()
                    guard hops.indices.contains(index) else { return }
                    hops[index][key] = key == "port" ? (Int(value) ?? 0) : value
                    model.draft["chain"] = hops
                }
            ),
            latin: true
        )
    }

    private var hasCredentials: Bool {
        ["vless", "vmess", "trojan", "shadowsocks", "shadowsocksr", "hysteria2", "hysteria", "tuic", "anytls", "naive", "ssh", "socks", "http", "ping", "dnstt", "masterdns", "wireguard", "warp", "chain"].contains(proto)
    }

    private func truthy(_ key: String) -> Bool {
        if let b = model.draft[key] as? Bool { return b }
        if let n = model.draft[key] as? Int { return n != 0 }
        let text = "\(model.draft[key] ?? "")".lowercased()
        return ["1", "true", "yes", "on"].contains(text)
    }

    func hopTruthy(_ index: Int, _ key: String) -> Bool {
        let hops = hopsList()
        guard hops.indices.contains(index) else { return false }
        if let b = hops[index][key] as? Bool { return b }
        if let n = hops[index][key] as? Int { return n != 0 }
        let text = "\(hops[index][key] ?? "")".lowercased()
        return ["1", "true", "yes", "on"].contains(text)
    }

    func toggleHop(_ index: Int, _ key: String, _ title: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Mix(text: title, size: 14, weight: .medium)
            Spacer(minLength: 8)
            SoftSwitch(isOn: Binding(
                get: { hopTruthy(index, key) },
                set: { value in
                    var hops = hopsList()
                    guard hops.indices.contains(index) else { return }
                    hops[index][key] = value
                    model.draft["chain"] = hops
                }
            ))
        }
        .padding(.vertical, 4)
    }

    func toggle(_ key: String, _ title: String, hint: String? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Mix(text: title, size: 14, weight: .medium)
                if let hint, !hint.isEmpty {
                    Mix(text: hint, size: 12, color: C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            SoftSwitch(isOn: Binding(get: { truthy(key) }, set: { model.draft[key] = $0 }))
        }
        .padding(.vertical, 4)
    }

    func edit(_ key: String, _ title: String, latin: Bool, secure: Bool = false, icon: String? = nil) -> some View {
        V2Field(
            label: title,
            placeholder: title,
            text: Binding(
                get: { "\(model.draft[key] ?? "")" },
                set: { model.draft[key] = key == "port" ? (Int($0) ?? 0) : $0 }
            ),
            latin: latin,
            secure: secure,
            icon: icon
        )
    }
}
