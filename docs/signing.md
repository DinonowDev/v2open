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

After `./build-macos.sh`:

```bash
ditto -c -k --keepParent V2Open.app /tmp/V2Open.zip
xcrun notarytool submit /tmp/V2Open.zip --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_SPECIFIC_PASSWORD" --wait
xcrun stapler staple V2Open.app
spctl --assess -v V2Open.app
```

Do not put Apple ID passwords in the repo. Notarization is not required for ad-hoc local debug.

---

## Hardened runtime / sandbox

The current entitlements do **not** enable App Sandbox. Packet Tunnel + spawning `sing-box` / `xray` from the appex is simpler unsandboxed. Enabling sandbox is a separate design change (more entitlements, more breakage). Do not turn it on in a drive-by PR.

---

## Contributor rules

- Entitlement or bundle-id changes need a risk note on the PR ([CONTRIBUTING.md](../CONTRIBUTING.md)).
- Never commit certificates, `.p12`, or provisioning profiles.
- Do not “fix” VPN by disabling SIP or copying random profiles from the internet.
