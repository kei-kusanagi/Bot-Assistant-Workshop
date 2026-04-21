# Semantic commits (workshop — English)

We follow **Conventional Commits**-style prefixes so history stays readable and `git log` doubles as a changelog.

## Prefixes

| Prefix | When to use |
|--------|----------------|
| `feat` | New behavior users or operators care about (e.g. QR flow). |
| `fix` | Bug fixes. |
| `docs` | README, migration notes, comments that mainly document. |
| `build` | Dockerfiles, compile scripts, CI images. |
| `chore` | Tooling, compose, ignores, refactors without feature change. |
| `test` | Tests only. |

Optional scope in parentheses: `feat(dart):`, `docs(node):`, etc.

## Dart / WhatsApp QR mission — atomic sequence

These commits map one concern each (boss request: small, explainable steps):

1. `chore(dart): add whatsapp_qr_pairing package skeleton` — pubspec, lockfile, lints, changelog, ignores, empty library + smoke test.
2. `feat(dart): implement Neonize QR pairing with deferred native load` — bin entry + `neonize_pairing` logic only.
3. `docs(dart): add README for WhatsApp QR pairing CLI` — how to run, `NEONIZE_PATH`, data dirs.
4. `build(dart): add Dockerfile for compiled WhatsApp QR CLI` — container build for Linux binary.
5. `docs(dart): add Baileys migration log and Dart workspace index` — cross-stack narrative + `Dart/README.md`.
6. `chore(dart): add docker-compose with Ollama sidecar` — compose file; Ollama optional for future local LLM work.

When extending the bot, keep splitting: e.g. `feat(dart): handle inbound text messages` as its own commit after the pairing baseline is stable.

## Follow-up commits (same mission, later session)

After the initial seven commits, these were added while clarifying Windows downloads and local setup:

- `docs(dart): document Windows run with Neonize DLL beside pubspec`
- `docs(dart): note local DLL path and gitignore in migration log`

(Plus earlier follow-ups: Node parity guide, DLL asset names, `.whl` warning, `gitignore` for `neonize-*.dll`.)
