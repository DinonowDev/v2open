use serde_json::{json, Value};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

pub struct Running {
    pub children: Vec<std::process::Child>,
    pub stops: Vec<Arc<AtomicBool>>,
    pub elevated: Vec<u32>,
}

impl Running {
    fn new() -> Self {
        Self { children: Vec::new(), stops: Vec::new(), elevated: Vec::new() }
    }
}

pub fn adapt_all(profiles: &[Value], singbox: &Path, work: &Path) -> Result<(Vec<Value>, Running), String> {
    let _ = fs::create_dir_all(work);
    let mut out = Vec::new();
    let mut running = Running::new();
    for (index, profile) in profiles.iter().enumerate() {
        match adapt_one(profile, singbox, &work.join(format!("b{index}"))) {
            Ok((node, part)) => {
                out.push(node);
                running.children.extend(part.children);
                running.stops.extend(part.stops);
                running.elevated.extend(part.elevated);
            }
            Err(err) => {
                stop(&mut running);
                return Err(err);
            }
        }
    }
    Ok((out, running))
}

pub fn stop(running: &mut Running) {
    for flag in &running.stops {
        flag.store(true, std::sync::atomic::Ordering::Relaxed);
    }
    for child in &mut running.children {
        let _ = child.kill();
        let _ = child.wait();
    }
    for pid in running.elevated.drain(..) {
        let _ = Command::new("osascript").arg("-e").arg(format!("do shell script \"kill {pid}\" with administrator privileges with prompt \"V2Open needs permission to stop the ping tunnel.\"")).status();
    }
    running.children.clear();
    running.stops.clear();
}

fn adapt_one(profile: &Value, singbox: &Path, work: &Path) -> Result<(Value, Running), String> {
    let protocol = text(profile, "protocol");
    match protocol.as_str() {
        "shadowsocksr" => {
            let (port, stop_flag) = crate::ssr::start(profile)?;
            let mut running = Running::new();
            running.stops.push(stop_flag);
            Ok((socks(profile, port), running))
        }
        "masterdns" => masterdns(profile, singbox, work),
        "dnstt" => dnstt(profile, singbox, work),
        "ping" => ping(profile, singbox, work),
        _ => Ok((profile.clone(), Running::new())),
    }
}

fn masterdns(profile: &Value, singbox: &Path, work: &Path) -> Result<(Value, Running), String> {
    let bin = tool(singbox, "masterdns")?;
    let _ = fs::create_dir_all(work);
    let port = free_port()?;
    let domain = {
        let domain = text(profile, "domain");
        if domain.is_empty() { text(profile, "address") } else { domain }
    };
    if domain.is_empty() {
        return Err("MasterDNS needs a tunnel domain".into());
    }
    let key = text(profile, "key");
    if key.is_empty() {
        return Err("MasterDNS needs the shared key".into());
    }
    let method = text(profile, "encryption_method");
    let method = if method.chars().all(|c| c.is_ascii_digit()) && !method.is_empty() { method } else { "1".into() };
    let cfg = work.join("client.toml");
    let resolvers = work.join("resolvers.txt");
    fs::write(&cfg, format!("DOMAINS = [\"{}\"]\nENCRYPTION_KEY = \"{}\"\nDATA_ENCRYPTION_METHOD = {method}\nPROTOCOL_TYPE = \"SOCKS5\"\nLISTEN_IP = \"127.0.0.1\"\nLISTEN_PORT = {port}\nLOG_LEVEL = \"ERROR\"\n", escape(&domain), escape(&key))).map_err(|e| e.to_string())?;
    let dns = text(profile, "dns_server");
    let resolver_body = if dns.is_empty() { "1.1.1.1\n8.8.8.8\n9.9.9.9\n".to_string() } else { format!("{dns}\n") };
    fs::write(&resolvers, resolver_body).map_err(|e| e.to_string())?;
    let log = File::create(work.join("masterdns.log")).map_err(|e| e.to_string())?;
    let err = log.try_clone().map_err(|e| e.to_string())?;
    let mut child = Command::new(bin)
        .arg("-config").arg(&cfg)
        .arg("-resolvers").arg(&resolvers)
        .arg("-listen-ip").arg("127.0.0.1")
        .arg("-listen-port").arg(port.to_string())
        .arg("-d").arg(&domain)
        .arg("-k").arg(&key)
        .arg("-data-encryption-method").arg(&method)
        .arg("-protocol-type").arg("SOCKS5")
        .stdout(Stdio::from(log))
        .stderr(Stdio::from(err))
        .spawn()
        .map_err(|e| e.to_string())?;
    wait_port(port, &mut child)?;
    let mut running = Running::new();
    running.children.push(child);
    Ok((socks(profile, port), running))
}

fn dnstt(profile: &Value, singbox: &Path, work: &Path) -> Result<(Value, Running), String> {
    let bin = tool(singbox, "dnstt-client")?;
    let _ = fs::create_dir_all(work);
    let port = free_port()?;
    let domain = {
        let domain = text(profile, "domain");
        if domain.is_empty() { text(profile, "address") } else { domain }
    };
    let pubkey = pubkey_hex(&text(profile, "pubkey"))?;
    let dns = text(profile, "dns_server");
    let log = File::create(work.join("dnstt.log")).map_err(|e| e.to_string())?;
    let err = log.try_clone().map_err(|e| e.to_string())?;
    let mut cmd = Command::new(bin);
    if dns.starts_with("https://") {
        cmd.arg("-doh").arg(&dns);
    } else if let Some(rest) = dns.strip_prefix("tls://") {
        cmd.arg("-dot").arg(rest);
    } else if !dns.is_empty() {
        let addr = if dns.contains(':') { dns } else { format!("{dns}:53") };
        cmd.arg("-udp").arg(addr);
    } else {
        cmd.arg("-doh").arg("https://1.1.1.1/dns-query");
    }
    cmd.arg("-pubkey").arg(pubkey).arg(&domain).arg(format!("127.0.0.1:{port}"));
    let mut child = cmd.stdout(Stdio::from(log)).stderr(Stdio::from(err)).spawn().map_err(|e| e.to_string())?;
    wait_port(port, &mut child)?;
    let mut running = Running::new();
    running.children.push(child);
    Ok((socks(profile, port), running))
}

fn ping(profile: &Value, singbox: &Path, work: &Path) -> Result<(Value, Running), String> {
    let bin = tool(singbox, "pingtunnel")?;
    let _ = fs::create_dir_all(work);
    let port = free_port()?;
    let host = text(profile, "address");
    if host.is_empty() {
        return Err("ping tunnel needs a server address".into());
    }
    let password = {
        let key = text(profile, "key");
        if key.is_empty() { text(profile, "password") } else { key }
    };
    if password.len() < 8 {
        return Err("ping tunnel password must be at least 8 characters".into());
    }
    let log = work.join("ping.log");
    let pidfile = work.join("ping.pid");
    let script = work.join("ping.sh");
    let bind = format!("127.0.0.1:{port}");
    let body = crate::platform::bash_detach_script(
        &bin,
        &["-type", "client", "-l", &bind, "-s", &host, "-socks5", "-password", &password],
        &log,
        &pidfile,
    );
    fs::write(&script, body).map_err(|e| e.to_string())?;
    let _ = Command::new("chmod").arg("+x").arg(&script).status();
    let osa = crate::platform::osa_run_bash_script(&script, "V2Open needs permission for the ping tunnel.");
    let result = Command::new("osascript").arg("-e").arg(osa).output().map_err(|e| e.to_string())?;
    if !result.status.success() {
        let err = String::from_utf8_lossy(&result.stderr);
        return Err(if err.trim().is_empty() { "ping tunnel permission was denied".into() } else { err.trim().to_string() });
    }
    thread::sleep(Duration::from_millis(400));
    let pid = fs::read_to_string(&pidfile).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0);
    if pid == 0 {
        return Err("ping tunnel did not start".into());
    }
    let mut running = Running::new();
    running.elevated.push(pid);
    Ok((socks(profile, port), running))
}

fn socks(profile: &Value, port: u16) -> Value {
    json!({
        "protocol": "socks",
        "address": "127.0.0.1",
        "port": port,
        "remark": text(profile, "remark"),
        "username": "",
        "password": "",
        "tls": "none",
        "network": "tcp"
    })
}

fn tool(singbox: &Path, name: &str) -> Result<PathBuf, String> {
    let dir = singbox.parent().unwrap_or_else(|| Path::new("."));
    let path = dir.join(name);
    if path.exists() {
        return Ok(path);
    }
    Err(format!("{name} was not found next to the core"))
}

fn free_port() -> Result<u16, String> {
    let listener = TcpListener::bind("127.0.0.1:0").map_err(|e| e.to_string())?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    drop(listener);
    Ok(port)
}

fn wait_port(port: u16, child: &mut std::process::Child) -> Result<(), String> {
    for _ in 0..40 {
        if let Ok(Some(status)) = child.try_wait() {
            return Err(format!("helper exited ({status}) before it started listening"));
        }
        if TcpStream::connect_timeout(&format!("127.0.0.1:{port}").parse().unwrap(), Duration::from_millis(150)).is_ok() {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(150));
    }
    if let Ok(Some(status)) = child.try_wait() {
        return Err(format!("helper exited ({status})"));
    }
    Ok(())
}

fn pubkey_hex(raw: &str) -> Result<String, String> {
    let compact: String = raw.chars().filter(|c| !c.is_whitespace()).collect();
    if compact.len() == 64 && compact.chars().all(|c| c.is_ascii_hexdigit()) {
        return Ok(compact.to_ascii_lowercase());
    }
    if let Some(bytes) = b64(&compact) {
        if bytes.len() == 32 {
            return Ok(bytes.iter().map(|b| format!("{b:02x}")).collect());
        }
    }
    Err("DNSTT public key must be 32 bytes, as 64 hex digits or base64".into())
}

fn b64(data: &str) -> Option<Vec<u8>> {
    let mut raw = data.replace('-', "+").replace('_', "/");
    let pad = (4 - raw.len() % 4) % 4;
    raw.push_str(&"=".repeat(pad));
    let alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut map = [255u8; 256];
    for (i, c) in alphabet.iter().enumerate() {
        map[*c as usize] = i as u8;
    }
    let clean: Vec<u8> = raw.bytes().filter(|b| *b != b'=').collect();
    if clean.len() % 4 == 1 {
        return None;
    }
    let mut out = Vec::new();
    let mut i = 0;
    while i < clean.len() {
        let n = (clean.len() - i).min(4);
        let mut buf = [0u8; 4];
        for j in 0..n {
            let v = map[clean[i + j] as usize];
            if v == 255 {
                return None;
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
    Some(out)
}

fn escape(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn text(v: &Value, key: &str) -> String {
    v.get(key).and_then(|x| x.as_str()).unwrap_or("").to_string()
}

pub fn race(ports: &[u16]) -> Result<(u16, Arc<AtomicBool>), String> {
    if ports.len() < 2 {
        return Err("race needs two paths".into());
    }
    let listener = TcpListener::bind("127.0.0.1:0").map_err(|e| e.to_string())?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    listener.set_nonblocking(true).map_err(|e| e.to_string())?;
    let stop = Arc::new(AtomicBool::new(false));
    let flag = stop.clone();
    let ports = ports.to_vec();
    thread::spawn(move || race_loop(listener, flag, ports));
    Ok((port, stop))
}

fn race_loop(listener: TcpListener, stop: Arc<AtomicBool>, ports: Vec<u16>) {
    while !stop.load(Ordering::Relaxed) {
        match listener.accept() {
            Ok((sock, _)) => {
                let _ = sock.set_nonblocking(false);
                let ports = ports.clone();
                thread::spawn(move || {
                    let _ = race_one(sock, &ports);
                });
            }
            Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => thread::sleep(Duration::from_millis(30)),
            Err(_) => break,
        }
    }
}

fn race_one(mut client: TcpStream, ports: &[u16]) -> std::io::Result<()> {
    let _ = client.set_read_timeout(Some(Duration::from_secs(20)));
    let request = read_socks_request(&mut client)?;
    let winner = race_dial(ports, &request).ok_or_else(|| std::io::Error::new(std::io::ErrorKind::ConnectionRefused, "both paths failed"))?;
    client.write_all(&[5, 0, 0, 1, 0, 0, 0, 0, 0, 0])?;
    let _ = client.set_read_timeout(None);
    let mut remote = winner;
    let _ = remote.set_read_timeout(None);
    let mut up_client = client.try_clone()?;
    let mut up_remote = remote.try_clone()?;
    thread::spawn(move || {
        let _ = std::io::copy(&mut up_client, &mut up_remote);
    });
    let _ = std::io::copy(&mut remote, &mut client);
    Ok(())
}

fn read_socks_request(stream: &mut TcpStream) -> std::io::Result<Vec<u8>> {
    let mut head = [0u8; 2];
    stream.read_exact(&mut head)?;
    if head[0] != 5 { return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "not socks5")); }
    let mut methods = vec![0u8; head[1] as usize];
    stream.read_exact(&mut methods)?;
    stream.write_all(&[5, 0])?;
    let mut req = vec![0u8; 4];
    stream.read_exact(&mut req)?;
    let more = match req[3] {
        1 => 6,
        4 => 18,
        3 => {
            let mut len = [0u8; 1];
            stream.read_exact(&mut len)?;
            req.push(len[0]);
            len[0] as usize + 2
        }
        _ => return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "bad address")),
    };
    let mut tail = vec![0u8; more];
    stream.read_exact(&mut tail)?;
    req.extend(tail);
    Ok(req)
}

fn race_dial(ports: &[u16], request: &[u8]) -> Option<TcpStream> {
    let (tx, rx) = mpsc::channel();
    for port in ports {
        let tx = tx.clone();
        let request = request.to_vec();
        let port = *port;
        thread::spawn(move || {
            let _ = tx.send(dial_socks(port, &request).ok());
        });
    }
    drop(tx);
    let mut found = None;
    while let Ok(item) = rx.recv() {
        if item.is_some() {
            found = item;
            break;
        }
    }
    found
}

fn dial_socks(port: u16, request: &[u8]) -> std::io::Result<TcpStream> {
    let address: std::net::SocketAddr = format!("127.0.0.1:{port}").parse().map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidInput, e))?;
    let mut stream = TcpStream::connect_timeout(&address, Duration::from_secs(4))?;
    let _ = stream.set_nodelay(true);
    let _ = stream.set_read_timeout(Some(Duration::from_secs(6)));
    stream.write_all(&[5, 1, 0])?;
    let mut greet = [0u8; 2];
    stream.read_exact(&mut greet)?;
    if greet[1] != 0 { return Err(std::io::Error::new(std::io::ErrorKind::PermissionDenied, "socks auth")); }
    stream.write_all(request)?;
    let mut head = [0u8; 4];
    stream.read_exact(&mut head)?;
    if head[1] != 0 { return Err(std::io::Error::new(std::io::ErrorKind::ConnectionRefused, "socks failed")); }
    let more = match head[3] {
        1 => 6,
        4 => 18,
        3 => {
            let mut len = [0u8; 1];
            stream.read_exact(&mut len)?;
            len[0] as usize + 2
        }
        _ => 0,
    };
    let mut tail = vec![0u8; more];
    if more > 0 { stream.read_exact(&mut tail)?; }
    Ok(stream)
}
