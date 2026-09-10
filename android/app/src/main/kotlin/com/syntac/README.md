# Android Runtime Bridge
## Ownership

- `MainActivity.kt` exposes `syntac/runtime`, routes commands, durable job list/status/log/stop/restart calls, network diagnostics, opens storage settings, and requests battery/notification permissions.
- `LocalRuntimeManager.kt` installs and validates packaged Arch PRoot, preserves runtime environment, runs/cancels commands, starts persistent jobs, bounds streams, and starts/stops foreground work.
- `RuntimeJobSupervisor.kt` owns persistent process records, lifecycle timestamps, exit codes, restart counts, and bounded app-private logs independent of Activity lifetime.
- `RuntimeForegroundService.kt` owns visible long-running runtime notification and stop-all action.
- `RootfsBundleInstaller.kt` verifies and extracts pinned assets.
- `TermuxBridge.kt` and `TermuxResultService.kt` implement Termux callbacks.

## Rules

- Keep rootfs, staging, caches, PRoot temporary files, and runtime metadata under app-private files.
- Mount only selected user project roots; never copy project data into runtime storage.
- Keep process output and persisted job logs bounded at 2,000,000 characters per stream with truncation metadata.
- Classify guest exit failures separately from PRoot/native crashes. Kill active process trees on cancellation and job stop.
- Start foreground service before install, self-test, Arch commands, diagnostics, or persistent jobs; stop it only after all native work ends.
- Persistent jobs restore as interrupted after process-owner restart; never claim they remain alive without a process.
- Request battery-unrestricted and notification access from settings UI; keep fallback behavior when Android declines access.
- Preserve pinned hashes, sizes, ABI checks, and release-build validation when changing runtime assets.

## Verification

Run `flutter test test/local_runtime_test.dart`, `flutter analyze`, and `flutter build apk --release`. Install release APK on physical arm64 Android, grant storage/background access, switch apps during install and commands, then inspect runtime status and cancellation.