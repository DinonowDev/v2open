mod common;

use common::core_harness::{cleanup, open_core};
use serde_json::json;

#[test]
fn rename_group_rpc() {
    let (mut core, dir) = open_core();
    let state = core.call("state", &json!({})).unwrap();
    let gid = state["groups"][0]["id"].as_str().unwrap();
    core.call("rename_group", &json!({"id": gid, "name": "My configs"})).unwrap();
    let state = core.call("state", &json!({})).unwrap();
    let group = state["groups"]
        .as_array()
        .unwrap()
        .iter()
        .find(|g| g["id"].as_str() == Some(gid))
        .unwrap();
    assert_eq!(group["name"].as_str(), Some("My configs"));
    let err = core.call("rename_group", &json!({"id": gid, "name": "   "})).unwrap_err();
    assert!(err.contains("name required"));
    cleanup(&dir);
}
