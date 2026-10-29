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

fn base64_decode(input: &str) -> Option<Vec<u8>> {
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

pub fn split_host_port(hostport: &str, fallback: u16) -> (String, u16) {
    let raw = hostport.trim();
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
    let insecure = query.get("allowInsecure").or(query.get("insecure")).or(query.get("allow_insecure")).map(|v| flag(v)).unwrap_or(false);
    if insecure {
        set(node, "insecure", json!(true));
    }
    if s(node, "tls") == "tls" && !s(node, "pbk").is_empty() {
        set(node, "tls", json!("reality"));
    }
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
    let mut body = text.trim().to_string();
    if body.is_empty() {
        return Vec::new();
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
    if let Some(outbounds) = map.get("outbounds").and_then(|v| v.as_array()) {
        let mut found = Vec::new();
        for outbound in outbounds {
            let kind = outbound["type"].as_str().or(outbound["protocol"].as_str()).unwrap_or("");
            if matches!(kind, "direct" | "block" | "blackhole" | "freedom" | "dns" | "selector" | "urltest") {
                continue;
            }
            found.push(from_outbound(outbound));
        }
        return found.into_iter().filter(|n| !s(n, "address").is_empty()).collect();
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
    set(&mut node, "address", json!(outbound["server"].as_str().unwrap_or("")));
    set(&mut node, "port", json!(outbound["server_port"].as_u64().unwrap_or(443)));
    set(&mut node, "uuid", json!(outbound["uuid"].as_str().unwrap_or("")));
    set(&mut node, "password", json!(outbound["password"].as_str().or(outbound["auth_str"].as_str()).unwrap_or("")));
    set(&mut node, "method", json!(outbound["security"].as_str().or(outbound["method"].as_str()).unwrap_or("auto")));
    set(&mut node, "flow", json!(outbound["flow"].as_str().unwrap_or("")));
    set(&mut node, "username", json!(outbound["username"].as_str().or(outbound["user"].as_str()).unwrap_or("")));
    if let Some(tls) = outbound.get("tls") {
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
        set(&mut node, "host", json!(transport["host"].as_str().unwrap_or("")));
        set(&mut node, "service_name", json!(transport["service_name"].as_str().unwrap_or("")));
    }
    node
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
        "shadowsocks" => format!("ss://{}@{}:{}#{}", b64_encode(format!("{}:{}", s(node, "method"), s(node, "password")).as_bytes()), host, port, remark),
        "hysteria2" => {
            let mut q = HashMap::new();
            q.insert("sni".into(), s(node, "sni"));
            q.insert("insecure".into(), if node["insecure"].as_bool().unwrap_or(false) { "1".into() } else { "0".into() });
            if !s(node, "obfs").is_empty() {
                q.insert("obfs".into(), s(node, "obfs"));
                q.insert("obfs-password".into(), s(node, "obfs_password"));
            }
            format!("hysteria2://{}@{}:{}?{}#{}", encode(&s(node, "password")), host, port, encode_query(&q), remark)
        }
        "wireguard" => {
            let mut q = HashMap::new();
            for (k, field) in [("publickey", "peer_public_key"), ("address", "local_address"), ("psk", "preshared_key"), ("reserved", "reserved")] {
                let v = s(node, field);
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
    q
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
        t[1..t.len() - 1].to_string()
    } else {
        t.trim_end_matches(',').to_string()
    }
}

fn parse_inline_map(body: &str) -> std::collections::HashMap<String, String> {
    let mut map = std::collections::HashMap::new();
    let inner = body.trim().trim_start_matches('{').trim_end_matches('}');
    for part in inner.split(',') {
        let Some((k, v)) = part.split_once(':') else { continue };
        map.insert(k.trim().to_string(), yaml_unquote(v));
    }
    map
}

fn clash_node(map: &std::collections::HashMap<String, String>) -> Option<Value> {
    let kind = map.get("type").map(|s| s.to_ascii_lowercase())?;
    let server = map.get("server").cloned().unwrap_or_default();
    if server.is_empty() {
        return None;
    }
    let port: u64 = map.get("port").and_then(|s| s.parse().ok()).unwrap_or(0);
    let name = map.get("name").cloned().unwrap_or_else(|| server.clone());
    let mut node = json!({
        "name": name,
        "address": server,
        "port": port,
        "protocol": kind,
        "security": "none",
        "network": "tcp"
    });
    match kind.as_str() {
        "ss" | "shadowsocks" => {
            node["protocol"] = json!("shadowsocks");
            node["method"] = json!(map.get("cipher").or_else(|| map.get("method")).cloned().unwrap_or_else(|| "aes-256-gcm".into()));
            node["password"] = json!(map.get("password").cloned().unwrap_or_default());
        }
        "vmess" => {
            node["protocol"] = json!("vmess");
            node["uuid"] = json!(map.get("uuid").cloned().unwrap_or_default());
            node["alterId"] = json!(map.get("alterId").or_else(|| map.get("alterid")).and_then(|s| s.parse::<u64>().ok()).unwrap_or(0));
            node["security"] = json!(map.get("cipher").cloned().unwrap_or_else(|| "auto".into()));
        }
        "vless" => {
            node["protocol"] = json!("vless");
            node["uuid"] = json!(map.get("uuid").cloned().unwrap_or_default());
            node["flow"] = json!(map.get("flow").cloned().unwrap_or_default());
        }
        "trojan" => {
            node["protocol"] = json!("trojan");
            node["password"] = json!(map.get("password").cloned().unwrap_or_default());
            node["security"] = json!("tls");
        }
        "hysteria2" | "hy2" => {
            node["protocol"] = json!("hysteria2");
            node["password"] = json!(map.get("password").or_else(|| map.get("auth")).cloned().unwrap_or_default());
            node["security"] = json!("tls");
        }
        "hysteria" => {
            node["protocol"] = json!("hysteria");
            node["password"] = json!(map.get("auth_str").or_else(|| map.get("auth-str")).or_else(|| map.get("password")).cloned().unwrap_or_default());
            node["security"] = json!("tls");
        }
        "socks5" | "socks" | "http" => {
            node["protocol"] = json!(if kind.starts_with("http") { "http" } else { "socks" });
            node["user"] = json!(map.get("username").cloned().unwrap_or_default());
            node["password"] = json!(map.get("password").cloned().unwrap_or_default());
        }
        _ => return None,
    }
    if let Some(net) = map.get("network") {
        node["network"] = json!(net);
    }
    if map.get("tls").map(|s| s == "true").unwrap_or(false) || map.get("skip-cert-verify").is_some() {
        if node["security"] == json!("none") {
            node["security"] = json!("tls");
        }
    }
    if let Some(sni) = map.get("sni").or_else(|| map.get("servername")) {
        node["sni"] = json!(sni);
        node["serverName"] = json!(sni);
    }
    if let Some(fp) = map.get("client-fingerprint").or_else(|| map.get("fingerprint")) {
        node["fingerprint"] = json!(fp);
    }
    Some(node)
}

pub fn parse_clash_yaml(text: &str) -> Vec<Value> {
    let body = text.trim();
    if body.is_empty() {
        return Vec::new();
    }
    let looks = body.contains("proxies:") || body.contains("\ntype: ") || body.contains("type: ss") || body.contains("type: vmess") || body.contains("type: vless") || body.contains("type: trojan");
    if !looks && !body.contains("proxy-groups:") {
        return Vec::new();
    }
    let mut nodes = Vec::new();
    let mut current: Option<std::collections::HashMap<String, String>> = None;
    let mut in_proxies = body.contains("proxies:");
    if !body.contains("proxies:") && looks {
        in_proxies = true;
    }
    for raw in body.lines() {
        let line = raw.trim_end();
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if trimmed == "proxies:" || trimmed.starts_with("proxies:") {
            in_proxies = true;
            continue;
        }
        if in_proxies && !line.starts_with(' ') && !line.starts_with('\t') && !trimmed.starts_with('-') && trimmed.ends_with(':') && !trimmed.contains(' ') {
            if let Some(map) = current.take() {
                if let Some(node) = clash_node(&map) {
                    nodes.push(node);
                }
            }
            in_proxies = trimmed == "proxies:";
            continue;
        }
        if !in_proxies {
            continue;
        }
        if trimmed.starts_with("- {") || (trimmed.starts_with('-') && trimmed.contains('{')) {
            if let Some(map) = current.take() {
                if let Some(node) = clash_node(&map) {
                    nodes.push(node);
                }
            }
            if let Some(start) = trimmed.find('{') {
                if let Some(node) = clash_node(&parse_inline_map(&trimmed[start..])) {
                    nodes.push(node);
                }
            }
            continue;
        }
        if trimmed.starts_with("- ") {
            if let Some(map) = current.take() {
                if let Some(node) = clash_node(&map) {
                    nodes.push(node);
                }
            }
            let rest = trimmed.trim_start_matches("- ").trim();
            let mut map = std::collections::HashMap::new();
            if let Some((k, v)) = rest.split_once(':') {
                map.insert(k.trim().to_string(), yaml_unquote(v));
            }
            current = Some(map);
            continue;
        }
        if let Some(map) = current.as_mut() {
            if let Some((k, v)) = trimmed.split_once(':') {
                map.insert(k.trim().to_string(), yaml_unquote(v));
            }
        }
    }
    if let Some(map) = current.take() {
        if let Some(node) = clash_node(&map) {
            nodes.push(node);
        }
    }
    nodes
}
