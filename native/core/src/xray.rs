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
    let mut doc = core(settings, routes, outbound(profile));
    doc["inbounds"] = json!([
        {"tag":"socks","port": settings["socks_port"].as_u64().unwrap_or(10808), "listen":"127.0.0.1", "protocol":"socks", "settings":{"udp": true, "auth":"noauth"}, "sniffing": sniffing(settings)},
        {"tag":"http","port": settings["http_port"].as_u64().unwrap_or(10807), "listen":"127.0.0.1", "protocol":"http", "sniffing": sniffing(settings)}
    ]);
    doc
}

fn core(settings: &Value, routes: &[Value], proxy: Value) -> Value {
    let direct = json!({"tag":"direct","protocol":"freedom"});
    let block = json!({"tag":"block","protocol":"blackhole"});
    let outbounds = if settings["final"].as_str() == Some("direct") {
        vec![direct, proxy, block]
    } else {
        vec![proxy, direct, block]
    };
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
        "queryStrategy": if settings["prefer_ipv6"].as_bool().unwrap_or(false) { "UseIPv6" } else { "UseIPv4" }
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
        node = json!({
            "tag": "proxy",
            "protocol": "wireguard",
            "settings": {
                "secretKey": s(profile, "private_key"),
                "address": [s(profile, "local_address")],
                "peers": [{"publicKey": s(profile, "peer_public_key"), "endpoint": format!("{}:{}", s(profile, "address"), profile["port"].as_u64().unwrap_or(51820))}]
            }
        });
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
                "shortId": s(profile, "sid")
            });
            if !alpn.is_empty() {
                stream["realitySettings"]["alpn"] = json!(alpn);
            }
        } else {
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
        "xhttp" => stream["xhttpSettings"] = json!({"host": host, "path": path, "mode": if s(profile, "mode").is_empty() { "auto".to_string() } else { s(profile, "mode") }}),
        "quic" => stream["quicSettings"] = json!({"security": "none"}),
        "kcp" => stream["kcpSettings"] = json!({"mtu": 1350, "tti": 50, "uplinkCapacity": 12, "downlinkCapacity": 100, "congestion": false, "header": {"type": if s(profile, "header_type").is_empty() { "none".to_string() } else { s(profile, "header_type") }}, "seed": if s(profile, "path").is_empty() { s(profile, "seed") } else { s(profile, "path") }}),
        _ => {}
    }
    stream
}

pub fn local_socks(profile: &Value, port: u16, bind_iface: Option<&str>) -> Value {
    let node = bind_outbound(outbound(profile), bind_iface);
    json!({
        "log": {"loglevel": "warning"},
        "inbounds": [{"listen": "127.0.0.1", "port": port, "protocol": "socks", "settings": {"udp": true, "auth": "noauth"}, "sniffing": json!({"enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true})}],
        "outbounds": [node]
    })
}

pub fn routed_socks(settings: &Value, profile: &Value, routes: &[Value], port: u16, bind_iface: Option<&str>) -> Value {
    let node = bind_outbound(outbound(profile), bind_iface);
    let mut doc = core(settings, routes, node);
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
        if !node.get("streamSettings").map(|v| v.is_object()).unwrap_or(false) {
            node["streamSettings"] = json!({});
        }
        node["streamSettings"]["sockopt"] = json!({"interface": iface});
    }
    node
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
        let doc = local_socks(&profile, 18080, None);
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
}
