mod common;

use common::core_harness::{cleanup, open_core, SAMPLE_VLESS};
use serde_json::json;

#[test]
fn panel_headers_apply_to_group() {
    let body = format!("{SAMPLE_VLESS}\n");
    let (url, _, handle) = common::http_mock::serve_once(
        &body,
        common::http_mock::MockHeaders::default()
            .push("Profile-Title", "I love hiddify")
            .push("subscription-userinfo", "upload=100; download=200; total=1000; expire=2000000000")
            .push("profile-update-interval", "12")
            .push("profile-web-page-url", "https://panel.example/user")
            .push("support-url", "https://panel.example/support")
            .push("announce", "hello"),
    );
    let (mut core, dir) = open_core();
    core.call("subscribe", &json!({"name": "Fallback", "url": url}))
        .expect("subscribe");
    common::http_mock::wait(handle);
    let state = core.call("state", &json!({})).expect("state");
    let group = state["groups"]
        .as_array()
        .unwrap()
        .iter()
        .find(|g| g["kind"].as_str() == Some("remote"))
        .expect("remote group");
    assert_eq!(group["name"].as_str(), Some("I love hiddify"));
    assert_eq!(group["announcement"].as_str(), Some("hello"));
    assert_eq!(group["upload"].as_u64(), Some(100));
    assert_eq!(group["download"].as_u64(), Some(200));
    assert_eq!(group["total"].as_u64(), Some(1000));
    assert_eq!(group["expire"].as_u64(), Some(2000000000));
    assert_eq!(group["web_page"].as_str(), Some("https://panel.example/user"));
    assert_eq!(group["support_url"].as_str(), Some("https://panel.example/support"));
    assert_eq!(group["refresh_hours"].as_u64(), Some(12));
    assert_eq!(state["settings"]["sub_auto_update"].as_bool(), Some(true));
    assert_eq!(state["settings"]["sub_auto_interval_hours"].as_u64(), Some(12));
    cleanup(&dir);
}

#[test]
fn moved_permanently_to_rewrites_url() {
    let (url_b, _, _h2) = common::http_mock::serve_once(
        SAMPLE_VLESS,
        common::http_mock::MockHeaders::default().push("Profile-Title", "Second"),
    );
    let (url_a, _, h1) = common::http_mock::serve_once(
        SAMPLE_VLESS,
        common::http_mock::MockHeaders::default()
            .push("moved-permanently-to", &url_b)
            .push("Profile-Title", "First"),
    );
    let (mut core, dir) = open_core();
    core.call("subscribe", &json!({"name": "G", "url": url_a}))
        .expect("subscribe");
    common::http_mock::wait(h1);
    let state = core.call("state", &json!({})).expect("state");
    let remote = state["groups"]
        .as_array()
        .unwrap()
        .iter()
        .find(|g| g["kind"].as_str() == Some("remote"))
        .expect("remote");
    assert_eq!(remote["url"].as_str(), Some(url_b.as_str()));
    cleanup(&dir);
}

#[test]
fn send_hwid_header_on_refresh() {
    let (url, captured, handle) = common::http_mock::serve_once(
        SAMPLE_VLESS,
        common::http_mock::MockHeaders::default(),
    );
    let (mut core, dir) = open_core();
    core.call("set", &json!({"key": "send_hwid", "value": true}))
        .expect("set hwid flag");
    core.call("set", &json!({"key": "hwid", "value": "test-device-99"}))
        .expect("set hwid");
    core.call("subscribe", &json!({"name": "H", "url": url}))
        .expect("subscribe");
    common::http_mock::wait(handle);
    let req = captured.lock().unwrap().clone();
    assert!(
        req.to_ascii_lowercase().contains("x-hwid: test-device-99"),
        "expected X-HWID in request, got:\n{req}"
    );
    cleanup(&dir);
}
