use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

const SING_BOX_VERSION: &str = "1.14.4";
const XRAY_VERSION: &str = "26.10.21";
pub const SINGBOX_UPSTREAM: &str = "sing-box-upstream";

pub fn engines_dir(data: &Path) -> PathBuf {
    data.join("engines")
}

/// Older builds stored stock sing-box as `engines/sing-box`; move to `sing-box-upstream` once.
pub fn migrate_legacy_layout(data: &Path) -> bool {
    let dir = engines_dir(data);
    let legacy = dir.join("sing-box");
    let upstream = dir.join(SINGBOX_UPSTREAM);
    if legacy.is_file() && !upstream.exists() {
        let _ = fs::create_dir_all(&dir);
        return fs::rename(&legacy, &upstream).is_ok();
    }
    false
}

/// `engine` is `bundled` (default) or `upstream` (stock SagerNet next to bundle).
pub fn resolve_singbox(bundled: &Path, data: &Path, engine: &str) -> PathBuf {
    if engine == "upstream" {
        let up = engines_dir(data).join(SINGBOX_UPSTREAM);
        if up.is_file() {
            return up;
        }
    }
    bundled.to_path_buf()
}

pub fn resolve_xray(singbox: &Path, data: &Path) -> PathBuf {
    let user = engines_dir(data).join("xray");
    if user.is_file() {
        return user;
    }
    singbox
        .parent()
        .unwrap_or(Path::new("."))
        .join("xray")
}

pub fn is_extended_build(version: &str) -> bool {
    version.to_ascii_lowercase().contains("extended")
}

pub fn core_version(bin: &Path) -> String {
    if !bin.exists() {
        return String::new();
    }
    let Ok(out) = Command::new(bin).arg("version").output() else {
        return String::new();
    };
    let text = String::from_utf8_lossy(&out.stdout);
    let line = text.lines().next().unwrap_or("").trim();
    if line.to_ascii_lowercase().starts_with("xray") {
        return xray_version_line(line);
    }
    line.to_string()
}

fn xray_version_line(raw: &str) -> String {
    let rest = raw.strip_prefix("Xray ").unwrap_or(raw);
    let token = rest.split_whitespace().next().unwrap_or(rest);
    let version = token.split('(').next().unwrap_or(token).trim();
    if version.is_empty() {
        raw.to_string()
    } else {
        version.to_string()
    }
}

pub fn status(bundled: &Path, data: &Path, singbox_engine: &str) -> Value {
    let dir = engines_dir(data);
    let active_sb = resolve_singbox(bundled, data, singbox_engine);
    let active_xr = resolve_xray(&active_sb, data);
    let bundled_xr = bundled.parent().unwrap_or(Path::new(".")).join("xray");
    let bundled_ver = core_version(bundled);
    let upstream = dir.join(SINGBOX_UPSTREAM);
    json!({
        "singbox": {
            "active": active_sb.display().to_string(),
            "active_version": core_version(&active_sb),
            "bundled": bundled.display().to_string(),
            "bundled_version": bundled_ver,
            "bundled_is_extended": is_extended_build(&bundled_ver),
            "upstream": upstream.display().to_string(),
            "upstream_version": core_version(&upstream),
            "upstream_installed": upstream.is_file(),
            "engine_mode": singbox_engine
        },
        "xray": {
            "active": active_xr.display().to_string(),
            "active_version": core_version(&active_xr),
            "bundled": bundled_xr.display().to_string(),
            "bundled_version": core_version(&bundled_xr),
            "user_installed": dir.join("xray").exists()
        },
        "arch": host_arch(),
        "catalog": {
            "sing-box": SING_BOX_VERSION,
            "xray": XRAY_VERSION
        }
    })
}

pub fn update(bundled: &Path, data: &Path, target: &str, singbox_engine: &str) -> Result<Value, String> {
    let name = match target.trim().to_ascii_lowercase().as_str() {
        "sing-box" | "singbox" => "sing-box",
        "xray" => "xray",
        _ => return Err("target must be sing-box or xray".into()),
    };
    let dir = engines_dir(data);
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let dest = if name == "sing-box" {
        dir.join(SINGBOX_UPSTREAM)
    } else {
        dir.join(name)
    };
    let ext = if name == "xray" { "zip" } else { "tar.gz" };
    let tmp = dir.join(format!(".{name}.download.{ext}"));
    let url = download_url(name)?;
    download_file(&url, &tmp)?;
    let bin = extract_binary(&tmp, name, ext)?;
    if let Ok(meta) = fs::metadata(&bin) {
        if !meta.is_file() || meta.len() < 512 {
            let _ = fs::remove_file(&tmp);
            return Err("downloaded engine looks invalid".into());
        }
    }
    fs::rename(&bin, &dest).or_else(|_| {
        fs::copy(&bin, &dest).map(|_| ()).map_err(|e| e.to_string())
    })?;
    let _ = fs::remove_file(&tmp);
    make_executable(&dest)?;
    Ok(status(bundled, data, singbox_engine))
}

fn host_arch() -> &'static str {
    if cfg!(target_arch = "aarch64") {
        "arm64"
    } else {
        "x86_64"
    }
}

fn download_url(name: &str) -> Result<String, String> {
    match (name, host_arch()) {
        ("sing-box", "arm64") => Ok(format!(
            "https://github.com/SagerNet/sing-box/releases/download/v{SING_BOX_VERSION}/sing-box-{SING_BOX_VERSION}-darwin-arm64.tar.gz"
        )),
        ("sing-box", _) => Ok(format!(
            "https://github.com/SagerNet/sing-box/releases/download/v{SING_BOX_VERSION}/sing-box-{SING_BOX_VERSION}-darwin-amd64.tar.gz"
        )),
        ("xray", "arm64") => Ok(format!(
            "https://github.com/XTLS/Xray-core/releases/download/v{XRAY_VERSION}/Xray-macos-arm64-v8a.zip"
        )),
        ("xray", _) => Ok(format!(
            "https://github.com/XTLS/Xray-core/releases/download/v{XRAY_VERSION}/Xray-macos-64.zip"
        )),
        _ => Err("unknown engine".into()),
    }
}

fn download_file(url: &str, dest: &Path) -> Result<(), String> {
    let resp = ureq::get(url)
        .timeout(std::time::Duration::from_secs(120))
        .call()
        .map_err(|e| e.to_string())?;
    let mut reader = resp.into_reader();
    let mut file = fs::File::create(dest).map_err(|e| e.to_string())?;
    std::io::copy(&mut reader, &mut file).map_err(|e| e.to_string())?;
    Ok(())
}

fn extract_binary(archive: &Path, name: &str, ext: &str) -> Result<PathBuf, String> {
    let work = archive
        .parent()
        .unwrap_or(Path::new("."))
        .join(format!(".extract-{name}-{}", now()));
    let _ = fs::remove_dir_all(&work);
    fs::create_dir_all(&work).map_err(|e| e.to_string())?;
    if ext == "zip" {
        let status = Command::new("ditto")
            .args(["-x", "-k", &archive.display().to_string(), &work.display().to_string()])
            .status()
            .map_err(|e| e.to_string())?;
        if !status.success() {
            return Err("failed to unzip engine".into());
        }
    } else {
        let status = Command::new("tar")
            .args(["-xzf", &archive.display().to_string(), "-C", &work.display().to_string()])
            .status()
            .map_err(|e| e.to_string())?;
        if !status.success() {
            return Err("failed to extract engine archive".into());
        }
    }
    find_binary(&work, name)
}

fn find_binary(root: &Path, name: &str) -> Result<PathBuf, String> {
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
                continue;
            }
            if path.file_name().and_then(|s| s.to_str()) == Some(name) {
                return Ok(path);
            }
        }
    }
    Err(format!("{name} not found in archive"))
}

fn make_executable(path: &Path) -> Result<(), String> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(path).map_err(|e| e.to_string())?.permissions();
        perms.set_mode(0o755);
        fs::set_permissions(path, perms).map_err(|e| e.to_string())?;
    }
    let _ = Command::new("xattr")
        .args(["-cr", &path.display().to_string()])
        .status();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn engines_dir_under_data() {
        let data = std::env::temp_dir().join("v2open-engines-dir");
        assert_eq!(engines_dir(&data), data.join("engines"));
        let _ = fs::remove_dir_all(&data);
    }

    #[test]
    fn download_url_matches_arch() {
        let url = download_url("xray").unwrap();
        if cfg!(target_arch = "aarch64") {
            assert!(url.contains("arm64"));
        } else {
            assert!(url.contains("macos-64") || url.contains("amd64"));
        }
    }

    #[test]
    fn upstream_does_not_replace_bundled_by_default() {
        let data = std::env::temp_dir().join(format!("v2open-eng-{}", std::process::id()));
        let _ = fs::remove_dir_all(&data);
        fs::create_dir_all(engines_dir(&data)).unwrap();
        let bundled = data.join("bundle-sing-box");
        fs::write(&bundled, b"").unwrap();
        fs::write(engines_dir(&data).join(SINGBOX_UPSTREAM), b"").unwrap();
        assert_eq!(resolve_singbox(&bundled, &data, "bundled"), bundled);
        assert_eq!(
            resolve_singbox(&bundled, &data, "upstream"),
            engines_dir(&data).join(SINGBOX_UPSTREAM)
        );
        let _ = fs::remove_dir_all(&data);
    }

    #[test]
    fn detects_extended_suffix() {
        assert!(is_extended_build("1.14.3-extended-2.7.3"));
        assert!(!is_extended_build("1.14.4"));
    }

    #[test]
    fn legacy_layout_migrates_once() {
        let data = std::env::temp_dir().join(format!("v2open-mig-{}", std::process::id()));
        let _ = fs::remove_dir_all(&data);
        fs::create_dir_all(engines_dir(&data)).unwrap();
        let legacy = engines_dir(&data).join("sing-box");
        fs::write(&legacy, b"x").unwrap();
        assert!(migrate_legacy_layout(&data));
        assert!(!legacy.exists());
        assert!(engines_dir(&data).join(SINGBOX_UPSTREAM).is_file());
        assert!(!migrate_legacy_layout(&data));
        let _ = fs::remove_dir_all(&data);
    }
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}
