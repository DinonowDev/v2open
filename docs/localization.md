# Localization

UI copy is JSON, not `Localizable.strings`.

## Files

| Path | Role |
| --- | --- |
| `macos-app/Resources/Locales/en.json` | **Source of truth** for keys |
| `macos-app/Resources/Locales/{fa,ar,id,ru,tr,uk,vi,zh,zh-Hans}.json` | Translations |
| `macos-app/Sources/Core/Localization.swift` | Compile-time fallback `enText` / `faText` |
| `macos-app/Sources/Core/LocaleStore.swift` | Loader + language menu |

`LocaleStore.options` is the language picker. Adding a language means a new JSON file, a new tuple in `options`, and copying every key from `en.json`.

RTL: `fa` and `ar` set `layoutDirection` to right-to-left.

---

## Lookup order

For `model.t("key")`:

1. `Locales/<language>.json`
2. If language is `fa`, `faText` in `Localization.swift`
3. `Locales/en.json`
4. `enText`
5. The raw key (so a missing string is obvious in the UI)

JSON is copied into `Contents/Resources/Locales/` by `dev-macos.sh` / `build-macos.sh`. After editing JSON, relaunch (watch mode does not track locale files).

---

## Adding or changing a string

In the **same** PR as the Swift that uses it:

1. Add or edit the key in **every** `macos-app/Resources/Locales/*.json`.
2. If the string can appear before JSON is on disk (early boot, tests), update `enText` and `faText`.
3. Keys are camelCase (`smartConnect`, `subAutoUpdate`). Reuse an existing key instead of inventing a synonym.
4. Do not build sentences with `+` in Swift. Translators need a whole phrase.
5. `en.json` is written in American English, sentence case matching nearby keys.
6. Persian (`fa.json`) should read naturally; do not leave English placeholders in fa unless the term is a protocol name (`Mux`, `VLESS`).
7. Run `./scripts/check-locales.sh`.

Placeholders: keep protocol names, URLs, and `%` units as in English.

Hardcoded bilingual exceptions (move to JSON if you touch them heavily): About developer blurb, `LegalView` terms/privacy clauses.

---

## Checks

```bash
./scripts/check-locales.sh
```

Fails when:

- A locale file is not valid JSON or is not a flat `string → string` map
- A file is missing a key present in `en.json`
- A file has extra keys not in `en.json`

---

## When copy changes behavior

If you rename a setting label, mention it in `CHANGELOG.md` under `Changed` only if users would look for the old words. Typos in a single language are `docs`/`fix` without a version bump.
