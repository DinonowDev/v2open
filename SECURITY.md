# Security policy

V2Open is a local client. A bug in parsing, the Packet Tunnel, sidecar processes, or the locked-catalog format can expose traffic or files on the Mac that runs it. Application source is MIT ([LICENSE](LICENSE)); bundled engines keep the licenses in [NOTICE](NOTICE).

## Supported versions

| Version | Support |
| --- | --- |
| `1.1.x` (current `main`) | Yes |
| Older tags | Best effort; please reproduce on `main` first |

## How to report

**Do not** open a public issue for a vulnerability.

1. Prefer a [GitHub private security advisory](https://github.com/DinonowDev/v2open/security/advisories/new) on this repository.
2. If that is unavailable, contact the maintainer through the GitHub profile linked from **Settings → About** in the app.

Include:

- V2Open version and build (`Settings → About`, or `VERSION`)
- macOS version and CPU architecture
- Whether you used `V2Open.app` or `V2Open-Dev.app`
- Engine (`sing-box` / Xray) if relevant
- Steps that stay within **your** configs and machines
- Impact (traffic leak, local file read, privilege, crash only)

Do not attach real subscription URLs, UUIDs, or passwords. Redact them.

## What we will do

- Acknowledge the report
- Work on a fix on a private branch
- Credit you in `CHANGELOG.md` under `Security` if you want to be named
- Ship a PATCH or MINOR release depending on severity (see [docs/versioning.md](docs/versioning.md))

## What is out of scope

- Servers, panels, or CDNs that are not part of this repository
- Misuse of a config you imported
- Unsigned local builds (`V2Open-Dev.app`) missing the Packet Tunnel entitlement
- Denial of service against public websites through the speed test or ping tools

## Hardening notes for contributors

- Configs stay in `~/Library/Application Support/V2Open/` unless the user exports or enables iCloud
- Locked packages use the `V2OPEN1` vault in `native/core/src/vault.rs` (AES-256-GCM, PBKDF2-HMAC-SHA256)
- Do not log share links, passwords, or `library.json` bodies
- FFI (`v2_init` / `v2_call` / `v2_free`) must keep owning the returned C string until `v2_free`
- New URL schemes are a security-sensitive surface: they import whatever the OS hands the app
