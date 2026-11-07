mod common;

use common::core_harness::{cleanup, open_core};
use serde_json::json;
use std::path::PathBuf;

#[test]
fn v2box_package_import_restores_route_sets() {
    let (mut core, dir) = open_core();
    let state = core.call("state", &json!({})).unwrap();
    let default_id = state["settings"]["active_route_set_id"].as_str().unwrap().to_string();

    let extra = core.call("create_route_set", &json!({"name": "ImportedSet"})).unwrap();
    let extra_id = extra["id"].as_str().unwrap().to_string();
    core.call("select_route_set", &json!({"id": default_id})).unwrap();
    core.call(
        "save_route",
        &json!({
            "route": {
                "enabled": true,
                "remark": "catalog-rule",
                "behavior": "direct",
                "domains": ["v2box.import"]
            }
        }),
    )
    .unwrap();

    let pack = PathBuf::from(&dir).join("catalog.v2box");
    core.call(
        "export_package",
        &json!({"path": pack.to_str().unwrap()}),
    )
    .expect("export_package");

    let (mut fresh, dir2) = open_core();
    fresh
        .call(
            "import_package",
            &json!({"path": pack.to_str().unwrap(), "allow_foreign": true}),
        )
        .expect("import_package");

    let state = fresh.call("state", &json!({})).unwrap();
    let sets = state["route_sets"].as_array().unwrap();
    assert!(sets.len() >= 2);
    assert!(sets.iter().any(|s| s["name"].as_str() == Some("ImportedSet")));
    assert_eq!(state["settings"]["active_route_set_id"].as_str(), Some(default_id.as_str()));

    fresh.call("select_route_set", &json!({"id": extra_id})).unwrap();
    let state = fresh.call("state", &json!({})).unwrap();
    assert!(state["routes"].as_array().unwrap().is_empty());

    fresh.call("select_route_set", &json!({"id": default_id})).unwrap();
    let state = fresh.call("state", &json!({})).unwrap();
    let remarks: Vec<&str> = state["routes"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|r| r["remark"].as_str())
        .collect();
    assert!(remarks.contains(&"catalog-rule"));

    cleanup(&dir);
    cleanup(&dir2);
}
