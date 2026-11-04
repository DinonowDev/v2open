use serde_json::{json, Map, Value};
use std::collections::HashMap;

pub fn blank(protocol: &str) -> Value {
    json!({
        "remark": "",
        "protocol": protocol,
        "address": "",
        "port": 443,
        "uuid": "",
        "password": "",
        "method": "auto",
        "alter_id": 0,
        "flow": "",
        "encryption": "none",
        "network": "tcp",
        "tls": "none",
        "sni": "",
        "fp": "",
        "alpn": "",
        "host": "",
        "path": "",
        "service_name": "",
        "header_type": "none",
        "insecure": false,
        "pbk": "",
        "sid": "",
        "spx": "",
        "obfs": "",
        "obfs_password": "",
        "pin_sha256": "",
        "up_mbps": 0,
        "down_mbps": 0,
        "username": "",
        "private_key": "",
        "peer_public_key": "",
        "preshared_key": "",
        "local_address": "",
        "mtu": 0,
        "reserved": "",
        "pubkey": "",
        "dns_server": "",
        "domain": "",
        "key": "",
        "chain": [],
        "hop_port": "",
        "packet_encoding": "",
        "mode": "",
        "ssr_protocol": "origin",
        "x_padding": "",
        "xhttp_extra": "",
        "spx": "",
        "pqv": "",
        "arq_window_size": "",
        "arq_initial_rto_seconds": "",
        "arq_max_rto_seconds": "",
        "arq_max_data_retries": "",
        "arq_inactivity_timeout_seconds": "",
        "encryption_method": "1",
        "link": ""
    })
}

fn b64_decode(data: &str) -> Option<String> {
    let mut raw = data.trim().replace('-', "+").replace('_', "/");
    let pad = (4 - raw.len() % 4) % 4;
    raw.push_str(&"=".repeat(pad));
    let bytes = base64_decode(&raw)?;
    String::from_utf8(bytes).ok()
}

pub fn base64_decode(input: &str) -> Option<Vec<u8>> {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut map = [255u8; 256];
    for (i, c) in T.iter().enumerate() {
        map[*c as usize] = i as u8;
    }
    let clean: Vec<u8> = input.bytes().filter(|b| *b != b'=' && !b.is_ascii_whitespace()).collect();
    if clean.len() % 4 == 1 {
        return None;
    }
    let mut out = Vec::new();
    let mut i = 0;
    while i < clean.len() {
        let remain = clean.len() - i;
        let n = remain.min(4);
        let mut buf = [0u8; 4];
        for j in 0..n {
            let v = map[clean[i + j] as usize];
            if v == 255 {
                return None;
            }
            buf[j] = v;
        }
        out.push((buf[0] << 2) | (buf[1] >> 4));
        if n > 2 {
            out.push((buf[1] << 4) | (buf[2] >> 2));
        }
        if n > 3 {
            out.push((buf[2] << 6) | buf[3]);
        }
        i += 4;
    }
    Some(out)
}

fn b64_encode(data: &[u8]) -> String {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in data.chunks(3) {
        let b0 = chunk[0];
        let b1 = if chunk.len() > 1 { chunk[1] } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] } else { 0 };
        out.push(T[(b0 >> 2) as usize] as char);
        out.push(T[(((b0 & 3) << 4) | (b1 >> 4)) as usize] as char);
        if chunk.len() > 1 {
            out.push(T[(((b1 & 15) << 2) | (b2 >> 6)) as usize] as char);
        } else {
            out.push('=');
        }
        if chunk.len() > 2 {
            out.push(T[(b2 & 63) as usize] as char);
        } else {
            out.push('=');
        }
    }
    out
}

fn flag(v: &str) -> bool {
    matches!(v.to_ascii_lowercase().as_str(), "1" | "true" | "yes" | "on")
}

fn qs(query: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    for part in query.split('&') {
        if part.is_empty() {
            continue;
        }
        let (k, v) = part.split_once('=').unwrap_or((part, ""));
        out.insert(decode(k), decode(v));
    }
    out
}

fn decode(s: &str) -> String {
    let s = s.replace('+', " ");
    let bytes = s.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(v) = u8::from_str_radix(std::str::from_utf8(&bytes[i + 1..i + 3]).unwrap_or(""), 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn encode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(b as char),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

pub const AWG_KEYS: [&str; 16] = ["jc", "jmin", "jmax", "s1", "s2", "s3", "s4", "h1", "h2", "h3", "h4", "i1", "i2", "i3", "i4", "i5"];

pub fn is_amnezia(node: &Value) -> bool {
    AWG_KEYS.iter().any(|k| !s(node, &format!("awg_{k}")).is_empty())
}

pub fn split_host_port(hostport: &str, fallback: u16) -> (String, u16) {
    let raw = hostport.trim();
    let raw = if raw.starts_with('[') { raw } else { raw.split('/').next().unwrap_or(raw) };
    if let Some(rest) = raw.strip_prefix('[') {
        if let Some(end) = rest.find(']') {
            let host = rest[..end].to_string();
            let after = &rest[end + 1..];
            if let Some(port) = after.strip_prefix(':') {
                return (host, port.split('/').next().unwrap_or("").parse().unwrap_or(fallback));
            }
            return (host, fallback);
        }
    }
    if let Some((host, port)) = raw.rsplit_once(':') {
        if !port.contains('/') && port.parse::<u16>().is_ok() && !host.is_empty() {
            return (host.to_string(), port.parse().unwrap_or(fallback));
        }
    }
    (raw.split('/').next().unwrap_or(raw).to_string(), fallback)
}

fn set(node: &mut Value, key: &str, value: Value) {
    node.as_object_mut().unwrap().insert(key.to_string(), value);
}

fn s(node: &Value, key: &str) -> String {
    node.get(key).and_then(|v| v.as_str()).unwrap_or("").to_string()
}

fn apply_stream(node: &mut Value, query: &HashMap<String, String>) {
    let network = query.get("type").or(query.get("net")).or(query.get("network")).cloned().unwrap_or_else(|| s(node, "network"));
    set(node, "network", json!(network));
    let security = query.get("security").or(query.get("tls")).cloned().unwrap_or_default();
    if security == "tls" || security == "reality" || security == "xtls" {
        let tls = if security == "reality" || query.get("pbk").map(|v| !v.is_empty()).unwrap_or(false) { "reality" } else { "tls" };
        set(node, "tls", json!(tls));
    } else if query.get("pbk").map(|v| !v.is_empty()).unwrap_or(false) {
        set(node, "tls", json!("reality"));
    } else if flag(query.get("tls").map(String::as_str).unwrap_or("")) || query.get("sni").map(|v| !v.is_empty()).unwrap_or(false) {
        if s(node, "tls") == "none" {
            set(node, "tls", json!("tls"));
        }
    }
    let pick = |keys: &[&str]| keys.iter().find_map(|k| query.get(*k).filter(|v| !v.is_empty()).cloned()).unwrap_or_default();
    if !pick(&["sni", "peer", "servername"]).is_empty() {
        set(node, "sni", json!(pick(&["sni", "peer", "servername"])));
    }
    if let Some(v) = query.get("fp").or(query.get("fingerprint")) {
        set(node, "fp", json!(v));
    }
    for (qk, nk) in [("alpn", "alpn"), ("host", "host"), ("path", "path"), ("flow", "flow"), ("encryption", "encryption"), ("pbk", "pbk"), ("sid", "sid"), ("spx", "spx")] {
        if let Some(v) = query.get(qk) {
            set(node, nk, json!(v));
        }
    }
    if let Some(v) = query.get("serviceName").or(query.get("service_name")) {
        set(node, "service_name", json!(v));
    }
    if let Some(v) = query.get("headerType") {
        set(node, "header_type", json!(v));
    }
    if let Some(v) = query.get("packetEncoding") {
        set(node, "packet_encoding", json!(v));
    }
    if let Some(v) = query.get("mode").filter(|v| !v.is_empty()) {
        set(node, "mode", json!(v));
    }
    if let Some(v) = query.get("extra").filter(|v| !v.is_empty()) {
        set(node, "xhttp_extra", json!(v));
    }
    if let Some(v) = query.get("x_padding").or(query.get("xPaddingBytes")).filter(|v| !v.is_empty()) {
        set(node, "x_padding", json!(v));
    }
    let insecure = query.get("allowInsecure").or(query.get("insecure")).or(query.get("allow_insecure")).map(|v| flag(v)).unwrap_or(false);
    if insecure {
        set(node, "insecure", json!(true));
    }
    if s(node, "tls") == "tls" && !s(node, "pbk").is_empty() {
        set(node, "tls", json!("reality"));
    }
    if let Some(v) = ["ech", "echConfigList", "ech-config"].iter().find_map(|k| query.get(*k).filter(|v| !v.is_empty())) {
        apply_ech(node, v);
    }
}

fn apply_ech(node: &mut Value, raw: &str) {
    let v = raw.trim();
    if matches!(v.to_ascii_lowercase().as_str(), "" | "0" | "false" | "off" | "no") {
        return;
    }
    set(node, "ech", json!(true));
    if flag(v) {
        return;
    }
    if let Some(idx) = v.find("://") {
        let head = &v[..idx];
        if let Some(cut) = head.rfind(|c| c == '+' || c == ' ') {
            set(node, "ech_query_server_name", json!(head[..cut].trim()));
            set(node, "ech_config", json!(v[cut + 1..].trim()));
        } else {
            set(node, "ech_config", json!(v));
        }
        return;
    }
    set(node, "ech_config", json!(v.replace(' ', "+")));
}

pub fn ech_link_value(node: &Value) -> String {
    if !node["ech"].as_bool().unwrap_or(false) {
        return String::new();
    }
    let config = s(node, "ech_config");
    let name = s(node, "ech_query_server_name");
    if config.is_empty() {
        return if name.is_empty() { "1".into() } else { format!("{name}+https://1.1.1.1/dns-query") };
    }
    if config.contains("://") && !name.is_empty() {
        return format!("{name}+{config}");
    }
    config
}

pub fn parse_link(link: &str) -> Result<Value, String> {
    let trimmed = link.trim();
    let (scheme, rest0) = trimmed.split_once("://").ok_or("not a link")?;
    let scheme = scheme.to_ascii_lowercase();
    let (rest, name) = match rest0.rfind('#') {
        Some(i) => (&rest0[..i], decode(&rest0[i + 1..])),
        None => (rest0, String::new()),
    };
    let mut node = match scheme.as_str() {
        "vmess" => parse_vmess(rest, &name)?,
        "vless" | "trojan" => parse_standard(&scheme, rest, &name)?,
        "ss" => parse_ss(rest, &name)?,
        "hysteria2" | "hy2" => parse_hy2(rest, &name)?,
        "hysteria" => parse_hysteria(rest, &name)?,
        "wireguard" | "wg" => parse_wg(rest, &name)?,
        "ssh" | "socks" | "socks5" | "http" | "https" => parse_userpass(&scheme, rest, &name)?,
        "dnstt" => parse_dnstt(rest, &name)?,
        "masterdns" => parse_master(rest, &name)?,
        "ping" => parse_ping(rest, &name)?,
        "ssr" => parse_ssr(rest, &name)?,
        "dnst" => parse_dnst(rest, &name)?,
        "chain" => parse_chain(rest, &name)?,
        "tuic" => parse_tuic(rest, &name)?,
        "anytls" => parse_anytls(rest, &name)?,
        "naive+https" | "naive+quic" | "naive" => parse_naive(&scheme, rest, &name)?,
        "vpn" => parse_amnezia_vpn(rest, &name)?,
        "warp" => parse_warp(rest0, &name)?,
        "v2box" | "v2open" => {
            let mut n = blank("subscription");
            let q = qs(rest.split_once('?').map(|p| p.1).unwrap_or(""));
            set(&mut n, "address", json!(q.get("url").cloned().unwrap_or_default()));
            set(&mut n, "remark", json!("subscription"));
            n
        }
        other => return Err(format!("unsupported {other}")),
    };
    set(&mut node, "link", json!(trimmed));
    if s(&node, "remark").is_empty() {
        let remark = if name.is_empty() { format!("{} {}", s(&node, "protocol"), s(&node, "address")) } else { name };
        set(&mut node, "remark", json!(remark));
    }
    Ok(node)
}

fn parse_vmess(rest: &str, name: &str) -> Result<Value, String> {
    let payload = b64_decode(rest.split('?').next().unwrap_or(rest)).ok_or("bad vmess")?;
    let obj: Value = serde_json::from_str(&payload).map_err(|e| e.to_string())?;
    let tls = obj["tls"].as_str().unwrap_or("");
    let mut node = blank("vmess");
    set(&mut node, "remark", json!(obj["ps"].as_str().unwrap_or(name)));
    set(&mut node, "address", json!(obj["add"].as_str().unwrap_or("")));
    let port = obj["port"].as_u64().or_else(|| obj["port"].as_str().and_then(|p| p.parse::<u64>().ok())).unwrap_or(443);
    set(&mut node, "port", json!(port));
    set(&mut node, "uuid", json!(obj["id"].as_str().unwrap_or("")));
    set(&mut node, "alter_id", json!(obj["aid"].as_str().and_then(|p| p.parse::<u64>().ok()).or(obj["aid"].as_u64()).unwrap_or(0)));
    set(&mut node, "method", json!(obj["scy"].as_str().unwrap_or("auto")));
    set(&mut node, "network", json!(obj["net"].as_str().unwrap_or("tcp")));
    set(&mut node, "header_type", json!(obj["type"].as_str().unwrap_or("none")));
    set(&mut node, "host", json!(obj["host"].as_str().unwrap_or("")));
    set(&mut node, "path", json!(obj["path"].as_str().unwrap_or("")));
    set(&mut node, "tls", json!(if !tls.is_empty() && tls != "none" { "tls" } else { "none" }));
    set(&mut node, "sni", json!(obj["sni"].as_str().unwrap_or("")));
    set(&mut node, "fp", json!(obj["fp"].as_str().unwrap_or("")));
    set(&mut node, "alpn", json!(obj["alpn"].as_str().unwrap_or("")));
    if flag(obj["insecure"].as_str().unwrap_or("")) {
        set(&mut node, "insecure", json!(true));
    }
    if let Some(q) = rest.split_once('?').map(|p| p.1) {
        apply_stream(&mut node, &qs(q));
    }
    Ok(node)
}

fn parse_standard(scheme: &str, rest: &str, name: &str) -> Result<Value, String> {
    let (info, after) = rest.split_once('@').ok_or("bad link")?;
    let (hostport, query) = after.split_once('?').unwrap_or((after, ""));
    let (host, port) = split_host_port(hostport, 443);
    let mut node = blank(if scheme == "vless" { "vless" } else { "trojan" });
    set(&mut node, "remark", json!(name));
    set(&mut node, "address", json!(host));
    set(&mut node, "port", json!(port));
    if scheme == "vless" {
        set(&mut node, "uuid", json!(decode(info)));
    } else {
        set(&mut node, "password", json!(decode(info)));
    }
    apply_stream(&mut node, &qs(query));
    Ok(node)
}

fn parse_ss(rest: &str, name: &str) -> Result<Value, String> {
    let (body, query) = rest.split_once('?').map(|(a, b)| (a, qs(b))).unwrap_or((rest, HashMap::new()));
    let (method, password, host, port) = if let Some((user, hostport)) = body.rsplit_once('@') {
        let decoded = b64_decode(&decode(user));
        let creds = decoded.filter(|d| d.contains(':')).unwrap_or_else(|| decode(user));
        let (method, password) = creds.split_once(':').ok_or("bad shadowsocks")?;
        let (host, port) = split_host_port(hostport, 8388);
        (method.to_string(), password.to_string(), host, port)
    } else {
        let decoded = b64_decode(body).ok_or("bad shadowsocks")?;
        let (creds, hostport) = decoded.rsplit_once('@').ok_or("bad shadowsocks")?;
        let (method, password) = creds.split_once(':').ok_or("bad shadowsocks")?;
        let (host, port) = split_host_port(hostport, 8388);
        (method.to_string(), password.to_string(), host, port)
    };
    let mut node = blank("shadowsocks");
    set(&mut node, "remark", json!(name));
    set(&mut node, "address", json!(host));
    set(&mut node, "port", json!(port));
    set(&mut node, "method", json!(method));
    set(&mut node, "password", json!(password));
    set(&mut node, "tls", json!("none"));
    if !query.is_empty() {
        apply_stream(&mut node, &query);
        set(&mut node, "tls", json!("none"));
        if let Some(plugin) = query.get("plugin").filter(|v| !v.is_empty()) {
            apply_ss_plugin(&mut node, plugin);
        }
    }
    Ok(node)
}

pub fn apply_ss_plugin(node: &mut Value, plugin: &str) {
    let mut parts = plugin.split(';').map(str::trim);
    let name = parts.next().unwrap_or("").to_ascii_lowercase();
    let opts: Vec<&str> = parts.filter(|p| !p.is_empty()).collect();
    match name.as_str() {
        "shadow-tls" | "shadowtls" => {
            set(node, "shadowtls_version", json!("3"));
            for opt in &opts {
                let (k, v) = opt.split_once('=').unwrap_or((opt, ""));
                match k.trim() {
                    "host" | "sni" => set(node, "shadowtls_sni", json!(v.trim())),
                    "password" | "passwd" => set(node, "shadowtls_password", json!(v.trim())),
                    "version" | "v" => set(node, "shadowtls_version", json!(v.trim())),
                    "fp" | "fingerprint" => set(node, "fp", json!(v.trim())),
                    _ => {}
                }
            }
        }
        "obfs-local" | "simple-obfs" | "obfs" => {
            set(node, "plugin", json!("obfs-local"));
            set(node, "plugin_opts", json!(opts.join(";")));
        }
        "v2ray-plugin" => {
            set(node, "plugin", json!("v2ray-plugin"));
            set(node, "plugin_opts", json!(opts.join(";")));
        }
        _ => {}
    }
}

fn userinfo_parts(rest: &str) -> (String, String, HashMap<String, String>) {
    let (main, query) = rest.split_once('?').unwrap_or((rest, ""));
    let (info, hostport) = main.rsplit_once('@').unwrap_or(("", main));
    (decode(info), hostport.trim_end_matches('/').to_string(), qs(query))
}

fn tls_query(node: &mut Value, q: &HashMap<String, String>) {
    set(node, "tls", json!("tls"));
    let pick = |keys: &[&str]| keys.iter().find_map(|k| q.get(*k).filter(|v| !v.is_empty()).cloned()).unwrap_or_default();
    set(node, "sni", json!(pick(&["sni", "peer", "servername"])));
    set(node, "alpn", json!(pick(&["alpn"])));
    set(node, "fp", json!(pick(&["fp", "fingerprint"])));
    let insecure = ["insecure", "allow_insecure", "allowInsecure", "skip-cert-verify"].iter().any(|k| flag(q.get(*k).map(String::as_str).unwrap_or("")));
    set(node, "insecure", json!(insecure));
    if let Some(v) = ["ech", "echConfigList", "ech-config"].iter().find_map(|k| q.get(*k).filter(|v| !v.is_empty())) {
        apply_ech(node, v);
    }
}

fn parse_tuic(rest: &str, name: &str) -> Result<Value, String> {
    let (info, hostport, q) = userinfo_parts(rest);
    let (uuid, password) = info.split_once(':').map(|(a, b)| (a.to_string(), b.to_string())).unwrap_or((info.clone(), String::new()));
    let (host, port) = split_host_port(&hostport, 443);
    let mut node = blank("tuic");
    set(&mut node, "remark", json!(name));
    set(&mut node, "address", json!(host));
    set(&mut node, "port", json!(port));
    set(&mut node, "uuid", json!(uuid));
    set(&mut node, "password", json!(if password.is_empty() { q.get("password").cloned().unwrap_or_default() } else { password }));
    tls_query(&mut node, &q);
    let pick = |keys: &[&str]| keys.iter().find_map(|k| q.get(*k).filter(|v| !v.is_empty()).cloned()).unwrap_or_default();
    set(&mut node, "congestion_control", json!(pick(&["congestion_control", "congestion_controller", "congestion"])));
    set(&mut node, "udp_relay_mode", json!(pick(&["udp_relay_mode", "udp-relay-mode"])));
    set(&mut node, "zero_rtt", json!(flag(&pick(&["reduce_rtt", "zero_rtt_handshake", "zero_rtt"]))));
    set(&mut node, "disable_sni", json!(flag(&pick(&["disable_sni", "disable-sni"]))));
    set(&mut node, "heartbeat", json!(pick(&["heartbeat", "heartbeat_interval"])));
    Ok(node)
}

fn parse_anytls(rest: &str, name: &str) -> Result<Value, String> {
    let (info, hostport, q) = userinfo_parts(rest);
    let (host, port) = split_host_port(&hostport, 443);
    let mut node = blank("anytls");
    set(&mut node, "remark", json!(name));
    set(&mut node, "address", json!(host));
    set(&mut node, "port", json!(port));
    set(&mut node, "password", json!(info));
    tls_query(&mut node, &q);
    for (qk, nk) in [("idle_session_check_interval", "idle_session_check_interval"), ("idle_session_timeout", "idle_session_timeout"), ("min_idle_session", "min_idle_session")] {
        if let Some(v) = q.get(qk).filter(|v| !v.is_empty()) {
            set(&mut node, nk, json!(v));
        }
    }
    Ok(node)
}

fn parse_naive(scheme: &str, rest: &str, name: &str) -> Result<Value, String> {
    let (info, hostport, q) = userinfo_parts(rest);
    let (user, password) = info.split_once(':').map(|(a, b)| (a.to_string(), b.to_string())).unwrap_or((info.clone(), String::new()));
    let (host, port) = split_host_port(&hostport, 443);
    let mut node = blank("naive");
    set(&mut node, "remark", json!(name));
    set(&mut node, "address", json!(host.clone()));
    set(&mut node, "port", json!(port));
    set(&mut node, "username", json!(user));
    set(&mut node, "password", json!(password));
    tls_query(&mut node, &q);
    if s(&node, "sni").is_empty() {
        set(&mut node, "sni", json!(host));
    }
    set(&mut node, "naive_quic", json!(scheme == "naive+quic" || flag(q.get("quic").map(String::as_str).unwrap_or(""))));
    if let Some(v) = q.get("insecure-concurrency").or(q.get("insecure_concurrency")).filter(|v| !v.is_empty()) {
        set(&mut node, "insecure_concurrency", json!(v));
    }
    if let Some(v) = q.get("extra-headers").or(q.get("extra_headers")).filter(|v| !v.is_empty()) {
        set(&mut node, "extra_headers", json!(v));
    }
    Ok(node)
}

pub fn parse_wg_conf(text: &str, name: &str) -> Option<Value> {
    if !text.contains("[Interface]") {
        return None;
    }
    let mut node = blank("wireguard");
    set(&mut node, "remark", json!(name));
    let mut section = String::new();
    let mut addresses = Vec::new();
    for raw in text.lines() {
        let line = raw.split('#').next().unwrap_or("").trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('[') {
            section = line.trim_matches(|c| c == '[' || c == ']').to_ascii_lowercase();
            continue;
        }
        let Some((k, v)) = line.split_once('=') else { continue };
        let key = k.trim().to_ascii_lowercase();
        let value = v.trim().to_string();
        match (section.as_str(), key.as_str()) {
            ("interface", "privatekey") => set(&mut node, "private_key", json!(value)),
            ("interface", "address") => addresses.extend(value.split(',').map(|a| a.trim().to_string()).filter(|a| !a.is_empty())),
            ("interface", "mtu") => set(&mut node, "mtu", json!(value.parse::<u64>().unwrap_or(0))),
            ("interface", "dns") => set(&mut node, "dns_server", json!(value)),
            ("interface", k) if AWG_KEYS.contains(&k) => set(&mut node, &format!("awg_{k}"), json!(value)),
            ("peer", "publickey") => set(&mut node, "peer_public_key", json!(value)),
            ("peer", "presharedkey") => set(&mut node, "preshared_key", json!(value)),
            ("peer", "allowedips") => set(&mut node, "allowed_ips", json!(value)),
            ("peer", "persistentkeepalive") => set(&mut node, "keepalive", json!(value)),
            ("peer", "reserved") => set(&mut node, "reserved", json!(value)),
            ("peer", "endpoint") => {
                let (host, port) = split_host_port(&value, 51820);
                set(&mut node, "address", json!(host));
                set(&mut node, "port", json!(port));
            }
            _ => {}
        }
    }
    set(&mut node, "local_address", json!(addresses.join(",")));
    if s(&node, "private_key").is_empty() || s(&node, "peer_public_key").is_empty() {
        return None;
    }
    if s(&node, "remark").is_empty() {
        let kind = if is_amnezia(&node) { "AmneziaWG" } else { "WireGuard" };
        let remark = format!("{kind} {}", s(&node, "address"));
        set(&mut node, "remark", json!(remark));
    }
    Some(node)
}

fn parse_amnezia_vpn(rest: &str, name: &str) -> Result<Value, String> {
    let compact: String = rest.chars().filter(|c| !c.is_whitespace()).collect();
    let mut raw = compact.replace('-', "+").replace('_', "/");
    raw.push_str(&"=".repeat((4 - raw.len() % 4) % 4));
    let bytes = base64_decode(&raw).ok_or("bad amnezia link")?;
    let text = if bytes.first() == Some(&b'{') {
        String::from_utf8(bytes).map_err(|e| e.to_string())?
    } else {
        let body = if bytes.len() > 4 { &bytes[4..] } else { &bytes[..] };
        let inflated = miniz_oxide::inflate::decompress_to_vec_zlib(body).map_err(|_| "bad amnezia link".to_string())?;
        String::from_utf8(inflated).map_err(|e| e.to_string())?
    };
    let doc: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let title = doc["description"].as_str().filter(|v| !v.is_empty()).unwrap_or(name).to_string();
    let host = doc["hostName"].as_str().unwrap_or("").to_string();
    let dns = [doc["dns1"].as_str().unwrap_or(""), doc["dns2"].as_str().unwrap_or("")].into_iter().filter(|v| !v.is_empty()).collect::<Vec<_>>().join(",");
    let default = doc["defaultContainer"].as_str().unwrap_or("");
    let mut containers = doc["containers"].as_array().cloned().unwrap_or_default();
    containers.sort_by_key(|c| c["container"].as_str() != Some(default));
    for container in containers {
        let Some(obj) = container.as_object() else { continue };
        for (key, inner) in obj {
            if key == "container" {
                continue;
            }
            let Some(last) = inner["last_config"].as_str() else { continue };
            let Ok(cfg) = serde_json::from_str::<Value>(last) else { continue };
            if let Some(conf) = cfg["config"].as_str() {
                let conf = conf
                    .replace("$PRIMARY_DNS", doc["dns1"].as_str().unwrap_or("1.1.1.1"))
                    .replace("$SECONDARY_DNS", doc["dns2"].as_str().unwrap_or("1.0.0.1"));
                if let Some(mut node) = parse_wg_conf(&conf, &title) {
                    if s(&node, "address").is_empty() || s(&node, "address").starts_with('$') {
                        set(&mut node, "address", json!(cfg["hostName"].as_str().unwrap_or(&host)));
                        let port = cfg["port"].as_u64().or_else(|| cfg["port"].as_str().and_then(|p| p.parse().ok())).unwrap_or(51820);
                        set(&mut node, "port", json!(port));
                    }
                    if s(&node, "dns_server").contains('$') || s(&node, "dns_server").is_empty() {
                        set(&mut node, "dns_server", json!(dns));
                    }
                    return Ok(node);
                }
            }
            let found = from_json(&cfg);
            if let Some(mut node) = found.into_iter().next() {
                if !title.is_empty() {
                    set(&mut node, "remark", json!(title));
                }
                return Ok(node);
            }
        }
    }
    Err("this Amnezia link has no supported container".into())
}

fn parse_warp(rest0: &str, name: &str) -> Result<Value, String> {
    let wow = rest0.contains("&&detour=") || rest0.contains("&&detour%3D");
    let head = rest0.split("&&").next().unwrap_or(rest0);
    let head = head.split('#').next().unwrap_or(head);
    let (info, after) = head.rsplit_once('@').unwrap_or(("", head));
    let (hostport, query) = after.split_once('?').unwrap_or((after, ""));
    let q = qs(query);
    let mut node = blank("warp");
    set(&mut node, "remark", json!(if name.is_empty() { "WARP" } else { name }));
    let hostport = hostport.trim_end_matches('/');
    let (host, port) = if hostport.is_empty() || hostport.eq_ignore_ascii_case("auto") { (String::new(), 0) } else { split_host_port(hostport, 2408) };
    set(&mut node, "address", json!(host));
    set(&mut node, "port", json!(port));
    let license = decode(info);
    if license.contains('-') && license.len() >= 20 {
        set(&mut node, "license", json!(license));
    }
    set(&mut node, "warp_wow", json!(wow || flag(q.get("wow").map(String::as_str).unwrap_or(""))));
    if let Some(count) = q.get("ifp").filter(|v| !v.is_empty()) {
        let max = count.split('-').last().unwrap_or(count).trim();
        set(&mut node, "awg_jc", json!(max));
    }
    if let Some(size) = q.get("ifps").filter(|v| !v.is_empty()) {
        let (lo, hi) = size.split_once('-').unwrap_or((size, size));
        set(&mut node, "awg_jmin", json!(lo.trim()));
        set(&mut node, "awg_jmax", json!(hi.trim()));
    }
    for k in AWG_KEYS {
        if let Some(v) = q.get(k).filter(|v| !v.is_empty()) {
            set(&mut node, &format!("awg_{k}"), json!(v));
        }
    }
    Ok(node)
}

fn parse_hy2(rest: &str, name: &str) -> Result<Value, String> {
    let (info, after) = rest.split_once('@').unwrap_or(("", rest));
    let (hostport, query) = after.split_once('?').unwrap_or((after, ""));
    let (host, port) = split_host_port(hostport, 443);
    let q = qs(query);
    let mut parts = decode(info).splitn(2, ':').map(|s| s.to_string()).collect::<Vec<_>>();
    if parts.is_empty() {
        parts.push(String::new());
    }
    let mut node = blank("hysteria2");
    set(&mut node, "remark", json!(name));
    set(&mut node, "address", json!(host));
    set(&mut node, "port", json!(port));
    set(&mut node, "password", json!(parts.first().cloned().unwrap_or_default()));
    set(&mut node, "username", json!(parts.get(1).cloned().unwrap_or_default()));
    set(&mut node, "tls", json!("tls"));
    set(&mut node, "sni", json!(q.get("sni").cloned().unwrap_or_default()));
    set(&mut node, "insecure", json!(flag(q.get("insecure").map(String::as_str).unwrap_or(""))));
    set(&mut node, "obfs", json!(q.get("obfs").cloned().unwrap_or_default()));
    set(&mut node, "obfs_password", json!(q.get("obfs-password").or(q.get("obfsPassword")).cloned().unwrap_or_default()));
    set(&mut node, "pin_sha256", json!(q.get("pinSHA256").cloned().unwrap_or_default()));
    set(&mut node, "hop_port", json!(q.get("mport").cloned().unwrap_or_default()));
    for (qk, nk) in [("alpn", "alpn"), ("fp", "fp")] {
        if let Some(v) = q.get(qk).filter(|v| !v.is_empty()) {
            set(&mut node, nk, json!(v));
        }
    }
    if let Some(v) = q.get("ech").filter(|v| !v.is_empty()) {
        apply_ech(&mut node, v);
    }
    Ok(node)
}

fn parse_hysteria(rest: &str, name: &str) -> Result<Value, String> {
    let (hostport, query) = rest.split_once('?').unwrap_or((rest, ""));
    let (host, port) = split_host_port(hostport.split('@').last().unwrap_or(hostport), 443);
    let q = qs(query);
    let mut node = blank("hysteria");
    set(&mut node, "remark", json!(name));
    set(&mut node, "address", json!(host));
    set(&mut node, "port", json!(port));
    set(&mut node, "password", json!(q.get("auth").cloned().unwrap_or_default()));
    set(&mut node, "tls", json!("tls"));
    set(&mut node, "sni", json!(q.get("peer").or(q.get("sni")).cloned().unwrap_or_default()));
    set(&mut node, "insecure", json!(flag(q.get("insecure").map(String::as_str).unwrap_or(""))));
    set(&mut node, "up_mbps", json!(q.get("upmbps").and_then(|v| v.parse::<u64>().ok()).unwrap_or(0)));
    set(&mut node, "down_mbps", json!(q.get("downmbps").and_then(|v| v.parse::<u64>().ok()).unwrap_or(0)));
    Ok(node)
}

fn parse_wg(rest: &str, name: &str) -> Result<Value, String> {
    if !rest.contains('?') && !rest.contains('@') {
        if let Some(payload) = b64_decode(rest) {
            if payload.trim().starts_with('{') {
                let obj: Value = serde_json::from_str(&payload).map_err(|e| e.to_string())?;
                let mut node = blank("wireguard");
                set(&mut node, "remark", json!(obj["remarks"].as_str().or(obj["remark"].as_str()).unwrap_or(name)));
                set(&mut node, "address", json!(obj["server"].as_str().or(obj["address"].as_str()).unwrap_or("")));
                set(&mut node, "port", json!(obj["port"].as_u64().or(obj["server_port"].as_u64()).unwrap_or(51820)));
                set(&mut node, "private_key", json!(obj["private_key"].as_str().or(obj["privateKey"].as_str()).unwrap_or("")));
                set(&mut node, "peer_public_key", json!(obj["peer_public_key"].as_str().or(obj["public_key"].as_str()).unwrap_or("")));
                set(&mut node, "local_address", json!(obj["local_address"].as_str().or(obj["ip"].as_str()).unwrap_or("")));
                set(&mut node, "mtu", json!(obj["mtu"].as_u64().unwrap_or(0)));
                return Ok(node);
            }
        }
    }
    let (info, after) = rest.split_once('@').unwrap_or(("", rest));
    let (hostport, query) = after.split_once('?').unwrap_or((after, ""));
    let (host, port) = split_host_port(hostport, 51820);
    let q = qs(query);
    let mut node = blank("wireguard");
    set(&mut node, "remark", json!(name));
    set(&mut node, "address", json!(host));
    set(&mut node, "port", json!(port));
    set(&mut node, "private_key", json!(decode(info)));
    set(&mut node, "peer_public_key", json!(q.get("publickey").or(q.get("public_key")).cloned().unwrap_or_default()));
    set(&mut node, "preshared_key", json!(q.get("psk").cloned().unwrap_or_default()));
    set(&mut node, "local_address", json!(q.get("address").or(q.get("local_address")).cloned().unwrap_or_default()));
    set(&mut node, "mtu", json!(q.get("mtu").and_then(|v| v.parse::<u64>().ok()).unwrap_or(0)));
    set(&mut node, "reserved", json!(q.get("reserved").cloned().unwrap_or_default()));
    for (qk, nk) in [("keepalive", "keepalive"), ("allowedips", "allowed_ips"), ("allowed_ips", "allowed_ips")] {
        if let Some(v) = q.get(qk).filter(|v| !v.is_empty()) {
            set(&mut node, nk, json!(v));
        }
    }
    for k in AWG_KEYS {
        if let Some(v) = q.get(k).or(q.get(&k.to_ascii_uppercase())).or(q.get(&format!("awg_{k}"))).filter(|v| !v.is_empty()) {
            set(&mut node, &format!("awg_{k}"), json!(v));
        }
    }
    Ok(node)
}

fn parse_userpass(scheme: &str, rest: &str, name: &str) -> Result<Value, String> {
    let protocol = match scheme {
        "socks5" => "socks",
        "https" => "http",
        other => other,
    };
    let (user, hostpart) = if let Some((u, h)) = rest.split_once('@') { (u, h) } else { ("", rest) };
    let (hostport, query) = hostpart.split_once('?').unwrap_or((hostpart, ""));
    let default_port = if protocol == "ssh" { 22 } else if protocol == "socks" { 1080 } else { 80 };
    let (host, port) = split_host_port(hostport, default_port);
    let q = qs(query);
    let (username, password) = user.split_once(':').map(|(a, b)| (decode(a), decode(b))).unwrap_or((decode(user), String::new()));
    let mut node = blank(protocol);
    set(&mut node, "remark", json!(name));
    set(&mut node, "address", json!(host));
    set(&mut node, "port", json!(port));
    set(&mut node, "username", json!(username));
    set(&mut node, "password", json!(password));
    if let Some(pk) = q.get("pk").and_then(|v| b64_decode(v)) {
        set(&mut node, "private_key", json!(pk));
    }
    set(&mut node, "tls", json!(if scheme == "https" || flag(q.get("tls").map(String::as_str).unwrap_or("")) { "tls" } else { "none" }));
    set(&mut node, "sni", json!(q.get("sni").cloned().unwrap_or_default()));
    Ok(node)
}

fn parse_dnstt(rest: &str, name: &str) -> Result<Value, String> {
    let (info, after) = rest.split_once('@').unwrap_or(("", rest));
    let (hostport, query) = after.split_once('?').unwrap_or((after, ""));
    let (host, port) = split_host_port(hostport, 53);
    let q = qs(query);
    let mut node = blank("dnstt");
    set(&mut node, "remark", json!(if name.is_empty() { "DNSTT" } else { name }));
    set(&mut node, "address", json!(host.clone()));
    set(&mut node, "domain", json!(host));
    set(&mut node, "port", json!(port));
    set(&mut node, "pubkey", json!(decode(info)));
    set(&mut node, "dns_server", json!(q.get("dns").cloned().unwrap_or_default()));
    Ok(node)
}

fn parse_master(rest: &str, name: &str) -> Result<Value, String> {
    let (info, after) = rest.split_once('@').unwrap_or(("", rest));
    let (host, port) = split_host_port(after.split('?').next().unwrap_or(after), 53);
    let mut node = blank("masterdns");
    set(&mut node, "remark", json!(if name.is_empty() { "MasterDNS" } else { name }));
    set(&mut node, "address", json!(host.clone()));
    set(&mut node, "domain", json!(host));
    set(&mut node, "port", json!(port));
    set(&mut node, "key", json!(decode(info)));
    set(&mut node, "encryption_method", json!("1"));
    Ok(node)
}

fn parse_ping(rest: &str, name: &str) -> Result<Value, String> {
    let (hostport, query) = rest.split_once('?').unwrap_or((rest, ""));
    let (host, port) = if hostport.contains(':') { split_host_port(hostport, 0) } else { (hostport.to_string(), 0) };
    let q = qs(query);
    let mut node = blank("ping");
    set(&mut node, "remark", json!(if name.is_empty() { host.as_str() } else { name }));
    set(&mut node, "address", json!(host));
    set(&mut node, "port", json!(port));
    let secret = q.get("password").or(q.get("key")).cloned().unwrap_or_default();
    set(&mut node, "password", json!(secret));
    Ok(node)
}

fn parse_ssr(rest: &str, name: &str) -> Result<Value, String> {
    let decoded = if rest.contains(':') { decode(rest) } else { b64_decode(rest).ok_or("bad ssr")? };
    let (main, query) = decoded.split_once("/?").or_else(|| decoded.split_once('?')).unwrap_or((decoded.as_str(), ""));
    let parts: Vec<&str> = main.splitn(6, ':').collect();
    if parts.len() < 6 {
        return Err("bad ssr".into());
    }
    let password = b64_decode(parts[5]).unwrap_or_else(|| decode(parts[5]));
    let q = qs(query);
    let mut node = blank("shadowsocksr");
    set(&mut node, "remark", json!(b64_decode(q.get("remarks").map(String::as_str).unwrap_or("")).unwrap_or(name.to_string())));
    set(&mut node, "address", json!(parts[0]));
    set(&mut node, "port", json!(parts[1].parse::<u64>().unwrap_or(0)));
    set(&mut node, "ssr_protocol", json!(parts[2]));
    set(&mut node, "method", json!(parts[3]));
    set(&mut node, "obfs", json!(parts[4]));
    set(&mut node, "password", json!(password));
    set(&mut node, "obfs_password", json!(b64_decode(q.get("obfsparam").map(String::as_str).unwrap_or("")).unwrap_or_default()));
    set(&mut node, "host", json!(b64_decode(q.get("obfsparam").map(String::as_str).unwrap_or("")).unwrap_or_default()));
    set(&mut node, "protocol_param", json!(b64_decode(q.get("protoparam").map(String::as_str).unwrap_or("")).unwrap_or_default()));
    if s(&node, "remark").is_empty() && !name.is_empty() {
        set(&mut node, "remark", json!(name));
    }
    Ok(node)
}

fn parse_dnst(rest: &str, name: &str) -> Result<Value, String> {
    let (path, query) = rest.split_once('?').unwrap_or((rest, ""));
    let mut parts = path.split('/');
    let domain = parts.next().unwrap_or("").to_string();
    let transport = parts.next().unwrap_or("");
    let q = qs(query);
    match transport {
        "masterdns" => {
            let mut node = blank("masterdns");
            set(&mut node, "remark", json!(if name.is_empty() { "MasterDNS" } else { name }));
            set(&mut node, "address", json!(domain.clone()));
            set(&mut node, "domain", json!(domain));
            set(&mut node, "port", json!(53));
            set(&mut node, "key", json!(q.get("mkey").cloned().unwrap_or_default()));
            set(&mut node, "encryption_method", json!(q.get("encryption").cloned().unwrap_or_else(|| "1".into())));
            set(&mut node, "dns_server", json!(q.get("dns").cloned().unwrap_or_default()));
            Ok(node)
        }
        "dnstt" => {
            let mut node = blank("dnstt");
            set(&mut node, "remark", json!(if name.is_empty() { "DNSTT" } else { name }));
            set(&mut node, "address", json!(domain.clone()));
            set(&mut node, "domain", json!(domain));
            set(&mut node, "port", json!(53));
            set(&mut node, "pubkey", json!(q.get("pubkey").or(q.get("publickey")).cloned().unwrap_or_default()));
            set(&mut node, "dns_server", json!(q.get("dns").cloned().unwrap_or_default()));
            Ok(node)
        }
        _ => Err("unsupported dnst transport".into()),
    }
}

fn parse_chain(rest: &str, name: &str) -> Result<Value, String> {
    let payload = b64_decode(rest).unwrap_or_else(|| decode(rest));
    let mut hops = Vec::new();
    let mut remark = name.to_string();
    if payload.trim().starts_with('{') || payload.trim().starts_with('[') {
        if let Ok(obj) = serde_json::from_str::<Value>(&payload) {
            if remark.is_empty() {
                remark = obj["remarks"].as_str().or(obj["remark"].as_str()).unwrap_or("").to_string();
            }
            let links = obj.get("outbounds").or(obj.get("links")).cloned().unwrap_or(obj);
            if let Some(arr) = links.as_array() {
                for item in arr {
                    if let Some(link) = item.as_str() {
                        if link.contains("://") {
                            if let Ok(n) = parse_link(link) {
                                hops.push(n);
                            }
                        }
                    }
                }
            }
        }
    }
    let mut node = blank("chain");
    set(&mut node, "remark", json!(if remark.is_empty() { "Chain" } else { remark.as_str() }));
    set(&mut node, "chain", Value::Array(hops.clone()));
    if let Some(first) = hops.first() {
        set(&mut node, "address", json!(s(first, "address")));
        set(&mut node, "port", json!(first["port"].as_u64().unwrap_or(0)));
    }
    Ok(node)
}

pub fn parse_text(text: &str) -> Vec<Value> {
    if crate::npv::is_npv_text(text) {
        return crate::npv::nodes_from_text(text);
    }
    parse_text_inner(text)
}

pub(crate) fn parse_text_inner(text: &str) -> Vec<Value> {
    let mut body = text.trim().to_string();
    if body.is_empty() {
        return Vec::new();
    }
    if let Some(node) = parse_wg_conf(&body, "") {
        return vec![node];
    }
    let clash = parse_clash_yaml(&body);
    if !clash.is_empty() {
        return clash;
    }
    let compact: String = body.chars().filter(|c| !c.is_whitespace()).collect();
    if !body.contains("://") && !body.trim_start().starts_with('{') && !body.trim_start().starts_with('[') {
        if let Some(decoded) = b64_decode(&compact) {
            if decoded.contains("://") || decoded.trim_start().starts_with('{') || decoded.trim_start().starts_with('[') {
                body = decoded;
            }
        }
    }
    let stripped = body.trim_start();
    if stripped.starts_with('{') || stripped.starts_with('[') {
        if let Ok(obj) = serde_json::from_str::<Value>(&body) {
            let found = from_json(&obj);
            if !found.is_empty() {
                return found;
            }
        }
    }
    let mut links = Vec::new();
    for line in body.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with("//") {
            continue;
        }
        if let Some(idx) = line.find("://") {
            let start = line[..idx].rfind(|c: char| !c.is_ascii_alphanumeric() && c != '+' && c != '-' && c != '.').map(|i| i + 1).unwrap_or(0);
            let uri = line[start..].split_whitespace().next().unwrap_or("");
            if let Ok(node) = parse_link(uri) {
                links.push(node);
                continue;
            }
        }
        if let Some(decoded) = b64_decode(line) {
            if decoded.contains("://") {
                links.extend(parse_text(&decoded));
            }
        }
    }
    links
}

fn from_json(obj: &Value) -> Vec<Value> {
    if let Some(arr) = obj.as_array() {
        if arr.first().and_then(|v| v.as_str()).is_some() {
            return parse_text(&arr.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>().join("\n"));
        }
        return arr.iter().flat_map(from_json).collect();
    }
    let Some(map) = obj.as_object() else { return Vec::new() };
    if map.get("outbounds").and_then(|v| v.as_array()).is_some() || map.get("endpoints").and_then(|v| v.as_array()).is_some() {
        let outbounds = map.get("outbounds").and_then(|v| v.as_array()).cloned().unwrap_or_default();
        let shadowtls: HashMap<String, Value> = outbounds
            .iter()
            .filter(|o| o["type"].as_str() == Some("shadowtls"))
            .filter_map(|o| o["tag"].as_str().map(|t| (t.to_string(), o.clone())))
            .collect();
        let mut found = Vec::new();
        for outbound in outbounds.iter().chain(map.get("endpoints").and_then(|v| v.as_array()).into_iter().flatten()) {
            let kind = outbound["type"].as_str().or(outbound["protocol"].as_str()).unwrap_or("");
            if matches!(kind, "direct" | "block" | "blackhole" | "freedom" | "dns" | "selector" | "urltest" | "loopback" | "shadowtls") {
                continue;
            }
            let mut node = from_outbound(outbound);
            if kind == "shadowsocks" {
                if let Some(stls) = outbound["detour"].as_str().and_then(|t| shadowtls.get(t)) {
                    set(&mut node, "address", json!(stls["server"].as_str().unwrap_or("")));
                    set(&mut node, "port", json!(stls["server_port"].as_u64().unwrap_or(443)));
                    set(&mut node, "shadowtls_version", json!(stls["version"].as_u64().unwrap_or(3).to_string()));
                    set(&mut node, "shadowtls_password", json!(stls["password"].as_str().unwrap_or("")));
                    set(&mut node, "shadowtls_sni", json!(stls["tls"]["server_name"].as_str().unwrap_or("")));
                    set(&mut node, "fp", json!(stls["tls"]["utls"]["fingerprint"].as_str().unwrap_or("")));
                }
            }
            found.push(node);
        }
        return found.into_iter().filter(|n| !s(n, "address").is_empty() || s(n, "protocol") == "warp").collect();
    }
    if map.contains_key("type") || map.contains_key("protocol") {
        return vec![from_outbound(obj)];
    }
    Vec::new()
}

fn from_outbound(outbound: &Value) -> Value {
    let protocol = outbound["protocol"].as_str().or(outbound["type"].as_str()).unwrap_or("custom");
    if outbound.get("streamSettings").is_some() || (outbound.get("settings").is_some() && outbound.get("protocol").is_some()) {
        return from_xray(outbound);
    }
    let mut node = blank(if protocol == "shadowsocks" { "shadowsocks" } else { protocol });
    set(&mut node, "remark", json!(outbound["tag"].as_str().unwrap_or(protocol)));
    if protocol == "wireguard" || protocol == "warp" {
        return from_wireguard_json(outbound, node);
    }
    set(&mut node, "address", json!(outbound["server"].as_str().unwrap_or("")));
    set(&mut node, "port", json!(outbound["server_port"].as_u64().unwrap_or(443)));
    set(&mut node, "uuid", json!(outbound["uuid"].as_str().unwrap_or("")));
    set(&mut node, "password", json!(outbound["password"].as_str().or(outbound["auth_str"].as_str()).unwrap_or("")));
    set(&mut node, "method", json!(outbound["security"].as_str().or(outbound["method"].as_str()).unwrap_or("auto")));
    set(&mut node, "flow", json!(outbound["flow"].as_str().unwrap_or("")));
    set(&mut node, "username", json!(outbound["username"].as_str().or(outbound["user"].as_str()).unwrap_or("")));
    for key in ["congestion_control", "udp_relay_mode", "heartbeat", "idle_session_check_interval", "idle_session_timeout", "plugin", "plugin_opts"] {
        if let Some(v) = outbound[key].as_str() {
            set(&mut node, key, json!(v));
        }
    }
    if let Some(v) = outbound["min_idle_session"].as_u64() {
        set(&mut node, "min_idle_session", json!(v.to_string()));
    }
    if let Some(v) = outbound["zero_rtt_handshake"].as_bool() {
        set(&mut node, "zero_rtt", json!(v));
    }
    if protocol == "naive" {
        set(&mut node, "naive_quic", json!(outbound["quic"].as_bool().unwrap_or(false)));
        if let Some(v) = outbound["insecure_concurrency"].as_u64() {
            set(&mut node, "insecure_concurrency", json!(v.to_string()));
        }
    }
    if protocol == "hysteria2" {
        if let Some(obfs) = outbound.get("obfs") {
            set(&mut node, "obfs", json!(obfs["type"].as_str().unwrap_or("")));
            set(&mut node, "obfs_password", json!(obfs["password"].as_str().unwrap_or("")));
        }
        if let Some(ports) = outbound["server_ports"].as_array().and_then(|a| a.first()).and_then(|v| v.as_str()) {
            set(&mut node, "hop_port", json!(ports.replace(':', "-")));
        }
    }
    for key in ["up_mbps", "down_mbps"] {
        if let Some(v) = outbound[key].as_u64() {
            set(&mut node, key, json!(v));
        }
    }
    if let Some(tls) = outbound.get("tls") {
        if let Some(alpn) = tls["alpn"].as_array() {
            set(&mut node, "alpn", json!(alpn.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>().join(",")));
        }
        if tls["ech"]["enabled"].as_bool().unwrap_or(false) {
            set(&mut node, "ech", json!(true));
            let config = match &tls["ech"]["config"] {
                Value::Array(lines) => lines.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>().join("\n"),
                Value::String(text) => text.clone(),
                _ => String::new(),
            };
            set(&mut node, "ech_config", json!(pem_to_b64(&config)));
            set(&mut node, "ech_query_server_name", json!(tls["ech"]["query_server_name"].as_str().unwrap_or("")));
        }
        let reality = tls.get("reality");
        let mode = if reality.and_then(|r| r.get("enabled")).and_then(|v| v.as_bool()).unwrap_or(false) {
            "reality"
        } else if tls.get("enabled").and_then(|v| v.as_bool()).unwrap_or(false) {
            "tls"
        } else {
            "none"
        };
        set(&mut node, "tls", json!(mode));
        set(&mut node, "sni", json!(tls["server_name"].as_str().unwrap_or("")));
        set(&mut node, "insecure", json!(tls["insecure"].as_bool().unwrap_or(false)));
        set(&mut node, "fp", json!(tls["utls"]["fingerprint"].as_str().unwrap_or("")));
        if let Some(reality) = reality {
            set(&mut node, "pbk", json!(reality["public_key"].as_str().unwrap_or("")));
            set(&mut node, "sid", json!(reality["short_id"].as_str().unwrap_or("")));
        }
    }
    if let Some(transport) = outbound.get("transport") {
        set(&mut node, "network", json!(transport["type"].as_str().unwrap_or("tcp")));
        set(&mut node, "path", json!(transport["path"].as_str().unwrap_or("")));
        let host = transport["host"].as_str()
            .or(transport["headers"]["Host"].as_str())
            .or(transport["host"].as_array().and_then(|a| a.first()).and_then(|v| v.as_str()))
            .unwrap_or("");
        set(&mut node, "host", json!(host));
        set(&mut node, "service_name", json!(transport["service_name"].as_str().unwrap_or("")));
        if let Some(mode) = transport["mode"].as_str() {
            set(&mut node, "mode", json!(mode));
        }
    }
    node
}

fn from_wireguard_json(outbound: &Value, mut node: Value) -> Value {
    let protocol = s(&node, "protocol");
    let list = |v: &Value| match v {
        Value::Array(items) => items.iter().filter_map(|x| x.as_str()).collect::<Vec<_>>().join(","),
        Value::String(text) => text.clone(),
        _ => String::new(),
    };
    let peer = outbound["peers"].as_array().and_then(|p| p.first()).cloned().unwrap_or(json!({}));
    let address = peer["address"].as_str().or(outbound["server"].as_str()).unwrap_or("");
    let port = peer["port"].as_u64().or(outbound["server_port"].as_u64()).unwrap_or(if protocol == "warp" { 0 } else { 51820 });
    set(&mut node, "address", json!(address));
    set(&mut node, "port", json!(port));
    set(&mut node, "private_key", json!(outbound["private_key"].as_str().or(outbound["profile"]["private_key"].as_str()).unwrap_or("")));
    set(&mut node, "peer_public_key", json!(peer["public_key"].as_str().or(outbound["peer_public_key"].as_str()).unwrap_or("")));
    set(&mut node, "preshared_key", json!(peer["pre_shared_key"].as_str().or(outbound["pre_shared_key"].as_str()).unwrap_or("")));
    let local = list(&outbound["address"]);
    set(&mut node, "local_address", json!(if local.is_empty() { list(&outbound["local_address"]) } else { local }));
    let reserved = match peer.get("reserved").or(outbound.get("reserved")) {
        Some(Value::Array(items)) => items.iter().filter_map(|v| v.as_u64()).map(|v| v.to_string()).collect::<Vec<_>>().join(","),
        Some(Value::String(text)) => text.clone(),
        _ => String::new(),
    };
    set(&mut node, "reserved", json!(reserved));
    if let Some(ips) = peer.get("allowed_ips") {
        set(&mut node, "allowed_ips", json!(list(ips)));
    }
    if let Some(mtu) = outbound["mtu"].as_u64() {
        set(&mut node, "mtu", json!(mtu));
    }
    if let Some(amnezia) = outbound["amnezia"].as_object() {
        for k in AWG_KEYS {
            match amnezia.get(k) {
                Some(Value::Number(n)) => set(&mut node, &format!("awg_{k}"), json!(n.to_string())),
                Some(Value::String(v)) if !v.is_empty() => set(&mut node, &format!("awg_{k}"), json!(v)),
                _ => {}
            }
        }
    }
    if protocol == "warp" {
        set(&mut node, "license", json!(outbound["profile"]["license_key"].as_str().unwrap_or("")));
    }
    node
}

pub fn pem_to_b64(raw: &str) -> String {
    raw.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with("-----"))
        .collect::<Vec<_>>()
        .join("")
}

fn from_xray(outbound: &Value) -> Value {
    let protocol = outbound["protocol"].as_str().unwrap_or("custom");
    let settings = &outbound["settings"];
    let stream = &outbound["streamSettings"];
    let mut node = blank(if protocol == "shadowsocks" { "shadowsocks" } else { protocol });
    set(&mut node, "remark", json!(outbound["tag"].as_str().unwrap_or(protocol)));
    set(&mut node, "network", json!(stream["network"].as_str().unwrap_or("tcp")));
    let security = stream["security"].as_str().unwrap_or("none");
    set(&mut node, "tls", json!(if security == "tls" || security == "reality" { security } else { "none" }));
    if protocol == "vmess" || protocol == "vless" {
        let vnext = &settings["vnext"][0];
        let user = &vnext["users"][0];
        set(&mut node, "address", json!(vnext["address"].as_str().unwrap_or("")));
        set(&mut node, "port", json!(vnext["port"].as_u64().unwrap_or(443)));
        set(&mut node, "uuid", json!(user["id"].as_str().unwrap_or("")));
        set(&mut node, "alter_id", json!(user["alterId"].as_u64().unwrap_or(0)));
        set(&mut node, "method", json!(user["security"].as_str().unwrap_or("auto")));
        set(&mut node, "flow", json!(user["flow"].as_str().unwrap_or("")));
        set(&mut node, "encryption", json!(user["encryption"].as_str().unwrap_or("none")));
    } else {
        let server = &settings["servers"][0];
        set(&mut node, "address", json!(server["address"].as_str().unwrap_or("")));
        set(&mut node, "port", json!(server["port"].as_u64().unwrap_or(443)));
        set(&mut node, "password", json!(server["password"].as_str().unwrap_or("")));
        set(&mut node, "method", json!(server["method"].as_str().unwrap_or("")));
    }
    set(&mut node, "sni", json!(stream["tlsSettings"]["serverName"].as_str().or(stream["realitySettings"]["serverName"].as_str()).unwrap_or("")));
    set(&mut node, "fp", json!(stream["tlsSettings"]["fingerprint"].as_str().or(stream["realitySettings"]["fingerprint"].as_str()).unwrap_or("")));
    set(&mut node, "pbk", json!(stream["realitySettings"]["publicKey"].as_str().unwrap_or("")));
    set(&mut node, "sid", json!(stream["realitySettings"]["shortId"].as_str().unwrap_or("")));
    set(&mut node, "path", json!(stream["wsSettings"]["path"].as_str().unwrap_or("")));
    set(&mut node, "host", json!(stream["wsSettings"]["headers"]["Host"].as_str().unwrap_or("")));
    set(&mut node, "service_name", json!(stream["grpcSettings"]["serviceName"].as_str().unwrap_or("")));
    if let Some(ech) = stream["tlsSettings"]["echConfigList"].as_str().filter(|v| !v.is_empty()) {
        apply_ech(&mut node, ech);
    }
    let _ = Map::<String, Value>::new();
    node
}

pub fn build_link(node: &Value) -> String {
    let protocol = s(node, "protocol");
    let remark = encode(&s(node, "remark"));
    let host = {
        let value = s(node, "address");
        if value.contains(':') && !value.starts_with('[') { format!("[{value}]") } else { value }
    };
    let port = node["port"].as_u64().unwrap_or(443);
    match protocol.as_str() {
        "vmess" => {
            let obj = json!({
                "v": "2",
                "ps": s(node, "remark"),
                "add": s(node, "address"),
                "port": port.to_string(),
                "id": s(node, "uuid"),
                "aid": node["alter_id"].as_u64().unwrap_or(0).to_string(),
                "scy": s(node, "method"),
                "net": s(node, "network"),
                "type": s(node, "header_type"),
                "host": s(node, "host"),
                "path": s(node, "path"),
                "tls": if s(node, "tls") == "tls" { "tls" } else { "" },
                "sni": s(node, "sni"),
                "fp": s(node, "fp")
            });
            format!("vmess://{}", b64_encode(obj.to_string().as_bytes()))
        }
        "vless" => {
            let mut q = stream_query(node);
            q.insert("encryption".into(), s(node, "encryption"));
            if !s(node, "flow").is_empty() {
                q.insert("flow".into(), s(node, "flow"));
            }
            format!("vless://{}@{}:{}?{}#{}", s(node, "uuid"), host, port, encode_query(&q), remark)
        }
        "trojan" => format!("trojan://{}@{}:{}?{}#{}", encode(&s(node, "password")), host, port, encode_query(&stream_query(node)), remark),
        "shadowsocks" => {
            let creds = b64_encode(format!("{}:{}", s(node, "method"), s(node, "password")).as_bytes());
            let plugin = ss_plugin_value(node);
            if plugin.is_empty() {
                format!("ss://{creds}@{host}:{port}#{remark}")
            } else {
                format!("ss://{creds}@{host}:{port}/?plugin={}#{remark}", encode(&plugin))
            }
        }
        "hysteria2" => {
            let mut q = HashMap::new();
            q.insert("sni".into(), s(node, "sni"));
            q.insert("insecure".into(), if node["insecure"].as_bool().unwrap_or(false) { "1".into() } else { "0".into() });
            if !s(node, "obfs").is_empty() {
                q.insert("obfs".into(), s(node, "obfs"));
                q.insert("obfs-password".into(), s(node, "obfs_password"));
            }
            if !s(node, "hop_port").is_empty() {
                q.insert("mport".into(), s(node, "hop_port"));
            }
            if !ech_link_value(node).is_empty() {
                q.insert("ech".into(), ech_link_value(node));
            }
            format!("hysteria2://{}@{}:{}?{}#{}", encode(&s(node, "password")), host, port, encode_query(&q), remark)
        }
        "tuic" => {
            let mut q = tls_link_query(node);
            for (k, field) in [("congestion_control", "congestion_control"), ("udp_relay_mode", "udp_relay_mode"), ("heartbeat", "heartbeat")] {
                let v = s(node, field);
                if !v.is_empty() {
                    q.insert(k.into(), v);
                }
            }
            if node["zero_rtt"].as_bool().unwrap_or(false) {
                q.insert("reduce_rtt".into(), "1".into());
            }
            if node["disable_sni"].as_bool().unwrap_or(false) {
                q.insert("disable_sni".into(), "1".into());
            }
            format!("tuic://{}:{}@{}:{}?{}#{}", encode(&s(node, "uuid")), encode(&s(node, "password")), host, port, encode_query(&q), remark)
        }
        "anytls" => format!("anytls://{}@{}:{}?{}#{}", encode(&s(node, "password")), host, port, encode_query(&tls_link_query(node)), remark),
        "naive" => {
            let scheme = if node["naive_quic"].as_bool().unwrap_or(false) { "naive+quic" } else { "naive+https" };
            let mut q = HashMap::new();
            if !s(node, "insecure_concurrency").is_empty() {
                q.insert("insecure-concurrency".into(), s(node, "insecure_concurrency"));
            }
            let tail = if q.is_empty() { String::new() } else { format!("?{}", encode_query(&q)) };
            format!("{scheme}://{}:{}@{}:{}{tail}#{}", encode(&s(node, "username")), encode(&s(node, "password")), host, port, remark)
        }
        "warp" => {
            let mut q = HashMap::new();
            if node["warp_wow"].as_bool().unwrap_or(false) {
                q.insert("wow".into(), "1".into());
            }
            for k in AWG_KEYS {
                let v = s(node, &format!("awg_{k}"));
                if !v.is_empty() {
                    q.insert(k.into(), v);
                }
            }
            let license = s(node, "license");
            let who = if license.is_empty() { "auto".to_string() } else { encode(&license) };
            let target = if s(node, "address").is_empty() { "auto".to_string() } else { format!("{host}:{port}") };
            format!("warp://{who}@{target}?{}#{}", encode_query(&q), remark)
        }
        "wireguard" => {
            let mut q = HashMap::new();
            for (k, field) in [("publickey", "peer_public_key"), ("address", "local_address"), ("psk", "preshared_key"), ("reserved", "reserved"), ("keepalive", "keepalive"), ("allowedips", "allowed_ips")] {
                let v = s(node, field);
                if !v.is_empty() {
                    q.insert(k.into(), v);
                }
            }
            if node["mtu"].as_u64().unwrap_or(0) > 0 {
                q.insert("mtu".into(), node["mtu"].as_u64().unwrap_or(0).to_string());
            }
            for k in AWG_KEYS {
                let v = s(node, &format!("awg_{k}"));
                if !v.is_empty() {
                    q.insert(k.into(), v);
                }
            }
            format!("wireguard://{}@{}:{}?{}#{}", encode(&s(node, "private_key")), host, port, encode_query(&q), remark)
        }
        "ssh" => format!("ssh://{}:{}@{}:{}#{}", encode(&s(node, "username")), encode(&s(node, "password")), host, port, remark),
        "socks" | "http" => {
            let scheme = if protocol == "http" && s(node, "tls") == "tls" { "https" } else { protocol.as_str() };
            format!("{scheme}://{}:{}@{}:{port}#{remark}", encode(&s(node, "username")), encode(&s(node, "password")), host)
        }
        _ => s(node, "link"),
    }
}

fn stream_query(node: &Value) -> HashMap<String, String> {
    let security = s(node, "tls");
    let mut q = HashMap::new();
    q.insert("type".into(), s(node, "network"));
    q.insert("security".into(), if security == "none" || security.is_empty() { "none".into() } else { security });
    for (key, field) in [("sni", "sni"), ("fp", "fp"), ("alpn", "alpn"), ("host", "host"), ("path", "path"), ("serviceName", "service_name"), ("pbk", "pbk"), ("sid", "sid"), ("spx", "spx")] {
        let v = s(node, field);
        if !v.is_empty() && v != "none" {
            q.insert(key.into(), v);
        }
    }
    if node["insecure"].as_bool().unwrap_or(false) {
        q.insert("allowInsecure".into(), "1".into());
    }
    if s(node, "tls") == "tls" && !ech_link_value(node).is_empty() {
        q.insert("ech".into(), ech_link_value(node));
    }
    q
}

fn tls_link_query(node: &Value) -> HashMap<String, String> {
    let mut q = HashMap::new();
    for (key, field) in [("sni", "sni"), ("alpn", "alpn"), ("fp", "fp")] {
        let v = s(node, field);
        if !v.is_empty() {
            q.insert(key.into(), v);
        }
    }
    if node["insecure"].as_bool().unwrap_or(false) {
        q.insert("insecure".into(), "1".into());
    }
    if !ech_link_value(node).is_empty() {
        q.insert("ech".into(), ech_link_value(node));
    }
    q
}

fn ss_plugin_value(node: &Value) -> String {
    let version = s(node, "shadowtls_version");
    if !version.is_empty() {
        let mut parts = vec!["shadow-tls".to_string(), format!("host={}", s(node, "shadowtls_sni")), format!("password={}", s(node, "shadowtls_password")), format!("version={version}")];
        if !s(node, "fp").is_empty() {
            parts.push(format!("fp={}", s(node, "fp")));
        }
        return parts.join(";");
    }
    let plugin = s(node, "plugin");
    if plugin.is_empty() {
        return String::new();
    }
    let opts = s(node, "plugin_opts");
    if opts.is_empty() { plugin } else { format!("{plugin};{opts}") }
}

fn encode_query(q: &HashMap<String, String>) -> String {
    q.iter().map(|(k, v)| format!("{}={}", encode(k), encode(v))).collect::<Vec<_>>().join("&")
}

#[allow(dead_code)]
pub fn parse_userinfo(header: &str) -> (u64, u64, u64, u64) {
    let mut upload = 0;
    let mut download = 0;
    let mut total = 0;
    let mut expire = 0;
    for part in header.split(';') {
        let Some((k, v)) = part.split_once('=') else { continue };
        let n = v.trim().parse().unwrap_or(0);
        match k.trim().to_ascii_lowercase().as_str() {
            "upload" => upload = n,
            "download" => download = n,
            "total" => total = n,
            "expire" => expire = n,
            _ => {}
        }
    }
    (upload, download, total, expire)
}

fn yaml_unquote(raw: &str) -> String {
    let t = raw.trim();
    if (t.starts_with('"') && t.ends_with('"') && t.len() >= 2) || (t.starts_with('\'') && t.ends_with('\'') && t.len() >= 2) {
        return t[1..t.len() - 1].to_string();
    }
    let t = match t.find(" #") {
        Some(i) => t[..i].trim(),
        None => t,
    };
    if t.starts_with('[') && t.ends_with(']') {
        return split_top(&t[1..t.len() - 1]).iter().map(|p| yaml_unquote(p)).filter(|p| !p.is_empty()).collect::<Vec<_>>().join(",");
    }
    t.trim_end_matches(',').to_string()
}

fn split_top(body: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut depth = 0i32;
    let mut quote: Option<char> = None;
    let mut cur = String::new();
    for c in body.chars() {
        match quote {
            Some(q) if c == q => quote = None,
            Some(_) => {}
            None => match c {
                '"' | '\'' => quote = Some(c),
                '{' | '[' => depth += 1,
                '}' | ']' => depth -= 1,
                ',' if depth == 0 => {
                    parts.push(cur.trim().to_string());
                    cur.clear();
                    continue;
                }
                _ => {}
            },
        }
        cur.push(c);
    }
    if !cur.trim().is_empty() {
        parts.push(cur.trim().to_string());
    }
    parts
}

fn flatten_inline(prefix: &str, body: &str, map: &mut HashMap<String, String>) {
    let inner = body.trim();
    let inner = inner.strip_prefix('{').unwrap_or(inner);
    let inner = inner.strip_suffix('}').unwrap_or(inner);
    for part in split_top(inner) {
        let Some((k, v)) = part.split_once(':') else { continue };
        let key = k.trim().trim_matches(|c| c == '"' || c == '\'');
        let full = if prefix.is_empty() { key.to_string() } else { format!("{prefix}.{key}") };
        let value = v.trim();
        if value.starts_with('{') {
            flatten_inline(&full, value, map);
        } else {
            map.insert(full, yaml_unquote(value));
        }
    }
}

fn leading_number(raw: &str) -> u64 {
    raw.trim().chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse().unwrap_or(0)
}

fn with_prefix_len(ip: &str) -> String {
    let ip = ip.trim();
    if ip.is_empty() || ip.contains('/') {
        ip.to_string()
    } else if ip.contains(':') {
        format!("{ip}/128")
    } else {
        format!("{ip}/32")
    }
}

fn clash_node(map: &HashMap<String, String>) -> Option<Value> {
    let get = |keys: &[&str]| keys.iter().find_map(|k| map.get(*k).filter(|v| !v.is_empty()).cloned()).unwrap_or_default();
    let kind = get(&["type"]).to_ascii_lowercase();
    let server = get(&["server"]);
    if server.is_empty() {
        return None;
    }
    let protocol = match kind.as_str() {
        "ss" | "shadowsocks" => "shadowsocks",
        "vmess" => "vmess",
        "vless" => "vless",
        "trojan" => "trojan",
        "hysteria2" | "hy2" => "hysteria2",
        "hysteria" => "hysteria",
        "tuic" => "tuic",
        "anytls" => "anytls",
        "wireguard" => "wireguard",
        "ssh" => "ssh",
        "socks5" | "socks" => "socks",
        "http" => "http",
        _ => return None,
    };
    let mut node = blank(protocol);
    let name = get(&["name"]);
    set(&mut node, "remark", json!(if name.is_empty() { server.clone() } else { name }));
    set(&mut node, "address", json!(server));
    set(&mut node, "port", json!(leading_number(&get(&["port"]))));
    let tls_on = flag(&get(&["tls"]));
    let always_tls = matches!(protocol, "trojan" | "hysteria2" | "hysteria" | "tuic" | "anytls");
    match protocol {
        "shadowsocks" => {
            let method = get(&["cipher", "method"]);
            set(&mut node, "method", json!(if method.is_empty() { "aes-256-gcm".to_string() } else { method }));
            set(&mut node, "password", json!(get(&["password"])));
            match get(&["plugin"]).to_ascii_lowercase().as_str() {
                "obfs" | "obfs-local" | "simple-obfs" => {
                    let mut opts = vec![format!("obfs={}", get(&["plugin-opts.mode"]))];
                    let host = get(&["plugin-opts.host"]);
                    if !host.is_empty() {
                        opts.push(format!("obfs-host={host}"));
                    }
                    set(&mut node, "plugin", json!("obfs-local"));
                    set(&mut node, "plugin_opts", json!(opts.join(";")));
                }
                "v2ray-plugin" => {
                    let mode = get(&["plugin-opts.mode"]);
                    let mut opts = vec![format!("mode={}", if mode.is_empty() { "websocket".to_string() } else { mode })];
                    if flag(&get(&["plugin-opts.tls"])) {
                        opts.push("tls".into());
                    }
                    for (k, field) in [("host", "plugin-opts.host"), ("path", "plugin-opts.path")] {
                        let v = get(&[field]);
                        if !v.is_empty() {
                            opts.push(format!("{k}={v}"));
                        }
                    }
                    set(&mut node, "plugin", json!("v2ray-plugin"));
                    set(&mut node, "plugin_opts", json!(opts.join(";")));
                }
                "shadow-tls" | "shadowtls" => {
                    let version = get(&["plugin-opts.version"]);
                    set(&mut node, "shadowtls_version", json!(if version.is_empty() { "3".to_string() } else { version }));
                    set(&mut node, "shadowtls_password", json!(get(&["plugin-opts.password"])));
                    set(&mut node, "shadowtls_sni", json!(get(&["plugin-opts.host"])));
                }
                _ => {}
            }
        }
        "vmess" => {
            set(&mut node, "uuid", json!(get(&["uuid"])));
            set(&mut node, "alter_id", json!(leading_number(&get(&["alterId", "alterid", "alter-id"]))));
            let cipher = get(&["cipher"]);
            set(&mut node, "method", json!(if cipher.is_empty() { "auto".to_string() } else { cipher }));
        }
        "vless" => {
            set(&mut node, "uuid", json!(get(&["uuid"])));
            set(&mut node, "flow", json!(get(&["flow"])));
            let enc = get(&["encryption"]);
            set(&mut node, "encryption", json!(if enc.is_empty() { "none".to_string() } else { enc }));
        }
        "trojan" | "anytls" => {
            set(&mut node, "password", json!(get(&["password"])));
            if protocol == "anytls" {
                for (k, field) in [("idle-session-check-interval", "idle_session_check_interval"), ("idle-session-timeout", "idle_session_timeout")] {
                    let v = get(&[k]);
                    if !v.is_empty() {
                        set(&mut node, field, json!(if v.chars().all(|c| c.is_ascii_digit()) { format!("{v}s") } else { v }));
                    }
                }
                let min = get(&["min-idle-session"]);
                if !min.is_empty() {
                    set(&mut node, "min_idle_session", json!(min));
                }
            }
        }
        "hysteria2" => {
            set(&mut node, "password", json!(get(&["password", "auth"])));
            set(&mut node, "obfs", json!(get(&["obfs"])));
            set(&mut node, "obfs_password", json!(get(&["obfs-password", "obfs_password"])));
            set(&mut node, "hop_port", json!(get(&["ports", "mport"])));
        }
        "hysteria" => {
            set(&mut node, "password", json!(get(&["auth-str", "auth_str", "auth", "password"])));
            set(&mut node, "obfs", json!(get(&["obfs"])));
        }
        "tuic" => {
            set(&mut node, "uuid", json!(get(&["uuid"])));
            set(&mut node, "password", json!(get(&["password"])));
            set(&mut node, "congestion_control", json!(get(&["congestion-controller", "congestion-control", "congestion_control"])));
            set(&mut node, "udp_relay_mode", json!(get(&["udp-relay-mode", "udp_relay_mode"])));
            set(&mut node, "zero_rtt", json!(flag(&get(&["reduce-rtt", "zero-rtt-handshake"]))));
            set(&mut node, "disable_sni", json!(flag(&get(&["disable-sni"]))));
            let beat = get(&["heartbeat-interval", "heartbeat"]);
            if !beat.is_empty() {
                set(&mut node, "heartbeat", json!(if beat.chars().all(|c| c.is_ascii_digit()) { format!("{beat}ms") } else { beat }));
            }
        }
        "wireguard" => {
            set(&mut node, "private_key", json!(get(&["private-key", "private_key"])));
            set(&mut node, "peer_public_key", json!(get(&["public-key", "public_key", "peers.public-key"])));
            set(&mut node, "preshared_key", json!(get(&["pre-shared-key", "preshared-key", "pre_shared_key"])));
            let local: Vec<String> = [get(&["ip"]), get(&["ipv6"])].iter().flat_map(|v| v.split(',').map(with_prefix_len).collect::<Vec<_>>()).filter(|v| !v.is_empty()).collect();
            set(&mut node, "local_address", json!(local.join(",")));
            set(&mut node, "mtu", json!(leading_number(&get(&["mtu"]))));
            set(&mut node, "reserved", json!(get(&["reserved"])));
            set(&mut node, "allowed_ips", json!(get(&["allowed-ips"])));
            set(&mut node, "keepalive", json!(get(&["persistent-keepalive"])));
            for k in AWG_KEYS {
                let v = get(&[&format!("amnezia-wg-option.{k}"), &format!("amnezia-wg-option.{}", k.to_ascii_uppercase())]);
                if !v.is_empty() {
                    set(&mut node, &format!("awg_{k}"), json!(v));
                }
            }
            set(&mut node, "tls", json!("none"));
            return Some(node);
        }
        "ssh" => {
            set(&mut node, "username", json!(get(&["username", "user"])));
            set(&mut node, "password", json!(get(&["password"])));
            set(&mut node, "private_key", json!(get(&["private-key", "private_key"])));
        }
        _ => {
            set(&mut node, "username", json!(get(&["username", "user"])));
            set(&mut node, "password", json!(get(&["password"])));
        }
    }
    for (key, field) in [("up", "up_mbps"), ("down", "down_mbps"), ("up-mbps", "up_mbps"), ("down-mbps", "down_mbps")] {
        let v = get(&[key]);
        if !v.is_empty() {
            set(&mut node, field, json!(leading_number(&v)));
        }
    }
    let network = get(&["network"]);
    match network.as_str() {
        "ws" => {
            let upgrade = flag(&get(&["ws-opts.v2ray-http-upgrade"]));
            set(&mut node, "network", json!(if upgrade { "httpupgrade" } else { "ws" }));
            set(&mut node, "path", json!(get(&["ws-opts.path", "ws-path", "path"])));
            set(&mut node, "host", json!(get(&["ws-opts.headers.Host", "ws-opts.headers.host", "ws-headers.Host", "ws-host", "host"])));
        }
        "grpc" => {
            set(&mut node, "network", json!("grpc"));
            set(&mut node, "service_name", json!(get(&["grpc-opts.grpc-service-name", "grpc-service-name", "serviceName"])));
        }
        "h2" => {
            set(&mut node, "network", json!("h2"));
            set(&mut node, "path", json!(get(&["h2-opts.path", "path"])));
            set(&mut node, "host", json!(get(&["h2-opts.host", "host"]).split(',').next().unwrap_or("").to_string()));
        }
        "http" => {
            set(&mut node, "network", json!("tcp"));
            set(&mut node, "header_type", json!("http"));
            set(&mut node, "path", json!(get(&["http-opts.path"]).split(',').next().unwrap_or("").to_string()));
            set(&mut node, "host", json!(get(&["http-opts.headers.Host"]).split(',').next().unwrap_or("").to_string()));
        }
        "xhttp" | "httpupgrade" => {
            set(&mut node, "network", json!(network));
            set(&mut node, "path", json!(get(&["xhttp-opts.path", "path"])));
            set(&mut node, "host", json!(get(&["xhttp-opts.host", "host"])));
            set(&mut node, "mode", json!(get(&["xhttp-opts.mode", "mode"])));
        }
        _ => {
            let path = get(&["ws-opts.path", "path"]);
            if !path.is_empty() {
                set(&mut node, "path", json!(path));
            }
            let host = get(&["ws-opts.headers.Host", "host"]);
            if !host.is_empty() {
                set(&mut node, "host", json!(host));
            }
        }
    }
    if always_tls || tls_on || !get(&["sni", "servername"]).is_empty() && protocol != "shadowsocks" {
        if protocol != "shadowsocks" && protocol != "ssh" {
            set(&mut node, "tls", json!("tls"));
        }
    }
    let pbk = get(&["reality-opts.public-key", "reality-public-key", "pbk"]);
    if !pbk.is_empty() && matches!(protocol, "vless" | "trojan" | "vmess") {
        set(&mut node, "tls", json!("reality"));
        set(&mut node, "pbk", json!(pbk));
        set(&mut node, "sid", json!(get(&["reality-opts.short-id", "reality-short-id", "short-id", "sid"])));
    }
    set(&mut node, "sni", json!(get(&["sni", "servername", "server-name"])));
    set(&mut node, "fp", json!(get(&["client-fingerprint", "fingerprint"])));
    set(&mut node, "alpn", json!(get(&["alpn"])));
    set(&mut node, "insecure", json!(flag(&get(&["skip-cert-verify"]))));
    set(&mut node, "packet_encoding", json!(get(&["packet-encoding"])));
    if flag(&get(&["ech-opts.enable", "ech-opts.enabled"])) {
        set(&mut node, "ech", json!(true));
        set(&mut node, "ech_config", json!(pem_to_b64(&get(&["ech-opts.config"]))));
        set(&mut node, "ech_query_server_name", json!(get(&["ech-opts.query-server-name"])));
    }
    Some(node)
}

pub fn parse_clash_yaml(text: &str) -> Vec<Value> {
    let body = text.trim();
    if body.is_empty() {
        return Vec::new();
    }
    let looks = body.contains("proxies:") || body.lines().any(|l| {
        let t = l.trim().trim_start_matches("- ").trim();
        t.starts_with("type: ") || t.starts_with("{") && t.contains("type:") && t.contains("server:")
    });
    if !looks || !body.contains("server") {
        return Vec::new();
    }
    let owned;
    let body = if body.contains("proxies:") {
        body
    } else if body.starts_with('-') {
        owned = format!("proxies:\n{body}");
        owned.as_str()
    } else {
        owned = format!("proxies:\n- {}", body.lines().collect::<Vec<_>>().join("\n  "));
        owned.as_str()
    };
    let mut nodes = Vec::new();
    let mut current: Option<HashMap<String, String>> = None;
    let mut item_indent = 0usize;
    let mut nests: Vec<(usize, String)> = Vec::new();
    let mut in_proxies = false;
    let flush = |current: &mut Option<HashMap<String, String>>, nodes: &mut Vec<Value>| {
        if let Some(map) = current.take() {
            if let Some(node) = clash_node(&map) {
                nodes.push(node);
            }
        }
    };
    for raw in body.lines() {
        let line = raw.trim_end();
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let indent = line.len() - line.trim_start().len();
        if indent == 0 && trimmed.starts_with("proxies:") {
            flush(&mut current, &mut nodes);
            nests.clear();
            in_proxies = true;
            continue;
        }
        if indent == 0 && !trimmed.starts_with('-') && trimmed.contains(':') {
            flush(&mut current, &mut nodes);
            nests.clear();
            in_proxies = false;
            continue;
        }
        if !in_proxies {
            continue;
        }
        let item = trimmed.strip_prefix("- ").or(if trimmed == "-" { Some("") } else { None });
        if let Some(rest) = item {
            let rest = rest.trim();
            if current.is_none() || indent <= item_indent {
                flush(&mut current, &mut nodes);
                nests.clear();
                item_indent = indent;
                let mut map = HashMap::new();
                if rest.starts_with('{') {
                    flatten_inline("", rest, &mut map);
                    if let Some(node) = clash_node(&map) {
                        nodes.push(node);
                    }
                    continue;
                }
                if let Some((k, v)) = rest.split_once(':') {
                    map.insert(k.trim().to_string(), yaml_unquote(v));
                }
                current = Some(map);
            } else if let Some(map) = current.as_mut() {
                while nests.len() > 1 && nests.last().map(|(i, _)| *i >= indent).unwrap_or(false) {
                    nests.pop();
                }
                let key = nests.iter().map(|(_, name)| name.as_str()).collect::<Vec<_>>().join(".");
                if key.is_empty() {
                    continue;
                }
                if rest.contains(':') && !rest.starts_with('"') {
                    let mut inner = HashMap::new();
                    flatten_inline("", rest, &mut inner);
                    for (k, v) in inner {
                        map.entry(format!("{key}.{k}")).or_insert(v);
                    }
                } else {
                    let value = yaml_unquote(rest);
                    let entry = map.entry(key).or_default();
                    if !entry.is_empty() {
                        entry.push(',');
                    }
                    entry.push_str(&value);
                }
            }
            continue;
        }
        if let Some(map) = current.as_mut() {
            while nests.last().map(|(i, _)| *i >= indent).unwrap_or(false) {
                nests.pop();
            }
            if let Some((k, v)) = trimmed.split_once(':') {
                let key = k.trim().trim_matches(|c| c == '"' || c == '\'').to_string();
                let prefix = nests.iter().map(|(_, name)| name.as_str()).collect::<Vec<_>>().join(".");
                let full = if prefix.is_empty() { key.clone() } else { format!("{prefix}.{key}") };
                let value = v.trim();
                if value.is_empty() {
                    nests.push((indent, key));
                } else if value.starts_with('{') {
                    flatten_inline(&full, value, map);
                } else {
                    map.insert(full, yaml_unquote(value));
                }
            }
        }
    }
    flush(&mut current, &mut nodes);
    nodes
}

#[cfg(test)]
mod tests {
    use super::*;

    fn round_trip(link: &str) -> (Value, Value) {
        let first = parse_link(link).unwrap_or_else(|e| panic!("{link}: {e}"));
        let rebuilt = build_link(&first);
        let second = parse_link(&rebuilt).unwrap_or_else(|e| panic!("{rebuilt}: {e}"));
        (first, second)
    }

    #[test]
    fn new_links_round_trip() {
        let (a, b) = round_trip("tuic://b1a2c3d4-1111-2222-3333-444455556666:pw@example.com:443?congestion_control=cubic&udp_relay_mode=quic&alpn=h3&sni=sni.example.com#T");
        for key in ["protocol", "uuid", "password", "congestion_control", "udp_relay_mode", "sni"] {
            assert_eq!(a[key], b[key], "tuic {key}");
        }
        assert_eq!(a["congestion_control"], "cubic");

        let (a, b) = round_trip("anytls://secret@example.com:8443?sni=example.com&insecure=1#A");
        assert_eq!(a["protocol"], "anytls");
        assert_eq!(a["password"], b["password"]);
        assert_eq!(a["port"], 8443);

        let (a, b) = round_trip("naive+quic://user:pass@example.com:443?padding=1#N");
        assert_eq!(a["protocol"], "naive");
        assert_eq!(a["username"], "user");
        assert!(truthy_value(&a["naive_quic"]));
        assert_eq!(a["username"], b["username"]);
        assert_eq!(a["naive_quic"], b["naive_quic"]);

        let (a, b) = round_trip("ss://YWVzLTI1Ni1nY206cHc@example.com:443/?plugin=shadow-tls%3Bhost%3Dwww.apple.com%3Bpassword%3Dx%3Bversion%3D2#S");
        assert_eq!(a["shadowtls_version"], "2");
        assert_eq!(a["shadowtls_sni"], "www.apple.com");
        assert_eq!(a["shadowtls_password"], b["shadowtls_password"]);

        let (a, b) = round_trip("wireguard://cHJpdg%3D%3D@1.2.3.4:51820?publickey=cHVi&address=10.0.0.2%2F32&jc=4&jmin=40&jmax=70&h1=5&i1=%3Cr%2010%3E#W");
        assert!(is_amnezia(&a));
        for key in ["awg_jc", "awg_jmin", "awg_jmax", "awg_h1", "awg_i1"] {
            assert_eq!(a[key], b[key], "awg {key}");
        }

        let (a, b) = round_trip("hysteria2://pw@example.com:443?sni=example.com&ech=cloudflare-ech.com%2Bhttps%3A%2F%2F1.1.1.1%2Fdns-query#H");
        assert!(truthy_value(&a["ech"]));
        assert_eq!(a["ech_query_server_name"], "cloudflare-ech.com");
        assert_eq!(a["ech_query_server_name"], b["ech_query_server_name"]);
    }

    #[test]
    fn warp_links() {
        let node = parse_link("warp://auto#W").unwrap();
        assert_eq!(node["protocol"], "warp");
        assert_eq!(node["license"].as_str().unwrap_or(""), "");
        let wow = parse_link("warp://auto?jc=5&jmin=50&jmax=80#Outer&&detour=warp://auto#Inner").unwrap();
        assert_eq!(wow["protocol"], "warp");
        assert!(truthy_value(&wow["warp_wow"]));
        assert_eq!(wow["awg_jc"], "5");
    }

    #[test]
    fn amnezia_vpn_and_conf() {
        let conf = "[Interface]\nPrivateKey = cHJpdg==\nAddress = 10.8.0.2/32\nJc = 4\nJmin = 40\nJmax = 70\nH1 = 1\n[Peer]\nPublicKey = cHVi\nEndpoint = 5.6.7.8:443\nAllowedIPs = 0.0.0.0/0\n";
        let body = json!({"containers": [{"container": "amnezia-awg", "awg": {"last_config": json!({"config": conf}).to_string()}}], "description": "Home"});
        let encoded = body.to_string().bytes().collect::<Vec<u8>>();
        let link = format!("vpn://{}", b64url(&encoded));
        let node = parse_link(&link).unwrap();
        assert_eq!(node["protocol"], "wireguard");
        assert_eq!(node["address"], "5.6.7.8");
        assert_eq!(node["port"], 443);
        assert_eq!(node["awg_jc"], "4");
    }

    fn truthy_value(v: &Value) -> bool {
        match v {
            Value::Bool(b) => *b,
            Value::String(s) => matches!(s.as_str(), "1" | "true"),
            _ => false,
        }
    }

    fn b64url(data: &[u8]) -> String {
        const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        let mut out = String::new();
        for chunk in data.chunks(3) {
            let b = [chunk[0], *chunk.get(1).unwrap_or(&0), *chunk.get(2).unwrap_or(&0)];
            let n = (b[0] as u32) << 16 | (b[1] as u32) << 8 | b[2] as u32;
            for i in 0..chunk.len() + 1 {
                out.push(T[(n >> (18 - 6 * i) & 63) as usize] as char);
            }
        }
        out
    }
}
