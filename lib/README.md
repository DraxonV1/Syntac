# Flutter Source

Syntac Flutter code lives under `src/` and is split by responsibility:

- `app.dart`: application controller and orchestration.
- `models.dart`: domain models, enums, serialization, and limits.
- `agent/`: model turns, context, prompts, and cancellation.
- `ai/`: provider transports, OAuth, model registry, and diagnostics.
- `storage/`: SQLite metadata, shared JSONL chat data, migration, and recovery.
- `runtime/`: shell and Android runtime adapters.
- `tools/`: sandboxed model-callable project tools.
- `ui/`: screens, chat, onboarding, reusable widgets, and theme.

Read `../PROJECT_STRUCTURE.md` for full ownership and `../AGENTS.md` for invariants.