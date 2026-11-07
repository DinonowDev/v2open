use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

#[derive(Clone, Default)]
pub struct MockHeaders {
    pub pairs: Vec<(String, String)>,
}

impl MockHeaders {
    pub fn push(mut self, key: &str, value: &str) -> Self {
        self.pairs.push((key.to_string(), value.to_string()));
        self
    }

    fn block(&self, body: &str) -> String {
        let mut lines = vec!["HTTP/1.1 200 OK".to_string(), format!("Content-Length: {}", body.len())];
        for (k, v) in &self.pairs {
            lines.push(format!("{k}: {v}"));
        }
        lines.push(String::new());
        format!("{}\r\n{}", lines.join("\r\n"), body)
    }
}

/// Binds `127.0.0.1:0`, serves one HTTP response, returns captured request text and base URL.
pub fn serve_once(body: &str, headers: MockHeaders) -> (String, Arc<Mutex<String>>, JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind mock");
    listener.set_nonblocking(false).ok();
    let port = listener.local_addr().unwrap().port();
    let url = format!("http://127.0.0.1:{port}/sub");
    let captured = Arc::new(Mutex::new(String::new()));
    let cap = captured.clone();
    let response = headers.block(body);
    let handle = thread::spawn(move || {
        if let Ok((mut stream, _)) = listener.accept() {
            let _ = stream.set_read_timeout(Some(Duration::from_secs(3)));
            let mut buf = vec![0u8; 16_384];
            if let Ok(n) = stream.read(&mut buf) {
                *cap.lock().unwrap() = String::from_utf8_lossy(&buf[..n]).to_string();
            }
            let _ = stream.write_all(response.as_bytes());
        }
    });
    (url, captured, handle)
}

pub fn wait(handle: JoinHandle<()>) {
    let _ = handle.join();
}
