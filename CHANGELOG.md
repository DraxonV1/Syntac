# Changelog

## 0.1.1-beta.6

Android Early Access provider, agent-tool, and release-safety update.

### Added

- Current bundled Models.dev catalog with reproducible source SHA-256 and pinned OMP compatibility reference.
- Complete direct DeepSeek thinking/tool protocol with native effort mapping, exact `reasoning_content` replay, and clear rejection of incomplete legacy tool history.
- Native DeepSeek provider choice in onboarding and provider settings.
- Persistent per-chat `todo` tool with bounded phases, tasks, deleted-chat guards, and active progress panel above the composer until work is completed, abandoned, or removed.
- Live running tool cards created from streamed provider arguments before model completion, with in-place argument and execution-output updates.

### Changed

- Google Antigravity tool declarations now follow OMP schema-map traversal: property names are preserved, unsupported schema keywords are stripped only in schema-key positions, and `required` entries are constrained to defined properties.
- `read` returns SHA-256 snapshots; `apply_patch` rejects stale or duplicate inputs before writes, bounds diffs/files, and rolls back earlier changes after in-process write failure.
- Provider transport failures remain inside provider surfaces instead of replacing the whole app with the fatal startup screen.
- Assistant and tool UI updates are coalesced to 33 ms while durable persistence remains separately throttled, preventing widget rebuilds from slowing provider streams.
- Tool code/content cards preview the first 300 lines; copy and maximize retain complete persisted content.
- Stable update channel rejects prereleases and malformed or insecure manifests.
- Release workflow validates source and exact tag/version match, builds signed arm64 candidate artifacts, never force-moves tags, publishes only the matching channel manifest, and opens a generated manifest-sync PR.

### Fixed

- Fixed Google Antigravity HTTP 400 failures where a tool property named `pattern` was stripped while still listed in `required`, producing `property is not defined`.
- Fixed raw Google OAuth DNS/socket failures displaying internal Dart exception text and incorrectly surfacing as global “Startup failed.”
- Fixed large `write` arguments above 12,000 characters decoding as generic raw JSON, which hid content and prevented complete maximize viewing.
- Fixed DeepSeek being registered internally but absent from user-visible provider setup.
- Fixed active todo state existing only in tool cards instead of remaining readable through the chat UI.
- Fixed manual release-candidate manifest generation failing when `build/release` did not exist.
- Corrected beta update metadata validation and kept unpublished stable/nightly channels inert.

### Release metadata

- Android package: `com.syntac`
- Version: `0.1.1-beta.6`
- Version code: `16`
- Default update channel: `beta`


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
