# Language Packs

Files in this folder:

- `zh.json`: Chinese language pack from `kailous/figma-zh-CN-localized`.
- `en_latest.json`: latest English pack downloaded from `kailous/figma-zh-CN-localized/lang/en_latest.json`.
- `en_latest.json.br`: downloaded from `kailous/figma-zh-CN-localized/lang/en_latest.json.br`.
- `auth_latest.en.json`: current public login/auth page English pack detected from Figma.

Notes:

- Direct unauthenticated probing of `https://www.figma.com/community` returned an AWS WAF challenge on 2026-06-15, so the main editor pack could not be discovered directly from the public page in this environment.
- The downloaded `en_latest.json.br` starts with `{`, so this copy is plain JSON content despite the `.br` extension.
