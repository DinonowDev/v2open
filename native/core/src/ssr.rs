use aes::cipher::{BlockEncrypt, KeyInit, KeyIvInit, StreamCipher};
use hmac::{Hmac, Mac};
use md5::Md5;
use sha1::Sha1;
use cfb_mode::{BufDecryptor, BufEncryptor};
use ctr::Ctr128BE;
use md5::Digest;
use serde_json::Value;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

pub fn start(profile: &Value) -> Result<(u16, Arc<AtomicBool>), String> {
    let method = text(profile, "method");
    let protocol = text(profile, "ssr_protocol");
    let obfs = text(profile, "obfs");
    if !protocol.is_empty() && !matches!(protocol.as_str(), "origin" | "auth_sha1_v4" | "auth_aes128_md5" | "auth_aes128_sha1" | "auth_chain_a" | "auth_chain_b" | "auth_chain_c" | "auth_chain_d" | "auth_chain_e" | "auth_chain_f") {
        return Err(format!("SSR protocol {protocol} cannot run on this core"));
    }
    if !(obfs.is_empty() || matches!(obfs.as_str(), "plain" | "http_simple" | "http_post" | "tls1.2_ticket_auth" | "tls1.2_ticket_fastauth")) {
        return Err(format!("SSR obfuscation {obfs} cannot run on this core"));
    }
    let _ = method_info(&method)?;
    let stop = Arc::new(AtomicBool::new(false));
    let listener = TcpListener::bind("127.0.0.1:0").map_err(|e| e.to_string())?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    listener.set_nonblocking(true).map_err(|e| e.to_string())?;
    let flag = stop.clone();
    let profile = profile.clone();
    thread::spawn(move || accept_loop(listener, flag, profile));
    Ok((port, stop))
}

fn accept_loop(listener: TcpListener, stop: Arc<AtomicBool>, profile: Value) {
    while !stop.load(Ordering::Relaxed) {
        match listener.accept() {
            Ok((sock, _)) => {
                let _ = sock.set_nonblocking(false);
                let profile = profile.clone();
                thread::spawn(move || {
                    let _ = handle(sock, &profile);
                });
            }
            Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => thread::sleep(Duration::from_millis(40)),
            Err(_) => break,
        }
    }
}

fn handle(mut client: TcpStream, profile: &Value) -> std::io::Result<()> {
    let _ = client.set_read_timeout(Some(Duration::from_secs(30)));
    let target = socks5(&mut client)?;
    let host = text(profile, "address");
    let port = profile["port"].as_u64().unwrap_or(0) as u16;
    let mut remote = TcpStream::connect_timeout(&format!("{host}:{port}").parse().map_err(|e: std::net::AddrParseError| std::io::Error::new(std::io::ErrorKind::InvalidInput, e))?, Duration::from_secs(15))?;
    let _ = remote.set_nodelay(true);
    let _ = client.set_nodelay(true);
    let method = text(profile, "method");
    let info = method_info(&method).map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidInput, e))?;
    let key = derive_key(text(profile, "password").as_bytes(), info.key_len);
    let iv = random(info.iv_len);
    let mut enc = open_cipher(&method, &key, &iv, false).map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidInput, e))?;
    let proto_name = text(profile, "ssr_protocol");
    let proto_param = text(profile, "protocol_param");
    let utc = unix_time();
    let mut send_lane = Lane::new(&proto_name, &key, &iv, &proto_param, utc);
    let mut header = send_lane.pre_encrypt(&target);
    enc.apply(&mut header);
    let mut first = iv.clone();
    first.extend(header);
    let obfs = text(profile, "obfs");
    let obfs_host = {
        let host = text(profile, "host");
        if host.is_empty() { text(profile, "address") } else { host }
    };
    let mut tls = TlsObfs::new(&obfs, &obfs_host, &key);
    if obfs == "http_simple" || obfs == "http_post" {
        first = http_wrap(&first, &obfs_host, obfs == "http_post");
    } else if tls.active {
        first = tls.client_encode(&first);
    }
    remote.write_all(&first)?;
    if tls.active && tls.status == 1 {
        let mut shake = [0u8; 4096];
        let n = remote.read(&mut shake)?;
        tls.client_decode(&shake[..n])?;
        let second = tls.client_encode(&[]);
        if !second.is_empty() { remote.write_all(&second)?; }
    }
    let mut dec_iv = if obfs == "http_simple" || obfs == "http_post" {
        read_after_http(&mut remote, info.iv_len)?
    } else if tls.active {
        let mut raw = Vec::new();
        let mut chunk = [0u8; 4096];
        while raw.len() < info.iv_len {
            let n = remote.read(&mut chunk)?;
            if n == 0 { break; }
            raw.extend(tls.client_decode(&chunk[..n])?);
        }
        raw
    } else {
        read_exact(&mut remote, info.iv_len)?
    };
    if dec_iv.len() < info.iv_len {
        return Err(std::io::Error::new(std::io::ErrorKind::UnexpectedEof, "short iv"));
    }
    let extra = dec_iv.split_off(info.iv_len);
    let mut dec = open_cipher(&method, &key, &dec_iv, true).map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidInput, e))?;
    let mut recv_lane = Lane::new(&proto_name, &key, &iv, &proto_param, utc);
    recv_lane.sent_header = true;
    if !extra.is_empty() {
        let mut extra = extra;
        dec.apply(&mut extra);
        let plain = recv_lane.post_decrypt(&extra);
        if !plain.is_empty() { client.write_all(&plain)?; }
    }
    let mut client_read = client.try_clone()?;
    let mut remote_write = remote.try_clone()?;
    let mut tls_up = tls.clone();
    thread::spawn(move || {
        let mut buf = [0u8; 16384];
        loop {
            let n = match client_read.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => n,
            };
            let mut framed = send_lane.pre_encrypt(&buf[..n]);
            enc.apply(&mut framed);
            let wire = if tls_up.active { tls_up.client_encode(&framed) } else { framed };
            if wire.is_empty() { continue; }
            if remote_write.write_all(&wire).is_err() { break; }
        }
    });
    let mut buf = [0u8; 16384];
    loop {
        let n = match remote.read(&mut buf) {
            Ok(0) | Err(_) => break,
            Ok(n) => n,
        };
        let decoded = if tls.active { tls.client_decode(&buf[..n]).unwrap_or_default() } else { buf[..n].to_vec() };
        if decoded.is_empty() { continue; }
        let mut decoded = decoded;
        dec.apply(&mut decoded);
        let plain = recv_lane.post_decrypt(&decoded);
        if !plain.is_empty() && client.write_all(&plain).is_err() { break; }
    }
    Ok(())
}

fn socks5(client: &mut TcpStream) -> std::io::Result<Vec<u8>> {
    let hello = read_exact(client, 2)?;
    if hello[0] != 5 {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "not socks5"));
    }
    let _methods = read_exact(client, hello[1] as usize)?;
    client.write_all(&[5, 0])?;
    let head = read_exact(client, 4)?;
    if head[1] != 1 {
        client.write_all(&[5, 7, 0, 1, 0, 0, 0, 0, 0, 0])?;
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "only connect"));
    }
    let addr = match head[3] {
        1 => read_exact(client, 4)?,
        4 => read_exact(client, 16)?,
        3 => {
            let len = read_exact(client, 1)?[0] as usize;
            read_exact(client, len)?
        }
        _ => return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "bad address")),
    };
    let port = read_exact(client, 2)?;
    client.write_all(&[5, 0, 0, 1, 0, 0, 0, 0, 0, 0])?;
    let mut out = Vec::new();
    match head[3] {
        1 => {
            out.push(1);
            out.extend(addr);
        }
        4 => {
            out.push(4);
            out.extend(addr);
        }
        _ => {
            out.push(3);
            out.push(addr.len() as u8);
            out.extend(addr);
        }
    }
    out.extend(port);
    Ok(out)
}

struct Method {
    key_len: usize,
    iv_len: usize,
}

fn method_info(method: &str) -> Result<Method, String> {
    let (key_len, iv_len) = match method {
        "aes-128-cfb" | "aes-128-ctr" => (16, 16),
        "aes-192-cfb" => (24, 16),
        "aes-256-cfb" | "aes-256-ctr" => (32, 16),
        "chacha20-ietf" => (32, 12),
        "rc4-md5" => (16, 16),
        "none" => (0, 0),
        other => return Err(format!("SSR cipher {other} is not supported")),
    };
    Ok(Method { key_len, iv_len })
}

enum Crypt {
    Aes128CfbE(BufEncryptor<aes::Aes128>),
    Aes192CfbE(BufEncryptor<aes::Aes192>),
    Aes256CfbE(BufEncryptor<aes::Aes256>),
    Aes128CfbD(BufDecryptor<aes::Aes128>),
    Aes192CfbD(BufDecryptor<aes::Aes192>),
    Aes256CfbD(BufDecryptor<aes::Aes256>),
    Aes128Ctr(Ctr128BE<aes::Aes128>),
    Aes256Ctr(Ctr128BE<aes::Aes256>),
    ChaCha(chacha20::ChaCha20),
    Rc4(Rc4),
    None,
}

impl Crypt {
    fn apply(&mut self, data: &mut [u8]) {
        match self {
            Crypt::Aes128CfbE(c) => c.encrypt(data),
            Crypt::Aes192CfbE(c) => c.encrypt(data),
            Crypt::Aes256CfbE(c) => c.encrypt(data),
            Crypt::Aes128CfbD(c) => c.decrypt(data),
            Crypt::Aes192CfbD(c) => c.decrypt(data),
            Crypt::Aes256CfbD(c) => c.decrypt(data),
            Crypt::Aes128Ctr(c) => c.apply_keystream(data),
            Crypt::Aes256Ctr(c) => c.apply_keystream(data),
            Crypt::ChaCha(c) => c.apply_keystream(data),
            Crypt::Rc4(c) => c.apply(data),
            Crypt::None => {}
        }
    }
}

fn open_cipher(method: &str, key: &[u8], iv: &[u8], decrypt: bool) -> Result<Crypt, String> {
    if method == "none" {
        return Ok(Crypt::None);
    }
    if method == "rc4-md5" {
        let mut hasher = Md5::new();
        hasher.update(key);
        hasher.update(iv);
        return Ok(Crypt::Rc4(Rc4::new(&hasher.finalize())));
    }
    let err = |e: cipher::InvalidLength| e.to_string();
    match (method, decrypt) {
        ("aes-128-cfb", false) => Ok(Crypt::Aes128CfbE(BufEncryptor::<aes::Aes128>::new_from_slices(key, iv).map_err(err)?)),
        ("aes-192-cfb", false) => Ok(Crypt::Aes192CfbE(BufEncryptor::<aes::Aes192>::new_from_slices(key, iv).map_err(err)?)),
        ("aes-256-cfb", false) => Ok(Crypt::Aes256CfbE(BufEncryptor::<aes::Aes256>::new_from_slices(key, iv).map_err(err)?)),
        ("aes-128-cfb", true) => Ok(Crypt::Aes128CfbD(BufDecryptor::<aes::Aes128>::new_from_slices(key, iv).map_err(err)?)),
        ("aes-192-cfb", true) => Ok(Crypt::Aes192CfbD(BufDecryptor::<aes::Aes192>::new_from_slices(key, iv).map_err(err)?)),
        ("aes-256-cfb", true) => Ok(Crypt::Aes256CfbD(BufDecryptor::<aes::Aes256>::new_from_slices(key, iv).map_err(err)?)),
        ("aes-128-ctr", _) => Ok(Crypt::Aes128Ctr(Ctr128BE::<aes::Aes128>::new_from_slices(key, iv).map_err(err)?)),
        ("aes-256-ctr", _) => Ok(Crypt::Aes256Ctr(Ctr128BE::<aes::Aes256>::new_from_slices(key, iv).map_err(err)?)),
        ("chacha20-ietf", _) => Ok(Crypt::ChaCha(chacha20::ChaCha20::new_from_slices(key, iv).map_err(err)?)),
        other => Err(format!("SSR cipher {} is not supported", other.0)),
    }
}

fn derive_key(password: &[u8], key_len: usize) -> Vec<u8> {
    if key_len == 0 {
        return Vec::new();
    }
    let mut out = Vec::new();
    let mut block = Vec::new();
    while out.len() < key_len {
        let mut hasher = Md5::new();
        hasher.update(&block);
        hasher.update(password);
        block = hasher.finalize().to_vec();
        out.extend_from_slice(&block);
    }
    out.truncate(key_len);
    out
}

fn http_wrap(payload: &[u8], host: &str, post: bool) -> Vec<u8> {
    if post {
        format!("POST / HTTP/1.1\r\nHost: {host}\r\nUser-Agent: Mozilla/5.0\r\nContent-Length: {}\r\nConnection: keep-alive\r\n\r\n", payload.len()).into_bytes().into_iter().chain(payload.iter().copied()).collect()
    } else {
        let path = b64(payload);
        format!("GET /{path} HTTP/1.1\r\nHost: {host}\r\nUser-Agent: Mozilla/5.0\r\nAccept: */*\r\nConnection: keep-alive\r\n\r\n").into_bytes()
    }
}

fn read_after_http(sock: &mut TcpStream, iv_len: usize) -> std::io::Result<Vec<u8>> {
    let mut collected = Vec::new();
    let mut buf = [0u8; 1];
    let mut seen = 0u8;
    loop {
        if sock.read(&mut buf)? == 0 {
            break;
        }
        collected.push(buf[0]);
        seen = match (seen, buf[0]) {
            (0 | 2, b'\r') => seen + 1,
            (1 | 3, b'\n') => seen + 1,
            _ => 0,
        };
        if seen == 4 || collected.len() > 8192 {
            break;
        }
    }
    let mut rest = read_exact(sock, iv_len)?;
    if let Some(pos) = collected.windows(4).position(|w| w == b"\r\n\r\n") {
        rest.splice(0..0, collected[pos + 4..].iter().copied());
    }
    Ok(rest)
}

fn read_exact(sock: &mut TcpStream, n: usize) -> std::io::Result<Vec<u8>> {
    let mut buf = vec![0u8; n];
    sock.read_exact(&mut buf)?;
    Ok(buf)
}

fn random(n: usize) -> Vec<u8> {
    let mut buf = vec![0u8; n];
    let _ = getrandom::getrandom(&mut buf);
    buf
}

fn b64(data: &[u8]) -> String {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::new();
    for chunk in data.chunks(3) {
        let b0 = chunk[0];
        let b1 = *chunk.get(1).unwrap_or(&0);
        let b2 = *chunk.get(2).unwrap_or(&0);
        out.push(T[(b0 >> 2) as usize] as char);
        out.push(T[(((b0 & 3) << 4) | (b1 >> 4)) as usize] as char);
        if chunk.len() > 1 {
            out.push(T[(((b1 & 15) << 2) | (b2 >> 6)) as usize] as char);
        }
        if chunk.len() > 2 {
            out.push(T[(b2 & 63) as usize] as char);
        }
    }
    out
}

fn text(v: &Value, key: &str) -> String {
    v.get(key).and_then(|x| x.as_str()).unwrap_or("").to_string()
}

#[derive(Clone, Copy, Default)]
struct XorShift { v0: u64, v1: u64 }

impl XorShift {
    fn next(&mut self) -> u64 {
        let mut x = self.v0;
        let y = self.v1;
        self.v0 = y;
        let mask = (1u64 << 41) - 1;
        x ^= (x & mask) << 23;
        x ^= y ^ (x >> 17) ^ (y >> 26);
        self.v1 = x;
        x.wrapping_add(y)
    }
    fn init_len(&mut self, hash: &[u8], length: usize) {
        let mut head = (length as u16).to_le_bytes().to_vec();
        if hash.len() >= 8 { head.extend_from_slice(&hash[2..8]); }
        head.resize(8, 0);
        let mut tail = if hash.len() >= 16 { hash[8..16].to_vec() } else { vec![0; 8] };
        tail.resize(8, 0);
        self.v0 = u64::from_le_bytes(head.try_into().unwrap());
        self.v1 = u64::from_le_bytes(tail.try_into().unwrap());
        for _ in 0..4 { self.next(); }
    }
    fn init_bin(&mut self, bin: &[u8]) {
        let mut packed = [0u8; 16];
        let n = bin.len().min(16);
        packed[..n].copy_from_slice(&bin[..n]);
        self.v0 = u64::from_le_bytes(packed[..8].try_into().unwrap());
        self.v1 = u64::from_le_bytes(packed[8..16].try_into().unwrap());
    }
}

fn mix_sized(variant: u8, overhead: usize, sizes: &[usize], sizes2: &[usize], size: usize, buf: &[u8], hash: &[u8], random: &mut XorShift) -> Vec<u8> {
    let rand_len = chain_pad(variant, overhead, sizes, sizes2, size, hash, random);
    let noise = random_bytes(rand_len);
    if size == 0 || rand_len == 0 { return if size == 0 { noise } else { buf.to_vec() }; }
    let start = ((random.next() % 8589934609) as usize) % rand_len;
    let mut out = noise[..start].to_vec();
    out.extend_from_slice(buf);
    out.extend_from_slice(&noise[start..]);
    out
}

fn chain_pad(variant: u8, overhead: usize, sizes: &[usize], sizes2: &[usize], buf_size: usize, hash: &[u8], random: &mut XorShift) -> usize {
    match variant {
        1 => pad_b(overhead, sizes, sizes2, buf_size, hash, random),
        2 => pad_c(overhead, sizes, buf_size, hash, random),
        3 => pad_d(overhead, sizes, buf_size, hash, random),
        4 | 5 => pad_e(overhead, sizes, buf_size, hash, random),
        _ => {
            if buf_size > 1440 { return 0; }
            random.init_len(hash, buf_size);
            pad_tail(buf_size, random)
        }
    }
}

fn pad_tail(buf_size: usize, random: &mut XorShift) -> usize {
    let n = random.next();
    (if buf_size > 1300 { n % 31 } else if buf_size > 900 { n % 127 } else if buf_size > 400 { n % 521 } else { n % 1021 }) as usize
}

fn pad_b(overhead: usize, sizes: &[usize], sizes2: &[usize], buf_size: usize, hash: &[u8], random: &mut XorShift) -> usize {
    if buf_size >= 1440 { return 0; }
    random.init_len(hash, buf_size);
    if sizes.is_empty() { return pad_tail(buf_size, random); }
    let other = buf_size + overhead;
    let pos = bisect_left(sizes, other);
    let final_pos = pos + (random.next() % sizes.len() as u64) as usize;
    if final_pos < sizes.len() { return sizes[final_pos].saturating_sub(other); }
    if sizes2.is_empty() { return pad_tail(buf_size, random); }
    let pos2 = bisect_left(sizes2, other);
    let final2 = pos2 + (random.next() % sizes2.len() as u64) as usize;
    if final2 < sizes2.len() { return sizes2[final2].saturating_sub(other); }
    if sizes2.len() > 1 && final2 < pos2 + sizes2.len() - 1 { return 0; }
    pad_tail(buf_size, random)
}

fn pad_c(overhead: usize, sizes: &[usize], buf_size: usize, hash: &[u8], random: &mut XorShift) -> usize {
    let other = buf_size + overhead;
    random.init_len(hash, buf_size);
    let last = sizes.last().copied().unwrap_or(0);
    if sizes.is_empty() || other >= last {
        if other >= 1440 { return 0; }
        return pad_tail(other, random);
    }
    let pos = bisect_left(sizes, other);
    let room = sizes.len().saturating_sub(pos);
    if room == 0 { return 0; }
    let final_pos = pos + (random.next() % room as u64) as usize;
    sizes[final_pos].saturating_sub(other)
}

fn pad_d(overhead: usize, sizes: &[usize], buf_size: usize, hash: &[u8], random: &mut XorShift) -> usize {
    let other = buf_size + overhead;
    let last = sizes.last().copied().unwrap_or(0);
    if sizes.is_empty() || other >= last { return 0; }
    random.init_len(hash, buf_size);
    let pos = bisect_left(sizes, other);
    let room = sizes.len().saturating_sub(pos);
    if room == 0 { return 0; }
    let final_pos = pos + (random.next() % room as u64) as usize;
    sizes[final_pos].saturating_sub(other)
}

fn pad_e(overhead: usize, sizes: &[usize], buf_size: usize, hash: &[u8], random: &mut XorShift) -> usize {
    random.init_len(hash, buf_size);
    let other = buf_size + overhead;
    let last = sizes.last().copied().unwrap_or(0);
    if sizes.is_empty() || other >= last { return 0; }
    let pos = bisect_left(sizes, other);
    sizes[pos].saturating_sub(other)
}

fn bisect_left(list: &[usize], value: usize) -> usize {
    list.partition_point(|item| *item < value)
}

fn size_draw(random: &mut XorShift) -> usize {
    (random.next() % 2340 % 2040 % 1440) as usize
}

fn init_list_b(key: &[u8]) -> (Vec<usize>, Vec<usize>) {
    let mut random = XorShift::default();
    random.init_bin(key);
    let n = (random.next() % 8 + 4) as usize;
    let mut first: Vec<usize> = (0..n).map(|_| size_draw(&mut random)).collect();
    first.sort_unstable();
    let n2 = (random.next() % 16 + 8) as usize;
    let mut second: Vec<usize> = (0..n2).map(|_| size_draw(&mut random)).collect();
    second.sort_unstable();
    (first, second)
}

fn init_list_c(key: &[u8]) -> Vec<usize> {
    let mut random = XorShift::default();
    random.init_bin(key);
    let n = (random.next() % 24 + 12) as usize;
    let mut list: Vec<usize> = (0..n).map(|_| size_draw(&mut random)).collect();
    list.sort_unstable();
    list
}

fn init_list_d(key: &[u8]) -> Vec<usize> {
    let mut random = XorShift::default();
    random.init_bin(key);
    let n = (random.next() % 24 + 12) as usize;
    let mut list: Vec<usize> = (0..n).map(|_| size_draw(&mut random)).collect();
    list.sort_unstable();
    let old = list.len();
    patch_sizes(&mut random, &mut list);
    if old != list.len() { list.sort_unstable(); }
    list
}

fn patch_sizes(random: &mut XorShift, list: &mut Vec<usize>) {
    if list.last().copied().unwrap_or(0) < 1300 && list.len() < 64 {
        list.push(size_draw(random));
        patch_sizes(random, list);
    }
}

fn init_list_f(key: &[u8], utc: u32, interval: u64) -> Vec<usize> {
    let stamp = utc as u64 / interval.max(1);
    let mut mixed = key.to_vec();
    for i in 0..8.min(mixed.len()) {
        mixed[i] ^= ((stamp >> (8 * (7 - i))) & 0xFF) as u8;
    }
    init_list_d(&mixed)
}

fn random_bytes(n: usize) -> Vec<u8> { random(n) }

fn unix_time() -> u32 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as u32).unwrap_or(0)
}

struct Rc4 {
    s: [u8; 256],
    i: u8,
    j: u8,
}

impl Rc4 {
    fn new(key: &[u8]) -> Self {
        let mut s = [0u8; 256];
        for (i, item) in s.iter_mut().enumerate() {
            *item = i as u8;
        }
        let mut j = 0u8;
        for i in 0..256 {
            j = j.wrapping_add(s[i]).wrapping_add(key[i % key.len()]);
            s.swap(i, j as usize);
        }
        Self { s, i: 0, j: 0 }
    }
    fn apply(&mut self, data: &mut [u8]) {
        for byte in data {
            self.i = self.i.wrapping_add(1);
            self.j = self.j.wrapping_add(self.s[self.i as usize]);
            self.s.swap(self.i as usize, self.j as usize);
            let k = self.s[(self.s[self.i as usize].wrapping_add(self.s[self.j as usize])) as usize];
            *byte ^= k;
        }
    }
}

struct Lane {
    kind: u8,
    variant: u8,
    key: Vec<u8>,
    iv: Vec<u8>,
    salt: Vec<u8>,
    utc: u32,
    overhead: usize,
    sizes: Vec<usize>,
    sizes2: Vec<usize>,
    pack_id: u32,
    recv_id: u32,
    sent_header: bool,
    pending: Vec<u8>,
    chain_rc4: Option<Rc4>,
    last_client: Vec<u8>,
    last_server: Vec<u8>,
    rand_c: XorShift,
    rand_s: XorShift,
}

impl Lane {
    fn new(protocol: &str, key: &[u8], iv: &[u8], param: &str, utc: u32) -> Self {
        let (kind, variant) = match protocol {
            "auth_sha1_v4" => (4, 0),
            "auth_aes128_md5" => (1, 0),
            "auth_aes128_sha1" => (2, 0),
            "auth_chain_a" => (3, 0),
            "auth_chain_b" => (3, 1),
            "auth_chain_c" => (3, 2),
            "auth_chain_d" => (3, 3),
            "auth_chain_e" => (3, 4),
            "auth_chain_f" => (3, 5),
            _ => (0, 0),
        };
        let letter = match variant { 1 => "b", 2 => "c", 3 => "d", 4 => "e", 5 => "f", _ => "a" };
        let interval = param.split('#').nth(1).unwrap_or("").trim().parse::<u64>().unwrap_or(86_400).max(1);
        let (sizes, sizes2) = match variant {
            1 => init_list_b(key),
            2 => (init_list_c(key), Vec::new()),
            3 | 4 => (init_list_d(key), Vec::new()),
            5 => (init_list_f(key, utc, interval), Vec::new()),
            _ => (Vec::new(), Vec::new()),
        };
        Self {
            kind, variant, key: key.to_vec(), iv: iv.to_vec(), salt: format!("auth_chain_{letter}").into_bytes(), utc, overhead: 4,
            sizes, sizes2, pack_id: 1, recv_id: 1, sent_header: false, pending: Vec::new(), chain_rc4: None,
            last_client: Vec::new(), last_server: Vec::new(), rand_c: XorShift::default(), rand_s: XorShift::default(),
        }
    }
    fn pre_encrypt(&mut self, buf: &[u8]) -> Vec<u8> {
        if self.kind == 4 { return self.sha1v4_pre(buf); }
        if self.kind == 3 { return self.chain_pre(buf); }
        if self.kind == 0 { return buf.to_vec(); }
        let mut out = Vec::new();
        let mut rest = buf;
        if !self.sent_header {
            let take = rest.len().min(rest.len());
            out.extend(self.pack_auth(&rest[..take]));
            rest = &rest[take..];
            self.sent_header = true;
            out.extend(self.pack_unit(&rest));
            return out;
        }
        if !rest.is_empty() { out.extend(self.pack_unit(rest)); }
        out
    }
    fn post_decrypt(&mut self, buf: &[u8]) -> Vec<u8> {
        if self.kind == 4 { return self.sha1v4_post(buf); }
        if self.kind == 3 { return self.chain_post(buf); }
        if self.kind == 0 { return buf.to_vec(); }
        self.pending.extend_from_slice(buf);
        let mut plain = Vec::new();
        while self.pending.len() > 4 {
            let mac_key = self.mac_key(self.recv_id);
            let mac = hmac_n(self.kind == 1, &mac_key, &self.pending[..2], 2);
            if mac != self.pending[2..4] { break; }
            let length = u16::from_le_bytes([self.pending[0], self.pending[1]]) as usize;
            if length < 8 || length > self.pending.len() { break; }
            let check = hmac_n(self.kind == 1, &mac_key, &self.pending[..length - 4], 4);
            if check != self.pending[length - 4..length] { break; }
            let pos = if self.pending[4] < 255 { 4 + self.pending[4] as usize } else { 4 + u16::from_le_bytes([self.pending[5], self.pending[6]]) as usize };
            if pos < length - 4 { plain.extend_from_slice(&self.pending[pos..length - 4]); }
            self.pending.drain(..length);
            self.recv_id = self.recv_id.wrapping_add(1);
        }
        plain
    }
    fn pack_unit(&mut self, buf: &[u8]) -> Vec<u8> {
        let rnd = rnd_prefix(buf.len().min(32));
        let mut body = rnd;
        body.extend_from_slice(buf);
        let data_len = (body.len() + 8) as u16;
        let mac_key = self.mac_key(self.pack_id);
        let mut packet = data_len.to_le_bytes().to_vec();
        packet.extend(hmac_n(self.kind == 1, &mac_key, &packet, 2));
        packet.extend(body);
        packet.extend(hmac_n(self.kind == 1, &mac_key, &packet, 4));
        self.pack_id = self.pack_id.wrapping_add(1);
        packet
    }
    fn pack_auth(&self, buf: &[u8]) -> Vec<u8> {
        let rnd_len: u16 = (random(2)[0] as u16) % if buf.len() > 400 { 512 } else { 1024 };
        let mut auth = Vec::new();
        auth.extend((std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as u32).unwrap_or(0)).to_le_bytes());
        auth.extend(random(4));
        auth.extend(1u32.to_le_bytes());
        let total = 7 + 4 + 16 + 4 + buf.len() + rnd_len as usize + 4;
        auth.extend((total as u16).to_le_bytes());
        auth.extend(rnd_len.to_le_bytes());
        let salt: &[u8] = if self.kind == 1 { b"auth_aes128_md5" } else { b"auth_aes128_sha1" };
        let aes_key = auth_aes_key(&self.key, salt);
        let block = aes128_encrypt(&aes_key, &auth[..16]);
        let uid = random(4);
        let mac_key = [self.iv.clone(), self.key.clone()].concat();
        let mut mid = uid.clone();
        mid.extend(block);
        mid.extend(hmac_n(self.kind == 1, &mac_key, &mid, 4));
        let check = random(1);
        let mut head = check.clone();
        head.extend(hmac_n(self.kind == 1, &mac_key, &check, 6));
        let mut packet = head;
        packet.extend(mid);
        packet.extend(random(rnd_len as usize));
        packet.extend_from_slice(buf);
        packet.extend(hmac_n(self.kind == 1, &self.key, &packet, 4));
        packet
    }
    fn chain_pre(&mut self, buf: &[u8]) -> Vec<u8> {
        if !self.sent_header {
            let take = buf.len();
            let packed = self.chain_auth(&buf[..take]);
            self.sent_header = true;
            return packed;
        }
        self.chain_data(buf)
    }
    fn chain_auth(&mut self, buf: &[u8]) -> Vec<u8> {
        let mut header = Vec::new();
        header.extend(self.utc.to_le_bytes());
        header.extend(random(4));
        header.extend(1u32.to_le_bytes());
        header.extend(4u16.to_le_bytes());
        header.extend(0u16.to_le_bytes());
        let mac_key = [self.iv.clone(), self.key.clone()].concat();
        let check = random(4);
        self.last_client = hmac_n(true, &mac_key, &check, 16);
        let mut head = check;
        head.extend(&self.last_client[..8]);
        let uid_raw = u32::from_le_bytes(random(4).try_into().unwrap());
        let mask = u32::from_le_bytes(self.last_client[8..12].try_into().unwrap());
        let uid = (uid_raw ^ mask).to_le_bytes();
        let block = aes128_encrypt(&auth_aes_key(&self.key, &self.salt), &header[..16]);
        let mut mid = uid.to_vec();
        mid.extend(block);
        self.last_server = hmac_n(true, &self.key, &mid, 16);
        mid.extend(&self.last_server[..4]);
        let rc4_password = [b64_std(&self.key).into_bytes(), b64_std(&self.last_client).into_bytes()].concat();
        self.chain_rc4 = Some(Rc4::new(&derive_key(&rc4_password, 16)));
        let mut packet = head;
        packet.extend(mid);
        packet.extend(self.chain_data(buf));
        packet
    }
    fn chain_data(&mut self, buf: &[u8]) -> Vec<u8> {
        let mut cipher = buf.to_vec();
        if let Some(rc4) = self.chain_rc4.as_mut() { rc4.apply(&mut cipher); }
        let last = self.last_client.clone();
        let sizes = self.sizes.clone();
        let sizes2 = self.sizes2.clone();
        let mixed = mix_sized(self.variant, self.overhead, &sizes, &sizes2, cipher.len(), &cipher, &last, &mut self.rand_c);
        let mut mac_key = self.key.clone();
        mac_key.extend(self.pack_id.to_le_bytes());
        let mask = u16::from_le_bytes(self.last_client.get(14..16).unwrap_or(&[0, 0]).try_into().unwrap_or([0, 0]));
        let length = (cipher.len() as u16) ^ mask;
        let mut data = length.to_le_bytes().to_vec();
        data.extend(mixed);
        self.last_client = hmac_n(true, &mac_key, &data, 16);
        data.extend(&self.last_client[..2]);
        self.pack_id = self.pack_id.wrapping_add(1);
        data
    }
    fn chain_post(&mut self, buf: &[u8]) -> Vec<u8> {
        self.pending.extend_from_slice(buf);
        let mut plain = Vec::new();
        while self.pending.len() > 4 && self.last_server.len() >= 16 {
            let mask = u16::from_le_bytes([self.last_server[14], self.last_server[15]]);
            let data_len = (u16::from_le_bytes([self.pending[0], self.pending[1]]) ^ mask) as usize;
            let last = self.last_server.clone();
            let sizes = self.sizes.clone();
            let sizes2 = self.sizes2.clone();
            let rand_len = chain_pad(self.variant, self.overhead, &sizes, &sizes2, data_len, &last, &mut self.rand_s);
            let length = data_len + rand_len;
            if length + 4 > self.pending.len() || length >= 4096 { break; }
            let mut mac_key = self.key.clone();
            mac_key.extend(self.recv_id.to_le_bytes());
            let hash = hmac_n(true, &mac_key, &self.pending[..length + 2], 16);
            if hash[..2] != self.pending[length + 2..length + 4] { break; }
            let mut pos = 2;
            if data_len > 0 && rand_len > 0 { pos += (self.rand_s.next() % 8589934609) as usize % rand_len; }
            let mut chunk = self.pending[pos..pos + data_len].to_vec();
            if let Some(rc4) = self.chain_rc4.as_mut() { rc4.apply(&mut chunk); }
            if self.recv_id == 1 && chunk.len() >= 2 { plain.extend_from_slice(&chunk[2..]); } else { plain.extend(chunk); }
            self.last_server = hash;
            self.recv_id = self.recv_id.wrapping_add(1);
            self.pending.drain(..length + 4);
        }
        plain
    }
    fn sha1v4_pre(&mut self, buf: &[u8]) -> Vec<u8> {
        let mut rest = buf;
        let mut out = Vec::new();
        if !self.sent_header {
            let take = rest.len().min(1200);
            let mut body = self.utc.to_le_bytes().to_vec();
            body.extend(random(4));
            let conn = (u32::from_le_bytes(random(4).try_into().unwrap_or([0; 4])) & 0x00FF_FFFF).wrapping_add(1);
            body.extend(conn.to_le_bytes());
            body.extend_from_slice(&rest[..take]);
            out.extend(self.sha1v4_auth(&body));
            rest = &rest[take..];
            self.sent_header = true;
        }
        while rest.len() > 8100 {
            out.extend(self.sha1v4_data(&rest[..8100]));
            rest = &rest[8100..];
        }
        out.extend(self.sha1v4_data(rest));
        out
    }
    fn sha1v4_auth(&self, body: &[u8]) -> Vec<u8> {
        let mut data = sha1_rnd(body.len());
        data.extend_from_slice(body);
        let data_len = (data.len() + 16) as u16;
        let mut crc_input = data_len.to_be_bytes().to_vec();
        crc_input.extend_from_slice(b"auth_sha1_v4");
        crc_input.extend(&self.key);
        let mut packet = data_len.to_be_bytes().to_vec();
        packet.extend(crc32(&crc_input).to_le_bytes());
        packet.extend(data);
        let mut mac_key = self.iv.clone();
        mac_key.extend(&self.key);
        packet.extend(hmac_n(false, &mac_key, &packet, 10));
        packet
    }
    fn sha1v4_data(&self, body: &[u8]) -> Vec<u8> {
        let mut data = sha1_rnd(body.len());
        data.extend_from_slice(body);
        let data_len = (data.len() + 8) as u16;
        let crc = (crc32(&data_len.to_be_bytes()) & 0xFFFF) as u16;
        let mut packet = data_len.to_be_bytes().to_vec();
        packet.extend(crc.to_le_bytes());
        packet.extend(data);
        packet.extend(adler32(&packet).to_le_bytes());
        packet
    }
    fn sha1v4_post(&mut self, buf: &[u8]) -> Vec<u8> {
        self.pending.extend_from_slice(buf);
        let mut plain = Vec::new();
        while self.pending.len() > 4 {
            let expect = (crc32(&self.pending[..2]) & 0xFFFF) as u16;
            let got = u16::from_le_bytes([self.pending[2], self.pending[3]]);
            if expect != got { break; }
            let length = u16::from_be_bytes([self.pending[0], self.pending[1]]) as usize;
            if length < 8 || length >= 8192 || length > self.pending.len() { break; }
            if adler32(&self.pending[..length - 4]) != u32::from_le_bytes(self.pending[length - 4..length].try_into().unwrap_or([0; 4])) { break; }
            let pos = if self.pending[4] < 255 {
                4 + self.pending[4] as usize
            } else if self.pending.len() >= 7 {
                4 + u16::from_be_bytes([self.pending[5], self.pending[6]]) as usize
            } else {
                break;
            };
            if pos < length - 4 { plain.extend_from_slice(&self.pending[pos..length - 4]); }
            self.pending.drain(..length);
        }
        plain
    }
    fn mac_key(&self, id: u32) -> Vec<u8> {
        let mut key = self.key.clone();
        key.extend(id.to_le_bytes());
        key
    }
}

#[derive(Clone)]
struct TlsObfs {
    active: bool,
    status: u8,
    host: String,
    key: Vec<u8>,
    client_id: Vec<u8>,
    send_buffer: Vec<u8>,
    recv_buffer: Vec<u8>,
}

impl TlsObfs {
    fn new(name: &str, host: &str, key: &[u8]) -> Self {
        let active = name.starts_with("tls1.2_ticket");
        Self { active, status: 0, host: host.to_string(), key: key.to_vec(), client_id: random(32), send_buffer: Vec::new(), recv_buffer: Vec::new() }
    }
    fn client_encode(&mut self, buf: &[u8]) -> Vec<u8> {
        if !self.active || self.status == 255 { return buf.to_vec(); }
        if self.status == 8 { return tls_app(buf); }
        if !buf.is_empty() { self.send_buffer.extend(tls_app(buf)); }
        if self.status == 0 {
            self.status = 1;
            return tls_hello(&self.host, &self.key, &self.client_id);
        }
        if self.status == 1 && buf.is_empty() {
            let mut data = vec![0x14, 0x03, 0x03, 0x00, 0x01, 0x01];
            data.extend_from_slice(&[0x16, 0x03, 0x03, 0x00, 0x20]);
            data.extend(random(22));
            data.extend(hmac_n(false, &[self.key.clone(), self.client_id.clone()].concat(), &data, 10));
            data.extend(self.send_buffer.drain(..));
            self.status = 8;
            return data;
        }
        Vec::new()
    }
    fn client_decode(&mut self, buf: &[u8]) -> std::io::Result<Vec<u8>> {
        if !self.active || self.status == 255 { return Ok(buf.to_vec()); }
        if self.status != 8 {
            if buf.len() < 43 { return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "short tls handshake")); }
            let key = [self.key.clone(), self.client_id.clone()].concat();
            let mac = hmac_n(false, &key, &buf[11..33], 10);
            if mac != buf[33..43] { return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "tls auth failed")); }
            return Ok(Vec::new());
        }
        self.recv_buffer.extend_from_slice(buf);
        let mut out = Vec::new();
        while self.recv_buffer.len() > 5 {
            if self.recv_buffer[0] != 0x17 { break; }
            let size = u16::from_be_bytes([self.recv_buffer[3], self.recv_buffer[4]]) as usize;
            if self.recv_buffer.len() < size + 5 { break; }
            out.extend_from_slice(&self.recv_buffer[5..5 + size]);
            self.recv_buffer.drain(..5 + size);
        }
        Ok(out)
    }
}

fn tls_app(buf: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    for chunk in buf.chunks(2048) {
        out.extend_from_slice(&[0x17, 0x03, 0x03]);
        out.extend((chunk.len() as u16).to_be_bytes());
        out.extend_from_slice(chunk);
    }
    out
}

fn tls_hello(host: &str, key: &[u8], client_id: &[u8]) -> Vec<u8> {
    let mut random_data = (std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as u32).unwrap_or(0)).to_be_bytes().to_vec();
    random_data.extend(random(18));
    random_data.extend(hmac_n(false, &[key, client_id].concat(), &random_data, 10));
    let mut body = vec![0x03, 0x03];
    body.extend(random_data);
    body.push(0x20);
    body.extend_from_slice(client_id);
    body.extend_from_slice(&hex_bytes("001cc02bc02fcca9cca8cc14cc13c00ac014c009c013009c0035002f000a0100"));
    let mut ext = hex_bytes("ff01000100");
    let host = host.split(',').next().unwrap_or("");
    if !host.is_empty() && !host.ends_with(|c: char| c.is_ascii_digit()) {
        let name = host.as_bytes();
        let mut inner = vec![0];
        inner.extend((name.len() as u16).to_be_bytes());
        inner.extend_from_slice(name);
        let mut sni = vec![0x00, 0x00];
        sni.extend(((inner.len() + 2) as u16).to_be_bytes());
        sni.extend((inner.len() as u16).to_be_bytes());
        sni.extend(inner);
        ext.extend(sni);
    }
    ext.extend_from_slice(&[0x00, 0x17, 0x00, 0x00]);
    let ticket = random(160);
    ext.extend_from_slice(&[0x00, 0x23]);
    ext.extend((ticket.len() as u16).to_be_bytes());
    ext.extend(ticket);
    ext.extend(hex_bytes("000d0016001406010603050105030401040303010303020102030005000501000000000012000075500000000b00020100000a0006000400170018"));
    body.extend((ext.len() as u16).to_be_bytes());
    body.extend(ext);
    let mut hello = vec![0x01, 0x00];
    hello.extend((body.len() as u16).to_be_bytes());
    hello.extend(body);
    let mut record = vec![0x16, 0x03, 0x01];
    record.extend((hello.len() as u16).to_be_bytes());
    record.extend(hello);
    record
}

fn rnd_prefix(max: usize) -> Vec<u8> {
    let n = if max == 0 { 0 } else { random(1)[0] as usize % max.min(127) };
    let mut out = vec![(n as u8).wrapping_add(1)];
    out.extend(random(n));
    out
}

fn sha1_rnd(buf_size: usize) -> Vec<u8> {
    if buf_size > 1200 { return vec![1]; }
    let sample = random(2);
    let n = if buf_size > 400 { sample[0] as usize } else { u16::from_be_bytes([sample[0], sample[1]]) as usize % 512 };
    let noise = random(n);
    if n < 128 {
        let mut out = vec![(n as u8).wrapping_add(1)];
        out.extend(noise);
        out
    } else {
        let mut out = vec![255];
        out.extend(((n + 3) as u16).to_be_bytes());
        out.extend(noise);
        out
    }
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &byte in data {
        crc ^= byte as u32;
        for _ in 0..8 {
            let mask = (crc & 1).wrapping_neg();
            crc = (crc >> 1) ^ (0xEDB8_8320 & mask);
        }
    }
    !crc
}

fn adler32(data: &[u8]) -> u32 {
    let mut a: u32 = 1;
    let mut b: u32 = 0;
    for &byte in data {
        a = (a + byte as u32) % 65521;
        b = (b + a) % 65521;
    }
    (b << 16) | a
}

fn hmac_n(md5_mode: bool, key: &[u8], data: &[u8], n: usize) -> Vec<u8> {
    if md5_mode {
        let mut mac = <Hmac<Md5> as Mac>::new_from_slice(key).unwrap_or_else(|_| <Hmac<Md5> as Mac>::new_from_slice(&[0]).unwrap());
        mac.update(data);
        mac.finalize().into_bytes()[..n].to_vec()
    } else {
        let mut mac = <Hmac<Sha1> as Mac>::new_from_slice(key).unwrap_or_else(|_| <Hmac<Sha1> as Mac>::new_from_slice(&[0]).unwrap());
        mac.update(data);
        mac.finalize().into_bytes()[..n].to_vec()
    }
}

fn auth_aes_key(user_key: &[u8], salt: &[u8]) -> [u8; 16] {
    let mut password = b64_std(user_key).into_bytes();
    password.extend_from_slice(salt);
    let derived = derive_key(&password, 16);
    let mut key = [0u8; 16];
    key.copy_from_slice(&derived[..16]);
    key
}

fn aes128_encrypt(key: &[u8; 16], block: &[u8]) -> Vec<u8> {
    use aes::cipher::generic_array::GenericArray;
    let cipher = aes::Aes128::new(GenericArray::from_slice(key));
    let mut data = GenericArray::clone_from_slice(block);
    cipher.encrypt_block(&mut data);
    data.to_vec()
}

fn b64_std(data: &[u8]) -> String {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in data.chunks(3) {
        let b0 = chunk[0];
        let b1 = *chunk.get(1).unwrap_or(&0);
        let b2 = *chunk.get(2).unwrap_or(&0);
        out.push(T[(b0 >> 2) as usize] as char);
        out.push(T[(((b0 & 3) << 4) | (b1 >> 4)) as usize] as char);
        if chunk.len() > 1 { out.push(T[(((b1 & 15) << 2) | (b2 >> 6)) as usize] as char); } else { out.push('='); }
        if chunk.len() > 2 { out.push(T[(b2 & 63) as usize] as char); } else { out.push('='); }
    }
    out
}

fn hex_bytes(text: &str) -> Vec<u8> {
    (0..text.len()).step_by(2).filter_map(|i| u8::from_str_radix(&text[i..i + 2], 16).ok()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cfb_roundtrip() {
        let key = derive_key(b"secret", 32);
        let iv = [7u8; 16];
        let mut enc = open_cipher("aes-256-cfb", &key, &iv, false).unwrap();
        let mut dec = open_cipher("aes-256-cfb", &key, &iv, true).unwrap();
        let original = b"shadowsocks address".to_vec();
        let mut data = original.clone();
        enc.apply(&mut data);
        assert_ne!(data, original);
        dec.apply(&mut data);
        assert_eq!(data, original);
    }

    #[test]
    fn auth_unit_roundtrip() {
        let key = derive_key(b"secret-password", 16);
        let iv = [9u8; 16];
        let mut send = Lane::new("auth_aes128_md5", &key, &iv, "", 1);
        send.sent_header = true;
        let packet = send.pack_unit(b"hello-ssr");
        let mut recv = Lane::new("auth_aes128_md5", &key, &iv, "", 1);
        let plain = recv.post_decrypt(&packet);
        assert_eq!(plain, b"hello-ssr");
    }

    #[test]
    fn xorshift_matches_reference() {
        let mut random = XorShift::default();
        random.init_len(&(0..16).collect::<Vec<_>>(), 20);
        assert_eq!(random.next(), 17632929753770267605);
        assert_eq!(random.next(), 12456224123253891485);
    }

    #[test]
    fn chain_variants_match_reference() {
        let key: Vec<u8> = (0..16).collect();
        let lane = Lane::new("auth_chain_b", &key, &[0u8; 16], "", 1);
        assert_eq!(lane.sizes, vec![91, 119, 273, 360, 435, 1214, 1303]);
        assert_eq!(&lane.sizes2[..3], &[71, 85, 142]);
        let hash: Vec<u8> = (0..16).collect();
        let mut random = XorShift::default();
        assert_eq!(chain_pad(1, 4, &lane.sizes, &lane.sizes2, 100, &hash, &mut random), 1110);
        let chain_c = Lane::new("auth_chain_c", &key, &[0u8; 16], "", 1);
        assert_eq!(chain_c.sizes.len(), 23);
        assert_eq!(chain_c.sizes[0], 85);
        assert_eq!(*chain_c.sizes.last().unwrap(), 1350);
        assert!(Lane::new("auth_chain_d", &key, &[0u8; 16], "", 1).sizes.len() >= 12);
        assert!(!Lane::new("auth_chain_e", &key, &[0u8; 16], "", 1).sizes.is_empty());
        let day = Lane::new("auth_chain_f", &key, &[0u8; 16], "64#86400", 1_700_000_000);
        let other = Lane::new("auth_chain_f", &key, &[0u8; 16], "64#86400", 1_700_000_100);
        assert_eq!(day.sizes, other.sizes);
        assert_eq!(day.salt, b"auth_chain_f");
    }

    #[test]
    fn sha1_v4_roundtrip() {
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
        let key = derive_key(b"secret-password", 16);
        let iv = [3u8; 16];
        let mut send = Lane::new("auth_sha1_v4", &key, &iv, "", 1);
        send.sent_header = true;
        let packet = send.sha1v4_data(b"hello-v4");
        let mut recv = Lane::new("auth_sha1_v4", &key, &iv, "", 1);
        assert_eq!(recv.post_decrypt(&packet), b"hello-v4");
    }
}
