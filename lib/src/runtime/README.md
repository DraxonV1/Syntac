# Runtime

`ShellExecutor` selects runtime adapter and streams bounded stdout/stderr.

## Ownership

- Arch PRoot install, validation, package commands, workspace mounts, cancellation.
- Termux `RUN_COMMAND` bridge and callback handling.
- Local process executor for tests and development.

## Rules

- Android Arch rootfs stays under app-private files; selected project directories remain shared-storage paths.
- Python is installed inside Arch with `pacman`; package installs must pass storage preflight and clear package cache after success.
- Termux uses its external-command bridge and callback service; background launches remain permission/status guarded.
- Command cancellation must terminate active process trees.
- Native runtime output is capped at 2,000,000 characters per stream and includes truncation metadata.

## Verification

Run `flutter test test/local_runtime_test.dart`, `flutter test test/app_foundation_test.dart`, `flutter analyze`, and release APK build. Validate install, `pacman`/Python command, app switching, cancellation, and storage recovery on physical arm64 Android.