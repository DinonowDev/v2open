# Signing and Network Extension

Unsigned **V2Open-Dev** is enough for UI work. The engine then starts as a child of the app (`connect` RPC). A real **system VPN** needs a signed Packet Tunnel extension and a paid [Apple Developer](https://developer.apple.com) membership.

---

## What the repo already has

| File | Bundle ID / group |
| --- | --- |
| `macos-app/Info.plist` | `local.v2open.desktop` |
| `macos-app/PacketTunnel/Info.plist` | `local.v2open.desktop.PacketTunnel` |
| `macos-app/V2Open.entitlements` | Network Extension + `group.local.v2open` |
| `macos-app/PacketTunnel/PacketTunnel.entitlements` | same |

`macos-env.sh` picks the first `Apple Development` / `Developer ID Application` / `Mac Developer` identity. If none, it signs ad-hoc (`codesign --sign -`). Ad-hoc **cannot** satisfy Network Extension for a system VPN.

Dev builds rewrite the app id to `local.v2open.dev` and the extension to `local.v2open.dev.PacketTunnel` so they can sit next to a release install.

---

## Identifiers to create in the developer portal

Create an App ID (macOS) for each:

1. `local.v2open.desktop` — capabilities:
   - Network Extensions → Packet Tunnel
   - App Groups → `group.local.v2open`
   - iCloud (CloudKit) → container `iCloud.local.v2open.desktop` if you ship iCloud backup
2. `local.v2open.desktop.PacketTunnel` — Network Extensions + the same App Group.

If Apple requires a team-prefixed group (`group.TEAMID.v2open`), change both entitlements files, the portal, and document the new id in this page.

Provisioning:

- Development profile for the app + one for the appex (for `V2Open-Dev` on your Mac).
- Developer ID *or* Mac App Store profiles for distribution. Network Extension outside the Mac App Store usually needs **Developer ID** plus notarization.

Put `.mobileprovision` / `.provisionprofile` files **outside** git (they are secrets).

---

## Entitlements to add for iCloud (signed builds)

`Cloud.swift` looks for these keys on the **running** app. They are **not** in the repo entitlements yet; iCloud backup stays inert until you add them on a signed identity:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
  <string>iCloud.local.v2open.desktop</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
  <string>CloudKit</string>
</array>
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array>
  <string>iCloud.local.v2open.desktop</string>
</array>
```

Keep Packet Tunnel entitlements without iCloud. After changing entitlements, bump nothing unless you also change user-visible iCloud behavior; still mention the signing change in the PR risk section.

---

## Local signed build

1. `security find-identity -v -p codesigning` shows your Apple Development identity.
2. `./build-macos.sh` (release) or `./dev-macos.sh run`.
3. `codesign -d --entitlements :- V2Open.app` and the appex under `Contents/PlugIns/PacketTunnel.appex`.
4. System Settings → Network / VPN: the first connect should prompt to add a VPN configuration. macOS will refuse the extension if the profile, entitlements, and bundle ids disagree.

If start fails, Swift falls back to `connect` (child process). That is **not** a system tunnel. Check Console.app for `PacketTunnel` and `nesessionmanager`.

---

## Notarization (Developer ID distribution)

`./build-macos.sh` signs with **Developer ID Application** when that identity is available (`--options runtime --timestamp`). Nested engines use `macos-app/Helper.entitlements`. Ad-hoc remains the fallback, and `./dev-macos.sh` prefers an Apple Development identity.

Notarization also needs provisioning profiles embedded as `Contents/embedded.provisionprofile` on the app and the Packet Tunnel appex. Restricted entitlements (Network Extension, App Groups) are rejected without them.

```bash
export V2OPEN_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)"
export V2OPEN_PROFILE_APP=/path/app.provisionprofile
export V2OPEN_PROFILE_TUNNEL=/path/tunnel.provisionprofile
export V2OPEN_NOTARIZE=1
export APPLE_NOTARY_KEY_PATH=/path/AuthKey.p8
export APPLE_NOTARY_KEY_ID=ABC123
export APPLE_NOTARY_ISSUER_ID=00000000-0000-0000-0000-000000000000
./build-macos.sh
```

`scripts/notarize-macos.sh` submits a zip, waits, staples, and runs `spctl --assess`. An Apple ID app-specific password (`APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`) works when the API key is not set. Do not put those values in the repo.

Intel builds: `V2OPEN_ARCH=x86_64 ./build-macos.sh` fetches official engines into `binaries/macos-x86_64/` (gitignored) and cross-compiles. See [binaries.md](binaries.md).

### GitHub Actions

[`.github/workflows/release.yml`](../.github/workflows/release.yml) and CI call `scripts/ci-import-certificate.sh`. With these repository secrets the zip is signed and notarized. Without them the job still publishes an ad-hoc zip. Step-by-step: [apple-ci-secrets.md](apple-ci-secrets.md).

| Secret | Purpose |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | Developer ID Application `.p12`, base64 |
| `APPLE_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `APPLE_PROFILE_APP_BASE64` | Provisioning profile for `local.v2open.desktop` |
| `APPLE_PROFILE_TUNNEL_BASE64` | Provisioning profile for `local.v2open.desktop.PacketTunnel` |
| `APPLE_NOTARY_KEY_BASE64` | App Store Connect API key (`.p8`), base64 |
| `APPLE_NOTARY_KEY_ID` | Key id |
| `APPLE_NOTARY_ISSUER_ID` | Issuer id |

Fallback instead of the API key: `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`.

Notarization is not required for ad-hoc local debug. A stapled app opens without `xattr -cr`. An ad-hoc zip still needs Right-click → Open the first time. The in-app updater clears quarantine only when `spctl` rejects the new bundle.

---

## Hardened runtime / sandbox

The current entitlements do **not** enable App Sandbox. Packet Tunnel + spawning `sing-box` / `xray` from the appex is simpler unsandboxed. Enabling sandbox is a separate design change (more entitlements, more breakage). Do not turn it on in a drive-by PR.

---

## Contributor rules

- Entitlement or bundle-id changes need a risk note on the PR ([CONTRIBUTING.md](../CONTRIBUTING.md)).
- Never commit certificates, `.p12`, or provisioning profiles.
- Do not “fix” VPN by disabling SIP or copying random profiles from the internet.
