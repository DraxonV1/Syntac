# Changelog

## 0.1.1-beta.2

Syntac Early Access Android beta.

### Added

- Local-first Android coding-agent app with on-device project, chat, tool result, provider, runtime, and update state.
- Project browser, chat-based coding agent, markdown/code rendering, expandable tool result cards, and settings diagnostics.
- Google Antigravity / Cloud Code Assist OAuth provider flow and OpenAI-compatible provider support.
- Packaged Arch Linux PRoot runtime and Termux `RUN_COMMAND` bridge for project shell commands.
- Public update manifests for stable, beta, and nightly channels.

### Hardened

- JSONL chat storage with atomic writes, malformed-line recovery, legacy SQLite migration coverage, and concurrent update stress tests.
- Startup/onboarding initialization error handling and retry surfaces.
- Provider credential handling: OAuth secrets come from build-time configuration; missing Google OAuth config fails safely.
- Android release automation now requires stable signing secrets before publishing public APKs.

### Release

- Android package: `com.syntac`
- Version: `0.1.1-beta.2`
- Version code: `12`
- Default update channel: `beta`
