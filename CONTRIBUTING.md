# Contributing to Syntac

Thanks for wanting to help. Syntac is still Early Access, so the best contributions are focused, tested, and easy to review.

- Author / maintainer: **DraxonV1**
- Repository: <https://github.com/DraxonV1/Syntac>

## Before you start

Read these first:

1. `README.md` for what the app does.
2. `PROJECT_STRUCTURE.md` for where things live.
3. The nearest `AGENTS.md` for local rules in the area you are editing.

If you are changing providers, tools, runtime, storage, or the agent loop, please add or update tests. Those areas are load-bearing.

## Project values

Syntac should stay:

- local-first,
- Android-focused for Early Access,
- small enough to understand,
- safe around user files,
- honest about runtime/provider failures,
- careful with secrets,
- tested where behavior matters.

## What is in scope

Good first contributions:

- UI bugs and small usability fixes.
- Clear provider error messages.
- Runtime diagnostics improvements.
- Test coverage for existing behavior.
- Documentation improvements.
- Small provider/model registry updates.
- Safer tool validation.

Bigger contributions are welcome, but should be discussed first:

- New AI provider transports.
- New shell runtime backends.
- Storage format changes.
- Agent-loop behavior changes.
- Large UI rewrites.
- Packaging/runtime bundle changes.

## What is out of scope by default

Please do not add these unless DraxonV1 explicitly asks for them:

- cloud database,
- account system,
- telemetry,
- billing,
- desktop app,
- web app,
- plugin marketplace,
- MCP integration,
- GitHub integration,
- SSH runtime,
- embeddings/vector database,
- bundled full unpacked rootfs in source.

## Setup

```sh
git clone https://github.com/DraxonV1/Syntac.git
cd Syntac
flutter pub get
```

Recommended toolchain:

- Flutter stable with Dart compatible with `sdk: ^3.11.5`.
- JDK 17.
- Android SDK.
- Physical Android phone for runtime validation.

## Day-to-day commands

```sh
dart format lib test
flutter analyze
flutter test
```

Focused examples:

```sh
flutter test test/app_foundation_test.dart
flutter test test/local_runtime_test.dart
flutter test test/widget_test.dart
```

Build release APK:

```sh
flutter build apk --release
```

Release build needs `android/key.properties`. See `README.md` for local signing setup.

## How to make a good change

1. Find owning files in `PROJECT_STRUCTURE.md`.
2. Read the nearest scoped `AGENTS.md`.
3. Make the smallest complete change.
4. Add or update tests for observable behavior.
5. Run focused tests.
6. Run `flutter analyze`.
7. Open a PR with a clear summary and test output.

## Safety rules

### Secrets

Never write API keys, OAuth tokens, refresh tokens, keystore passwords, or user secrets into:

- SQLite,
- JSONL chat files,
- logs,
- diagnostics,
- tests,
- screenshots,
- GitHub Actions output.

Use `SecretStore` and credential abstractions.

### User files

Project files belong to the user. Tool changes must keep path validation strict:

- resolve symlinks,
- stay inside selected project root,
- reject fake/unsupported URI paths,
- do not copy projects silently,
- do not delete source folders when removing a project from Syntac.

### Storage

SQLite stores app metadata. JSONL stores chat-owned runtime data. If you touch JSONL persistence, preserve:

- per-file locks,
- atomic temp replacement,
- startup temp recovery,
- malformed-row quarantine,
- deleted-chat write rejection,
- output/text caps.

### Agent loop

If you touch `AgentLoop`, preserve:

- one active run per chat,
- structured assistant `tool_calls` before matching tool messages,
- cancellation stops tools and does not resume generation,
- partial streamed text survives errors,
- tool updates stay in the owning chat.

### Runtime

Runtime changes need Android validation when possible. At minimum, update Dart-side tests. For real validation, install the release APK on a phone and check:

1. storage permission flow,
2. Arch runtime install/repair,
3. shell self-test,
4. project command execution,
5. cancellation,
6. diagnostics redaction.

## Pull request checklist

Include this in your PR description:

```md
## Summary
- 

## Tests
- [ ] dart format lib test
- [ ] flutter analyze
- [ ] flutter test
- [ ] Android phone runtime check, if runtime/storage/tool behavior changed

## Risk
- 
```

## GitHub Actions

PRs run CI for formatting, analysis, and tests.

Release APK workflow runs on tags like `v1.0.0` or manual dispatch. Maintainers can configure real signing through repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Without signing secrets, the release APK workflow fails. This protects update/install compatibility by keeping public APKs on one locked signing key.

## Style

Keep text and UI copy human. Keep code boring. Prefer clear names over clever abstractions. If a change needs a long explanation to feel safe, split it smaller.
