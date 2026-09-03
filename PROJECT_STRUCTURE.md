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
│               │           ├── MainActivity.kt
│               │           ├── LocalRuntimeManager.kt
│               │           ├── LocalRuntimeConfig.kt
│               │           ├── LocalRunResult.kt
│               │           ├── RootfsBundleInstaller.kt
│               │           ├── TermuxBridge.kt
│               │           └── TermuxResultService.kt
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
│   ├── main.dart
│   └── src/
│       ├── app.dart
│       ├── models.dart
│       ├── agent/
│       │   ├── AGENTS.md
│       │   ├── agent_loop.dart
│       │   ├── context_builder.dart
│       │   └── system_prompt.dart
│       ├── ai/
│       │   ├── AGENTS.md
│       │   ├── ai_error_messages.dart
│       │   ├── ai_provider.dart
│       │   ├── google_cloud_code_assist_provider.dart
│       │   ├── openai_codex_provider.dart
│       │   ├── openai_provider.dart
│       │   ├── provider_diagnostics.dart
│       │   ├── auth/
│       │   │   └── credential_store.dart
│       │   ├── oauth/
│       │   │   ├── google_antigravity_oauth.dart
│       │   │   ├── openai_codex_oauth.dart
│       │   │   └── oauth_credential.dart
│       │   └── registry/
│       │       └── provider_registry.dart
│       ├── core/
│       │   ├── app_identity.dart
│       │   ├── cancellation.dart
│       │   └── update_service.dart
│       ├── runtime/
│       │   ├── AGENTS.md
│       │   └── shell_executor.dart
│       ├── security/
│       │   └── secret_store.dart
│       ├── storage/
│       │   ├── AGENTS.md
│       │   ├── app_repository.dart
│       │   ├── chat_jsonl_store.dart
│       │   ├── local_database.dart
│       │   └── storage_stats.dart
│       ├── tools/
│       │   ├── AGENTS.md
│       │   └── agent_tools.dart
│       └── ui/
│           ├── AGENTS.md
│           ├── chat/
│           │   ├── agent_running_indicator.dart
│           │   ├── chat_message_list.dart
│           │   ├── chat_message_view.dart
│           │   ├── composer_view.dart
│           │   ├── empty_chat_view.dart
│           │   ├── markdown_content.dart
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
│   ├── build_android_proot.py
│   ├── build_android_proot.ps1
│   └── prepare_arch_rootfs.py
├── test/
│   ├── AGENTS.md
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
- `PROJECT_STRUCTURE.md`: this source map.
- `AGENTS.md`: global rules for AI agents and developers.
- `STATE.md`: running engineering state log for resumable AI work.
- `pubspec.yaml`: Flutter package metadata, app version, dependencies, assets.
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

- `lib/src/agent/agent_loop.dart`: chat run lifecycle, streaming, tool calls, cancellation, provider retries, job state.
- `lib/src/agent/context_builder.dart`: bounded model context and global/project `AGENTS.md` loading.
- `lib/src/agent/system_prompt.dart`: base system instructions sent to models.

### AI providers

- `lib/src/ai/ai_provider.dart`: common provider request/response/event interfaces.
- `lib/src/ai/openai_provider.dart`: OpenAI-compatible chat completions and model listing.
- `lib/src/ai/openai_codex_provider.dart`: ChatGPT Codex OAuth Responses streaming transport.
- `lib/src/ai/google_cloud_code_assist_provider.dart`: Google Antigravity / Cloud Code Assist transport.
- `lib/src/ai/ai_error_messages.dart`: safe user-facing error classification.
- `lib/src/ai/provider_diagnostics.dart`: diagnostics and redaction.
- `lib/src/ai/auth/credential_store.dart`: credential abstraction.
- `lib/src/ai/oauth/google_antigravity_oauth.dart`: Google OAuth login/refresh/discovery flow.
- `lib/src/ai/oauth/openai_codex_oauth.dart`: ChatGPT Codex OAuth PKCE login/refresh flow.
- `lib/src/ai/oauth/oauth_credential.dart`: OAuth credential model.
- `lib/src/ai/registry/provider_registry.dart`: built-in providers, capabilities, beta visibility, default models.

### Storage

- `lib/src/storage/local_database.dart`: SQLite metadata schema and migrations.
- `lib/src/storage/app_repository.dart`: storage facade used by app, agent, and UI.
- `lib/src/storage/chat_jsonl_store.dart`: JSONL chat index, messages, tool executions, jobs, attachments, migration, recovery.
- `lib/src/storage/storage_stats.dart`: storage breakdown shown in settings.
- `lib/src/security/secret_store.dart`: secure storage boundary for secrets.

### Tools

- `lib/src/tools/agent_tools.dart`: model-callable `read`, `write`, `edit`, `delete`, `list`, `search`, and `bash` tools. Owns path sandboxing, output caps, and tool result shape.

### Runtime

- `lib/src/runtime/shell_executor.dart`: shell abstraction, local process executor, Termux runtime adapter, Arch Linux runtime adapter, command output streaming, diagnostics redaction.
- `android/app/src/main/kotlin/com/syntac/MainActivity.kt`: MethodChannel `syntac/runtime`, runtime status, storage settings, command routing.
- `LocalRuntimeManager.kt`: Arch Linux PRoot install/run/cancel/remove/self-test.
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
- `runtime_screen.dart`: runtime status, install, shell test, storage access.
- `settings_screen.dart`: settings categories, diagnostics, system info.
- `create_project_dialog.dart`: project creation flow.
- `lib/src/ui/onboarding/`: first-run wizard.
- `lib/src/ui/chat/`: chat message rendering, composer, model selector, tool cards, markdown.
- `lib/src/ui/theme/`: colors, typography, motion, icon system, Flutter theme.
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
