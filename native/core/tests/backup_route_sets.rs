mod common;

use common::core_harness::{cleanup, open_core};
use serde_json::json;

#[test]
fn backup_restore_keeps_route_sets() {
    let (mut core, dir) = open_core();
    let state = core.call("state", &json!({})).unwrap();
    let default_id = state["settings"]["active_route_set_id"].as_str().unwrap().to_string();

    let work = core.call("create_route_set", &json!({"name": "Work"})).unwrap();
    let work_id = work["id"].as_str().unwrap().to_string();
    core.call("select_route_set", &json!({"id": default_id})).unwrap();

    core.call(
        "save_route",
        &json!({
            "route": {
                "enabled": true,
                "remark": "only-in-default",
                "behavior": "direct",
                "domains": ["backup.test"]
            }
        }),
    )
    .unwrap();

    core.call("select_route_set", &json!({"id": work_id})).unwrap();
    core.call("backup", &json!({})).unwrap();
    let state = core.call("state", &json!({})).unwrap();
    let backup_id = state["backups"][0]["id"].as_str().unwrap();

    core.call(
        "save_route",
        &json!({
            "route": {
                "enabled": true,
                "remark": "work-only",
                "behavior": "proxy",
                "domains": ["work.test"]
            }
        }),
    )
    .unwrap();

    core.call("restore", &json!({"id": backup_id})).unwrap();
    let state = core.call("state", &json!({})).unwrap();
    assert_eq!(state["settings"]["active_route_set_id"].as_str(), Some(work_id.as_str()));
    let remarks: Vec<&str> = state["routes"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|r| r["remark"].as_str())
        .collect();
    assert!(!remarks.contains(&"work-only"));

    core.call("select_route_set", &json!({"id": default_id})).unwrap();
    let state = core.call("state", &json!({})).unwrap();
    let remarks: Vec<&str> = state["routes"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|r| r["remark"].as_str())
        .collect();
    assert!(remarks.contains(&"only-in-default"));
    assert!(state["route_sets"].as_array().unwrap().len() >= 2);
    cleanup(&dir);
}
