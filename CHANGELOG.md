# Changelog

## 0.1.1-beta.4

Android Early Access tooling release.

### Added

- Durable ARCH Linux Runtime job APIs: list, status, bounded logs, live log follow, wait, and cancel.
- Job lifecycle metadata: start/finish timestamps, duration, exit code, terminal state, failure kind, restart count, and log truncation counts.
- Bounded project `glob` discovery for files and directories.
- Explicit read-only systemwide `read` mode for absolute diagnostic paths with sensitive-path blocking.
- Multi-file `apply_patch` tool with project-root validation and atomic file writes.
- Live durable job log updates in tool cards.

### Changed

- `write` cards now show exact content with syntax highlighting; no patch markers or green diff styling.
- `edit` tool replaced by `apply_patch`.
- Runtime job controls expose explicit cancel routing through Android MethodChannel.

### Release metadata

- Android package: `com.syntac`
- Version: `0.1.1-beta.4`
- Version code: `14`
- Default update channel: `beta`
