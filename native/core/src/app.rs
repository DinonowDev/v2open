use crate::builder::{build_config, build_pipe, exclude_tunnel_addresses, preset};
use crate::routing::{builtin_geo_assets, export_routes, geoip_download_url, geosite_download_url, matcher_text, normalize_rule, parse_routes};
use crate::parser::{build_link, parse_text, parse_userinfo};
use serde_json::{json, Value};
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::collections::HashSet;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[derive(Clone)]
struct Runtime {
    connected: bool,
    phase: String,
    error: String,
    upload_speed: u64,
    download_speed: u64,
    upload_total: u64,
    download_total: u64,
    core: String,
    profile_name: String,
    smart: bool,
    pid: u32,
    elevated: bool,
    ssid: String,
    net_kind: String,
    net_iface: String,
    seen_iface: String,
    blackhole: bool,
    connected_at: u64,
    net_at: u64,
    tunnel: String,
    engine: String,
}

impl Default for Runtime {
    fn default() -> Self {
        Self {
            connected: false,
            phase: "idle".into(),
            error: String::new(),
            upload_speed: 0,
            download_speed: 0,
            upload_total: 0,
            download_total: 0,
            core: String::new(),
            profile_name: String::new(),
            smart: false,
            pid: 0,
            elevated: false,
            ssid: String::new(),
            net_kind: String::new(),
            net_iface: String::new(),
            seen_iface: String::new(),
            blackhole: false,
            connected_at: 0,
            net_at: 0,
            tunnel: "admin".into(),
            engine: "sing-box".into(),
        }
    }
}

pub struct Core {
    path: PathBuf,
    singbox: PathBuf,
    rules: PathBuf,
    settings: Value,
    groups: Vec<Value>,
    routes: Vec<Value>,
    backups: Vec<Value>,
    runtime: Runtime,
    child: Option<std::process::Child>,
    stop_traffic: Arc<Mutex<bool>>,
    bridges: crate::sidecar::Running,
    unlocked: HashSet<String>,
    hold_routes: bool,
    direct_bridge: u16,
    bypass: Vec<String>,
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

static ID_SEQ: AtomicU64 = AtomicU64::new(0);

fn id() -> String {
    let seq = ID_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("{:x}{:x}{:x}", now(), std::process::id(), seq)
}

fn tcp_connect_ms(host: &str, port: u16, timeout: Duration, prefer_ipv6: bool) -> Option<u64> {
    let mut addrs: Vec<SocketAddr> = (host, port).to_socket_addrs().ok()?.collect();
    if addrs.is_empty() {
        return None;
    }
    addrs.sort_by_key(|addr| {
        let v6 = addr.is_ipv6();
        if prefer_ipv6 { !v6 } else { v6 }
    });
    let bind_index = physical_bind_index();
    for addr in addrs {
        if addr.ip().is_unspecified() {
            continue;
        }
        let started = Instant::now();
        if tcp_connect_addr(addr, timeout, bind_index).is_ok() {
            return Some(started.elapsed().as_millis().max(1) as u64);
        }
    }
    None
}

fn physical_bind_index() -> Option<u32> {
    let name = crate::platform::physical_iface()?;
    let c = std::ffi::CString::new(name).ok()?;
    let idx = unsafe { libc::if_nametoindex(c.as_ptr()) };
    if idx == 0 { None } else { Some(idx) }
}

fn tcp_connect_addr(addr: SocketAddr, timeout: Duration, bind_index: Option<u32>) -> std::io::Result<TcpStream> {
    use socket2::{Domain, Protocol, Socket, Type};
    let domain = if addr.is_ipv4() { Domain::IPV4 } else { Domain::IPV6 };
    let socket = Socket::new(domain, Type::STREAM, Some(Protocol::TCP))?;
    let loopback = addr.ip().is_loopback();
    if let (Some(idx), false) = (bind_index, loopback) {
        bind_socket_iface(&socket, addr.is_ipv4(), idx)?;
    } else if bind_index.is_none() && !loopback && crate::platform::is_tunnel_iface(&crate::platform::status().iface) {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "refusing tun-local ping"));
    }
    socket.connect_timeout(&addr.into(), timeout)?;
    Ok(socket.into())
}

fn bind_socket_iface(socket: &socket2::Socket, ipv4: bool, index: u32) -> std::io::Result<()> {
    use std::os::unix::io::AsRawFd;
    let fd = socket.as_raw_fd();
    let idx = index as libc::c_uint;
    let (level, opt) = if ipv4 {
        (libc::IPPROTO_IP, libc::IP_BOUND_IF)
    } else {
        (libc::IPPROTO_IPV6, libc::IPV6_BOUND_IF)
    };
    let rc = unsafe {
        libc::setsockopt(
            fd,
            level,
            opt,
            &idx as *const libc::c_uint as *const libc::c_void,
            std::mem::size_of::<libc::c_uint>() as libc::socklen_t,
        )
    };
    if rc == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}

fn defaults() -> Value {
    json!({
        "language": "fa",
        "loglevel": "none",
        "logging_enabled": true,
        "stop_on_sleep": true,
        "socks_enabled": true,
        "socks_port": 10808,
        "http_enabled": true,
        "http_port": 10807,
        "lan_sharing": false,
        "clash_port": 9097,
        "mux_enabled": false,
        "mux_concurrency": 8,
        "allow_insecure": false,
        "prefer_ipv6": false,
        "memory_limit_mb": 30,
        "mode": "tun",
        "apply_system_proxy": true,
        "mtu": 1500,
        "include_local": false,
        "enforce_routes": false,
        "fragment_enabled": false,
        "fragment_packets": "tlshello",
        "fragment_length": "100-200",
        "fragment_interval": "10-20",
        "domain_strategy": "AsIs",
        "route_only": true,
        "apple_direct": false,
        "routing_enabled": true,
        "sniffing": true,
        "geo_files_source": "v2fly/domain-list-community",
        "geoip_source": "v2fly/geoip",
        "geo_assets": [],
        "remote_dns": "https://1.1.1.1/dns-query",
        "domestic_dns": "223.5.5.5",
        "query_strategy": "prefer_ipv4",
        "dns_cache": true,
        "dns_split": "none",
        "routing_preset": "global",
        "final": "proxy",
        "block_udp_443": true,
        "bypass_lan": true,
        "hosts": {},
        "per_app_mode": "off",
        "per_app_list": [],
        "per_app_text": "",
        "fake_dns": false,
        "kill_switch": false,
        "on_demand": false,
        "on_demand_text": "",
        "net_combiner": false,
        "theme": "dark",
        "icloud": false,
        "selected_id": "",
        "user_agent": "Mozilla/5.0",
        "send_hwid": false,
        "hwid": id(),
        "auto_update": false,
        "geo_auto_update": false,
        "geo_auto_interval_hours": 24,
        "geo_last_auto_update": 0,
        "sub_auto_update": false,
        "sub_auto_interval_hours": 24,
        "sub_last_auto_update": 0,
        "sub_last_error": "",
        "smart_connect": false,
        "smart_interval": "1m",
        "smart_tolerance": 50,
        "probe_url": "https://www.gstatic.com/generate_204",
        "probe_interval": "1m",
        "observatory_enabled": false,
        "burst_observatory": false,
        "speed_mode": "http",
        "persist_tunnel": false,
        "remote_dns_id": "",
        "domestic_dns_id": "",
        "dns_items": [],
        "mtu_optimize": false,
        "mtu_optimize_on_connect": false,
        "mtu_save_log": false,
        "min_upload_mtu": 38,
        "max_upload_mtu": 150,
        "min_download_mtu": 100,
        "max_download_mtu": 500,
        "mtu_test_parallelism": 16,
        "mtu_test_retries": 2,
        "mtu_test_timeout": 2,
        "mtu_last_result": 0,
        "xray_balancer_enabled": false,
        "xray_balancer_tag": "balancer",
        "xray_balancer_strategy": "random",
        "xray_balancer_selector": ["proxy"],
        "xray_balancers": [],
        "xray_policy_level": 0,
        "xray_policy_uplink_only": 0,
        "xray_policy_downlink_only": 0,
        "xray_policy_stats_user_uplink": false,
        "xray_policy_stats_user_downlink": false,
        "show_announcements": true,
        "speed_endpoint": "https://www.gstatic.com/generate_204",
        "speed_timeout": 8,
        "sort_by": "default",
        "throughput_test": false,
        "throughput_duration": 10,
        "auto_connect_best": false
    })
}

impl Core {
    pub fn open(data_dir: PathBuf, singbox: PathBuf, rules: PathBuf) -> Self {
        let _ = fs::create_dir_all(&data_dir);
        install_rules(&rules);
        seed_geo_files(&data_dir, &singbox);
        let path = data_dir.join("library.json");
        let mut core = Self {
            path,
            singbox,
            rules,
            settings: defaults(),
            groups: Vec::new(),
            routes: Vec::new(),
            backups: Vec::new(),
            runtime: Runtime::default(),
            child: None,
            stop_traffic: Arc::new(Mutex::new(false)),
            bridges: crate::sidecar::Running { children: Vec::new(), stops: Vec::new(), elevated: Vec::new() },
            unlocked: HashSet::new(),
            hold_routes: false,
            direct_bridge: 0,
            bypass: Vec::new(),
        };
        core.load();
        crate::migrate::migrate_settings(&mut core.settings);
        crate::dns_items::ensure_dns_items(&mut core.settings);
        crate::xray_balancers::ensure_balancers(&mut core.settings);
        core.ensure_unique_profile_ids();
        core.forget_session_pings();
        if core.singbox.exists() {
            if let Ok(out) = Command::new(&core.singbox).arg("version").output() {
                core.runtime.core = String::from_utf8_lossy(&out.stdout).lines().next().unwrap_or("").trim().to_string();
            }
        }
        core
    }

    fn load(&mut self) {
        self.read_library();
        if self.settings["icloud"].as_bool().unwrap_or(false) {
            self.merge_icloud();
        }
        if self.groups.is_empty() {
            self.groups.push(json!({
                "id": id(), "name": "Local", "kind": "local", "url": "", "pinned": false,
                "expanded": true, "locked": false, "announcement": "", "expire": 0,
                "upload": 0, "download": 0, "total": 0, "updated_at": 0, "profiles": []
            }));
            self.save();
        }
        crate::migrate::migrate_settings(&mut self.settings);
        crate::dns_items::ensure_dns_items(&mut self.settings);
        crate::xray_balancers::ensure_balancers(&mut self.settings);
    }

    fn merge_icloud(&mut self) {
        let Some(cloud) = crate::platform::icloud_library() else { return };
        if !cloud_newer(&cloud, &self.path) {
            return;
        }
        let Ok(text) = fs::read_to_string(&cloud) else { return };
        let Ok(data) = serde_json::from_str::<Value>(&text) else { return };
        let local_groups = self.groups.clone();
        if let Some(settings) = data.get("settings") {
            let mut merged = defaults();
            if let (Some(dst), Some(src)) = (merged.as_object_mut(), settings.as_object()) {
                for (k, v) in src { dst.insert(k.clone(), v.clone()); }
            }
            self.settings = merged;
        }
        self.groups = data["groups"].as_array().cloned().unwrap_or_default();
        if data.get("routes").is_some() {
            self.routes = data["routes"].as_array().cloned().unwrap_or_default();
        }
        for group in local_groups {
            let id = group["id"].as_str().unwrap_or("").to_string();
            let profiles = group["profiles"].as_array().cloned().unwrap_or_default();
            if let Some(existing) = self.groups.iter_mut().find(|g| g["id"].as_str() == Some(id.as_str())) {
                let have: std::collections::HashSet<String> = existing["profiles"].as_array().map(|a| a.iter().filter_map(|p| p["link"].as_str().map(|s| s.to_string())).collect()).unwrap_or_default();
                if let Some(arr) = existing["profiles"].as_array_mut() {
                    for profile in profiles {
                        let link = profile["link"].as_str().unwrap_or("");
                        if link.is_empty() || !have.contains(link) { arr.push(profile); }
                    }
                }
            } else {
                self.groups.push(group);
            }
        }
        self.save();
    }

    fn ensure_unique_profile_ids(&mut self) {
        let mut changed = false;
        for group in &mut self.groups {
            let gid = group["id"].as_str().unwrap_or("").to_string();
            let mut seen = HashSet::new();
            let Some(arr) = group["profiles"].as_array_mut() else { continue };
            for profile in arr.iter_mut() {
                let pid = profile["id"].as_str().unwrap_or("").to_string();
                let duplicate = pid.is_empty() || pid == gid || seen.contains(&pid);
                if duplicate {
                    let new_id = id();
                    profile["id"] = json!(new_id.clone());
                    if let Some(data) = profile.get_mut("data").and_then(|d| d.as_object_mut()) {
                        data.insert("id".to_string(), json!(new_id));
                    }
                    changed = true;
                }
                seen.insert(profile["id"].as_str().unwrap_or("").to_string());
            }
        }
        if changed {
            self.save();
        }
    }

    fn forget_session_pings(&mut self) {
        for group in &mut self.groups {
            let Some(arr) = group["profiles"].as_array_mut() else { continue };
            for profile in arr {
                profile["ping"] = json!(-1);
            }
        }
    }

    fn read_library(&mut self) {
        if let Ok(text) = fs::read_to_string(&self.path) {
            if let Ok(data) = serde_json::from_str::<Value>(&text) {
                if let Some(settings) = data.get("settings").cloned() {
                    let mut merged = defaults();
                    if let (Some(dst), Some(src)) = (merged.as_object_mut(), settings.as_object()) {
                        for (k, v) in src {
                            dst.insert(k.clone(), v.clone());
                        }
                    }
                    self.settings = merged;
                }
                self.groups = data["groups"].as_array().cloned().unwrap_or_default();
                self.routes = data["routes"].as_array().cloned().unwrap_or_default();
                self.backups = data["backups"].as_array().cloned().unwrap_or_default();
            }
        }
    }

    fn save(&self) {
        if let Some(parent) = self.path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let data = json!({"settings": self.settings, "groups": self.groups, "routes": self.routes, "backups": self.backups});
        let _ = fs::write(&self.path, serde_json::to_string_pretty(&data).unwrap_or_else(|_| "{}".into()));
        if self.settings["icloud"].as_bool().unwrap_or(false) {
            if let Some(cloud) = crate::platform::icloud_library() {
                let _ = fs::copy(&self.path, cloud);
            }
        }
    }

    pub fn state(&mut self) -> Value {
        self.pull_traffic();
        self.refresh_net();
        json!({
            "settings": self.settings,
            "groups": self.public_groups(),
            "routes": self.public_routes(),
            "geo_assets": self.list_geo_assets(),
            "backups": self.backups.iter().map(|b| json!({"id": b["id"], "name": b["name"]})).collect::<Vec<_>>(),
            "runtime": {
                "connected": self.runtime.connected,
                "phase": self.runtime.phase,
                "error": self.runtime.error,
                "upload_speed": self.runtime.upload_speed,
                "download_speed": self.runtime.download_speed,
                "upload_total": self.runtime.upload_total,
                "download_total": self.runtime.download_total,
                "memory": self.runtime_memory_bytes(),
                "core": self.runtime.core,
                "profile_name": self.runtime.profile_name,
                "smart": self.runtime.smart,
                "ssid": self.runtime.ssid,
                "network": self.runtime.net_kind,
                "interface": self.runtime.net_iface,
                "kill_switch": self.runtime.blackhole,
                "tunnel": self.runtime.tunnel,
                "engine": self.runtime.engine,
                "config_path": self.path.parent().unwrap_or(Path::new(".")).join("config.json"),
                "log_path": self.path.parent().unwrap_or(Path::new(".")).join("core.log")
            }
        })
    }

    pub fn call(&mut self, method: &str, args: &Value) -> Result<Value, String> {
        match method {
            "state" => Ok(self.state()),
            "set" => {
                let key = args["key"].as_str().ok_or("missing key")?;
                self.settings[key] = args["value"].clone();
                self.save();
                Ok(self.state())
            }
            "import" => {
                self.import_text(args["text"].as_str().unwrap_or(""), args["group_id"].as_str())?;
                Ok(self.state())
            }
            "subscribe" => {
                self.subscribe(args["name"].as_str().unwrap_or("Subscription"), args["url"].as_str().unwrap_or(""))?;
                Ok(self.state())
            }
            "connect" => {
                if let Err(err) = self.connect(args["id"].as_str().unwrap_or(""), args["smart"].as_bool().unwrap_or(false)) {
                    self.runtime.error = err.clone();
                    self.runtime.phase = "error".into();
                    self.runtime.connected = false;
                    return Err(err);
                }
                Ok(self.state())
            }
            "disconnect" => {
                self.disconnect()?;
                Ok(self.state())
            }
            "select" => {
                self.settings["selected_id"] = json!(args["id"].as_str().unwrap_or(""));
                self.save();
                Ok(self.state())
            }
            "delete" => {
                let id = args["id"].as_str().unwrap_or("");
                for group in &mut self.groups {
                    if let Some(arr) = group["profiles"].as_array_mut() {
                        arr.retain(|p| p["id"].as_str() != Some(id));
                    }
                }
                if self.settings["selected_id"].as_str() == Some(id) {
                    self.settings["selected_id"] = json!("");
                }
                self.save();
                Ok(self.state())
            }
            "ping" => {
                let bench = args["throughput"].as_bool().unwrap_or(false);
                if let Some(group) = args["group_id"].as_str() {
                    let ids: Vec<String> = self.groups.iter().find(|g| g["id"].as_str() == Some(group)).and_then(|g| g["profiles"].as_array()).map(|a| a.iter().filter_map(|p| p["id"].as_str().map(|s| s.to_string())).collect()).unwrap_or_default();
                    for id in ids {
                        self.measure_profile(&id, bench)?;
                    }
                } else if let Some(id) = args["id"].as_str() {
                    self.measure_profile(id, bench)?;
                } else {
                    let ids: Vec<String> = self
                        .groups
                        .iter()
                        .flat_map(|g| g["profiles"].as_array())
                        .flat_map(|a| a.iter().filter_map(|p| p["id"].as_str().map(|s| s.to_string())))
                        .collect();
                    for id in ids {
                        self.measure_profile(&id, bench)?;
                    }
                }
                Ok(self.state())
            }
            "pick_best" => {
                let id = self.pick_best_profile(true)?;
                self.settings["selected_id"] = json!(id);
                self.save();
                Ok(json!({"id": id}))
            }
            "preset" => {
                self.apply_preset(args["name"].as_str().unwrap_or("global"));
                Ok(self.state())
            }
            "save_route" => {
                let route = args.get("route").cloned().unwrap_or_else(|| args.clone());
                self.save_route(&route)?;
                Ok(self.state())
            }
            "delete_route" => {
                let id = args["id"].as_str().unwrap_or("");
                self.routes.retain(|r| r["id"].as_str() != Some(id));
                self.save();
                Ok(self.state())
            }
            "toggle_route" => {
                let id = args["id"].as_str().unwrap_or("");
                let enabled = args["enabled"].as_bool();
                if let Some(rule) = self.routes.iter_mut().find(|r| r["id"].as_str() == Some(id)) {
                    let next = enabled.unwrap_or(!rule["enabled"].as_bool().unwrap_or(true));
                    rule["enabled"] = json!(next);
                    self.save();
                }
                Ok(self.state())
            }
            "reorder_routes" => {
                self.reorder_routes(&args["ids"])?;
                Ok(self.state())
            }
            "import_routes" => {
                let text = args["text"].as_str().unwrap_or("");
                let rules = parse_routes(text)?;
                if rules.is_empty() {
                    return Err("routing json is invalid".into());
                }
                self.routes = rules;
                self.settings["block_udp_443"] = json!(false);
                self.settings["bypass_lan"] = json!(false);
                self.save();
                Ok(self.state())
            }
            "export_routes" => Ok(json!({"text": export_routes(&self.routes)})),
            "add_geo_asset" => {
                self.add_geo_asset(args["name"].as_str().unwrap_or(""), args["url"].as_str().unwrap_or(""))?;
                Ok(self.state())
            }
            "update_geo_asset" => {
                self.update_geo_asset(args["name"].as_str().unwrap_or(""))?;
                Ok(self.state())
            }
            "delete_geo_asset" => {
                self.delete_geo_asset(args["name"].as_str().unwrap_or(""))?;
                Ok(self.state())
            }
            "update_all_geo_assets" => {
                self.update_all_geo_assets()?;
                Ok(self.state())
            }
            "import_geo_asset_file" => {
                self.import_geo_asset_file(
                    args["path"].as_str().unwrap_or(""),
                    args["name"].as_str().unwrap_or(""),
                )?;
                Ok(self.state())
            }
            "import_hosts" => {
                self.import_hosts(args["text"].as_str().unwrap_or(""))?;
                Ok(self.state())
            }
            "save_dns_item" => {
                crate::dns_items::save_dns_item(&mut self.settings, args)?;
                self.save();
                Ok(self.state())
            }
            "delete_dns_item" => {
                crate::dns_items::delete_dns_item(&mut self.settings, args["id"].as_str().unwrap_or(""))?;
                self.save();
                Ok(self.state())
            }
            "set_active_dns" => {
                crate::dns_items::set_active_dns(
                    &mut self.settings,
                    args["role"].as_str().unwrap_or("remote"),
                    args["id"].as_str().unwrap_or(""),
                )?;
                self.save();
                Ok(self.state())
            }
            "optimize_mtu" => {
                let result = self.optimize_mtu()?;
                self.save();
                Ok(json!({"result": result, "state": self.state()}))
            }
            "save_xray_advanced" => {
                for key in [
                    "xray_policy_level",
                    "xray_policy_uplink_only",
                    "xray_policy_downlink_only",
                    "xray_policy_stats_user_uplink",
                    "xray_policy_stats_user_downlink",
                    "observatory_enabled",
                    "burst_observatory",
                    "probe_url",
                    "probe_interval",
                    "smart_interval",
                    "smart_tolerance",
                ] {
                    if let Some(value) = args.get(key) {
                        self.settings[key] = value.clone();
                    }
                }
                self.save();
                Ok(self.state())
            }
            "save_xray_balancer" => {
                crate::xray_balancers::save_balancer(&mut self.settings, args)?;
                self.save();
                Ok(self.state())
            }
            "delete_xray_balancer" => {
                crate::xray_balancers::delete_balancer(&mut self.settings, args["id"].as_str().unwrap_or(""))?;
                self.save();
                Ok(self.state())
            }
            "save_profile" => {
                self.save_profile(&args["profile"])?;
                Ok(self.state())
            }
            "backup" => {
                self.backups.insert(0, json!({"id": id(), "name": now().to_string(), "payload": {"settings": self.settings, "groups": self.groups, "routes": self.routes}}));
                self.save();
                Ok(self.state())
            }
            "restore" => {
                let bid = args["id"].as_str().unwrap_or("");
                if let Some(item) = self.backups.iter().find(|b| b["id"].as_str() == Some(bid)).cloned() {
                    let payload = &item["payload"];
                    if let Some(settings) = payload.get("settings") {
                        let mut merged = defaults();
                        if let (Some(dst), Some(src)) = (merged.as_object_mut(), settings.as_object()) {
                            for (k, v) in src {
                                dst.insert(k.clone(), v.clone());
                            }
                        }
                        self.settings = merged;
                    }
                    self.groups = payload["groups"].as_array().cloned().unwrap_or_default();
                    self.routes = payload["routes"].as_array().cloned().unwrap_or_default();
                    self.save();
                }
                Ok(self.state())
            }
            "reset" => {
                let hwid = self.settings["hwid"].clone();
                self.settings = defaults();
                self.settings["hwid"] = hwid;
                self.routes.clear();
                self.save();
                Ok(self.state())
            }
            "erase" => {
                self.groups = vec![json!({"id": id(), "name":"Local","kind":"local","url":"","pinned":false,"expanded":true,"locked":false,"announcement":"","expire":0,"upload":0,"download":0,"total":0,"updated_at":0,"profiles":[]})];
                self.settings["selected_id"] = json!("");
                self.save();
                Ok(self.state())
            }
            "logs" => Ok(json!({"text": self.logs()})),
            "clear_logs" => {
                let _ = fs::write(self.path.parent().unwrap_or(Path::new(".")).join("core.log"), "");
                Ok(json!({"ok": true}))
            }
            "sidecar_logs" => Ok(json!({"text": self.sidecar_logs()})),
            "delete_backup" => {
                let id = args["id"].as_str().unwrap_or("");
                self.backups.retain(|b| b["id"].as_str() != Some(id));
                self.save();
                Ok(self.state())
            }
            "rename_backup" => {
                let id = args["id"].as_str().unwrap_or("");
                let name = args["name"].as_str().unwrap_or("").trim();
                if name.is_empty() {
                    return Err("backup name is required".into());
                }
                if let Some(item) = self.backups.iter_mut().find(|b| b["id"].as_str() == Some(id)) {
                    item["name"] = json!(name);
                    self.save();
                }
                Ok(self.state())
            }
            "export_backup" => {
                let id = args["id"].as_str().unwrap_or("");
                let path = args["path"].as_str().unwrap_or("");
                if path.is_empty() {
                    return Err("path is required".into());
                }
                let item = self.backups.iter().find(|b| b["id"].as_str() == Some(id)).ok_or("backup not found")?;
                fs::write(path, serde_json::to_string_pretty(item).unwrap_or_else(|_| "{}".into())).map_err(|e| e.to_string())?;
                Ok(json!({"path": path}))
            }
            "import_backup" => {
                let path = args["path"].as_str().unwrap_or("");
                let text = fs::read_to_string(path).map_err(|e| e.to_string())?;
                let data: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
                if data.get("payload").is_some() {
                    let mut item = data;
                    if item["id"].as_str().unwrap_or("").is_empty() {
                        item["id"] = json!(id());
                    }
                    if item["name"].as_str().unwrap_or("").is_empty() {
                        item["name"] = json!(now().to_string());
                    }
                    self.backups.insert(0, item);
                } else {
                    self.restore_payload(&data);
                    self.backups.insert(0, json!({"id": id(), "name": now().to_string(), "payload": data}));
                }
                self.save();
                Ok(self.state())
            }
            "export_package" => {
                let path = args["path"].as_str().unwrap_or("");
                if path.is_empty() {
                    return Err("path is required".into());
                }
                let payload = json!({
                    "settings": self.settings,
                    "groups": self.groups,
                    "routes": self.routes,
                    "dns_items": self.settings["dns_items"],
                    "xray_balancers": self.settings["xray_balancers"]
                });
                fs::write(path, serde_json::to_string_pretty(&payload).unwrap_or_else(|_| "{}".into())).map_err(|e| e.to_string())?;
                Ok(json!({"path": path}))
            }
            "import_package" => {
                let path = args["path"].as_str().unwrap_or("");
                let text = fs::read_to_string(path).map_err(|e| e.to_string())?;
                let data: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
                let payload = if data.get("payload").is_some() { &data["payload"] } else { &data };
                self.restore_payload(payload);
                Ok(self.state())
            }
            "update_group" => {
                self.update_group(args["id"].as_str().unwrap_or(""))?;
                Ok(self.state())
            }
            "prepare" => self.prepare(args["id"].as_str().unwrap_or(""), args["smart"].as_bool().unwrap_or(false)),
            "mark_connected" => {
                self.runtime.connected = true;
                self.runtime.phase = "connected".into();
                self.runtime.connected_at = now();
                self.runtime.tunnel = "system".into();
                self.runtime.error.clear();
                let id = args["id"].as_str().unwrap_or("");
                if let Some(profile) = self.find_profile(if id.is_empty() { self.settings["selected_id"].as_str().unwrap_or("") } else { id }) {
                    self.runtime.profile_name = profile["remark"].as_str().unwrap_or("").to_string();
                }
                self.watch_traffic();
                if self.settings["mtu_optimize_on_connect"].as_bool().unwrap_or(false)
                    && self.settings["mode"].as_str().unwrap_or("tun") == "tun"
                {
                    let _ = self.optimize_mtu();
                    self.save();
                }
                Ok(self.state())
            }
            "processes" => Ok(json!({"names": process_names()})),
            "tick" => {
                self.tick()?;
                Ok(self.state())
            }
            "speed" => self.speed_test(),
            "xray_json" => {
                let id = args["id"].as_str().unwrap_or("");
                let profile = self.find_profile(if id.is_empty() { self.settings["selected_id"].as_str().unwrap_or("") } else { id }).ok_or("no profile")?;
                Ok(json!({"text": serde_json::to_string_pretty(&crate::xray::document(&self.settings, &node_data(&profile), &self.routes)).unwrap_or_else(|_| "{}".into())}))
            }
            "seal" => {
                let password = args["password"].as_str().unwrap_or("");
                let payload = serde_json::to_vec(&json!({"settings": self.settings, "groups": self.groups, "routes": self.routes})).map_err(|e| e.to_string())?;
                let bytes = crate::vault::seal(password, &payload)?;
                if let Some(path) = args["path"].as_str().filter(|p| !p.is_empty()) {
                    fs::write(path, &bytes).map_err(|e| e.to_string())?;
                }
                Ok(json!({"path": args["path"], "bytes": bytes.len()}))
            }
            "unseal" => {
                let password = args["password"].as_str().unwrap_or("");
                let bytes = if let Some(path) = args["path"].as_str().filter(|p| !p.is_empty()) {
                    fs::read(path).map_err(|e| e.to_string())?
                } else {
                    base64_bytes(args["text"].as_str().unwrap_or(""))?
                };
                let plain = if bytes.starts_with(b"V2OPEN1") {
                    crate::vault::open(password, &bytes)?
                } else if bytes.starts_with(b"PK") {
                    unzip_password(password, &bytes)?
                } else {
                    return Err("the file is not a locked V2Open backup".into());
                };
                let data: Value = serde_json::from_slice(&plain).map_err(|_| "locked file did not contain a library".to_string())?;
                self.restore_payload(&data);
                Ok(self.state())
            }
            "lock_group" => {
                let id = args["id"].as_str().unwrap_or("").to_string();
                let password = args["password"].as_str().unwrap_or("");
                if password.len() < 4 {
                    return Err("password is too short".into());
                }
                if let Some(group) = self.groups.iter_mut().find(|g| g["id"].as_str() == Some(id.as_str())) {
                    group["locked"] = json!(true);
                    group["lock_hash"] = json!(crate::vault::lock_hash(password));
                }
                self.unlocked.remove(&id);
                self.save();
                Ok(self.state())
            }
            "unlock_group" => {
                let id = args["id"].as_str().unwrap_or("");
                let password = args["password"].as_str().unwrap_or("");
                let hash = self.groups.iter().find(|g| g["id"].as_str() == Some(id)).and_then(|g| g["lock_hash"].as_str()).unwrap_or("").to_string();
                if !crate::vault::lock_matches(password, &hash) {
                    return Err("wrong password".into());
                }
                self.unlocked.insert(id.to_string());
                Ok(self.state())
            }
            other => Err(format!("unknown {other}")),
        }
    }

    fn local_group_index(&self) -> usize {
        self.groups.iter().position(|g| g["kind"].as_str() == Some("local")).unwrap_or(0)
    }

    fn import_text(&mut self, text: &str, group_id: Option<&str>) -> Result<(), String> {
        let trimmed = text.trim();
        if trimmed.starts_with("v2box://") || trimmed.starts_with("v2open://") {
            if let Ok(node) = crate::parser::parse_link(trimmed) {
                if node["protocol"].as_str() == Some("subscription") {
                    let url = node["address"].as_str().unwrap_or("");
                    if !url.is_empty() {
                        return self.subscribe(node["remark"].as_str().unwrap_or("Subscription"), url);
                    }
                }
            }
        }
        if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
            return self.subscribe("Subscription", trimmed);
        }
        if trimmed.starts_with('{') {
            if let Ok(payload) = serde_json::from_str::<Value>(trimmed) {
                if payload.get("format").and_then(|v| v.as_str()) == Some("v2open") || payload.get("groups").is_some() {
                    let inner = payload.get("payload").unwrap_or(&payload);
                    self.restore_payload(inner);
                    return Ok(());
                }
            }
        }
        let nodes = parse_text(trimmed);
        if nodes.is_empty() {
            return Err("could not read that config".into());
        }
        let gid = group_id.map(|s| s.to_string()).unwrap_or_else(|| self.groups[self.local_group_index()]["id"].as_str().unwrap_or("").to_string());
        for node in nodes {
            if node["protocol"].as_str() == Some("subscription") {
                self.subscribe("subscription", node["address"].as_str().unwrap_or(""))?;
            } else {
                self.insert_profile(&gid, node);
            }
        }
        Ok(())
    }

    fn insert_profile(&mut self, group_id: &str, mut data: Value) {
        if data["link"].as_str().unwrap_or("").is_empty() {
            data["link"] = json!(build_link(&data));
        }
        let link = data["link"].as_str().unwrap_or("").to_string();
        if let Some(group) = self.groups.iter_mut().find(|g| g["id"].as_str() == Some(group_id)) {
            let profiles = group["profiles"].as_array_mut().unwrap();
            if !link.is_empty() && profiles.iter().any(|p| p["link"].as_str() == Some(link.as_str())) {
                return;
            }
            profiles.push(json!({
                "id": id(),
                "remark": data["remark"],
                "protocol": data["protocol"],
                "address": data["address"],
                "port": data["port"],
                "ping": -1,
                "download_bps": -1,
                "upload_bps": -1,
                "locked": false,
                "created_at": now(),
                "link": data["link"],
                "data": data
            }));
        }
        self.save();
    }

    fn public_routes(&self) -> Vec<Value> {
        self.routes
            .iter()
            .map(|rule| {
                let mut item = rule.clone();
                item["match"] = json!(matcher_text(rule));
                item
            })
            .collect()
    }

    fn apply_preset(&mut self, name: &str) {
        let bundle = preset(name);
        self.routes = bundle["rules"].as_array().cloned().unwrap_or_default();
        self.settings["routing_preset"] = json!(name);
        self.settings["final"] = bundle["final"].clone();
        self.settings["block_udp_443"] = bundle["block_udp_443"].clone();
        self.settings["dns_split"] = bundle["dns_split"].clone();
        if let Some(lan) = bundle.get("bypass_lan") {
            self.settings["bypass_lan"] = lan.clone();
        }
        self.save();
    }

    fn save_route(&mut self, raw: &Value) -> Result<(), String> {
        let Some(mut rule) = normalize_rule(raw.clone(), raw["id"].as_str().map(|s| s.to_string())) else {
            return Err("invalid route".into());
        };
        if rule["id"].as_str().unwrap_or("").is_empty() {
            rule["id"] = json!(id());
        }
        let rid = rule["id"].as_str().unwrap_or("").to_string();
        if let Some(existing) = self.routes.iter_mut().find(|item| item["id"].as_str() == Some(rid.as_str())) {
            *existing = rule;
        } else {
            self.routes.push(rule);
        }
        self.save();
        Ok(())
    }

    fn reorder_routes(&mut self, ids: &Value) -> Result<(), String> {
        let order: Vec<String> = ids
            .as_array()
            .ok_or("missing ids")?
            .iter()
            .filter_map(|v| v.as_str().map(|s| s.to_string()))
            .collect();
        let mut next = Vec::new();
        for id in &order {
            if let Some(rule) = self.routes.iter().find(|r| r["id"].as_str() == Some(id.as_str())) {
                next.push(rule.clone());
            }
        }
        for rule in &self.routes {
            let id = rule["id"].as_str().unwrap_or("");
            if !order.iter().any(|item| item == id) {
                next.push(rule.clone());
            }
        }
        self.routes = next;
        self.save();
        Ok(())
    }

    fn data_dir(&self) -> PathBuf {
        self.path.parent().unwrap_or(Path::new(".")).to_path_buf()
    }

    fn geo_dir(&self) -> PathBuf {
        self.data_dir().join("geo")
    }

    fn geo_path(&self, name: &str, kind: &str) -> PathBuf {
        if kind == "srs" || name.ends_with(".srs") {
            self.rules.join(name)
        } else {
            self.geo_dir().join(name)
        }
    }

    fn catalog_geo(&self) -> Vec<Value> {
        let mut items = builtin_geo_assets();
        if let Some(extra) = self.settings["geo_assets"].as_array() {
            for item in extra {
                let name = item["name"].as_str().unwrap_or("");
                if name.is_empty() || items.iter().any(|a| a["name"].as_str() == Some(name)) {
                    continue;
                }
                let mut row = item.clone();
                row["builtin"] = json!(false);
                if row.get("kind").and_then(|v| v.as_str()).unwrap_or("").is_empty() {
                    row["kind"] = json!(if name.ends_with(".srs") { "srs" } else { "dat" });
                }
                items.push(row);
            }
        }
        items
            .into_iter()
            .map(|mut item| {
                let name = item["name"].as_str().unwrap_or("").to_string();
                let fallback = item["url"].as_str().unwrap_or("").to_string();
                item["url"] = json!(self.geo_asset_url(&name, &fallback));
                item
            })
            .collect()
    }

    fn geo_asset_url(&self, name: &str, fallback: &str) -> String {
        match name {
            "geosite.dat" => geosite_download_url(self.settings["geo_files_source"].as_str().unwrap_or("v2fly/domain-list-community")),
            "geoip.dat" => geoip_download_url(self.settings["geoip_source"].as_str().unwrap_or("v2fly/geoip")),
            _ => fallback.to_string(),
        }
    }

    fn list_geo_assets(&self) -> Vec<Value> {
        self.catalog_geo()
            .into_iter()
            .map(|mut item| {
                let name = item["name"].as_str().unwrap_or("").to_string();
                let kind = item["kind"].as_str().unwrap_or("dat").to_string();
                let path = self.geo_path(&name, &kind);
                let meta = fs::metadata(&path).ok();
                item["exists"] = json!(meta.is_some());
                item["size"] = json!(meta.as_ref().map(|m| m.len()).unwrap_or(0));
                item["updated_at"] = json!(meta.and_then(|m| m.modified().ok()).and_then(|t| t.duration_since(UNIX_EPOCH).ok()).map(|d| d.as_secs()).unwrap_or(0));
                item["path"] = json!(path.to_string_lossy());
                item["primary"] = json!(matches!(name.as_str(), "geoip.dat" | "geosite.dat" | "iran.dat"));
                item
            })
            .collect()
    }

    fn add_geo_asset(&mut self, name: &str, url: &str) -> Result<(), String> {
        let name = Path::new(name).file_name().and_then(|s| s.to_str()).unwrap_or("").trim();
        if name.is_empty() || !(name.ends_with(".dat") || name.ends_with(".srs")) {
            return Err("file name must end with .dat or .srs".into());
        }
        if !url.starts_with("http://") && !url.starts_with("https://") {
            return Err("asset url must be http or https".into());
        }
        let mut extras = self.settings["geo_assets"].as_array().cloned().unwrap_or_default();
        extras.retain(|item| item["name"].as_str() != Some(name));
        extras.push(json!({"name": name, "url": url, "kind": if name.ends_with(".srs") { "srs" } else { "dat" }, "builtin": false}));
        self.settings["geo_assets"] = json!(extras);
        self.save();
        self.download_geo(name, url)
    }

    fn update_geo_asset(&self, name: &str) -> Result<(), String> {
        let item = self
            .catalog_geo()
            .into_iter()
            .find(|a| a["name"].as_str() == Some(name))
            .ok_or_else(|| "unknown geo asset".to_string())?;
        let url = item["url"].as_str().unwrap_or("").to_string();
        if url.is_empty() {
            return Err("this asset has no download url".into());
        }
        self.download_geo(name, &url)
    }

    fn update_all_geo_assets(&self) -> Result<(), String> {
        let names: Vec<String> = self
            .catalog_geo()
            .into_iter()
            .filter_map(|a| a["name"].as_str().map(|s| s.to_string()))
            .collect();
        let mut last_err = None;
        for name in names {
            if let Err(err) = self.update_geo_asset(&name) {
                last_err = Some(err);
            }
        }
        if let Some(err) = last_err {
            return Err(err);
        }
        Ok(())
    }

    fn import_geo_asset_file(&self, path: &str, name: &str) -> Result<(), String> {
        let src = Path::new(path);
        if !src.is_file() {
            return Err("geo file not found".into());
        }
        let file_name = if name.trim().is_empty() {
            src.file_name().and_then(|s| s.to_str()).unwrap_or("").to_string()
        } else {
            Path::new(name).file_name().and_then(|s| s.to_str()).unwrap_or(name).to_string()
        };
        if !(file_name.ends_with(".dat") || file_name.ends_with(".srs")) {
            return Err("file name must end with .dat or .srs".into());
        }
        let kind = if file_name.ends_with(".srs") { "srs" } else { "dat" };
        let dest = self.geo_path(&file_name, kind);
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        fs::copy(src, &dest).map_err(|e| e.to_string())?;
        Ok(())
    }

    fn import_hosts(&mut self, text: &str) -> Result<(), String> {
        let mut hosts = serde_json::Map::new();
        for line in text.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let mut parts = line.split_whitespace();
            let Some(domain) = parts.next() else { continue };
            let ip = parts.collect::<Vec<_>>().join(" ");
            if ip.is_empty() {
                continue;
            }
            hosts.insert(domain.to_string(), json!(ip));
        }
        self.settings["hosts"] = json!(hosts);
        self.save();
        Ok(())
    }

    fn delete_geo_asset(&mut self, name: &str) -> Result<(), String> {
        if builtin_geo_assets().iter().any(|a| a["name"].as_str() == Some(name)) {
            return Err("built-in geo assets cannot be removed".into());
        }
        if let Some(arr) = self.settings["geo_assets"].as_array_mut() {
            arr.retain(|item| item["name"].as_str() != Some(name));
        }
        let kind = if name.ends_with(".srs") { "srs" } else { "dat" };
        let path = self.geo_path(name, kind);
        let _ = fs::remove_file(path);
        self.save();
        Ok(())
    }

    fn download_geo(&self, name: &str, url: &str) -> Result<(), String> {
        let kind = if name.ends_with(".srs") { "srs" } else { "dat" };
        let path = self.geo_path(name, kind);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let agent = ureq::AgentBuilder::new().timeout(Duration::from_secs(120)).build();
        let response = agent.get(url).call().map_err(|e| e.to_string())?;
        let mut reader = response.into_reader();
        let tmp = path.with_extension("part");
        {
            let mut file = File::create(&tmp).map_err(|e| e.to_string())?;
            std::io::copy(&mut reader, &mut file).map_err(|e| e.to_string())?;
        }
        let size = fs::metadata(&tmp).map(|m| m.len()).unwrap_or(0);
        if size < 32 {
            let _ = fs::remove_file(&tmp);
            return Err("downloaded geo asset is empty".into());
        }
        fs::rename(&tmp, &path).or_else(|_| {
            fs::copy(&tmp, &path).map(|_| ()).and_then(|_| fs::remove_file(&tmp))
        }).map_err(|e| e.to_string())?;
        Ok(())
    }

    fn subscribe(&mut self, name: &str, url: &str) -> Result<(), String> {
        if !url.starts_with("http://") && !url.starts_with("https://") {
            return Err("subscription url must be http or https".into());
        }
        let mut req = ureq::get(url);
        req = req.set("User-Agent", self.settings["user_agent"].as_str().unwrap_or("V2Open"));
        if self.settings["send_hwid"].as_bool().unwrap_or(false) {
            req = req.set("X-HWID", self.settings["hwid"].as_str().unwrap_or(""));
        }
        let response = req.call().map_err(|e| e.to_string())?;
        let info_header = response.header("subscription-userinfo").unwrap_or("").to_string();
        let title = response.header("profile-title").unwrap_or("").to_string();
        let announce = response.header("announce").unwrap_or("").to_string();
        let body = response.into_string().map_err(|e| e.to_string())?;
        let info = parse_userinfo(&info_header);
        let nodes = parse_text(&body);
        let nodes: Vec<Value> = nodes.into_iter().filter(|n| n["protocol"].as_str() != Some("subscription")).collect();
        if nodes.is_empty() {
            return Err("subscription did not include any configs".into());
        }
        let gid = id();
        self.groups.push(json!({
            "id": gid, "name": if title.is_empty() { name.to_string() } else { title }, "kind": "subscription", "url": url,
            "pinned": false, "expanded": true, "locked": false, "announcement": announce,
            "expire": info.3, "upload": info.0, "download": info.1, "total": info.2,
            "updated_at": now(), "profiles": []
        }));
        for node in nodes {
            self.insert_profile(&gid, node);
        }
        Ok(())
    }

    fn update_group(&mut self, group_id: &str) -> Result<(), String> {
        let url = self.groups.iter().find(|g| g["id"].as_str() == Some(group_id)).and_then(|g| g["url"].as_str()).unwrap_or("").to_string();
        if url.is_empty() {
            return Ok(());
        }
        let mut req = ureq::get(&url).set("User-Agent", self.settings["user_agent"].as_str().unwrap_or("V2Open"));
        if self.settings["send_hwid"].as_bool().unwrap_or(false) {
            req = req.set("X-HWID", self.settings["hwid"].as_str().unwrap_or(""));
        }
        let response = req.call().map_err(|e| e.to_string())?;
        let info_header = response.header("subscription-userinfo").unwrap_or("").to_string();
        let title = response.header("profile-title").unwrap_or("").to_string();
        let announce = response.header("announce").unwrap_or("").to_string();
        let body = response.into_string().map_err(|e| e.to_string())?;
        let info = parse_userinfo(&info_header);
        let nodes = parse_text(&body);
        if let Some(group) = self.groups.iter_mut().find(|g| g["id"].as_str() == Some(group_id)) {
            group["profiles"] = json!([]);
            group["updated_at"] = json!(now());
            if !title.is_empty() {
                group["name"] = json!(title);
            }
            if !announce.is_empty() {
                group["announcement"] = json!(announce);
            }
            if !info_header.is_empty() {
                group["expire"] = json!(info.3);
                group["upload"] = json!(info.0);
                group["download"] = json!(info.1);
                group["total"] = json!(info.2);
            }
        }
        self.save();
        for node in nodes {
            if node["protocol"].as_str() != Some("subscription") {
                self.insert_profile(group_id, node);
            }
        }
        Ok(())
    }

    fn save_profile(&mut self, profile: &Value) -> Result<(), String> {
        let mut data = profile.clone();
        data["link"] = json!(build_link(&data));
        if let Some(existing) = data["id"].as_str().filter(|s| !s.is_empty()) {
            for group in &mut self.groups {
                if let Some(arr) = group["profiles"].as_array_mut() {
                    for item in arr.iter_mut() {
                        if item["id"].as_str() == Some(existing) {
                            item["remark"] = data["remark"].clone();
                            item["protocol"] = data["protocol"].clone();
                            item["address"] = data["address"].clone();
                            item["port"] = data["port"].clone();
                            item["link"] = data["link"].clone();
                            item["data"] = data.clone();
                        }
                    }
                }
            }
            self.save();
        } else {
            let gid = self.groups[self.local_group_index()]["id"].as_str().unwrap_or("").to_string();
            self.insert_profile(&gid, data);
        }
        Ok(())
    }

    fn profiles_for(&self, id: &str, smart: bool) -> Vec<Value> {
        let selected = if id.is_empty() { self.settings["selected_id"].as_str().unwrap_or("") } else { id };
        if smart {
            let pool = if !selected.is_empty() {
                self.groups.iter().find(|g| g["profiles"].as_array().unwrap_or(&Vec::new()).iter().any(|p| p["id"].as_str() == Some(selected))).and_then(|g| g["profiles"].as_array()).cloned().unwrap_or_default()
            } else {
                self.groups.iter().flat_map(|g| g["profiles"].as_array().cloned().unwrap_or_default()).collect()
            };
            return pool.into_iter().filter_map(|p| {
                let data = node_data(&p);
                let protocol = data["protocol"].as_str().unwrap_or("");
                if protocol == "subscription" { None } else { Some(data) }
            }).collect();
        }
        let one = self.find_profile(selected).or_else(|| self.groups.iter().flat_map(|g| g["profiles"].as_array().cloned().unwrap_or_default()).next());
        one.map(|p| vec![node_data(&p)]).unwrap_or_default()
    }

    fn find_profile(&self, id: &str) -> Option<Value> {
        for group in &self.groups {
            if let Some(arr) = group["profiles"].as_array() {
                if let Some(p) = arr.iter().find(|p| p["id"].as_str() == Some(id)) {
                    return Some(p.clone());
                }
            }
        }
        None
    }

    fn prepare(&mut self, id: &str, smart: bool) -> Result<Value, String> {
        let cfg = self.prepare_files(id, smart, "proxy", true)?;
        let dns = self.settings["remote_dns"].as_str().unwrap_or("1.1.1.1");
        let host = dns.trim_start_matches("https://").trim_start_matches("tls://").split('/').next().unwrap_or(dns).split(':').next().unwrap_or(dns);
        Ok(json!({
            "path": cfg,
            "socks_port": if self.direct_bridge > 0 { self.direct_bridge as u64 } else { self.settings["socks_port"].as_u64().unwrap_or(10808) },
            "launch_core": self.direct_bridge == 0,
            "mtu": self.settings["mtu"].as_u64().unwrap_or(1500),
            "include_local": self.settings["include_local"].as_bool().unwrap_or(false),
            "kill_switch": self.settings["kill_switch"].as_bool().unwrap_or(false),
            "dns": host,
            "on_demand": self.settings["on_demand"].as_bool().unwrap_or(false),
            "on_demand_text": self.settings["on_demand_text"].as_str().unwrap_or(""),
            "combiner": self.settings["net_combiner"].as_bool().unwrap_or(false)
        }))
    }

    fn prepare_files(&mut self, id: &str, smart: bool, mode: &str, touch_selection: bool) -> Result<PathBuf, String> {
        let mut profiles = self.profiles_for(id, smart);
        if profiles.is_empty() {
            return Err("no profile".into());
        }
        self.disconnect()?;
        let dir = self.path.parent().unwrap_or(Path::new(".")).to_path_buf();
        let _ = fs::create_dir_all(&dir);
        let (extras, routed, stops) = self.front_xray(&mut profiles, &dir)?;
        let (profiles, mut running) = crate::sidecar::adapt_all(&profiles, &self.singbox, &dir.join("bridges"), &self.settings)?;
        running.children.extend(extras);
        running.stops.extend(stops);
        self.bridges = running;
        let built = if routed {
            build_pipe(&self.settings, &profiles, &self.routes, &self.rules, mode)
        } else {
            build_config(&self.settings, &profiles, &self.routes, &self.rules, mode)
        };
        let mut config = match built {
            Ok(config) => config,
            Err(err) => {
                crate::sidecar::stop(&mut self.bridges);
                return Err(err);
            }
        };
        if mode == "tun" {
            exclude_tunnel_addresses(&mut config, &self.bypass);
        }
        let cfg = dir.join("config.json");
        fs::write(&cfg, serde_json::to_string_pretty(&config).unwrap_or_else(|_| "{}".into())).map_err(|e| e.to_string())?;
        if !self.singbox.exists() {
            return Err("sing-box core was not found".into());
        }
        let check = Command::new(&self.singbox).args(["check", "-c"]).arg(&cfg).output().map_err(|e| e.to_string())?;
        if !check.status.success() {
            let err = String::from_utf8_lossy(&check.stderr);
            crate::sidecar::stop(&mut self.bridges);
            return Err(err.lines().last().unwrap_or("invalid configuration").to_string());
        }
        self.runtime.smart = smart || profiles.len() > 1;
        self.runtime.profile_name = if self.runtime.smart { "Smart".into() } else { profiles[0]["remark"].as_str().unwrap_or("").into() };
        self.direct_bridge = if routed && profiles.len() == 1 {
            profiles[0]["port"].as_u64().unwrap_or(0) as u16
        } else {
            0
        };
        if touch_selection && !smart && !id.is_empty() {
            self.settings["selected_id"] = json!(id);
            self.save();
        }
        Ok(cfg)
    }

    fn front_xray(&mut self, profiles: &mut Vec<Value>, dir: &Path) -> Result<(Vec<std::process::Child>, bool, Vec<Arc<AtomicBool>>), String> {
        let binds = self.combiner_binds();
        let owns_routing = !profiles.is_empty() && profiles.iter().all(|profile| xray_protocol(profile["protocol"].as_str().unwrap_or("")));
        let settings = self.settings.clone();
        let routes = self.routes.clone();
        let mut children = Vec::new();
        let mut extras = Vec::new();
        let mut race_stops = Vec::new();
        let mut complete = owns_routing;
        self.bypass.clear();
        for (index, profile) in profiles.iter_mut().enumerate() {
            if !xray_protocol(profile["protocol"].as_str().unwrap_or("")) {
                continue;
            }
            let mut origin = profile.clone();
            let host = origin["address"].as_str().unwrap_or("").to_string();
            let port = origin["port"].as_u64().unwrap_or(443).min(65535) as u16;
            self.bypass.extend(crate::xray::dial_addresses(&host, port));
            crate::xray::pin_reachable_address(&mut origin);
            if let Some(pinned) = origin["address"].as_str() {
                self.bypass.extend(crate::xray::dial_addresses(pinned, port));
            }
            let mut ports = Vec::new();
            for (bind_index, bind) in binds.iter().enumerate() {
                let port = 18080 + (index * 4 + bind_index) as u16;
                let bin = xray_binary(&self.singbox)?;
                let cfg = dir.join(format!("xray-{index}-{bind_index}.json"));
                let rendered = if owns_routing {
                    crate::xray::routed_socks(&settings, &origin, &routes, port, bind.as_deref())
                } else {
                    crate::xray::local_socks(&origin, port, bind.as_deref())
                };
                fs::write(&cfg, serde_json::to_string(&rendered).unwrap_or_else(|_| "{}".into())).map_err(|e| e.to_string())?;
                let check = xray_cmd(&bin, &self.data_dir()).args(["run", "-test", "-c"]).arg(&cfg).output().map_err(|e| e.to_string())?;
                if !check.status.success() {
                    complete = false;
                    break;
                }
                let log = File::create(dir.join(format!("xray-{index}-{bind_index}.log"))).map_err(|e| e.to_string())?;
                let err = log.try_clone().map_err(|e| e.to_string())?;
                children.push(xray_cmd(&bin, &self.data_dir()).args(["run", "-c"]).arg(&cfg).stdout(Stdio::from(log)).stderr(Stdio::from(err)).spawn().map_err(|e| e.to_string())?);
                ports.push(port);
            }
            if ports.is_empty() {
                complete = false;
            }
            if ports.len() > 1 {
                match crate::sidecar::race(&ports) {
                    Ok((port, stop)) => {
                        *profile = socks_profile(&origin, port);
                        race_stops.push(stop);
                    }
                    Err(_) => {
                        if let Some(port) = ports.first() { *profile = socks_profile(&origin, *port); }
                        for port in ports.into_iter().skip(1) { extras.push(socks_profile(&origin, port)); }
                    }
                }
            } else if let Some(port) = ports.first() {
                *profile = socks_profile(&origin, *port);
            }
        }
        profiles.extend(extras);
        let started = !children.is_empty();
        if started {
            self.runtime.engine = "xray".into();
        }
        Ok((children, complete && started, race_stops))
    }

    fn combiner_binds(&self) -> Vec<Option<String>> {
        if !self.settings["net_combiner"].as_bool().unwrap_or(false) {
            return vec![None];
        }
        let status = crate::platform::status();
        let mut binds = Vec::new();
        if !status.wifi_iface.is_empty() { binds.push(Some(status.wifi_iface)); }
        if !status.cell_iface.is_empty() { binds.push(Some(status.cell_iface)); }
        if binds.len() < 2 { vec![None] } else { binds }
    }

    fn connect(&mut self, id: &str, smart: bool) -> Result<(), String> {
        let mode = self.settings["mode"].as_str().unwrap_or("tun").to_string();
        let cfg = self.prepare_files(id, smart, &mode, true)?;
        self.runtime.phase = "connecting".into();
        self.runtime.error.clear();
        if mode == "tun" {
            self.disable_proxy();
            if let Err(err) = self.start_tun(&cfg) {
                crate::sidecar::stop(&mut self.bridges);
                return Err(err);
            }
            self.runtime.elevated = true;
        } else if let Err(err) = self.start_user(&cfg) {
            crate::sidecar::stop(&mut self.bridges);
            return Err(err);
        } else {
            self.runtime.elevated = false;
            if self.settings["apply_system_proxy"].as_bool().unwrap_or(true) {
                self.enable_proxy();
            }
        }
        self.runtime.connected = true;
        self.runtime.phase = "connected".into();
        self.runtime.connected_at = now();
        self.runtime.tunnel = if mode == "tun" { "admin".into() } else { "proxy".into() };
        self.runtime.upload_total = 0;
        self.runtime.download_total = 0;
        if !smart && !id.is_empty() {
            self.settings["selected_id"] = json!(id);
            self.save();
        }
        self.watch_traffic();
        Ok(())
    }

    fn start_user(&mut self, cfg: &Path) -> Result<(), String> {
        let log_path = self.path.parent().unwrap_or(Path::new(".")).join("core.log");
        let log = File::create(&log_path).map_err(|e| e.to_string())?;
        let err = log.try_clone().map_err(|e| e.to_string())?;
        let child = Command::new(&self.singbox)
            .args(["run", "-c"])
            .arg(cfg)
            .stdout(Stdio::from(log))
            .stderr(Stdio::from(err))
            .spawn()
            .map_err(|e| e.to_string())?;
        self.runtime.pid = child.id();
        self.child = Some(child);
        thread::sleep(std::time::Duration::from_millis(400));
        if let Some(child) = self.child.as_mut() {
            if let Ok(Some(_)) = child.try_wait() {
                let text = fs::read_to_string(&log_path).unwrap_or_default();
                return Err(text.lines().last().unwrap_or("core exited").to_string());
            }
        }
        Ok(())
    }

    fn start_tun(&mut self, cfg: &Path) -> Result<(), String> {
        let dir = self.path.parent().unwrap_or(Path::new(".")).to_path_buf();
        let log = dir.join("core.log");
        let pidfile = dir.join("core.pid");
        #[cfg(target_os = "macos")]
        {
            let script = dir.join("tun.sh");
            let hold = dir.join("core.hold");
            let cfg_s = cfg.display().to_string();
            fs::write(&hold, b"1").map_err(|e| e.to_string())?;
            let body = crate::platform::bash_supervised_script(&self.singbox, &["run", "-c", &cfg_s], &log, &pidfile, std::process::id(), &hold);
            fs::write(&script, body).map_err(|e| e.to_string())?;
            let _ = Command::new("chmod").args(["+x"]).arg(&script).status();
            let osa = crate::platform::osa_run_bash_script(&script, "V2Open needs permission to create the VPN tunnel.");
            let result = Command::new("osascript").arg("-e").arg(osa).output().map_err(|e| e.to_string())?;
            if !result.status.success() {
                let _ = fs::remove_file(&hold);
                let err = String::from_utf8_lossy(&result.stderr);
                return Err(if err.trim().is_empty() { "VPN permission was denied".into() } else { err.trim().to_string() });
            }
            self.runtime.pid = fs::read_to_string(&pidfile).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0);
            if self.runtime.pid == 0 || !crate::platform::alive(self.runtime.pid) {
                let _ = fs::remove_file(&hold);
                let detail = fs::read_to_string(&log).unwrap_or_default();
                let last = detail.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("tunnel did not start");
                return Err(last.to_string());
            }
        }
        Ok(())
    }

    fn disconnect(&mut self) -> Result<(), String> {
        *self.stop_traffic.lock().unwrap() = true;
        #[cfg(target_os = "macos")]
        {
            let dir = self.path.parent().unwrap_or(Path::new("."));
            let _ = fs::remove_file(dir.join("core.hold"));
        }
        crate::sidecar::stop(&mut self.bridges);
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
        if self.runtime.elevated && self.runtime.pid > 0 {
            #[cfg(target_os = "macos")]
            {
                let dir = self.path.parent().unwrap_or(Path::new("."));
                let _ = fs::remove_file(dir.join("core.hold"));
                let pid = self.runtime.pid;
                let deadline = Instant::now() + Duration::from_secs(3);
                while crate::platform::alive(pid) && Instant::now() < deadline {
                    thread::sleep(Duration::from_millis(100));
                }
                if crate::platform::alive(pid) {
                    let _ = Command::new("osascript").arg("-e").arg(format!("do shell script \"kill {}\" with administrator privileges with prompt \"V2Open needs permission to stop the VPN tunnel.\"", pid)).status();
                }
            }
        } else if self.runtime.pid > 0 {
            let _ = Command::new("kill").arg(self.runtime.pid.to_string()).status();
        }
        self.runtime.pid = 0;
        self.runtime.elevated = false;
        self.disable_proxy();
        let _ = fs::remove_file(std::env::temp_dir().join("v2open-traffic.json"));
        self.runtime.connected = false;
        self.runtime.phase = "idle".into();
        self.runtime.smart = false;
        self.runtime.upload_speed = 0;
        self.runtime.download_speed = 0;
        self.bypass.clear();
        if !self.hold_routes {
            self.clear_blackhole();
        }
        Ok(())
    }

    fn watch_traffic(&mut self) {
        *self.stop_traffic.lock().unwrap() = false;
        let stop = self.stop_traffic.clone();
        let port = self.settings["clash_port"].as_u64().unwrap_or(9097) as u16;
        let flag = stop.clone();
        thread::spawn(move || {
            let mut stream = None;
            for _ in 0..40 {
                if *flag.lock().unwrap() {
                    return;
                }
                if let Ok(s) = TcpStream::connect(("127.0.0.1", port)) {
                    stream = Some(s);
                    break;
                }
                thread::sleep(Duration::from_millis(250));
            }
            let Ok(mut stream) = stream.ok_or(()) else { return };
            let _ = stream.set_read_timeout(Some(std::time::Duration::from_secs(2)));
            let _ = stream.write_all(b"GET /traffic HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: keep-alive\r\n\r\n");
            let mut reader = BufReader::new(stream);
            let mut line = String::new();
            let mut upload_total: u64 = 0;
            let mut download_total: u64 = 0;
            while !*flag.lock().unwrap() {
                line.clear();
                if reader.read_line(&mut line).ok().unwrap_or(0) == 0 {
                    break;
                }
                let trimmed = line.trim();
                let Some(start) = trimmed.find('{') else { continue };
                if let Ok(value) = serde_json::from_str::<Value>(&trimmed[start..]) {
                    let up = value["up"].as_u64().unwrap_or(0);
                    let down = value["down"].as_u64().unwrap_or(0);
                    upload_total = upload_total.saturating_add(up);
                    download_total = download_total.saturating_add(down);
                    let payload = json!({
                        "up": up,
                        "down": down,
                        "upload_total": upload_total,
                        "download_total": download_total
                    });
                    let _ = fs::write(
                        std::env::temp_dir().join("v2open-traffic.json"),
                        serde_json::to_string(&payload).unwrap_or_default(),
                    );
                }
            }
        });
    }

    fn pull_traffic(&mut self) {
        if !self.runtime.connected {
            return;
        }
        let path = std::env::temp_dir().join("v2open-traffic.json");
        if let Ok(text) = fs::read_to_string(&path) {
            if let Ok(value) = serde_json::from_str::<Value>(&text) {
                let up = value["up"].as_u64().unwrap_or(0);
                let down = value["down"].as_u64().unwrap_or(0);
                self.runtime.upload_speed = up;
                self.runtime.download_speed = down;
                if let Some(total) = value["upload_total"].as_u64() {
                    self.runtime.upload_total = total;
                }
                if let Some(total) = value["download_total"].as_u64() {
                    self.runtime.download_total = total;
                }
            }
        }
    }

    fn runtime_memory_bytes(&self) -> u64 {
        if self.runtime.pid > 0 {
            return crate::platform::process_rss_bytes(self.runtime.pid);
        }
        0
    }

    fn ping_one(&self, id: &str) -> i64 {
        let Some(profile) = self.find_profile(id) else { return -1 };
        let data = node_data(&profile);
        let host = data["address"].as_str().unwrap_or("");
        let port = port_num(&data["port"]);
        if host.is_empty() {
            return 0;
        }
        let port = if port == 0 { 443 } else { port };
        let timeout = Duration::from_secs(3);
        let prefer_ipv6 = self.settings["prefer_ipv6"].as_bool().unwrap_or(false);
        if let Some(ms) = tcp_connect_ms(host, port, timeout, prefer_ipv6) {
            return ms as i64;
        }
        0
    }

    fn ping_via_local_proxy(&self) -> i64 {
        let http = self.settings["http_port"].as_u64().unwrap_or(10807);
        let url = self.settings["speed_endpoint"].as_str().unwrap_or("https://www.gstatic.com/generate_204");
        let Ok(proxy) = ureq::Proxy::new(&format!("http://127.0.0.1:{http}")) else {
            return -1;
        };
        let agent = ureq::AgentBuilder::new()
            .proxy(proxy)
            .timeout(Duration::from_secs(self.settings["speed_timeout"].as_u64().unwrap_or(8)))
            .build();
        let started = Instant::now();
        if agent.get(url).call().is_ok() {
            started.elapsed().as_millis().max(1) as i64
        } else {
            -1
        }
    }

    fn set_ping(&mut self, id: &str, ms: i64) {
        self.set_metrics(id, ms, None, None);
    }

    fn set_metrics(&mut self, id: &str, ping: i64, download_bps: Option<i64>, upload_bps: Option<i64>) {
        for group in &mut self.groups {
            if let Some(arr) = group["profiles"].as_array_mut() {
                for profile in arr {
                    if profile["id"].as_str() == Some(id) {
                        profile["ping"] = json!(ping);
                        if let Some(d) = download_bps {
                            profile["download_bps"] = json!(d);
                        }
                        if let Some(u) = upload_bps {
                            profile["upload_bps"] = json!(u);
                        }
                    }
                }
            }
        }
        self.save();
    }

    fn measure_profile(&mut self, id: &str, bench: bool) -> Result<(), String> {
        if bench {
            match self.benchmark_profile(id) {
                Ok((ms, down, up)) => self.set_metrics(id, ms, Some(down as i64), Some(up as i64)),
                Err(_) => {
                    let ms = self.ping_one(id);
                    self.set_ping(id, ms);
                }
            }
        } else {
            let ms = self.ping_one(id);
            self.set_ping(id, ms);
        }
        Ok(())
    }

    fn benchmark_profile(&mut self, id: &str) -> Result<(i64, u64, u64), String> {
        let was_connected = self.runtime.connected;
        let was_id = self.settings["selected_id"].as_str().unwrap_or("").to_string();
        let was_smart = self.runtime.smart;
        let result = (|| {
            let cfg = self.prepare_files(id, false, "proxy", false)?;
            self.start_user(&cfg)?;
            thread::sleep(Duration::from_millis(700));
            let ms = {
                let proxy_ms = self.ping_via_local_proxy();
                if proxy_ms > 0 {
                    proxy_ms
                } else {
                    self.ping_one(id)
                }
            };
            let duration = self.settings["throughput_duration"].as_u64().unwrap_or(10).max(3);
            let (down, up) = self.measure_proxy_throughput(duration);
            Ok((ms, down, up))
        })();
        let _ = self.disconnect();
        if was_connected && !was_id.is_empty() {
            let _ = self.connect(&was_id, was_smart);
        }
        result
    }

    fn measure_proxy_throughput(&self, duration_secs: u64) -> (u64, u64) {
        let urls = [
            "https://www.youtube.com/generate_204",
            "https://www.instagram.com/",
            "https://telegram.org/",
        ];
        let http = self.settings["http_port"].as_u64().unwrap_or(10807);
        let Ok(proxy) = ureq::Proxy::new(&format!("http://127.0.0.1:{http}")) else {
            return (0, 0);
        };
        let agent = ureq::AgentBuilder::new()
            .proxy(proxy)
            .timeout(Duration::from_secs(20))
            .build();
        let end = Instant::now() + Duration::from_secs(duration_secs);
        let mut down_bytes = 0u64;
        let mut up_bytes = 0u64;
        let mut index = 0usize;
        while Instant::now() < end {
            let url = urls[index % urls.len()];
            index += 1;
            if let Ok(response) = agent.get(url).call() {
                let mut reader = response.into_reader();
                let mut buf = [0u8; 16384];
                while Instant::now() < end {
                    match reader.read(&mut buf) {
                        Ok(0) => break,
                        Ok(n) => down_bytes += n as u64,
                        Err(_) => break,
                    }
                }
            }
            if Instant::now() >= end {
                break;
            }
            let payload = vec![0u8; 128 * 1024];
            let began = Instant::now();
            if agent.post(url).send_bytes(&payload).is_ok() {
                up_bytes += payload.len() as u64;
                let _ = began.elapsed();
            }
        }
        let secs = duration_secs.max(1) as f64;
        (((down_bytes as f64) / secs) as u64, ((up_bytes as f64) / secs) as u64)
    }

    fn pick_best_profile(&mut self, measure: bool) -> Result<String, String> {
        let ids: Vec<String> = self
            .groups
            .iter()
            .flat_map(|g| g["profiles"].as_array().cloned().unwrap_or_default())
            .filter_map(|p| {
                if p["protocol"].as_str() == Some("subscription") {
                    None
                } else {
                    p["id"].as_str().map(|s| s.to_string())
                }
            })
            .collect();
        if ids.is_empty() {
            return Err("no profile".into());
        }
        if measure {
            for id in &ids {
                let ping = self.ping_one(id);
                self.set_ping(id, ping);
            }
        }
        let mut items: Vec<Value> = self
            .groups
            .iter()
            .flat_map(|g| g["profiles"].as_array().cloned().unwrap_or_default())
            .collect();
        items.sort_by(|a, b| {
            let ping = Self::cmp_asc_metric(a["ping"].as_i64().unwrap_or(-1), b["ping"].as_i64().unwrap_or(-1));
            if ping != std::cmp::Ordering::Equal {
                return ping;
            }
            Self::cmp_desc_metric(a["download_bps"].as_i64().unwrap_or(-1), b["download_bps"].as_i64().unwrap_or(-1))
        });
        items
            .iter()
            .find(|p| p["ping"].as_i64().unwrap_or(-1) > 0)
            .or_else(|| items.first())
            .and_then(|p| p["id"].as_str())
            .map(String::from)
            .ok_or_else(|| "no profile".into())
    }

    fn cmp_asc_metric(a: i64, b: i64) -> std::cmp::Ordering {
        let av = if a > 0 { a } else { i64::MAX };
        let bv = if b > 0 { b } else { i64::MAX };
        av.cmp(&bv)
    }

    fn cmp_desc_metric(a: i64, b: i64) -> std::cmp::Ordering {
        let av = if a > 0 { a } else { i64::MIN };
        let bv = if b > 0 { b } else { i64::MIN };
        bv.cmp(&av)
    }

    fn logs(&self) -> String {
        let path = self.path.parent().unwrap_or(Path::new(".")).join("core.log");
        Self::tail_log(&path)
    }

    fn sidecar_logs(&self) -> String {
        let dir = self.path.parent().unwrap_or(Path::new(".")).join("bridges");
        let mut chunks = Vec::new();
        if let Ok(entries) = fs::read_dir(&dir) {
            let mut files: Vec<PathBuf> = entries
                .flatten()
                .flat_map(|e| fs::read_dir(e.path()).ok())
                .flatten()
                .flatten()
                .map(|e| e.path())
                .filter(|p| {
                    let name = p.file_name().and_then(|s| s.to_str()).unwrap_or("");
                    name.ends_with(".log") || name.contains("mtu") || name.contains("masterdns")
                })
                .collect();
            files.sort();
            for path in files {
                let name = path.file_name().and_then(|s| s.to_str()).unwrap_or("log");
                let body = Self::tail_log(&path);
                if !body.trim().is_empty() {
                    chunks.push(format!("----- {name} -----\n{body}"));
                }
            }
        }
        if chunks.is_empty() {
            "no sidecar logs".into()
        } else {
            chunks.join("\n\n")
        }
    }

    fn tail_log(path: &Path) -> String {
        strip_ansi(&fs::read_to_string(path).unwrap_or_default())
            .lines()
            .rev()
            .take(200)
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .collect::<Vec<_>>()
            .join("\n")
    }

    fn enable_proxy(&self) {
        let host = "127.0.0.1";
        let socks = self.settings["socks_port"].as_u64().unwrap_or(10808).to_string();
        let http = self.settings["http_port"].as_u64().unwrap_or(10807).to_string();
        #[cfg(target_os = "macos")]
        {
            if let Ok(out) = Command::new("networksetup").arg("-listallnetworkservices").output() {
                let services: Vec<String> = String::from_utf8_lossy(&out.stdout).lines().skip(1).filter(|l| !l.is_empty() && !l.starts_with('*') && !l.starts_with("An asterisk")).map(|s| s.to_string()).collect();
                let backup_path = self.path.parent().unwrap_or(Path::new(".")).join("proxy-backup.json");
                if !backup_path.exists() {
                    let mut backup = json!({});
                    for service in &services {
                        backup[service] = json!({
                            "socks": mac_proxy(service, "getsocksfirewallproxy"),
                            "web": mac_proxy(service, "getwebproxy"),
                            "secure": mac_proxy(service, "getsecurewebproxy")
                        });
                    }
                    let _ = fs::write(&backup_path, backup.to_string());
                }
                for service in services {
                    if self.settings["socks_enabled"].as_bool().unwrap_or(true) {
                        let _ = Command::new("networksetup").args(["-setsocksfirewallproxy", &service, host, &socks]).status();
                        let _ = Command::new("networksetup").args(["-setsocksfirewallproxystate", &service, "on"]).status();
                    }
                    if self.settings["http_enabled"].as_bool().unwrap_or(true) {
                        let _ = Command::new("networksetup").args(["-setwebproxy", &service, host, &http]).status();
                        let _ = Command::new("networksetup").args(["-setsecurewebproxy", &service, host, &http]).status();
                        let _ = Command::new("networksetup").args(["-setwebproxystate", &service, "on"]).status();
                        let _ = Command::new("networksetup").args(["-setsecurewebproxystate", &service, "on"]).status();
                    }
                    let _ = Command::new("networksetup").args(["-setproxybypassdomains", &service, "localhost", "127.0.0.1", "*.local"]).status();
                }
            }
        }
    }

    fn disable_proxy(&self) {
        #[cfg(target_os = "macos")]
        {
            let backup_path = self.path.parent().unwrap_or(Path::new(".")).join("proxy-backup.json");
            if let Ok(text) = fs::read_to_string(&backup_path) {
                if let Ok(backup) = serde_json::from_str::<Value>(&text) {
                    if let Some(map) = backup.as_object() {
                        for (service, state) in map {
                            mac_restore(service, "setsocksfirewallproxy", "setsocksfirewallproxystate", &state["socks"]);
                            mac_restore(service, "setwebproxy", "setwebproxystate", &state["web"]);
                            mac_restore(service, "setsecurewebproxy", "setsecurewebproxystate", &state["secure"]);
                        }
                    }
                }
                let _ = fs::remove_file(backup_path);
            }
        }
    }

    fn public_groups(&self) -> Vec<Value> {
        self.groups.iter().map(|group| {
            let mut group = group.clone();
            let id = group["id"].as_str().unwrap_or("").to_string();
            let locked = group["locked"].as_bool().unwrap_or(false) && !self.unlocked.contains(&id);
            if locked {
                if let Some(arr) = group["profiles"].as_array_mut() {
                    for profile in arr {
                        profile["link"] = json!("");
                        profile["data"] = json!({"locked": true});
                        profile["locked"] = json!(true);
                    }
                }
            }
            if let Some(obj) = group.as_object_mut() {
                obj.remove("lock_hash");
            }
            group
        }).collect()
    }

    fn refresh_net(&mut self) {
        if now().saturating_sub(self.runtime.net_at) < 3 && !self.runtime.net_kind.is_empty() {
            return;
        }
        let status = crate::platform::status();
        self.runtime.ssid = status.ssid;
        self.runtime.net_kind = status.kind;
        self.runtime.net_iface = status.iface;
        self.runtime.net_at = now();
    }

    fn tick(&mut self) -> Result<(), String> {
        if self.settings["icloud"].as_bool().unwrap_or(false) {
            self.merge_icloud();
        }
        self.refresh_net();
        let kind = self.runtime.net_kind.clone();
        let ssid = self.runtime.ssid.clone();
        let previous = self.runtime.seen_iface.clone();
        let iface = self.runtime.net_iface.clone();
        self.runtime.seen_iface = iface.clone();
        if self.runtime.connected && self.settings["kill_switch"].as_bool().unwrap_or(false) && self.runtime.pid > 0 && now().saturating_sub(self.runtime.connected_at) > 3 && !crate::platform::alive(self.runtime.pid) {
            let id = self.settings["selected_id"].as_str().unwrap_or("").to_string();
            let smart = self.runtime.smart;
            if let Err(err) = self.connect(&id, smart) {
                self.arm_blackhole();
                self.runtime.connected = false;
                self.runtime.phase = "killswitch".into();
                self.runtime.error = format!("the tunnel stopped and the kill switch is blocking traffic: {err}");
            }
            return Ok(());
        }
        if self.settings["on_demand"].as_bool().unwrap_or(false) && self.runtime.phase != "killswitch" {
            if let Some(action) = demand_action(self.settings["on_demand_text"].as_str().unwrap_or(""), &kind, &ssid) {
                if action == "connect" && !self.runtime.connected {
                    let id = self.settings["selected_id"].as_str().unwrap_or("").to_string();
                    let _ = self.connect(&id, false);
                } else if action == "disconnect" && self.runtime.connected {
                    let _ = self.disconnect();
                    return Ok(());
                }
            }
        }
        if self.settings["net_combiner"].as_bool().unwrap_or(false) && self.runtime.connected && !previous.is_empty() && !iface.is_empty() && iface != previous {
            let id = self.settings["selected_id"].as_str().unwrap_or("").to_string();
            let smart = self.runtime.smart;
            let _ = self.connect(&id, smart);
        }
        self.run_schedulers();
        Ok(())
    }

    fn scheduler_due(last: u64, hours: u64) -> bool {
        now().saturating_sub(last) >= hours.max(1) * 3600
    }

    fn geo_auto_enabled(&self) -> bool {
        self.settings["geo_auto_update"]
            .as_bool()
            .unwrap_or_else(|| self.settings["auto_update"].as_bool().unwrap_or(false))
    }

    fn run_schedulers(&mut self) {
        let geo_due = self.geo_auto_enabled()
            && Self::scheduler_due(
                self.settings["geo_last_auto_update"].as_u64().unwrap_or(0),
                self.settings["geo_auto_interval_hours"].as_u64().unwrap_or(24),
            );
        let sub_due = self.settings["sub_auto_update"].as_bool().unwrap_or(false)
            && Self::scheduler_due(
                self.settings["sub_last_auto_update"].as_u64().unwrap_or(0),
                self.settings["sub_auto_interval_hours"].as_u64().unwrap_or(24),
            );
        if geo_due {
            if self.update_all_geo_assets().is_ok() {
                self.settings["geo_last_auto_update"] = json!(now());
                self.save();
            }
            return;
        }
        if sub_due {
            self.refresh_due_subscriptions();
        }
    }

    fn refresh_due_subscriptions(&mut self) {
        let ids: Vec<String> = self
            .groups
            .iter()
            .filter(|g| {
                let url = g["url"].as_str().unwrap_or("").trim();
                !url.is_empty()
            })
            .filter_map(|g| g["id"].as_str().map(|s| s.to_string()))
            .collect();
        let mut last_err = String::new();
        for id in ids {
            if let Err(err) = self.update_group(&id) {
                last_err = err;
            }
        }
        self.settings["sub_last_auto_update"] = json!(now());
        self.settings["sub_last_error"] = json!(last_err);
        self.save();
    }

    fn optimize_mtu(&mut self) -> Result<Value, String> {
        let floor = self.settings["min_upload_mtu"].as_u64().unwrap_or(576).max(576) as usize;
        let ceiling = self
            .settings["max_download_mtu"]
            .as_u64()
            .unwrap_or(1500)
            .clamp(900, 9000) as usize;
        let url = self.settings["speed_endpoint"].as_str().unwrap_or("https://www.gstatic.com/generate_204");
        let timeout = Duration::from_secs(self.settings["speed_timeout"].as_u64().unwrap_or(8));
        let http_port = self.settings["http_port"].as_u64().unwrap_or(10807);
        let use_proxy = self.runtime.connected;
        let mut lo = floor;
        let mut hi = ceiling;
        let mut best = floor;
        while lo <= hi {
            let mid = lo + (hi - lo) / 2;
            if mtu_probe_post(url, mid, timeout, use_proxy, http_port) {
                best = mid;
                lo = mid + 1;
            } else {
                if mid == 0 {
                    break;
                }
                hi = mid - 1;
            }
        }
        let mtu = (best + 120).min(1500).max(576) as u64;
        self.settings["mtu"] = json!(mtu);
        self.settings["mtu_last_result"] = json!(mtu);
        Ok(json!({"mtu": mtu, "payload": best}))
    }

    pub fn speed_plan(&self) -> SpeedPlan {
        SpeedPlan {
            connected: self.runtime.connected,
            http_port: self.settings["http_port"].as_u64().unwrap_or(10807).min(65535) as u16,
            socks_port: if self.direct_bridge > 0 {
                self.direct_bridge
            } else {
                self.settings["socks_port"].as_u64().unwrap_or(10808).min(65535) as u16
            },
            http_enabled: self.settings["http_enabled"].as_bool().unwrap_or(true),
            socks_enabled: self.settings["socks_enabled"].as_bool().unwrap_or(true),
        }
    }

    fn speed_test(&mut self) -> Result<Value, String> {
        if self.settings["speed_mode"].as_str() == Some("tcp") {
            let url = self.settings["speed_endpoint"].as_str().unwrap_or("https://www.gstatic.com/generate_204");
            let host = url.trim_start_matches("https://").trim_start_matches("http://").split('/').next().unwrap_or(url);
            let (host, port) = crate::parser::split_host_port(host, 443);
            let prefer_ipv6 = self.settings["prefer_ipv6"].as_bool().unwrap_or(false);
            let ms = tcp_connect_ms(&host, port, Duration::from_secs(self.settings["speed_timeout"].as_u64().unwrap_or(8)), prefer_ipv6).unwrap_or(0);
            return Ok(json!({"mode": "tcp", "tcp_ms": ms, "host": host, "port": port}));
        }
        run_speed_probe(&self.speed_plan())
    }

    fn restore_payload(&mut self, data: &Value) {
        if let Some(settings) = data.get("settings") {
            let mut merged = defaults();
            if let (Some(dst), Some(src)) = (merged.as_object_mut(), settings.as_object()) {
                for (k, v) in src {
                    dst.insert(k.clone(), v.clone());
                }
            }
            self.settings = merged;
            crate::migrate::migrate_settings(&mut self.settings);
            crate::dns_items::ensure_dns_items(&mut self.settings);
            crate::xray_balancers::ensure_balancers(&mut self.settings);
        }
        if data.get("groups").is_some() {
            self.groups = data["groups"].as_array().cloned().unwrap_or_default();
        }
        if data.get("routes").is_some() {
            self.routes = data["routes"].as_array().cloned().unwrap_or_default();
        }
        self.unlocked.clear();
        self.save();
    }

    fn arm_blackhole(&mut self) {
        if self.runtime.blackhole {
            return;
        }
        #[cfg(target_os = "macos")]
        {
            let script = "route -n add -inet -blackhole 0.0.0.0/1; route -n add -inet -blackhole 128.0.0.0/1";
            let osa = format!("do shell script \"{script}\" with administrator privileges with prompt \"V2Open kill switch needs permission to block traffic.\"");
            if Command::new("osascript").arg("-e").arg(osa).status().map(|s| s.success()).unwrap_or(false) {
                self.runtime.blackhole = true;
            }
        }
    }

    fn clear_blackhole(&mut self) {
        if !self.runtime.blackhole {
            return;
        }
        #[cfg(target_os = "macos")]
        {
            let script = "route -n delete -inet -blackhole 0.0.0.0/1; route -n delete -inet -blackhole 128.0.0.0/1";
            let osa = format!("do shell script \"{script}\" with administrator privileges with prompt \"V2Open needs permission to remove the kill switch.\"");
            let _ = Command::new("osascript").arg("-e").arg(osa).status();
        }
        self.runtime.blackhole = false;
    }
}

#[derive(Clone)]
pub struct SpeedPlan {
    pub connected: bool,
    pub http_port: u16,
    pub socks_port: u16,
    pub http_enabled: bool,
    pub socks_enabled: bool,
}

enum SpeedProxyKind {
    Http,
    Socks,
    Direct,
}

const SPEED_DOWNLOAD_URLS: &[&str] = &[
    "https://speed.cloudflare.com/__down?bytes=25000000",
    "https://speed.cloudflare.com/__down?bytes=8000000",
    "http://speedtest.tele2.net/10MB.zip",
];

const SPEED_DOWNLOAD_SECS: u64 = 20;
const SPEED_UPLOAD_SECS: u64 = 20;

#[derive(Clone, Default)]
pub struct SpeedProgress {
    pub running: bool,
    pub phase: String,
    pub live_bps: u64,
    pub download_bps: i64,
    pub upload_bps: i64,
    pub tcp_ms: i64,
    pub icmp_ms: i64,
    pub jitter_ms: i64,
    pub bytes: u64,
    pub exit_ip: String,
    pub exit_country: String,
    pub country_code: String,
    pub vpn_active: bool,
    pub error: String,
}

struct SpeedState {
    progress: SpeedProgress,
}

impl SpeedState {
    const fn new() -> Self {
        Self { progress: SpeedProgress { running: false, phase: String::new(), live_bps: 0, download_bps: -1, upload_bps: -1, tcp_ms: -1, icmp_ms: -1, jitter_ms: -1, bytes: 0, exit_ip: String::new(), exit_country: String::new(), country_code: String::new(), vpn_active: false, error: String::new() } }
    }
}

static SPEED_STATE: Mutex<SpeedState> = Mutex::new(SpeedState::new());

fn speed_touch(report: bool, update: impl FnOnce(&mut SpeedProgress)) {
    if !report {
        return;
    }
    if let Ok(mut guard) = SPEED_STATE.lock() {
        update(&mut guard.progress);
    }
}

pub fn speed_progress_value() -> Value {
    let guard = SPEED_STATE.lock().unwrap();
    let p = &guard.progress;
    json!({
        "running": p.running,
        "phase": p.phase,
        "live_bps": p.live_bps,
        "download_bps": p.download_bps,
        "upload_bps": p.upload_bps,
        "tcp_ms": p.tcp_ms,
        "icmp_ms": p.icmp_ms,
        "jitter_ms": p.jitter_ms,
        "bytes": p.bytes,
        "exit_ip": p.exit_ip,
        "exit_country": p.exit_country,
        "country_code": p.country_code,
        "vpn_active": p.vpn_active,
        "error": p.error,
    })
}

pub fn speed_start_probe(plan: SpeedPlan) -> Result<Value, String> {
    let mut guard = SPEED_STATE.lock().map_err(|e| e.to_string())?;
    if guard.progress.running {
        return Err("speed test already running".into());
    }
    guard.progress = SpeedProgress {
        running: true,
        phase: "starting".into(),
        ..SpeedProgress::default()
    };
    drop(guard);
    thread::spawn(move || {
        let result = run_speed_probe_inner(&plan, true);
        let mut guard = SPEED_STATE.lock().unwrap();
        match result {
            Ok(data) => {
                guard.progress.running = false;
                guard.progress.phase = "done".into();
                guard.progress.live_bps = 0;
                guard.progress.tcp_ms = data["tcp_ms"].as_i64().unwrap_or(-1);
                guard.progress.icmp_ms = data["icmp_ms"].as_i64().unwrap_or(-1);
                guard.progress.jitter_ms = data["jitter_ms"].as_i64().unwrap_or(-1);
                guard.progress.bytes = data["bytes"].as_u64().unwrap_or(0);
                guard.progress.download_bps = data["download_bps"].as_i64().unwrap_or(-1);
                guard.progress.upload_bps = data["upload_bps"].as_i64().unwrap_or(-1);
                guard.progress.exit_ip = data["exit_ip"].as_str().unwrap_or("").into();
                guard.progress.exit_country = data["exit_country"].as_str().unwrap_or("").into();
                guard.progress.country_code = data["country_code"].as_str().unwrap_or("").into();
                guard.progress.vpn_active = data["vpn_active"].as_bool().unwrap_or(false);
            }
            Err(err) => {
                guard.progress.running = false;
                guard.progress.phase = "error".into();
                guard.progress.error = err;
                guard.progress.live_bps = 0;
            }
        }
    });
    Ok(json!({"started": true}))
}

fn geo_via(agent: &ureq::Agent) -> Option<(String, String, String)> {
    let response = agent.get("https://ipwho.is/").call().ok()?;
    let body = response.into_string().ok()?;
    let value: Value = serde_json::from_str(&body).ok()?;
    if value["success"].as_bool() != Some(true) {
        return None;
    }
    let ip = value["ip"].as_str()?.trim().to_string();
    if ip.is_empty() {
        return None;
    }
    let country = value["country"].as_str().unwrap_or("").trim().to_string();
    let code = value["country_code"].as_str().unwrap_or("").trim().to_string();
    Some((ip, country, code))
}

fn speed_transfer_timeout() -> Duration {
    Duration::from_secs(SPEED_DOWNLOAD_SECS + SPEED_UPLOAD_SECS + 8)
}

fn speed_agent(plan: &SpeedPlan, kind: SpeedProxyKind, timeout: Duration) -> Result<ureq::Agent, String> {
    match kind {
        SpeedProxyKind::Direct => Ok(ureq::AgentBuilder::new().timeout(timeout).build()),
        SpeedProxyKind::Http if plan.connected && plan.http_enabled => {
            let proxy = ureq::Proxy::new(&format!("http://127.0.0.1:{}", plan.http_port)).map_err(|e| e.to_string())?;
            Ok(ureq::AgentBuilder::new().proxy(proxy).timeout(timeout).build())
        }
        SpeedProxyKind::Socks if plan.connected && plan.socks_enabled => {
            let proxy = ureq::Proxy::new(&format!("socks5://127.0.0.1:{}", plan.socks_port)).map_err(|e| e.to_string())?;
            Ok(ureq::AgentBuilder::new().proxy(proxy).timeout(timeout).build())
        }
        _ => Err("proxy unavailable".into()),
    }
}

fn speed_agents(plan: &SpeedPlan) -> Result<(ureq::Agent, ureq::Agent), String> {
    let transfer_timeout = speed_transfer_timeout();
    let quick_timeout = Duration::from_secs(4);
    if plan.connected {
        if plan.http_enabled {
            if let Ok(quick) = speed_agent(plan, SpeedProxyKind::Http, quick_timeout) {
                if let Ok(transfer) = speed_agent(plan, SpeedProxyKind::Http, transfer_timeout) {
                    return Ok((quick, transfer));
                }
            }
        }
        if plan.socks_enabled {
            let quick = speed_agent(plan, SpeedProxyKind::Socks, quick_timeout)?;
            let transfer = speed_agent(plan, SpeedProxyKind::Socks, transfer_timeout)?;
            return Ok((quick, transfer));
        }
        return Err("no local proxy inbound".into());
    }
    Ok((
        speed_agent(plan, SpeedProxyKind::Direct, quick_timeout)?,
        speed_agent(plan, SpeedProxyKind::Direct, transfer_timeout)?,
    ))
}

fn speed_transfer_candidates(plan: &SpeedPlan) -> Vec<ureq::Agent> {
    let timeout = speed_transfer_timeout();
    let mut agents = Vec::new();
    if plan.connected {
        if plan.http_enabled {
            if let Ok(agent) = speed_agent(plan, SpeedProxyKind::Http, timeout) {
                agents.push(agent);
            }
        }
        if plan.socks_enabled {
            if let Ok(agent) = speed_agent(plan, SpeedProxyKind::Socks, timeout) {
                agents.push(agent);
            }
        }
    } else if let Ok(agent) = speed_agent(plan, SpeedProxyKind::Direct, timeout) {
        agents.push(agent);
    }
    agents
}

fn probe_download(transfer: &ureq::Agent, report: bool) -> (u64, u64) {
    speed_touch(report, |p| {
        p.phase = "download".into();
        p.live_bps = 0;
    });
    for url in SPEED_DOWNLOAD_URLS {
        let (bytes, rate) = download_from_url(transfer, url, report);
        if bytes > 0 {
            return (bytes, rate);
        }
    }
    (0, 0)
}

fn download_from_url(transfer: &ureq::Agent, url: &str, report: bool) -> (u64, u64) {
    let began = Instant::now();
    let limit = Duration::from_secs(SPEED_DOWNLOAD_SECS);
    let mut bytes = 0u64;
    let Ok(response) = transfer.get(url).call() else {
        return (0, 0);
    };
    let mut reader = response.into_reader();
    let mut buf = [0u8; 32 * 1024];
    while began.elapsed() < limit {
        match reader.read(&mut buf) {
            Ok(0) | Err(_) => break,
            Ok(n) => {
                bytes += n as u64;
                let elapsed = began.elapsed();
                let live = rate_bps(bytes, elapsed);
                speed_touch(report, |p| {
                    p.bytes = bytes;
                    p.live_bps = live;
                    p.download_bps = live as i64;
                });
            }
        }
    }
    (bytes, rate_bps(bytes, began.elapsed().max(Duration::from_millis(1))))
}

fn measure_speed(
    plan: &SpeedPlan,
    report: bool,
) -> Result<(u64, u64, u64, u64, u64, (String, String, String)), String> {
    let (quick, default_transfer) = speed_agents(plan)?;
    let mut transfer = default_transfer;
    speed_touch(report, |p| {
        p.phase = "ping".into();
        p.live_bps = 0;
    });
    let exit = geo_via(&quick);
    let mut samples = Vec::new();
    for _ in 0..2 {
        let began = Instant::now();
        if quick.get("https://www.gstatic.com/generate_204").call().is_ok() {
            samples.push(began.elapsed().as_millis().max(1) as u64);
        }
    }
    let ping = samples.iter().copied().min().unwrap_or(0);
    let jitter = samples.iter().copied().max().unwrap_or(ping).saturating_sub(ping);
    speed_touch(report, |p| {
        p.tcp_ms = ping as i64;
        p.icmp_ms = ping as i64;
        p.jitter_ms = jitter as i64;
    });

    let mut bytes = 0u64;
    let mut download_bps = 0u64;
    for agent in speed_transfer_candidates(plan) {
        let (got, rate) = probe_download(&agent, report);
        if got > bytes {
            bytes = got;
            download_bps = rate;
            transfer = agent;
        }
        if bytes > 0 {
            break;
        }
    }
    if bytes == 0 {
        let (got, rate) = probe_download(&transfer, report);
        bytes = got;
        download_bps = rate;
    }

    speed_touch(report, |p| {
        p.phase = "upload".into();
        p.download_bps = download_bps as i64;
        p.live_bps = 0;
    });
    let payload = vec![0u8; 64 * 1024];
    let upload_began = Instant::now();
    let upload_limit = Duration::from_secs(SPEED_UPLOAD_SECS);
    let mut upload_bytes = 0u64;
    while upload_began.elapsed() < upload_limit {
        match transfer.post("https://speed.cloudflare.com/__up").send_bytes(&payload) {
            Ok(_) => {
                upload_bytes += payload.len() as u64;
                let elapsed = upload_began.elapsed();
                let live = rate_bps(upload_bytes, elapsed);
                speed_touch(report, |p| {
                    p.live_bps = live;
                    p.upload_bps = live as i64;
                });
            }
            Err(_) => break,
        }
    }
    let upload_bps = rate_bps(upload_bytes, upload_began.elapsed().max(Duration::from_millis(1)));

    if samples.is_empty() && bytes == 0 && upload_bytes == 0 {
        return Err("speed failed".into());
    }
    let geo = exit.unwrap_or((String::new(), String::new(), String::new()));
    speed_touch(report, |p| {
        p.download_bps = download_bps as i64;
        p.upload_bps = upload_bps as i64;
        p.live_bps = 0;
    });
    Ok((ping, jitter, bytes, download_bps, upload_bps, geo))
}

fn run_speed_probe_inner(plan: &SpeedPlan, report: bool) -> Result<Value, String> {
    let vpn_path = if plan.connected {
        match measure_speed(plan, report) {
            Ok(result) => Some(result),
            Err(_) => None,
        }
    } else {
        None
    };

    let direct_plan = SpeedPlan {
        connected: false,
        http_port: plan.http_port,
        socks_port: plan.socks_port,
        http_enabled: plan.http_enabled,
        socks_enabled: plan.socks_enabled,
    };

    let (ping, jitter, bytes, download_bps, upload_bps, (exit_ip, exit_country, country_code), vpn_active) =
        if let Some((ping, jitter, bytes, down, up, geo)) = vpn_path {
            (ping, jitter, bytes, down, up, geo, true)
        } else {
            let (ping, jitter, bytes, down, up, geo) = measure_speed(&direct_plan, report)?;
            (ping, jitter, bytes, down, up, geo, false)
        };

    Ok(json!({
        "tcp_ms": ping,
        "icmp_ms": ping,
        "jitter_ms": jitter,
        "bytes": bytes,
        "download_bps": download_bps,
        "upload_bps": upload_bps,
        "exit_ip": exit_ip,
        "exit_country": exit_country,
        "country_code": country_code,
        "vpn_active": vpn_active
    }))
}

pub fn run_speed_probe(plan: &SpeedPlan) -> Result<Value, String> {
    run_speed_probe_inner(plan, false)
}

fn rate_bps(bytes: u64, elapsed: Duration) -> u64 {
    if bytes == 0 {
        return 0;
    }
    (bytes as f64 / elapsed.as_secs_f64().max(0.05)) as u64
}

fn xray_protocol(protocol: &str) -> bool {
    matches!(protocol, "vless" | "vmess" | "trojan" | "shadowsocks" | "hysteria" | "hysteria2" | "wireguard" | "socks" | "http")
}

fn socks_profile(origin: &Value, port: u16) -> Value {
    json!({"protocol":"socks","address":"127.0.0.1","port": port, "remark": origin["remark"], "username":"", "password":"", "tls":"none", "network":"tcp"})
}

fn seed_geo_files(data_dir: &Path, singbox: &Path) {
    let geo = data_dir.join("geo");
    let _ = fs::create_dir_all(&geo);
    for name in ["geoip.dat", "geosite.dat"] {
        let dest = geo.join(name);
        if dest.exists() {
            continue;
        }
        if let Some(src) = bundled_geo(name, singbox) {
            let _ = fs::copy(src, &dest);
        }
    }
}

fn bundled_geo(name: &str, singbox: &Path) -> Option<PathBuf> {
    let parent = singbox.parent()?;
    let direct = parent.join(name);
    if direct.exists() {
        return Some(direct);
    }
    let resources = parent.parent()?.join("Resources").join(name);
    if resources.exists() {
        return Some(resources);
    }
    None
}

fn xray_cmd(bin: &Path, data_dir: &Path) -> Command {
    let mut cmd = Command::new(bin);
    if let Some(dir) = xray_asset_dir(bin, data_dir) {
        cmd.current_dir(&dir);
        cmd.env("XRAY_LOCATION_ASSET", &dir);
    }
    cmd
}

fn xray_asset_dir(bin: &Path, data_dir: &Path) -> Option<PathBuf> {
    let geo = data_dir.join("geo");
    if geo.join("geoip.dat").exists() || geo.join("geosite.dat").exists() || geo.join("iran.dat").exists() {
        return Some(geo);
    }
    let parent = bin.parent()?;
    if parent.join("geoip.dat").exists() {
        return Some(parent.to_path_buf());
    }
    let resources = parent.parent()?.join("Resources");
    if resources.join("geoip.dat").exists() {
        return Some(resources);
    }
    Some(parent.to_path_buf())
}

fn xray_binary(singbox: &Path) -> Result<PathBuf, String> {
    let path = singbox.parent().unwrap_or(Path::new(".")).join("xray");
    if path.exists() {
        return Ok(path);
    }
    Err("xray core was not found next to sing-box".into())
}

fn process_names() -> Vec<String> {
    let output = Command::new("ps").args(["-axco", "comm"]).output();
    let mut names = Vec::new();
    if let Ok(output) = output {
        for line in String::from_utf8_lossy(&output.stdout).lines() {
            let name = line.trim().trim_matches('"').split(',').next().unwrap_or("").trim();
            if !name.is_empty() && name != "comm" { names.push(name.to_string()); }
        }
    }
    names.sort();
    names.dedup();
    names.truncate(180);
    names
}

fn cloud_newer(cloud: &Path, local: &Path) -> bool {
    let cloud_time = fs::metadata(cloud).and_then(|m| m.modified()).ok();
    let local_time = fs::metadata(local).and_then(|m| m.modified()).ok();
    match (cloud_time, local_time) {
        (Some(cloud), Some(local)) => cloud > local,
        (Some(_), None) => true,
        _ => false,
    }
}

fn demand_action(text: &str, kind: &str, ssid: &str) -> Option<String> {
    for line in text.lines() {
        let parts: Vec<&str> = line.split(',').map(|s| s.trim()).filter(|s| !s.is_empty()).collect();
        if parts.len() < 3 {
            continue;
        }
        let iface_ok = parts[0].eq_ignore_ascii_case("any") || parts[0].eq_ignore_ascii_case(kind);
        let ssid_ok = parts[1] == "*" || parts[1] == ssid;
        if iface_ok && ssid_ok {
            return Some(parts[2].to_ascii_lowercase());
        }
    }
    None
}

fn base64_bytes(data: &str) -> Result<Vec<u8>, String> {
    let mut raw = data.trim().replace('-', "+").replace('_', "/");
    let pad = (4 - raw.len() % 4) % 4;
    raw.push_str(&"=".repeat(pad));
    let alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut map = [255u8; 256];
    for (i, c) in alphabet.iter().enumerate() {
        map[*c as usize] = i as u8;
    }
    let clean: Vec<u8> = raw.bytes().filter(|b| *b != b'=' && !b.is_ascii_whitespace()).collect();
    if clean.len() % 4 == 1 {
        return Err("bad backup".into());
    }
    let mut out = Vec::new();
    let mut i = 0;
    while i < clean.len() {
        let n = (clean.len() - i).min(4);
        let mut buf = [0u8; 4];
        for j in 0..n {
            let v = map[clean[i + j] as usize];
            if v == 255 {
                return Err("bad backup".into());
            }
            buf[j] = v;
        }
        out.push((buf[0] << 2) | (buf[1] >> 4));
        if n > 2 {
            out.push((buf[1] << 4) | (buf[2] >> 2));
        }
        if n > 3 {
            out.push((buf[2] << 6) | buf[3]);
        }
        i += 4;
    }
    Ok(out)
}

fn strip_ansi(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let bytes = text.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == 0x1b && i + 1 < bytes.len() && bytes[i + 1] == b'[' {
            i += 2;
            while i < bytes.len() {
                let c = bytes[i];
                i += 1;
                if (b'@'..=b'~').contains(&c) {
                    break;
                }
            }
            continue;
        }
        out.push(bytes[i] as char);
        i += 1;
    }
    out
}

fn unzip_password(password: &str, bytes: &[u8]) -> Result<Vec<u8>, String> {
    let dir = std::env::temp_dir().join(format!("v2open-zip-{}", now()));
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let zip = dir.join("in.zip");
    fs::write(&zip, bytes).map_err(|e| e.to_string())?;
    let result = Command::new("unzip").args(["-P", password, "-o"]).arg(&zip).arg("-d").arg(&dir).output().map_err(|_| "unzip is not available".to_string())?;
    if !result.status.success() {
        return Err("wrong password or the archive is not a zip".into());
    }
    for entry in fs::read_dir(&dir).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        if entry.path().extension().and_then(|e| e.to_str()) == Some("json") || entry.file_name().to_string_lossy().ends_with(".json") {
            return fs::read(entry.path()).map_err(|e| e.to_string());
        }
    }
    Err("the archive did not contain a library".into())
}

fn port_num(value: &Value) -> u16 {
    value
        .as_u64()
        .or_else(|| value.as_i64().and_then(|n| u64::try_from(n.max(0)).ok()))
        .or_else(|| value.as_str().and_then(|s| s.parse::<u64>().ok()))
        .unwrap_or(0) as u16
}

fn node_data(profile: &Value) -> Value {
    let mut data = profile.get("data").cloned().unwrap_or_else(|| json!({}));
    for key in ["remark", "protocol", "address", "port", "link"] {
        if profile.get(key).is_some() {
            data[key] = profile[key].clone();
        }
    }
    data["id"] = profile["id"].clone();
    data
}

#[cfg(target_os = "macos")]
fn mac_proxy(service: &str, getter: &str) -> Value {
    let out = Command::new("networksetup").arg(format!("-{getter}")).arg(service).output();
    let mut enabled = false;
    let mut server = String::new();
    let mut port = String::new();
    if let Ok(out) = out {
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            let Some((k, v)) = line.split_once(':') else { continue };
            let v = v.trim();
            if k.to_ascii_lowercase().starts_with("enabled") {
                enabled = v.eq_ignore_ascii_case("yes");
            }
            if k.to_ascii_lowercase().starts_with("server") {
                server = v.to_string();
            }
            if k.to_ascii_lowercase().starts_with("port") {
                port = v.to_string();
            }
        }
    }
    json!({"enabled": enabled, "server": server, "port": port})
}

#[cfg(target_os = "macos")]
fn mac_restore(service: &str, setter: &str, state_setter: &str, state: &Value) {
    if state["enabled"].as_bool().unwrap_or(false) && !state["server"].as_str().unwrap_or("").is_empty() {
        let _ = Command::new("networksetup").args([format!("-{setter}").as_str(), service, state["server"].as_str().unwrap_or(""), state["port"].as_str().unwrap_or("")]).status();
        let _ = Command::new("networksetup").args([format!("-{state_setter}").as_str(), service, "on"]).status();
    } else {
        let _ = Command::new("networksetup").args([format!("-{state_setter}").as_str(), service, "off"]).status();
    }
}

fn install_rules(dir: &Path) {
    let _ = fs::create_dir_all(dir);
    let files: &[(&str, &[u8])] = &[
        ("geoip-cn.srs", include_bytes!("../../../assets/rulesets/geoip-cn.srs")),
        ("geoip-ir.srs", include_bytes!("../../../assets/rulesets/geoip-ir.srs")),
        ("geoip-ru.srs", include_bytes!("../../../assets/rulesets/geoip-ru.srs")),
        ("geosite-cn.srs", include_bytes!("../../../assets/rulesets/geosite-cn.srs")),
        ("geosite-google.srs", include_bytes!("../../../assets/rulesets/geosite-google.srs")),
        ("geosite-apple.srs", include_bytes!("../../../assets/rulesets/geosite-apple.srs")),
        ("geosite-category-ir.srs", include_bytes!("../../../assets/rulesets/geosite-category-ir.srs")),
        ("geosite-category-ru.srs", include_bytes!("../../../assets/rulesets/geosite-category-ru.srs")),
        ("geosite-private.srs", include_bytes!("../../../assets/rulesets/geosite-private.srs")),
        ("geosite-category-ads-all.srs", include_bytes!("../../../assets/rulesets/geosite-category-ads-all.srs")),
    ];
    for (name, bytes) in files {
        let path = dir.join(name);
        if !path.exists() {
            let _ = fs::write(path, bytes);
        }
    }
}

pub fn support_dir() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| ".".into())).join("Library/Application Support/V2Open")
}

fn mtu_probe_post(url: &str, payload_bytes: usize, timeout: Duration, via_proxy: bool, http_port: u64) -> bool {
    let body = vec![b'x'; payload_bytes];
    let mut agent = ureq::AgentBuilder::new().timeout(timeout);
    if via_proxy {
        if let Ok(proxy) = ureq::Proxy::new(&format!("http://127.0.0.1:{http_port}")) {
            agent = agent.proxy(proxy);
        }
    }
    let agent = agent.build();
    match agent.post(url).send_bytes(&body) {
        Ok(resp) => resp.status() >= 200 && resp.status() < 500,
        Err(_) => false,
    }
}

pub fn locate_core() -> Option<PathBuf> {
    let mut candidates = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            candidates.push(dir.join("sing-box"));
            let mut walk = dir.to_path_buf();
            for _ in 0..8 {
                candidates.push(walk.join("binaries").join("macos").join("sing-box"));
                if !walk.pop() {
                    break;
                }
            }
        }
    }
    candidates.push(PathBuf::from("binaries").join("macos").join("sing-box"));
    candidates.into_iter().find(|p| p.exists())
}

#[cfg(test)]
mod speed_probe_tests {
    use super::{rate_bps, run_speed_probe, SpeedPlan};
    use std::time::Duration;

    #[test]
    fn speed_plan_allows_direct_mode() {
        let plan = SpeedPlan {
            connected: false,
            http_port: 10807,
            socks_port: 10808,
            http_enabled: true,
            socks_enabled: true,
        };
        assert!(!plan.connected);
    }

    #[test]
    fn rate_uses_bytes_over_time() {
        assert_eq!(rate_bps(1_000_000, Duration::from_secs(1)), 1_000_000);
        assert_eq!(rate_bps(0, Duration::from_secs(1)), 0);
    }
}

#[cfg(test)]
mod ping_measure_tests {
    use super::*;
    use std::net::TcpListener;
    use std::thread;

    #[test]
    fn loopback_tcp_ping_measures_handshake_only() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        thread::spawn(move || {
            let _ = listener.accept();
        });
        let ms = tcp_connect_ms("127.0.0.1", port, Duration::from_secs(2), false).expect("loopback ping");
        assert!(ms >= 1);
        assert!(ms < 100, "loopback handshake was {ms} ms");
    }

    #[test]
    fn dns_time_is_not_counted_as_ping() {
        let started = Instant::now();
        let _ = ("localhost", 1u16).to_socket_addrs();
        let dns_ms = started.elapsed().as_millis();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        thread::spawn(move || {
            let _ = listener.accept();
        });
        let ms = tcp_connect_ms("localhost", port, Duration::from_secs(2), false).expect("localhost ping");
        assert!(ms >= 1);
        if dns_ms > 20 {
            assert!(u128::from(ms) < dns_ms, "ping {ms} included dns {dns_ms}");
        }
        assert!(ms < 100, "localhost handshake was {ms} ms");
    }

    #[test]
    fn remote_tcp_ping_is_not_one_millisecond() {
        let Some(ms) = tcp_connect_ms("8.8.8.8", 443, Duration::from_secs(3), false) else {
            return;
        };
        assert!(ms >= 5, "remote ping {ms}ms is still tun-local");
    }
}
