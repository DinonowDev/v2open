# Bundled binaries

V2Open does not compile `sing-box`, Xray, or the sidecar helpers from this repo. Build scripts **copy** whatever is in `binaries/macos/` into the app bundle.

Licenses and upstream URLs: [NOTICE](../NOTICE). Process for replacing them is this page. Touch both files in the same PR if the upstream or license changes.

---

## Layout

| Path | Role | Copied into the app? |
| --- | --- | --- |
| `binaries/macos/sing-box` | Default engine (currently an **extended** build) | Yes → `Contents/MacOS/sing-box` |
| `binaries/macos/sing-box.official` | Stock SagerNet build, kept for comparison / swap | No (not copied by the scripts) |
| `binaries/macos/xray` | Xray engine | Yes |
| `binaries/macos/dnstt-client` | DNSTT sidecar | Yes |
| `binaries/macos/masterdns` | MasterDNS sidecar | Yes |
| `binaries/macos/pingtunnel` | ICMP sidecar | Yes |
| `binaries/macos/geoip.dat` | GeoIP database | Yes → `Contents/Resources/` |
| `binaries/macos/geosite.dat` | Geosite database | Yes → `Contents/Resources/` |
| `binaries/dnstt-COPYING` | CC0 text for dnstt | No |
| `binaries/macos/VERSIONS` | Recorded version strings | No |

`dev-macos.sh` / `build-macos.sh` ad-hoc codesign each executable after copy.

Current machines in this tree are **Mach-O arm64**. A release for Intel (or universal) needs matching binaries; `file binaries/macos/sing-box` must show `arm64`, `x86_64`, or `universal`.

---

## Recorded versions

`binaries/macos/VERSIONS` is the checklist. After every replacement run:

```bash
./scripts/binaries-versions.sh > binaries/macos/VERSIONS
git diff binaries/macos/VERSIONS
```

Then update the “Current tree” table below if the marketing version of an engine changed, and mention it in `CHANGELOG.md` (`Changed`).

### Current tree

| File | Identity (as of this docs revision) |
| --- | --- |
| `sing-box` | `1.14.3-extended-2.7.3` (`darwin/arm64`) — launched by the app |
| `sing-box.official` | stock `1.14.4` (`darwin/arm64`) — not copied into the bundle |
| `xray` | `26.10.21` (`darwin/arm64`) |
| sidecars + `.dat` | sizes and `file(1)` type in `binaries/macos/VERSIONS` |

The extended `sing-box` is **not** a vanilla SagerNet release (version suffix `extended-…`, extra tags). Do not advertise it as official sing-box. Official binary lives next to it as `sing-box.official`. To ship stock instead: copy it over `sing-box`, regenerate `VERSIONS`, and document the swap in the PR.

---

## How to replace an engine

1. Download or build **only** from the upstream in [NOTICE](../NOTICE) (or a fork whose license you record).
2. Confirm architecture:

   ```bash
   file /path/to/new-sing-box
   # Mach-O 64-bit executable arm64   OR  universal
   ```

3. Confirm it runs:

   ```bash
   /path/to/new-sing-box version
   /path/to/new-xray version
   ```

4. Install into the tree:

   ```bash
   cp /path/to/new-sing-box binaries/macos/sing-box
   chmod +x binaries/macos/sing-box
   codesign --force --sign - binaries/macos/sing-box
   ```

5. Refresh the version record and smoke-test:

   ```bash
   ./scripts/binaries-versions.sh > binaries/macos/VERSIONS
   ./dev-macos.sh relaunch
   ```

6. In the same PR: [NOTICE](../NOTICE) if upstream/license changed, this page if the procedure changed, `CHANGELOG.md` under `Changed`, and a risk note (parser/builder may need a MINOR if the new engine rejects old JSON).

Never commit a binary you cannot attribute. Never strip the sidecar that `sidecar.rs` still launches unless you remove that protocol in the same PR.

---

## Geo files

`geoip.dat` / `geosite.dat` default to v2fly sources (see settings `geoip_source` / `geo_files_source`). Replacing them:

```bash
cp /path/to/geoip.dat binaries/macos/geoip.dat
cp /path/to/geosite.dat binaries/macos/geosite.dat
```

The app also copies them into `~/Library/Application Support/V2Open/` on first run. After a geo upgrade, either bump that copy via **Settings → Routing → Geo assets** or delete the Application Support copies so the bundle files seed again.

---

## Git and size

These files are large (tens of MB). They are **not** gitignored. If GitHub rejects a push, use [Git LFS](https://git-lfs.com) for `binaries/macos/*` and say so in the PR. CI that needs `sing-box check` must have the file present or the Rust tests in `config.rs` will skip.

`binaries/linux/` and `binaries/windows/` are gitignored leftovers from a removed stack — do not re-add them.
