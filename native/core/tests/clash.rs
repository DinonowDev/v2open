use serde_json::json;
use v2core::{parse_clash_yaml, parse_text};

#[test]
fn parses_clash_yaml_proxies() {
    let text = r#"
proxies:
  - name: "ss-one"
    type: ss
    server: 1.2.3.4
    port: 443
    cipher: aes-256-gcm
    password: secret
  - { name: "vless-two", type: vless, server: 8.8.8.8, port: 443, uuid: 00000000-0000-0000-0000-000000000001, tls: true, servername: example.com }
"#;
    let nodes = parse_clash_yaml(text);
    assert_eq!(nodes.len(), 2);
    assert_eq!(nodes[0]["protocol"], "shadowsocks");
    assert_eq!(nodes[0]["address"], "1.2.3.4");
    assert_eq!(nodes[1]["protocol"], "vless");
    assert_eq!(nodes[1]["sni"], "example.com");
    let via_text = parse_text(text);
    assert_eq!(via_text.len(), 2);
}

#[test]
fn parse_text_still_reads_share_links() {
    let nodes = parse_text("vless://00000000-0000-0000-0000-000000000001@127.0.0.1:443?security=tls#one");
    assert_eq!(nodes.len(), 1);
    assert_eq!(nodes[0]["protocol"], "vless");
    assert_eq!(nodes[0]["address"], json!("127.0.0.1"));
}
