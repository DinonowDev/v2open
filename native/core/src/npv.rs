use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{ChaCha20Poly1305, Nonce};
use hkdf::Hkdf;
use pbkdf2::pbkdf2_hmac;
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::OnceLock;

const SHIFT: [usize; 16] = [0, 5, 10, 15, 4, 9, 14, 3, 8, 13, 2, 7, 12, 1, 6, 11];
const SENTINEL_ALPHABET: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-";

#[derive(Debug)]
pub struct NpvOpened {
    pub nodes: Vec<Value>,
    pub notice: String,
}

struct Tables {
    ty: Vec<u32>,
    mbl: Vec<u32>,
    xt: Vec<u8>,
    tbl: Vec<u8>,
    tbl_v1: Vec<u8>,
}

pub fn is_npv_text(text: &str) -> bool {
    let trimmed = text.trim();
    trimmed.starts_with("NPVT1")
        || trimmed.starts_with("NPVTSUB1")
        || trimmed.starts_with("NPVO1")
        || trimmed.as_bytes().starts_with(b"NPVS")
        || compact_npvs(trimmed).is_some()
}

pub fn nodes_from_text(text: &str) -> Vec<Value> {
    open_bytes(text.as_bytes(), "").map(|opened| opened.nodes).unwrap_or_default()
}

pub fn open_bytes(bytes: &[u8], password: &str) -> Result<NpvOpened, String> {
    if bytes.starts_with(b"NPVS") {
        return open_npvs(bytes, password);
    }
    let text = std::str::from_utf8(bytes).map_err(|_| "could not read that config".to_string())?;
    let trimmed = text.trim();
    if trimmed.starts_with("NPVO1") {
        return open_value(parse_json_text(trimmed.trim_start_matches("NPVO1").trim())?, "");
    }
    if trimmed.starts_with("NPVT1") || trimmed.starts_with("NPVTSUB1") {
        return open_npvt(trimmed);
    }
    if let Some(bin) = compact_npvs(trimmed) {
        return open_npvs(&bin, password);
    }
    Err("could not read that config".into())
}

fn open_npvt(text: &str) -> Result<NpvOpened, String> {
    let tables = tables();
    let mut nodes = Vec::new();
    let mut notes = Vec::new();
    let body = text.replace("NPVTSUB1", ",").replace("NPVT1", ",");
    for token in body.split(',') {
        let token = token.trim();
        if token.is_empty() {
            continue;
        }
        let Some(blob) = crate::parser::base64_decode(token) else { continue };
        if blob.len() < 32 {
            continue;
        }
        let plain = wb_ctr(&tables.ty, &tables.mbl, &tables.xt, &tables.tbl, &blob[..16], &blob[16..]);
        absorb_plain(&plain, &mut nodes, &mut notes);
    }
    if nodes.is_empty() {
        return Err("could not read that config".into());
    }
    Ok(NpvOpened { nodes, notice: unique_notice(notes) })
}

fn open_npvs(data: &[u8], password: &str) -> Result<NpvOpened, String> {
    if data.len() >= 9 && data.starts_with(b"NPVS") && data[4] == 5 {
        return open_gen2(data, password);
    }
    if data.len() >= 9 && data.starts_with(b"NPVS") && data[4] <= 1 {
        return open_v1(data, password);
    }
    Err("could not read that config".into())
}

fn open_v1(data: &[u8], password: &str) -> Result<NpvOpened, String> {
    let hdr_len = u32be(data, 5)? as usize;
    if data.len() < 9 + hdr_len {
        return Err("could not read that config".into());
    }
    let hdr_raw = &data[9..9 + hdr_len];
    let hdr: Value = serde_json::from_slice(hdr_raw).map_err(|_| "could not read that config".to_string())?;
    let mut off = 9 + hdr_len;
    if data.len() < off + 16 {
        return Err("could not read that config".into());
    }
    let nonce = &data[off..off + 12];
    let body_len = u32be(data, off + 12)? as usize;
    off += 16;
    if data.len() < off + body_len {
        return Err("could not read that config".into());
    }
    let body = &data[off..off + body_len];
    let mut notes = policy_notes(hdr.get("policy"));
    let mut dek = None;
    if let Some(app_key) = hdr.get("appKey").filter(|v| v.is_object()) {
        let salt = b64_any(app_key["salt"].as_str().unwrap_or(""))?;
        let wrap = b64_any(app_key["wrap"].as_str().unwrap_or(""))?;
        for kdk in custodian_kdks(&salt) {
            if let Ok(opened) = aead_open(&kdk, &wrap[..12], &salt, &wrap[12..]) {
                dek = Some(opened);
                break;
            }
        }
    }
    if dek.is_none() {
        if let Some(pass) = hdr.get("passphrase").filter(|v| v.is_object()) {
            if password.is_empty() {
                return Err("password required".into());
            }
            let salt = b64_any(pass["salt"].as_str().unwrap_or(""))?;
            let wrap = b64_any(pass["wrap"].as_str().unwrap_or(""))?;
            let iters = pass["iters"].as_u64().unwrap_or(600_000) as u32;
            let mut derived = [0u8; 32];
            pbkdf2_hmac::<Sha256>(password.as_bytes(), &salt, iters, &mut derived);
            dek = Some(aead_open(&derived, &wrap[..12], &salt, &wrap[12..]).map_err(|_| "wrong password".to_string())?);
        }
    }
    let dek = dek.ok_or_else(|| {
        if hdr.get("passphrase").is_some() { "password required".to_string() } else { "could not read that config".to_string() }
    })?;
    let plain = aead_open(&dek, nonce, hdr_raw, body).map_err(|_| "could not read that config".to_string())?;
    let mut nodes = Vec::new();
    absorb_plain(&plain, &mut nodes, &mut notes);
    if nodes.is_empty() {
        return Err("could not read that config".into());
    }
    Ok(NpvOpened { nodes, notice: unique_notice(notes) })
}

fn open_gen2(data: &[u8], password: &str) -> Result<NpvOpened, String> {
    let hdr_len = u32be(data, 5)? as usize;
    if data.len() < 9 + hdr_len {
        return Err("could not read that config".into());
    }
    let h = &data[9..9 + hdr_len];
    if h.first().copied() != Some(1) {
        return Err("could not read that config".into());
    }
    let config_id = h.get(1..17).ok_or("could not read that config")?;
    let method = *h.get(50).ok_or("could not read that config")?;
    let recipients = u16be(h, 51)? as usize;
    let mut off = 53 + recipients * (32 + 0x5D);
    let (salt, wrap, iters) = if method == 2 {
        if h.len() < off + 78 {
            return Err("could not read that config".into());
        }
        let salt = h[off + 2..off + 18].to_vec();
        let wrap = h[off + 18..off + 78].to_vec();
        off += 78;
        (salt, wrap, 0u32)
    } else if method == 1 {
        if h.len() < off + 80 {
            return Err("could not read that config".into());
        }
        let iters = u32be(h, off)?;
        let salt = h[off + 4..off + 20].to_vec();
        let wrap = h[off + 20..off + 80].to_vec();
        off += 80;
        (salt, wrap, iters)
    } else {
        return Err("recipient key required".into());
    };
    if h.len() < off + 4 {
        return Err("could not read that config".into());
    }
    let meta_len = u32be(h, off)? as usize;
    let meta_blob = h.get(off + 4..off + 4 + meta_len).ok_or("could not read that config")?;
    let prefix = &h[..off];
    let nonce_off = 9 + hdr_len;
    if data.len() < nonce_off + 16 {
        return Err("could not read that config".into());
    }
    let nonce = &data[nonce_off..nonce_off + 12];
    let body_len = u32be(data, nonce_off + 12)? as usize;
    let body = data.get(nonce_off + 16..nonce_off + 16 + body_len).ok_or("could not read that config")?;
    let kdk = if method == 2 {
        let a16 = gen2_a16(&salt)?;
        let mut hasher = Sha256::new();
        hasher.update(b"npvtunnel/appkey/v2 ");
        hasher.update(a16);
        hasher.update(config_id);
        hasher.finalize().to_vec()
    } else {
        if password.is_empty() {
            return Err("password required".into());
        }
        let mut derived = [0u8; 32];
        pbkdf2_hmac::<Sha256>(password.as_bytes(), &salt, iters, &mut derived);
        derived.to_vec()
    };
    let dek = aead_open(&kdk, &wrap[..12], &salt, &wrap[12..]).map_err(|_| {
        if method == 1 { "wrong password".to_string() } else { "could not read that config".to_string() }
    })?;
    let mut notes = Vec::new();
    if let Ok(meta_key) = hkdf32(nonce, &dek, b"NPVS-v5/metadata") {
        if let Ok(meta) = aead_open(&meta_key, nonce, prefix, meta_blob) {
            if let Ok(value) = serde_json::from_slice::<Value>(&meta) {
                notes.extend(policy_notes(value.get("policy")));
            }
        }
    }
    if body.len() < 38 || &body[..4] != b"NPF\x01" {
        return Err("could not read that config".into());
    }
    let content_id = &body[4..36];
    let count = u16be(body, 36)? as usize;
    let mut fields = HashMap::new();
    let mut cursor = 38usize;
    for _ in 0..count {
        if cursor + 6 > body.len() {
            break;
        }
        let seq = u16be(body, cursor)? as u32;
        let blob_len = u16be(body, cursor + 4)? as usize;
        let blob = body.get(cursor + 6..cursor + 6 + blob_len).unwrap_or_default();
        cursor += 6 + blob_len;
        let info = {
            let mut info = b"NPV-fields-v1/field/".to_vec();
            info.extend_from_slice(&(seq as u16).to_be_bytes());
            info
        };
        let Ok(field_key) = hkdf32(content_id, &dek, &info) else { continue };
        let pt_len = blob.len().saturating_sub(16);
        let mut aad = b"NPV-fields-v1/record/".to_vec();
        aad.extend_from_slice(content_id);
        aad.extend_from_slice(&(seq as u16).to_be_bytes());
        aad.extend_from_slice(&(pt_len as u32).to_be_bytes());
        if let Ok(pt) = aead_open(&field_key, &[0u8; 12], &aad, blob) {
            fields.insert(seq, pt);
        }
    }
    let mut nodes = Vec::new();
    if let Some(raw) = fields.get(&0xFFFFu32) {
        if let Ok(spec) = serde_json::from_slice::<Value>(raw) {
            let configs = spec.get("configs").and_then(|v| v.as_array()).cloned().unwrap_or_else(|| vec![spec]);
            for cfg in configs {
                let subbed = gen2_substitute(&cfg, &fields);
                nodes.extend(nodes_from_value(&subbed));
            }
        }
    }
    if nodes.is_empty() {
        for (seq, raw) in &fields {
            if *seq == 0xFFFF {
                continue;
            }
            absorb_plain(raw, &mut nodes, &mut notes);
        }
    }
    if nodes.is_empty() {
        return Err("could not read that config".into());
    }
    Ok(NpvOpened { nodes, notice: unique_notice(notes) })
}

fn open_value(value: Value, notice: &str) -> Result<NpvOpened, String> {
    let value = walk_sentinels(value);
    let mut notes = policy_notes(Some(&value));
    if !notice.is_empty() {
        notes.insert(0, notice.to_string());
    }
    let nodes = nodes_from_value(&value);
    if nodes.is_empty() {
        return Err("could not read that config".into());
    }
    Ok(NpvOpened { nodes, notice: unique_notice(notes) })
}

fn absorb_plain(plain: &[u8], nodes: &mut Vec<Value>, notes: &mut Vec<String>) {
    let text = decode_sentinels(&String::from_utf8_lossy(plain));
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return;
    }
    if let Ok(value) = serde_json::from_str::<Value>(trimmed) {
        let value = walk_sentinels(value);
        collect_notes(&value, notes);
        nodes.extend(nodes_from_value(&value));
        return;
    }
    nodes.extend(crate::parser::parse_text_inner(trimmed));
}

fn nodes_from_value(value: &Value) -> Vec<Value> {
    if let Some(items) = value.as_array() {
        return items.iter().flat_map(nodes_from_value).collect();
    }
    let Some(obj) = value.as_object() else { return Vec::new() };
    let mut out = Vec::new();
    if obj.contains_key("outbounds") || obj.contains_key("endpoints") {
        if let Ok(text) = serde_json::to_string(value) {
            out.extend(crate::parser::parse_text_inner(&text));
        }
    }
    if let Some(raw) = obj.get("v2rayJson").and_then(|v| v.as_str()) {
        out.extend(crate::parser::parse_text_inner(raw));
    }
    if let Some(configs) = obj.get("configs").and_then(|v| v.as_array()) {
        for cfg in configs {
            out.extend(nodes_from_value(cfg));
        }
    }
    if out.is_empty() {
        for link in profile_links(value) {
            if let Ok(node) = crate::parser::parse_link(&link) {
                let address = node["address"].as_str().unwrap_or("");
                let protocol = node["protocol"].as_str().unwrap_or("");
                if !address.is_empty() || matches!(protocol, "ssh" | "socks" | "http") {
                    out.push(node);
                }
            }
        }
    }
    out
}

fn profile_links(item: &Value) -> Vec<String> {
    let Some(obj) = item.as_object() else { return Vec::new() };
    let remark = first_str(obj, &["name", "remarks", "remark", "ps"]).unwrap_or_else(|| "NPV".into());
    if let Some(profile) = obj.get("v2rayProfile").and_then(coerce_json) {
        if let Some(link) = v2ray_profile_link(&remark, obj.get("address").map(as_text).unwrap_or_default().as_str(), &profile) {
            return vec![link];
        }
    }
    if let Some(ssh) = obj.get("sshConfig").and_then(coerce_json) {
        if let Some(link) = ssh_link(&remark, &ssh) {
            return vec![link];
        }
    }
    for kind in ["socksConfig", "socksProfile", "httpConfig", "httpProfile", "proxyConfig"] {
        if let Some(proxy) = obj.get(kind).and_then(coerce_json) {
            if let Some(link) = proxy_link(&remark, obj.get("address").map(as_text).unwrap_or_default().as_str(), kind, &proxy) {
                return vec![link];
            }
        }
    }
    legacy_link(&remark, item).into_iter().collect()
}

fn v2ray_profile_link(remark: &str, address: &str, profile: &Value) -> Option<String> {
    let Some(map) = profile.as_object() else { return None };
    let host = first_str(map, &["server", "address", "host"]).filter(|v| !v.is_empty()).unwrap_or_else(|| address.to_string());
    let port = first_str(map, &["serverPort", "port"]).and_then(|v| v.parse().ok()).unwrap_or(0u16);
    if host.is_empty() || port == 0 {
        return None;
    }
    let kind = map.get("configType").and_then(|v| as_text(v).parse::<i64>().ok()).unwrap_or(0);
    let own = first_str(map, &["remarks", "remark"]).unwrap_or_else(|| remark.to_string());
    match kind {
        1 => Some(vmess_link(&host, port, &own, map)),
        3 => Some(ss_link(&host, port, &own, map)),
        5 => Some(vless_link(&host, port, &own, map)),
        6 => Some(trojan_link(&host, port, &own, map)),
        _ => legacy_link(&own, profile),
    }
}

fn vless_link(host: &str, port: u16, remark: &str, map: &Map<String, Value>) -> String {
    let mut q = stream_query(map);
    let method = first_str(map, &["method", "encryption"]).unwrap_or_default();
    q.push(("encryption".into(), if method.trim().is_empty() { "none".into() } else { method }));
    if let Some(flow) = first_str(map, &["flow"]).filter(|v| !v.is_empty()) {
        q.push(("flow".into(), flow));
    }
    let id = first_str(map, &["password", "id", "uuid"]).unwrap_or_default();
    format!("vless://{}@{}?{}#{}", qenc(&id), hostport(host, port), form(&q), qenc(remark))
}

fn trojan_link(host: &str, port: u16, remark: &str, map: &Map<String, Value>) -> String {
    let mut q = stream_query(map);
    if let Some(flow) = first_str(map, &["flow"]).filter(|v| !v.is_empty()) {
        q.push(("flow".into(), flow));
    }
    let password = first_str(map, &["password"]).unwrap_or_default();
    format!("trojan://{}@{}?{}#{}", qenc(&password), hostport(host, port), form(&q), qenc(remark))
}

fn vmess_link(host: &str, port: u16, remark: &str, map: &Map<String, Value>) -> String {
    let network = first_str(map, &["network"]).unwrap_or_else(|| "tcp".into());
    let mut header = first_str(map, &["headerType"]).unwrap_or_else(|| "none".into());
    let mut host_header = first_str(map, &["host"]).unwrap_or_default();
    let mut path = first_str(map, &["path"]).unwrap_or_default();
    if network == "kcp" && path.is_empty() {
        path = first_str(map, &["seed"]).unwrap_or_default();
    } else if network == "grpc" {
        header = first_str(map, &["mode"]).unwrap_or_default();
        if path.is_empty() {
            path = first_str(map, &["serviceName"]).unwrap_or_default();
        }
        if host_header.is_empty() {
            host_header = first_str(map, &["authority"]).unwrap_or_default();
        }
    }
    let security = first_str(map, &["security"]).unwrap_or_default();
    let tls = if security == "tls" || security == "reality" { "tls" } else { "" };
    let insecure = if security == "tls" && truthy(map, &["tlsAllowInsecure", "insecure"]) { "1" } else { "" };
    let method = first_str(map, &["method"]).filter(|v| !v.is_empty()).unwrap_or_else(|| "auto".into());
    let obj = json!({
        "v": "2",
        "ps": remark,
        "add": host,
        "port": port.to_string(),
        "id": first_str(map, &["password", "id", "uuid"]).unwrap_or_default(),
        "aid": first_str(map, &["alterId"]).unwrap_or_else(|| "0".into()),
        "scy": method,
        "net": network,
        "type": header,
        "host": host_header,
        "path": path,
        "tls": tls,
        "sni": first_str(map, &["sni"]).unwrap_or_default(),
        "fp": first_str(map, &["fingerPrint", "fp"]).unwrap_or_default(),
        "alpn": first_str(map, &["alpn"]).unwrap_or_default(),
        "insecure": insecure
    });
    format!("vmess://{}", b64_std(obj.to_string().as_bytes()))
}

fn ss_link(host: &str, port: u16, remark: &str, map: &Map<String, Value>) -> String {
    let method = first_str(map, &["method"]).filter(|v| !v.is_empty()).unwrap_or_else(|| "aes-256-gcm".into());
    let password = first_str(map, &["password"]).unwrap_or_default();
    let user = b64_std(format!("{method}:{password}").as_bytes());
    format!("ss://{user}@{}#{}", hostport(host, port), qenc(remark))
}

fn ssh_link(remark: &str, ssh: &Value) -> Option<String> {
    let map = ssh.as_object()?;
    let host = first_str(map, &["sshHost", "server", "host"])?;
    if host.is_empty() {
        return None;
    }
    let port = first_str(map, &["sshPort", "port"]).and_then(|v| v.parse().ok()).unwrap_or(22u16);
    let user = first_str(map, &["sshUsername", "username"]).unwrap_or_default();
    let password = first_str(map, &["sshPassword", "password"]).unwrap_or_default();
    Some(format!("ssh://{}:{}@{}#{}", qenc(&user), qenc(&password), hostport(&host, port), qenc(remark)))
}

fn proxy_link(remark: &str, address: &str, kind: &str, proxy: &Value) -> Option<String> {
    let map = proxy.as_object()?;
    let scheme = if kind.to_ascii_lowercase().contains("http") { "http" } else { "socks" };
    let host = first_str(map, &["server", "host"]).filter(|v| !v.is_empty()).unwrap_or_else(|| address.to_string());
    if host.is_empty() {
        return None;
    }
    let port = first_str(map, &["serverPort", "port", "localPort"]).and_then(|v| v.parse().ok()).unwrap_or(if scheme == "http" { 80 } else { 1080 });
    let user = first_str(map, &["username"]).unwrap_or_default();
    let password = first_str(map, &["password"]).unwrap_or_default();
    let auth = if !user.is_empty() { format!("{}:{}@", qenc(&user), qenc(&password)) } else if !password.is_empty() { format!("{}@", qenc(&password)) } else { String::new() };
    Some(format!("{scheme}://{auth}{}#{}", hostport(&host, port), qenc(remark)))
}

fn legacy_link(remark: &str, item: &Value) -> Option<String> {
    let map = item.as_object()?;
    let host = first_str(map, &["server", "address", "host", "add"]).filter(|v| !v.is_empty())?;
    let port = first_str(map, &["serverPort", "port"]).and_then(|v| v.parse().ok()).unwrap_or(443u16);
    let proto = first_str(map, &["protocol", "type"]).unwrap_or_default().to_ascii_lowercase();
    if proto.contains("ss") || proto.contains("shadowsocks") {
        return Some(ss_link(&host, port, remark, map));
    }
    if proto.contains("trojan") || (map.contains_key("password") && !map.contains_key("uuid") && !map.contains_key("id")) {
        return Some(trojan_link(&host, port, remark, map));
    }
    if proto.contains("vless") || map.contains_key("uuid") || map.contains_key("flow") {
        return Some(vless_link(&host, port, remark, map));
    }
    if proto.contains("vmess") || map.contains_key("id") {
        return Some(vmess_link(&host, port, remark, map));
    }
    if proto.contains("ssh") {
        return ssh_link(remark, item);
    }
    None
}

fn stream_query(map: &Map<String, Value>) -> Vec<(String, String)> {
    let network = first_str(map, &["network", "net"]).filter(|v| !v.is_empty()).unwrap_or_else(|| "tcp".into());
    let security = first_str(map, &["security"]).filter(|v| !v.is_empty()).unwrap_or_else(|| "none".into());
    let mut q = vec![("type".into(), network.clone()), ("security".into(), security.clone())];
    let mut host = first_str(map, &["host"]).unwrap_or_default();
    if host.is_empty() {
        host = first_str(map, &["authority"]).unwrap_or_default();
    }
    push_q(&mut q, "sni", first_str(map, &["sni", "peer", "servername"]));
    push_q(&mut q, "fp", first_str(map, &["fingerPrint", "fp"]));
    push_q(&mut q, "alpn", first_str(map, &["alpn"]));
    push_q(&mut q, "host", Some(host));
    push_q(&mut q, "path", first_str(map, &["path"]));
    push_q(&mut q, "serviceName", first_str(map, &["serviceName"]));
    push_q(&mut q, "headerType", first_str(map, &["headerType"]));
    push_q(&mut q, "pbk", first_str(map, &["publicKey", "pbk"]));
    push_q(&mut q, "sid", first_str(map, &["shortId", "sid"]));
    push_q(&mut q, "spx", first_str(map, &["spiderX", "spx"]));
    push_q(&mut q, "mode", first_str(map, &["xhttpMode", "mode"]));
    push_q(&mut q, "extra", first_str(map, &["xhttpExtra", "extra"]));
    push_q(&mut q, "x_padding", first_str(map, &["xPaddingBytes", "x_padding"]));
    if network == "kcp" {
        push_q(&mut q, "path", first_str(map, &["seed"]));
    }
    if security == "tls" && truthy(map, &["tlsAllowInsecure", "insecure"]) {
        q.push(("allowInsecure".into(), "1".into()));
    }
    q
}

fn push_q(q: &mut Vec<(String, String)>, key: &str, value: Option<String>) {
    if let Some(value) = value.filter(|v| !v.is_empty()) {
        if !q.iter().any(|(k, _)| k == key) {
            q.push((key.into(), value));
        }
    }
}

fn form(pairs: &[(String, String)]) -> String {
    pairs.iter().filter(|(_, v)| !v.is_empty()).map(|(k, v)| format!("{}={}", qenc(k), qenc(v))).collect::<Vec<_>>().join("&")
}

fn hostport(host: &str, port: u16) -> String {
    if host.contains(':') { format!("[{host}]:{port}") } else { format!("{host}:{port}") }
}

fn first_str(map: &Map<String, Value>, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| map.get(*key).map(as_text).filter(|v| !v.is_empty()))
}

fn as_text(value: &Value) -> String {
    match value {
        Value::String(text) => decode_sentinels(text),
        Value::Number(n) => n.to_string(),
        Value::Bool(true) => "true".into(),
        Value::Bool(false) => "false".into(),
        _ => String::new(),
    }
}

fn truthy(map: &Map<String, Value>, keys: &[&str]) -> bool {
    first_str(map, keys).map(|v| matches!(v.to_ascii_lowercase().as_str(), "1" | "true" | "yes" | "on")).unwrap_or(false)
}

fn coerce_json(value: &Value) -> Option<Value> {
    if value.is_object() || value.is_array() {
        return Some(walk_sentinels(value.clone()));
    }
    let text = value.as_str()?.trim();
    if text.starts_with('{') || text.starts_with('[') {
        return serde_json::from_str::<Value>(text).ok().map(walk_sentinels);
    }
    None
}

fn parse_json_text(text: &str) -> Result<Value, String> {
    let decoded = decode_sentinels(text);
    serde_json::from_str(&decoded).map(walk_sentinels).map_err(|_| "could not read that config".to_string())
}

fn collect_notes(value: &Value, notes: &mut Vec<String>) {
    notes.extend(policy_notes(Some(value)));
    if let Some(policy) = value.get("policy") {
        notes.extend(policy_notes(Some(policy)));
    }
    if let Some(lock) = value.get("lockConfig") {
        notes.extend(policy_notes(Some(lock)));
        push_expiry(lock, notes);
    }
    push_expiry(value, notes);
    if let Some(items) = value.as_array() {
        for item in items {
            collect_notes(item, notes);
        }
    }
}

fn push_expiry(value: &Value, notes: &mut Vec<String>) {
    for key in ["expiryDate", "expire", "expiry"] {
        let text = value.get(key).map(as_text).unwrap_or_default();
        if text.is_empty() || text == "0" || text == "null" {
            continue;
        }
        let line = format!("expires {text}");
        if !notes.iter().any(|note| note == &line) {
            notes.push(line);
        }
    }
}

fn unique_notice(notes: Vec<String>) -> String {
    let mut out = Vec::new();
    for note in notes {
        let note = note.trim();
        if !note.is_empty() && !out.iter().any(|existing: &String| existing == note) {
            out.push(note.to_string());
        }
    }
    out.join("\n")
}

fn policy_notes(value: Option<&Value>) -> Vec<String> {
    let Some(value) = value else { return Vec::new() };
    let mut notes = Vec::new();
    for key in ["displayMessage", "customServerMessage", "message"] {
        if let Some(text) = value.get(key).and_then(|v| v.as_str()) {
            let text = text.trim();
            if !text.is_empty() {
                notes.push(text.to_string());
            }
        }
    }
    notes
}

fn gen2_substitute(value: &Value, fields: &HashMap<u32, Vec<u8>>) -> Value {
    if let Some(seq) = value.as_i64().or_else(|| value.as_u64().map(|n| n as i64)).or_else(|| value.as_f64().map(|n| n as i64)) {
        if seq < 0 {
            return Value::String(String::new());
        }
        let raw = fields.get(&(seq as u32)).map(|v| v.as_slice()).unwrap_or(b"");
        return Value::String(decode_sentinels(&field_text(raw)));
    }
    match value {
        Value::Object(map) => Value::Object(map.iter().map(|(k, v)| (k.clone(), gen2_substitute(v, fields))).collect()),
        Value::Array(items) => Value::Array(items.iter().map(|v| gen2_substitute(v, fields)).collect()),
        other => other.clone(),
    }
}

fn field_text(raw: &[u8]) -> String {
    let text = String::from_utf8_lossy(raw).trim().to_string();
    if text.len() >= 2 && text.starts_with('"') && text.ends_with('"') {
        if let Ok(Value::String(inner)) = serde_json::from_str(&text) {
            return inner;
        }
        return text[1..text.len() - 1].to_string();
    }
    text
}

fn walk_sentinels(value: Value) -> Value {
    match value {
        Value::String(text) => Value::String(decode_sentinels(&text)),
        Value::Array(items) => Value::Array(items.into_iter().map(walk_sentinels).collect()),
        Value::Object(map) => Value::Object(map.into_iter().map(|(k, v)| (k, walk_sentinels(v))).collect()),
        other => other,
    }
}

fn decode_sentinels(text: &str) -> String {
    let prefix = "npvs1:";
    if !text.contains(prefix) {
        return text.to_string();
    }
    let mut rest = text;
    let mut out = String::new();
    while let Some(idx) = rest.find(prefix) {
        out.push_str(&rest[..idx]);
        rest = &rest[idx + prefix.len()..];
        let end = rest.find(|c: char| !SENTINEL_ALPHABET.contains(c)).unwrap_or(rest.len());
        let token = &rest[..end];
        rest = &rest[end..];
        if let Some(decoded) = sentinel_token(token) {
            out.push_str(&decoded);
        } else {
            out.push_str(prefix);
            out.push_str(token);
        }
    }
    out.push_str(rest);
    out
}

fn sentinel_token(token: &str) -> Option<String> {
    for pad in ["", "=", "==", "==="] {
        let padded = format!("{token}{pad}");
        if let Some(bytes) = crate::parser::base64_decode(&padded) {
            return Some(String::from_utf8_lossy(&bytes).into_owned());
        }
        let url = padded.replace('-', "+").replace('_', "/");
        if let Some(bytes) = crate::parser::base64_decode(&url) {
            return Some(String::from_utf8_lossy(&bytes).into_owned());
        }
    }
    None
}

fn custodian_kdks(salt: &[u8]) -> Vec<[u8; 32]> {
    let tables = tables();
    let variants = [&tables.tbl_v1, &tables.tbl];
    let mut material = [0u8; 32];
    let n = salt.len().min(16);
    material[..n].copy_from_slice(&salt[..n]);
    variants.iter().map(|tbl| {
        let stream = wb_ctr(&tables.ty, &tables.mbl, &tables.xt, tbl, &material[..16], &material[16..]);
        let mut hasher = Sha256::new();
        hasher.update(b"npvtunnel/appkey/v1 ");
        hasher.update(stream);
        hasher.finalize().into()
    }).collect()
}

fn gen2_a16(salt: &[u8]) -> Result<[u8; 16], String> {
    let tables = gen2_tables();
    let mut state = [0u8; 16];
    let n = salt.len().min(16);
    state[..n].copy_from_slice(&salt[..n]);
    for block_index in 0..13 {
        let block = &tables[block_index * 57344..(block_index + 1) * 57344];
        let mut shifted = [0u8; 16];
        for i in 0..16 {
            shifted[i] = state[SHIFT[i]];
        }
        state = shifted;
        let mut words: Vec<u32> = state.iter().map(|b| *b as u32).collect();
        for j in 0..4 {
            gen2_group(&mut words, block, j)?;
        }
        for i in 0..16 {
            state[i] = words[i] as u8;
        }
    }
    let page = &tables[13 * 57344..];
    let mut out = [0u8; 16];
    for i in 0..16 {
        let idx = 0x100 * i + state[SHIFT[i]] as usize;
        out[i] = *page.get(idx).ok_or("could not read that config")?;
    }
    Ok(out)
}

fn gen2_group(state: &mut [u32], block: &[u8], j: usize) -> Result<(), String> {
    let s = [state[4 * j], state[4 * j + 1], state[4 * j + 2], state[4 * j + 3]];
    let base1 = 0x6000 + 0x1000 * j;
    let args1 = [
        be32(block, base1 + 4 * s[0] as usize)?,
        be32(block, base1 + 0x400 + 4 * s[1] as usize)?,
        be32(block, base1 + 0x800 + 4 * s[2] as usize)?,
        be32(block, base1 + 0xC00 + 4 * s[3] as usize)?,
    ];
    let w1 = gen2_sub(block, j as u32, args1[0], args1[1], args1[2], args1[3])?;
    let base2 = 0xA000 + 0x1000 * j;
    let args2 = [
        be32(block, base2 + 4 * w1[0] as usize)?,
        be32(block, base2 + 0x400 + 4 * w1[1] as usize)?,
        be32(block, base2 + 0x800 + 4 * w1[2] as usize)?,
        be32(block, base2 + 0xC00 + 4 * w1[3] as usize)?,
    ];
    let w2 = gen2_sub(block, j as u32, args2[0], args2[1], args2[2], args2[3])?;
    state[4 * j..4 * j + 4].copy_from_slice(&w2);
    Ok(())
}

fn gen2_sub(block: &[u8], i: u32, x3: u32, x4: u32, x5: u32, x6: u32) -> Result<[u32; 4], String> {
    let at = |addr: u32| -> Result<u32, String> {
        block.get(addr as usize).copied().map(|b| b as u32).ok_or_else(|| "could not read that config".to_string())
    };
    let x2 = i;
    let mut x8 = x2.wrapping_add(x2.wrapping_shl(1));
    let mut x12 = x3 >> 0x14;
    let mut x11 = x3 >> 0x18;
    let mut x13 = (x4 >> 0x18) & 0xF;
    let mut x14 = x5 >> 0x18;
    let mut x10 = x6;
    let mut x9 = x8 << 3;
    x8 = x4;
    x12 &= 0xF0;
    x12 = x12.wrapping_add(x13);
    x13 = x5 >> 0x14;
    let mut x16 = x8 >> 0x1C;
    x11 &= 0xF0;
    x14 &= 0xF0;
    let mut x15 = (x6 >> 0x18) & 0xF;
    x13 &= 0xF0;
    let mut x17 = x3 >> 0x10;
    x9 <<= 8;
    x8 &= 0xF;
    x13 = x13.wrapping_add(x15);
    x17 &= 0xF0;
    x11 = x9.wrapping_add(x11);
    x14 = x9.wrapping_add(x14);
    x12 = x9.wrapping_add(x12);
    x16 = at(x11.wrapping_add(x16))?;
    x14 = x14.wrapping_add(x10 >> 28);
    x12 = at(x12.wrapping_add(0x200))?;
    x13 = x9.wrapping_add(x13);
    let mut x0 = (x6 >> 0x14) & 0xF;
    x14 = at(x14.wrapping_add(0x100))?;
    x15 = x9.wrapping_add(x16 << 4);
    x13 = at(x13.wrapping_add(0x300))?;
    x12 = x9.wrapping_add(x12 << 4);
    x16 = (x4 >> 0x14) & 0xF;
    x10 &= 0xF;
    x14 = x15.wrapping_add(x14);
    x15 = x5 >> 0x10;
    x12 = x12.wrapping_add(x13);
    x13 = x3 >> 0xC;
    x14 = at(x14.wrapping_add(0x400))?;
    x12 = at(x12.wrapping_add(0x500))?;
    x15 &= 0xF0;
    x16 = x17.wrapping_add(x16);
    x15 = x15.wrapping_add(x0);
    x0 = (x4 >> 0x10) & 0xF;
    x17 = x5 >> 0xC;
    x12 |= x14 << 4;
    x13 &= 0xF0;
    x14 = (x6 >> 0x10) & 0xF;
    x13 = x13.wrapping_add(x0);
    x17 &= 0xF0;
    x16 = x9.wrapping_add(x16);
    let out0 = x12 & 0xFF;
    x13 = x9.wrapping_add(x13);
    x12 = x17.wrapping_add(x14);
    x14 = at(x16.wrapping_add(0x600))?;
    x13 = at(x13.wrapping_add(0x800))?;
    x15 = x9.wrapping_add(x15);
    x12 = x9.wrapping_add(x12);
    x15 = at(x15.wrapping_add(0x700))?;
    x16 = x5 >> 8;
    x12 = at(x12.wrapping_add(0x900))?;
    x14 = x9.wrapping_add(x14 << 4);
    x13 = x9.wrapping_add(x13 << 4);
    x0 = (x6 >> 0xC) & 0xF;
    x17 = x3 >> 8;
    x14 = x14.wrapping_add(x15);
    x12 = x13.wrapping_add(x12);
    x13 = x16 & 0xF0;
    x14 = at(x14.wrapping_add(0xA00))?;
    x12 = at(x12.wrapping_add(0xB00))?;
    x15 = x3 >> 4;
    x13 = x13.wrapping_add(x0);
    x0 = (x4 >> 8) & 0xF;
    x16 = (x4 >> 0xC) & 0xF;
    x12 |= x14 << 4;
    x14 = x15 & 0xF0;
    x17 &= 0xF0;
    x14 = x14.wrapping_add(x0);
    x15 = x9.wrapping_add(0xC00);
    x0 = x5 >> 4;
    x17 = x15.wrapping_add(x17);
    let out1 = x12 & 0xFF;
    x12 = (x6 >> 8) & 0xF;
    x16 = at(x17.wrapping_add(x16))?;
    x14 = x9.wrapping_add(x14);
    x17 = x0 & 0xF0;
    x14 = at(x14.wrapping_add(0xE00))?;
    x12 = x17.wrapping_add(x12);
    x13 = x15.wrapping_add(x13);
    x12 = x9.wrapping_add(x12);
    x13 = at(x13.wrapping_add(0x100))?;
    x15 = x9.wrapping_add(x16 << 4);
    x12 = at(x12.wrapping_add(0xF00))?;
    x14 = x9.wrapping_add(x14 << 4);
    x16 = 0x1000;
    x13 = x15.wrapping_add(x13);
    x17 = (x6 >> 4) & 0xF;
    x0 = x5 & 0xF0;
    x12 = x14.wrapping_add(x12);
    x14 = 0x1100;
    x13 = at(x13.wrapping_add(x16))?;
    x12 = at(x12.wrapping_add(x14))?;
    x14 = 0x1200;
    x15 = (x4 >> 4) & 0xF;
    x16 = x3 & 0xF0;
    x17 = x0.wrapping_add(x17);
    x14 = x9.wrapping_add(x14);
    x12 |= x13 << 4;
    x13 = (x3 & 0xF) << 4;
    x16 = x14.wrapping_add(x16);
    let out2 = x12 & 0xFF;
    x8 = x13.wrapping_add(x8);
    x12 = x14.wrapping_add(x17);
    x14 = (x5 & 0xF) << 4;
    x13 = at(x16.wrapping_add(x15))?;
    x8 = x9.wrapping_add(x8);
    x15 = 0x1400;
    x12 = at(x12.wrapping_add(0x100))?;
    x8 = at(x8.wrapping_add(x15))?;
    x10 = x14.wrapping_add(x10);
    x14 = 0x1500;
    x10 = x9.wrapping_add(x10);
    x13 = x9.wrapping_add(x13 << 4);
    x10 = at(x10.wrapping_add(x14))?;
    x8 = x9.wrapping_add(x8 << 4);
    x9 = x13.wrapping_add(x12);
    x12 = 0x1600;
    x8 = x8.wrapping_add(x10);
    x10 = 0x1700;
    x9 = at(x9.wrapping_add(x12))?;
    x8 = at(x8.wrapping_add(x10))?;
    x8 |= x9 << 4;
    let out3 = x8 & 0xFF;
    Ok([out0, out1, out2, out3])
}

fn wb_ctr(ty: &[u32], mbl: &[u32], xt: &[u8], tbl: &[u8], nonce: &[u8], data: &[u8]) -> Vec<u8> {
    let mut counter = [0u8; 16];
    let n = nonce.len().min(16);
    counter[..n].copy_from_slice(&nonce[..n]);
    let mut out = vec![0u8; data.len()];
    let mut off = 0;
    while off < data.len() {
        let ks = wb_core(ty, mbl, xt, tbl, &counter);
        for i in (0..16).rev() {
            counter[i] = counter[i].wrapping_add(1);
            if counter[i] != 0 {
                break;
            }
        }
        let end = (off + 16).min(data.len());
        for (i, byte) in data[off..end].iter().enumerate() {
            out[off + i] = byte ^ ks[i];
        }
        off += 16;
    }
    out
}

fn wb_core(ty: &[u32], mbl: &[u32], xt: &[u8], tbl: &[u8], block: &[u8]) -> [u8; 16] {
    let mut buf = [0u32; 16];
    for i in 0..16.min(block.len()) {
        buf[i] = block[i] as u32;
    }
    buf = shift_buf(buf);
    for i11 in 0..4 {
        let i13 = i11 * 4;
        let (ic, ic2, ic3, ic4) = (
            table_u32(ty, i13 * 256 + buf[i13] as usize),
            table_u32(ty, (i13 + 1) * 256 + buf[i13 + 1] as usize),
            table_u32(ty, (i13 + 2) * 256 + buf[i13 + 2] as usize),
            table_u32(ty, (i13 + 3) * 256 + buf[i13 + 3] as usize),
        );
        mix_round(xt, &mut buf, i11, i13, ic, ic2, ic3, ic4, false);
        let (ic5, ic6, ic7, ic8) = (
            table_u32(mbl, i13 * 256 + buf[i13] as usize),
            table_u32(mbl, (i13 + 1) * 256 + buf[i13 + 1] as usize),
            table_u32(mbl, (i13 + 2) * 256 + buf[i13 + 2] as usize),
            table_u32(mbl, (i13 + 3) * 256 + buf[i13 + 3] as usize),
        );
        mix_round(xt, &mut buf, i11, i13, ic5, ic6, ic7, ic8, true);
    }
    buf = shift_buf(buf);
    let mut out = [0u8; 16];
    for i in 0..16 {
        out[i] = tbl.get(i * 256 + buf[i] as usize).copied().unwrap_or(0);
    }
    out
}

fn mix_round(xt: &[u8], buf: &mut [u32; 16], i11: usize, i13: usize, c1: u32, c2: u32, c3: u32, c4: u32, mbl: bool) {
    for step in 0..4 {
        let i18 = i11 * 24 + step * 6;
        let shift_hi = 28 - step * 8;
        let shift_lo = 24 - step * 8;
        let n1 = ((c1 >> shift_hi) & 15) as usize;
        let n2 = ((c2 >> shift_hi) & 15) as usize;
        let n3 = ((c3 >> shift_hi) & 15) as usize;
        let n4 = ((c4 >> shift_hi) & 15) as usize;
        let b10 = xt_at(xt, (i18 * 16 + n1) * 16 + n2) as usize;
        let b11 = xt_at(xt, (i18 * 16 + n3) * 16 + n4) as usize;
        let m1 = ((c1 >> shift_lo) & 15) as usize;
        let m2 = ((c2 >> shift_lo) & 15) as usize;
        let m3 = ((c3 >> shift_lo) & 15) as usize;
        let m4 = ((c4 >> shift_lo) & 15) as usize;
        let lo = xt_at(xt, (i18 + 5) * 256 + xt_at(xt, (i18 + 2) * 256 + m1 * 16 + m2) as usize * 16 + xt_at(xt, (i18 + 3) * 256 + m3 * 16 + m4) as usize) as u32;
        let hi = xt_at(xt, (i18 + 4) * 256 + b10 * 16 + b11) as u32;
        buf[i13 + step] = if mbl { (hi << 4) | lo } else { lo | (hi << 4) };
    }
}

fn shift_buf(buf: [u32; 16]) -> [u32; 16] {
    let mut out = [0u32; 16];
    for i in 0..16 {
        out[i] = buf[SHIFT[i]];
    }
    out
}

fn xt_at(xt: &[u8], index: usize) -> u8 {
    xt.get(index).copied().unwrap_or(0)
}

fn table_u32(table: &[u32], index: usize) -> u32 {
    table.get(index).copied().unwrap_or(0)
}

fn tables() -> &'static Tables {
    static TABLES: OnceLock<Tables> = OnceLock::new();
    TABLES.get_or_init(|| {
        let raw: Value = serde_json::from_slice(include_bytes!("../data/npv_tables.json")).expect("npv tables");
        let column = |key: &str| -> Vec<u32> {
            raw[key]["data"].as_array().map(|items| items.iter().filter_map(|v| v.as_u64().map(|n| n as u32)).collect()).unwrap_or_default()
        };
        let bytes = |key: &str| -> Vec<u8> { column(key).into_iter().map(|n| n as u8).collect() };
        let v1 = if raw["tboxesLastV1"]["data"].as_array().is_some() { bytes("tboxesLastV1") } else { include_bytes!("../data/tboxes_last_v1.bin").to_vec() };
        Tables { ty: column("tyBoxes"), mbl: column("mbl"), xt: bytes("xorTable"), tbl: bytes("tboxesLast"), tbl_v1: v1 }
    })
}

fn gen2_tables() -> &'static [u8] {
    static TABLES: OnceLock<Vec<u8>> = OnceLock::new();
    TABLES.get_or_init(|| {
        let out = miniz_oxide::inflate::decompress_to_vec_zlib(include_bytes!("../data/gen2_tables.bin.z")).expect("gen2 tables");
        assert_eq!(out.len(), 13 * 57344 + 4096);
        out
    })
}

fn aead_open(key: &[u8], nonce: &[u8], aad: &[u8], data: &[u8]) -> Result<Vec<u8>, String> {
    if key.len() != 32 || nonce.len() != 12 {
        return Err("could not read that config".into());
    }
    let cipher = ChaCha20Poly1305::new_from_slice(key).map_err(|_| "could not read that config".to_string())?;
    cipher.decrypt(Nonce::from_slice(nonce), Payload { msg: data, aad }).map_err(|_| "could not read that config".to_string())
}

fn hkdf32(salt: &[u8], ikm: &[u8], info: &[u8]) -> Result<[u8; 32], String> {
    let hk = Hkdf::<Sha256>::new(Some(salt), ikm);
    let mut out = [0u8; 32];
    hk.expand(info, &mut out).map_err(|_| "could not read that config".to_string())?;
    Ok(out)
}

fn b64_any(text: &str) -> Result<Vec<u8>, String> {
    let std = text.trim().replace('-', "+").replace('_', "/");
    crate::parser::base64_decode(&std).ok_or_else(|| "could not read that config".to_string())
}

fn compact_npvs(text: &str) -> Option<Vec<u8>> {
    let compact: String = text.chars().filter(|c| !c.is_whitespace()).collect();
    if !compact.starts_with("TlBWUw") {
        return None;
    }
    let bytes = crate::parser::base64_decode(&compact)?;
    if bytes.starts_with(b"NPVS") { Some(bytes) } else { None }
}

fn u32be(data: &[u8], off: usize) -> Result<u32, String> {
    let s = data.get(off..off + 4).ok_or("could not read that config")?;
    Ok(u32::from_be_bytes([s[0], s[1], s[2], s[3]]))
}

fn u16be(data: &[u8], off: usize) -> Result<u16, String> {
    let s = data.get(off..off + 2).ok_or("could not read that config")?;
    Ok(u16::from_be_bytes([s[0], s[1]]))
}

fn be32(data: &[u8], off: usize) -> Result<u32, String> {
    u32be(data, off)
}

fn qenc(text: &str) -> String {
    let mut out = String::new();
    for byte in text.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(byte as char),
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

fn b64_std(data: &[u8]) -> String {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    let mut i = 0;
    while i + 3 <= data.len() {
        let n = ((data[i] as u32) << 16) | ((data[i + 1] as u32) << 8) | data[i + 2] as u32;
        out.push(T[((n >> 18) & 63) as usize] as char);
        out.push(T[((n >> 12) & 63) as usize] as char);
        out.push(T[((n >> 6) & 63) as usize] as char);
        out.push(T[(n & 63) as usize] as char);
        i += 3;
    }
    if i < data.len() {
        let left = data.len() - i;
        let mut n = (data[i] as u32) << 16;
        if left == 2 {
            n |= (data[i + 1] as u32) << 8;
        }
        out.push(T[((n >> 18) & 63) as usize] as char);
        out.push(T[((n >> 12) & 63) as usize] as char);
        if left == 2 {
            out.push(T[((n >> 6) & 63) as usize] as char);
            out.push('=');
        } else {
            out.push('=');
            out.push('=');
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn gen2_header(method: u8) -> Vec<u8> {
        let mut header = vec![0u8; 220];
        header[0] = 1;
        header[50] = method;
        if method == 1 {
            header[53..57].copy_from_slice(&1000u32.to_be_bytes());
            header[133..137].copy_from_slice(&0u32.to_be_bytes());
        }
        let mut data = b"NPVS".to_vec();
        data.push(5);
        data.extend_from_slice(&(header.len() as u32).to_be_bytes());
        data.extend_from_slice(&header);
        data.extend_from_slice(&[0u8; 16]);
        data
    }

    #[test]
    fn passphrase_without_password_is_explicit() {
        let err = open_bytes(&gen2_header(1), "").unwrap_err();
        assert_eq!(err, "password required");
    }

    #[test]
    fn recipient_key_is_rejected() {
        let err = open_bytes(&gen2_header(3), "").unwrap_err();
        assert_eq!(err, "recipient key required");
    }

    #[test]
    fn sentinel_roundtrip() {
        let token = b64_std(b"example.example");
        let text = decode_sentinels(&format!("before npvs1:{token} after"));
        assert_eq!(text, "before example.example after");
    }

    #[test]
    fn plain_links_are_not_npv() {
        assert!(!is_npv_text("vless://11111111-1111-1111-1111-111111111111@example.com:443"));
    }

    #[test]
    fn local_telegram_samples_keep_shape() {
        let mut seen = 0;
        for path in [
            "/Users/amirhossein/Downloads/Telegram Desktop/@XpnTeam-176.npvt",
            "/Users/amirhossein/Downloads/Telegram Desktop/@XpnTeam-266.npvs",
        ] {
            let Ok(bytes) = std::fs::read(path) else { continue };
            seen += 1;
            let opened = open_bytes(&bytes, "").unwrap_or_else(|err| panic!("{path}: {err}"));
            assert!(!opened.nodes.is_empty(), "{path} produced no profiles");
            for node in &opened.nodes {
                assert!(!node["protocol"].as_str().unwrap_or("").is_empty());
                assert!(node["port"].as_u64().unwrap_or(0) > 0);
                assert!(!node["address"].as_str().unwrap_or("").is_empty());
                assert_eq!(node["network"].as_str(), Some("ws"));
                assert_eq!(node["tls"].as_str(), Some("tls"));
                assert!(!node["host"].as_str().unwrap_or("").is_empty());
                assert!(!node["path"].as_str().unwrap_or("").is_empty());
                assert!(!node["sni"].as_str().unwrap_or("").is_empty());
            }
        }
        if std::path::Path::new("/Users/amirhossein/Downloads/Telegram Desktop/@XpnTeam-176.npvt").exists() {
            assert_eq!(seen, 2, "both local NPV samples should decode");
        }
    }
}
