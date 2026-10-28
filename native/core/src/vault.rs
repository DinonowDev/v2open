use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use pbkdf2::pbkdf2_hmac;
use sha2::Sha256;

const MAGIC: &[u8] = b"V2OPEN1";

pub fn seal(password: &str, plaintext: &[u8]) -> Result<Vec<u8>, String> {
    if password.len() < 4 {
        return Err("password is too short".into());
    }
    let salt = random(16);
    let nonce = random(12);
    let key = derive(password, &salt);
    let cipher = Aes256Gcm::new_from_slice(&key).map_err(|e| e.to_string())?;
    let body = cipher.encrypt(Nonce::from_slice(&nonce), plaintext).map_err(|e| e.to_string())?;
    let mut out = MAGIC.to_vec();
    out.extend(salt);
    out.extend(nonce);
    out.extend(body);
    Ok(out)
}

pub fn open(password: &str, blob: &[u8]) -> Result<Vec<u8>, String> {
    if blob.len() < MAGIC.len() + 16 + 12 + 16 || &blob[..MAGIC.len()] != MAGIC {
        return Err("this is not a V2Open locked file".into());
    }
    let salt = &blob[MAGIC.len()..MAGIC.len() + 16];
    let nonce = &blob[MAGIC.len() + 16..MAGIC.len() + 28];
    let body = &blob[MAGIC.len() + 28..];
    let key = derive(password, salt);
    let cipher = Aes256Gcm::new_from_slice(&key).map_err(|e| e.to_string())?;
    cipher.decrypt(Nonce::from_slice(nonce), body).map_err(|_| "wrong password".to_string())
}

pub fn lock_hash(password: &str) -> String {
    let salt = random(16);
    let mut out = [0u8; 32];
    pbkdf2_hmac::<Sha256>(password.as_bytes(), &salt, 120_000, &mut out);
    format!("{}:{}", hex(&salt), hex(&out))
}

pub fn lock_matches(password: &str, stored: &str) -> bool {
    let Some((salt_hex, hash_hex)) = stored.split_once(':') else { return false };
    let Some(salt) = unhex(salt_hex) else { return false };
    let Some(expected) = unhex(hash_hex) else { return false };
    let mut out = vec![0u8; expected.len()];
    pbkdf2_hmac::<Sha256>(password.as_bytes(), &salt, 120_000, &mut out);
    out == expected
}

fn derive(password: &str, salt: &[u8]) -> [u8; 32] {
    let mut key = [0u8; 32];
    pbkdf2_hmac::<Sha256>(password.as_bytes(), salt, 120_000, &mut key);
    key
}

fn random(n: usize) -> Vec<u8> {
    let mut buf = vec![0u8; n];
    let _ = getrandom::getrandom(&mut buf);
    buf
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn unhex(text: &str) -> Option<Vec<u8>> {
    if text.len() % 2 != 0 {
        return None;
    }
    (0..text.len()).step_by(2).map(|i| u8::from_str_radix(&text[i..i + 2], 16).ok()).collect()
}
