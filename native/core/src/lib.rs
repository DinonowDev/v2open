#![recursion_limit = "512"]

#[cfg(not(target_os = "macos"))]
compile_error!("v2core is macOS-only");

mod app;
mod builder;
mod dns_items;
mod migrate;
mod parser;
mod platform;
mod routing;
mod sidecar;
mod ssr;
mod vault;
mod xray;
mod xray_balancers;

pub use app::{locate_core, support_dir, Core};
pub use builder::{build_config, preset};
pub use migrate::migrate_settings;
pub use parser::{parse_clash_yaml, parse_link, parse_text};
pub use routing::{export_routes, parse_routes};
pub use xray::document as xray_document;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::Mutex;

static CORE: Mutex<Option<Core>> = Mutex::new(None);

fn c_string(value: &str) -> *mut c_char {
    CString::new(value.replace('\0', "")).unwrap_or_else(|_| CString::new("").unwrap()).into_raw()
}

/// Open the local library. Safe to call once at startup.
#[no_mangle]
pub extern "C" fn v2_init(data_dir: *const c_char, singbox: *const c_char, rules: *const c_char) -> i32 {
    let data = unsafe { CStr::from_ptr(data_dir) }.to_string_lossy();
    let bin = unsafe { CStr::from_ptr(singbox) }.to_string_lossy();
    let rule_dir = unsafe { CStr::from_ptr(rules) }.to_string_lossy();
    let core = Core::open(PathBuf::from(data.as_ref()), PathBuf::from(bin.as_ref()), PathBuf::from(rule_dir.as_ref()));
    *CORE.lock().unwrap() = Some(core);
    0
}

/// `method` is a short name and `args` is a JSON object. The returned string must be freed with `v2_free`.
#[no_mangle]
pub extern "C" fn v2_call(method: *const c_char, args: *const c_char) -> *mut c_char {
    let method = unsafe { CStr::from_ptr(method) }.to_string_lossy();
    let args_raw = unsafe { CStr::from_ptr(args) }.to_string_lossy();
    let args = serde_json::from_str::<serde_json::Value>(&args_raw).unwrap_or(serde_json::json!({}));
    if method == "speed" || method == "speed_start" || method == "speed_progress" {
        let plan = {
            let guard = CORE.lock().unwrap();
            let Some(core) = guard.as_ref() else {
                return c_string(r#"{"ok":false,"error":"not ready"}"#);
            };
            core.speed_plan()
        };
        if method == "speed_progress" {
            let value = app::speed_progress_value();
            return c_string(&serde_json::json!({"ok": true, "data": value}).to_string());
        }
        if method == "speed_start" {
            return match app::speed_start_probe(plan) {
                Ok(value) => c_string(&serde_json::json!({"ok": true, "data": value}).to_string()),
                Err(err) => c_string(&serde_json::json!({"ok": false, "error": err}).to_string()),
            };
        }
        return match app::run_speed_probe(&plan) {
            Ok(value) => c_string(&serde_json::json!({"ok": true, "data": value}).to_string()),
            Err(err) => c_string(&serde_json::json!({"ok": false, "error": err}).to_string()),
        };
    }
    let mut guard = CORE.lock().unwrap();
    let Some(core) = guard.as_mut() else {
        return c_string(r#"{"ok":false,"error":"not ready"}"#);
    };
    match core.call(&method, &args) {
        Ok(value) => c_string(&serde_json::json!({"ok": true, "data": value}).to_string()),
        Err(err) => {
            #[cfg(debug_assertions)]
            eprintln!("[v2core] {}: {}", method, err);
            c_string(&serde_json::json!({"ok": false, "error": err}).to_string())
        }
    }
}

#[no_mangle]
pub extern "C" fn v2_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)) }
    }
}
