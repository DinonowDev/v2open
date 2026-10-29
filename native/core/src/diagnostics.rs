use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

pub fn parse_ifconfig(text: &str, wifi_iface: &str) -> Vec<Value> {
    let mut rows = Vec::new();
    let mut name = String::new();
    let mut flags = String::new();
    let mut ipv4 = String::new();
    let mut ipv6 = String::new();
    let flush = |name: &str, flags: &str, ipv4: &str, ipv6: &str, wifi_iface: &str, rows: &mut Vec<Value>| {
        if name.is_empty() {
            return;
        }
        if skip_iface(name) {
            return;
        }
        if ipv4.is_empty() && ipv6.is_empty() {
            return;
        }
        let up = flags.to_ascii_uppercase().contains("UP") || flags.contains("<UP");
        rows.push(json!({
            "name": name,
            "kind": iface_kind(name, wifi_iface),
            "ipv4": ipv4,
            "ipv6": ipv6,
            "status": if up { "active" } else { "inactive" }
        }));
    };
    for line in text.lines() {
        if !line.starts_with('\t') && !line.starts_with(' ') && line.contains(':') {
            flush(&name, &flags, &ipv4, &ipv6, wifi_iface, &mut rows);
            name = line.split(':').next().unwrap_or("").trim().to_string();
            flags = line.to_string();
            ipv4.clear();
            ipv6.clear();
            continue;
        }
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("inet ") {
            if ipv4.is_empty() {
                ipv4 = rest.split_whitespace().next().unwrap_or("").to_string();
            }
        } else if let Some(rest) = trimmed.strip_prefix("inet6 ") {
            let candidate = rest.split_whitespace().next().unwrap_or("");
            if ipv6.is_empty() && !candidate.starts_with("fe80:") && !candidate.contains('%') {
                ipv6 = candidate.split('%').next().unwrap_or(candidate).to_string();
            }
        }
    }
    flush(&name, &flags, &ipv4, &ipv6, wifi_iface, &mut rows);
    rows
}

pub fn iface_names_from_rows(rows: &[Value]) -> Vec<String> {
    rows.iter()
        .filter_map(|row| {
            let name = row["name"].as_str().unwrap_or("");
            if name.is_empty() || crate::platform::is_tunnel_iface(name) {
                None
            } else {
                Some(name.to_string())
            }
        })
        .collect()
}

pub fn parse_scutil_proxy(text: &str) -> Value {
    let mut map = BTreeMap::new();
    for line in text.lines() {
        let line = line.trim().trim_start_matches('<').trim_end_matches('>');
        let Some((key, value)) = line.split_once(':') else { continue };
        let key = key.trim();
        let value = value.trim();
        if key.is_empty() || key == "dictionary" || key == "array" {
            continue;
        }
        map.insert(key.to_string(), value.to_string());
    }
    let http = proxy_entry(&map, "HTTPEnable", "HTTPProxy", "HTTPPort");
    let https = proxy_entry(&map, "HTTPSEnable", "HTTPSProxy", "HTTPSPort");
    let socks = proxy_entry(&map, "SOCKSEnable", "SOCKSProxy", "SOCKSPort");
    let pac_on = flag_on(map.get("ProxyAutoConfigEnable").map(String::as_str));
    let pac_url = map.get("ProxyAutoConfigURLString").cloned().unwrap_or_default();
    let active = http["enabled"].as_bool() == Some(true)
        || https["enabled"].as_bool() == Some(true)
        || socks["enabled"].as_bool() == Some(true)
        || (pac_on && !pac_url.is_empty());
    json!({
        "active": active,
        "http": http,
        "https": https,
        "socks": socks,
        "pac": { "enabled": pac_on && !pac_url.is_empty(), "url": pac_url },
        "raw": text
    })
}

pub fn parse_dns_nameservers(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        let Some(rest) = line.split_once("nameserver[") else { continue };
        let Some((_, value)) = rest.1.split_once(':') else { continue };
        let ip = value.trim();
        if ip.is_empty() || out.iter().any(|item: &String| item == ip) {
            continue;
        }
        out.push(ip.to_string());
    }
    out
}

pub fn parse_default_route(text: &str) -> (String, String) {
    let mut gateway = String::new();
    let mut iface = String::new();
    for line in text.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("gateway:") {
            gateway = rest.trim().to_string();
        } else if let Some(rest) = line.strip_prefix("interface:") {
            iface = rest.trim().to_string();
        }
    }
    (gateway, iface)
}

pub fn parse_route_rows(text: &str) -> Vec<String> {
    text.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .filter(|line| line.contains('.') || line.contains("default") || line.contains("Destination"))
        .take(80)
        .map(|line| line.to_string())
        .collect()
}

pub fn file_entry(name: &str, path: &Path) -> Value {
    let meta = fs::metadata(path).ok();
    json!({
        "name": name,
        "path": path.display().to_string(),
        "exists": meta.is_some(),
        "size": meta.as_ref().map(|m| m.len()).unwrap_or(0)
    })
}

pub fn tun_from_rows(rows: &[Value]) -> Value {
    rows.iter()
        .find(|row| row["kind"].as_str() == Some("tun"))
        .cloned()
        .unwrap_or(json!({"name": "", "ipv4": "", "ipv6": "", "kind": "tun", "status": "inactive"}))
}

fn proxy_entry(map: &BTreeMap<String, String>, enable: &str, host: &str, port: &str) -> Value {
    let enabled = flag_on(map.get(enable).map(String::as_str));
    let host = map.get(host).cloned().unwrap_or_default();
    let port = map.get(port).cloned().unwrap_or_default();
    let summary = if enabled && !host.is_empty() {
        if port.is_empty() { host.clone() } else { format!("{host}:{port}") }
    } else {
        String::new()
    };
    json!({ "enabled": enabled, "host": host, "port": port, "summary": summary })
}

fn flag_on(value: Option<&str>) -> bool {
    matches!(value, Some("1") | Some("true") | Some("YES") | Some("yes"))
}

fn skip_iface(name: &str) -> bool {
    let n = name.to_ascii_lowercase();
    n == "lo0"
        || n.starts_with("lo")
        || n.starts_with("awdl")
        || n.starts_with("llw")
        || n.starts_with("gif")
        || n.starts_with("stf")
        || n.starts_with("anpi")
        || n.starts_with("ap")
        || n.starts_with("bridge")
}

fn iface_kind(name: &str, wifi_iface: &str) -> &'static str {
    let n = name.to_ascii_lowercase();
    if !wifi_iface.is_empty() && name == wifi_iface {
        return "wifi";
    }
    if n.starts_with("utun") || n.starts_with("ipsec") || n.starts_with("ppp") {
        return "tun";
    }
    if n.starts_with("en") {
        return "ethernet";
    }
    "other"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_ifconfig_wifi_and_tun() {
        let text = "\
en0: flags=8863<UP,BROADCAST,RUNNING> mtu 1500
	inet 192.168.1.10 netmask 0xffffff00 broadcast 192.168.1.255
	inet6 fe80::1%en0 prefixlen 64 scopeid 0x7
	inet6 2a00:1::10 prefixlen 64
utun4: flags=8051<UP,POINTOPOINT,RUNNING> mtu 1500
	inet 172.19.0.1 --> 172.19.0.2 netmask 0xfffffffc
lo0: flags=8049<UP,LOOPBACK,RUNNING>
	inet 127.0.0.1 netmask 0xff000000
";
        let rows = parse_ifconfig(text, "en0");
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0]["name"], "en0");
        assert_eq!(rows[0]["kind"], "wifi");
        assert_eq!(rows[0]["ipv4"], "192.168.1.10");
        assert_eq!(rows[0]["ipv6"], "2a00:1::10");
        assert_eq!(rows[1]["name"], "utun4");
        assert_eq!(rows[1]["kind"], "tun");
        assert_eq!(rows[1]["ipv4"], "172.19.0.1");
        let names = iface_names_from_rows(&rows);
        assert_eq!(names, vec!["en0".to_string()]);
        let tun = tun_from_rows(&rows);
        assert_eq!(tun["name"], "utun4");
    }

    #[test]
    fn parses_system_proxy_and_dns() {
        let proxy = parse_scutil_proxy(
            "\
<dictionary> {
  HTTPEnable : 1
  HTTPPort : 10807
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 0
  SOCKSEnable : 1
  SOCKSPort : 10808
  SOCKSProxy : 127.0.0.1
  ProxyAutoConfigEnable : 0
}
",
        );
        assert_eq!(proxy["active"], true);
        assert_eq!(proxy["http"]["summary"], "127.0.0.1:10807");
        assert_eq!(proxy["socks"]["enabled"], true);
        assert_eq!(proxy["https"]["enabled"], false);

        let dns = parse_dns_nameservers(
            "\
resolver #1
  nameserver[0] : 1.1.1.1
  nameserver[1] : 8.8.8.8
resolver #2
  nameserver[0] : 1.1.1.1
",
        );
        assert_eq!(dns, vec!["1.1.1.1".to_string(), "8.8.8.8".to_string()]);

        let (gateway, iface) = parse_default_route("gateway: 192.168.1.1\ninterface: en0\n");
        assert_eq!(gateway, "192.168.1.1");
        assert_eq!(iface, "en0");
    }
}
