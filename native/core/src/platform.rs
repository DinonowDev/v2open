use std::path::PathBuf;
use std::process::Command;

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct NetStatus {
    pub kind: String,
    pub ssid: String,
    pub iface: String,
    pub wifi_iface: String,
    pub cell_iface: String,
    pub has_wifi: bool,
    pub has_cellular: bool,
    pub has_ethernet: bool,
}

pub fn status() -> NetStatus {
    mac_status()
}

pub fn icloud_library() -> Option<PathBuf> {
    let home = PathBuf::from(std::env::var_os("HOME")?);
    let candidates = [
        home.join("Library/Mobile Documents/com~apple~CloudDocs"),
        home.join("iCloudDrive"),
        home.join("Library/Mobile Documents/com~apple~CloudDocs"),
    ];
    for base in candidates {
        if base.is_dir() {
            let dir = base.join("V2Open");
            std::fs::create_dir_all(&dir).ok()?;
            return Some(dir.join("library.json"));
        }
    }
    None
}

pub fn process_rss_bytes(pid: u32) -> u64 {
    if pid == 0 {
        return 0;
    }
    let out = command(&["ps", "-o", "rss=", "-p", &pid.to_string()]);
    let kb = out.trim().parse::<u64>().unwrap_or(0);
    kb * 1024
}

pub fn alive(pid: u32) -> bool {
    if pid == 0 {
        return false;
    }
    Command::new("ps").args(["-p", &pid.to_string()]).output().map(|out| out.status.success()).unwrap_or(false)
}

pub fn is_tunnel_iface(name: &str) -> bool {
    let n = name.to_ascii_lowercase();
    n.starts_with("utun")
        || n.starts_with("ipsec")
        || n.starts_with("ppp")
        || n.starts_with("awdl")
        || n.starts_with("llw")
        || n.starts_with("ap")
        || n.starts_with("gif")
        || n.starts_with("stf")
        || n.starts_with("bridge")
        || n == "lo0"
        || n.starts_with("lo")
}

pub fn physical_iface() -> Option<String> {
    let text = command(&["ifconfig"]);
    let mut current = String::new();
    let mut fallback = None;
    for line in text.lines() {
        if !line.starts_with('\t') && !line.starts_with(' ') {
            current = line.split(':').next().unwrap_or("").trim().to_string();
            continue;
        }
        let Some(rest) = line.trim().strip_prefix("inet ") else { continue };
        let ip = rest.split_whitespace().next().unwrap_or("");
        if ip.is_empty() || dummy_vpn_ip(ip) || is_tunnel_iface(&current) {
            continue;
        }
        if current.starts_with("en") {
            return Some(current);
        }
        if fallback.is_none() {
            fallback = Some(current.clone());
        }
    }
    fallback
}

fn dummy_vpn_ip(ip: &str) -> bool {
    ip.starts_with("127.")
        || ip.starts_with("169.254.")
        || ip.starts_with("240.")
        || ip.starts_with("198.18.")
        || ip.starts_with("198.19.")
        || ip.starts_with("172.19.0.")
}

fn mac_status() -> NetStatus {
    let ports = command(&["networksetup", "-listallhardwareports"]);
    let mut wifi = String::new();
    let mut cell = String::new();
    let mut cellular = false;
    let mut ethernet = false;
    let mut current = String::new();
    for line in ports.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("Hardware Port:") {
            current = rest.trim().to_string();
        } else if let Some(rest) = line.strip_prefix("Device:") {
            let device = rest.trim();
            let name = current.to_ascii_lowercase();
            if name.contains("wi-fi") || name.contains("airport") {
                wifi = device.to_string();
            } else if name.contains("iphone") || name.contains("cellular") {
                cellular = true;
                cell = device.to_string();
            } else if name.contains("ethernet") || name.contains("lan") || name.contains("thunderbolt") {
                ethernet = true;
            }
        }
    }
    let route = command(&["route", "-n", "get", "default"]);
    let iface = route.lines().find_map(|l| l.trim().strip_prefix("interface:").map(|s| s.trim().to_string())).unwrap_or_default();
    let ssid = if wifi.is_empty() {
        String::new()
    } else {
        let out = command(&["networksetup", "-getairportnetwork", &wifi]);
        out.split(':').nth(1).map(|s| s.trim().to_string()).filter(|s| !s.is_empty() && !s.to_ascii_lowercase().contains("not associated")).unwrap_or_default()
    };
    let kind = if !ssid.is_empty() || iface == wifi {
        "wifi".into()
    } else if cellular {
        "cellular".into()
    } else if ethernet {
        "ethernet".into()
    } else {
        "other".into()
    };
    let has_wifi = !wifi.is_empty();
    NetStatus { kind, ssid, iface, wifi_iface: wifi, cell_iface: cell, has_wifi, has_cellular: cellular, has_ethernet: ethernet }
}

fn command(args: &[&str]) -> String {
    let Some((bin, rest)) = args.split_first() else { return String::new() };
    Command::new(bin).args(rest).output().map(|o| String::from_utf8_lossy(&o.stdout).to_string()).unwrap_or_default()
}

fn osa_escape(text: &str) -> String {
    text.replace('\\', "\\\\").replace('"', "\\\"")
}

/// AppleScript `do shell script` that runs a bash script path (handles spaces in `Application Support`, etc.).
pub fn osa_run_bash_script(script: &std::path::Path, prompt: &str) -> String {
    let path = osa_escape(&script.display().to_string());
    let prompt = osa_escape(prompt);
    format!(
        "do shell script \"bash \" & quoted form of \"{path}\" with administrator privileges with prompt \"{prompt}\""
    )
}

/// Launch `bin args` so it survives AppleScript `do shell script`.
/// `nohup` fails there with "can't detach from console: Inappropriate ioctl for device".
pub fn bash_detach_script(bin: &std::path::Path, args: &[&str], log: &std::path::Path, pidfile: &std::path::Path) -> String {
    let mut exec = format!("{:?}", bin);
    for arg in args {
        exec.push(' ');
        exec.push_str(&format!("{:?}", arg));
    }
    format!(
        "#!/bin/bash\nexport NO_COLOR=1 CLICOLOR=0 TERM=dumb\nLOG={:?}\nPIDFILE={:?}\n(\n  trap '' HUP\n  exec </dev/null\n  exec >>\"$LOG\" 2>&1\n  exec {exec}\n) &\necho $! > \"$PIDFILE\"\n",
        log,
        pidfile
    )
}

/// Root tunnel that exits when `watch_pid` dies or `hold` is removed.
/// Closing the app, including a force quit, deletes the tunnel without a second password prompt.
pub fn bash_supervised_script(bin: &std::path::Path, args: &[&str], log: &std::path::Path, pidfile: &std::path::Path, watch_pid: u32, hold: &std::path::Path) -> String {
    let mut exec = format!("{:?}", bin);
    for arg in args {
        exec.push(' ');
        exec.push_str(&format!("{:?}", arg));
    }
    let support = hold.parent().unwrap_or(std::path::Path::new("."));
    format!(
        r#"#!/bin/bash
export NO_COLOR=1 CLICOLOR=0 TERM=dumb
BIN={bin:?}
LOG={log:?}
PIDFILE={pidfile:?}
HOLD={hold:?}
APP_PID={watch_pid}
SUPPORT={support:?}
stop_one() {{
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill -TERM "$pid" 2>/dev/null || true
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.2
  done
  kill -KILL "$pid" 2>/dev/null || true
}}
if [ -f "$PIDFILE" ]; then
  OLD=$(tr -d '[:space:]' < "$PIDFILE" 2>/dev/null || true)
  CMD=$(ps -p "$OLD" -o command= 2>/dev/null || true)
  case "$CMD" in
    *"$BIN"*) stop_one "$OLD" ;;
  esac
fi
(
  trap '' HUP
  exec </dev/null
  {exec} >>"$LOG" 2>&1 &
  SB=$!
  echo "$SB" > "$PIDFILE"
  while kill -0 "$APP_PID" 2>/dev/null && kill -0 "$SB" 2>/dev/null && [ -f "$HOLD" ]; do
    sleep 0.5
  done
  stop_one "$SB"
  pkill -f "$SUPPORT/xray-" 2>/dev/null || true
  rm -f "$PIDFILE" "$HOLD"
) >/dev/null 2>&1 &
disown || true
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  PID=$(tr -d '[:space:]' < "$PIDFILE" 2>/dev/null || true)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    exit 0
  fi
  sleep 0.1
done
exit 1
"#
    )
}

#[cfg(all(test, target_os = "macos"))]
mod tests {
    use super::*;

    #[test]
    fn physical_iface_skips_tunnels() {
        if let Some(name) = physical_iface() {
            assert!(!is_tunnel_iface(&name), "{name}");
        }
    }

    #[test]
    fn supervised_script_is_valid_bash() {
        let path = std::env::temp_dir().join("v2open-supervised-test.sh");
        let script = bash_supervised_script(
            std::path::Path::new("/usr/bin/true"),
            &["run", "-c", "/tmp/v2 open/config.json"],
            std::path::Path::new("/tmp/v2 open/core.log"),
            std::path::Path::new("/tmp/v2 open/core.pid"),
            1,
            std::path::Path::new("/tmp/v2 open/core.hold"),
        );
        std::fs::write(&path, &script).unwrap();
        let status = Command::new("bash").arg("-n").arg(&path).status().unwrap();
        let _ = std::fs::remove_file(&path);
        assert!(status.success(), "{script}");
    }
}
