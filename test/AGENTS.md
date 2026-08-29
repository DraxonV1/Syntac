# AGENTS.md

## Scope

Tests protect app contracts, not implementation trivia.

## Files

- `app_foundation_test.dart`: repository, providers, agent loop, tools, storage, controller flows.
- `local_runtime_test.dart`: runtime status/diagnostics parsing and Android runtime fixture expectations.
- `widget_test.dart`: UI components/screens/widgets.
- `fixtures/`: pinned runtime/rootfs fixture data.

## Add tests when

- Observable behavior changes.
- Persistence/migration changes.
- Provider payload/stream/error behavior changes.
- Tool/runtime sandbox/output/cancellation behavior changes.
- UI visible states/actions change.

## Rules

- Prefer focused test by `--plain-name` during development.
- Keep tests deterministic and isolated with temp directories/in-memory DB.
- Do not assert source text or private implementation details.
- For old-data compatibility, seed old rows/maps and assert new model/store behavior.
- For security, assert absence of secrets/raw paths in diagnostics/results.

## Commands

```sh
C:/tools/flutter/bin/flutter.bat test test/app_foundation_test.dart
C:/tools/flutter/bin/flutter.bat test test/local_runtime_test.dart
C:/tools/flutter/bin/flutter.bat test test/widget_test.dart
C:/tools/flutter/bin/flutter.bat test
```
