use serde_json::{json, Value};
use std::io::{Read, Write};
use std::net::{IpAddr, SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

fn s(v: &Value, key: &str) -> String {
    v.get(key).and_then(|x| x.as_str()).unwrap_or("").to_string()
}

pub fn document(settings: &Value, profile: &Value, routes: &[Value]) -> Value {
    let mut doc = core(settings, routes, proxy_outbounds(settings, profile, None));
    let listen = if settings["lan_sharing"].as_bool().unwrap_or(false) { "0.0.0.0" } else { "127.0.0.1" };
    let mut inbounds = vec![
        json!({"tag":"socks","port": settings["socks_port"].as_u64().unwrap_or(10808), "listen": listen, "protocol":"socks", "settings":{"udp": true, "auth":"noauth"}, "sniffing": sniffing(settings)}),
        json!({"tag":"http","port": settings["http_port"].as_u64().unwrap_or(10807), "listen": listen, "protocol":"http", "sniffing": sniffing(settings)})
    ];
    if settings["use_xray_tun"].as_bool().unwrap_or(false) {
        inbounds.insert(0, json!({
            "tag": "socks-tun",
            "port": 10809,
            "listen": "127.0.0.1",
            "protocol": "socks",
            "settings": {"udp": true, "auth": "noauth"},
            "sniffing": sniffing(settings)
        }));
        inbounds.insert(0, json!({
            "tag": "tun-in",
            "protocol": "tun",
            "settings": {
                "name": "xray0",
                "MTU": settings["mtu"].as_u64().unwrap_or(1500)
            },
            "sniffing": sniffing(settings)
        }));
    }
    doc["inbounds"] = json!(inbounds);
    doc
}

fn core(settings: &Value, routes: &[Value], proxy: Vec<Value>) -> Value {
    let direct = json!({"tag":"direct","protocol":"freedom"});
    let block = json!({"tag":"block","protocol":"blackhole"});
    let mut outbounds = Vec::new();
    let mut rest = proxy.into_iter();
    let main = rest.next().unwrap_or_else(|| json!({"tag":"proxy","protocol":"freedom"}));
    if settings["final"].as_str() == Some("direct") {
        outbounds.extend([direct, main, block]);
    } else {
        outbounds.extend([main, direct, block]);
    }
    outbounds.extend(rest);
    let mut routing = json!({
        "domainStrategy": settings["domain_strategy"].as_str().unwrap_or("AsIs"),
        "rules": rules(settings, routes)
    });
    if let Some(balancers) = crate::xray_balancers::export_balancers(settings) {
        routing["balancers"] = balancers;
    }
    let mut doc = json!({
        "log": {"loglevel": settings["loglevel"].as_str().unwrap_or("warning")},
        "dns": dns(settings),
        "inbounds": [],
        "outbounds": outbounds,
        "routing": routing
    });
    if let Some(policy) = policy(settings) {
        doc["policy"] = policy;
    }
    if settings["fake_dns"].as_bool().unwrap_or(false) {
        doc["fakedns"] = json!([{"ipPool":"198.18.0.0/15","poolSize":65535}]);
    }
    if let Some(obs) = observatory(settings) {
        doc["observatory"] = obs;
    }
    if settings["burst_observatory"].as_bool().unwrap_or(false) {
        doc["burstObservatory"] = json!({
            "subjectSelector": ["proxy"],
            "pingConfig": {
                "destination": settings["probe_url"].as_str().unwrap_or("https://www.gstatic.com/generate_204"),
                "interval": settings["probe_interval"].as_str().unwrap_or("1m"),
                "timeout": "5s",
                "sampling": 3
            }
        });
    }
    doc
}

fn observatory(settings: &Value) -> Option<Value> {
    let least = settings["xray_balancers"]
        .as_array()
        .map(|a| a.iter().any(|b| b["strategy"].as_str() == Some("leastPing") && b["enabled"].as_bool().unwrap_or(true)))
        .unwrap_or(false);
    if !settings["observatory_enabled"].as_bool().unwrap_or(false) && !least {
        return None;
    }
    Some(json!({
        "subjectSelector": ["proxy"],
        "probeURL": settings["probe_url"].as_str().filter(|s| !s.is_empty()).unwrap_or_else(|| settings["speed_endpoint"].as_str().unwrap_or("https://www.gstatic.com/generate_204")),
        "probeInterval": settings["probe_interval"].as_str().unwrap_or("1m"),
        "enableConcurrency": true
    }))
}

fn sniffing(settings: &Value) -> Value {
    json!({
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": settings["route_only"].as_bool().unwrap_or(true)
    })
}

fn dns(settings: &Value) -> Value {
    let mut settings = settings.clone();
    crate::dns_items::sync_legacy_dns(&mut settings);
    let remote = settings["remote_dns"].as_str().unwrap_or("https://1.1.1.1/dns-query");
    let domestic = settings["domestic_dns"].as_str().unwrap_or("223.5.5.5");
    let mut servers = Vec::new();
    if settings["fake_dns"].as_bool().unwrap_or(false) {
        servers.push(json!("fakedns"));
    }
    match settings["dns_split"].as_str().unwrap_or("none") {
        "cn" => {
            servers.push(json!({"address": domestic, "domains": ["geosite:cn"], "expectIPs": ["geoip:cn"]}));
            servers.push(json!({"address": remote, "domains": ["geosite:geolocation-!cn"]}));
        }
        "ir" => {
            servers.push(json!({"address": domestic, "domains": ["geosite:category-ir", "regexp:.*\\.ir$"]}));
            servers.push(json!(remote));
        }
        "ru" => {
            servers.push(json!({"address": domestic, "domains": ["geosite:category-ru"]}));
            servers.push(json!(remote));
        }
        _ => servers.push(json!(remote)),
    }
    if !servers.iter().any(|item| item.as_str() == Some(domestic) || item.get("address").and_then(|v| v.as_str()) == Some(domestic)) {
        servers.push(json!(domestic));
    }
    let mut dns = json!({
        "servers": servers,
        "queryStrategy": if settings["prefer_ipv6"].as_bool().unwrap_or(false) { "UseIPv6" } else { "UseIPv4" },
        "disableCache": settings["dns_cache"].as_bool() == Some(false),
        "disableFallback": settings["dns_disable_fallback"].as_bool().unwrap_or(false),
        "disableFallbackIfMatch": settings["dns_disable_fallback_if_match"].as_bool().unwrap_or(false)
    });
    if let Some(hosts) = settings["hosts"].as_object() {
        if !hosts.is_empty() {
            dns["hosts"] = json!(hosts);
        }
    }
    dns
}

fn policy(settings: &Value) -> Option<Value> {
    let level = settings["xray_policy_level"].as_u64().unwrap_or(0);
    let uplink = settings["xray_policy_uplink_only"].as_u64().unwrap_or(0);
    let downlink = settings["xray_policy_downlink_only"].as_u64().unwrap_or(0);
    let stats_up = settings["xray_policy_stats_user_uplink"].as_bool().unwrap_or(false);
    let stats_down = settings["xray_policy_stats_user_downlink"].as_bool().unwrap_or(false);
    if level == 0 && uplink == 0 && downlink == 0 && !stats_up && !stats_down {
        return None;
    }
    let mut level_obj = json!({});
    if uplink > 0 {
        level_obj["uplinkOnly"] = json!(uplink);
    }
    if downlink > 0 {
        level_obj["downlinkOnly"] = json!(downlink);
    }
    if stats_up {
        level_obj["statsUserUplink"] = json!(true);
    }
    if stats_down {
        level_obj["statsUserDownlink"] = json!(true);
    }
    Some(json!({
        "levels": {
            level.to_string(): level_obj
        },
        "system": {
            "statsInboundUplink": stats_up,
            "statsInboundDownlink": stats_down,
            "statsOutboundUplink": stats_up,
            "statsOutboundDownlink": stats_down
        }
    }))
}

fn rules(settings: &Value, routes: &[Value]) -> Vec<Value> {
    let mut rules = Vec::new();
    if settings["block_udp_443"].as_bool().unwrap_or(false) && !routes.iter().any(|rule| {
        rule["enabled"].as_bool() != Some(false) && rule["behavior"].as_str() == Some("block") && rule["network"].as_str() == Some("udp") && rule["port"].as_str() == Some("443")
    }) {
        rules.push(json!({"type":"field","network":"udp","port":"443","outboundTag":"block"}));
    }
    if settings["bypass_lan"].as_bool().unwrap_or(true) && !routes.iter().any(|rule| {
        rule["enabled"].as_bool() != Some(false) && list(&rule["ips"]).iter().any(|item| item == "geoip:private" || item == "private")
    }) {
        rules.push(json!({"type":"field","ip":["geoip:private"],"outboundTag":"direct"}));
    }
    if settings["apple_direct"].as_bool().unwrap_or(false) {
        rules.push(json!({"type":"field","domain":["domain:apple.com","domain:icloud.com","domain:mzstatic.com","domain:cdn-apple.com"],"outboundTag":"direct"}));
    }
    if settings["routing_enabled"].as_bool().unwrap_or(true) {
        for rule in routes {
            push_rule(&mut rules, rule);
        }
    }
    rules.extend(crate::xray_balancers::balancer_rules(settings));
    rules
}

fn push_rule(rules: &mut Vec<Value>, rule: &Value) {
    if rule["enabled"].as_bool() == Some(false) {
        return;
    }
    let balancer = rule["balancer_tag"].as_str().unwrap_or("").trim();
    let tag = match rule["behavior"].as_str().unwrap_or("proxy") {
        "direct" => "direct",
        "block" => "block",
        _ => "proxy",
    };
    let mut extras = json!({});
    if balancer.is_empty() {
        extras["outboundTag"] = json!(tag);
    } else {
        extras["balancerTag"] = json!(balancer);
    }
    let port = rule["port"].as_str().unwrap_or("").trim();
    if !port.is_empty() && port != "0-65535" {
        extras["port"] = json!(port);
    }
    let network = rule["network"].as_str().unwrap_or("");
    if network == "tcp" || network == "udp" {
        extras["network"] = json!(network);
    }
    let protocol = rule["protocol"].as_str().unwrap_or("");
    if !protocol.is_empty() {
        extras["protocol"] = json!([protocol]);
    }
    let inbounds = list(&rule["inbounds"]);
    if !inbounds.is_empty() {
        extras["inboundTag"] = json!(inbounds);
    }
    let sources = list(&rule["sources"]);
    if !sources.is_empty() {
        extras["source"] = json!(sources);
    }
    let source_port = rule["source_port"].as_str().unwrap_or("").trim();
    if !source_port.is_empty() {
        extras["sourcePort"] = json!(source_port);
    }
    let users = list(&rule["users"]);
    if !users.is_empty() {
        extras["user"] = json!(users);
    }
    let domains = list(&rule["domains"]);
    let ips = list(&rule["ips"]);
    if domains.is_empty() && ips.is_empty() {
        if extras.as_object().map(|o| o.keys().any(|k| k != "outboundTag" && k != "balancerTag")).unwrap_or(false) || !balancer.is_empty() {
            let mut item = json!({"type":"field"});
            merge(&mut item, &extras);
            rules.push(item);
        }
        return;
    }
    if !domains.is_empty() {
        let mut item = json!({"type":"field","domain": domains});
        merge(&mut item, &extras);
        rules.push(item);
    }
    if !ips.is_empty() {
        let mut item = json!({"type":"field","ip": ips});
        merge(&mut item, &extras);
        rules.push(item);
    }
}

fn merge(into: &mut Value, extra: &Value) {
    if let (Some(dest), Some(src)) = (into.as_object_mut(), extra.as_object()) {
        for (key, value) in src {
            dest.insert(key.clone(), value.clone());
        }
    }
}

fn outbound(profile: &Value) -> Value {
    let protocol = s(profile, "protocol");
    let mut node = json!({
        "tag": "proxy",
        "protocol": xray_protocol(&protocol),
        "settings": settings_block(profile),
        "streamSettings": stream(profile)
    });
    if protocol == "hysteria2" || protocol == "hysteria" {
        return json!({
            "tag": "proxy",
            "protocol": "hysteria",
            "settings": {"version": 2, "address": s(profile, "address"), "port": profile["port"].as_u64().unwrap_or(443), "password": s(profile, "password")},
            "streamSettings": {"network": "hysteria", "security": "tls", "tlsSettings": {"serverName": if s(profile, "sni").is_empty() { s(profile, "address") } else { s(profile, "sni") }, "allowInsecure": profile["insecure"].as_bool().unwrap_or(false)}}
        });
    }
    if protocol == "wireguard" {
        let list = |key: &str| -> Vec<String> {
            s(profile, key).split(',').map(|v| v.trim().to_string()).filter(|v| !v.is_empty()).collect()
        };
        let host = s(profile, "address");
        let host = if host.contains(':') && !host.starts_with('[') { format!("[{host}]") } else { host };
        let mut peer = json!({"publicKey": s(profile, "peer_public_key"), "endpoint": format!("{}:{}", host, profile["port"].as_u64().unwrap_or(51820))});
        if !s(profile, "preshared_key").is_empty() {
            peer["preSharedKey"] = json!(s(profile, "preshared_key"));
        }
        let allowed = list("allowed_ips");
        if !allowed.is_empty() {
            peer["allowedIPs"] = json!(allowed);
        }
        if let Some(keepalive) = s(profile, "keepalive").parse::<u64>().ok().filter(|k| *k > 0) {
            peer["keepAlive"] = json!(keepalive);
        }
        let mut settings = json!({"secretKey": s(profile, "private_key"), "address": list("local_address"), "peers": [peer]});
        let reserved: Vec<u8> = list("reserved").iter().filter_map(|b| b.parse().ok()).collect();
        if reserved.len() == 3 {
            settings["reserved"] = json!(reserved);
        }
        let mtu = profile["mtu"].as_u64().or_else(|| s(profile, "mtu").parse().ok()).unwrap_or(0);
        if mtu > 0 {
            settings["mtu"] = json!(mtu);
        }
        node = json!({"tag": "proxy", "protocol": "wireguard", "settings": settings});
    }
    node["remarks"] = json!(s(profile, "remark"));
    if matches!(protocol.as_str(), "dnstt" | "masterdns" | "ping" | "shadowsocksr") {
        node["link"] = json!(s(profile, "link"));
    }
    node
}

fn xray_protocol(protocol: &str) -> &str {
    match protocol {
        "shadowsocks" | "shadowsocksr" => "shadowsocks",
        "hysteria2" => "hysteria",
        "http" => "http",
        "socks" => "socks",
        other => other,
    }
}

fn settings_block(profile: &Value) -> Value {
    let protocol = s(profile, "protocol");
    let address = s(profile, "address");
    let port = profile["port"].as_u64().unwrap_or(443);
    match protocol.as_str() {
        "vless" => json!({"vnext":[{"address": address, "port": port, "users":[{"id": s(profile, "uuid"), "encryption": s(profile, "encryption"), "flow": s(profile, "flow")}]}]}),
        "vmess" => json!({"vnext":[{"address": address, "port": port, "users":[{"id": s(profile, "uuid"), "alterId": profile["alter_id"].as_u64().unwrap_or(0), "security": s(profile, "method")}]}]}),
        "trojan" => json!({"servers":[{"address": address, "port": port, "password": s(profile, "password")}]}),
        "shadowsocks" | "shadowsocksr" => json!({"servers":[{"address": address, "port": port, "method": s(profile, "method"), "password": s(profile, "password")}]}),
        "socks" | "http" => json!({"servers":[{"address": address, "port": port, "users":[{"user": s(profile, "username"), "pass": s(profile, "password")}]}]}),
        _ => json!({"address": address, "port": port}),
    }
}

fn stream(profile: &Value) -> Value {
    let network = s(profile, "network");
    let network = if network.is_empty() { "tcp".to_string() } else { network };
    let mut stream = json!({"network": network});
    let security = s(profile, "tls");
    if security == "reality" || security == "tls" {
        stream["security"] = json!(if security == "reality" { "reality" } else { "tls" });
        let mut tls = json!({
            "serverName": if s(profile, "sni").is_empty() { s(profile, "host") } else { s(profile, "sni") },
            "fingerprint": s(profile, "fp"),
            "allowInsecure": profile["insecure"].as_bool().unwrap_or(false)
        });
        let alpn: Vec<String> = s(profile, "alpn").split(',').map(|v| v.trim().to_string()).filter(|v| !v.is_empty()).collect();
        if !alpn.is_empty() {
            tls["alpn"] = json!(alpn);
        }
        if security == "reality" {
            stream["realitySettings"] = json!({
                "serverName": tls["serverName"],
                "fingerprint": if s(profile, "fp").is_empty() { "chrome".to_string() } else { s(profile, "fp") },
                "publicKey": s(profile, "pbk"),
                "shortId": s(profile, "sid"),
                "spiderX": s(profile, "spx")
            });
            if !s(profile, "pqv").is_empty() {
                stream["realitySettings"]["mldsa65Verify"] = json!(s(profile, "pqv"));
            }
            if !alpn.is_empty() {
                stream["realitySettings"]["alpn"] = json!(alpn);
            }
        } else {
            if let Some(list) = ech_config_list(profile) {
                tls["echConfigList"] = json!(list);
            }
            stream["tlsSettings"] = tls;
        }
    }
    let path = if s(profile, "path").is_empty() { "/".to_string() } else { s(profile, "path") };
    let host = s(profile, "host");
    match network.as_str() {
        "ws" => stream["wsSettings"] = json!({"path": path, "headers": {"Host": host}}),
        "grpc" => stream["grpcSettings"] = json!({"serviceName": s(profile, "service_name")}),
        "h2" | "http" => stream["httpSettings"] = json!({"host": [host], "path": path}),
        "httpupgrade" => stream["httpupgradeSettings"] = json!({"host": host, "path": path}),
        "xhttp" => {
            let mut xhttp = json!({"host": host, "path": path, "mode": if s(profile, "mode").is_empty() { "auto".to_string() } else { s(profile, "mode") }});
            if !s(profile, "x_padding").is_empty() {
                xhttp["xPaddingBytes"] = json!(s(profile, "x_padding"));
            }
            let extra = s(profile, "xhttp_extra");
            if !extra.is_empty() {
                if let Ok(value) = serde_json::from_str::<Value>(&extra) {
                    xhttp["extra"] = value;
                }
            }
            stream["xhttpSettings"] = xhttp;
        }
        "quic" => stream["quicSettings"] = json!({"security": "none"}),
        "kcp" => stream["kcpSettings"] = json!({"mtu": 1350, "tti": 50, "uplinkCapacity": 12, "downlinkCapacity": 100, "congestion": false, "header": {"type": if s(profile, "header_type").is_empty() { "none".to_string() } else { s(profile, "header_type") }}, "seed": if s(profile, "path").is_empty() { s(profile, "seed") } else { s(profile, "path") }}),
        _ => {}
    }
    stream
}

pub fn local_socks(settings: &Value, profile: &Value, port: u16, bind_iface: Option<&str>) -> Value {
    json!({
        "log": {"loglevel": "warning"},
        "inbounds": [{"listen": "127.0.0.1", "port": port, "protocol": "socks", "settings": {"udp": true, "auth": "noauth"}, "sniffing": json!({"enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true})}],
        "outbounds": proxy_outbounds(settings, profile, bind_iface)
    })
}

pub fn routed_socks(settings: &Value, profile: &Value, routes: &[Value], port: u16, bind_iface: Option<&str>) -> Value {
    let mut doc = core(settings, routes, proxy_outbounds(settings, profile, bind_iface));
    doc["inbounds"] = json!([{
        "listen": "127.0.0.1",
        "port": port,
        "protocol": "socks",
        "settings": {"udp": true, "auth": "noauth"},
        "sniffing": sniffing(settings)
    }]);
    doc
}

pub fn dial_addresses(host: &str, port: u16) -> Vec<String> {
    let host = host.trim();
    if host.is_empty() {
        return Vec::new();
    }
    if ip_literal(host) {
        return vec![host.trim_matches(|c| c == '[' || c == ']').to_string()];
    }
    let Ok(found) = (host, port.max(1)).to_socket_addrs() else { return Vec::new() };
    let mut ips = Vec::new();
    for addr in found {
        let ip = addr.ip().to_string();
        if !ips.contains(&ip) {
            ips.push(ip);
        }
    }
    ips
}

pub fn pin_reachable_address(profile: &mut Value) {
    let protocol = s(profile, "protocol");
    let network = s(profile, "network");
    if matches!(protocol.as_str(), "wireguard" | "hysteria" | "hysteria2") || matches!(network.as_str(), "quic" | "kcp") {
        return;
    }
    let address = s(profile, "address");
    if address.is_empty() || ip_literal(&address) {
        return;
    }
    let port = profile["port"].as_u64().unwrap_or(443).min(65535) as u16;
    if port == 0 {
        return;
    }
    let sni = s(profile, "sni");
    let host = s(profile, "host");
    let server_name = if !sni.is_empty() { sni } else if !host.is_empty() { host } else { address.clone() };
    let tls = matches!(s(profile, "tls").as_str(), "tls" | "reality");
    if let Some(ip) = first_reachable(&address, port, &server_name, tls) {
        profile["address"] = json!(ip);
    }
}

fn ip_literal(host: &str) -> bool {
    host.trim_matches(|c| c == '[' || c == ']').parse::<IpAddr>().is_ok()
}

fn first_reachable(host: &str, port: u16, server_name: &str, tls: bool) -> Option<String> {
    let addrs: Vec<SocketAddr> = (host, port).to_socket_addrs().ok()?.collect();
    if addrs.is_empty() {
        return None;
    }
    let (tx, rx) = mpsc::channel();
    for addr in addrs.into_iter().take(8) {
        let tx = tx.clone();
        let server_name = server_name.to_string();
        thread::spawn(move || {
            let ok = if tls { speaks_tls(addr, &server_name) } else { tcp_open(addr) };
            if ok {
                let _ = tx.send(addr.ip().to_string());
            }
        });
    }
    drop(tx);
    rx.recv_timeout(Duration::from_millis(2500)).ok()
}

fn tcp_open(addr: SocketAddr) -> bool {
    TcpStream::connect_timeout(&addr, Duration::from_millis(1500)).is_ok()
}

fn speaks_tls(addr: SocketAddr, server_name: &str) -> bool {
    let timeout = Duration::from_millis(1500);
    let Ok(mut sock) = TcpStream::connect_timeout(&addr, timeout) else { return false };
    let _ = sock.set_read_timeout(Some(timeout));
    let _ = sock.set_write_timeout(Some(timeout));
    if sock.write_all(&client_hello(server_name)).is_err() {
        return false;
    }
    let mut kind = [0u8; 1];
    sock.read_exact(&mut kind).is_ok() && (kind[0] == 0x16 || kind[0] == 0x15)
}

fn client_hello(server_name: &str) -> Vec<u8> {
    let name = server_name.as_bytes();
    let mut extensions = Vec::new();
    push_ext(&mut extensions, 0x0000, |body| {
        body.extend_from_slice(&((name.len() + 3) as u16).to_be_bytes());
        body.push(0);
        body.extend_from_slice(&(name.len() as u16).to_be_bytes());
        body.extend_from_slice(name);
    });
    push_ext(&mut extensions, 0x000a, |body| {
        let groups = [0x00u8, 0x1d, 0x00, 0x17];
        body.extend_from_slice(&(groups.len() as u16).to_be_bytes());
        body.extend_from_slice(&groups);
    });
    push_ext(&mut extensions, 0x000b, |body| {
        body.push(1);
        body.push(0);
    });
    push_ext(&mut extensions, 0x000d, |body| {
        let algs = [0x04u8, 0x03, 0x08, 0x04, 0x04, 0x01, 0x05, 0x03, 0x08, 0x05, 0x05, 0x01, 0x08, 0x06, 0x06, 0x01];
        body.extend_from_slice(&(algs.len() as u16).to_be_bytes());
        body.extend_from_slice(&algs);
    });
    push_ext(&mut extensions, 0x002b, |body| {
        body.push(4);
        body.extend_from_slice(&[0x03, 0x04, 0x03, 0x03]);
    });
    push_ext(&mut extensions, 0x0010, |body| {
        let alpn = b"\x02h2\x08http/1.1";
        body.extend_from_slice(&(alpn.len() as u16).to_be_bytes());
        body.extend_from_slice(alpn);
    });
    let mut random = [0u8; 32];
    let _ = getrandom::getrandom(&mut random);
    let ciphers: &[u8] = &[0x13, 0x01, 0x13, 0x02, 0x13, 0x03, 0xc0, 0x2b, 0xc0, 0x2f, 0xc0, 0x2c, 0xc0, 0x30, 0x00, 0x9c, 0x00, 0x9d, 0x00, 0x2f, 0x00, 0x35];
    let mut hello = Vec::new();
    hello.extend_from_slice(&[0x03, 0x03]);
    hello.extend_from_slice(&random);
    hello.push(0);
    hello.extend_from_slice(&(ciphers.len() as u16).to_be_bytes());
    hello.extend_from_slice(ciphers);
    hello.push(1);
    hello.push(0);
    hello.extend_from_slice(&(extensions.len() as u16).to_be_bytes());
    hello.extend_from_slice(&extensions);
    let mut handshake = Vec::new();
    handshake.push(0x01);
    let len = hello.len();
    handshake.push(((len >> 16) & 0xff) as u8);
    handshake.push(((len >> 8) & 0xff) as u8);
    handshake.push((len & 0xff) as u8);
    handshake.extend_from_slice(&hello);
    let mut record = Vec::new();
    record.push(0x16);
    record.extend_from_slice(&[0x03, 0x01]);
    record.extend_from_slice(&(handshake.len() as u16).to_be_bytes());
    record.extend_from_slice(&handshake);
    record
}

fn push_ext(out: &mut Vec<u8>, id: u16, fill: impl FnOnce(&mut Vec<u8>)) {
    let mut body = Vec::new();
    fill(&mut body);
    out.extend_from_slice(&id.to_be_bytes());
    out.extend_from_slice(&(body.len() as u16).to_be_bytes());
    out.extend_from_slice(&body);
}

fn bind_outbound(mut node: Value, bind_iface: Option<&str>) -> Value {
    if let Some(iface) = bind_iface.filter(|s| !s.is_empty()) {
        sockopt(&mut node)["interface"] = json!(iface);
    }
    node
}

fn sockopt(node: &mut Value) -> &mut Value {
    if !node.get("streamSettings").map(|v| v.is_object()).unwrap_or(false) {
        node["streamSettings"] = json!({});
    }
    if !node["streamSettings"].get("sockopt").map(|v| v.is_object()).unwrap_or(false) {
        node["streamSettings"]["sockopt"] = json!({});
    }
    &mut node["streamSettings"]["sockopt"]
}

pub fn proxy_outbounds(settings: &Value, profile: &Value, bind_iface: Option<&str>) -> Vec<Value> {
    let mut proxy = outbound(profile);
    match dialer(settings, profile) {
        Some(dialer) => {
            sockopt(&mut proxy)["dialerProxy"] = json!("dialer");
            vec![proxy, bind_outbound(dialer, bind_iface)]
        }
        None => vec![bind_outbound(proxy, bind_iface)],
    }
}

fn dialer(settings: &Value, profile: &Value) -> Option<Value> {
    let protocol = s(profile, "protocol");
    let network = s(profile, "network");
    let udp = matches!(protocol.as_str(), "wireguard" | "hysteria" | "hysteria2") || matches!(network.as_str(), "quic" | "kcp");
    let tls = matches!(s(profile, "tls").as_str(), "tls" | "reality");
    let mut freedom = json!({"domainStrategy": "AsIs"});
    let mut used = false;
    if settings["fragment_enabled"].as_bool().unwrap_or(false) && tls && !udp {
        let packets = settings["fragment_packets"].as_str().filter(|v| !v.trim().is_empty()).unwrap_or("tlshello");
        let length = settings["fragment_length"].as_str().filter(|v| !v.trim().is_empty()).unwrap_or("100-200");
        let interval = settings["fragment_interval"].as_str().filter(|v| !v.trim().is_empty()).unwrap_or("10-20");
        freedom["fragment"] = json!({"packets": packets.trim(), "length": length.trim(), "interval": interval.trim()});
        used = true;
    }
    let noises = noises(settings);
    if !noises.is_empty() && udp {
        freedom["noises"] = Value::Array(noises);
        used = true;
    }
    used.then(|| json!({"tag": "dialer", "protocol": "freedom", "settings": freedom}))
}

pub fn noises(settings: &Value) -> Vec<Value> {
    if !settings["xray_noise_enabled"].as_bool().unwrap_or(false) {
        return Vec::new();
    }
    let mut out = Vec::new();
    for item in settings["xray_noises"].as_array().cloned().unwrap_or_default() {
        let kind = item["type"].as_str().unwrap_or("rand").trim().to_ascii_lowercase();
        let packet = item["packet"].as_str().unwrap_or("").trim().to_string();
        if !matches!(kind.as_str(), "rand" | "str" | "hex" | "base64") || packet.is_empty() {
            continue;
        }
        let mut noise = json!({"type": kind, "packet": packet});
        let delay = item["delay"].as_str().unwrap_or("").trim();
        if !delay.is_empty() {
            noise["delay"] = json!(delay);
        }
        let apply = item["apply_to"].as_str().unwrap_or("").trim();
        if matches!(apply, "ip" | "ipv4" | "ipv6") {
            noise["applyTo"] = json!(apply);
        }
        out.push(noise);
    }
    out
}

fn ech_config_list(profile: &Value) -> Option<String> {
    if !matches!(&profile["ech"], Value::Bool(true)) && !matches!(profile["ech"].as_str(), Some("1" | "true")) {
        return None;
    }
    let config = s(profile, "ech_config");
    let name = s(profile, "ech_query_server_name");
    let config = config.trim();
    if !config.is_empty() && !config.contains("://") {
        return Some(crate::parser::pem_to_b64(config));
    }
    let server = if config.is_empty() { "https://1.1.1.1/dns-query" } else { config };
    Some(if name.is_empty() { server.to_string() } else { format!("{name}+{server}") })
}

fn list(value: &Value) -> Vec<String> {
    if let Some(arr) = value.as_array() {
        return arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).filter(|s| !s.is_empty()).collect();
    }
    value.as_str().unwrap_or("").lines().map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xhttp_tls_keeps_alpn() {
        let profile = json!({
            "protocol": "vless",
            "address": "example.com",
            "port": 443,
            "uuid": "b1a2c3d4-1111-2222-3333-444455556666",
            "encryption": "none",
            "network": "xhttp",
            "tls": "tls",
            "sni": "example.com",
            "host": "example.com",
            "path": "/xh",
            "mode": "stream-up",
            "alpn": "h2",
            "fp": "chrome"
        });
        let doc = local_socks(&json!({}), &profile, 18080, None);
        let alpn = &doc["outbounds"][0]["streamSettings"]["tlsSettings"]["alpn"];
        assert_eq!(alpn, &json!(["h2"]));
    }

    #[test]
    fn pin_keeps_ip_literals() {
        let mut profile = json!({"protocol": "vless", "address": "203.0.113.10", "port": 443, "tls": "tls", "network": "tcp"});
        pin_reachable_address(&mut profile);
        assert_eq!(profile["address"], json!("203.0.113.10"));
    }

    #[test]
    fn client_hello_includes_server_name() {
        let hello = client_hello("example.com");
        assert_eq!(hello[0], 0x16);
        assert!(hello.windows(b"example.com".len()).any(|w| w == b"example.com"));
    }

    #[test]
    fn tun_inbound_is_xray0_with_socks_bridge() {
        let settings = json!({
            "use_xray_tun": true,
            "socks_port": 10808,
            "http_port": 10807,
            "lan_sharing": false,
            "mtu": 1500,
            "loglevel": "warning"
        });
        let profile = json!({
            "protocol": "vless",
            "address": "example.com",
            "port": 443,
            "uuid": "b1a2c3d4-1111-2222-3333-444455556666",
            "encryption": "none",
            "network": "tcp",
            "tls": "tls",
            "sni": "example.com"
        });
        let doc = document(&settings, &profile, &[]);
        let inbounds = doc["inbounds"].as_array().cloned().unwrap_or_default();
        let tun = inbounds.iter().find(|item| item["tag"] == "tun-in").expect("tun inbound");
        assert_eq!(tun["settings"]["name"], json!("xray0"));
        assert!(tun.get("settings").and_then(|s| s.get("stack")).is_none());
        let socks = inbounds.iter().find(|item| item["tag"] == "socks-tun").expect("socks bridge");
        assert_eq!(socks["port"], json!(10809));
        assert_eq!(socks["listen"], json!("127.0.0.1"));
    }

    fn xray_accepts(doc: &Value, label: &str) {
        let bin = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../binaries/macos/xray");
        if !bin.exists() {
            return;
        }
        let file = std::env::temp_dir().join(format!("v2open-xray-{label}.json"));
        std::fs::write(&file, serde_json::to_string_pretty(doc).unwrap()).unwrap();
        let out = std::process::Command::new(&bin).args(["run", "-test", "-c"]).arg(&file).output().unwrap();
        assert!(out.status.success(), "{label}: {}{}", String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
    }

    #[test]
    fn dialer_carries_fragment_noise_and_ech() {
        let settings = json!({
            "fragment_enabled": true, "fragment_packets": "tlshello", "fragment_length": "100-200", "fragment_interval": "10-20",
            "xray_noise_enabled": true,
            "xray_noises": [
                {"type": "rand", "packet": "10-20", "delay": "10-16", "apply_to": "ip"},
                {"type": "str", "packet": "hello", "delay": "", "apply_to": "ipv4"},
                {"type": "bogus", "packet": "x"}
            ]
        });
        let vless = json!({
            "protocol": "vless", "address": "example.com", "port": 443, "uuid": "b1a2c3d4-1111-2222-3333-444455556666",
            "encryption": "none", "network": "tcp", "tls": "tls", "sni": "example.com", "ech": true, "ech_query_server_name": "cloudflare-ech.com"
        });
        let doc = local_socks(&settings, &vless, 18080, Some("en0"));
        let outbounds = doc["outbounds"].as_array().unwrap();
        assert_eq!(outbounds[0]["streamSettings"]["sockopt"]["dialerProxy"], "dialer");
        assert_eq!(outbounds[0]["streamSettings"]["tlsSettings"]["echConfigList"], "cloudflare-ech.com+https://1.1.1.1/dns-query");
        assert_eq!(outbounds[1]["settings"]["fragment"]["packets"], "tlshello");
        assert!(outbounds[1]["settings"].get("noises").is_none());
        assert_eq!(outbounds[1]["streamSettings"]["sockopt"]["interface"], "en0");
        xray_accepts(&doc, "fragment-ech");

        let hy2 = json!({"protocol": "hysteria2", "address": "example.com", "port": 443, "password": "p", "tls": "tls", "sni": "example.com"});
        let doc = local_socks(&settings, &hy2, 18081, None);
        let noises = doc["outbounds"][1]["settings"]["noises"].as_array().unwrap();
        assert_eq!(noises.len(), 2);
        assert!(doc["outbounds"][1]["settings"].get("fragment").is_none());
        xray_accepts(&doc, "noise-hy2");

        let wg = json!({"protocol": "wireguard", "address": "1.2.3.4", "port": 51820, "private_key": "yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=",
            "peer_public_key": "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=", "local_address": "10.8.1.2/32,fd00::2/128", "mtu": 1280, "keepalive": "25", "reserved": "1,2,3"});
        xray_accepts(&local_socks(&settings, &wg, 18082, None), "noise-wg");

        let plain = local_socks(&json!({}), &vless, 18083, None);
        assert_eq!(plain["outbounds"].as_array().unwrap().len(), 1);
    }
}
