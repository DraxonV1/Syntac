# AGENTS.md

## Scope

This directory owns Android native runtime integration for Syntac.

## Files

- `MainActivity.kt`: MethodChannel `syntac/runtime`, runtime status, storage settings intent, command routing, battery/background permission requests.
- `LocalRuntimeManager.kt`: Arch Linux PRoot install/status/self-test/run/cancel/remove and foreground-service lifecycle.
- `RuntimeForegroundService.kt`: visible Android foreground service keeping long runtime work alive while app is backgrounded.
- `RootfsBundleInstaller.kt`: packaged rootfs verification/extraction/materialization.
- `LocalRuntimeConfig.kt`: pinned runtime manifest, asset names, hashes, sizes.
- `LocalRunResult.kt`: normalized command result and bounded stream readers.
- `TermuxBridge.kt`: Termux RUN_COMMAND integration and callback tracking.
- `TermuxResultService.kt`: receives Termux callback result.
## Change here when

- Changing MethodChannel methods or payloads.
- Changing Arch Linux rootfs install/run behavior.
- Changing native PRoot assets, rootfs bundle, diagnostics, storage permission behavior, or Termux bridge.

## Invariants

- Package/namespace stays `com.syntac`.
- MethodChannel stays `syntac/runtime` unless Dart side changes in same commit.
- Keep rootfs under app-private files; project mounts point to selected shared-storage project path.
- Verify rootfs bundle checksum/manifest before install.
- Bound stdout/stderr and stream updates at 2,000,000 characters per stream.
- `cancelCommand` must kill active process tree.
- Diagnostics must not expose raw secrets and should avoid raw private paths.
- Storage settings action must target current package.

## Tests

Dart-side contract tests live in `test/local_runtime_test.dart` and `test/app_foundation_test.dart`. Native-only behavior also needs physical Android phone validation with release APK.

## Documentation

Keep `README.md` aligned with MethodChannel methods, runtime lifecycle, process cancellation, output limits, storage boundaries, and physical-phone verification. Update `PROJECT_STRUCTURE.md` when native ownership changes.
