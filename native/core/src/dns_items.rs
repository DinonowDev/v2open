use serde_json::{json, Value};

pub fn default_dns_items() -> Vec<Value> {
    vec![
        item("cloudflare-doh", "Cloudflare DoH", "https", "1.1.1.1", "/dns-query", true, "remote"),
        item("cloudflare-dot", "Cloudflare DoT", "tls", "1.1.1.1", "", true, "remote"),
        item("google-doh", "Google DoH", "https", "dns.google", "/dns-query", false, "remote"),
        item("ali-dns", "AliDNS", "udp", "223.5.5.5", "", true, "domestic"),
    ]
}

fn item(id: &str, name: &str, kind: &str, server: &str, path: &str, enabled: bool, role: &str) -> Value {
    json!({
        "id": id,
        "name": name,
        "type": kind,
        "server": server,
        "path": path,
        "addresses": [],
        "enabled": enabled,
        "role": role
    })
}

pub fn ensure_dns_items(settings: &mut Value) {
    if settings.get("dns_items").and_then(|v| v.as_array()).map(|a| !a.is_empty()) == Some(true) {
        return;
    }
    settings["dns_items"] = json!(default_dns_items());
    settings["remote_dns_id"] = json!("cloudflare-doh");
    settings["domestic_dns_id"] = json!("ali-dns");
    settings["enabledDnsServer"] = json!("cloudflare-doh");
    sync_legacy_dns(settings);
}

pub fn item_by_id<'a>(settings: &'a Value, id: &str) -> Option<&'a Value> {
    settings["dns_items"].as_array()?.iter().find(|i| i["id"].as_str() == Some(id))
}

pub fn item_to_uri(item: &Value) -> String {
    let kind = item["type"].as_str().unwrap_or("udp");
    let server = item["server"].as_str().unwrap_or("").trim();
    if server.is_empty() {
        return String::new();
    }
    match kind {
        "https" => {
            let path = item["path"].as_str().unwrap_or("/dns-query");
            let path = if path.starts_with('/') { path.to_string() } else { format!("/{path}") };
            if server.starts_with("http://") || server.starts_with("https://") {
                server.to_string()
            } else {
                format!("https://{server}{path}")
            }
        }
        "tls" => {
            if server.starts_with("tls://") {
                server.to_string()
            } else {
                format!("tls://{server}:853")
            }
        }
        "quic" => {
            if server.starts_with("quic://") {
                server.to_string()
            } else {
                format!("quic://{server}:853")
            }
        }
        _ => {
            if server.contains(':') {
                server.to_string()
            } else {
                server.to_string()
            }
        }
    }
}

pub fn sync_legacy_dns(settings: &mut Value) {
    let remote_id = settings["remote_dns_id"].as_str().unwrap_or("").to_string();
    let domestic_id = settings["domestic_dns_id"].as_str().unwrap_or("").to_string();
    if let Some(item) = item_by_id(settings, &remote_id) {
        let uri = item_to_uri(item);
        if !uri.is_empty() {
            settings["remote_dns"] = json!(uri);
        }
    }
    if let Some(item) = item_by_id(settings, &domestic_id) {
        let uri = item_to_uri(item);
        if !uri.is_empty() {
            settings["domestic_dns"] = json!(uri);
        }
    }
}

pub fn is_ip(raw: &str) -> bool {
    raw.parse::<std::net::IpAddr>().is_ok()
}

pub fn resolver_host(item: &Value) -> String {
    let server = item["server"].as_str().unwrap_or("").trim();
    if server.is_empty() {
        return String::new();
    }
    if server.starts_with("https://") || server.starts_with("http://") {
        let body = server.trim_start_matches("https://").trim_start_matches("http://");
        return body.split('/').next().unwrap_or(body).split(':').next().unwrap_or(body).to_string();
    }
    if let Some(body) = server.strip_prefix("tls://") {
        return body.split(':').next().unwrap_or(body).to_string();
    }
    server.split(':').next().unwrap_or(server).to_string()
}

fn address_value(value: &Value) -> Option<String> {
    let raw = if let Some(s) = value.as_str() {
        s.trim().to_string()
    } else {
        value.get("value").and_then(|v| v.as_str()).unwrap_or("").trim().to_string()
    };
    if raw.is_empty() || !is_ip(&raw) {
        None
    } else {
        Some(raw)
    }
}

fn address_row(value: &str, index: usize) -> Value {
    let slug: String = value
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect();
    json!({
        "id": format!("ip-{index}-{slug}"),
        "value": value
    })
}

pub fn normalized_addresses(item: &Value) -> Vec<String> {
    let mut out = Vec::new();
    if let Some(arr) = item["addresses"].as_array() {
        for value in arr {
            if let Some(ip) = address_value(value) {
                out.push(ip);
            }
        }
    }
    out
}

pub fn parse_addresses_text(text: &str) -> Vec<Value> {
    text.split(|c| c == '\n' || c == ',' || c == ';')
        .map(str::trim)
        .filter(|s| !s.is_empty() && is_ip(s))
        .enumerate()
        .map(|(i, s)| address_row(s, i))
        .collect()
}

pub fn apply_to_server(server: &mut Value, item: &Value) {
    let addrs = normalized_addresses(item);
    if addrs.is_empty() {
        return;
    }
    let host = resolver_host(item);
    let dial = &addrs[0];
    match server["type"].as_str().unwrap_or("") {
        "https" | "tls" | "quic" => {
            if !host.is_empty() && !is_ip(&host) {
                server["server"] = json!(dial);
                if let Some(tls) = server.get_mut("tls") {
                    if let Some(obj) = tls.as_object_mut() {
                        obj.insert("server_name".into(), json!(host));
                        obj.insert("enabled".into(), json!(true));
                    }
                } else {
                    server["tls"] = json!({"enabled": true, "server_name": host});
                }
            }
        }
        "udp" => {
            server["server"] = json!(dial);
        }
        _ => {}
    }
}

pub fn dns_hosts_map(settings: &Value) -> Value {
    let mut map = serde_json::Map::new();
    let Some(items) = settings["dns_items"].as_array() else {
        return json!(map);
    };
    for item in items {
        if !item["enabled"].as_bool().unwrap_or(true) {
            continue;
        }
        let host = resolver_host(item);
        let addrs = normalized_addresses(item);
        if host.is_empty() || is_ip(&host) || addrs.is_empty() {
            continue;
        }
        map.insert(host, json!(addrs));
    }
    json!(map)
}

pub fn save_dns_item(settings: &mut Value, item: &Value) -> Result<(), String> {
    let id = item["id"].as_str().unwrap_or("").trim();
    if id.is_empty() {
        return Err("dns item id is required".into());
    }
    let kind = item["type"].as_str().unwrap_or("udp");
    if !matches!(kind, "udp" | "tls" | "https" | "quic") {
        return Err("dns type must be udp, tls, https, or quic".into());
    }
    if item["server"].as_str().unwrap_or("").trim().is_empty() {
        return Err("dns server is required".into());
    }
    let mut row = item.clone();
    if row.get("name").and_then(|v| v.as_str()).unwrap_or("").is_empty() {
        row["name"] = json!(id);
    }
    row["enabled"] = json!(item["enabled"].as_bool().unwrap_or(true));
    row["role"] = json!(match item["role"].as_str().unwrap_or("remote") {
        "domestic" => "domestic",
        _ => "remote",
    });
    let mut addresses = Vec::new();
    if let Some(text) = item.get("addresses_text").and_then(|v| v.as_str()) {
        addresses = parse_addresses_text(text);
    } else if let Some(arr) = item["addresses"].as_array() {
        for (index, value) in arr.iter().enumerate() {
            if let Some(ip) = address_value(value) {
                if let Some(obj) = value.as_object() {
                    let id = obj.get("id").and_then(|v| v.as_str()).unwrap_or("");
                    if id.is_empty() {
                        addresses.push(address_row(&ip, index));
                    } else {
                        addresses.push(json!({"id": id, "value": ip}));
                    }
                } else {
                    addresses.push(address_row(&ip, index));
                }
            }
        }
    }
    row["addresses"] = json!(addresses);
    row.as_object_mut().map(|o| o.remove("addresses_text"));
    let mut items = settings["dns_items"].as_array().cloned().unwrap_or_default();
    if let Some(existing) = items.iter_mut().find(|i| i["id"].as_str() == Some(id)) {
        *existing = row;
    } else {
        items.push(row);
    }
    settings["dns_items"] = json!(items);
    sync_legacy_dns(settings);
    Ok(())
}

pub fn delete_dns_item(settings: &mut Value, id: &str) -> Result<(), String> {
    let mut items = settings["dns_items"].as_array().cloned().unwrap_or_default();
    let before = items.len();
    items.retain(|i| i["id"].as_str() != Some(id));
    if items.len() == before {
        return Err("dns item not found".into());
    }
    settings["dns_items"] = json!(items);
    if settings["remote_dns_id"].as_str() == Some(id) {
        settings["remote_dns_id"] = json!("");
    }
    if settings["domestic_dns_id"].as_str() == Some(id) {
        settings["domestic_dns_id"] = json!("");
    }
    if settings["enabledDnsServer"].as_str() == Some(id) {
        settings["enabledDnsServer"] = json!("");
    }
    sync_legacy_dns(settings);
    Ok(())
}

pub fn set_active_dns(settings: &mut Value, role: &str, id: &str) -> Result<(), String> {
    if item_by_id(settings, id).is_none() {
        return Err("dns item not found".into());
    }
    match role {
        "domestic" => settings["domestic_dns_id"] = json!(id),
        "enabled" => {
            settings["enabledDnsServer"] = json!(id);
            settings["remote_dns_id"] = json!(id);
        }
        _ => {
            settings["remote_dns_id"] = json!(id);
            settings["enabledDnsServer"] = json!(id);
        }
    }
    if settings["enabledDnsServer"].as_str().unwrap_or("").is_empty() {
        settings["enabledDnsServer"] = json!(settings["remote_dns_id"].as_str().unwrap_or(""));
    }
    sync_legacy_dns(settings);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn structured_and_plain_addresses() {
        let item = json!({"addresses": [{"id": "a", "value": "1.1.1.1"}, "8.8.8.8"]});
        assert_eq!(normalized_addresses(&item), vec!["1.1.1.1".to_string(), "8.8.8.8".to_string()]);
        let rows = parse_addresses_text("9.9.9.9\n1.0.0.1");
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0]["value"], "9.9.9.9");
        assert!(rows[0]["id"].as_str().unwrap().starts_with("ip-"));
    }
}
