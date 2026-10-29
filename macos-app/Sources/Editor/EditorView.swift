import SwiftUI

struct EditorView: View {
    @EnvironmentObject var model: Model

    private var proto: String { model.draft["protocol"] as? String ?? "vless" }
    private var isProxy: Bool { ["vless", "vmess", "trojan", "hysteria", "hysteria2"].contains(proto) }

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
                        _ = model.call("save_profile", ["profile": model.draft])
                        model.refresh()
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
        if ["trojan", "shadowsocks", "hysteria2", "hysteria", "ssh", "socks", "http", "ping"].contains(proto) {
            edit("password", "Password", latin: true, secure: true, icon: "lock.fill")
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
        }
        if proto == "chain" {
            chainHopsEditor
        }
        if proto == "wireguard" {
            edit("private_key", "Private key", latin: true, secure: true, icon: "key.fill")
            edit("peer_public_key", "Public key", latin: true, icon: "key")
            edit("local_address", "Local address", latin: true, icon: "internaldrive")
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
        let proxy = ["vless", "vmess", "trojan", "hysteria", "hysteria2"].contains(proto)
        VStack(alignment: .leading, spacing: 10) {
            Mix(text: "\(model.t("hop")) \(index + 1)", size: 13, weight: .bold)
            SoftSelect(
                title: model.t("protocol"),
                value: proto,
                options: ["vless", "vmess", "trojan", "shadowsocks", "hysteria2", "hysteria", "socks", "http", "ssh"].map { ($0, $0) },
                wide: true
            ) { setHop(index, "protocol", $0) }

            Mix(text: model.t("server"), size: 11, color: C.muted)
            hopField(index, "address", model.fa ? "آدرس" : "Address")
            hopField(index, "port", model.fa ? "پورت" : "Port")

            Mix(text: model.t("identity"), size: 11, color: C.muted)
            if proto == "vless" || proto == "vmess" {
                hopField(index, "uuid", "UUID")
                hopField(index, "flow", "Flow")
            }
            if ["trojan", "shadowsocks", "hysteria2", "hysteria", "socks", "http", "ssh"].contains(proto) {
                hopField(index, "password", "Password")
            }
            if proto == "shadowsocks" {
                hopField(index, "method", "Method")
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

            if proxy {
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

                Mix(text: model.t("security"), size: 11, color: C.muted)
                SoftSelect(
                    title: "TLS",
                    value: tls,
                    options: ["none", "tls", "reality"].map { ($0, $0) },
                    wide: true
                ) { setHop(index, "tls", $0) }
                hopField(index, "sni", "SNI")
                hopField(index, "alpn", "ALPN")
                hopField(index, "fp", "Fingerprint")
                if tls == "reality" {
                    hopField(index, "pbk", "Reality public key")
                    hopField(index, "sid", "Short ID")
                    hopField(index, "spx", "SpiderX")
                    hopField(index, "pqv", "ML-DSA verify")
                }
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
        ["vless", "vmess", "trojan", "shadowsocks", "shadowsocksr", "hysteria2", "hysteria", "ssh", "socks", "http", "ping", "dnstt", "masterdns", "wireguard", "chain"].contains(proto)
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
