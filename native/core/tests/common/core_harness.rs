use std::fs;
use std::path::{Path, PathBuf};
use v2core::Core;

pub fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

pub fn open_core() -> (Core, PathBuf) {
    let root = workspace_root();
    let tag = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let dir = std::env::temp_dir().join(format!("v2open-it-{}-{}", std::process::id(), tag));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("tmpdir");
    let rules = dir.join("rulesets");
    fs::create_dir_all(&rules).expect("rulesets");
    let singbox = root.join("binaries/macos/sing-box");
    if !singbox.is_file() {
        let stub = dir.join("sing-box-stub");
        fs::write(&stub, b"").expect("stub sing-box");
        return (Core::open(dir.clone(), stub, rules), dir);
    }
    (Core::open(dir.clone(), singbox, rules), dir)
}

pub fn cleanup(dir: &Path) {
    let _ = fs::remove_dir_all(dir);
}

pub const SAMPLE_VLESS: &str =
    "vless://b1a2c3d4-1111-2222-3333-444455556666@example.com:443?encryption=none&security=tls&sni=example.com&type=tcp#Demo";
