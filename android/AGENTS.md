# AGENTS.md

## Scope

`android/` owns the Android host project, Gradle configuration, signing expectations, app manifest, native assets, and Kotlin runtime bridge.

## Files and folders

- `settings.gradle.kts`, `build.gradle.kts`, `gradle.properties`: Android/Gradle project configuration.
- `app/build.gradle.kts`: app namespace, application ID, release signing, native-library packaging, dependencies.
- `app/src/main/AndroidManifest.xml`: app label, permissions, activities, services, metadata.
- `app/src/main/kotlin/com/syntac/`: MethodChannel and runtime implementation.
- `app/src/main/jniLibs/arm64-v8a/`: packaged native PRoot binaries.
- `app/src/main/res/`: launcher icons, launch background, Android styles.

## Invariants

- Package ID stays `com.syntac` unless a release migration plan exists.
- MethodChannel stays `syntac/runtime` unless Dart changes in same commit.
- Release build expects `android/key.properties`; never commit real signing secrets.
- Native assets must match `LocalRuntimeConfig.kt` hashes/sizes.
- Android runtime changes need `test/local_runtime_test.dart` plus physical phone validation when possible.
