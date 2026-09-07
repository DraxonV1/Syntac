# Storage

`AppRepository` is storage facade. Global agent instructions live in `agent/SYSTEM.md`; project-local `.syntac/agent/SYSTEM.md` or `AGENTS.md` overrides them for that project.

## Ownership

- `LocalDatabase` stores stable metadata: projects, providers, models, settings.
- `ChatJsonlStore` stores chats, messages, tool executions, jobs, and attachments as user-accessible JSONL.
- `storage_stats.dart` reports metadata and chat-store sizes to settings UI.

## Android layout

Preferred shared root:

```text
/storage/emulated/0/.syntac/
├── syntac.sqlite
├── cache/
├── logs/
├── natives/
├── run/
└── agent/
    ├── SYSTEM.md
    ├── config.yml
    ├── blobs/
    └── sessions/
        ├── chats.jsonl
        ├── attachments.jsonl
        └── sqlite-chat-migration-v1.done
```

`agent/` and `sessions/` match OMP's internal layout while keeping Syntac data under `.syntac`. Runtime binaries stay app-private. API keys and OAuth credentials stay in Android secure storage.

If shared storage permission or filesystem access fails, app-private database/chat paths remain usable. Startup copies legacy private `chats_jsonl/`, shared `.syntac/chats_jsonl/`, and old `.omp/agent/sessions/` files into preferred paths without overwriting newer files.

## Change workflow

1. Keep metadata in SQLite; keep chat-owned runtime data in JSONL.
2. Add migrations for schema or path changes; never discard valid legacy rows.
3. Preserve atomic temp-file replacement, startup recovery, per-file serialization, deleted-chat guards, and bounded text.
4. Keep secrets out of all files, logs, diagnostics, and tool output.
5. Update storage tests, this file, `AGENTS.md`, and `PROJECT_STRUCTURE.md` when ownership or paths change.

## Verification

Run focused persistence tests in `test/app_foundation_test.dart`, then `flutter analyze` and `flutter test`. Shared-storage and runtime changes also need physical Android validation.