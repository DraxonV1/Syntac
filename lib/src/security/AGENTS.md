# AGENTS.md

## Scope

`lib/src/security/` owns secret storage abstraction and secure-storage implementation.

## Rules

- Store API keys, OAuth access tokens, refresh tokens, authorization codes, and cookies only through `SecretStore`/Android secure storage.
- Never put secrets in SQLite, JSONL, project files, logs, diagnostics, tool results, provider errors, or test fixtures.
- Keep provider code dependent on `SecretStore` abstraction; do not read secure storage from widgets or `AgentLoop` internals.
- Treat missing/corrupt secret values as safe authentication failures. Do not echo raw values.

## Change workflow

Update credential callers and secrecy tests when methods or key formats change. Preserve migration compatibility without copying secrets into shared `.syntac` storage. Run focused provider/persistence tests and `flutter analyze`.