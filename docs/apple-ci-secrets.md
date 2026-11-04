# Apple signing secrets for GitHub Actions

Public releases that open without Gatekeeper warnings need a **Developer ID Application** certificate, **two macOS provisioning profiles** (app + Packet Tunnel), and **notarization** credentials. CI reads them from repository secrets and runs [scripts/ci-import-certificate.sh](../scripts/ci-import-certificate.sh) before [build-macos.sh](../build-macos.sh).

If **`APPLE_CERTIFICATE_BASE64` is empty**, CI builds **ad-hoc** zips (Right-click → Open the first time). If the certificate secret is set, **both profile secrets are required** so Network Extension builds are valid.

---

## One-time Apple Developer setup

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/) (paid).
2. Create App IDs and capabilities as in [signing.md](signing.md):
   - `local.v2open.desktop` — Packet Tunnel + App Group `group.local.v2open`
   - `local.v2open.desktop.PacketTunnel` — Packet Tunnel + same App Group
3. Create **Developer ID Application** certificate in Keychain Access → export as `.p12` with a password.
4. Create **Mac Developer ID** provisioning profiles for the app and the Packet Tunnel extension. Download `.provisionprofile` files (keep them out of git).
5. Create an [App Store Connect API key](https://appstoreconnect.apple.com/access/integrations/api) with **Developer** role, or an app-specific password for `notarytool`.

---

## Encode files for GitHub (local Mac)

From the repo root, with your real paths:

```bash
./scripts/encode-apple-secrets.sh \
  ~/Downloads/DeveloperID.p12 \
  ~/Downloads/local_v2open_desktop.provisionprofile \
  ~/Downloads/local_v2open_desktop_PacketTunnel.provisionprofile \
  ~/Downloads/AuthKey_ABC123XYZ.p8
```

The script prints `base64 | pbcopy` hints and the `gh secret set` commands. Do **not** commit `.p12`, profiles, or `.p8` files.

---

## Repository secrets

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | Base64 of the `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | Export password for that `.p12` |
| `APPLE_PROFILE_APP_BASE64` | Base64 of the **app** `.provisionprofile` |
| `APPLE_PROFILE_TUNNEL_BASE64` | Base64 of the **Packet Tunnel** `.provisionprofile` |
| `APPLE_NOTARY_KEY_BASE64` | Base64 of `AuthKey_*.p8` |
| `APPLE_NOTARY_KEY_ID` | Key ID from App Store Connect |
| `APPLE_NOTARY_ISSUER_ID` | Issuer UUID from App Store Connect |

**Notary fallback** (instead of the API key trio):

| Secret | Value |
| --- | --- |
| `APPLE_ID` | Apple ID email |
| `APPLE_TEAM_ID` | 10-character Team ID |
| `APPLE_APP_PASSWORD` | App-specific password |

Set secrets with GitHub CLI (admin on the repo):

```bash
gh auth login
gh secret set APPLE_CERTIFICATE_BASE64 < /tmp/cert.b64
gh secret set APPLE_CERTIFICATE_PASSWORD --body 'your-p12-password'
gh secret set APPLE_PROFILE_APP_BASE64 < /tmp/app-profile.b64
gh secret set APPLE_PROFILE_TUNNEL_BASE64 < /tmp/tunnel-profile.b64
gh secret set APPLE_NOTARY_KEY_BASE64 < /tmp/notary-key.b64
gh secret set APPLE_NOTARY_KEY_ID --body 'ABC123XYZ'
gh secret set APPLE_NOTARY_ISSUER_ID --body '00000000-0000-0000-0000-000000000000'
```

Verify (names only, not values):

```bash
gh secret list
```

---

## What CI does

1. **No certificate secret** → `V2OPEN_ADHOC=1`, ad-hoc sign, no notarization.
2. **Certificate + both profiles** → Developer ID sign, embed profiles, hardened runtime on engines.
3. **Plus notary secrets** → `V2OPEN_NOTARIZE=1`, staple ticket, `spctl --assess` in [notarize-macos.sh](../scripts/notarize-macos.sh).

Release workflow builds **arm64** and **x86_64**, uploads:

- `V2Open-{version}-build{build}-macos-arm64.zip`
- `V2Open-{version}-build{build}-macos-x86_64.zip`

The in-app updater picks the zip matching the Mac architecture. GitHub attaches a **SHA-256 digest** on each release asset; the app verifies it when present.

---

## Local signed + notarized build

```bash
export V2OPEN_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export V2OPEN_PROFILE_APP=/path/app.provisionprofile
export V2OPEN_PROFILE_TUNNEL=/path/tunnel.provisionprofile
export V2OPEN_NOTARIZE=1
export APPLE_NOTARY_KEY_PATH=/path/AuthKey.p8
export APPLE_NOTARY_KEY_ID=...
export APPLE_NOTARY_ISSUER_ID=...
./build-macos.sh
V2OPEN_ARCH=x86_64 ./build-macos.sh
```

---

## Intel `masterdns`

Intel zips include `masterdns` when Go is available during `./build-macos.sh` (via [fetch-macos-engines.sh](../scripts/fetch-macos-engines.sh)), compiled from [masterking32/MasterDnsVPN](https://github.com/masterking32/MasterDnsVPN) at tag **`v2026.10.26.100415-5f83ee9`** (same lineage as the committed Apple Silicon binary). To pin another upstream revision, set `MASTERDNS_REF` and `MASTERDNS_VERSION` before building.

---

## After secrets are set

1. Merge release prep to `main` ([release.md](release.md)).
2. `./scripts/pre-release-check.sh` (defaults to the version in `VERSION`).
3. `git tag -a vX.Y.Z -m "V2Open X.Y.Z"` and `git push origin vX.Y.Z` (tag must match `VERSION` line 1).
4. Watch the **Release** workflow; download both zips and smoke-test on Apple Silicon and Intel Macs.

Or run [scripts/setup-github-secrets.sh](../scripts/setup-github-secrets.sh) once Apple files are on disk (see env vars in that script).
