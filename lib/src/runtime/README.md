# Runtime

`ShellExecutor` selects runtime adapter, streams bounded stdout/stderr, and exposes durable Arch job handles.

## Ownership

- Arch PRoot install, validation, package commands, workspace mounts, cancellation.
- `RuntimeJobSupervisor` owns persistent Arch processes, job registry, bounded logs, restart, and process-tree stop.
- Termux `RUN_COMMAND` bridge and callback handling.
- Local process executor for tests and development.

## Rules

- Android Arch rootfs stays under app-private files; selected project directories remain shared-storage paths.
- Persistent jobs use app-private JSON metadata and bounded stdout/stderr logs; Flutter Activity lifetime must not own their processes.
- Python is installed inside Arch with `pacman`; package installs must pass storage preflight and clear package cache after success.
- Termux uses its external-command bridge and callback service; durable background jobs are Arch-only.
- Command timeout `0` means no deadline; cancellation still kills active process trees.
- Native runtime output is capped at 2,000,000 characters per stream and includes truncation metadata.
- Runtime environment preserves executable paths, home/temp directories, locale, terminal, proxy values, and CA paths.

## Verification

Run `flutter test test/local_runtime_test.dart`, `flutter test test/app_foundation_test.dart`, `flutter analyze`, and release APK build. Validate install, `pacman`/Python command, persistent job after Activity removal, app switching, cancellation, network diagnostics, and storage recovery on physical arm64 Android.