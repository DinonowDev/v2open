mod common;

use common::core_harness::{cleanup, open_core, SAMPLE_VLESS};
use common::http_mock;
use serde_json::json;

#[test]
fn clash_install_config_subscribes() {
    let (url, captured, handle) = http_mock::serve_once(
        SAMPLE_VLESS,
        http_mock::MockHeaders::default().push("Profile-Title", "ClashImport"),
    );
    let (mut core, dir) = open_core();
    let link = format!("clash://install-config?url={url}");
    core.call("import", &json!({"text": link})).expect("import");
    http_mock::wait(handle);
    let state = core.call("state", &json!({})).expect("state");
    let remote = state["groups"]
        .as_array()
        .unwrap()
        .iter()
        .find(|g| g["url"].as_str() == Some(url.as_str()))
        .expect("remote group from clash deeplink");
    assert_eq!(remote["name"].as_str(), Some("ClashImport"));
    assert!(!captured.lock().unwrap().is_empty());
    cleanup(&dir);
}
