# AGENTS.md

## Scope

`lib/src/storage/` owns persistence. SQLite stores app metadata. JSONL stores chat-owned runtime data.

## Files

- `local_database.dart`: SQLite open/create/upgrade, metadata schema, project mount naming.
- `app_repository.dart`: storage facade used by app/agent/UI; also implements `CredentialStore` bridge.
- `chat_jsonl_store.dart`: chat index, messages, tool executions, jobs, attachments, JSONL recovery/migration.
- `storage_stats.dart`: async storage breakdown for settings UI.

## Change here when

- Adding persistent field/table/file.
- Changing migration or compatibility behavior.
- Changing chat/message/tool/job/attachment persistence.
- Changing secure credential lookup boundary.

## Invariants

- Do not store API keys, OAuth tokens, refresh tokens, or other secrets in SQLite/JSONL.
- Preserve existing installs through migrations and enum fallback parsing.
- Chat-owned runtime data belongs in JSONL, not new SQLite chat tables.
- JSONL writes must remain per-file serialized and atomically replaced through unique temp files.
- Startup must recover/dismiss temp files safely.
- Malformed rows must not drop valid rows.
- Deleted chats must reject later messages, jobs, tool executions, and attachments.
- Persisted text/raw JSON caps must keep UI responsive.

## Tests

Use `test/app_foundation_test.dart` for SQLite migrations, JSONL malformed data, temp recovery, concurrent writes, deleted-chat races, credential secrecy, and truncation behavior.
