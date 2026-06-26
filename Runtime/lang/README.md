# Language Packs

This folder contains the local language packs used by `Runtime/injector.py`.

## Runtime Chinese packs

- `zh.json`: main Figma app Chinese pack.
- `auth-zh.json`: login/account/auth Chinese pack.
- `prototype_app_beta-zh.json`: prototype preview Chinese pack.

## Captured English source packs

- `en_latest.json`: captured from `figma_app_beta-*.min.en.json.br`.
- `auth_latest.en.json`: captured from `auth-*.min.en.json.br`.
- `prototype_app_beta_latest.en.json`: captured from `prototype_app_beta-*.min.en.json.br`.

## Metadata

- `manifest.json`: source URLs, key counts, and merge statistics.

## Merge policy

Chinese packs are generated from the captured English source packs by reusing
matching entries from the existing Chinese main pack. If a key has no matching
Chinese entry, the English entry is kept as a fallback so Figma still receives a
complete language object.

Current fallback counts are recorded in `manifest.json`.
