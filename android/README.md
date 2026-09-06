# Android Host

`android/` owns Gradle configuration, manifest permissions/components, release packaging, launcher resources, native PRoot libraries, and Kotlin runtime bridge.

Rules:

- Keep namespace/application ID `com.syntac` unless migration is planned across Dart, Android, and release metadata.
- Keep MethodChannel `syntac/runtime` synchronized with Dart contracts.
- Keep Arch rootfs and runtime temporary files app-private; mount user-selected shared project roots.
- Never commit `android/key.properties` or signing secrets.
- Native asset hash/size changes require matching `LocalRuntimeConfig.kt`, scripts, fixtures, and tests.
- Runtime process cancellation must kill process trees; output must stay bounded.
- Storage permission flows must identify current package and expose actionable failure state.

Run focused runtime tests and release APK build. Physical Android validation remains required for native/runtime changes.