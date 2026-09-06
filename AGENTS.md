# AGENTS.md

## Purpose

Syntac is a local-first Flutter Android coding agent for Early Access/Beta. Read `PROJECT_STRUCTURE.md` before changing code. Scoped `AGENTS.md` files in subdirectories override/add local rules.

## Product boundary

Do not add cloud DB, telemetry, web app, desktop app, billing, embeddings, MCP/plugin marketplace, SSH/GitHub integration, or account system unless explicitly requested.

Android release is primary. iOS target is intentionally removed/disabled for Early Access.

## Important directories

```text
lib/src/app.dart                         SyntacApp + AppController orchestration
lib/src/models.dart                      Domain models, enums, serialization, caps
lib/src/core/app_identity.dart           Brand, developer, repo, version, update channel
lib/src/agent/                           Agent loop, context, system prompt
lib/src/ai/                              Provider contracts, transports, OAuth
lib/src/storage/                         SQLite metadata + shared JSONL chat store
lib/src/tools/                           Model-callable project tools
lib/src/runtime/                         ShellExecutor and runtime adapters
lib/src/ui/                              Screens, onboarding, chat widgets, theme
android/app/src/main/kotlin/com/syntac/  Android runtime bridge and PRoot manager
assets/runtime/                          Packaged Arch rootfs bundle
scripts/                                 Runtime/native packaging scripts
test/                                    Regression tests
```

## Structure maintenance

- Treat `PROJECT_STRUCTURE.md` as living architecture map. Update it in same change whenever files, directories, ownership, storage roots, or platform boundaries change.
- Preserve this structure across future modifications. Do not silently create parallel folders, duplicate responsibilities, or leave stale tree entries.
- Every owned source directory needs both `AGENTS.md` for binding change instructions and `README.md` for human-facing purpose, boundaries, workflows, and verification guidance when directory complexity warrants it.
- Keep folder documentation actionable: state what belongs there, what must not be added, invariants, dependency boundaries, migration rules, and tests/validation expected.
- Update affected folder `AGENTS.md` and `README.md` whenever behavior or ownership changes, not only when adding files.

## Non-negotiable invariants

- Local-first: project files stay in user-selected directories.
- On Android, user-visible metadata and chat data live under `/storage/emulated/0/.syntac`; app-private storage is reserved for runtime binaries, caches, and platform-required state.
- Shared-storage initialization must be permission-gated and must retain a safe private fallback when access is unavailable.
- Runtime rootfs stays app-private; selected project files stay in user-selected shared-storage directories.
- Tool cards show command/edit intent first, bounded output second; edit cards use line-numbered colored diffs.
- Markdown rendering uses real TeX widgets for math and supports remote/data-URI images without hardcoded symbol substitution.
- Secrets stay in `SecretStore`/secure storage, never SQLite/JSONL/logs/diagnostics.
- SQLite stores metadata; JSONL stores chat-owned runtime data.
- File tools must stay inside project root after realpath/symlink resolution.
- Tool output and stored text must stay bounded.
- Assistant `tool_calls` metadata must remain before matching tool messages.
- Cancellation must stop active tools and must not resume model generation afterward.
- Deleted chats must not accept later messages/jobs/tool executions.
- Provider errors must be sanitized and user-facing.
- Brand strings come from `AppIdentity` where possible.

## Add/remove map

- Provider/model/auth: `lib/src/ai/`, `lib/src/ai/registry/provider_registry.dart`, `lib/src/app.dart`, provider UI, `test/app_foundation_test.dart`.
- Tool: `lib/src/tools/agent_tools.dart`, `AgentLoop` tool list if needed, tool card UI, tests.
- Runtime: `lib/src/runtime/shell_executor.dart`, `android/app/src/main/kotlin/com/syntac/`, runtime UI, local runtime tests.
- Storage: `local_database.dart` for SQLite metadata; `chat_jsonl_store.dart` for chats/messages/jobs/tools/attachments; repository facade; migration tests.
- UI: `lib/src/ui/screens/`, `lib/src/ui/onboarding/`, `lib/src/ui/chat/`, `lib/src/ui/theme/`, widget tests.
- Branding: `AppIdentity`, Android manifest/Gradle, package metadata, tests/docs.
- Updates: `update/*.json`, `lib/src/core/update_service.dart`, `lib/src/app.dart`, home/settings UI, Android `openUrl` bridge, tests.

## Validation

Run focused tests for touched area, then before release claim:

```sh
C:/tools/flutter/bin/flutter.bat analyze
C:/tools/flutter/bin/flutter.bat test
C:/tools/flutter/bin/flutter.bat build apk --release
```

Runtime or storage changes also need physical Android phone validation.
