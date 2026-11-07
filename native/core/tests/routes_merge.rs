mod common;

use common::core_harness::{cleanup, open_core};
use serde_json::json;
use v2core::parse_clash_rules;

#[test]
fn import_routes_merge_appends() {
    let (mut core, dir) = open_core();
    let initial = json!({
        "remark": "keep",
        "behavior": "direct",
        "domains": ["domain:keep.test"],
        "ips": [],
        "port": "",
        "network": "",
        "protocol": "",
        "inbounds": [],
        "sources": [],
        "source_port": "",
        "users": [],
        "balancer_tag": "",
        "enabled": true
    });
    core.call("save_route", &json!({"route": initial}))
        .expect("save");
    let clash = "rules:\n  - DOMAIN-SUFFIX,ads.test,REJECT";
    let merged = core
        .call(
            "import_routes",
            &json!({"text": clash, "merge": true}),
        )
        .expect("merge import");
    let routes = merged["routes"].as_array().expect("routes");
    assert_eq!(routes.len(), 2);
    let remarks: Vec<_> = routes.iter().filter_map(|r| r["remark"].as_str()).collect();
    assert!(remarks.iter().any(|r| r.contains("keep")));
    assert!(remarks.iter().any(|r| r.contains("DOMAIN-SUFFIX")));
    cleanup(&dir);
}

#[test]
fn import_routes_replace_clears_presets() {
    let (mut core, dir) = open_core();
    core.call("save_route", &json!({"route": {
        "remark": "old",
        "behavior": "block",
        "domains": ["keyword:old"],
        "ips": [],
        "port": "",
        "network": "",
        "protocol": "",
        "enabled": true
    }})).expect("save");
    let rules = parse_clash_rules("DOMAIN,only.one,Proxy").expect("parse");
    assert_eq!(rules.len(), 1);
    let replaced = core
        .call(
            "import_routes",
            &json!({"text": "DOMAIN,only.one,Proxy"}),
        )
        .expect("replace");
    let routes = replaced["routes"].as_array().unwrap();
    assert_eq!(routes.len(), 1);
    assert_eq!(routes[0]["behavior"].as_str(), Some("proxy"));
    cleanup(&dir);
}
