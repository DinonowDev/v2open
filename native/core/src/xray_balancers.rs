use serde_json::{json, Value};

pub fn ensure_balancers(settings: &mut Value) {
    if settings.get("xray_balancers").and_then(|v| v.as_array()).is_some() {
        return;
    }
    let mut list = Vec::new();
    if settings["xray_balancer_enabled"].as_bool().unwrap_or(false) {
        list.push(json!({
            "id": "legacy",
            "enabled": true,
            "tag": settings["xray_balancer_tag"].as_str().unwrap_or("balancer"),
            "strategy": settings["xray_balancer_strategy"].as_str().unwrap_or("random"),
            "selector": settings["xray_balancer_selector"].clone(),
            "domains": [],
            "ips": [],
            "networks": "tcp,udp",
            "default": true
        }));
    }
    settings["xray_balancers"] = json!(list);
}

pub fn save_balancer(settings: &mut Value, row: &Value) -> Result<(), String> {
    let id = row["id"].as_str().unwrap_or("").trim();
    if id.is_empty() {
        return Err("balancer id is required".into());
    }
    let tag = row["tag"].as_str().unwrap_or("").trim();
    if tag.is_empty() {
        return Err("balancer tag is required".into());
    }
    let strategy = row["strategy"].as_str().unwrap_or("random");
    if !matches!(strategy, "random" | "roundRobin" | "leastPing") {
        return Err("invalid balancer strategy".into());
    }
    let selector: Vec<Value> = row["selector"]
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|v| {
                    v.as_str()
                        .map(str::trim)
                        .filter(|s| !s.is_empty())
                        .map(|s| json!(s))
                })
                .collect()
        })
        .unwrap_or_default();
    if selector.is_empty() {
        return Err("balancer selector is required".into());
    }
    let item = json!({
        "id": id,
        "enabled": row["enabled"].as_bool().unwrap_or(true),
        "tag": tag,
        "strategy": strategy,
        "selector": selector,
        "domains": string_list(&row["domains"]),
        "ips": string_list(&row["ips"]),
        "networks": row["networks"].as_str().unwrap_or("tcp,udp"),
        "default": row["default"].as_bool().unwrap_or(false)
    });
    let mut list = settings["xray_balancers"].as_array().cloned().unwrap_or_default();
    if item["default"].as_bool() == Some(true) {
        for other in list.iter_mut() {
            if other["id"].as_str() != Some(id) {
                other["default"] = json!(false);
            }
        }
    }
    if let Some(existing) = list.iter_mut().find(|b| b["id"].as_str() == Some(id)) {
        *existing = item;
    } else {
        if list.iter().any(|b| b["tag"].as_str() == Some(tag)) {
            return Err("balancer tag already exists".into());
        }
        list.push(item);
    }
    settings["xray_balancers"] = json!(list);
    sync_legacy_flag(settings);
    Ok(())
}

pub fn delete_balancer(settings: &mut Value, id: &str) -> Result<(), String> {
    let mut list = settings["xray_balancers"].as_array().cloned().unwrap_or_default();
    let before = list.len();
    list.retain(|b| b["id"].as_str() != Some(id));
    if list.len() == before {
        return Err("balancer not found".into());
    }
    settings["xray_balancers"] = json!(list);
    sync_legacy_flag(settings);
    Ok(())
}

fn sync_legacy_flag(settings: &mut Value) {
    let list = settings["xray_balancers"].as_array().cloned().unwrap_or_default();
    let active: Vec<&Value> = list.iter().filter(|b| b["enabled"].as_bool().unwrap_or(true)).collect();
    settings["xray_balancer_enabled"] = json!(!active.is_empty());
    if let Some(first) = active.first() {
        settings["xray_balancer_tag"] = first["tag"].clone();
        settings["xray_balancer_strategy"] = first["strategy"].clone();
        settings["xray_balancer_selector"] = first["selector"].clone();
    }
}

fn string_list(value: &Value) -> Vec<Value> {
    value
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|v| v.as_str().map(|s| s.trim()).filter(|s| !s.is_empty()).map(|s| json!(s)))
                .collect()
        })
        .unwrap_or_default()
}

pub fn export_balancers(settings: &Value) -> Option<Value> {
    let list = settings["xray_balancers"].as_array()?;
    let mut out = Vec::new();
    for row in list {
        if !row["enabled"].as_bool().unwrap_or(true) {
            continue;
        }
        let tag = row["tag"].as_str().unwrap_or("");
        if tag.is_empty() {
            continue;
        }
        let selector = row["selector"].as_array().cloned().unwrap_or_default();
        if selector.is_empty() {
            continue;
        }
        let strategy = row["strategy"].as_str().unwrap_or("random");
        let strategy_obj = match strategy {
            "leastPing" => json!({"type": "leastPing"}),
            "roundRobin" => json!({"type": "roundRobin"}),
            _ => json!({"type": "random"}),
        };
        out.push(json!({
            "tag": tag,
            "selector": selector,
            "strategy": strategy_obj
        }));
    }
    if out.is_empty() {
        None
    } else {
        Some(json!(out))
    }
}

pub fn balancer_rules(settings: &Value) -> Vec<Value> {
    let mut rules = Vec::new();
    let Some(list) = settings["xray_balancers"].as_array() else {
        return rules;
    };
    for row in list {
        if !row["enabled"].as_bool().unwrap_or(true) {
            continue;
        }
        let tag = row["tag"].as_str().unwrap_or("");
        if tag.is_empty() {
            continue;
        }
        let networks = row["networks"].as_str().unwrap_or("tcp,udp");
        let domains: Vec<Value> = string_list(&row["domains"]);
        let ips: Vec<Value> = string_list(&row["ips"]);
        if !domains.is_empty() || !ips.is_empty() {
            let mut rule = json!({"type": "field", "network": networks, "balancerTag": tag});
            if !domains.is_empty() {
                rule["domain"] = json!(domains);
            }
            if !ips.is_empty() {
                rule["ip"] = json!(ips);
            }
            rules.push(rule);
        } else if row["default"].as_bool().unwrap_or(false) {
            rules.push(json!({"type": "field", "network": networks, "balancerTag": tag}));
        }
    }
    rules
}
