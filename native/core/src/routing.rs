use serde_json::{json, Value};

pub fn preset(name: &str) -> Value {
    let (final_tag, split, raw) = match name {
        "white" => ("proxy", "cn", include_str!("../../../assets/routing/white.json")),
        "black" => ("direct", "none", include_str!("../../../assets/routing/black.json")),
        "iran" => ("proxy", "ir", include_str!("../../../assets/routing/iran.json")),
        "russia" => ("proxy", "ru", include_str!("../../../assets/routing/russia.json")),
        _ => ("proxy", "none", include_str!("../../../assets/routing/global.json")),
    };
    let rules = parse_routes(raw).unwrap_or_default();
    json!({
        "final": final_tag,
        "block_udp_443": false,
        "bypass_lan": false,
        "dns_split": split,
        "rules": rules
    })
}

pub fn parse_routes(text: &str) -> Result<Vec<Value>, String> {
    let value: Value = serde_json::from_str(text.trim()).map_err(|_| "routing json is invalid".to_string())?;
    let items = if let Some(arr) = value.as_array() {
        arr.clone()
    } else if let Some(arr) = value.get("rules").and_then(|v| v.as_array()) {
        arr.clone()
    } else if value.get("routing").and_then(|v| v.get("rules")).and_then(|v| v.as_array()).is_some() {
        value["routing"]["rules"].as_array().cloned().unwrap_or_default()
    } else if value.is_object() {
        vec![value]
    } else {
        return Err("routing json is invalid".into());
    };
    let mut rules = Vec::new();
    for item in items {
        if let Some(rule) = normalize_rule(item, None) {
            if !is_final_catch_all(&rule) {
                rules.push(rule);
            }
        }
    }
    Ok(rules)
}

pub fn export_routes(rules: &[Value]) -> String {
    let items: Vec<Value> = rules.iter().map(to_v2box).collect();
    serde_json::to_string_pretty(&items).unwrap_or_else(|_| "[]".into())
}

pub fn matcher_text(rule: &Value) -> String {
    let mut parts = Vec::new();
    parts.extend(list(&rule["domains"]));
    parts.extend(list(&rule["ips"]));
    let port = rule["port"].as_str().unwrap_or("").trim();
    if !port.is_empty() && port != "0-65535" {
        parts.push(port.to_string());
    }
    let network = rule["network"].as_str().unwrap_or("").trim();
    if network == "tcp" || network == "udp" {
        parts.push(network.to_string());
    }
    let protocol = rule["protocol"].as_str().unwrap_or("").trim();
    if !protocol.is_empty() {
        parts.push(protocol.to_string());
    }
    parts.extend(list(&rule["inbounds"]));
    parts.extend(list(&rule["sources"]));
    let source_port = rule["source_port"].as_str().unwrap_or("").trim();
    if !source_port.is_empty() {
        parts.push(source_port.to_string());
    }
    let balancer = rule["balancer_tag"].as_str().unwrap_or("").trim();
    if !balancer.is_empty() {
        parts.push(format!("balancer:{balancer}"));
    }
    parts.join(",")
}

pub fn normalize_rule(raw: Value, fallback_id: Option<String>) -> Option<Value> {
    if raw.as_object().is_none() {
        return None;
    }
    let remark = first_str(&raw, &["remark", "remarks", "name"]).unwrap_or_else(|| "Rule".into());
    let behavior = behavior_of(&raw);
    let enabled = raw.get("enabled").and_then(|v| v.as_bool()).unwrap_or(true);
    let id = first_str(&raw, &["id", "ruleTag"]).filter(|s| !s.is_empty()).unwrap_or_else(|| fallback_id.unwrap_or_else(new_id));
    let domains = list(&raw["domains"]);
    let mut domains = if domains.is_empty() { list(&raw["domain"]) } else { domains };
    let ips = list(&raw["ips"]);
    let mut ips = if ips.is_empty() { list(&raw["ip"]) } else { ips };
    if domains.is_empty() && ips.is_empty() {
        if let Some(text) = raw.get("text").and_then(|v| v.as_str()) {
            for line in text.lines() {
                let line = line.trim();
                if line.is_empty() {
                    continue;
                }
                if looks_ip(line) {
                    ips.push(line.to_string());
                } else {
                    domains.push(line.to_string());
                }
            }
        }
    }
    let port = first_str(&raw, &["port"]).unwrap_or_default();
    let network = first_str(&raw, &["network"]).unwrap_or_default();
    let protocol = protocol_of(&raw);
    let inbounds = first_list(&raw, &["inbounds", "inboundTag", "inbound"]);
    let sources = first_list(&raw, &["sources", "source", "sourceIp", "sourceIPs"]);
    let source_port = first_str(&raw, &["source_port", "sourcePort", "sourcePortList"]).unwrap_or_default();
    let users = first_list(&raw, &["users", "user"]);
    let balancer_tag = first_str(&raw, &["balancer_tag", "balancerTag"]).unwrap_or_default();
    Some(json!({
        "id": id,
        "enabled": enabled,
        "remark": remark,
        "behavior": behavior,
        "domains": domains,
        "ips": ips,
        "port": port,
        "network": network,
        "protocol": protocol,
        "inbounds": inbounds,
        "sources": sources,
        "source_port": source_port,
        "users": users,
        "balancer_tag": balancer_tag
    }))
}

pub fn builtin_geo_assets() -> Vec<Value> {
    vec![
        asset("geoip.dat", "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat", "dat"),
        asset("geosite.dat", "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat", "dat"),
        asset("iran.dat", "https://github.com/bootmortis/iran-hosted-domains/releases/latest/download/iran.dat", "dat"),
        asset("geoip-cn.srs", "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs", "srs"),
        asset("geoip-ir.srs", "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ir.srs", "srs"),
        asset("geoip-ru.srs", "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs", "srs"),
        asset("geosite-cn.srs", "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs", "srs"),
        asset("geosite-google.srs", "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-google.srs", "srs"),
        asset("geosite-apple.srs", "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-apple.srs", "srs"),
        asset("geosite-category-ir.srs", "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ir.srs", "srs"),
        asset("geosite-category-ru.srs", "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ru.srs", "srs"),
        asset("geosite-private.srs", "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-private.srs", "srs"),
        asset("geosite-category-ads-all.srs", "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs", "srs"),
    ]
}

fn asset(name: &str, url: &str, kind: &str) -> Value {
    json!({"name": name, "url": url, "kind": kind, "builtin": true})
}

pub fn geosite_download_url(source: &str) -> String {
    let s = source.trim();
    if s.starts_with("http://") || s.starts_with("https://") {
        return s.to_string();
    }
    let repo = s.trim_start_matches("https://github.com/").trim_matches('/');
    if repo.is_empty() {
        return "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat".into();
    }
    format!("https://github.com/{repo}/releases/latest/download/dlc.dat")
}

pub fn geoip_download_url(source: &str) -> String {
    let s = source.trim();
    if s.starts_with("http://") || s.starts_with("https://") {
        return s.to_string();
    }
    let repo = s.trim_start_matches("https://github.com/").trim_matches('/');
    if repo.is_empty() {
        return "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat".into();
    }
    format!("https://github.com/{repo}/releases/latest/download/geoip.dat")
}

fn to_v2box(rule: &Value) -> Value {
    let mut item = json!({
        "remarks": rule["remark"].as_str().unwrap_or(""),
        "outboundTag": match rule["behavior"].as_str().unwrap_or("proxy") {
            "direct" => "direct",
            "block" => "block",
            _ => "proxy",
        }
    });
    if rule.get("enabled") == Some(&json!(false)) {
        item["enabled"] = json!(false);
    }
    let domains = list(&rule["domains"]);
    if !domains.is_empty() {
        item["domain"] = json!(domains);
    }
    let ips = list(&rule["ips"]);
    if !ips.is_empty() {
        item["ip"] = json!(ips);
    }
    let port = rule["port"].as_str().unwrap_or("").trim();
    if !port.is_empty() {
        item["port"] = json!(port);
    }
    let network = rule["network"].as_str().unwrap_or("").trim();
    if network == "tcp" || network == "udp" {
        item["network"] = json!(network);
    }
    let protocol = rule["protocol"].as_str().unwrap_or("").trim();
    if !protocol.is_empty() {
        item["protocol"] = json!([protocol]);
    }
    let inbounds = list(&rule["inbounds"]);
    if !inbounds.is_empty() {
        item["inboundTag"] = json!(inbounds);
    }
    let sources = list(&rule["sources"]);
    if !sources.is_empty() {
        item["source"] = json!(sources);
    }
    let source_port = rule["source_port"].as_str().unwrap_or("").trim();
    if !source_port.is_empty() {
        item["sourcePort"] = json!(source_port);
    }
    let users = list(&rule["users"]);
    if !users.is_empty() {
        item["user"] = json!(users);
    }
    let balancer = rule["balancer_tag"].as_str().unwrap_or("").trim();
    if !balancer.is_empty() {
        item["balancerTag"] = json!(balancer);
        item.as_object_mut().map(|o| o.remove("outboundTag"));
    }
    item
}

fn is_final_catch_all(rule: &Value) -> bool {
    list(&rule["domains"]).is_empty()
        && list(&rule["ips"]).is_empty()
        && list(&rule["inbounds"]).is_empty()
        && list(&rule["sources"]).is_empty()
        && list(&rule["users"]).is_empty()
        && rule["balancer_tag"].as_str().unwrap_or("").is_empty()
        && rule["source_port"].as_str().unwrap_or("").is_empty()
        && rule["protocol"].as_str().unwrap_or("").is_empty()
        && rule["network"].as_str().unwrap_or("").is_empty()
        && matches!(rule["port"].as_str().unwrap_or(""), "0-65535" | "0:65535" | "")
}

fn behavior_of(raw: &Value) -> String {
    if let Some(tag) = first_str(raw, &["behavior", "outboundTag", "outbound"]) {
        return match tag.to_ascii_lowercase().as_str() {
            "direct" | "freedom" => "direct".into(),
            "block" | "reject" | "blackhole" => "block".into(),
            _ => "proxy".into(),
        };
    }
    "proxy".into()
}

fn protocol_of(raw: &Value) -> String {
    let items = list(&raw["protocol"]);
    items.first().cloned().unwrap_or_default()
}

fn first_str(value: &Value, keys: &[&str]) -> Option<String> {
    for key in keys {
        if let Some(text) = value.get(*key).and_then(|v| v.as_str()).map(|s| s.trim().to_string()) {
            if !text.is_empty() {
                return Some(text);
            }
        }
        if let Some(n) = value.get(*key).and_then(|v| v.as_u64()) {
            return Some(n.to_string());
        }
    }
    None
}

fn first_list(raw: &Value, keys: &[&str]) -> Vec<String> {
    for key in keys {
        let items = list(&raw[key]);
        if !items.is_empty() {
            return items;
        }
    }
    Vec::new()
}

pub fn list(value: &Value) -> Vec<String> {
    if let Some(arr) = value.as_array() {
        return arr.iter().flat_map(list).collect();
    }
    value
        .as_str()
        .unwrap_or("")
        .split(|c| c == '\n' || c == ',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

fn looks_ip(line: &str) -> bool {
    let line = line.trim();
    line.starts_with("geoip:")
        || line.contains('/')
        || line.starts_with("ext:geoip")
        || line.chars().next().map(|c| c.is_ascii_digit() || c == '[').unwrap_or(false)
}

fn new_id() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    format!("r{now:x}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_v2box_iran_ruleset() {
        let rules = parse_routes(include_str!("../../../assets/routing/iran.json")).unwrap();
        assert_eq!(rules.len(), 5);
        assert_eq!(rules[0]["remark"], "Block udp443");
        assert_eq!(rules[0]["behavior"], "block");
        assert_eq!(rules[0]["port"], "443");
        assert_eq!(rules[0]["network"], "udp");
        assert_eq!(rules[3]["domains"], json!(["domain:ir", "geosite:category-ir"]));
        assert_eq!(rules[4]["ips"], json!(["geoip:ir"]));
    }

    #[test]
    fn export_roundtrip_keeps_matchers() {
        let rules = parse_routes(include_str!("../../../assets/routing/iran.json")).unwrap();
        let exported = export_routes(&rules);
        let again = parse_routes(&exported).unwrap();
        assert_eq!(again.len(), rules.len());
        assert_eq!(again[1]["ips"], json!(["geoip:private"]));
        assert_eq!(again[2]["domains"], json!(["geosite:private"]));
    }

    #[test]
    fn matcher_text_joins_fields() {
        let rule = json!({
            "remark": "Bypass Iran domains",
            "behavior": "direct",
            "domains": ["domain:ir", "geosite:category-ir"],
            "ips": [],
            "port": "",
            "network": "",
            "protocol": ""
        });
        assert_eq!(matcher_text(&rule), "domain:ir,geosite:category-ir");
    }

    #[test]
    fn parses_advanced_v2box_fields() {
        let text = r#"[{"remarks":"in","inboundTag":["socks"],"source":["10.0.0.1"],"sourcePort":"443","user":["alice"],"balancerTag":"b1","domain":["domain:example.com"]}]"#;
        let rules = parse_routes(text).unwrap();
        assert_eq!(rules[0]["inbounds"], json!(["socks"]));
        assert_eq!(rules[0]["sources"], json!(["10.0.0.1"]));
        assert_eq!(rules[0]["source_port"], "443");
        assert_eq!(rules[0]["users"], json!(["alice"]));
        assert_eq!(rules[0]["balancer_tag"], "b1");
        let exported = export_routes(&rules);
        assert!(exported.contains("balancerTag"));
        assert!(exported.contains("inboundTag"));
    }
}
