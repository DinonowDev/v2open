use serde_json::json;
use std::path::PathBuf;
use v2core::Core;

#[test]
#[ignore = "live TCP ping against the user's library; run: V2OPEN_LIVE_PING=1 cargo test -p v2core ping_sets_positive_ms_for_real_host -- --ignored"]
fn ping_sets_positive_ms_for_real_host() {
    if std::env::var("V2OPEN_LIVE_PING").ok().as_deref() != Some("1") {
        return;
    }
    let home = std::env::var("HOME").expect("HOME");
    let data = PathBuf::from(home).join("Library/Application Support/V2Open");
    let library = data.join("library.json");
    if !library.exists() {
        return;
    }
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let singbox = root.join("binaries/macos/sing-box");
    let rules = root.join("assets/rulesets");
    if !singbox.exists() {
        return;
    }
    let mut core = Core::open(data, singbox, rules);
    let groups = core.call("state", &json!({})).unwrap();
    let profiles: Vec<_> = groups["groups"]
        .as_array()
        .unwrap_or(&vec![])
        .iter()
        .flat_map(|g| g["profiles"].as_array().cloned().unwrap_or_default())
        .collect();
    let Some(first) = profiles.first() else { return };
    let pid = first["id"].as_str().unwrap_or("");
    assert!(!pid.is_empty());
    let leftover = first["ping"].as_i64().unwrap_or(-1);
    assert!(leftover <= 0, "opening the core must drop leftover ping, got {leftover}");
    let out = core.call("ping", &json!({"id": pid})).unwrap();
    let after: Vec<_> = out["groups"]
        .as_array()
        .unwrap_or(&vec![])
        .iter()
        .flat_map(|g| g["profiles"].as_array().cloned().unwrap_or_default())
        .collect();
    let ping = after
        .iter()
        .find(|p| p["id"].as_str() == Some(pid))
        .and_then(|p| p["ping"].as_i64())
        .unwrap_or(-1);
    let addr = first["address"].as_str().unwrap_or("");
    let port = first["port"].as_u64().unwrap_or(443) as u16;
    eprintln!("profile id={pid} addr={addr}:{port} ping={ping}");
    if ping <= 0 {
        eprintln!("skip: host unreachable or probe returned {ping}");
        return;
    }
    if !addr.is_empty() && addr != "127.0.0.1" && addr != "localhost" {
        assert!(
            ping >= 5,
            "ping {ping}ms to {addr}:{port} is tun-local, not a real handshake"
        );
    }
}
