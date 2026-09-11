# Runtime

`ShellExecutor` selects runtime adapter, streams bounded stdout/stderr, and exposes current-session Arch job handles. Runtime status stays focused on installation and execution capability; job records live on the Runtime Jobs screen.

## Ownership

- Arch PRoot install, validation, package commands, workspace mounts, cancellation.
- `RuntimeJobSupervisor` owns current-session Arch processes, job registry, bounded logs, restart, status, wait polling, and process-tree stop. Only active records survive process-owner restart; terminal records remain memory-only.
- `RuntimeJobExecutor` exposes Dart-side `listJobs`, `jobStatus`, `jobLogs`, and `cancelJob` capability without coupling tools to Android channels.
- Termux `RUN_COMMAND` bridge and callback handling.
- Local process executor for tests and development.

## Rules

- Android Arch rootfs stays under app-private files; selected project directories remain shared-storage paths.
- Runtime job metadata and bounded stdout/stderr logs stay app-private. Active records may be restored as interrupted after process-owner restart; completed/cancelled records are not persisted.
- Job records preserve start/finish timestamps, duration, exit code, terminal state, failure kind, restart count, and log truncation counts for current-session inspection.
- Python is installed inside Arch with `pacman`; package installs must pass storage preflight and clear package cache after success.
- Termux uses its external-command bridge and callback service; durable background jobs are Arch-only.
- Command timeout `0` means no deadline; cancellation still kills active process trees.
- Native runtime output is capped at 2,000,000 characters per stream and includes truncation metadata.
- Runtime environment preserves executable paths, home/temp directories, locale, terminal, proxy values, and CA paths.

## Verification

Run `flutter test test/local_runtime_test.dart`, `flutter test test/app_foundation_test.dart`, `flutter analyze`, and release APK build. Validate install, `pacman`/Python command, persistent job after Activity removal, app switching, cancellation, network diagnostics, and storage recovery on physical arm64 Android.