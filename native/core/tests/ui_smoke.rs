mod common;

use common::core_harness::{cleanup, open_core};
use serde_json::json;
use v2core::{engines_dir, SINGBOX_UPSTREAM};

/// RPC paths used by About → engine updates and Settings → Routing (no XCTest host).
#[test]
fn smoke_about_engines_routing_navigation() {
    let (mut core, dir) = open_core();

    let status = core.call("engines_status", &json!({})).expect("engines_status");
    assert!(status["singbox"]["bundled"].is_string());
    assert!(status["singbox"]["engine_mode"].is_string());
    assert!(status["catalog"]["sing-box"].is_string());

    core.call("set_singbox_engine", &json!({"mode": "bundled"}))
        .expect("bundled");
    let bundled = core.call("engines_status", &json!({})).unwrap();
    assert_eq!(bundled["singbox"]["engine_mode"].as_str(), Some("bundled"));

    core.call("set_singbox_engine", &json!({"mode": "upstream"}))
        .expect("upstream mode without binary");
    let upstream = core.call("engines_status", &json!({})).unwrap();
    assert_eq!(upstream["singbox"]["engine_mode"].as_str(), Some("upstream"));

    let eng = engines_dir(&dir);
    std::fs::create_dir_all(&eng).unwrap();
    let up = eng.join(SINGBOX_UPSTREAM);
    std::fs::write(&up, b"").unwrap();
    let with_up = core.call("engines_status", &json!({})).unwrap();
    assert_eq!(with_up["singbox"]["upstream_installed"].as_bool(), Some(true));

    let state = core.call("state", &json!({})).expect("state");
    assert!(state.get("route_sets").is_some());
    assert!(state.get("routes").is_some());

    core.call(
        "import_routes",
        &json!({
            "text": "rules:\n  - DOMAIN-SUFFIX,smoke.test,DIRECT",
            "merge": true
        }),
    )
    .expect("import_routes");

    _ = core.call("export_routes", &json!({})).expect("export_routes");

    core.call("set_singbox_engine", &json!({"mode": "bundled"})).unwrap();
    cleanup(&dir);
}
