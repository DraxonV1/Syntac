# Changelog

## Unreleased

### Added

- Current bundled Models.dev catalog with reproducible source SHA-256 and OMP compatibility reference.
- Complete direct DeepSeek thinking/tool protocol: native effort mapping and exact reasoning replay.
- Persistent per-chat `todo` tool with bounded phases, tasks, and deleted-chat guards.

### Changed

- `read` returns SHA-256 snapshots; `apply_patch` rejects stale/duplicate inputs before writes, bounds diffs/files, and rolls back earlier changes after in-process write failure.
- Stable update channel rejects prereleases and malformed or insecure manifests.
- Release workflow validates source and exact tag/version match, builds arm64 candidate artifacts, never force-moves tags, publishes only matching channel manifest, and opens generated manifest-sync PR.

## 0.1.1-beta.5

Android Early Access tooling release.

### Added

- Durable ARCH Linux Runtime job APIs: list, status, bounded logs, live log follow, wait, and cancel.
- Job lifecycle metadata: start/finish timestamps, duration, exit code, terminal state, failure kind, restart count, and log truncation counts.
- Bounded project `glob` discovery for files and directories.
- Explicit read-only systemwide `read` mode for absolute diagnostic paths with sensitive-path blocking.
- Multi-file `apply_patch` tool with project-root validation and atomic file writes.
- Live durable job log updates in tool cards.
- Direct `!command` Bash execution with persisted user-owned output in agent context.
- ANSI color rendering for Bash and runtime job output.
- Runtime Jobs screen with current-session job details and controls.

### Changed

- `write` cards now show exact content with syntax highlighting; no patch markers or green diff styling.
- `edit` tool replaced by `apply_patch`.
- Runtime job controls expose explicit cancel routing through Android MethodChannel.
- Normal tool-result surfaces are transparent; explicit code and diff viewers retain intentional surfaces.
- Chat opens and switches to latest message automatically.
- Provider reasoning effort/thinking now maps to supported OpenAI, Codex, and Gemini wire formats with bounded sanitized failures and project-local error JSONL.
- Appearance control is a Light/Dark display-mode toggle with readable light-mode syntax and text colors.
### Release metadata

- Android package: `com.syntac`
- Version: `0.1.1-beta.5`
- Version code: `15`
- Default update channel: `beta`
