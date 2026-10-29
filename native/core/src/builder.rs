use crate::parser::{parse_link, split_host_port};
use serde_json::{json, Value};
use std::path::Path;

pub use crate::routing::preset;

fn s(v: &Value, key: &str) -> String {
    v.get(key).and_then(|x| x.as_str()).unwrap_or("").to_string()
}

pub fn build_config(settings: &Value, profiles: &[Value], rules: &[Value], rules_dir: &Path, mode: &str) -> Result<Value, String> {
    assemble(settings, profiles, rules, rules_dir, mode, false)
}

pub fn build_pipe(settings: &Value, profiles: &[Value], rules: &[Value], rules_dir: &Path, mode: &str) -> Result<Value, String> {
    assemble(settings, profiles, rules, rules_dir, mode, true)
}

pub fn exclude_tunnel_addresses(config: &mut Value, ips: &[String]) {
    if ips.is_empty() {
        return;
    }
    let Some(inbounds) = config.get_mut("inbounds").and_then(|v| v.as_array_mut()) else { return };
    for inbound in inbounds {
        if inbound.get("type").and_then(|v| v.as_str()) != Some("tun") {
            continue;
        }
        let mut list = inbound.get("route_exclude_address").and_then(|v| v.as_array()).cloned().unwrap_or_default();
        for ip in ips {
            let ip = ip.trim();
            if ip.is_empty() {
                continue;
            }
            let cidr = if ip.contains('/') {
                ip.to_string()
            } else if ip.contains(':') {
                format!("{ip}/128")
            } else {
                format!("{ip}/32")
            };
            let value = Value::String(cidr);
            if !list.contains(&value) {
                list.push(value);
            }
        }
        inbound["route_exclude_address"] = Value::Array(list);
    }
}

fn assemble(settings: &Value, profiles: &[Value], rules: &[Value], rules_dir: &Path, mode: &str, pipe: bool) -> Result<Value, String> {
    if profiles.is_empty() {
        return Err("no profile".into());
    }
    let mut outbounds = Vec::new();
    let mut endpoints = Vec::new();
    let mut tags: Vec<(String, String)> = Vec::new();
    for (i, profile) in profiles.iter().enumerate() {
        let produced = materialize(profile, &format!("p{i}"), settings)?;
        for (kind, tag, node) in &produced {
            if kind == "endpoint" {
                endpoints.push(node.clone());
            } else {
                outbounds.push(node.clone());
            }
            let _ = tag;
        }
        let last = produced.last().unwrap();
        tags.push((last.0.clone(), last.1.clone()));
    }
    let final_tag = if profiles.len() > 1 {
        let proxy_tags: Vec<String> = tags.iter().filter(|(k, _)| k == "outbound").map(|(_, t)| t.clone()).collect();
        if proxy_tags.is_empty() {
            return Err("smart connect needs proxy profiles".into());
        }
        outbounds.push(json!({
            "type": "urltest",
            "tag": "auto",
            "outbounds": proxy_tags,
            "url": settings["speed_endpoint"].as_str().unwrap_or("https://www.gstatic.com/generate_204"),
            "interval": "1m",
            "tolerance": 50
        }));
        "auto".to_string()
    } else {
        tags[0].1.clone()
    };
    outbounds.push(json!({"type":"direct","tag":"direct"}));
    outbounds.push(json!({"type":"block","tag":"block"}));
    for outbound in &mut outbounds {
        let kind = outbound["type"].as_str().unwrap_or("");
        if !matches!(kind, "direct" | "block" | "urltest") && outbound.get("domain_resolver").is_none() {
            outbound["domain_resolver"] = json!("dns-direct");
        }
    }
    let listen = if settings["lan_sharing"].as_bool().unwrap_or(false) { "0.0.0.0" } else { "127.0.0.1" };
    let mut inbounds = Vec::new();
    if mode == "tun" {
        let mut tun = json!({
            "type": "tun",
            "tag": "tun-in",
            "address": ["172.19.0.1/30"],
            "mtu": settings["mtu"].as_u64().unwrap_or(1500),
            "auto_route": true,
            "strict_route": settings["kill_switch"].as_bool().unwrap_or(false) || settings["enforce_routes"].as_bool().unwrap_or(false),
            "stack": "gvisor"
        });
        if !settings["include_local"].as_bool().unwrap_or(false) {
            tun["route_exclude_address"] = json!(["10.0.0.0/8","172.16.0.0/12","192.168.0.0/16","127.0.0.0/8","169.254.0.0/16","fc00::/7","fe80::/10"]);
        }
        inbounds.push(tun);
    }
    if settings["socks_enabled"].as_bool().unwrap_or(true) {
        inbounds.push(json!({"type":"socks","tag":"socks-in","listen":listen,"listen_port": settings["socks_port"].as_u64().unwrap_or(10808)}));
    }
    if settings["http_enabled"].as_bool().unwrap_or(true) {
        inbounds.push(json!({"type":"http","tag":"http-in","listen":listen,"listen_port": settings["http_port"].as_u64().unwrap_or(10807)}));
    }
    let dns = dns(settings, rules_dir);
    let (route_rules, rule_sets) = route(settings, rules, rules_dir, mode, pipe)?;
    let mut experimental = json!({"clash_api": {"external_controller": format!("127.0.0.1:{}", settings["clash_port"].as_u64().unwrap_or(9097)), "secret": ""}});
    if settings["fake_dns"].as_bool().unwrap_or(false) {
        experimental["cache_file"] = json!({"enabled": true, "path": rules_dir.join("fakeip.cache").to_string_lossy(), "store_fakeip": true});
    }
    let mut config = json!({
        "log": {"level": if settings["logging_enabled"].as_bool().unwrap_or(true) { level(settings) } else { "error" }, "timestamp": true},
        "dns": dns,
        "inbounds": inbounds,
        "outbounds": outbounds,
        "route": {
            "rules": route_rules,
            "rule_set": rule_sets,
            "final": final_tag,
            "auto_detect_interface": true,
            "default_domain_resolver": {"server":"dns-direct","strategy": strategy(settings)}
        },
        "experimental": experimental
    });
    if !endpoints.is_empty() {
        config["endpoints"] = Value::Array(endpoints);
    }
    rewrite(&mut config, &final_tag);
    if settings["per_app_mode"].as_str() == Some("include") && !process_names(settings).is_empty() {
        config["route"]["final"] = json!("direct");
    }
    Ok(config)
}

fn process_names(settings: &Value) -> Vec<String> {
    let mut names = Vec::new();
    if let Some(arr) = settings["per_app_list"].as_array() {
        names.extend(arr.iter().filter_map(|v| v.as_str().map(|s| s.trim().to_string())).filter(|s| !s.is_empty()));
    }
    names.extend(settings["per_app_text"].as_str().unwrap_or("").lines().map(|s| s.trim().to_string()).filter(|s| !s.is_empty()));
    names.sort();
    names.dedup();
    names
}

fn level(settings: &Value) -> &'static str {
    match settings["loglevel"].as_str().unwrap_or("info") {
        "none" | "error" => "error",
        "warning" | "warn" => "warn",
        "debug" => "debug",
        _ => "info",
    }
}

fn rewrite(config: &mut Value, tag: &str) {
    if let Some(rules) = config["route"]["rules"].as_array_mut() {
        for rule in rules {
            if rule["outbound"].as_str() == Some("proxy") {
                rule["outbound"] = json!(tag);
            }
        }
    }
    if config["route"]["final"].as_str() == Some("proxy") {
        config["route"]["final"] = json!(tag);
    }
    if let Some(servers) = config["dns"]["servers"].as_array_mut() {
        for server in servers {
            if server["detour"].as_str() == Some("proxy") {
                server["detour"] = json!(tag);
            }
        }
    }
}

fn materialize(profile: &Value, prefix: &str, settings: &Value) -> Result<Vec<(String, String, Value)>, String> {
    if s(profile, "protocol") != "chain" {
        let (kind, node) = node(profile, prefix, settings)?;
        return Ok(vec![(kind, prefix.to_string(), node)]);
    }
    let mut hops = Vec::new();
    for hop in profile["chain"].as_array().cloned().unwrap_or_default() {
        if let Some(link) = hop.as_str() {
            hops.push(parse_link(link)?);
        } else if hop["protocol"].as_str().unwrap_or("").is_empty() {
            if let Some(link) = hop["link"].as_str() {
                hops.push(parse_link(link)?);
            }
        } else {
            hops.push(hop);
        }
    }
    if hops.is_empty() {
        return Err("chain has no hops".into());
    }
    let mut produced: Vec<(String, String, Value)> = Vec::new();
    for (i, hop) in hops.iter().enumerate() {
        if matches!(s(hop, "protocol").as_str(), "wireguard" | "chain") {
            return Err("chain hops must be proxy links".into());
        }
        let tag = format!("{prefix}h{i}");
        let (kind, mut node) = node(hop, &tag, settings)?;
        if i > 0 {
            node["detour"] = json!(produced.last().unwrap().1);
        }
        produced.push((kind, tag, node));
    }
    Ok(produced)
}

fn node(profile: &Value, tag: &str, settings: &Value) -> Result<(String, Value), String> {
    let protocol = s(profile, "protocol");
    if matches!(protocol.as_str(), "dnstt" | "masterdns" | "ping" | "shadowsocksr" | "subscription") {
        return Err(format!("{protocol} is saved, and this core does not run it"));
    }
    if protocol == "wireguard" {
        return Ok(("endpoint".into(), wireguard(profile, tag)));
    }
    Ok(("outbound".into(), proxy(profile, tag, settings)?))
}

fn proxy(profile: &Value, tag: &str, settings: &Value) -> Result<Value, String> {
    let protocol = s(profile, "protocol");
    let mut node = json!({
        "tag": tag,
        "server": s(profile, "address"),
        "server_port": profile["port"].as_u64().unwrap_or(443)
    });
    match protocol.as_str() {
        "vless" => {
            node["type"] = json!("vless");
            node["uuid"] = json!(s(profile, "uuid"));
            node["packet_encoding"] = json!(if s(profile, "packet_encoding").is_empty() { "xudp".into() } else { s(profile, "packet_encoding") });
            if !s(profile, "flow").is_empty() {
                node["flow"] = json!(s(profile, "flow"));
            }
        }
        "vmess" => {
            node["type"] = json!("vmess");
            node["uuid"] = json!(s(profile, "uuid"));
            let method = s(profile, "method");
            node["security"] = json!(if method.is_empty() { "auto".to_string() } else { method });
            node["alter_id"] = json!(profile["alter_id"].as_u64().unwrap_or(0));
        }
        "trojan" => {
            node["type"] = json!("trojan");
            node["password"] = json!(s(profile, "password"));
        }
        "shadowsocks" => {
            node["type"] = json!("shadowsocks");
            let method = s(profile, "method");
            node["method"] = json!(if method.is_empty() { "chacha20-ietf-poly1305".to_string() } else { method });
            node["password"] = json!(s(profile, "password"));
        }
        "socks" => {
            node["type"] = json!("socks");
            node["version"] = json!("5");
            if !s(profile, "username").is_empty() {
                node["username"] = json!(s(profile, "username"));
                node["password"] = json!(s(profile, "password"));
            }
        }
        "http" => {
            node["type"] = json!("http");
            if !s(profile, "username").is_empty() {
                node["username"] = json!(s(profile, "username"));
                node["password"] = json!(s(profile, "password"));
            }
        }
        "ssh" => {
            node["type"] = json!("ssh");
            let user = s(profile, "username");
            node["user"] = json!(if user.is_empty() { "root".to_string() } else { user });
            node["password"] = json!(s(profile, "password"));
            node["server_port"] = json!(profile["port"].as_u64().unwrap_or(22));
            if !s(profile, "private_key").is_empty() {
                node["private_key"] = json!(s(profile, "private_key"));
            }
        }
        "hysteria2" => {
            let mut password = s(profile, "password");
            if !s(profile, "username").is_empty() {
                password = format!("{password}:{}", s(profile, "username"));
            }
            node["type"] = json!("hysteria2");
            node["password"] = json!(password);
            if profile["up_mbps"].as_u64().unwrap_or(0) > 0 {
                node["up_mbps"] = profile["up_mbps"].clone();
            }
            if profile["down_mbps"].as_u64().unwrap_or(0) > 0 {
                node["down_mbps"] = profile["down_mbps"].clone();
            }
            if !s(profile, "obfs").is_empty() {
                node["obfs"] = json!({"type": s(profile, "obfs"), "password": s(profile, "obfs_password")});
            }
            if !s(profile, "hop_port").is_empty() {
                node.as_object_mut().unwrap().remove("server_port");
                node["server_ports"] = json!([s(profile, "hop_port").replace('-', ":")]);
            }
        }
        "hysteria" => {
            node["type"] = json!("hysteria");
            node["auth_str"] = json!(s(profile, "password"));
            node["up_mbps"] = json!(profile["up_mbps"].as_u64().filter(|n| *n > 0).unwrap_or(100));
            node["down_mbps"] = json!(profile["down_mbps"].as_u64().filter(|n| *n > 0).unwrap_or(100));
        }
        other => return Err(format!("unsupported protocol {other}")),
    }
    if let Some(tls) = tls(profile, settings) {
        if !matches!(protocol.as_str(), "shadowsocks" | "socks" | "ssh") {
            node["tls"] = tls;
        }
    }
    if let Some(transport) = transport(profile)? {
        if matches!(protocol.as_str(), "vless" | "vmess" | "trojan") {
            node["transport"] = transport;
        }
    }
    if settings["mux_enabled"].as_bool().unwrap_or(false) && s(profile, "flow").is_empty() && matches!(protocol.as_str(), "vmess" | "vless" | "trojan" | "shadowsocks") {
        node["multiplex"] = json!({"enabled": true, "protocol": "smux", "max_connections": settings["mux_concurrency"].as_u64().unwrap_or(8)});
    }
    Ok(node)
}

fn tls(profile: &Value, settings: &Value) -> Option<Value> {
    let mode = s(profile, "tls");
    if mode == "none" || mode.is_empty() {
        return None;
    }
    let insecure = profile["insecure"].as_bool().unwrap_or(false) || (settings["allow_insecure"].as_bool().unwrap_or(false) && mode == "tls");
    let sni = s(profile, "sni");
    let host = s(profile, "host");
    let address = s(profile, "address");
    let server_name = if !sni.is_empty() { sni } else if !host.is_empty() { host } else { address };
    let mut tls = json!({"enabled": true, "server_name": server_name, "insecure": insecure});
    let alpn_raw = s(profile, "alpn");
    let alpn: Vec<String> = alpn_raw.split(',').map(|v| v.trim().to_string()).filter(|v| !v.is_empty()).collect();
    if !alpn.is_empty() {
        tls["alpn"] = json!(alpn);
    }
    let fp = s(profile, "fp");
    if !fp.is_empty() {
        tls["utls"] = json!({"enabled": true, "fingerprint": fp});
    }
    if mode == "reality" {
        let fp = s(profile, "fp");
        tls["reality"] = json!({"enabled": true, "public_key": s(profile, "pbk"), "short_id": s(profile, "sid")});
        tls["utls"] = json!({"enabled": true, "fingerprint": if fp.is_empty() { "chrome".to_string() } else { fp }});
    }
    Some(tls)
}

fn transport(profile: &Value) -> Result<Option<Value>, String> {
    let network = s(profile, "network");
    if matches!(network.as_str(), "tcp" | "raw" | "none" | "") {
        return Ok(None);
    }
    if network == "kcp" {
        return Err("mKCP is not available on this core".into());
    }
    let path = s(profile, "path");
    let path = if path.is_empty() { "/".to_string() } else { path };
    if network == "ws" {
        let mut headers = json!({});
        let host = s(profile, "host");
        if !host.is_empty() {
            headers["Host"] = json!(host);
        }
        return Ok(Some(json!({"type":"ws","path": path, "headers": headers})));
    }
    if network == "grpc" {
        return Ok(Some(json!({"type":"grpc","service_name": s(profile, "service_name")})));
    }
    if network == "h2" || network == "http" {
        let host = s(profile, "host");
        let hosts = if host.is_empty() { Vec::<String>::new() } else { vec![host] };
        return Ok(Some(json!({"type":"http","host": hosts, "path": path})));
    }
    if network == "httpupgrade" {
        return Ok(Some(json!({"type":"httpupgrade","host": s(profile, "host"), "path": path})));
    }
    if network == "xhttp" {
        let mode = s(profile, "mode");
        let mode = if mode.is_empty() { "auto".to_string() } else { mode };
        let padding = s(profile, "x_padding");
        let padding = if padding.is_empty() { "100-1000".to_string() } else { padding };
        return Ok(Some(json!({"type":"xhttp","host": s(profile, "host"), "path": path, "mode": mode, "x_padding_bytes": padding})));
    }
    if network == "quic" {
        return Ok(Some(json!({"type":"quic"})));
    }
    Err(format!("transport {network} is not available on this core"))
}

fn wireguard(profile: &Value, tag: &str) -> Value {
    let reserved: Vec<u64> = s(profile, "reserved").split(',').filter_map(|p| p.trim().parse().ok()).take(3).collect();
    let local: Vec<String> = if s(profile, "local_address").is_empty() { vec!["10.0.0.2/32".into()] } else { s(profile, "local_address").split(',').map(|v| v.trim().to_string()).filter(|v| !v.is_empty()).collect() };
    let mut peer = json!({
        "address": s(profile, "address"),
        "port": profile["port"].as_u64().unwrap_or(51820),
        "public_key": s(profile, "peer_public_key"),
        "allowed_ips": ["0.0.0.0/0", "::/0"]
    });
    if !s(profile, "preshared_key").is_empty() {
        peer["pre_shared_key"] = json!(s(profile, "preshared_key"));
    }
    if !reserved.is_empty() {
        peer["reserved"] = json!(reserved);
    }
    json!({
        "type": "wireguard",
        "tag": tag,
        "private_key": s(profile, "private_key"),
        "address": local,
        "mtu": profile["mtu"].as_u64().filter(|n| *n > 0).unwrap_or(1280),
        "peers": [peer],
        "domain_resolver": "dns-direct"
    })
}

fn strategy(settings: &Value) -> &'static str {
    if settings["prefer_ipv6"].as_bool().unwrap_or(false) && settings["query_strategy"].as_str() != Some("ipv4_only") {
        return "prefer_ipv6";
    }
    match settings["query_strategy"].as_str().unwrap_or("prefer_ipv4") {
        "ipv4_only" | "UseIPv4" => "ipv4_only",
        "ipv6_only" | "UseIPv6" => "ipv6_only",
        "prefer_ipv6" => "prefer_ipv6",
        _ => "prefer_ipv4",
    }
}

fn dns(settings: &Value, rules_dir: &Path) -> Value {
    let mut settings = settings.clone();
    crate::dns_items::sync_legacy_dns(&mut settings);
    let remote_id = settings["remote_dns_id"].as_str().unwrap_or("");
    let domestic_id = settings["domestic_dns_id"].as_str().unwrap_or("");
    let remote_item = crate::dns_items::item_by_id(&settings, remote_id);
    let domestic_item = crate::dns_items::item_by_id(&settings, domestic_id);
    let mut domestic = dns_server(settings["domestic_dns"].as_str().unwrap_or("223.5.5.5"), "dns-direct", None, domestic_item);
    let mut remote = dns_server(
        settings["remote_dns"].as_str().unwrap_or("https://1.1.1.1/dns-query"),
        "dns-remote",
        Some("proxy"),
        remote_item,
    );
    remote["domain_resolver"] = json!("dns-direct");
    let mut rules = Vec::new();
    if let Some(hosts) = settings["hosts"].as_object() {
        for (host, ip) in hosts {
            let ip = ip.as_str().unwrap_or("");
            if host.is_empty() || ip.is_empty() {
                continue;
            }
            let record = if ip.contains(':') { "AAAA" } else { "A" };
            rules.push(json!({"domain":[host], "action":"predefined", "rcode":"NOERROR", "answer":[format!("{host}. 300 IN {record} {ip}")]}));
        }
    }
    let split = match settings["dns_split"].as_str().unwrap_or("none") {
        "cn" => Some("geosite-cn"),
        "ir" => Some("geosite-category-ir"),
        "ru" => Some("geosite-category-ru"),
        _ => None,
    };
    if let Some(tag) = split {
        if rules_dir.join(format!("{tag}.srs")).exists() {
            rules.push(json!({"rule_set": tag, "action":"route", "server":"dns-direct"}));
        }
    }
    if rules_dir.join("geosite-private.srs").exists() {
        rules.push(json!({"rule_set":"geosite-private","action":"route","server":"dns-direct"}));
    }
    let names = process_names(&settings);
    let mut dns_final = if settings["final"].as_str() == Some("direct") { "dns-direct" } else { "dns-remote" };
    match settings["per_app_mode"].as_str().unwrap_or("off") {
        "exclude" if !names.is_empty() => {
            rules.insert(0, json!({"process_name": names, "action":"route", "server":"dns-direct"}));
        }
        "include" if !names.is_empty() => {
            rules.insert(0, json!({"process_name": names, "action":"route", "server":"dns-remote"}));
            dns_final = "dns-direct";
        }
        _ => {}
    }
    let mut servers = vec![domestic, remote];
    if let Some(items) = settings["dns_items"].as_array() {
        for item in items {
            if !item["enabled"].as_bool().unwrap_or(true) {
                continue;
            }
            let id = item["id"].as_str().unwrap_or("");
            if id.is_empty() || id == remote_id || id == domestic_id {
                continue;
            }
            let uri = crate::dns_items::item_to_uri(item);
            if uri.is_empty() {
                continue;
            }
            let tag = format!("dns-{id}");
            let detour = match item["role"].as_str().unwrap_or("remote") {
                "domestic" => None,
                _ => Some("proxy"),
            };
            let mut extra = dns_server(&uri, &tag, detour, Some(item));
            if detour.is_some() {
                extra["domain_resolver"] = json!("dns-direct");
            }
            servers.push(extra);
        }
    }
    if settings["fake_dns"].as_bool().unwrap_or(false) {
        servers.insert(0, json!({"type":"fakeip","tag":"fakeip","inet4_range":"198.18.0.0/15","inet6_range":"fc00::/18"}));
        rules.push(json!({"query_type":["A","AAAA"],"action":"route","server":"fakeip"}));
    }
    let mut dns_doc = json!({
        "servers": servers,
        "rules": rules,
        "final": dns_final,
        "strategy": strategy(&settings),
        "disable_cache": settings["dns_cache"].as_bool() == Some(false)
    });
    let item_hosts = crate::dns_items::dns_hosts_map(&settings);
    if let Some(obj) = item_hosts.as_object() {
        if !obj.is_empty() {
            dns_doc["hosts"] = item_hosts;
        }
    }
    dns_doc
}

fn dns_server(raw: &str, tag: &str, detour: Option<&str>, item: Option<&Value>) -> Value {
    let first = raw.split(',').next().unwrap_or(raw).trim();
    let mut server = json!({"tag": tag});
    if let Some(body) = first.strip_prefix("https://") {
        let host = body.split('/').next().unwrap_or(body).split(':').next().unwrap_or(body);
        let name = if host.chars().next().unwrap_or('a').is_ascii_digit() { "cloudflare-dns.com" } else { host };
        server["type"] = json!("https");
        server["server"] = json!(host);
        server["tls"] = json!({"enabled": true, "server_name": name});
    } else if let Some(body) = first.strip_prefix("tls://") {
        let (host, port) = split_host_port(body, 853);
        server["type"] = json!("tls");
        server["server"] = json!(host.clone());
        server["server_port"] = json!(port);
        server["tls"] = json!({"enabled": true, "server_name": host});
    } else {
        let (host, port) = split_host_port(first, 53);
        server["type"] = json!("udp");
        server["server"] = json!(host);
        server["server_port"] = json!(port);
    }
    if let Some(detour) = detour {
        server["detour"] = json!(detour);
    }
    if let Some(item) = item {
        crate::dns_items::apply_to_server(&mut server, item);
    }
    server
}

fn route(settings: &Value, rules: &[Value], rules_dir: &Path, mode: &str, pipe: bool) -> Result<(Vec<Value>, Vec<Value>), String> {
    let mut route_rules = vec![json!({"action":"sniff","timeout":"300ms"})];
    let names = process_names(settings);
    if settings["per_app_mode"].as_str() == Some("exclude") && !names.is_empty() {
        route_rules.push(json!({"action":"route","outbound":"direct","process_name": names.clone()}));
    }
    if mode == "tun" || settings["sniffing"].as_bool().unwrap_or(true) {
        route_rules.push(json!({"action":"hijack-dns","protocol":"dns"}));
    }
    if settings["per_app_mode"].as_str() == Some("include") && !names.is_empty() {
        route_rules.push(json!({"action":"route","outbound":"proxy","process_name": names}));
    }
    if settings["fake_dns"].as_bool().unwrap_or(false) {
        route_rules.push(json!({"action":"resolve","ip_cidr":["198.18.0.0/15","fc00::/18"]}));
    }
    let domain_strategy = settings["domain_strategy"].as_str().unwrap_or("AsIs");
    if matches!(domain_strategy, "IPOnDemand" | "IPIfNonMatch") && !settings["route_only"].as_bool().unwrap_or(false) {
        route_rules.push(json!({"action":"resolve","server":"dns-remote","strategy": strategy(settings)}));
    }
    if !pipe && settings["fragment_enabled"].as_bool().unwrap_or(false) {
        let packets = settings["fragment_packets"].as_str().unwrap_or("tlshello").to_ascii_lowercase();
        if matches!(packets.as_str(), "tlshello" | "1-1" | "1-3") {
            route_rules.push(json!({"action":"route-options","tls_fragment": true, "tls_fragment_fallback_delay": delay(settings["fragment_interval"].as_str().unwrap_or(""))}));
        } else {
            route_rules.push(json!({"action":"route-options","tls_record_fragment": true}));
        }
    }
    if !pipe && settings["block_udp_443"].as_bool().unwrap_or(false) && !covers_udp443(rules) {
        route_rules.push(json!({"action":"reject","network":"udp","port":443}));
    }
    if settings["bypass_lan"].as_bool().unwrap_or(true) && !covers_lan(rules) {
        route_rules.push(json!({"action":"route","outbound":"direct","ip_is_private": true}));
    }
    if !pipe && settings["apple_direct"].as_bool().unwrap_or(false) {
        route_rules.push(json!({"action":"route","outbound":"direct","domain_suffix":["apple.com","icloud.com","mzstatic.com","apple-cloudkit.com","cdn-apple.com"]}));
    }
    let mut needed = Vec::new();
    if !pipe && settings["routing_enabled"].as_bool().unwrap_or(true) {
        for rule in rules {
            if rule["enabled"].as_bool() == Some(false) {
                continue;
            }
            for mut piece in user_rule(rule) {
                if let Some(tag) = piece.get("_ruleset").and_then(|v| v.as_str()).map(|s| s.to_string()) {
                    piece.as_object_mut().unwrap().remove("_ruleset");
                    needed.push(tag);
                }
                route_rules.push(piece);
            }
        }
    }
    let split = match settings["dns_split"].as_str().unwrap_or("") {
        "cn" => Some("geosite-cn"),
        "ir" => Some("geosite-category-ir"),
        "ru" => Some("geosite-category-ru"),
        _ => None,
    };
    if let Some(tag) = split {
        needed.push(tag.to_string());
    }
    needed.push("geosite-private".into());
    let mut sets = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for tag in needed {
        if !seen.insert(tag.clone()) {
            continue;
        }
        let path = rules_dir.join(format!("{tag}.srs"));
        if !path.exists() {
            if tag == "geosite-private" || Some(tag.as_str()) == split {
                continue;
            }
            return Err(format!("missing geo asset {tag}.srs"));
        }
        sets.push(json!({"type":"local","tag": tag, "format":"binary","path": path.to_string_lossy()}));
    }
    Ok((route_rules, sets))
}

fn delay(raw: &str) -> String {
    let number = raw.split('-').next().unwrap_or("").trim().parse::<u64>().unwrap_or(100);
    format!("{}ms", number.max(10))
}

fn user_rule(rule: &Value) -> Vec<Value> {
    let behavior = rule["behavior"].as_str().unwrap_or("proxy");
    let mut base = json!({"action": if behavior == "block" { "reject" } else { "route" }});
    if behavior != "block" {
        base["outbound"] = json!(if behavior == "direct" { "direct" } else { "proxy" });
    }
    let mut extras = json!({});
    let port = rule["port"].as_str().unwrap_or("").trim();
    if !port.is_empty() && port != "0-65535" {
        if port.contains('-') || port.contains(':') {
            extras["port_range"] = json!(port.replace('-', ":"));
        } else if let Ok(n) = port.parse::<u64>() {
            extras["port"] = json!(n);
        }
    }
    let network = rule["network"].as_str().unwrap_or("");
    if network == "tcp" || network == "udp" {
        extras["network"] = json!(network);
    }
    let protocol = rule["protocol"].as_str().unwrap_or("");
    if !protocol.is_empty() {
        extras["protocol"] = json!(protocol);
    }
    let mut pieces = Vec::new();
    let (dmatch, dsets) = domain_match(&list(&rule["domains"]));
    let (imatch, isets) = ip_match(&list(&rule["ips"]));
    if !dmatch.as_object().unwrap().is_empty() {
        let mut item = base.clone();
        merge(&mut item, &extras);
        merge(&mut item, &dmatch);
        pieces.push(item);
    }
    for tag in dsets {
        let mut item = base.clone();
        merge(&mut item, &extras);
        item["rule_set"] = json!(tag);
        item["_ruleset"] = json!(tag);
        pieces.push(item);
    }
    if !imatch.as_object().unwrap().is_empty() {
        let mut item = base.clone();
        merge(&mut item, &extras);
        merge(&mut item, &imatch);
        pieces.push(item);
    }
    for tag in isets {
        let mut item = base.clone();
        merge(&mut item, &extras);
        item["rule_set"] = json!(tag);
        item["_ruleset"] = json!(tag);
        pieces.push(item);
    }
    if pieces.is_empty() && extras.as_object().map(|o| !o.is_empty()).unwrap_or(false) {
        let mut item = base;
        merge(&mut item, &extras);
        pieces.push(item);
    }
    pieces
}

fn covers_udp443(rules: &[Value]) -> bool {
    rules.iter().any(|rule| {
        rule["enabled"].as_bool() != Some(false)
            && rule["behavior"].as_str() == Some("block")
            && rule["network"].as_str() == Some("udp")
            && rule["port"].as_str() == Some("443")
    })
}

fn covers_lan(rules: &[Value]) -> bool {
    rules.iter().any(|rule| {
        if rule["enabled"].as_bool() == Some(false) {
            return false;
        }
        list(&rule["ips"]).iter().any(|item| item == "geoip:private" || item == "private")
            || list(&rule["domains"]).iter().any(|item| item == "geosite:private")
    })
}

fn merge(dst: &mut Value, src: &Value) {
    if let (Some(d), Some(s)) = (dst.as_object_mut(), src.as_object()) {
        for (k, v) in s {
            d.insert(k.clone(), v.clone());
        }
    }
}

fn list(value: &Value) -> Vec<String> {
    if let Some(arr) = value.as_array() {
        return arr.iter().filter_map(|v| v.as_str().map(|s| s.trim().to_string())).filter(|s| !s.is_empty()).collect();
    }
    value.as_str().unwrap_or("").lines().map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect()
}

fn domain_match(items: &[String]) -> (Value, Vec<String>) {
    let mut sets = Vec::new();
    let mut suffixes = Vec::new();
    let mut full = Vec::new();
    let mut keywords = Vec::new();
    for item in items {
        if let Some(rest) = item.strip_prefix("geosite:") {
            sets.push(format!("geosite-{rest}"));
        } else if let Some(rest) = item.strip_prefix("domain:") {
            suffixes.push(rest.trim_start_matches('.').to_string());
        } else if let Some(rest) = item.strip_prefix("full:") {
            full.push(rest.to_string());
        } else if let Some(rest) = item.strip_prefix("keyword:") {
            keywords.push(rest.to_string());
        } else {
            suffixes.push(item.trim_start_matches('.').to_string());
        }
    }
    let mut match_v = json!({});
    if !suffixes.is_empty() {
        match_v["domain_suffix"] = json!(suffixes);
    }
    if !full.is_empty() {
        match_v["domain"] = json!(full);
    }
    if !keywords.is_empty() {
        match_v["domain_keyword"] = json!(keywords);
    }
    (match_v, sets)
}

fn ip_match(items: &[String]) -> (Value, Vec<String>) {
    let mut sets = Vec::new();
    let mut cidrs = Vec::new();
    let mut private = false;
    for item in items {
        if item == "geoip:private" || item == "private" {
            private = true;
        } else if let Some(rest) = item.strip_prefix("geoip:") {
            sets.push(format!("geoip-{rest}"));
        } else if item.contains('/') {
            cidrs.push(item.clone());
        } else if item.split('.').count() == 4 && item.split('.').all(|p| p.parse::<u8>().is_ok()) {
            cidrs.push(format!("{item}/32"));
        } else {
            cidrs.push(item.clone());
        }
    }
    let mut match_v = json!({});
    if !cidrs.is_empty() {
        match_v["ip_cidr"] = json!(cidrs);
    }
    if private {
        match_v["ip_is_private"] = json!(true);
    }
    (match_v, sets)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tunnel_excludes_server_address() {
        let mut config = json!({
            "inbounds": [{
                "type": "tun",
                "route_exclude_address": ["10.0.0.0/8"]
            }]
        });
        exclude_tunnel_addresses(&mut config, &["203.0.113.10".into(), "203.0.113.10".into(), "2001:db8::1".into()]);
        let list = &config["inbounds"][0]["route_exclude_address"];
        assert_eq!(list, &json!(["10.0.0.0/8", "203.0.113.10/32", "2001:db8::1/128"]));
    }

    #[test]
    fn iran_rules_include_udp443_reject() {
        let rules = preset("iran")["rules"].as_array().cloned().unwrap();
        let block = rules.iter().find(|r| r["remark"] == "Block udp443").unwrap();
        let pieces = user_rule(block);
        assert_eq!(pieces.len(), 1);
        assert_eq!(pieces[0]["action"], "reject");
        assert_eq!(pieces[0]["network"], "udp");
        assert_eq!(pieces[0]["port"], 443);
    }
}
