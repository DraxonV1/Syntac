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

## First pull request

PR means pull request: branch diff proposed for review before `master` changes.

1. Fork repository on GitHub if you lack write access.
2. Clone your fork, then create branch: `git switch -c fix/short-description`.
3. Make one focused change. Commit it: `git add <files>` then `git commit -m "fix: short description"`.
4. Push branch: `git push -u origin fix/short-description`.
5. Open GitHub URL printed by push, or select **Compare & pull request**. Base must be `DraxonV1/Syntac:master`; compare must be your branch.
6. Fill summary, tests, and risk. PR does not release or change `master`.
7. CI checks formatting, analysis, and tests. Fix failures on same branch and push again; PR updates automatically.
8. Reviewer may request changes. Reply after pushing fixes. Maintainer merges only approved, green PR.
9. Delete branch after merge. Merged commit remains in `master`.

Repository collaborators can skip fork but still use branch. Never commit feature work directly to `master`.

## How to make good change

1. Find owning files in `PROJECT_STRUCTURE.md`.
2. Read nearest scoped `AGENTS.md`.
3. Make smallest complete change.
4. Add or update tests for observable behavior.
5. Run focused tests, `flutter analyze`, then full tests.
6. Open PR using checklist below.

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

## Risk
- 
```

## GitHub Actions

PRs run CI for formatting, analysis, and tests. PRs never receive signing credentials.

Manual Android workflow builds signed candidate artifact for maintainer testing but does not create or move Git tags. Release only after candidate passes physical Android checks. Maintainer updates `pubspec.yaml`, channel notes, and changelog through PR; merged commit gets immutable matching tag. Tag workflow rejects version mismatch, builds arm64 APK, publishes only matching stable/beta/nightly manifest, then opens generated manifest-sync PR containing exact APK SHA-256 and size. Repository setting **Allow GitHub Actions to create and approve pull requests** must allow PR creation.

## Style

Keep text and UI copy human. Keep code boring. Prefer clear names over clever abstractions. If a change needs a long explanation to feel safe, split it smaller.
