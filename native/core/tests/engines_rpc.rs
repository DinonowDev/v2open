mod common;

use common::core_harness::{cleanup, open_core};
use serde_json::json;
use std::fs;
use v2core::{engines_dir, resolve_singbox, resolve_xray, SINGBOX_UPSTREAM};

#[test]
fn resolve_upstream_only_when_mode_upstream() {
    let root = common::core_harness::workspace_root();
    let data = std::env::temp_dir().join(format!("v2open-engines-{}", std::process::id()));
    let _ = fs::remove_dir_all(&data);
    fs::create_dir_all(engines_dir(&data)).unwrap();
    let upstream = engines_dir(&data).join(SINGBOX_UPSTREAM);
    fs::write(&upstream, b"\x00").unwrap();
    let bundled = root.join("binaries/macos/sing-box");
    let bundled = if bundled.is_file() {
        bundled
    } else {
        data.join("bundled-stub")
    };
    if !bundled.is_file() {
        fs::write(&bundled, b"").unwrap();
    }
    assert_eq!(resolve_singbox(&bundled, &data, "bundled"), bundled);
    assert_eq!(resolve_singbox(&bundled, &data, "upstream"), upstream);
    let _ = fs::remove_dir_all(&data);
}

#[test]
fn resolve_xray_prefers_user_binary() {
    let root = common::core_harness::workspace_root();
    let data = std::env::temp_dir().join(format!("v2open-xray-{}", std::process::id()));
    let _ = fs::remove_dir_all(&data);
    fs::create_dir_all(engines_dir(&data)).unwrap();
    let user_xr = engines_dir(&data).join("xray");
    fs::write(&user_xr, b"\x00").unwrap();
    let bundled = root.join("binaries/macos/sing-box");
    let singbox = if bundled.is_file() {
        bundled
    } else {
        user_xr.clone()
    };
    assert_eq!(resolve_xray(&singbox, &data), user_xr);
    let _ = fs::remove_dir_all(&data);
}

#[test]
fn engines_status_rpc_shape() {
    let (mut core, dir) = open_core();
    let status = core.call("engines_status", &json!({})).expect("status");
    assert!(status.get("singbox").is_some());
    assert!(status.get("xray").is_some());
    assert!(status["singbox"].get("active").is_some());
    assert!(status["singbox"].get("upstream_installed").is_some());
    assert!(status["singbox"].get("engine_mode").is_some());
    assert!(status["catalog"].get("sing-box").is_some());
    cleanup(&dir);
}

#[test]
fn set_singbox_engine_rpc() {
    let (mut core, dir) = open_core();
    let status = core
        .call("set_singbox_engine", &json!({"mode": "upstream"}))
        .expect("upstream");
    assert_eq!(status["singbox"]["engine_mode"].as_str(), Some("upstream"));
    let status = core
        .call("set_singbox_engine", &json!({"mode": "bundled"}))
        .expect("bundled");
    assert_eq!(status["singbox"]["engine_mode"].as_str(), Some("bundled"));
    cleanup(&dir);
}

#[test]
#[ignore = "downloads engine binaries from GitHub; run: V2OPEN_LIVE_ENGINE_UPDATE=1 cargo test -p v2core engines_update_live_xray -- --ignored"]
fn engines_update_live_xray() {
    if std::env::var("V2OPEN_LIVE_ENGINE_UPDATE").ok().as_deref() != Some("1") {
        panic!("set V2OPEN_LIVE_ENGINE_UPDATE=1 for this test");
    }
    let (mut core, dir) = open_core();
    let status = core
        .call("engines_update", &json!({"target": "xray"}))
        .expect("engines_update");
    assert!(status["xray"]["user_installed"].as_bool() == Some(true));
    let path = status["xray"]["active"].as_str().unwrap();
    let meta = fs::metadata(path).expect("xray file");
    assert!(meta.len() > 1_000_000);
    let sing = status["singbox"]["active"].as_str().unwrap();
    assert!(!sing.contains(SINGBOX_UPSTREAM) || status["singbox"]["engine_mode"].as_str() == Some("upstream"));
    cleanup(&dir);
}

#[test]
#[ignore = "downloads sing-box from GitHub; run: V2OPEN_LIVE_ENGINE_UPDATE=1 cargo test -p v2core engines_update_live_singbox -- --ignored"]
fn engines_update_live_singbox() {
    if std::env::var("V2OPEN_LIVE_ENGINE_UPDATE").ok().as_deref() != Some("1") {
        panic!("set V2OPEN_LIVE_ENGINE_UPDATE=1 for this test");
    }
    let (mut core, dir) = open_core();
    let status = core
        .call("engines_update", &json!({"target": "sing-box"}))
        .expect("engines_update sing-box");
    assert_eq!(status["singbox"]["upstream_installed"].as_bool(), Some(true));
    let path = status["singbox"]["upstream"].as_str().unwrap();
    assert!(path.contains(SINGBOX_UPSTREAM));
    let meta = fs::metadata(path).expect("upstream file");
    assert!(meta.len() > 1_000_000);
    let upstream = core
        .call("set_singbox_engine", &json!({"mode": "upstream"}))
        .expect("upstream mode");
    assert_eq!(upstream["singbox"]["engine_mode"].as_str(), Some("upstream"));
    assert!(upstream["singbox"]["active"].as_str().unwrap().contains(SINGBOX_UPSTREAM));
    core.call("set_singbox_engine", &json!({"mode": "bundled"})).unwrap();
    cleanup(&dir);
}
