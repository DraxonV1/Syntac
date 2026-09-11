# Project Structure

This file is the map of the Syntac source tree. Start here when you need to know what folder owns what.

Generated/ignored folders such as `build/`, `.dart_tool/`, `.gradle/`, and local signing files are not listed as source. The bundled runtime artifacts are listed because they ship in the APK.

## Repository tree

```text
.
├── README.md
├── CONTRIBUTING.md
├── PROJECT_STRUCTURE.md
├── AGENTS.md
├── STATE.md
├── features.md
├── pubspec.yaml
├── pubspec.lock
├── analysis_options.yaml
├── .gitignore
├── .gitmodules
├── .metadata
├── syntac.iml
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── android-apk.yml
├── update/
│   ├── stable.json
│   ├── beta.json
│   └── nightly.json
├── android/
│   ├── AGENTS.md
│   ├── README.md
│   ├── build.gradle.kts
│   ├── gradle.properties
│   ├── gradlew
│   ├── gradlew.bat
│   ├── local.properties
│   ├── settings.gradle.kts
│   ├── syntac_android.iml
│   ├── gradle/
│   │   └── wrapper/
│   │       ├── gradle-wrapper.jar
│   │       └── gradle-wrapper.properties
│   └── app/
│       ├── build.gradle.kts
│       └── src/
│           └── main/
│               ├── AndroidManifest.xml
│               ├── kotlin/
│               │   └── com/
│               │       └── syntac/
│               │           ├── AGENTS.md
│               │           ├── README.md
│               │           ├── MainActivity.kt
│               │           ├── LocalRuntimeManager.kt
│               │           ├── RuntimeJobSupervisor.kt
│               │           ├── LocalRuntimeConfig.kt
│               │           ├── LocalRunResult.kt
│               │           ├── RootfsBundleInstaller.kt
│               │           ├── TermuxBridge.kt
│               │           ├── TermuxResultService.kt
│               │           └── RuntimeForegroundService.kt
│               ├── jniLibs/
│               │   └── arm64-v8a/
│               │       ├── libsyntac_proot.so
│               │       └── libsyntac_proot_loader.so
│               └── res/
│                   ├── drawable/
│                   ├── drawable-v21/
│                   ├── mipmap-hdpi/
│                   ├── mipmap-mdpi/
│                   ├── mipmap-xhdpi/
│                   ├── mipmap-xxhdpi/
│                   ├── mipmap-xxxhdpi/
│                   ├── values/
│                   └── values-night/
├── assets/
│   └── runtime/
│       └── arch-linux-rootfs-v1.bundle
├── lib/
│   ├── README.md
│   ├── main.dart
│   └── src/
│       ├── AGENTS.md
│       ├── README.md
│       ├── app.dart
│       ├── models.dart
│       ├── agent/
│       │   ├── AGENTS.md
│       │   ├── README.md
│       │   ├── agent_loop.dart
│       │   ├── context_builder.dart
│       │   └── system_prompt.dart
│       ├── ai/
│       │   ├── AGENTS.md
│       │   ├── README.md
│       │   ├── ai_error_messages.dart
│       │   ├── ai_provider.dart
│       │   ├── google_cloud_code_assist_provider.dart
│       │   ├── openai_codex_provider.dart
│       │   ├── provider_diagnostics.dart
│       │   ├── provider_error_store.dart
│       │   ├── auth/
│       │   │   └── credential_store.dart
│       │   ├── oauth/
│       │   │   ├── google_antigravity_oauth.dart
│       │   │   ├── openai_codex_oauth.dart
│       │   │   └── oauth_credential.dart
│       │   └── registry/
│       │       └── provider_registry.dart
│       ├── core/
│       │   ├── AGENTS.md
│       │   ├── README.md
│       │   ├── app_identity.dart
│       │   ├── cancellation.dart
│       │   └── update_service.dart
│       ├── runtime/
│       │   ├── AGENTS.md
│       │   ├── README.md
│       │   └── shell_executor.dart
│       ├── security/
│       │   ├── AGENTS.md
│       │   ├── README.md
│       │   └── secret_store.dart
│       ├── storage/
│       │   ├── AGENTS.md
│       │   ├── README.md
│       │   ├── app_repository.dart
│       │   ├── chat_jsonl_store.dart
│       │   ├── local_database.dart
│       │   └── storage_stats.dart
│       ├── tools/
│       │   ├── AGENTS.md
│       │   ├── README.md
│       │   ├── agent_tools.dart
│       │   ├── apply_patch_tool.dart
│       │   ├── glob_tool.dart
│       │   ├── runtime_jobs_tool.dart
│       │   ├── copy_tool.dart
│       │   └── tool_context.dart
│       └── ui/
│           ├── AGENTS.md
│           ├── README.md
│           ├── chat/
│           │   ├── README.md
│           │   ├── ansi_text.dart
│           │   ├── agent_running_indicator.dart
│           │   ├── chat_message_list.dart
│           │   ├── chat_message_view.dart
│           │   ├── composer_view.dart
│           │   ├── empty_chat_view.dart
│           │   ├── markdown_content.dart
│           │   ├── syntax_highlighted_code.dart
│           │   ├── model_selector_sheet.dart
│           │   └── tool_call_card.dart
│           ├── components/
│           │   ├── animated_hamburger.dart
│           │   ├── glass_surface.dart
│           │   └── wipe_reveal_text.dart
│           ├── navigation/
│           │   └── central_navigation_overlay.dart
│           ├── onboarding/
│           │   ├── onboarding_screen.dart
│           │   ├── steps/
│           │   │   ├── project_step.dart
│           │   │   ├── prompt_step.dart
│           │   │   ├── provider_step.dart
│           │   │   ├── review_step.dart
│           │   │   ├── runtime_step.dart
│           │   │   └── welcome_step.dart
│           │   └── widgets/
│           │       └── oauth_auth_sheet.dart
│           ├── screens/
│           │   ├── chat_sidebar.dart
│           │   ├── chats_screen.dart
│           │   ├── create_project_dialog.dart
│           │   ├── home_screen.dart
│           │   ├── main_chat_screen.dart
│           │   ├── projects_screen.dart
│           │   ├── provider_dialog.dart
│           │   ├── providers_screen.dart
│           │   ├── runtime_jobs_screen.dart
│           │   ├── runtime_screen.dart
│           │   └── settings_screen.dart
│           ├── theme/
│           │   ├── app_colors.dart
│           │   ├── app_icons.dart
│           │   ├── app_motion.dart
│           │   ├── app_theme.dart
│           │   └── app_typography.dart
│           └── widgets/
│               ├── adaptive_sheet.dart
│               ├── app_buttons.dart
│               ├── app_card.dart
│               ├── badge_chip.dart
│               ├── empty_state.dart
│               ├── floating_panel.dart
│               └── maximizable_surface.dart
├── native/
│   └── talloc_compat/
├── scripts/
│   ├── AGENTS.md
│   ├── README.md
│   ├── build_android_proot.py
│   ├── build_android_proot.ps1
│   └── prepare_arch_rootfs.py
├── test/
│   ├── AGENTS.md
│   ├── README.md
│   ├── app_foundation_test.dart
│   ├── local_runtime_test.dart
│   ├── widget_test.dart
│   └── fixtures/
│       └── archlinux_aarch64_pd_v4_29_0_structure.json
└── third_party/
    ├── proot/
    └── termux-proot/
        ├── src/
        │   ├── cli/
        │   ├── execve/
        │   ├── extension/
        │   ├── path/
        │   ├── syscall/
        │   └── tracee/
        └── tests/
```

## What each area owns

### Root files

- `README.md`: user-first app overview, features, build instructions, release notes for humans.
- `CONTRIBUTING.md`: contribution rules and PR checklist.
- `PROJECT_STRUCTURE.md`: living source map and ownership boundaries.
- `AGENTS.md`: global rules for AI agents and developers, including documentation maintenance requirements.
- `STATE.md`: running engineering state log for resumable AI work.
- `features.md`: prioritized Syntac feature roadmap, OMP capability mapping, delivery order, dependencies, and acceptance gates.
- `pubspec.yaml`: Flutter package metadata, dependencies, assets, and SDK constraints.
- `.github/workflows/`: CI and APK build automation.
- `update/`: public update manifests for stable, beta, and nightly channels.

### Flutter app core

- `lib/main.dart`: app entry point.
- `lib/src/app.dart`: `SyntacApp` and `AppController`; coordinates repository, providers, runtime, chats, onboarding, settings, and UI actions.
- `lib/src/models.dart`: IDs, enums, persistence caps, JSON helpers, domain objects.
- `lib/src/core/app_identity.dart`: app name, developer, repository URL, current version, update channel, display strings.
- `lib/src/core/cancellation.dart`: cancellation token used by agent/runtime/tool flows.
- `lib/src/core/update_service.dart`: reads channel update manifests from `syntac.com` or GitHub and decides whether an APK update is newer.

### Agent


- `lib/src/agent/agent_loop.dart`: chat run lifecycle, streaming, tool calls, cancellation, provider retries, job/chat state.
- `lib/src/agent/context_builder.dart`: bounded model context, global `agent/SYSTEM.md`, project `.syntac/agent/SYSTEM.md` or `AGENTS.md` override, attachments, and message trimming. User-run `!bash` results re-enter context as user-owned execution records.
- `lib/src/agent/system_prompt.dart`: base model instructions and tool-use expectations.

### AI providers

- `lib/src/ai/ai_provider.dart`: common provider request/response/event interfaces.
- `lib/src/ai/openai_provider.dart`: OpenAI-compatible chat completions and model listing.
- `lib/src/ai/openai_codex_provider.dart`: ChatGPT Codex OAuth Responses streaming transport.
- `lib/src/ai/google_cloud_code_assist_provider.dart`: Google Antigravity / Cloud Code Assist transport.
- `lib/src/ai/ai_error_messages.dart`: safe user-facing error classification and bounded response display.
- `lib/src/ai/provider_diagnostics.dart`: diagnostics, redaction, and captured request/response metadata.
- `lib/src/ai/provider_error_store.dart`: redacted full provider request/response JSONL under `.syntac/errors/<status>/`.
- `lib/src/ai/auth/credential_store.dart`: credential abstraction.
- `lib/src/ai/oauth/google_antigravity_oauth.dart`: Google OAuth login/refresh/discovery flow.
- `lib/src/ai/oauth/openai_codex_oauth.dart`: ChatGPT Codex OAuth PKCE login/refresh flow.
- `lib/src/ai/oauth/oauth_credential.dart`: OAuth credential model.
- `lib/src/ai/registry/provider_registry.dart`: built-in providers, capabilities, beta visibility, default models.

### Storage

- `lib/src/storage/local_database.dart`: SQLite metadata schema and migrations. Android prefers `/storage/emulated/0/.syntac/syntac.sqlite`, then falls back to app-private storage when shared access is unavailable.
- `lib/src/storage/app_repository.dart`: storage facade used by app, agent, and UI; initializes shared `.syntac/agent/config.yml`, `.syntac/agent/SYSTEM.md`, `.syntac/agent/blobs/`, and `.syntac/agent/sessions/` paths.
- `lib/src/storage/chat_jsonl_store.dart`: JSONL chat index, messages, tool executions, jobs, attachments, migration, recovery. Android stores this under `/storage/emulated/0/.syntac/agent/sessions/`, matching OMP's `agent/sessions` layout under Syntac's shared root. Completed/cancelled runtime jobs are not persisted here.
- `lib/src/storage/storage_stats.dart`: storage breakdown shown in settings.
- `lib/src/security/secret_store.dart`: secure storage boundary for secrets; credentials never move to shared storage.

### Tools

- `lib/src/tools/agent_tools.dart`: model-callable `read`, `write`, `apply_patch`, `delete`, `list`, `glob`, `search`, `bash`, `jobs.*`, and `copy` tools. Owns path sandboxing, output caps, persisted truncation notices, and tool result shape.
- `lib/src/tools/apply_patch_tool.dart`: bounded multi-file patch parser and project-root writes.
- `lib/src/tools/glob_tool.dart`: bounded project-relative file/directory discovery.
- `lib/src/tools/runtime_jobs_tool.dart`: runtime job list/status/log-follow/wait/cancel calls for active and current-session records.

### Runtime

- `android/app/src/main/kotlin/com/syntac/MainActivity.kt`: MethodChannel `syntac/runtime`, runtime status, storage settings, background execution permissions, command routing, and runtime job list/status/log/stop/restart/cancel APIs.
- `LocalRuntimeManager.kt`: Arch Linux PRoot install/run/cancel/remove/self-test, environment/network diagnostics, runtime job launch, and foreground-service lifecycle.
- `RuntimeJobSupervisor.kt`: in-memory Arch job metadata/logs, process ownership, restart/status/log/cancel APIs, lifecycle timestamps, exit codes, truncation counts, and active-job crash recovery state. Terminal records are not persisted.
- `RuntimeForegroundService.kt`: visible Android foreground service for long install/command/job work.
- `RootfsBundleInstaller.kt`: rootfs bundle verification and extraction.
- `LocalRuntimeConfig.kt`: pinned native/runtime asset names, sizes, hashes.
- `LocalRunResult.kt`: native command result and stream-bounding helpers.
- `TermuxBridge.kt`: Termux RUN_COMMAND pending result registry.
- `TermuxResultService.kt`: Termux callback receiver.
- `assets/runtime/arch-linux-rootfs-v1.bundle`: packaged Arch runtime bundle shipped in APK.
- `android/app/src/main/jniLibs/arm64-v8a/`: packaged PRoot native binaries.

### UI

- `lib/src/ui/screens/`: full-screen routes and page-level layout.
- `home_screen.dart`: project dashboard and onboarding gate.
- `main_chat_screen.dart`: active project chat workspace.
- `chat_sidebar.dart`: chat/sidebar navigation.
- `projects_screen.dart`: project list/search/remove.
- `chats_screen.dart`: chat list and filters.
- `providers_screen.dart`: provider list/actions.
- `provider_dialog.dart`: provider create/edit/test form.
- `runtime_screen.dart`: runtime status, install, shell test, storage access, and navigation to jobs.
- `runtime_jobs_screen.dart`: current-session runtime job list, bounded output, cancellation, and restart actions.
- `lib/src/ui/chat/`: chat timeline, composer, tool cards, markdown, TeX, images, model selector, and direct user `!bash` output.
- `lib/src/ui/chat/tool_call_card.dart`: transparent intent/result layout; apply-patch and code blocks retain intentional code surfaces; write cards show exact syntax-highlighted content; job-log cards show bounded live stdout/stderr.
- `lib/src/ui/components/` and `lib/src/ui/widgets/`: reusable cards, buttons, sheets, empty states, glass surfaces, maximizable panels.

### Scripts and native code

- `scripts/prepare_arch_rootfs.py`: builds/prepares rootfs bundle inputs.
- `scripts/build_android_proot.py`: builds/copies Android PRoot assets.
- `scripts/build_android_proot.ps1`: Windows helper wrapper.
- `native/talloc_compat/`: native compatibility support.
- `third_party/proot/`, `third_party/termux-proot/`: PRoot source trees used for native runtime work.

### Tests

- `test/app_foundation_test.dart`: app controller, repository, providers, agent loop, tools, storage, errors.
- `test/local_runtime_test.dart`: runtime status parsing, diagnostics, Arch fixture expectations.
- `test/widget_test.dart`: UI widgets and screen behavior.
- `test/fixtures/`: pinned runtime/rootfs fixtures.

## Add/remove quick map

- Add provider: `lib/src/ai/`, `provider_registry.dart`, `app.dart`, provider UI, `test/app_foundation_test.dart`.
- Remove/hide provider: registry visibility, credential resolution, provider UI, compatibility tests.
- Add tool: `agent_tools.dart`, maybe `agent_loop.dart`, `tool_call_card.dart`, tests.
- Remove tool: remove spec/handler, keep old stored tool cards renderable, update tests.
- Change storage: `local_database.dart`, `app_repository.dart`, `chat_jsonl_store.dart`, `models.dart`, migration/recovery tests.
- Change agent loop: `agent_loop.dart`, `context_builder.dart`, provider contracts, agent-loop tests.
- Change runtime: `shell_executor.dart`, Android Kotlin runtime files, runtime UI, local runtime tests, phone validation.
- Change UI: `lib/src/ui/`, `AppController` only for actions/state, widget tests.
- Change branding/author/repo: `app_identity.dart`, `pubspec.yaml`, Android manifest/Gradle, README/docs/tests.
- Change update flow: `update/*.json`, `lib/src/core/update_service.dart`, `lib/src/app.dart`, home/settings UI, Android `openUrl` bridge, tests.
- Change Android runtime bundle: scripts, `assets/runtime`, `LocalRuntimeConfig.kt`, runtime fixture tests.

## Verification commands

```sh
dart format lib test
flutter analyze
flutter test
flutter build apk --release
```

Release APK path:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Runtime changes still need a real Android phone test.
