use serde_json::json;
use std::process::Command;
use v2core::{build_config, parse_link, preset};

#[test]
fn links_pass_sing_box_check() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let rules_dir = root.join("assets/rulesets");
    let core = root.join("binaries/macos/sing-box");
    if !core.exists() || !rules_dir.exists() {
        return;
    }
    let vmess = format!(
        "vmess://{}",
        b64(&json!({
            "v":"2","ps":"VMess","add":"example.com","port":"443",
            "id":"b1a2c3d4-1111-2222-3333-444455556666","aid":"0","scy":"auto",
            "net":"ws","type":"none","host":"example.com","path":"/vm","tls":"tls","sni":"example.com"
        })
        .to_string())
    );
    let samples = [
        vmess,
        "vless://b1a2c3d4-1111-2222-3333-444455556666@example.com:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&sid=ab&type=tcp&flow=xtls-rprx-vision#Demo".into(),
        "trojan://secret@example.com:443?security=tls&sni=example.com&type=ws&path=%2Ftrojan&host=example.com#Trojan".into(),
        format!("ss://{}@example.com:8388#SS", b64("chacha20-ietf-poly1305:password")),
        "hysteria2://pass@example.com:443?sni=example.com&insecure=1#HY".into(),
        "vless://b1a2c3d4-1111-2222-3333-444455556666@example.com:443?encryption=none&security=tls&sni=example.com&type=xhttp&path=%2Fxh&host=example.com&mode=stream-one#XHTTP".into(),
    ];
    let settings = json!({
        "socks_enabled": true, "socks_port": 10808, "http_enabled": true, "http_port": 10807,
        "lan_sharing": false, "clash_port": 9097, "mux_enabled": false, "sniffing": true,
        "fragment_enabled": true, "fragment_packets": "tlshello", "fragment_interval": "10-20",
        "domain_strategy": "AsIs", "apple_direct": true, "routing_enabled": true,
        "remote_dns": "https://1.1.1.1/dns-query", "domestic_dns": "223.5.5.5",
        "query_strategy": "prefer_ipv4", "dns_cache": true, "dns_split": "ir",
        "prefer_ipv6": false, "loglevel": "info", "logging_enabled": true,
        "final": "proxy", "block_udp_443": true, "bypass_lan": true, "hosts": {"example.org":"1.2.3.4"},
        "speed_endpoint": "https://www.gstatic.com/generate_204", "allow_insecure": false
    });
    let rules = preset("iran")["rules"].as_array().cloned().unwrap_or_default();
    for link in samples {
        let node = parse_link(&link).unwrap_or_else(|e| panic!("{link} {e}"));
        let config = build_config(&settings, &[node.clone()], &rules, &rules_dir, "proxy").unwrap_or_else(|e| panic!("{} {e}", node["protocol"]));
        let file = std::env::temp_dir().join("v2open-rust-check.json");
        std::fs::write(&file, serde_json::to_string(&config).unwrap()).unwrap();
        let check = Command::new(&core).args(["check", "-c"]).arg(&file).output().unwrap();
        assert!(check.status.success(), "{} {}", node["protocol"], String::from_utf8_lossy(&check.stderr));
    }
}

#[test]
fn per_app_modes_pass_sing_box_check() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let rules_dir = root.join("assets/rulesets");
    let core = root.join("binaries/macos/sing-box");
    if !core.exists() || !rules_dir.exists() {
        return;
    }
    let node = parse_link("vless://b1a2c3d4-1111-2222-3333-444455556666@example.com:443?encryption=none&security=tls&sni=example.com&type=tcp#Demo").unwrap();
    let rules = preset("iran")["rules"].as_array().cloned().unwrap_or_default();
    for mode in ["off", "exclude", "include"] {
        let settings = json!({
            "socks_enabled": true, "socks_port": 10808, "http_enabled": false,
            "clash_port": 9097, "sniffing": true, "routing_enabled": true,
            "remote_dns": "https://1.1.1.1/dns-query", "domestic_dns": "223.5.5.5",
            "final": "proxy", "block_udp_443": true, "bypass_lan": true,
            "per_app_mode": mode,
            "per_app_text": "Safari\nFinder\nNotes"
        });
        let config = build_config(&settings, &[node.clone()], &rules, &rules_dir, "tun").unwrap();
        let file = std::env::temp_dir().join(format!("v2open-per-app-{mode}.json"));
        std::fs::write(&file, serde_json::to_string(&config).unwrap()).unwrap();
        let check = Command::new(&core).args(["check", "-c"]).arg(&file).output().unwrap();
        assert!(check.status.success(), "{mode} {}", String::from_utf8_lossy(&check.stderr));
    }
}

fn b64(text: &str) -> String {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in text.as_bytes().chunks(3) {
        let b0 = chunk[0];
        let b1 = *chunk.get(1).unwrap_or(&0);
        let b2 = *chunk.get(2).unwrap_or(&0);
        out.push(T[(b0 >> 2) as usize] as char);
        out.push(T[(((b0 & 3) << 4) | (b1 >> 4)) as usize] as char);
        if chunk.len() > 1 {
            out.push(T[(((b1 & 15) << 2) | (b2 >> 6)) as usize] as char);
        } else {
            out.push('=');
        }
        if chunk.len() > 2 {
            out.push(T[(b2 & 63) as usize] as char);
        } else {
            out.push('=');
        }
    }
    out
}
