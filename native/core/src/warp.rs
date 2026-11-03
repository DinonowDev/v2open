use serde_json::{json, Value};
use std::path::Path;
use std::process::Command;
use std::time::Duration;

const API: &str = "https://api.cloudflareclient.com/v0a2158";
const CLIENT_VERSION: &str = "a-6.30-3596";
const USER_AGENT: &str = "okhttp/3.12.1";

fn s(v: &Value, key: &str) -> String {
    v.get(key).and_then(|x| x.as_str()).unwrap_or("").to_string()
}

pub fn keypair(singbox: &Path) -> Result<(String, String), String> {
    let out = Command::new(singbox).args(["generate", "wg-keypair"]).output().map_err(|e| e.to_string())?;
    if !out.status.success() {
        return Err("could not generate a WireGuard key".into());
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let field = |name: &str| {
        text.lines()
            .find_map(|line| line.trim().strip_prefix(name).map(|v| v.trim_start_matches(':').trim().to_string()))
            .filter(|v| !v.is_empty())
    };
    match (field("PrivateKey"), field("PublicKey")) {
        (Some(private), Some(public)) => Ok((private, public)),
        _ => Err("could not read the generated WireGuard key".into()),
    }
}

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new().timeout(Duration::from_secs(20)).build()
}

fn request(agent: &ureq::Agent, method: &str, path: &str, token: Option<&str>) -> ureq::Request {
    let mut req = agent
        .request(method, &format!("{API}{path}"))
        .set("User-Agent", USER_AGENT)
        .set("CF-Client-Version", CLIENT_VERSION)
        .set("Content-Type", "application/json; charset=UTF-8");
    if let Some(token) = token {
        req = req.set("Authorization", &format!("Bearer {token}"));
    }
    req
}

fn api_error(err: ureq::Error) -> String {
    match err {
        ureq::Error::Status(code, response) => {
            let body = response.into_string().unwrap_or_default();
            let message = serde_json::from_str::<Value>(&body)
                .ok()
                .and_then(|v| v["errors"][0]["message"].as_str().map(|m| m.to_string()))
                .unwrap_or(body);
            format!("WARP server answered {code}: {}", message.trim())
        }
        other => format!("could not reach the WARP server: {other}"),
    }
}

pub fn reserved(client_id: &str) -> String {
    crate::parser::base64_decode(client_id.trim())
        .filter(|bytes| bytes.len() >= 3)
        .map(|bytes| bytes[..3].iter().map(|b| b.to_string()).collect::<Vec<_>>().join(","))
        .unwrap_or_default()
}

pub fn account_from_response(private_key: &str, body: &Value) -> Result<Value, String> {
    let config = &body["config"];
    let v4 = s(&config["interface"]["addresses"], "v4");
    let v6 = s(&config["interface"]["addresses"], "v6");
    if v4.is_empty() && v6.is_empty() {
        return Err("the WARP server did not return an address".into());
    }
    let mut addresses = Vec::new();
    if !v4.is_empty() {
        addresses.push(format!("{v4}/32"));
    }
    if !v6.is_empty() {
        addresses.push(format!("{v6}/128"));
    }
    let peer = &config["peers"][0];
    Ok(json!({
        "private_key": private_key,
        "local_address": addresses.join(","),
        "peer_public_key": s(peer, "public_key"),
        "reserved": reserved(&s(config, "client_id")),
        "warp_id": s(body, "id"),
        "warp_token": s(body, "token"),
        "license": s(&body["account"], "license"),
        "account_type": s(&body["account"], "account_type"),
    }))
}

pub fn register(singbox: &Path, license: &str) -> Result<Value, String> {
    let (private_key, public_key) = keypair(singbox)?;
    let agent = agent();
    let tos = chrono_like_now();
    let body = json!({
        "key": public_key,
        "install_id": "",
        "fcm_token": "",
        "tos": tos,
        "model": "PC",
        "serial_number": "",
        "locale": "en_US"
    });
    let text = request(&agent, "POST", "/reg", None)
        .send_string(&body.to_string())
        .map_err(api_error)?
        .into_string()
        .map_err(|e| e.to_string())?;
    let response: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let mut account = account_from_response(&private_key, &response)?;
    let license = license.trim();
    if !license.is_empty() {
        apply_license(&s(&account, "warp_id"), &s(&account, "warp_token"), license)?;
        account["license"] = json!(license);
        account["account_type"] = json!("limited");
    }
    Ok(account)
}

pub fn apply_license(id: &str, token: &str, license: &str) -> Result<(), String> {
    if id.is_empty() || token.is_empty() {
        return Err("the WARP account is not registered yet".into());
    }
    let agent = agent();
    request(&agent, "PUT", &format!("/reg/{id}/account"), Some(token))
        .send_string(&json!({"license": license.trim()}).to_string())
        .map_err(api_error)?;
    Ok(())
}

pub fn valid_license(license: &str) -> bool {
    let license = license.trim();
    license.len() >= 20 && license.contains('-') && license.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
}

pub fn blank(name: &str, license: &str, wow: bool) -> Value {
    let mut node = crate::parser::blank("warp");
    node["remark"] = json!(if name.trim().is_empty() { if wow { "WARP-on-WARP" } else { "WARP" } } else { name.trim() });
    node["address"] = json!(crate::builder::WARP_ENDPOINT);
    node["port"] = json!(crate::builder::WARP_PORT);
    node["license"] = json!(if valid_license(license) { license.trim() } else { "" });
    node["warp_wow"] = json!(wow);
    node["awg_jc"] = json!("4");
    node["awg_jmin"] = json!("40");
    node["awg_jmax"] = json!("70");
    node
}

pub fn needs_registration(profile: &Value) -> bool {
    if profile["protocol"].as_str() != Some("warp") {
        return false;
    }
    if s(profile, "private_key").is_empty() {
        return true;
    }
    profile["warp_wow"].as_bool().unwrap_or(false) && s(&profile["warp_outer"], "private_key").is_empty()
}

pub fn complete(singbox: &Path, profile: &mut Value) -> Result<(), String> {
    if s(profile, "private_key").is_empty() {
        let account = register(singbox, &s(profile, "license"))?;
        for (key, value) in account.as_object().into_iter().flatten() {
            profile[key] = value.clone();
        }
    }
    if profile["warp_wow"].as_bool().unwrap_or(false) && s(&profile["warp_outer"], "private_key").is_empty() {
        profile["warp_outer"] = register(singbox, "")?;
    }
    Ok(())
}

fn chrono_like_now() -> String {
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    let (h, m, sec) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let mo = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if mo <= 2 { 1 } else { 0 };
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{m:02}:{sec:02}.000Z")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_registration_response() {
        let body = json!({
            "id": "abc", "token": "tok",
            "account": {"license": "a1b2c3d4-e5f6g7h8-i9j0k1l2", "account_type": "free"},
            "config": {
                "client_id": "AQID",
                "peers": [{"public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="}],
                "interface": {"addresses": {"v4": "172.16.0.2", "v6": "2606:4700::2"}}
            }
        });
        let account = account_from_response("priv", &body).unwrap();
        assert_eq!(account["reserved"], "1,2,3");
        assert_eq!(account["local_address"], "172.16.0.2/32,2606:4700::2/128");
        assert_eq!(account["warp_id"], "abc");
        assert!(valid_license("a1b2c3d4-e5f6g7h8-i9j0k1l2"));
        assert!(!valid_license("auto"));
        assert_eq!(chrono_like_now().len(), 24);
    }

    #[test]
    #[ignore]
    fn live_warp_on_warp() {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
        let core = root.join("binaries/macos/sing-box");
        let mut profile = blank("", "", true);
        complete(&core, &mut profile).unwrap();
        assert!(!needs_registration(&profile));
        let settings = json!({"socks_enabled": true, "socks_port": 18765, "http_enabled": false, "routing_enabled": false,
            "remote_dns": "1.1.1.1", "domestic_dns": "1.1.1.1", "final": "proxy"});
        let config = crate::builder::build_config(&settings, &[profile], &[], &root.join("assets/rulesets"), "proxy").unwrap();
        let file = std::env::temp_dir().join("v2open-warp-live.json");
        std::fs::write(&file, serde_json::to_string_pretty(&config).unwrap()).unwrap();
        let mut child = Command::new(&core).args(["run", "-c"]).arg(&file).spawn().unwrap();
        std::thread::sleep(Duration::from_secs(4));
        let out = Command::new("curl").args(["-s", "-m", "15", "-x", "socks5h://127.0.0.1:18765", "https://www.cloudflare.com/cdn-cgi/trace"]).output().unwrap();
        let _ = child.kill();
        let text = String::from_utf8_lossy(&out.stdout).to_string();
        assert!(text.contains("warp=on") || text.contains("warp=plus"), "{text}");
    }
}
