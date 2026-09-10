# AGENTS.md

## Scope

This directory owns Android native runtime integration for Syntac.

## Files

- `MainActivity.kt`: MethodChannel `syntac/runtime`, runtime status, storage settings intent, command routing, battery/background permission requests.
- `LocalRuntimeManager.kt`: Arch Linux PRoot install/status/self-test/run/cancel/remove, network diagnostics, environment setup, and foreground-service lifecycle.
- `RuntimeJobSupervisor.kt`: persistent Arch job registry, app-private bounded logs, process ownership, restart/status/log/cancel APIs, lifecycle timestamps, exit codes, truncation counts, and crash recovery state.
- `RuntimeForegroundService.kt`: visible Android foreground service keeping install, command, and persistent job work alive while app is backgrounded.
- `RootfsBundleInstaller.kt`: packaged rootfs verification/extraction/materialization.
- `LocalRuntimeConfig.kt`: pinned runtime manifest, asset names, hashes, sizes.
- `LocalRunResult.kt`: normalized command result and bounded stream readers.
- `TermuxBridge.kt`: Termux RUN_COMMAND integration and callback tracking.
- `TermuxResultService.kt`: receives Termux callback result.

## Change here when
- Changing MethodChannel methods or payloads, including durable job and network diagnostic APIs.
- Changing Arch Linux rootfs install/run behavior.
- Changing native PRoot assets, rootfs bundle, diagnostics, storage permission behavior, or Termux bridge.

## Invariants
- Package/namespace stays `com.syntac`.
- MethodChannel stays `syntac/runtime` unless Dart side changes in same commit.
- Keep rootfs under app-private files; project mounts point to selected shared-storage project path.
- Persistent job metadata/logs stay app-private; process ownership belongs to `RuntimeJobSupervisor`, not Activity.
- Verify rootfs bundle checksum/manifest before install.
- Bound stdout/stderr and stream updates at 2,000,000 characters per stream.
- `cancelCommand`, `stopLocalRuntimeJob`, and `jobs.cancel` must kill active process trees.
- Diagnostics must not expose raw secrets and should avoid raw private paths.
- Storage settings action must target current package.
## Tests

Dart-side contract tests live in `test/local_runtime_test.dart` and `test/app_foundation_test.dart`. Native-only behavior also needs physical Android phone validation with release APK.

## Documentation

Keep `README.md` aligned with MethodChannel methods, runtime lifecycle, process cancellation, output limits, storage boundaries, and physical-phone verification. Update `PROJECT_STRUCTURE.md` when native ownership changes.
