mod common;

use common::core_harness::{cleanup, open_core};
use serde_json::json;

#[test]
fn route_sets_migrate_and_switch() {
    let (mut core, dir) = open_core();
    let state = core.call("state", &json!({})).expect("state");
    let sets = state["route_sets"].as_array().expect("route_sets");
    assert!(!sets.is_empty());
    let active = state["settings"]["active_route_set_id"].as_str().unwrap();
    assert!(sets.iter().any(|s| s["id"].as_str() == Some(active)));

    let created = core
        .call("create_route_set", &json!({"name": "Work"}))
        .expect("create");
    let work_id = created["id"].as_str().expect("id");

    core.call(
        "save_route",
        &json!({
            "route": {
                "enabled": true,
                "remark": "test-rule",
                "behavior": "direct",
                "domains": ["example.com"]
            }
        }),
    )
    .expect("save_route");

    core.call("select_route_set", &json!({"id": work_id}))
        .expect("select");
    let state = core.call("state", &json!({})).expect("state");
    assert_eq!(state["settings"]["active_route_set_id"].as_str(), Some(work_id));
    assert!(state["routes"].as_array().map(|a| a.is_empty()).unwrap_or(false));

    core.call("select_route_set", &json!({"id": active}))
        .expect("back");
    let state = core.call("state", &json!({})).expect("state");
    let rules = state["routes"].as_array().unwrap();
    assert!(rules.iter().any(|r| r["remark"].as_str() == Some("test-rule")));

    core.call("duplicate_route_set", &json!({"id": active}))
        .expect("duplicate");
    let state = core.call("state", &json!({})).expect("state");
    assert!(state["route_sets"].as_array().unwrap().len() >= 3);
    cleanup(&dir);
}

#[test]
fn rename_route_set_rpc() {
    let (mut core, dir) = open_core();
    let state = core.call("state", &json!({})).unwrap();
    let active = state["settings"]["active_route_set_id"].as_str().unwrap();
    core.call("rename_route_set", &json!({"id": active, "name": "Home"})).unwrap();
    let state = core.call("state", &json!({})).unwrap();
    let named = state["route_sets"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["id"].as_str() == Some(active))
        .unwrap();
    assert_eq!(named["name"].as_str(), Some("Home"));
    cleanup(&dir);
}

#[test]
fn reorder_routes_persists_in_active_set() {
    let (mut core, dir) = open_core();
    for i in 0..3 {
        core.call(
            "save_route",
            &json!({
                "route": {
                    "enabled": true,
                    "remark": format!("r{i}"),
                    "behavior": "direct",
                    "domains": [format!("{i}.test")]
                }
            }),
        )
        .unwrap();
    }
    let state = core.call("state", &json!({})).unwrap();
    let ids: Vec<String> = state["routes"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|r| r["id"].as_str().map(|s| s.to_string()))
        .collect();
    let mut reordered = ids.clone();
    reordered.reverse();
    core.call("reorder_routes", &json!({"ids": reordered}))
        .unwrap();

    let active = state["settings"]["active_route_set_id"].as_str().unwrap();
    core.call("create_route_set", &json!({"name": "Other"})).unwrap();
    core.call("select_route_set", &json!({"id": active})).unwrap();
    let state = core.call("state", &json!({})).unwrap();
    let remarks: Vec<&str> = state["routes"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|r| r["remark"].as_str())
        .collect();
    assert_eq!(remarks, vec!["r2", "r1", "r0"]);
    cleanup(&dir);
}
