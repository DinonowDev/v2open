use serde_json::{json, Value};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use v2core::Core;

const SITES: &[(&str, &str)] = &[
    ("تلگرام", "https://telegram.org"),
    ("یوتیوب", "https://www.youtube.com"),
    ("اینستاگرام", "https://www.instagram.com"),
];

#[test]
#[ignore = "dials the saved profile and must always tear the tunnel down"]
fn connection_matrix() {
    let home = std::env::var("HOME").expect("HOME");
    let data = PathBuf::from(home).join("Library/Application Support/V2Open");
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let report = root.join("dev-logs/connection-matrix.txt");
    let _ = fs::create_dir_all(report.parent().unwrap());
    let _ = fs::write(&report, "");
    let _ = Command::new("pkill").args(["-9", "-f", "V2Open-Dev.app/Contents/MacOS/V2Open"]).status();

    let bin = root.join("binaries/macos/sing-box");
    let mut core = Core::open(data.clone(), bin.clone(), data.join("rulesets"));
    let state = core.call("state", &json!({})).expect("state");
    let id = state["settings"]["selected_id"].as_str().unwrap_or("").to_string();
    assert!(!id.is_empty(), "no selected config");
    let saved = json!({
        "mode": state["settings"]["mode"].clone(),
        "apply_system_proxy": state["settings"]["apply_system_proxy"].clone(),
        "per_app_mode": state["settings"]["per_app_mode"].clone(),
        "per_app_text": state["settings"]["per_app_text"].clone(),
        "kill_switch": state["settings"]["kill_switch"].clone(),
        "on_demand": state["settings"]["on_demand"].clone()
    });
    let iface = default_iface();
    note(&report, &format!("iface {iface}"));

    let mut rows = Vec::new();
    rows.push(run_baseline(&report, &iface));

    let scenarios = [
        Scenario { name: "SOCKS اپ، بدون پروکسی سیستم", mode: "proxy", system_proxy: false, per_app: "off", list: "", via: Via::Socks },
        Scenario { name: "پروکسی سیستم", mode: "proxy", system_proxy: true, per_app: "off", list: "", via: Via::System },
        Scenario { name: "تونل، به‌جز محیط توسعه", mode: "tun", system_proxy: false, per_app: "exclude", list: "Cursor\nCursor Helper\nCursor Helper (Plugin)\nCursor Helper (Renderer)\nCursor Helper (GPU)", via: Via::Route },
        Scenario { name: "تونل، فقط Safari", mode: "tun", system_proxy: false, per_app: "include", list: "Safari", via: Via::Route },
        Scenario { name: "تونل، همه برنامه‌ها", mode: "tun", system_proxy: false, per_app: "off", list: "", via: Via::Route },
    ];

    let mut abort = false;
    for scenario in scenarios {
        if abort {
            rows.push(Row { name: scenario.name.into(), cells: ["متوقف شد".into(), "متوقف شد".into(), "متوقف شد".into()], note: "شبکه برنگشت".into() });
            continue;
        }
        let row = run_scenario(&mut core, &data, &bin, &id, &report, &iface, &scenario);
        if row.note.contains("شبکه برنگشت") {
            abort = true;
        }
        rows.push(row);
    }

    restore(&mut core, &data, &bin, &saved);
    if !direct_ok(&iface) {
        force_stop(&data, &bin);
    }
    note(&report, "TABLE");
    for row in &rows {
        note(&report, &format!("{}\t{}\t{}\t{}\t{}", row.name, row.cells[0], row.cells[1], row.cells[2], row.note));
    }
}

struct Scenario {
    name: &'static str,
    mode: &'static str,
    system_proxy: bool,
    per_app: &'static str,
    list: &'static str,
    via: Via,
}

#[derive(Clone, Copy)]
enum Via { Socks, System, Route }

struct Row {
    name: String,
    cells: [String; 3],
    note: String,
}

fn run_baseline(report: &PathBuf, iface: &str) -> Row {
    let mut cells = [String::new(), String::new(), String::new()];
    for (i, (label, url)) in SITES.iter().enumerate() {
        let (code, ms, err) = curl(url, None, Some(iface));
        cells[i] = fmt_cell(code, ms, &err);
        note(report, &format!("baseline {label} {}", cells[i]));
    }
    Row { name: "بدون اتصال اپ".into(), cells, note: "مسیر فعلی سیستم".into() }
}

fn run_scenario(core: &mut Core, data: &PathBuf, bin: &PathBuf, id: &str, report: &PathBuf, iface: &str, scenario: &Scenario) -> Row {
    let _ = core.call("set", &json!({"key": "kill_switch", "value": false}));
    let _ = core.call("set", &json!({"key": "on_demand", "value": false}));
    let _ = core.call("set", &json!({"key": "mode", "value": scenario.mode}));
    let _ = core.call("set", &json!({"key": "apply_system_proxy", "value": scenario.system_proxy}));
    let _ = core.call("set", &json!({"key": "per_app_mode", "value": scenario.per_app}));
    let _ = core.call("set", &json!({"key": "per_app_text", "value": scenario.list}));
    note(report, &format!("connect {}", scenario.name));
    let connected = call_with_timeout(core, "connect", json!({"id": id, "smart": false}), if scenario.mode == "tun" { 25 } else { 12 });
    let mut cells = [String::new(), String::new(), String::new()];
    let mut note_text = String::new();
    let mut failed = false;
    match connected {
        Ok(state) => {
            let port = state["settings"]["socks_port"].as_u64().unwrap_or(10808) as u16;
            if scenario.system_proxy && !system_proxy_on() {
                note_text = "پروکسی سیستم روشن نشد".into();
                failed = true;
            }
            if !failed {
                for (i, (label, url)) in SITES.iter().enumerate() {
                    let (code, ms, err) = match scenario.via {
                        Via::Socks | Via::System => curl(url, Some(port), None),
                        Via::Route => curl(url, None, None),
                    };
                    cells[i] = fmt_cell(code, ms, &err);
                    note(report, &format!("{} {label} {}", scenario.name, cells[i]));
                    if !ok_code(code) {
                        failed = true;
                    }
                }
            }
            if failed {
                for cell in cells.iter_mut() {
                    if cell.is_empty() { *cell = "قطع شد".into(); }
                }
                note_text = if note_text.is_empty() { "ناموفق، اتصال بسته شد".into() } else { note_text };
            } else if note_text.is_empty() {
                note_text = "هر سه سایت باز شدند".into();
            }
        }
        Err(err) => {
            cells = ["متصل نشد".into(), "متصل نشد".into(), "متصل نشد".into()];
            note_text = trim_err(&err);
            failed = true;
            note(report, &format!("{} connect {}", scenario.name, note_text));
        }
    }
    cleanup(core, data, bin);
    if !direct_ok(iface) {
        force_stop(data, bin);
        thread::sleep(Duration::from_secs(1));
        if !direct_ok(iface) {
            note_text = format!("{note_text}؛ شبکه برنگشت");
        }
    }
    let _ = failed;
    Row { name: scenario.name.into(), cells, note: note_text }
}

fn call_with_timeout(core: &mut Core, method: &str, args: Value, seconds: u64) -> Result<Value, String> {
    let stop = Arc::new(AtomicBool::new(false));
    let flag = stop.clone();
    thread::spawn(move || {
        for _ in 0..seconds {
            if flag.load(Ordering::Relaxed) { return; }
            thread::sleep(Duration::from_secs(1));
        }
        if !flag.load(Ordering::Relaxed) {
            let _ = Command::new("pkill").args(["-f", "V2Open needs permission"]).status();
        }
    });
    let result = core.call(method, &args).map_err(|e| e);
    stop.store(true, Ordering::Relaxed);
    result
}

fn cleanup(core: &mut Core, data: &PathBuf, bin: &PathBuf) {
    let _ = call_with_timeout(core, "disconnect", json!({}), 12);
    force_stop(data, bin);
}

fn force_stop(data: &PathBuf, bin: &PathBuf) {
    if let Ok(pid) = fs::read_to_string(data.join("core.pid")) {
        let pid = pid.trim();
        if !pid.is_empty() {
            let _ = Command::new("kill").args(["-9", pid]).status();
            let _ = Command::new("sudo").args(["-n", "kill", "-9", pid]).status();
        }
    }
    let _ = Command::new("pkill").args(["-9", "-f", &bin.display().to_string()]).status();
    thread::sleep(Duration::from_millis(200));
    if Command::new("pgrep").args(["-f", &bin.display().to_string()]).status().map(|s| s.success()).unwrap_or(false) {
        let _ = Command::new("killall").args(["-9", "sing-box"]).status();
    }
}

fn restore(core: &mut Core, data: &PathBuf, bin: &PathBuf, saved: &Value) {
    cleanup(core, data, bin);
    for key in ["mode", "apply_system_proxy", "per_app_mode", "per_app_text", "kill_switch", "on_demand"] {
        if saved.get(key).is_some() {
            let _ = core.call("set", &json!({"key": key, "value": saved[key].clone()}));
        }
    }
}

fn curl(url: &str, socks: Option<u16>, iface: Option<&str>) -> (u16, u128, String) {
    let mut cmd = Command::new("curl");
    cmd.args(["-sS", "-o", "/dev/null", "-w", "%{http_code} %{time_total}", "--max-time", "12", "--connect-timeout", "8"]);
    if let Some(port) = socks {
        cmd.args(["--socks5-hostname", &format!("127.0.0.1:{port}")]);
    }
    if let Some(iface) = iface {
        cmd.args(["--interface", iface]);
    }
    cmd.arg(url);
    let started = std::time::Instant::now();
    let output = match cmd.output() {
        Ok(output) => output,
        Err(err) => return (0, started.elapsed().as_millis(), err.to_string()),
    };
    let text = String::from_utf8_lossy(&output.stdout);
    let mut parts = text.split_whitespace();
    let code = parts.next().unwrap_or("0").parse().unwrap_or(0);
    let secs: f64 = parts.next().unwrap_or("0").parse().unwrap_or(0.0);
    let err = if output.status.success() { String::new() } else { String::from_utf8_lossy(&output.stderr).trim().to_string() };
    (code, (secs * 1000.0) as u128, trim_err(&err))
}

fn ok_code(code: u16) -> bool { (200..400).contains(&code) }

fn fmt_cell(code: u16, ms: u128, err: &str) -> String {
    if ok_code(code) { format!("{code} در {ms}ms") } else if err.is_empty() { format!("ناموفق {code}") } else { format!("ناموفق: {err}") }
}

fn trim_err(err: &str) -> String {
    let line = err.lines().find(|l| !l.trim().is_empty()).unwrap_or(err);
    let mut short = line.trim().to_string();
    if short.len() > 140 { short.truncate(140); }
    short
}

fn system_proxy_on() -> bool {
    let output = Command::new("networksetup").args(["-listallnetworkservices"]).output();
    let Ok(output) = output else { return false };
    let services: Vec<String> = String::from_utf8_lossy(&output.stdout).lines().skip(1).map(|s| s.trim().to_string()).filter(|s| !s.is_empty() && !s.starts_with('*')).collect();
    services.iter().any(|service| {
        Command::new("networksetup").args(["-getsocksfirewallproxy", service]).output().ok().map(|out| String::from_utf8_lossy(&out.stdout).contains("Enabled: Yes")).unwrap_or(false)
    })
}

fn default_iface() -> String {
    let output = Command::new("route").args(["-n", "get", "1.1.1.1"]).output();
    let Ok(output) = output else { return "en0".into() };
    String::from_utf8_lossy(&output.stdout).lines().find_map(|line| line.trim().strip_prefix("interface: ").map(|s| s.to_string())).unwrap_or_else(|| "en0".into())
}

fn direct_ok(iface: &str) -> bool {
    Command::new("curl").args(["--interface", iface, "-m", "6", "-o", "/dev/null", "-sS", "https://captive.apple.com/hotspot-detect.html"]).status().map(|s| s.success()).unwrap_or(false)
        || Command::new("curl").args(["-m", "6", "-o", "/dev/null", "-sS", "https://captive.apple.com/hotspot-detect.html"]).status().map(|s| s.success()).unwrap_or(false)
}

fn note(path: &PathBuf, line: &str) {
    eprintln!("{line}");
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{line}");
        let _ = file.flush();
    }
}
