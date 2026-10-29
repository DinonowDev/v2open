use serde_json::{json, Value};

pub fn migrate_settings(settings: &mut Value) {
    if settings.get("geo_auto_update").is_none() {
        settings["geo_auto_update"] = json!(settings["auto_update"].as_bool().unwrap_or(false));
    }
    if settings.get("sub_auto_update").is_none() {
        settings["sub_auto_update"] = json!(false);
    }
    if settings.get("sub_auto_interval_hours").is_none() {
        settings["sub_auto_interval_hours"] = json!(24);
    }
    if settings.get("sub_last_auto_update").is_none() {
        settings["sub_last_auto_update"] = json!(0);
    }
    if settings.get("smart_connect").is_none() {
        settings["smart_connect"] = json!(false);
    }
    if settings.get("smart_interval").is_none() {
        settings["smart_interval"] = json!("1m");
    }
    if settings.get("smart_tolerance").is_none() {
        settings["smart_tolerance"] = json!(50);
    }
    if settings.get("probe_url").is_none() {
        settings["probe_url"] = settings["speed_endpoint"].clone();
    }
    if settings.get("probe_interval").is_none() {
        settings["probe_interval"] = json!("1m");
    }
    if settings.get("observatory_enabled").is_none() {
        let least = settings["xray_balancers"]
            .as_array()
            .map(|a| a.iter().any(|b| b["strategy"].as_str() == Some("leastPing") && b["enabled"].as_bool().unwrap_or(true)))
            .unwrap_or(false);
        settings["observatory_enabled"] = json!(least);
    }
    if settings.get("speed_mode").is_none() {
        settings["speed_mode"] = json!("http");
    }
    if settings.get("persist_tunnel").is_none() {
        settings["persist_tunnel"] = json!(false);
    }
    if settings.get("enabledDnsServer").is_none() {
        settings["enabledDnsServer"] = json!(settings["remote_dns_id"].as_str().unwrap_or(""));
    }
    settings["sub_auto_update"] = json!(false);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migrates_legacy_auto_update_to_geo() {
        let mut settings = json!({"auto_update": true, "speed_endpoint": "https://example.com"});
        migrate_settings(&mut settings);
        assert_eq!(settings["geo_auto_update"], true);
        assert_eq!(settings["sub_auto_update"], false);
        assert_eq!(settings["sub_auto_interval_hours"], 24);
        assert_eq!(settings["probe_url"], "https://example.com");
    }

    #[test]
    fn does_not_overwrite_existing_geo_flag() {
        let mut settings = json!({"auto_update": true, "geo_auto_update": false});
        migrate_settings(&mut settings);
        assert_eq!(settings["geo_auto_update"], false);
    }
}
