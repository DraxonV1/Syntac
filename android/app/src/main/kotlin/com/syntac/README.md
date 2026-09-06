# Android Runtime Bridge

## Ownership

- `MainActivity.kt` exposes `syntac/runtime`, routes commands, opens storage settings, and requests battery/notification permissions.
- `LocalRuntimeManager.kt` installs and validates packaged Arch PRoot, runs/cancels commands, bounds streams, and starts/stops foreground work.
- `RuntimeForegroundService.kt` owns visible long-running runtime notification.
- `RootfsBundleInstaller.kt` verifies and extracts pinned assets.
- `TermuxBridge.kt` and `TermuxResultService.kt` implement Termux callbacks.

## Rules

- Keep rootfs, staging, caches, PRoot temporary files, and runtime metadata under app-private files.
- Mount only selected user project roots; never copy project data into runtime storage.
- Keep process output bounded at 2,000,000 characters per stream and return truncation metadata.
- Classify guest exit failures separately from PRoot/native crashes. Kill active process trees on cancellation.
- Start foreground service before install, self-test, or Arch command work; stop it only after all native work ends.
- Request battery-unrestricted and notification access from settings UI; keep fallback behavior when Android declines access.
- Preserve pinned hashes, sizes, ABI checks, and release-build validation when changing runtime assets.

## Verification

Run `flutter test test/local_runtime_test.dart`, `flutter analyze`, and `flutter build apk --release`. Install release APK on physical arm64 Android, grant storage/background access, switch apps during install and commands, then inspect runtime status and cancellation.