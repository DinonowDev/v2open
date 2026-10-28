use serde_json::json;
use std::path::PathBuf;
use std::process::Command;
use v2core::Core;

struct Restore {
    core: Core,
    mode: String,
    proxy: bool,
    block_udp: bool,
}

impl Drop for Restore {
    fn drop(&mut self) {
        let _ = self.core.call("disconnect", &json!({}));
        let _ = self.core.call("set", &json!({"key": "mode", "value": self.mode}));
        let _ = self.core.call("set", &json!({"key": "apply_system_proxy", "value": self.proxy}));
        let _ = self.core.call("set", &json!({"key": "block_udp_443", "value": self.block_udp}));
    }
}

#[test]
#[ignore = "uses the saved profile and a local socks port"]
fn proxy_reaches_filtered_sites() {
    let home = std::env::var("HOME").expect("HOME");
    let data = PathBuf::from(home).join("Library/Application Support/V2Open");
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let bin = root.join("binaries/macos/sing-box");
    let mut core = Core::open(data.clone(), bin, data.join("rulesets"));
    let state = core.call("state", &json!({})).expect("state");
    let id = state["settings"]["selected_id"].as_str().unwrap_or("").to_string();
    assert!(!id.is_empty(), "no selected config");
    let mode = state["settings"]["mode"].as_str().unwrap_or("tun").to_string();
    let proxy = state["settings"]["apply_system_proxy"].as_bool().unwrap_or(true);
    let block_udp = state["settings"]["block_udp_443"].as_bool().unwrap_or(true);
    let per_app = state["settings"]["per_app_mode"].as_str().unwrap_or("").to_string();
    eprintln!("mode={mode} per_app={per_app} block_udp={block_udp}");
    core.call("set", &json!({"key": "mode", "value": "proxy"})).expect("mode");
    core.call("set", &json!({"key": "apply_system_proxy", "value": false})).expect("proxy flag");
    let mut guard = Restore { core, mode, proxy, block_udp };
    let connected = guard.core.call("connect", &json!({"id": id, "smart": false}));
    if let Err(err) = &connected {
        panic!("connect failed: {err}");
    }
    let port = connected.unwrap()["settings"]["socks_port"].as_u64().unwrap_or(10808);
    let targets = ["https://telegram.org", "https://www.youtube.com", "https://www.instagram.com"];
    let mut failed = Vec::new();
    for url in targets {
        match http_status(url, port as u16) {
            Ok(code) if (200..400).contains(&code) || code == 301 || code == 302 || code == 303 || code == 307 || code == 308 => {
                eprintln!("{url} {code}");
            }
            Ok(code) => {
                eprintln!("{url} {code}");
                failed.push(format!("{url} {code}"));
            }
            Err(err) => {
                eprintln!("{url} {err}");
                failed.push(format!("{url} {err}"));
            }
        }
    }
    assert!(failed.is_empty(), "{}", failed.join("; "));
}

#[test]
#[ignore = "downloads through the saved profile"]
fn proxy_download_rate() {
    let (mut guard, port) = connect_proxy();
    let _ = &mut guard;
    match transfer("https://speed.cloudflare.com/__down?bytes=8000000", Some(port)) {
        Ok((bytes, ms)) => eprintln!("proxy down {bytes} bytes in {ms} ms ({:.2} Mbps)", mbps(bytes, ms)),
        Err(err) => panic!("{err}"),
    }
}

#[test]
#[ignore = "opens a tun, measures, then removes the hold file"]
fn tun_download_rate() {
    let home = std::env::var("HOME").expect("HOME");
    let data = PathBuf::from(home).join("Library/Application Support/V2Open");
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let bin = root.join("binaries/macos/sing-box");
    let mut core = Core::open(data.clone(), bin, data.join("rulesets"));
    let state = core.call("state", &json!({})).expect("state");
    let id = state["settings"]["selected_id"].as_str().unwrap_or("").to_string();
    assert!(!id.is_empty(), "no selected config");
    let mode = state["settings"]["mode"].as_str().unwrap_or("tun").to_string();
    let proxy = state["settings"]["apply_system_proxy"].as_bool().unwrap_or(true);
    let block_udp = state["settings"]["block_udp_443"].as_bool().unwrap_or(true);
    core.call("set", &json!({"key": "mode", "value": "tun"})).expect("mode");
    core.call("set", &json!({"key": "apply_system_proxy", "value": false})).expect("proxy flag");
    let mut guard = Restore { core, mode, proxy, block_udp };
    guard.core.call("connect", &json!({"id": id, "smart": false})).expect("connect");
    let cfg = std::fs::read_to_string(data.join("config.json")).unwrap_or_default();
    let doc: serde_json::Value = serde_json::from_str(&cfg).unwrap_or(json!({}));
    let tun = doc["inbounds"].as_array().and_then(|items| items.iter().find(|v| v["type"] == "tun"));
    eprintln!("stack {:?}", tun.and_then(|v| v["stack"].as_str()));
    let excluded = tun.and_then(|v| v["route_exclude_address"].as_array()).map(|items| items.len()).unwrap_or(0);
    eprintln!("exclude entries {excluded}");
    let down = transfer("https://speed.cloudflare.com/__down?bytes=8000000", None);
    let page = transfer("https://telegram.org", None);
    match down {
        Ok((bytes, ms)) => eprintln!("tun down {bytes} bytes in {ms} ms ({:.2} Mbps)", mbps(bytes, ms)),
        Err(err) => eprintln!("tun down failed: {err}"),
    }
    match page {
        Ok((bytes, ms)) => eprintln!("tun telegram {bytes} bytes in {ms} ms"),
        Err(err) => eprintln!("tun telegram failed: {err}"),
    }
    guard.core.call("disconnect", &json!({})).expect("disconnect");
    let _ = &mut guard;
}

fn connect_proxy() -> (Restore, u16) {
    let home = std::env::var("HOME").expect("HOME");
    let data = PathBuf::from(home).join("Library/Application Support/V2Open");
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let bin = root.join("binaries/macos/sing-box");
    let mut core = Core::open(data.clone(), bin, data.join("rulesets"));
    let state = core.call("state", &json!({})).expect("state");
    let id = state["settings"]["selected_id"].as_str().unwrap_or("").to_string();
    assert!(!id.is_empty(), "no selected config");
    let mode = state["settings"]["mode"].as_str().unwrap_or("tun").to_string();
    let proxy = state["settings"]["apply_system_proxy"].as_bool().unwrap_or(true);
    let block_udp = state["settings"]["block_udp_443"].as_bool().unwrap_or(true);
    core.call("set", &json!({"key": "mode", "value": "proxy"})).expect("mode");
    core.call("set", &json!({"key": "apply_system_proxy", "value": false})).expect("proxy flag");
    let mut guard = Restore { core, mode, proxy, block_udp };
    let connected = guard.core.call("connect", &json!({"id": id, "smart": false})).expect("connect");
    let port = connected["settings"]["socks_port"].as_u64().unwrap_or(10808) as u16;
    (guard, port)
}

fn mbps(bytes: u64, ms: u128) -> f64 {
    if ms == 0 { return 0.0; }
    (bytes as f64 * 8.0) / (ms as f64 / 1000.0) / 1_000_000.0
}

fn transfer(url: &str, port: Option<u16>) -> Result<(u64, u128), String> {
    let mut args = vec![
        "--silent".to_string(),
        "--show-error".to_string(),
        "--max-time".to_string(),
        "25".to_string(),
        "-o".to_string(),
        "/dev/null".to_string(),
        "-w".to_string(),
        "%{size_download} %{time_total} %{http_code}".to_string(),
    ];
    if let Some(port) = port {
        args.push("--socks5-hostname".into());
        args.push(format!("127.0.0.1:{port}"));
    }
    args.push(url.into());
    let started = std::time::Instant::now();
    let child = Command::new("curl").args(&args).output().map_err(|e| e.to_string())?;
    if !child.status.success() {
        return Err(format!("{} after {} ms", String::from_utf8_lossy(&child.stderr).trim(), started.elapsed().as_millis()));
    }
    let text = String::from_utf8_lossy(&child.stdout);
    let mut parts = text.split_whitespace();
    let bytes: f64 = parts.next().unwrap_or("0").parse().map_err(|e: std::num::ParseFloatError| e.to_string())?;
    let secs: f64 = parts.next().unwrap_or("0").parse().map_err(|e: std::num::ParseFloatError| e.to_string())?;
    let code: u16 = parts.next().unwrap_or("0").parse().map_err(|e: std::num::ParseIntError| e.to_string())?;
    if !(200..400).contains(&code) {
        return Err(format!("http {code}"));
    }
    Ok((bytes as u64, (secs * 1000.0) as u128))
}

fn http_status(url: &str, port: u16) -> Result<u16, String> {
    let mut child = Command::new("curl")
        .args([
            "--silent",
            "--show-error",
            "--max-time",
            "25",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            "--socks5-hostname",
            &format!("127.0.0.1:{port}"),
            url,
        ])
        .output()
        .map_err(|e| e.to_string())?;
    if !child.status.success() {
        return Err(String::from_utf8_lossy(&child.stderr).trim().to_string());
    }
    String::from_utf8_lossy(&child.stdout).trim().parse::<u16>().map_err(|e| e.to_string())
}
