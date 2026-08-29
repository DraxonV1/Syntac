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
lib/src/storage/                         SQLite metadata + JSONL chat store
lib/src/tools/                           Model-callable project tools
lib/src/runtime/                         ShellExecutor and runtime adapters
lib/src/ui/                              Screens, onboarding, chat widgets, theme
android/app/src/main/kotlin/com/syntac/  Android runtime bridge and PRoot manager
assets/runtime/                          Packaged Arch rootfs bundle
scripts/                                 Runtime/native packaging scripts
test/                                    Regression tests
```

## Non-negotiable invariants

- Local-first: project files stay in user-selected directories.
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
