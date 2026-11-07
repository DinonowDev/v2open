mod common;

use common::core_harness::{cleanup, open_core};
use serde_json::json;

#[test]
fn clear_group_removes_local_group() {
    let (mut core, dir) = open_core();
    let state = core.call("state", &json!({})).unwrap();
    let local_id = state["groups"]
        .as_array()
        .unwrap()
        .iter()
        .find(|g| g["kind"].as_str() == Some("local"))
        .map(|g| g["id"].as_str().unwrap().to_string())
        .unwrap();
    core.call("rename_group", &json!({"id": local_id, "name": "Custom local"})).unwrap();
    let before = core.call("state", &json!({})).unwrap();
    assert!(
        before["groups"]
            .as_array()
            .unwrap()
            .iter()
            .any(|g| g["name"].as_str() == Some("Custom local"))
    );
    core.call("clear_group", &json!({"id": local_id})).unwrap();
    let after = core.call("state", &json!({})).unwrap();
    assert!(
        !after["groups"]
            .as_array()
            .unwrap()
            .iter()
            .any(|g| g["id"].as_str() == Some(local_id.as_str()))
    );
    assert!(
        after["groups"]
            .as_array()
            .unwrap()
            .iter()
            .any(|g| g["kind"].as_str() == Some("local"))
    );
    cleanup(&dir);
}

#[test]
fn restore_group_after_clear() {
    let (mut core, dir) = open_core();
    let state = core.call("state", &json!({})).unwrap();
    let local = state["groups"][0].clone();
    let id = local["id"].as_str().unwrap();
    core.call("rename_group", &json!({"id": id, "name": "Undo me"})).unwrap();
    let state = core.call("state", &json!({})).unwrap();
    let snapshot = state["groups"]
        .as_array()
        .unwrap()
        .iter()
        .find(|g| g["id"].as_str() == Some(id))
        .cloned()
        .unwrap();
    core.call("clear_group", &json!({"id": id})).unwrap();
    core.call("restore_group", &json!({"group": snapshot})).unwrap();
    let after = core.call("state", &json!({})).unwrap();
    assert!(
        after["groups"]
            .as_array()
            .unwrap()
            .iter()
            .any(|g| g["name"].as_str() == Some("Undo me"))
    );
    cleanup(&dir);
}
