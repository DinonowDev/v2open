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

fn check_settings() -> serde_json::Value {
    json!({
        "socks_enabled": true, "socks_port": 10808, "http_enabled": true, "http_port": 10807,
        "clash_port": 9097, "sniffing": true, "routing_enabled": true,
        "remote_dns": "https://1.1.1.1/dns-query", "domestic_dns": "223.5.5.5",
        "final": "proxy", "block_udp_443": true, "bypass_lan": true, "dns_split": "ir"
    })
}

fn sing_box_accepts(settings: &serde_json::Value, nodes: &[serde_json::Value], label: &str) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let rules_dir = root.join("assets/rulesets");
    let core = root.join("binaries/macos/sing-box");
    if !core.exists() || !rules_dir.exists() {
        return;
    }
    let rules = preset("iran")["rules"].as_array().cloned().unwrap_or_default();
    let config = build_config(settings, nodes, &rules, &rules_dir, "tun").unwrap_or_else(|e| panic!("{label}: {e}"));
    let file = std::env::temp_dir().join(format!("v2open-check-{}.json", label.replace(' ', "-")));
    std::fs::write(&file, serde_json::to_string_pretty(&config).unwrap()).unwrap();
    let check = Command::new(&core).args(["check", "-c"]).arg(&file).output().unwrap();
    assert!(check.status.success(), "{label}: {}\n{}", String::from_utf8_lossy(&check.stderr), serde_json::to_string_pretty(&config).unwrap());
}

fn warp_profile(wow: bool) -> serde_json::Value {
    json!({
        "protocol": "warp", "remark": "WARP", "address": "", "port": 0,
        "private_key": "yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=",
        "local_address": "172.16.0.2/32,2606:4700:110:8691::2/128",
        "awg_jc": "4", "awg_jmin": "40", "awg_jmax": "70",
        "warp_wow": wow,
        "warp_outer": {
            "private_key": "iN9ohPHzrEPoF6DHzwJboQVMyBEYcUjUmd9SIcAro1w=",
            "local_address": "172.16.0.2/32,2606:4700:110:84c5::2/128"
        }
    })
}

#[test]
fn new_protocols_pass_sing_box_check() {
    let ech = "AEX+DQBBpQAgACB/RUc0Ho5lB2jd8oyDjsXr3kK8qhjVPiHfKY4vxnD5LQAEAAEAAQASY2xvdWRmbGFyZS1lY2guY29tAAA=";
    let links = [
        "tuic://b1a2c3d4-1111-2222-3333-444455556666:pass@example.com:443?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=example.com&allow_insecure=1#TUIC".to_string(),
        "anytls://secret@example.com:443?sni=example.com&fp=chrome&insecure=1#AnyTLS".into(),
        format!("ss://{}@example.com:443/?plugin={}#STLS", b64("2022-blake3-aes-128-gcm:8JCsPssfgS8tiRwiMlhARg=="), "shadow-tls%3Bhost%3Dwww.microsoft.com%3Bpassword%3Dhunter2%3Bversion%3D3"),
        format!("ss://{}@example.com:8388/?plugin={}#OBFS", b64("aes-256-gcm:pw"), "obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dbing.com"),
        format!("trojan://secret@example.com:443?security=tls&sni=example.com&ech={}#ECH", ech.replace('+', "%2B")),
        "vless://b1a2c3d4-1111-2222-3333-444455556666@example.com:443?encryption=none&security=tls&sni=example.com&type=ws&path=%2F&ech=cloudflare-ech.com%2Bhttps%3A%2F%2F1.1.1.1%2Fdns-query#ECHQ".into(),
        "hysteria2://pass@example.com:443?sni=example.com&ech=1#HYECH".into(),
        "wireguard://yAnz5TF%2BlXXJte14tji3zlMNq%2Bhd2rYUIgJBgB3fBmk%3D@1.2.3.4:51820?publickey=xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg%3D&address=10.8.1.2%2F32&reserved=1,2,3&jc=4&jmin=40&jmax=70&s1=15&s2=68&h1=1020325451&h2=3288052141&h3=1766607858&h4=2120568120&i1=%3Cb%200xc0ffee%3E%3Cr%2016%3E#AWG".into(),
    ];
    let settings = check_settings();
    for link in &links {
        let node = parse_link(link).unwrap_or_else(|e| panic!("{link} {e}"));
        sing_box_accepts(&settings, &[node.clone()], node["remark"].as_str().unwrap_or("node"));
    }
    let conf = "[Interface]\nPrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=\nAddress = 10.8.1.2/32\nDNS = 1.1.1.1\nJc = 3\nJmin = 10\nJmax = 50\nS1 = 0\nS2 = 0\nH1 = 1\nH2 = 2\nH3 = 3\nH4 = 4\n\n[Peer]\nPublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=\nAllowedIPs = 0.0.0.0/0, ::/0\nEndpoint = 1.2.3.4:51820\nPersistentKeepalive = 25\n";
    let nodes = v2core::parse_text(conf);
    assert_eq!(nodes.len(), 1);
    assert_eq!(nodes[0]["awg_jc"], "3");
    sing_box_accepts(&settings, &nodes, "awg-conf");
    sing_box_accepts(&settings, &[warp_profile(false)], "warp");
    sing_box_accepts(&settings, &[warp_profile(true)], "warp-wow");
    let vless = parse_link("vless://b1a2c3d4-1111-2222-3333-444455556666@example.com:443?encryption=none&security=tls&sni=example.com&type=tcp#V").unwrap();
    let mut chained = settings.clone();
    chained["_warp_chain"] = warp_profile(true);
    sing_box_accepts(&chained, &[vless.clone()], "warp-chain");
    sing_box_accepts(&settings, &[vless, warp_profile(false), parse_link(&links[0]).unwrap()], "smart-mixed");
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
