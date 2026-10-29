use serde_json::json;
use v2core::build_config;
use v2core::xray_document as xray_document;

#[test]
fn dns_item_addresses_apply_to_config() {
    let mut settings = base_settings();
    settings["remote_dns_id"] = json!("cf");
    settings["domestic_dns_id"] = json!("ali-dns");
    settings["dns_items"] = json!([{
        "id": "cf",
        "name": "CF",
        "type": "https",
        "server": "cloudflare-dns.com",
        "path": "/dns-query",
        "addresses": ["1.1.1.1", "1.0.0.1"],
        "enabled": true,
        "role": "remote"
    }]);
    settings["remote_dns"] = json!("https://cloudflare-dns.com/dns-query");
    let profile = json!({
        "protocol": "vmess",
        "address": "127.0.0.1",
        "port": 443,
        "uuid": "00000000-0000-0000-0000-000000000099",
        "security": "auto"
    });
    let cfg = build_config(&settings, &[profile], &[], &rules_dir(), "proxy").expect("config");
    let dns = &cfg["dns"];
    let hosts = dns["hosts"].as_object().expect("dns hosts");
    assert!(hosts.contains_key("cloudflare-dns.com"));
    let remote = dns["servers"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["tag"] == "dns-remote")
        .expect("remote dns");
    assert_eq!(remote["server"], "1.1.1.1");
}

#[test]
fn xray_exports_multiple_balancers() {
    let mut settings = base_settings();
    settings["xray_balancers"] = json!([
        {
            "id": "a",
            "enabled": true,
            "tag": "b1",
            "strategy": "random",
            "selector": ["proxy"],
            "domains": ["domain:example.com"],
            "ips": [],
            "networks": "tcp,udp",
            "default": false
        },
        {
            "id": "b",
            "enabled": true,
            "tag": "b2",
            "strategy": "roundRobin",
            "selector": ["proxy"],
            "domains": [],
            "ips": [],
            "networks": "tcp,udp",
            "default": true
        }
    ]);
    let profile = json!({
        "protocol": "vmess",
        "address": "127.0.0.1",
        "port": 443,
        "uuid": "00000000-0000-0000-0000-000000000099",
        "security": "auto"
    });
    let doc = xray_document(&settings, &profile, &[]);
    let balancers = doc["routing"]["balancers"].as_array().expect("balancers");
    assert_eq!(balancers.len(), 2);
    let rules = doc["routing"]["rules"].as_array().expect("rules");
    assert!(rules.iter().any(|r| r.get("balancerTag") == Some(&json!("b1"))));
    assert!(rules.iter().any(|r| r.get("balancerTag") == Some(&json!("b2"))));
}

#[test]
fn xray_rule_and_observatory_export() {
    let mut settings = base_settings();
    settings["observatory_enabled"] = json!(true);
    settings["probe_url"] = json!("https://www.gstatic.com/generate_204");
    settings["probe_interval"] = json!("30s");
    let routes = vec![json!({
        "enabled": true,
        "behavior": "proxy",
        "domains": ["domain:example.com"],
        "ips": [],
        "inbounds": ["socks"],
        "sources": ["10.0.0.1"],
        "source_port": "443",
        "users": ["alice"],
        "balancer_tag": "b1",
        "port": "",
        "network": "",
        "protocol": ""
    })];
    let profile = json!({
        "protocol": "vmess",
        "address": "127.0.0.1",
        "port": 443,
        "uuid": "00000000-0000-0000-0000-000000000099",
        "security": "auto"
    });
    let doc = xray_document(&settings, &profile, &routes);
    assert!(doc.get("observatory").is_some());
    let rules = doc["routing"]["rules"].as_array().unwrap();
    let rule = rules.iter().find(|r| r.get("balancerTag") == Some(&json!("b1"))).expect("balancer rule");
    assert_eq!(rule["inboundTag"], json!(["socks"]));
    assert_eq!(rule["source"], json!(["10.0.0.1"]));
}

fn base_settings() -> serde_json::Value {
    json!({
        "language": "en",
        "loglevel": "none",
        "socks_enabled": true,
        "socks_port": 10808,
        "http_enabled": true,
        "http_port": 10807,
        "mode": "proxy",
        "remote_dns": "https://1.1.1.1/dns-query",
        "domestic_dns": "223.5.5.5",
        "dns_items": [],
        "query_strategy": "prefer_ipv4",
        "dns_cache": true,
        "dns_split": "none",
        "routing_enabled": true,
        "final": "proxy",
        "block_udp_443": false,
        "bypass_lan": true,
        "hosts": {},
        "fake_dns": false,
        "domain_strategy": "AsIs",
        "route_only": true,
        "sniffing": true,
        "per_app_mode": "off"
    })
}

fn rules_dir() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/rulesets")
}
