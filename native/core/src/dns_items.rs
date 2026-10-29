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

pub fn save_dns_item(settings: &mut Value, item: &Value) -> Result<(), String> {
    let id = item["id"].as_str().unwrap_or("").trim();
    if id.is_empty() {
        return Err("dns item id is required".into());
    }
    let kind = item["type"].as_str().unwrap_or("udp");
    if !matches!(kind, "udp" | "tls" | "https") {
        return Err("dns type must be udp, tls, or https".into());
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
    sync_legacy_dns(settings);
    Ok(())
}

pub fn set_active_dns(settings: &mut Value, role: &str, id: &str) -> Result<(), String> {
    if item_by_id(settings, id).is_none() {
        return Err("dns item not found".into());
    }
    match role {
        "domestic" => settings["domestic_dns_id"] = json!(id),
        _ => settings["remote_dns_id"] = json!(id),
    }
    sync_legacy_dns(settings);
    Ok(())
}
