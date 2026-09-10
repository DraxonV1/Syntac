# Changelog
## 0.1.1-beta.3

P0 runtime reliability release for Android Early Access.

### Added

- Durable Arch Linux runtime jobs with `background`/`async` Bash execution and `timeout_seconds: 0`.
- App-private runtime job registry and bounded logs with status, logs, stop, restart, and stop-all controls.
- Foreground-service ownership and notification stop action for persistent runtime jobs.
- Arch network diagnostics for DNS, CA certificates, and HTTPS connectivity.
- Explicit command approval for destructive commands, package installation, and persistent services.

### Hardened

- Preserved Arch PATH, proxy, locale, terminal, temporary-directory, and CA environment settings.
- Added process-tree cancellation, crash recovery state, bounded output, port detection, and structured runtime failures.

### Release

- Android package: `com.syntac`
- Version: `0.1.1-beta.3`
- Version code: `13`
- Default update channel: `beta`


## 0.1.1-beta.2

Syntac Early Access Android beta.

### Added

- Local-first Android coding-agent app with on-device project, chat, tool result, provider, runtime, and update state.
- Project browser, chat-based coding agent, markdown/code rendering, expandable tool result cards, and settings diagnostics.
- Google Antigravity / Cloud Code Assist OAuth, ChatGPT Codex OAuth, Grok, and OpenAI-compatible provider support.
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
