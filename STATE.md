---- STATE 1 ----

Implemented:

- Created Flutter app foundation for local-first mobile coding agent.
- Added SQLite schema/repository for projects, chats, messages, tool executions, providers, models, attachments, agent jobs, and settings.
- API keys stored through `flutter_secure_storage`; provider metadata/models only in SQLite.
- Implemented OpenAI-compatible streaming provider with `/v1/models` test, SSE text/tool-call parsing, HTTP error kinds, malformed stream handling, timeout/cancellation token support.
- Implemented cancellable coding-agent loop with bounded context, concise system prompt, structured assistant tool-call history, tool execution persistence, duplicate-run guard, job/chat states, and preflight error persistence.
- Implemented seven project tools: read, write, edit, delete, list, search, bash. File tools validate project-root containment and bound reads/search.
- Implemented Android Termux RUN_COMMAND bridge with permission/package visibility, callback service, background command launch, timeout wrapper, runtime status, and Flutter-side cancellation. V1 uses shared-storage project paths such as `/storage/emulated/0/DraxonCodingAgent/<project>`.
- Implemented iOS runtime channel returning unavailable shell capability and exit 127 for shell commands.
- Added functional UI skeleton for projects, chats, conversation, tool cards, attachments, provider/model settings, agent limits, runtime status, send/stop.
- Added README.md and AGENTS.md with architecture, setup, commands, Termux configuration, and iOS limitations.
- Generated ignored local Android release signing key to build release APK.

Verification:

- `C:/tools/flutter/bin/dart.bat format lib test` passed.
- `C:/tools/flutter/bin/flutter.bat analyze` passed.
- `C:/tools/flutter/bin/flutter.bat test` passed: 11 tests.
- `C:/tools/flutter/bin/flutter.bat build apk --release` passed.
- Release APK: `build/app/outputs/flutter-apk/app-release.apk`, 51,017,037 bytes, SHA-256 `99cd9bafdabcd52196d1f1bf1adc6cb8442566a87d36f327c000bb108109dfce`.
- `flutter build ipa` unavailable on this Windows Flutter toolchain; Xcode/macOS required.

Pending/manual:

- Replace local development Android signing key before distribution.
- On Android device, install Termux, set `allow-external-apps=true`, run `termux-setup-storage`, grant this app Termux RUN_COMMAND permission, grant storage/all-files permissions as needed.
- True Termux process kill on user cancellation remains platform-limited; app cancels pending result and stops further agent loop work.

---- STATE 2 ----

Implemented:

- Designed and implemented near-black developer-focused UI design system (`AppColors`, `AppTypography`, `AppTheme`).
- Created core reusable UI components: `StatusIndicator` (with subtle running pulse), `BadgeChip` (diffs, exit codes, metadata), `AppButton`, `AppIconButton`, `StopButton`, `AppCard`, `AppModal` (bottom sheets and confirmation dialogs).
- Built high-performance `MarkdownContent` with headings, lists, inline code pills, and syntax code blocks with copy actions.
- Built expandable `ToolCallCard` supporting read, write, edit (diff badges `+14 -3`), search (matches list), delete, and bash (stdout/stderr terminal views, exit codes, durations).
- Implemented smart auto-scrolling `ChatMessageList` with threshold detection and floating "Jump to bottom" button.
- Built modern rounded dark `ComposerView` with auto-expanding multiline input (up to 6 lines), attachment preview chips, compact model selector, and dynamic send/stop buttons.
- Implemented `ProjectsScreen` with compact cards, search filtering, empty state, and safe remove confirmations.
- Implemented responsive `ChatSidebar` (drawer on mobile <720px, persistent left panel on tablets >=720px) with grouped history, context menu rename/delete, and connected provider status.
- Implemented `MainChatScreen`, `EmptyChatView`, `ModelSelectorSheet`, and `AgentRunningIndicator`.
- Built comprehensive `SettingsScreen` (Providers, Termux Runtime status directly from backend, Agent Limits, Appearance, About) and `ProviderConfigDialog`.
- Preserved all backend services, SQLite persistence, and agent execution loop.

Verification:

- `dart format lib test`: all files formatted cleanly.
- `flutter analyze`: 0 issues found.
- `flutter test`: 20 tests passed (app foundation, persistence, tools, providers, agent loop, widget rendering, markdown, tools, composer, model sheet).
- `flutter build apk --release`: release APK built successfully (48.8MB).

---- STATE 3 ----

Implemented:

- Fixed release Android networking by moving required `android.permission.INTERNET` into `android/app/src/main/AndroidManifest.xml` and adding `android.permission.ACCESS_NETWORK_STATE`.
- Confirmed debug/profile manifests only carried development INTERNET permission; no flavors or Android network security config exist.
- Added AI provider endpoint validation and transport diagnostics for malformed URL, no network, DNS failure, TLS failure, timeout, HTTP provider response, and malformed stream response.
- Added user-safe AI error mapping for provider tests and agent failures; raw `ClientException`/`SocketException` details now stay in debug logs.
- Fixed `Chat.copyWith` so repository timestamp updates no longer clear persisted chat errors.

Verification:

- Temporary Flutter network probe reached `https://openrouter.ai` through app provider code and received provider-level response instead of DNS/TLS/network failure.
- `flutter clean`, `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build apk --release` passed.
- Release merged manifests include both `android.permission.INTERNET` and `android.permission.ACCESS_NETWORK_STATE`.

---- STATE 4 ----

Implemented:

- Ported OMP Google Antigravity OAuth2 auth-code flow into Dart: loopback callback `127.0.0.1:51121/oauth-callback`, Google scopes, token exchange, refresh-token refresh, userinfo lookup, Cloud Code Assist `loadCodeAssist`, and Antigravity project provisioning.
- Added OAuth credential model and secure-storage persistence; SQLite stores provider metadata only (`provider_key`, `auth_type`), not OAuth tokens.
- Added provider registry skeleton with OpenRouter, DeepSeek, custom OpenAI-compatible, and Google Antigravity provider definitions/capabilities.
- Wired central credential resolution for API-key and OAuth credentials. Agent loop still supports OpenAI-compatible transport only; Google Cloud Code Assist transport is intentionally blocked with a safe error until implemented.
- Provider settings now has Google Antigravity sign-in flow that copies the auth URL and stores OAuth credentials after callback.
- Fixed OpenAI-compatible `/v1` base-path normalization so `https://openrouter.ai/api/v1/` resolves to `/api/v1/models`, not `/api/v1/v1/models`.

Verification:

- OMP reference files used: `packages/ai/src/registry/oauth/google-antigravity.ts`, `google-oauth-shared.ts`, `oauth/types.ts`, `registry/google-antigravity.ts`, `providers/google-gemini-cli.ts`, catalog Antigravity descriptor/discovery.
- Added tests for OAuth credential storage, OpenAI-compatible URL normalization, Antigravity auth URL/token exchange/userinfo/project discovery/refresh.
- `dart format lib test` passed.
- `flutter analyze` passed.
- `flutter test` passed: 25 tests.
- `flutter build apk --release` passed after clearing a Windows file lock; APK `build/app/outputs/flutter-apk/app-release.apk`, 51,494,269 bytes.

---- STATE 5 ----

Implemented:

- Replaced generic provider failure UI with sanitized `ProviderErrorDetails` containing provider, model, endpoint, method, HTTP status, error type, safe response body/exception, stream state, and chunk count.
- Wired Google Antigravity to Cloud Code Assist SSE transport instead of blocking it from the agent loop: POST `/v1internal:streamGenerateContent?alt=sse`, Antigravity user agent, OAuth structured credentials, model wire routing, tool declarations, and function-call parsing.
- Fixed visible streaming by inserting an assistant placeholder immediately, updating message content during provider chunks, throttling persistence, and notifying UI during the run.
- Hardened project path V1 around one real shared-storage filesystem path; rejects URI paths and Android non-shared-storage paths for new projects. File tools and bash use the same `project.folderPath`.
- Improved bash results: schema accepts `timeout_seconds`, output includes command, workingDirectory, success, category, failureKind, stdout/stderr/exitCode/duration, and distinguishes Termux callback failure from real command timeout.
- Added Settings developer diagnostics: project ID/path, file-tool root, bash cwd, writable roundtrip, Termux status, `echo hello`, `pwd`, and `ls -la` self-test output.
- Removed DeepSeek examples/test fixtures from UI/tests; only the intentional built-in provider registry entry remains.

Verification:

- `dart format lib test` passed.
- `flutter clean`, `flutter pub get`, `flutter analyze`, `flutter test` passed: 29 tests.
- `flutter build apk --release` passed; APK `build/app/outputs/flutter-apk/app-release.apk`, 51,608,957 bytes.
- Final `DeepSeek|deepseek` search found only `lib/src/ai/registry/provider_registry.dart` built-in provider definition.

---- STATE 6 ----

Implemented:

- Fixed tool-result UI by making `ToolCallCard` read the canonical `ToolExecution.resultJson` envelope (`ok` plus structured `result`) instead of assuming flat Bash fields. Bash cards now show command, working directory, stdout, stderr, exit code, duration, category, failure kind, empty output markers, truncation markers, and copy actions.
- Generalized expandable result rendering for read/write/edit/delete/list/search/bash and ensured `AgentLoop` notifies UI when tool executions start and when results arrive, so cards appear running before the agent turn completes.
- Added bounded Bash output persistence with explicit truncation metadata, while preserving structured fields sent to the model.
- Added real streaming diagnostics in assistant message metadata: request start, first network chunk, first provider event, first text delta, first UI delta, completion time, and `realStreamingObserved`.
- Preserved Google/Gemini thought signatures by storing provider metadata on `AIToolCall`, persisting it in assistant metadata, and resending it on subsequent Cloud Code Assist requests without showing signature values in UI.
- Normalized Termux background restriction into `termux_background_restricted`; foreground-only V1 now interrupts the agent, preserves tool history, and shows a clear return-to-app message instead of a fake timeout or generic Bash failure.
- Expanded Termux runtime status/diagnostics with app foreground, launch state, last bridge result, and last runtime error category. No foreground service, WorkManager, background isolate, or app-closed execution was added.
- Updated system prompt to trust structured runtime/tool errors and avoid speculative retries.

Verification:

- `node C:/Users/Administrator/.omp/agent/skills/impeccable/scripts/detect.mjs --json lib/src/ui/chat/tool_call_card.dart` returned `[]`.
- `DeepSeek|deepseek` search found only `lib/src/ai/registry/provider_registry.dart` built-in DeepSeek provider/model definition.
- Fake streaming search for `typewriter|replay|collect full|character-by-character|animate.*response` found no matches.
- Required sequence passed: `flutter clean`, `flutter pub get`, `flutter analyze`, `flutter test` (33 tests), `flutter build apk --release`.
- Release APK: `build/app/outputs/flutter-apk/app-release.apk`, 51,658,109 bytes.

---- STATE 7 ----

Implemented:

- Added selectable shell runtime architecture with `ShellRuntimeId.termux` and `ShellRuntimeId.draxonLocal`, persisted in SQLite `settings.shell_runtime`.
- Kept Bash tool schema stable while routing command execution through selected `ShellExecutor`; normalized results include runtime id, category, failure kind, stdout/stderr, exit code, duration, timeout, and cancellation.
- Kept current Termux RUN_COMMAND bridge and foreground/background restriction handling.
- Added Draxon Local Runtime skeleton on Android: private execution storage under app files, user-visible `.draxon` directories for config/logs/shared runtime data, install/remove actions, and explicit `LocalRuntimeLauncherMissing` command result.
- Draxon Local Runtime intentionally does not claim ready, download Alpine, expose `apk`, or run shell commands because Android 10+ blocks execve from writable app data and no packaged native PRoot/JNI launcher is present in this APK.
- Settings now lets user select Termux vs Draxon Local Runtime, shows each runtime status/details, and provides install/remove controls without redesigning settings.
- Added non-Android guards for Draxon Local install/remove so desktop tests/UI do not hit missing platform channels.

Blocked:

- Live Termux command matrix and Gemini-with-Termux Bash require an attached Android device with Termux configured.
- Local runtime command matrix, Gemini-with-local Bash, Alpine rootfs install/checksum, bind mount, `apk`, and bash-in-base-runtime require packaged native PRoot launcher plus Android device validation.

Verification:

- `dart format lib test` passed.
- `flutter analyze` passed.
- `flutter test` passed: 34 tests.
- `flutter build apk --release` passed; APK `build/app/outputs/flutter-apk/app-release.apk`, 51,985,821 bytes.
- `DeepSeek|deepseek` search found only `lib/src/ai/registry/provider_registry.dart` built-in provider/model definition.

---- STATE 8 ----

Implemented:

- Hardened Gemini history continuity: `ContextBuilder` now drops incomplete assistant/tool exchanges instead of sending a model turn with only a subset of required function responses.
- Added Cloud Code Assist request preflight that records a structural trace and rejects malformed Gemini turn ordering before HTTP, including missing/partial functionResponse groups.
- Preserved provider-native Gemini parts and tool metadata while testing text+functionCall replay in one model turn and functionResponse name recovery.
- Added Google Antigravity OAuth refresh in normal agent execution: proactive refresh within 5 minutes of expiry, persist refreshed credential, and exactly one same-credential refresh/replay on initial 401 before any stream output.
- Confirmed packaged native PRoot/local runtime remains blocked: current checkout has no Android PRoot source, JNI wrapper, Gradle/NDK build, or attached Android/Termux device for live RUN_COMMAND validation.

Verification:

- `dart format lib test` passed.
- `flutter analyze` passed.
- `flutter test` passed: 39 tests.
- `flutter build apk --release` passed; APK `build/app/outputs/flutter-apk/app-release.apk`, 52,018,589 bytes.
- Settings UI detector returned `[]`.
- `DeepSeek|deepseek` search found only `lib/src/ai/registry/provider_registry.dart` built-in provider/model definition.

---- STATE 9 ----

Implemented:

- Integrated pinned upstream PRoot source under `third_party/proot` at tag `v5.4.0`, commit `bd5a5f63d72f8210d8cee76195eb9f0749e5bd70`, with uthash submodule `e493aa90a2833b4655927598f169c31cfcdf7861`.
- Added reproducible Android arm64 PRoot build scripts: `scripts/build_android_proot.py` and `scripts/build_android_proot.ps1`.
- Added local talloc compatibility shim under `native/talloc_compat` so PRoot links into a single Android PIE executable artifact.
- Built and packaged `android/app/src/main/jniLibs/arm64-v8a/libdraxon_proot.so`; Gradle packages it as `lib/arm64-v8a/libdraxon_proot.so`.
- Implemented Android Draxon Local Runtime manager: ABI/launcher checks, Alpine 3.20.3 download, SHA256 verification, private rootfs extraction via `/system/bin/tar`, DNS initialization, PRoot command execution with `/workspace` bind, timeout/cancel, install recovery, remove/reset, and diagnostics.
- Updated Dart runtime channel usage with command IDs/cancel for local runtime and added installer states.
- Settings now exposes Install, Remove, Reset, Retry, Run runtime test, and Copy diagnostics.

Verification:

- `python scripts/build_android_proot.py` passed and copied final native artifact into `jniLibs`.
- `llvm-readelf -h -d` on packaged/extracted APK native entry confirmed ELF64 AArch64, type DYN/PIE, deps `libdl.so` and `libc.so`.
- `dart format lib test` passed.
- `flutter analyze` passed.
- `flutter test` passed: 42 tests.
- `flutter build apk --release` passed; APK `build/app/outputs/flutter-apk/app-release.apk`, 23,665,359 bytes.
- APK contains `lib/arm64-v8a/libdraxon_proot.so`, uncompressed entry size 165,688 bytes, compressed size 62,863 bytes.

Pending/manual:

- Final PRoot/Alpine execution verification pending physical Android arm64 device; no ADB/device/emulator available in this session.

---- STATE 10 ----

Implemented:

- Reworked Android `LocalRuntimeManager` install pipeline for Draxon Local Runtime only.
- Added guaranteed private `PROOT_TMP_DIR` at `<filesDir>/runtime/tmp`; every PRoot `ProcessBuilder` now verifies write/delete probe and injects `PROOT_TMP_DIR` into process environment.
- Fixed rootfs gating: normal command execution now requires metadata `ready=true` and critical rootfs validation. Installer validates rootfs before self-test, so `/bin/sh` is not launched while rootfs is missing/incomplete.
- Stopped status recovery from deleting runtime/cache merely because metadata says `ready=false`; it now only cleans stale `alpine.installing`.
- Installer now downloads to private cache, records HTTP/byte/checksum diagnostics, verifies Alpine SHA256, extracts atomically into `runtime/alpine.installing`, validates, then renames to `runtime/alpine`.
- Extraction stays through `/system/bin/tar`; diagnostics count symlink entries and validate `/bin/sh` symlink target. Rootfs validation requires `/bin/sh`, `/bin/busybox`, `/sbin/apk`, `/etc/alpine-release`, plus `/bin`, `/usr`, `/etc`.
- Self-test is layered: first minimal `proot -r ROOTFS -w / /bin/sh -c "echo hello"`, then workspace bind `pwd && ls -la`; default command args no longer bind `/dev` or `/proc`.
- Added Dart regression coverage for detailed installer diagnostics.

Verification:

- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed, 0 files changed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 43 tests.
- Downloaded Alpine archive SHA matched pinned `041fa34a81788242df9e78fa69b97ab45b8ec47ddbf88864755610414a7bf3de`; temporary archive removed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 23,670,435 bytes.
- APK contains `lib/arm64-v8a/libdraxon_proot.so`.

Pending/manual:

- Real Android phone install/runtime execution still pending. Next phone test should paste app diagnostics if install does not reach Ready or `echo hello` fails.

---- STATE 11 ----

Implemented:

- Reproduced Alpine 3.20.3 aarch64 archive on RDP: downloaded `build/alpine-minirootfs-3.20.3-aarch64.tar.gz`, size 3,947,906 bytes, SHA256 matched `041fa34a81788242df9e78fa69b97ab45b8ec47ddbf88864755610414a7bf3de`.
- Inspected real archive layout: entries use `./bin/`, `./usr/`, `./etc/` prefixes, not bare `bin/`; `./bin/sh` is a symlink to `/bin/busybox`; `./bin/busybox`, `./sbin/apk`, and `./etc/alpine-release` exist.
- Added `test/fixtures/alpine_3_20_3_aarch64_structure.json` and a Flutter test that validates the pinned archive layout; if the downloaded archive exists, the test also runs local `tar -tzf/-tvzf`.
- Centralized local runtime version/artifact data into `LocalRuntimeManifest`/`AlpineRuntimeArtifact` while keeping Alpine pinned to 3.20.3.
- Reworked Android extraction diagnostics: exact `/system/bin/tar` argv, archive/destination, destination existence before/after, tar exit code/stdout/stderr, archive entry counts, extracted filesystem counts, staging top-level names, final top-level names.
- Added forensic install timeline events: staging created, tar started/exit, staging exists/top-level after tar, staging/final validation, rename, rootfs-ready metadata, self-test start/result, ready metadata.
- Split diagnostics between staging and final rootfs. Removed ambiguous single `Rootfs directory exists: false`.
- Added persisted `installInProgress` lock plus in-memory `installRunning`; status/diagnostics can inspect but recovery only deletes staging after an interrupted install with no active installer.
- Cleanup now records deleted path, reason, and success.
- Install flow validates `runtime/alpine.installing` before rename, then validates `runtime/alpine` after rename. Self-test starts only after final rootfs validation and rootfs-ready metadata.

Verification:

- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- First `flutter test` failed only because Windows tar output had CRLF; test fixed with `trimRight()`.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 44 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 23,676,259 bytes.
- APK contains `lib/arm64-v8a/libdraxon_proot.so`.

Pending/manual:

- Real phone install/runtime still pending. Next diagnostics should show whether staging validates and whether final rename/self-test succeeds.

---- STATE 12 ----

Implemented:

- Fixed Draxon Local Runtime rootfs validation bug exposed by phone diagnostics.
- Root cause: Alpine `/bin/sh` is an absolute Linux symlink to `/bin/busybox`. Android/Java `File.exists()` follows it against host root, so `<rootfs>/bin/sh.exists()` returned false even though symlink entry existed and `<rootfs>/bin/busybox` existed.
- Added rootfs-aware symlink resolution in `LocalRuntimeManager`: no-follow entry existence via `Os.lstat`, `Os.readlink`, absolute symlink targets resolved inside the rootfs, relative targets resolved against link parent, lexical normalization, root containment check, cycle/depth guard.
- Critical rootfs paths now validate via rootfs semantics: `/bin/sh`, `/bin/busybox`, `/sbin/apk`, `/etc/alpine-release`.
- Diagnostics now distinguish `/bin/sh entry exists`, `/bin/sh exists` (rootfs-valid), link target, resolved rootfs target, and resolved target exists for staging/final rootfs.
- Added Flutter unit test modeling `rootfs/bin/sh -> /bin/busybox`, relative `sh -> busybox`, and chained symlink behavior without host-root lookup.

Verification:

- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 45 tests.
- First release build failed because `initializeRootfs()` still referenced removed `resolveRootfsLink`; fixed to call `resolveRootfsSymlink`.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 23,677,951 bytes.
- APK contains `lib/arm64-v8a/libdraxon_proot.so`.

Pending/manual:

- Real phone should now pass staging/final rootfs validation and proceed to first PRoot `/bin/sh -c "echo hello"` self-test.

---- STATE 13 ----

Implemented:

- Studied Android PRoot references: skirsten portable example, Termux fork, green-green-avk Android fork, and AnotherTerm Android10Essentials plugin.
- Root cause now narrowed: targetSdk 29+ cannot `execve()` app-writable files. Our PRoot launcher was packaged in `nativeLibraryDir`, but its embedded loader still extracted into `files/runtime/tmp` via `PROOT_TMP_DIR`, so guest `/bin/sh` startup could still fail with EACCES.
- Built and packaged a native-library loader at `lib/arm64-v8a/libdraxon_proot_loader.so` and set `PROOT_LOADER` for every PRoot process. Embedded loader remains fallback, but normal phone path now executes loader from extracted APK native-library storage.
- Made PRoot invocation closer to Android references: `--link2symlink`, `-0`, binds `/dev`, `/proc`, `/sys`, `/system`, `/storage` when present, `/usr/bin/env HOME=/root PATH=/bin:/usr/bin:/sbin:/usr/sbin`, and minimal process environment with `PROOT_TMP_DIR` plus `PROOT_LOADER`.
- Added diagnostics for target SDK, native loader path/existence/executable bit/mode, and final BusyBox mode. Manifest now explicitly sets `android:extractNativeLibs="true"`.

Verification:

- `python scripts/build_android_proot.py` passed and copied `libdraxon_proot.so` plus `libdraxon_proot_loader.so` into `android/app/src/main/jniLibs/arm64-v8a/`.
- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 45 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 23,683,296 bytes.
- APK contains `lib/arm64-v8a/libdraxon_proot.so` and `lib/arm64-v8a/libdraxon_proot_loader.so`.

Pending/manual:

- Real phone test still required. Expected next outcome: install reaches Ready and `echo hello` returns `hello`; otherwise diagnostics should identify whether native loader exec, guest ELF mmap, ptrace/seccomp, or shell command failed.

---- STATE 14 ----

Implemented:

- Replaced active Draxon Local Runtime with `coderredlab/proroot` v1.2.8. Old `libdraxon_proot.so`/Alpine/proot-me invocation removed from APK active path; legacy `runtime/alpine*` data is only cleaned during install/reset.
- Added pinned manifest `DraxonRuntimeManifest`: five official proroot release binaries, SHA256/size/source/license, and Ubuntu Base 24.04.4 arm64 rootfs URL/SHA/size.
- Downloaded official proroot v1.2.8 binaries and packaged unmodified under `android/app/src/main/jniLibs/arm64-v8a/`: `libproroot.so`, `libproroot-runtime.so`, `libproroot-linker.so`, `libproroot-bridge.so`, `libproroot-stub-loader.so`.
- Added Gradle `keepDebugSymbols` for `**/libproroot*.so`; verified APK entries match upstream SHA and are not stripped.
- Switched install flow to Ubuntu Base: download, SHA verify, extract to `runtime/ubuntu.installing`, initialize DNS/tmp perms, validate, atomic rename to `runtime/ubuntu`, validate, run proroot self-test.
- Proroot command: `libproroot.so -r <rootfs> -0 --link2symlink [-b <project>:/workspace] -b /dev -b /proc -b /sys -b /system -b /storage -w <dir> /bin/bash -lc <command>` for user commands; self-test starts with `/bin/sh -c \"echo hello\"`.
- Rootfs validation handles Ubuntu symlinked layout (`bin -> usr/bin`, `usr/bin/sh -> dash`) and requires bash, apt, apt-get, dpkg, os-release, and arm64 dynamic linker.
- Added diagnostics for proroot components, license/attribution, rootfs SHA/extraction/validation, safe argv, last output, and proroot log tail.
- Updated Settings text to Ubuntu/proroot and added Ubuntu archive fixture `test/fixtures/ubuntu_base_24_04_4_arm64_structure.json`.

Verification:

- Official proroot SHA256 matched all five downloaded files; `llvm-readelf` showed ELF64 AArch64 for each.
- Ubuntu Base archive downloaded: `build/ubuntu-base-24.04.4-base-arm64.tar.gz`, 29,870,567 bytes, SHA256 `04207713ece899c3740823d33690441ad3a7f0ded1101aca744e2b0f37ac7ff2`.
- Local archive inspection: 3,413 entries; `bin -> usr/bin`, `usr/bin/sh -> dash`, `usr/bin/bash`, `usr/bin/apt`, `usr/bin/apt-get`, `usr/bin/dpkg`, `etc/os-release`, and `usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1` present; CA bundle absent in base rootfs.
- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- First full `flutter test` attempt hit host disk-full temp error; freed temp space; later `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 45 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 23,873,080 bytes, SHA256 `7237bdea5f3e2e17abb7a8a0c334b7b1237d02e343e16e502036f1495e49768f`.
- APK contains all five proroot `.so` files with upstream SHA256 and does not contain `lib/arm64-v8a/libdraxon_proot.so`.

Pending/manual:

- Real phone execution still pending. Expected install should download Ubuntu Base, reach Ready, and pass `echo hello`, `pwd`, `cat /etc/os-release`, and `apt-get --version`. `apt-get update` still needs phone network validation.

---- STATE 15 ----

Implemented:

- Replaced Android `/system/bin/tar` extraction in Draxon Local Runtime with app-owned `RootfsExtractor` using Apache Commons Compress 1.28.0.
- Extractor handles Ubuntu Base tar.gz entries under app control: directories, regular files, symlinks, hard links, Unix modes, `./` prefixes, safe lexical path normalization, absolute-path rejection, `..` traversal rejection, and root containment.
- Hard links are queued then materialized after normal entries. Native `Os.link()` is attempted first; if Android rejects it, target file content is copied to the destination and mode restored. Fallback details and native/copy counts are persisted.
- Verified exact Ubuntu hard-link metadata on RDP archive: `usr/bin/perl5.38.2` is a hard link to `usr/bin/perl`; `usr/bin/uncompress` is a hard link to `usr/bin/gunzip`.
- Replaced tar diagnostics with extractor diagnostics: archive type counts, created entry counts, hard-link counts, bytes, duration, success, warnings, error, and fallback details.
- Extended `test/fixtures/ubuntu_base_24_04_4_arm64_structure.json` with hard-link counts and exact critical metadata for perl/gunzip hard-link pairs.

Verification:

- Ubuntu archive inspection: total 3,413 entries; directories 655; regular files 2,562; symlinks 194; hard links 2; other 0.
- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed: no issues.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 45 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 24,015,694 bytes, SHA256 `7e7da63255cb291e56ead582bfc9e01478ecd4e1b51d9591db657910571ddccc`.
- APK still contains all five proroot files with expected SHA256:
  - `lib/arm64-v8a/libproroot.so` `a4e74d75b66cdc02b080adfe863dbf9951c3b30610d77beddc95488d5fe5de01`
  - `lib/arm64-v8a/libproroot-runtime.so` `8c47a0a7db32d84c179ebb5bf3640f655a3181860ece5886ae44d92858730c34`
  - `lib/arm64-v8a/libproroot-linker.so` `51a0ec5bfed00e572a0de09e22d9057e2befc386b78e426613d3e0ab03f4ecee`
  - `lib/arm64-v8a/libproroot-bridge.so` `1c5bc9537a270e8bf8b1c70222813f57b60b828bfb5503ddf8fe37685092de2f`
  - `lib/arm64-v8a/libproroot-stub-loader.so` `06c6624db3bdc45b9ced151cd781df439a37b47731d244b93e9d6a58cd48cde0`

Pending/manual:

- Real phone validation still pending. Next expected diagnostics: cached Ubuntu archive reused or downloaded, SHA match, extractor success true, archive hard links 2, staging validation pass, atomic rename success, final validation pass, self-test attempted true, then proroot `/bin/bash -lc "echo hello"` stdout `hello`.

---- STATE 16 ----

Implemented:

- Current-session change superseded STATE 15 extractor path. Removed active Android upstream Ubuntu TAR parsing and removed Apache Commons Compress dependency/`RootfsExtractor.kt`.
- Added deterministic build-time rootfs preparation script `scripts/prepare_draxon_rootfs.py`. It downloads/verifies pinned Ubuntu Base 24.04.4 arm64 when needed, parses source tar.gz off-device with Python `tarfile`, validates critical rootfs paths, validates usrmerge links, verifies known hard links, deduplicates blobs, and emits bundle format v1.
- Generated bundled runtime asset `assets/runtime/draxon-rootfs-v1.bundle`: deterministic ZIP with `manifest.json` plus `blobs/<sha256>`. Manifest explicitly represents directories, files, modes, symlinks, hard links, file blob refs, sizes, and checksums.
- Added asset to `pubspec.yaml`; release APK packages it as `assets/flutter_assets/assets/runtime/draxon-rootfs-v1.bundle`.
- Added Android `DraxonRootfsBundleInstaller`: copies bundled asset from APK to app-private cache, verifies size/SHA, parses only Draxon bundle manifest, materializes files into `files/runtime/ubuntu.installing`, creates symlinks, tries native hard links, falls back to copying target file bytes, then existing validation/final rename/self-test flow continues.
- Install flow is offline: no Ubuntu download, no mirror diagnostics, no `/system/bin/tar`, no upstream TAR parser on Android. Old Alpine paths and old Ubuntu cache files are cleaned during install/reset without touching projects/chats/credentials.
- Runtime versioning added: `draxon-runtime-v1` maps to proroot v1.2.8 + Ubuntu Base 24.04.4 arm64 + bundle format v1.
- Settings copy updated: bundled offline Ubuntu/proroot runtime; install status shows Preparing/Installing/Validating/Testing/Ready.

Verification:

- Source Ubuntu archive: `build/ubuntu-base-24.04.4-base-arm64.tar.gz`, size 29,870,567, SHA256 `04207713ece899c3740823d33690441ad3a7f0ded1101aca744e2b0f37ac7ff2`.
- Build-time archive counts from Python `tarfile`: total 3,413; directories 655; regular files 2,562; symlinks 194; hard links 2; other 0; unique blobs 2,436.
- Known hard links preserved: `usr/bin/perl5.38.2 -> usr/bin/perl`, `usr/bin/uncompress -> usr/bin/gunzip`.
- Bundle size: 29,955,868 bytes; SHA256 `268e11876019c20e5216314a5ce93f53fe2f1f68cba56c39de8806c8f6fe291e`; manifest entries 3,413.
- `python scripts/prepare_draxon_rootfs.py --self-test` passed.
- `python scripts/prepare_draxon_rootfs.py --inspect` passed and reported expected counts/hard links.
- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed: no issues.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 46 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 53,314,018 bytes, SHA256 `0db5f3ccbbe444a64346b4845e9806ed59ca0e510796c9c2a5ffe14ffeefcb60`.
- Previous APK size before bundling rootfs: 24,015,694 bytes. New APK size: 53,314,018 bytes.
- APK inspection confirmed rootfs asset present with SHA256 `268e11876019c20e5216314a5ce93f53fe2f1f68cba56c39de8806c8f6fe291e`, manifest entries 3,413, and all five proroot v1.2.8 libs still packaged with expected SHA256. `libdraxon_proot.so` remains absent.

Pending/manual:

- Real Android phone validation still pending. Expected next flow: install APK, Settings → Draxon Local Runtime → Install Local Shell, no Ubuntu download, then Preparing → Installing → Validating → Testing → Ready. If self-test reaches `Self-test attempted: true` and proroot fails, next bug is concrete proroot execution, not filesystem installation.

---- STATE 17 ----

Implemented:

- Updated Draxon Local Runtime command invocation using proroot README/tag docs and packaged binary strings. Both main and v1.2.8 README document `-b <host>` / `-b <host>:<guest>`, but packaged v1.2.8 `libproroot.so` contains usage string `[-b host:guest]` and error string `bad bind format (expected host:guest)`, so release binary appears stricter than README.
- Verified packaged `libproroot.so`: official v1.2.8 release asset, 43,624 bytes, SHA256 `a4e74d75b66cdc02b080adfe863dbf9951c3b30610d77beddc95488d5fe5de01`, ELF64 AArch64, matches downloaded official release byte-for-byte.
- Removed all default optional binds from runtime command construction. No default `-b /dev`, `/proc`, `/sys`, `/system`, `/storage`.
- Added explicit command builders:
  - minimal runtime: `libproroot.so -r <rootfs> -0 --link2symlink -w /root /bin/sh -c <command>`
  - workspace: `libproroot.so -r <rootfs> -0 --link2symlink -b <project>:/workspace -w /workspace /bin/bash -lc <command>`
- Self-test now starts with exact README-style `/bin/sh -c "echo hello"` with no binds. Later stages run `/bin/sh -c "pwd"`, `/bin/sh -c "cat /etc/os-release"`, `/bin/sh -c "apt-get --version"`, `/bin/bash -lc "echo hello"`, and workspace bind `pwd && ls -la`.
- Self-test diagnostics now record each stage with argv, exit, stdout, stderr. App also attempts `libproroot.so --help` on phone and stores complete captured stdout/stderr for diagnostics.
- Proroot environment is now minimal: only `PROROOT_TMP_DIR` is set. Removed `PROROOT_LOG_APPEND` from launched process environment.
- Install now reuses existing final rootfs when runtime version matches and validation passes. It skips bundle materialization and reruns self-test only. Added `retryLocalRuntimeTest` channel and Settings `Retry Runtime Test` button when diagnostics show `Rootfs installed: true` but runtime is not ready.

Verification:

- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed: no issues.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 46 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 53,325,134 bytes, SHA256 `1c763a8eb0b3494ff69e164273602f45059f51e1c77ee498b4257994359c498f`.
- APK inspection confirmed bundled rootfs asset present with SHA256 `268e11876019c20e5216314a5ce93f53fe2f1f68cba56c39de8806c8f6fe291e`, manifest entries 3,413, and all five proroot v1.2.8 libraries present with expected SHA256. `libdraxon_proot.so` remains absent.

Pending/manual:

- Real Android phone validation still pending. Next expected phone path: if rootfs already validates, tap `Retry Runtime Test`; otherwise Install Local Shell. Diagnostics should show Self-test 1 argv exactly `libproroot.so -r <rootfs> -0 --link2symlink -w /root /bin/sh -c <command>`, no binds, stdout `hello`, exit `0`. If it fails, diagnostics include exact stage stdout/stderr and phone-captured `libproroot.so --help`.

---- STATE 18 ----

Implemented:

- Changed Draxon Local Runtime workspace model from single `/workspace` bind to stable per-project guest paths: `/workspace/<mount-name>`.
- Added `Project.mountName` persistence, DB schema v3, unique mount-name generation, and repository `listProjects()` for available workspace binds.
- Dart runtime now sends active project plus all registered projects to Android `runLocalCommand`; diagnostics show active/available mount names.
- Android runtime now materializes `/workspace` and project mountpoint directories inside rootfs, binds each host project as `-b <host>:/workspace/<mount-name>`, and runs active project commands with `-w /workspace/<mount-name>`.
- Self-test stage 6 now verifies multi-project workspace semantics: active cwd, `/workspace` listing, sibling project access, bash, apt-get, and Linux-side write coherence.
- Settings diagnostics now evaluate `pwd` against `/workspace/<mount-name>` for Draxon Local Runtime. `Retry Runtime Test` reuse semantics remain from prior state.

Verification:

- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed: no issues.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 47 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 53,332,282 bytes, SHA256 `e689d111efe052c0c3dbfd3399b431c4b0c62eb1c863704ed3f18b9e64348530`.
- APK inspection confirmed rootfs asset present with SHA256 `268e11876019c20e5216314a5ce93f53fe2f1f68cba56c39de8806c8f6fe291e`; all five proroot v1.2.8 libraries still present with expected SHA256; `libdraxon_proot.so` remains absent.

Pending/manual:

- Real Android phone validation still pending. Expected next phone path: install APK, Settings → Draxon Local Runtime. If rootfs already validates, tap `Retry Runtime Test`; otherwise `Install Local Shell`. Expected self-test stage 6 cwd is `/workspace/<mount-name>`, sibling projects appear under `/workspace`, Linux write creates file in Android project folder, and normal commands run in active project cwd.

---- STATE 19 ----

Implemented:

- Added Draxon Local Runtime AUXV diagnostics for Python/glibc SIGSTKSZ crash triage.
- Host Android diagnostics now parse `/proc/self/auxv` and report `AT_MINSIGSTKSZ`, `AT_PAGESZ`, `AT_HWCAP`, `AT_HWCAP2`, `AT_PLATFORM`, kernel `uname -a`, Android release, SDK, and supported ABIs.
- Guest diagnostics now compare proroot loader modes: default, `--static-loader`, and `--no-static-loader`.
- Each loader mode runs `/bin/sh -c "echo hello"`, `LD_SHOW_AUXV=1 /bin/true`, `getconf MINSIGSTKSZ; getconf SIGSTKSZ`, and `python3 -c "print(1)"`; results capture exit, stdout, stderr, and runtime signal.
- Failing Python diagnostics run with `PROROOT_VERBOSE=1` and `PROROOT_LOG_APPEND=<private app log>`; diagnostics show bounded proroot log tail.
- Runtime stores `selectedLoaderMode`; normal project commands use that mode. Selection stays `default` unless phone diagnostics prove Python or `getconf MINSIGSTKSZ` needs `static`/`no-static`.
- Proroot exit codes like 139 now classify as `runtime_signal` with `runtimeSignal=SIGSEGV` and `guestExitCode=139` instead of generic command failure.
- Checked public proroot releases: GitHub latest remains v1.2.8, so there is no newer official release to A/B yet. v1.2.8 notes mention Python 3.12.3 tested, but no public `AT_MINSIGSTKSZ`/auxv fix.

Verification:

- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed: no issues.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 48 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 53,338,458 bytes, SHA256 `61056e7f2c7dcd392b5fa670edd013b43ddebae27c14d2f001d1dcfe0beca1b2`.
- APK inspection confirmed rootfs asset SHA256 `268e11876019c20e5216314a5ce93f53fe2f1f68cba56c39de8806c8f6fe291e`; all five proroot v1.2.8 libs remain packaged with expected SHA256; `libdraxon_proot.so` remains absent.

Pending/manual:

- Phone values still required for exact root cause. Next run: install APK, Settings → Draxon Local Runtime → Retry Runtime Test. Report `AUXV TEST` block: host `AT_MINSIGSTKSZ`, guest `AT_MINSIGSTKSZ`, loader-mode comparison, selected loader mode, Python exit/stdout/stderr, and proroot log tail.

---- STATE 20 ----

Implemented:

- Replaced bundled Draxon Local Runtime rootfs from Ubuntu Base 24.04.4 arm64 to official Ubuntu Base 22.04.5 LTS arm64 (Jammy), keeping proroot v1.2.8 binaries and runtime command model unchanged.
- Updated `scripts/prepare_draxon_rootfs.py`, Android `DraxonRuntimeManifest`, rootfs bundle asset, and fixture/test expectations for Jammy source URL/SHA/size, archive counts, and hard links.
- Generated deterministic `assets/runtime/draxon-rootfs-v1.bundle` from `build/ubuntu-base-22.04.5-base-arm64.tar.gz`.
- Added AUXV compatibility diagnostics for `/bin/bash -lc 'echo hello'`, `apt-get --version`, `dpkg --version`, and `ldd --version` per loader mode. Python diagnostic now reports `python_not_installed`, `python_success`, `python_runtime_crash`, or `python_other_failure`; exit 127 is no longer treated as runtime incompatibility evidence.
- Removed stale local 24.04 archive cache and deleted the 24.04 fixture.

Verification:

- Source Ubuntu archive: `build/ubuntu-base-22.04.5-base-arm64.tar.gz`, 27,671,306 bytes, SHA256 `075d4abd2817a5023ab0a82f5cb314c5ec0aa64a9c0b40fd3154ca3bfdae979f`.
- Ubuntu archive counts: total 3,497; directories 673; regular files 2,615; symlinks 207; hard links 2; other 0; unique blobs 2,487.
- Known hard links: `usr/bin/perl5.34.0 -> usr/bin/perl`, `usr/bin/uncompress -> usr/bin/gunzip`.
- Detected OS: `Ubuntu 22.04.5 LTS`; detected glibc: `GNU C Library (Ubuntu GLIBC 2.35-0ubuntu3.8) stable release version 2.35.`
- Bundle: 29,653,552 bytes, SHA256 `3daeccdbc55eaf1ae34902ecdbd6a2240d4c7c8e73dd8f7229a1cd9b06aaa692`, manifest entries 3,497.
- Host materialized regular-file bytes: 69,213,701; Android copy-fallback install bytes if both hard links copy: 72,862,815.
- `python scripts/prepare_draxon_rootfs.py --inspect` passed and reported Jammy counts/hard links.
- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed: no issues.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 48 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 53,158,794 bytes, SHA256 `61b7eb194a6a8f75819fd451719a26a7822cd83a4eb9d3664399adf6ba1bec13`.
- APK inspection confirmed rootfs asset SHA256 `3daeccdbc55eaf1ae34902ecdbd6a2240d4c7c8e73dd8f7229a1cd9b06aaa692`, old 24.04 tar absent, no `ubuntu-base*.tar.gz` packaged, and all five proroot v1.2.8 libs remain packaged with expected SHA256.

Pending/manual:

- Real Android phone validation still pending. Install APK, Settings → Draxon Local Runtime. If existing rootfs validates as old bundle mismatch, use Install Local Shell; otherwise Retry Runtime Test. Diagnostics should show Ubuntu 22.04.5, glibc 2.35 from `ldd --version`, host/guest `AT_MINSIGSTKSZ`, selected loader mode, per-loader compatibility stages, and Python status. Then run package test: `apt-get update`, `apt-get install -y python3`, `python3 --version`, `python3 -c 'print(1)'`, `python3 -c 'import sys; print(sys.version)'`, `apt-get install -y git`, `git --version`, `apt-get install -y nodejs npm`, `node --version`, `npm --version`.

---- STATE 21 ----

Implemented:

- Replaced proprietary `coderredlab/proroot` APK runtime files with open-source Termux/LocalDesktop PRoot binaries packaged as `libdraxon_proot.so` and `libdraxon_proot_loader.so`.
- Removed all five `libproroot*.so` files from `android/app/src/main/jniLibs/arm64-v8a/`; Gradle now keeps debug symbols for `**/libdraxon_proot*.so`.
- Switched bundled rootfs from Ubuntu Base to official `termux/proot-distro` Arch Linux AArch64 `v4.29.0`, source archive `archlinux-aarch64-pd-v4.29.0.tar.xz`.
- Reworked `scripts/prepare_draxon_rootfs.py` for `.tar.xz`, `archlinux-aarch64/` prefix stripping, Arch manifest metadata, pacman/linker critical paths, and no known hard-link requirement.
- Updated Kotlin runtime paths to `runtime/arch`, validates `/bin/sh`, `/bin/bash`, `usr/bin/pacman`, `etc/os-release`, `usr/lib/ld-linux-aarch64.so.1`, sets `PROOT_TMP_DIR` and `PROOT_LOADER`, and binds existing host `/dev`, `/proc`, `/sys`, `/system`, `/storage` plus project mounts.
- Runtime self-test now checks Arch os-release and `pacman --version`; project command model remains `/bin/bash -lc <command>` under `/workspace/<mount-name>`.
- Updated diagnostics, Settings copy, fixture, and Dart tests for Arch/PRoot/pacman metadata.

Verification:

- PRoot binaries: `libdraxon_proot.so` 245,816 bytes SHA256 `2d278e9a3f96ca275776909551c63eb878fb96a6d1b7a6b0c6f94e7f9a2e056a`; `libdraxon_proot_loader.so` 5,464 bytes SHA256 `cf4f87772e1baf5950e35af9a729a1402898a81492e0aa011bcde3007455ddc8`.
- Source rootfs: `build/archlinux-aarch64-pd-v4.29.0.tar.xz`, 151,744,988 bytes, SHA256 `08d74365213e647c558e561b0a2a7afb6fa3dfe345a1994c62ccac5af1a1cdc6`.
- Arch archive after prefix strip: total 33,369 entries; directories 1,369; regular files 23,803; symlinks 8,197; hard links 0; other 0; unique blobs 20,186.
- Detected libc in source archive: `GNU C Library (GNU libc) stable release version 2.41`.
- Bundle: `assets/runtime/draxon-rootfs-v1.bundle`, 245,223,138 bytes, SHA256 `487323090a6600d40e5be0141e4f3998dcc93434de53cd539d858657e3aecd7c`, manifest entries 33,369.
- `python scripts/build_android_proot.py` passed and repackaged open PRoot binaries.
- `python scripts/prepare_draxon_rootfs.py --inspect` passed.
- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed: no issues.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 47 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 265,885,262 bytes, SHA256 `28cc3f3c6c0ddb186bf81f6ae39ff2b564c2ca93ce6b5642d4ce4c6c5a6b2eca`.
- APK inspection confirmed rootfs bundle SHA256 `487323090a6600d40e5be0141e4f3998dcc93434de53cd539d858657e3aecd7c`, `libdraxon_proot.so` and `libdraxon_proot_loader.so` present with expected SHA256, and no `libproroot*.so` entries.

Pending/manual:

- Real Android phone validation still pending. Install APK, Settings → Draxon Local Runtime → Install Local Shell. Expected diagnostics: Arch Linux `proot-distro-v4.29.0`, rootfs validation pass, `PROOT_LOADER` path available through env, self-test stages pass through `pacman --version`, and project command cwd `/workspace/<mount-name>`.
- Phone package test after Ready: `pacman -Sy --noconfirm python git nodejs npm`, `python3 --version`, `python3 -c 'print(1)'`, `python3 -c 'import sys; print(sys.version)'`, `git --version`, `node --version`, `npm --version`.

---- STATE 22 ----

Implemented:

- Finished migration cleanup after open-source Termux PRoot + Arch rootfs cutover. Removed remaining loader/AUXV/proprietary/Ubuntu diagnostic references from active Kotlin, Dart, scripts, tests, and assets.
- Rebuilt `assets/runtime/draxon-rootfs-v1.bundle` as deterministic minimal Arch Linux AArch64 payload from official `termux/proot-distro` v4.29.0 archive. Bundle keeps shell, pacman, curl, find/grep/sed/awk, tar/gzip/xz/zstd, glibc linker/libc, os-release, pacman config, and CA certificates; drops desktop/SSH/editor extras.
- Updated `DraxonRuntimeManifest.rootfsBundle` to SHA256 `a6662dfbaba07b524fd04683a23819f394978147acfc6f7596ca353d1d2efddf`, size 131,882,628 bytes, 30,903 manifest entries.
- Fixed bundle materializer script scoping bug and preserved delayed chmod handling for read-only dirs such as `etc/ca-certificates/extracted/cadir` mode `0555`.
- Updated fixture `archlinux_aarch64_pd_v4_29_0_structure.json` to minimal-bundle counts and CA certificate permission regression data.

Verification:

- `python scripts/build_android_proot.py` passed; packaged `libdraxon_proot.so` SHA256 `2d278e9a3f96ca275776909551c63eb878fb96a6d1b7a6b0c6f94e7f9a2e056a` and `libdraxon_proot_loader.so` SHA256 `cf4f87772e1baf5950e35af9a729a1402898a81492e0aa011bcde3007455ddc8`.
- `python scripts/prepare_draxon_rootfs.py --inspect` passed on minimal bundle: total 30,903 entries; directories 1,203; regular files 21,677; symlinks 8,023; hard links 0; other 0; installed size 663,639,321 bytes; payload size 130,790,536 bytes.
- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed: no issues.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 47 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK `build/app/outputs/flutter-apk/app-release.apk`, 155,817,104 bytes, SHA256 `66be7cd2a1d3e2ef26208cb0578b239589a69008e79a8edc8696b250e1b2a7ef`. APK contains rootfs bundle with expected SHA256 and both `libdraxon_proot*.so`; no Ubuntu archive, no source Arch archive, no `libproroot*.so`.

Pending/manual:

- Phone validation still pending. Install APK, Settings to Draxon Local Runtime to Install Local Shell. Expected: bundled rootfs extracted from APK, validation pass, self-test reaches `pacman --version`, Ready. Then run `pacman -Sy --noconfirm python git nodejs npm`, `python3 --version`, `git --version`, `node --version`, `npm --version`.

---- STATE 23 ----

Implemented:

- Fixed Arch rootfs bundle mismatch that caused Android installer failure `payload_entry_not_in_manifest: archlinux-aarch64/etc/ca-certificates/extracted/cadir/Autoridad_de_Certificacion_Firmaprofesional_CIF_A62634068.pem`. Root cause: `scripts/prepare_draxon_rootfs.py` reused source `TarInfo` objects with preserved PAX headers; long-name entries kept original `archlinux-aarch64/` PAX path while manifest recorded stripped paths.
- Added final bundle validator to `scripts/prepare_draxon_rootfs.py`: validates final APK-bound `.bundle` payload entries against manifest entries, strict path normalization, type counts, file size/SHA256, symlink/hardlink targets, duplicate payload paths, unsafe traversal/absolute paths, missing payload entries, and missing manifest entries. `write_bundle()` now validates before replacing output.
- Regenerated `assets/runtime/draxon-rootfs-v1.bundle` after clearing PAX headers on output tar entries. Bundle now has zero missing-from-manifest, zero missing-from-payload, zero unsafe paths, zero duplicate payload paths.
- Hardened Android `DraxonRootfsBundleInstaller`: rejects payload prefix leakage (`archlinux-aarch64/`), duplicate payload paths, payload entries missing from manifest, manifest entries missing from payload, and symlink ancestors before writing files/links under staging. Directory chmod remains delayed until after extraction.
- Cleared stale diagnostics by ignoring metadata from non-current runtime family for install timeline, cleanup events, and diagnostics; old Ubuntu/proroot/AUXV fields no longer surface as current Open PRoot/Arch diagnostics.
- Added rootfs script self-tests covering normal file, directory, relative symlink, absolute symlink, symlink chain, CA-style symlink, spaces, long filename, Unicode filename, hardlink copy fallback, duplicate normalized payload path, traversal path, absolute payload path, payload entry missing from manifest, manifest entry missing from payload, and manifest traversal.
- Updated Kotlin manifest constants and Arch fixture/test expectations for new bundle hash and size.

Verification:

- Reproduced old bundle mismatch before fix: 20 payload entries retained `archlinux-aarch64/` prefix, including the phone CA certificate path; 20 corresponding manifest entries lacked the prefix.
- `python scripts/prepare_draxon_rootfs.py` passed and regenerated bundle.
- `python scripts/prepare_draxon_rootfs.py --validate-bundle` passed: payload entries 30,903; manifest entries 30,903; files 21,677; directories 1,203; symlinks 8,023; hardlinks 0; missing-from-manifest 0; missing-from-payload 0; unsafe paths 0.
- `python scripts/prepare_draxon_rootfs.py --self-test` passed.
- `python -m py_compile scripts/prepare_draxon_rootfs.py` passed.
- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed: no issues.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 47 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK `build/app/outputs/flutter-apk/app-release.apk`, 155,551,444 bytes, SHA256 `db3267483a0cca490700855923d90fd85d2b2d72f890051e732ac906a7f4d970`. APK contains rootfs bundle SHA256 `705651fbe972ab4c9257d309cf5341d49140efb8a333546285614518e76c5a60`, both expected `libdraxon_proot*.so`, no Ubuntu archive, no source Arch archive, no `libproroot*.so`.

Pending/manual:

- Phone validation still pending. Fresh install or Reset Runtime. Expected sequence: extract bundle, validate rootfs, rename `arch.installing` to `arch`, run Open PRoot self-test, show Ready. Test only base shell first: `/bin/sh -c 'echo hello'`, `/bin/bash -lc 'echo hello'`, `uname -a`, `cat /etc/os-release`, `pacman --version`. Do not install Python/Node/Git until these pass.



---- STATE 24 ----

Implemented:

- Kept current proven architecture: Flutter app → Android `LocalRuntimeManager` → open-source Termux PRoot → Arch Linux ARM64 rootfs. Did not restore Ubuntu or proprietary `libproroot*.so`.
- Fixed pacman DB mismatch by adding `var/lib/pacman/local/ALPM_DB_VERSION` with pacman 7 local DB version `9` into the generated bundle.
- Fixed initial keyring failure path by packaging writable pacman keyring/cache/sync directories, initializing `/etc/pacman.d/gnupg` during install, and adding background self-test stage `pacman-key --init && pacman-key --populate archlinuxarm`. Signature verification stays enabled (`SigLevel = Required DatabaseOptional`).
- Fixed known package ownership conflicts for Python install by overlaying current Arch Linux ARM `libgcc` and `libstdc++` packages into the bundle and moving ownership of `libgcc_s.so*`/`libstdc++*` out of stale `gcc-libs` local metadata.
- Added install/package low-storage protection returning `low_storage`; install preflight requires rootfs installed bytes + two bundle copies + 512 MiB safety. Pacman commands require 512 MiB free before running.
- Added pacman cache cleanup for successful Bash-controlled `pacman -S...` commands: removes `/var/cache/pacman/pkg/*.pkg.tar.*` and `*.sig`; sync databases under `/var/lib/pacman/sync` are preserved.
- Diagnostics now report expected rootfs installed size, free app storage, runtime directory size, and pacman cache size.
- Regenerated deterministic rootfs bundle and updated Kotlin manifest + Arch fixture/test expectations.

Measurement:

- Previous bundle: 131,618,615 bytes compressed, 663,639,321 installed file bytes, 30,903 entries, 105 packages.
- New bundle: 126,848,208 bytes compressed, 643,931,317 installed file bytes, 30,918 entries, 107 packages.
- Measured current bundle before changes: `/` 663,639,321 file bytes; `/usr` 659,569,782; `/usr/lib` 350,954,260; `/usr/share` 176,358,871; `/var` 2,383,877; `/var/cache/pacman/pkg` 0; `/var/lib/pacman` 2,378,245. Largest waste remains old GCC runtimes/locales/docs/static libs/systemd, but package-owned files were not randomly pruned.

Verification:

- `python scripts/prepare_draxon_rootfs.py --inspect` passed: 30,918 entries, 107 packages, installed file bytes 643,931,317.
- `python scripts/prepare_draxon_rootfs.py` passed and regenerated `assets/runtime/draxon-rootfs-v1.bundle`.
- `python scripts/prepare_draxon_rootfs.py --validate-bundle` passed: payload entries 30,918; manifest entries 30,918; missing/unsafe/duplicate/type/checksum/target mismatches all 0.
- `python scripts/prepare_draxon_rootfs.py --self-test` passed.
- `python -m py_compile scripts/prepare_draxon_rootfs.py` passed.
- `python scripts/build_android_proot.py` passed; both `libdraxon_proot*.so` hashes matched.
- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 47 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed after clearing generated build caches for disk space.
- Release APK: `build/app/outputs/flutter-apk/app-release.apk`, 150,780,068 bytes, SHA256 `c426cc202a9413f08f0efa197975db439062f5e48d6e07057eaece6b7baf01e8`.
- APK contains rootfs bundle SHA256 `ea824f33e71d9b456841d80fa9552f5009b78f777d8a304eb1c9793fe6a3dd63`, `libdraxon_proot.so`, and `libdraxon_proot_loader.so`; no `libproroot*.so`.

Pending/manual:

- Physical phone validation still required for `pacman-key --init` duration and real signed package installs. Install/reset local runtime, confirm Ready, then run `pacman -Sy`, `pacman -S --noconfirm python`, `python --version`, `python -c 'print("python works")'`, then git/node/npm package tests.

---- STATE 25 ----

Implemented:

- Fixed Android ANR/lag root cause for Draxon Local Runtime Linux actions: `runLocalCommand` previously executed `validateRootfs`, `ProcessBuilder.start`, `waitFor`, stdout/stderr joins, and command completion directly on the Flutter platform-channel/UI thread.
- `LocalRuntimeManager.runCommand()` now copies args on entry, runs validation and PRoot command execution on a background `Thread`, then posts `result.success()` back through `activity.runOnUiThread`.
- `MainActivity` now handles `localRuntimeStatus` and `removeLocalRuntime` on background threads as well; status does filesystem validation and diagnostics, remove can recursively delete a large rootfs.
- Removed recursive full-runtime `directorySize(runtimeDir)` from status diagnostics. It walked the whole Arch rootfs on status refresh and could stall the app. Diagnostics now use O(1)/shallow estimates: manifest installed size + top-level cache/tmp files + direct pacman package-cache files.
- Kept command async behavior, stdout/stderr capture, cancellation, timeout, and real exit-code reporting unchanged.

Verification:

- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- First `flutter test` attempt failed from Windows temp disk exhaustion, not test failure; after clearing generated artifacts, `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 47 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed.
- Release APK: `build/app/outputs/flutter-apk/app-release.apk`, 150,780,764 bytes, SHA256 `9cd4d35202b7f617620153b91ee726b174558afde6f581063921b5df2d7a7504`.

Pending/manual:

- Install this APK on the phone and re-test Draxon Local Runtime actions. Expected result: no Android "Not Responding" dialog while Linux commands, status refreshes, reset/remove, or pacman operations run. Long pacman installs may still take time, but UI should remain responsive.

---- STATE 26 ----

Implemented:

- Simplified startup runtime behavior after phone reported immediate app crash / severe lag. `AppController.refreshAll()` no longer blocks first app load waiting for `runtime.status()`; it sets a cheap placeholder status and refreshes runtime status asynchronously.
- Made `LocalRuntimeManager.status()` lightweight: no full rootfs validation, no PRoot launch, no recursive runtime scan, no long diagnostic dump. It now uses metadata + rootfs directory existence and returns short details only.
- Kept expensive validation on the actual operations that need it: install/self-test/run command. `runLocalCommand` still validates rootfs before executing, but on a background thread.
- Kept `removeLocalRuntime` background-threaded because deleting rootfs can be slow.
- Removed background thread wrapper for `localRuntimeStatus` because status is now cheap and direct; this avoids extra lifecycle/result timing risk during app startup.

Verification:

- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test test/local_runtime_test.dart` passed: 8 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 47 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed.
- Release APK: `build/app/outputs/flutter-apk/app-release.apk`, 150,778,048 bytes, SHA256 `1c74caef405d85a2dd90328d7f0073acedcd826b8270e45395cb899297893233`.

Pending/manual:

- Install this APK on the phone. Expected startup: app opens immediately without waiting for local runtime filesystem/diagnostics. Settings may briefly show runtime status not checked, then refresh. Linux commands and install still run in background; UI should not show Android Not Responding.

---- STATE 27 ----

Implemented:

- Fixed install-click crash risk in `LocalRuntimeManager.install()`: top-level install thread now catches `Throwable`, records a safe install error in metadata, clears `installRunning`, and returns a channel result instead of letting an uncaught background-thread exception terminate the Android process.
- Removed `pacman-key --init && pacman-key --populate archlinuxarm` from the install self-test path. Install now verifies the writable `/etc/pacman.d/gnupg` directory only. This keeps the Install Local Shell button to extract/validate/smoke-test instead of running a long mutable keyring operation during click/install.
- Deferred keyring initialization to actual Bash-controlled pacman `-S` operations. `wrapPackageCommand()` now runs `pacman-key --list-keys`; if missing, it initializes/populates the Arch Linux ARM keyring before the package command, then cleans downloaded package archives only after command success.

Reason:

- Likely install crash source was new install-time keyring initialization or another uncaught native/runtime exception in the install background thread. Previous architecture did not run that mutable pacman-key step during install click.

Verification:

- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test test/local_runtime_test.dart` passed: 8 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 47 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed.
- Release APK: `build/app/outputs/flutter-apk/app-release.apk`, 150,778,160 bytes, SHA256 `91cbe14c4c39201229d17e3cc63344877d912e5fe6cb8ea6fce03cc225a1db28`.

Pending/manual:

- Install APK on phone, tap Settings -> Install Local Shell. Expected: no app crash. If install fails, UI should show a Draxon Local Runtime error instead of process death. After Ready, first `pacman -S ...` may take longer because keyring init is deferred to that package operation.

---- STATE 28 ----

Implemented:

- Fixed phone install failure `install_failed: delete_failed: .../files/runtime/arch.installing`.
- Root cause: installer reused fixed staging path `runtime/arch.installing`; stale partial Arch rootfs could contain read-only directory modes from extraction, so Android `deleteRecursively()` returned false before new extraction started. That left app in error with corrupted `runtime/arch` (`bin=false`, `usr=false`, `pacman=false`).
- Install now uses fresh timestamped staging directories: `arch.installing.<time>`.
- Stale staging cleanup is best-effort and cannot fail the next install click.
- Cleanup now chmods files/directories before deletion and avoids following symlinks.
- Rootfs replacement now renames old/corrupt `arch` aside to `arch.replaced.<time>` before moving fresh staging into place. If old rootfs deletion fails, install can still proceed with clean new rootfs.
- Interrupted install recovery no longer throws from status path; it records cleanup attempt and leaves UI usable.

Verification:

- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 47 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed.
- Release APK: `build/app/outputs/flutter-apk/app-release.apk`, 150,778,484 bytes, SHA256 `1d0876922e5cf8dc8d26417eb4a66b65b73faa62df5d659fd6f8e9fcfce83648`.

Pending/manual:

- Install APK on phone, then tap Settings -> Install Local Shell again. Expected: stale `arch.installing` no longer blocks install; corrupted `arch` is moved aside/replaced; UI should reach Ready or show a new actionable extraction/validation error.

---- STATE 29 ----

Implemented:

- Fixed latest phone install validation error: `staging_rootfs_validation_failed ... bin=false, sh=false, bash=false` while `usr=true` and `pacman=true`.
- Root cause: staged Arch rootfs had `/usr/bin/*` but no usable root `/bin` compatibility path. The bundled manifest does include `bin -> usr/bin`, `sbin -> usr/bin`, and `lib -> usr/lib`, but Android extraction/install still produced a staging tree missing `/bin` on device. Runtime self-test requires `/bin/sh` and `/bin/bash`; many Linux scripts also require `/bin/sh`.
- `initializeRootfs()` now repairs root compatibility links after extraction and before validation:
  - `/bin -> usr/bin`
  - `/sbin -> usr/bin`
  - `/lib -> usr/lib`
- If symlink creation is unavailable, installer creates a real `/bin` directory and adds `sh` / `bash` fallbacks pointing to or copied from `/usr/bin`.
- Fixed cleanup safety bug: `deletePath()` now deletes symlinks with `delete()` instead of `deleteRecursively()`, so cleanup cannot accidentally follow `/bin -> usr/bin` and delete target contents.

Verification:

- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `python scripts/prepare_draxon_rootfs.py --validate-bundle` passed. Bundle still has 30,918 entries, 8,023 symlinks, zero target/type/checksum mismatches.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test test/local_runtime_test.dart` passed: 8 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 47 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed.
- Release APK: `build/app/outputs/flutter-apk/app-release.apk`, 150,779,112 bytes, SHA256 `5baabe9360e53fbd77a3b21c9b5be65c3855a3174bb71cb58ea0f18a2935ff70`.

Pending/manual:

- Install this APK on phone, then tap Settings -> Install Local Shell. Expected validation should no longer report `bin=false`, `sh=false`, or `bash=false`. If it fails again, paste diagnostics; next likely root cause would be PRoot execution, not extraction layout.

---- STATE 30 ----

Implemented:

- Confirmed phone report: APK from STATE 29 works for Bash and Python despite installer ending in error at `cat /workspace/project-b/b.txt`.
- Root cause of remaining install error: `runtimeCommand()` created `/workspace/project-a` and `/workspace/project-b` directories inside rootfs, but did not pass host project bind mounts to PRoot. `cat /workspace/project-b/b.txt` therefore looked at empty rootfs placeholder instead of host `selftest_project_b`.
- Fixed PRoot runtime command arguments to bind every available project: `<host path>:/workspace/<mount-name>`.
- Filtered project binds to existing host directories before creating PRoot args.
- Kept multi-project workspace self-test because it catches real bind regressions. Functional phone behavior already proved base shell/Python runtime works; this fix should make installer status reach Ready instead of false error.

Verification:

- `cmd.exe /c C:/tools/flutter/bin/dart.bat format .` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test test/local_runtime_test.dart` passed: 8 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 47 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed.
- Release APK: `build/app/outputs/flutter-apk/app-release.apk`, 150,779,160 bytes, SHA256 `8eb7c11fba1f6d35f07ad89dca1088ee7e47d36614ce1435355d2e1a3e034825`.

Pending/manual:

- Current installed APK is usable for Bash/Python. New APK only fixes installer Ready status and multi-project bind correctness. Install it when convenient; no urgent reinstall needed if shell/Python already work.

---- STATE 31 ----

Implemented:

- Reverted prior accidental `.omp-reference` edits only; reference repo status is clean and reference `node_modules` / reference `STATE.md` created by this session were removed.
- Fixed saved-chat reopen crash path in real Draxon app. Persisted `messages.content`, `messages.metadata_json`, `tool_executions.arguments_json`, `tool_executions.result_json`, and `tool_executions.error` now recover/truncate oversized strings before UI/context use.
- `AppRepository.listMessages()` and `listToolExecutions()` self-heal old oversized rows by writing sanitized records back after load, so a crashy chat should become safe after first successful open.
- Tool result persistence now uses `64,000` character caps instead of `200,000`; JSON sanitization preserves valid JSON where practical and marks truncated keys with `*Truncated` / `*OriginalLength` metadata.
- `ToolCallCard` refuses to `jsonDecode` oversized raw JSON and shows a recovered/truncated preview instead of blocking render.
- Fixed large command freeze source in Android runtime capture: `LocalRunResult.readAsync()` now drains stdout/stderr while retaining bounded output only, so `pacman`-style verbose commands cannot grow unbounded process-output strings.
- `TermuxBridge` also bounds callback stdout/stderr/errmsg before sending payloads over the Flutter method channel. `CommandResult` carries runtime-provided truncation metadata through Dart.

Files modified:

- `lib/src/models.dart`
- `lib/src/storage/app_repository.dart`
- `lib/src/runtime/shell_executor.dart`
- `lib/src/tools/agent_tools.dart`
- `lib/src/ui/chat/tool_call_card.dart`
- `android/app/src/main/kotlin/com/draxon/draxon_coding_agent/LocalRunResult.kt`
- `android/app/src/main/kotlin/com/draxon/draxon_coding_agent/TermuxBridge.kt`
- `test/app_foundation_test.dart`

Verification:

- `git status --short` in `.omp-reference` returned clean output.
- `cmd.exe /c C:/tools/flutter/bin/dart.bat format ...` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test test/app_foundation_test.dart` passed: 30 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 49 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 150,793,904 bytes, SHA256 `892bfbe76ce7c74ede711e8425da0aae513bdc7a4b658952591e9dc6c2f5fd84`.

Pending/manual:

- Phone validation required on the previously crashy chat: open chat, confirm UI stays responsive, run `pacman -Sy --noconfirm python` or another verbose command, restart app, reopen same chat, confirm output is truncated/recovered instead of ANR/crash.
- Broader stability/tooling milestone remains beyond this crash/output pass: read/search/edit schema redesign, parallel tool execution, deeper session recovery, and stress tests.


---- STATE 32 ----

Implemented after STATE 31:

- Continued stability/tooling work in real Draxon source, not `.omp-reference`.
- Read tool schema now supports line ranges via `offset`/`limit` or `startLine`/`endLine`, byte ranges via `unit: "byte"`, `raw`, and bounded output. Large files no longer fail solely because total file size exceeds the old full-read cap when caller requests a safe range.
- Search tool now accepts `maxResults`, scans bounded file content, reports `scannedFiles`, `skippedLargeFiles`, and `skippedBinaryFiles`, and truncates long match lines.
- Edit/write now use atomic temp-file replacement where possible. Edit supports `replaceAll` and `expectedReplacements` in addition to unique single-target replacement.
- Agent loop now executes multiple tool calls from one assistant turn concurrently with `Future.wait`, then persists tool results/messages in original call order.
- Added regression coverage for byte-range read, replace-all edit with expected replacement count, oversized persisted chat/tool recovery, capped bash output, and parallel tool calls.

Additional files modified:

- `lib/src/agent/agent_loop.dart`
- `lib/src/tools/agent_tools.dart`
- `test/app_foundation_test.dart`

Final verification:

- `cmd.exe /c C:/tools/flutter/bin/dart.bat format lib/src/tools/agent_tools.dart lib/src/agent/agent_loop.dart test/app_foundation_test.dart` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat analyze` passed.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test test/app_foundation_test.dart` passed: 31 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat test` passed: 50 tests.
- `cmd.exe /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 150,823,356 bytes, SHA256 `7103504e92c4e6c42d5bc2489ab23731340622749db67824d7690ed0643f524d`.

Pending/manual:

- Physical phone validation still required for the original crash report: open the previously crashy chat, confirm no ANR, run a verbose command such as `pacman -Sy --noconfirm python`, restart app, reopen the chat, and confirm recovered/truncated output renders.
- Exact runtime behavior under real phone storage pressure cannot be proven on RDP.


---- STATE 33 ----

Implemented after STATE 32:

- Finished remaining stability/tooling items in real Draxon source.
- Read tool line-range metadata now counts full file `totalLines` instead of stopping at requested `endLine`; response includes `hasMore`, `contentTruncated`, and `requestedLines`.
- Search tool schema now supports fixed or regex matching, case sensitivity, include/exclude globs, context lines, offsets, result caps, and pagination metadata.
- Google Antigravity OAuth now discovers Gemini model ids from `loadCodeAssist`, persists discovered models, keeps existing manually configured models, and falls back to bundled defaults.
- New empty chats and first sends now attach first configured provider/model before the agent starts, avoiding model-selector/send mismatch.
- Added regressions for read metadata, search paging/context, dynamic Gemini model extraction, and no-model chat fallback.

Files modified:

- lib/src/app.dart
- lib/src/ai/oauth/google_antigravity_oauth.dart
- lib/src/tools/agent_tools.dart
- test/app_foundation_test.dart
- STATE.md

Verification:

- `cmd /c C:/tools/flutter/bin/dart.bat format lib/src/tools/agent_tools.dart lib/src/app.dart lib/src/ai/oauth/google_antigravity_oauth.dart test/app_foundation_test.dart` passed.
- `cmd /c C:/tools/flutter/bin/flutter.bat analyze` passed: no issues.
- `cmd /c C:/tools/flutter/bin/flutter.bat test test/app_foundation_test.dart` passed: 33 tests.
- `cmd /c C:/tools/flutter/bin/flutter.bat test` passed: 51 tests.
- First parallel release build hit 600 second harness timeout while still in Gradle. Retried standalone.
- `cmd /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 150,836,992 bytes, SHA256 `4f3fa804d392e41f4affacbdc5b305d9d3d86546266313c1f9cdf4afc557f531`.

Pending/manual:

- Physical phone validation still required for original ANR/crash: install APK, open previously crashy chat, confirm UI stays responsive, run `pacman -Sy --noconfirm python` or another verbose command, restart app, reopen same chat, confirm output remains truncated/recovered and no ANR/crash occurs.
- `git status --short` is not available in this working tree because `C:/Projects/draxoncodingagent` is not a git repository.


---- STATE 34 ----

Implemented after phone still crashed:

- Root cause found in reopen path: `listMessages()` and `listToolExecutions()` used `SELECT *`, so legacy huge `content`, `metadata_json`, `arguments_json`, `result_json`, and `error` values were fully copied out of SQLite before Dart truncation/recovery could run. A previously crashy chat could still ANR/OOM during database load, before widgets rendered.
- Added SQL-side projection for chat/tool text columns. Reopen now pulls only a 12k-character prefix plus truncation marker for oversized values, then rewrites those projected/recovered records back to SQLite so future opens stay small.
- Tightened malformed persisted JSON recovery: invalid JSON is wrapped into a small recovered JSON object instead of being returned raw.
- Reduced tool-card visible code preview from 20k to 4k and skips JSON decoding for tool payloads above 12k, preventing collapsed cards from decoding/rendering large payloads.
- Updated oversized persisted chat regression to assert database-projected rows are loaded and then compacted before rendering.

Files modified:

- lib/src/models.dart
- lib/src/storage/app_repository.dart
- lib/src/ui/chat/tool_call_card.dart
- test/app_foundation_test.dart
- STATE.md

Verification:

- `cmd /c C:/tools/flutter/bin/dart.bat format lib/src/models.dart lib/src/storage/app_repository.dart lib/src/ui/chat/tool_call_card.dart test/app_foundation_test.dart` passed.
- `cmd /c C:/tools/flutter/bin/flutter.bat analyze` passed: no issues.
- `cmd /c C:/tools/flutter/bin/flutter.bat test test/app_foundation_test.dart` passed: 33 tests.
- `cmd /c C:/tools/flutter/bin/flutter.bat test` passed: 51 tests.
- `cmd /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 150,843,096 bytes, SHA256 `3d14618f6424b0e3914229d0f056b98c04445e3ea99e252a46fb168f97ea5386`.

Pending/manual:

- Install the new APK, reopen the same crashy chat first, and confirm the app no longer ANRs before running any new command. If it still crashes, next needed evidence is Android logcat around the crash because database and widget payloads are now bounded before Dart/UI decode.


---- STATE 35 ----

Implemented after JSONL persistence request:

- Moved chat-owned runtime data out of SQLite into JSONL files under a `chats_jsonl/` store next to the app database: chat index, per-chat messages, tool executions, agent jobs, and attachments now load/save through `ChatJsonlStore`.
- Kept SQLite for stable app metadata only: projects, providers, models, settings, and secrets indirection. Provider/model data still validates through existing SQLite tests.
- Added lazy one-time migration from legacy SQLite chat tables into bounded JSONL. Migration reads legacy large text through SQL-side projection, writes compact/recovered JSONL records, and leaves old SQLite rows unused.
- Added explicit Google Antigravity model refresh from provider settings. It refreshes OAuth when needed, fetches live Gemini model ids, merges discovered + existing + defaults, and preserves manual fallback models.
- Settings provider menu now shows `Refresh models` for Google Antigravity providers.

Files modified:

- lib/src/app.dart
- lib/src/models.dart
- lib/src/storage/app_repository.dart
- lib/src/storage/chat_jsonl_store.dart
- lib/src/storage/local_database.dart
- lib/src/ui/chat/tool_call_card.dart
- lib/src/ui/screens/settings_screen.dart
- test/app_foundation_test.dart
- STATE.md

Verification:

- `cmd /c C:/tools/flutter/bin/dart.bat format lib/src/storage/chat_jsonl_store.dart lib/src/storage/app_repository.dart lib/src/storage/local_database.dart test/app_foundation_test.dart` passed.
- `cmd /c C:/tools/flutter/bin/dart.bat format lib/src/app.dart lib/src/ui/screens/settings_screen.dart` passed.
- `cmd /c C:/tools/flutter/bin/flutter.bat analyze` passed: no issues.
- `cmd /c C:/tools/flutter/bin/flutter.bat test test/app_foundation_test.dart --plain-name "migrates legacy SQLite chats into bounded JSONL files"` passed.
- `cmd /c C:/tools/flutter/bin/flutter.bat test test/app_foundation_test.dart` passed: 32 tests.
- `cmd /c C:/tools/flutter/bin/flutter.bat test` passed: 51 tests.
- `cmd /c C:/tools/flutter/bin/flutter.bat build apk --release` passed. APK: `build/app/outputs/flutter-apk/app-release.apk`, 150,879,112 bytes, SHA256 `b70974dacf2552f1e1cb51489f056632b31cf8026ce864d967787e95b018677d`.

Pending/manual:

- Physical phone validation still required: install the APK, open the previously crashy chat, confirm no ANR, run a verbose command such as `pacman -Sy --noconfirm python`, restart, reopen the same chat, and confirm JSONL-backed truncated/recovered output stays responsive.


---- STATE 36 ----

Implemented live command + file-view follow-up after STATE 35:
- Added shell output streaming contract: Dart `ShellExecutor.run(... onOutput:)`, `CommandOutputUpdate`, Android `commandOutput` MethodChannel events, and bounded stdout/stderr accumulators.
- Local Android runtime now emits stdout/stderr chunk previews while command runs; agent loop persists throttled running `ToolExecution` previews so reopened chats show current output before final result.
- Local process executor now drains streams with bounded buffers and reports truncation metadata. Existing stale running job recovery remains active through repository reconciliation.
- Tool card now shows write content preview and edit diff preview with green `+` and red `-` lines; read/list/bash existing bounded previews retained. Edit tool now reports `newBytes`.
- Added tests for streaming update payloads and write/edit file previews.

Verified:
- `flutter analyze`: no issues.
- `flutter test test/app_foundation_test.dart --plain-name "bash streaming updates expose bounded running output"`: passed.
- `flutter test test/widget_test.dart`: 13 tests passed.
- `flutter test`: 54 tests passed.
- `flutter build apk --release`: passed. APK `build/app/outputs/flutter-apk/app-release.apk`, size 150,914,928 bytes, SHA256 `3dc6c81995ef66b7c9a5d56c7bc54209bbd3cea5f8b92bf1e2f30bea02df5257`.

Pending/manual:
- Phone validation still required: install APK, open old crash chat first, run verbose command like `pacman -Sy --noconfirm python`, confirm live stdout renders during run, restart app, reopen same chat, confirm no ANR/crash and output remains bounded/truncated.

---- STATE 37 ----

Implemented follow-up after STATE 36:
- Stop now cancels an active bash tool before recording the chat as interrupted; agent loop no longer resumes the model after tool cancellation.
- Draxon runtime command output bus attaches lazily, so non-Android tests can instantiate diagnostics without a Flutter binary messenger.
- Chat JSONL writes are serialized per file and use unique temp files plus retry, reducing Windows rename conflicts during concurrent chat/message updates.
- Structured fallback errors now include categories for timeouts, filesystem errors, format errors, state errors, and internal exceptions instead of generic agent failure text.
- Edit tool now reports `replacedLines` and `newLines`; tool card uses line counts for `+N -M` badges and details.

Verified:
- `flutter test test/local_runtime_test.dart --plain-name "local runtime diagnostics include stable project mount names"`: passed.
- `flutter test test/app_foundation_test.dart --plain-name "stop cancels a running chat and marks it interrupted"`: passed.
- `flutter test test/app_foundation_test.dart --plain-name "stop cancels a running bash tool without resuming model"`: passed.
- `flutter test test/app_foundation_test.dart --plain-name "bash streaming updates expose bounded running output"`: passed.
- `flutter test test/app_foundation_test.dart --plain-name "generic agent errors include structured category and detail"`: passed.
- `flutter test test/widget_test.dart --plain-name "ToolCallCard renders edit diff badge using lines"`: passed.
- `flutter test --concurrency=1`: 56 tests passed. Default parallel `flutter test` hit Flutter tool temp `output.dill` failure after earlier concurrent run, then serialized full run passed.
- `flutter analyze`: no issues.
- `flutter build apk --release`: passed. APK `build/app/outputs/flutter-apk/app-release.apk`, size 150,927,404 bytes, SHA256 `fba19f4d019dfc79c4a5cbdf86a9308c01b8c52e011b4375e9eec54aedbc6f15`.

Pending/manual:
- Physical phone validation still required: install release APK, open old crash chat first, confirm no ANR, run `pacman -Sy --noconfirm python`, press Stop mid-run once, confirm command cancels and chat becomes interrupted, restart app, reopen same chat, confirm bounded recovered output stays responsive.

---- STATE 38 ----

Implemented Complete Mobile Frontend Redesign:
- Added `AppIdentity` central application identity and dynamic branding system; no hardcoded app names in UI.
- Standardized typography on Jost everywhere via `google_fonts` with JetBrainsMono for code/terminal.
- Replaced all emoji icons with vector icon system `AppIcons` and branded marks for Google, OpenAI, Anthropic, Arch Linux, Termux.
- Built layered Dark Blue theme system (`AppColors`, `AppTypography`, `AppMotion`, `AppTheme`).
- Built core reusable components: `FloatingPanel`, `AdaptiveSheet`, `MaximizableSurface`, `EmptyState`, `AppCard`, `AppButton`, `AppIconButton`, `BadgeChip`, `StatusIndicator`.
- Implemented 6-step sequential onboarding flow with state restoration (`OnboardingScreen`, `WelcomeStep`, `ProviderStep`, `PromptStep`, `ReviewStep`, `RuntimeStep`, `ProjectStep`).
- Ported OpenAI Codex / ChatGPT OAuth PKCE flow with live model discovery from `/v1/models` and live streaming test card.
- Implemented universal live model discovery from APIs across providers and dynamic model refresh.
- Implemented runtime recommendation (Arch Linux for ARM64 with full local agent tools vs Termux), 2-step confirmation sheet, and stage-based progress.
- Implemented inline editable "First Project" placeholder and persistence.
- Redesigned `HomeScreen` with projects overview, recent chats, runtime and provider status cards.
- Redesigned `ChatSidebar` with `← Home`, dropdown groups (`Chats ▼` with search, `Providers ▼`), and settings navigation.
- Redesigned `MainChatScreen` with compact header, floating searchable `ModelSelectorSheet` with immediate selection, floating multiline `ComposerView`, and attachment chips.
- Enhanced `ToolCallCard` with collapsible and full-screen maximizable viewers for command output, diffs, and search matches.
- Redesigned `SettingsScreen` with floating cards for Providers, Global Prompt Instructions, Runtime, Agent Limits, Storage breakdown, Appearance, and Rerun Onboarding.
- Implemented asynchronous storage stats calculation service (`StorageStatsService`).
- Integrated Global `AGENTS.md` and Project-specific `AGENTS.md` instruction precedence in `AgentLoop` and `ContextBuilder`.

Files Modified / Added:
- lib/src/core/app_identity.dart
- lib/src/ui/theme/app_colors.dart
- lib/src/ui/theme/app_typography.dart
- lib/src/ui/theme/app_motion.dart
- lib/src/ui/theme/app_icons.dart
- lib/src/ui/theme/app_theme.dart
- lib/src/ui/widgets/floating_panel.dart
- lib/src/ui/widgets/adaptive_sheet.dart
- lib/src/ui/widgets/empty_state.dart
- lib/src/ui/widgets/maximizable_surface.dart
- lib/src/ui/widgets/badge_chip.dart
- lib/src/ui/widgets/app_buttons.dart
- lib/src/ui/widgets/app_card.dart
- lib/src/ui/onboarding/onboarding_screen.dart
- lib/src/ui/onboarding/steps/welcome_step.dart
- lib/src/ui/onboarding/steps/provider_step.dart
- lib/src/ui/onboarding/steps/prompt_step.dart
- lib/src/ui/onboarding/steps/review_step.dart
- lib/src/ui/onboarding/steps/runtime_step.dart
- lib/src/ui/onboarding/steps/project_step.dart
- lib/src/ui/onboarding/widgets/oauth_auth_sheet.dart
- lib/src/ui/screens/home_screen.dart
- lib/src/ui/screens/chat_sidebar.dart
- lib/src/ui/screens/main_chat_screen.dart
- lib/src/ui/screens/settings_screen.dart
- lib/src/ui/screens/provider_dialog.dart
- lib/src/ui/screens/create_project_dialog.dart
- lib/src/ui/chat/model_selector_sheet.dart
- lib/src/ui/chat/composer_view.dart
- lib/src/ui/chat/empty_chat_view.dart
- lib/src/ui/chat/chat_message_view.dart
- lib/src/ui/chat/tool_call_card.dart
- lib/src/storage/storage_stats.dart
- lib/src/storage/app_repository.dart
- lib/src/ai/oauth/openai_codex_oauth.dart
- lib/src/ai/oauth/oauth_credential.dart
- lib/src/ai/oauth/google_antigravity_oauth.dart
- lib/src/ai/openai_provider.dart
- lib/src/ai/registry/provider_registry.dart
- lib/src/agent/context_builder.dart
- lib/src/agent/agent_loop.dart
- lib/src/models.dart
- lib/src/app.dart
- test/widget_test.dart
- STATE.md

Verified:
- `dart format .`: all files cleanly formatted.
- `flutter analyze`: 0 issues found.
- `flutter test --concurrency=1`: 59 tests passed.
- `flutter build apk --release`: release APK built successfully (144.9MB), SHA-256 `bbd2745b3c4272ed54923b4799fc0cf33515d5ecfcaeedacea3908711709d634`.

PHONE VALIDATION REQUIRED:
- On physical Android device:
  1. Fresh install → Welcome screen.
  2. Configure Provider → Google / OpenAI Codex / Custom OAuth or API key.
  3. Live streaming provider test card validation.
  4. Prompt configuration editor & review cards.
  5. Runtime recommendation & 2-step confirmation install or skip.
  6. Inline First Project creation and workspace entry.
  7. Project workspace with smooth sidebar (`← Home`, `Chats ▼`, `Providers ▼`, `Settings`).
  8. Floating model selector with live dynamic discovery.
  9. Floating composer with file attachment chips.
  10. Live streaming assistant response and first-class tool cards with full-screen maximize.

---- STATE 39 ----

Implemented Complete Frontend/UX Rewrite & OMP Provider Logic:
- Base Visual Language: layered dark glass design system on almost-black background (`#05070C`, `#080C14`, `#0D1420`, `glass`, `glassStrong`, `primary #6684FF`, `primaryBright #91A7FF`, `borderActive #736E8CFF`).
- Typography: standardized on Jost (400 body, 500 interactive, 600 headers, 700 hero) with JetBrainsMono for code and terminal streams.
- Zero emojis: replaced all with real vector icons and official brand vector marks (Google, OpenAI, Anthropic, Arch Linux, Termux).
- Reusable components: `GlassSurface`, `BlurOverlay`, `WipeRevealText`, `AnimatedHamburger`, `CentralNavigationOverlay`.
- Welcome Screen: cinematic sequence with horizontal wipe mask, soft subtitle fade, and spring button reveal.
- Progressive First Project: cycling animated project ideas (`First Project` -> `My Fire Idea` -> `API Playground` -> `Demo Workspace` -> `Build Something`), tap-to-edit inline hero text with visible caret, animated directory reveal, and Create button.
- Exact Project Path: selected folder path remains exact project root; no appending or redirecting to app storage.
- Central Navigation Overlay: clicking hamburger on Home or empty project opens central modal hub (`Projects`, `Chats`, `Providers`, `Runtime`, `Settings`).
- Top-Level Standalone Screens: `HomeScreen` (project grid, search, 2-column portrait / 3-5 column landscape), `ProvidersScreen`, `RuntimeScreen`, `ChatsScreen` (project filter, debounced search, paged loading).
- Empty Project Screen: center glowing glass hamburger with transition into active chat workspace.
- Settings Screen Rewrite: portrait category drill-down and responsive desktop/tablet two-pane landscape layout (>= 720px width), with distinct Developer and System technical sections.
- OpenAI Codex OAuth Fix: exact OMP authorization URL (`originator=pi`, `id_token_add_organizations=true`, `codex_cli_simplified_flow=true`, fixed `http://localhost:1455/auth/callback`), plus `loginDeviceCode` headless flow (`https://auth.openai.com/codex/device`).
- Universal live model discovery from APIs across providers and dynamic model refresh.
- Bash normal guest command exits (e.g. exit code 1) classified as `command_exit_error`, preserving stdout and stderr without false runtime failure flags.

Files Modified / Added:
- lib/src/ui/theme/app_colors.dart
- lib/src/ui/components/glass_surface.dart
- lib/src/ui/components/wipe_reveal_text.dart
- lib/src/ui/components/animated_hamburger.dart
- lib/src/ui/navigation/central_navigation_overlay.dart
- lib/src/ui/screens/home_screen.dart
- lib/src/ui/screens/main_chat_screen.dart
- lib/src/ui/screens/providers_screen.dart
- lib/src/ui/screens/runtime_screen.dart
- lib/src/ui/screens/chats_screen.dart
- lib/src/ui/screens/settings_screen.dart
- lib/src/ui/onboarding/steps/welcome_step.dart
- lib/src/ui/onboarding/steps/project_step.dart
- lib/src/ai/oauth/openai_codex_oauth.dart
- test/widget_test.dart
- STATE.md

Verified:
- `dart format .`: all files cleanly formatted.
- `flutter analyze`: 0 issues found.
- `flutter test --concurrency=1`: 63 tests passed.
- `flutter build apk --release`: release APK built successfully (145.0MB), SHA-256 `40990723244007387be1f257a60a73c3f3062a039ef882cc851c733986f8c339`.

PHONE VALIDATION REQUIRED:
- Physical phone verification flow:
  1. Clear app data -> nearly black screen.
  2. Glowing wipe: "Welcome to {appName}" -> Continue.
  3. Provider selection: OpenAI Codex (browser OAuth with fixed 1455 port or device code flow) or Google Antigravity.
  4. Live streaming test card validation.
  5. System prompt & review cards.
  6. Runtime recommendation & install or skip.
  7. Animated hero project creation -> tap cycling idea -> enter name -> select folder -> create.
  8. Project opens with CENTER hamburger -> tap -> central navigation hub -> New Chat.
  9. Chat canvas forms -> floating model picker -> stream response -> expand/maximize tool output.
  10. Rotate phone to landscape -> verify two-pane settings, wider project grid, and navigation responsiveness.

---- STATE 2 ----

Implemented for Early Access/Beta release:

- Fixed P0 onboarding startup race: HomeScreen now waits for AppController initialization before deciding whether to show onboarding, and startup initialization failures render a retry surface instead of hanging behind a spinner.
- Removed OpenAI Codex OAuth from shipped beta provider surfaces. Codex auth types are no longer selectable/resolvable, while legacy stored enum parsing still survives as data compatibility.
- Hardened storage: JSONL malformed rows are quarantined, temp files recover on startup, per-file locks serialize writes, deleted chats reject later writes, and legacy SQLite migration now reads larger persisted text instead of 12k projection loss.
- Reduced streaming persistence/UI pressure with bounded running output, aggregate bash output caps, partial streaming error preservation, and safer concurrent tool update behavior.
- Hardened runtime/tool execution: symlink escapes are rejected, local process trees are killed on cancel, PRoot signals classify as runtime failures, diagnostics redact project paths/secrets, and Android storage settings can be opened from runtime UI when All files access is missing.
- Hid beta-unsafe Anthropic custom provider until native transport exists. Google Antigravity OAuth/model discovery now validates callback port and filters supported Gemini model IDs.
- Completed Syntac branding cutover in Dart, Android, package metadata, native runtime assets, and IDE module names. Legacy identifiers intentionally retained only where external compatibility requires them: SQLite filename/key migration, secure-storage keys, and enum fallback parsing.

Verification:

- `flutter analyze` passed.
- `flutter test` passed: 72 tests.
- `flutter build apk --release` passed.
- Final APK: `build/app/outputs/flutter-apk/app-release.apk`, 151,433,720 bytes, package `com.syntac`; contains `libsyntac_proot*.so` and `assets/runtime/arch-linux-rootfs-v1.bundle`; no `Draxon`/`draxon`/`com.draxon` byte matches in APK.

Pending/manual:

- Real phone validation remains: install release APK, grant storage if prompted, install/repair Arch runtime, run shell test, create project, run streaming chat/tool path, rotate UI, verify diagnostics on failure.

---- STATE 40 ----

Implemented developer/agent navigation docs:

- Added root `PROJECT_STRUCTURE.md` with current Syntac architecture map, data boundaries, startup/chat/runtime flows, add/remove recipes for providers/tools/storage/agent/runtime/UI/branding/runtime bundles, verification commands, and phone validation checklist.
- Replaced stale root `AGENTS.md` with Syntac-specific invariants and quick change map.
- Added scoped `AGENTS.md` files for `lib/src/agent`, `lib/src/ai`, `lib/src/storage`, `lib/src/tools`, `lib/src/runtime`, `lib/src/ui`, Android Kotlin runtime, tests, and scripts so future AI agents/developers can land in relevant code paths quickly.

Verification:

- Confirmed docs include key add/remove recipes.
- Confirmed new docs have no stale `Draxon`/`DRAXON`/`draxon` references.

Pending/manual:

- None for docs.

---- STATE 41 ----

Implemented user/developer repository docs and CI:

- Rewrote `README.md` as a user-first Syntac overview with human-readable feature coverage, platform status, Android/Termux notes, build-from-source steps, signing setup, GitHub Actions notes, author/developer `DraxonV1`, and repo link `https://github.com/DraxonV1/Syntac`.
- Added `CONTRIBUTING.md` with setup, scoped docs to read, project values, in/out-of-scope contribution areas, safety rules for secrets/user files/storage/agent/runtime, PR checklist, and CI/release signing notes.
- Replaced `PROJECT_STRUCTURE.md` with full source-tree map plus ownership notes and add/remove quick map. It now lists root docs, workflows, Android, assets, Flutter source, runtime/native/scripts/tests/third_party areas.
- Added GitHub Actions: `.github/workflows/ci.yml` for format/analyze/tests on push/PR and `.github/workflows/android-apk.yml` for tag/manual release APK builds with optional real signing secrets or temporary CI signing key.
- Added app developer/repository metadata in `AppIdentity`, System settings UI, Android manifest metadata, and `pubspec.yaml` homepage/repository/issue tracker fields.
- Added `android/AGENTS.md` for Android host project rules.

Verification:

- `flutter pub get` passed.
- `dart format lib/src/core/app_identity.dart lib/src/ui/screens/settings_screen.dart` passed.
- `flutter analyze` passed.
- `flutter test test/widget_test.dart` passed: 19 tests.
- Checked docs/workflow files are non-empty, contain no tabs, include DraxonV1/repo/workflow markers, and do not contain stale `com.draxon`, `draxon_coding_agent`, `Draxon Local`, `Alpine`, or old iOS wording.

Pending/manual:

- GitHub Actions need first remote run after pushing to GitHub.

---- STATE 42 ----

Implemented update/distribution prep:

- Added public update manifests under update/ for stable, beta, and nightly channels, all pointing at v0.1.1-beta.2 syntac-arm64.apk with SHA-256 cc90789dbc0d8c9eebdad6804906db1cd24c407f4bd9f613504c9e7f42ebb73e and size 151,441,704 bytes.
- Wired AppIdentity release metadata: developer DraxonV1, repo https://github.com/DraxonV1/Syntac, version 0.1.1-beta.2, versionCode 12, beta channel. Settings now shows version/developer/repo/storage.
- Added UpdateService, Android openUrl bridge, AppController update checks, and HomeScreen UpdateAvailableBanner opening release URL in browser.
- Android APK workflow now requires release signing secrets and fails if they are missing; no temporary public signing key. Local release APK copied to build/app/outputs/flutter-apk/syntac-arm64.apk.

Verification:

- dart format targeted files passed.
- flutter analyze passed.
- flutter test passed: 76 tests.
- flutter build apk --release passed. APK package com.syntac, versionName 0.1.1-beta.2, versionCode 12.

Pending/manual:

- Upload syntac-arm64.apk to GitHub Release v0.1.1-beta.2 and host update/*.json from syntac.com or GitHub Pages. Android phone install/runtime validation still manual.

---- STATE 43 ----

Implemented release/doc hardening after public README concern:

- Removed maintainer-style signing/OAuth secret setup block from public README. README now describes app, contributor flow, CI, and release artifacts without telling users to configure repo secrets.
- CONTRIBUTING now says PRs run CI; accepted changes release from trusted master workflow. No secret names or temporary signing-key guidance in contributor docs.
- Android APK workflow now runs on merges to main/master and version tags, fetches Git LFS, pins Flutter 3.41.9, uses actions/checkout@v5 and actions/setup-java@v5, derives release tag from pubspec for branch releases, force-updates that tag to the merged commit, stamps update manifests from the built APK, uploads the APK artifact, and publishes GitHub Release assets.
- Release signing now fails closed when ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, or ANDROID_KEY_PASSWORD are absent. No more temporary CI signing key for public release automation.
- CI workflow now fetches Git LFS and pins Flutter 3.41.9; latest GitHub CI run #8 passed format, analyze, and tests.

Verification:

- Local: git diff --check passed.
- Local: flutter analyze passed.
- Local: flutter test test/widget_test.dart --plain-name "app identity exposes release metadata" passed.
- GitHub: CI run 33259798589 passed.
- GitHub: Android APK run 33259798622 failed at signing gate with expected missing-secret errors.

Pending/manual:

- Configure real GitHub release signing secrets before merge-to-master APK auto-release can publish a new APK. Current failure is intentional production-safe behavior, not a code failure.
- Untracked logo.png exists locally and was not touched.
