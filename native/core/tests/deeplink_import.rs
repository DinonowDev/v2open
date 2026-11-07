mod common;

use common::core_harness::{cleanup, open_core, SAMPLE_VLESS};
use serde_json::json;

#[test]
fn hiddify_import_single_link() {
    let (mut core, dir) = open_core();
    let text = format!("hiddify://import/{SAMPLE_VLESS}#PanelNode");
    let _state = core.call("import", &json!({"text": text})).expect("import");
    let state = core.call("state", &json!({})).expect("state");
    let groups = state["groups"].as_array().expect("groups");
    assert!(!groups.is_empty());
    let profiles = groups[0]["profiles"].as_array().unwrap();
    assert_eq!(profiles.len(), 1);
    assert!(profiles[0]["link"]
        .as_str()
        .unwrap_or("")
        .starts_with("vless://"));
    cleanup(&dir);
}

#[test]
fn sub_scheme_subscribes() {
    let (url, captured, handle) = common::http_mock::serve_once(
        SAMPLE_VLESS,
        common::http_mock::MockHeaders::default().push("Profile-Title", "SubFromScheme"),
    );
    let (mut core, dir) = open_core();
    let sub = format!("sub://{url}");
    core.call("import", &json!({"text": sub})).expect("sub import");
    common::http_mock::wait(handle);
    let state = core.call("state", &json!({})).expect("state");
    let groups = state["groups"].as_array().unwrap();
    let remote = groups
        .iter()
        .find(|g| g["url"].as_str() == Some(url.as_str()))
        .expect("remote group");
    assert_eq!(remote["name"].as_str(), Some("SubFromScheme"));
    assert!(!captured.lock().unwrap().is_empty());
    cleanup(&dir);
}
