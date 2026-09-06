# Security

`secret_store.dart` is boundary for credentials. Provider metadata may live in SQLite; secret values may not.

## Allowed data flow

Provider login or API-key forms write through `SecretStore`. Provider transports read through the same abstraction for one request. Diagnostics and persistence receive only provider ID, auth state, and sanitized error categories.

## Never do

Do not log tokens, cookies, authorization codes, raw headers, API keys, or secure-storage values. Do not write them to `.syntac`, `.omp`, JSONL, SQLite, project files, or tool output. Do not add test fixtures containing real credentials.

## Verification

Credential tests belong in `test/app_foundation_test.dart`. Assert values stay absent from SQLite, JSONL, diagnostics, and user-facing errors. Update this file and `AGENTS.md` when storage or provider auth boundaries change.