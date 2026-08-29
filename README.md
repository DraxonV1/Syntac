# Syntac

Syntac is a local-first Android coding agent by **DraxonV1**.

Open a project folder, connect an AI provider, ask for code changes, review every tool result, and keep the whole session on your device.

- Developer: **DraxonV1**
- Repository: <https://github.com/DraxonV1/Syntac>
- Default update channel: **beta**
- Current version: **0.1.1-beta.2** (`versionCode` 12)
- Current target: Android Early Access / Beta

## Why this app exists

Sometimes you need to inspect or fix code without opening a laptop. Syntac turns an Android phone into a small coding workspace: project files, chat history, tool output, provider settings, and runtime state all stay local unless you call your chosen AI provider.

## What you can do in Syntac

### Work with local projects

- Create a workspace from a folder on your phone.
- Keep the exact folder path you selected.
- Search projects by name or path.
- Open recent projects from the home screen.
- Remove a project from Syntac without deleting its files.
- Use shared-storage paths for Android project folders.

### Chat with a coding agent

- Create separate chats inside each project.
- Continue older chats after restarting the app.
- Stream assistant responses as they are generated.
- Stop a running chat.
- Keep partial assistant text when a provider or network error happens.
- Preserve tool calls, tool results, and chat state in local history.

### Connect AI providers

- Use Google Antigravity / Cloud Code Assist.
- Use OpenAI-compatible APIs.
- Use built-in presets for OpenRouter and DeepSeek.
- Add custom OpenAI-compatible endpoints.
- Refresh live model lists from providers.
- Keep manual model names as fallback options.
- Store API keys and OAuth credentials in secure storage, not chat files.

### Let the agent use tools

The agent can ask to use these project tools:

- `read`: read file content.
- `write`: create or replace files.
- `edit`: replace exact text.
- `delete`: delete files or explicitly requested directories.
- `list`: inspect folders.
- `search`: search project files.
- `bash`: run a shell command in the active project.

Tool safety is part of the app design:

- Paths are checked against the project root.
- Symlink escapes are blocked.
- Output is capped so old chats stay responsive.
- Bash stdout and stderr are shown separately.
- Long command output can be expanded without freezing the chat.

### Run commands on Android

Syntac supports two command runtimes.

#### Arch Linux isolated PRoot runtime

- Installs a packaged Arch rootfs bundle into private app storage.
- Runs commands through a packaged PRoot launcher.
- Mounts your selected project into the runtime.
- Supports install, repair, remove, status, and shell test actions.
- Streams command output while the command is still running.
- Cancels running process trees when you stop a command.

#### Termux RUN_COMMAND bridge

- Uses the Termux app if you prefer an external runtime.
- Sends commands through Termux `RUN_COMMAND`.
- Receives results through an Android callback service.
- Reports missing Termux permissions and background launch restrictions.

Termux setup:

```sh
mkdir -p ~/.termux
printf 'allow-external-apps=true\n' >> ~/.termux/termux.properties
termux-reload-settings
termux-setup-storage
```

Then grant Syntac the Termux command permission from Android settings.

### Manage app state locally

- SQLite stores app metadata.
- JSONL files store chats, messages, tool results, jobs, and attachments.
- Secure storage stores secrets.
- Older SQLite chat data can migrate into JSONL.
- Interrupted JSONL writes are recovered on startup.
- Malformed chat rows are quarantined instead of breaking the whole chat.

### Use a phone-friendly interface

- Home screen for projects and app status.
- Central navigation hub.
- Dedicated Projects, Chats, Providers, Runtime, and Settings screens.
- Floating chat composer.
- Floating model picker.
- Markdown and code rendering.
- Tool cards with compact and expanded views.
- Portrait and landscape layouts.
- System settings with app version, update channel, developer, repository, storage ID, and diagnostics.

## Updates

Syntac checks for updates automatically on startup.

Update flow:

```text
Syntac checks syntac.com and GitHub for the active channel manifest
↓
"v0.1.2 available"
↓
View Update
↓
opens GitHub Release or syntac.com/download in the browser
↓
browser downloads APK
↓
Android handles install prompt
```

Channels:

- `stable`: tested public releases.
- `beta`: default channel right now.
- `nightly`: newest test builds.

Manifest format:

```json
{
  "version": "0.1.1-beta.2",
  "versionCode": 12,
  "apkUrl": "https://github.com/DraxonV1/Syntac/releases/download/v0.1.1-beta.2/syntac-arm64.apk",
  "sha256": "cc90789dbc0d8c9eebdad6804906db1cd24c407f4bd9f613504c9e7f42ebb73e",
  "size": 151441704,
  "mandatory": false,
  "minSupportedVersionCode": 10,
  "notes": [
    "Current Early Access Android APK build",
    "Local chat storage and runtime diagnostics hardened"
  ]
}
```

Current manifests live in:

```text
update/stable.json
update/beta.json
update/nightly.json
```

When `syntac.com` is ready, host the same JSON at:

```text
https://syntac.com/download/stable.json
https://syntac.com/download/beta.json
https://syntac.com/download/nightly.json
```

GitHub fallback path:

```text
https://raw.githubusercontent.com/DraxonV1/Syntac/main/update/<channel>.json
```

## Platform support

| Platform | Status |
| --- | --- |
| Android | Main supported platform for Early Access / Beta. |
| iOS | Not shipped for Early Access. Normal iOS sandboxing blocks unrestricted local bash. |
| Desktop/Web | Not in scope right now. |

## Build from source

### Requirements

- Flutter stable with Dart compatible with `sdk: ^3.11.5`.
- JDK 17.
- Android SDK.
- Android NDK from Flutter/Android tooling.
- Git.
- Physical Android device for runtime testing.

### Clone

```sh
git clone https://github.com/DraxonV1/Syntac.git
cd Syntac
```

### Install dependencies

```sh
flutter pub get
```

### Run checks

```sh
dart format lib test
flutter analyze
flutter test
```

### Build a release APK

Release builds require `android/key.properties`. This file is ignored and must not be committed.

Example local development key:

```sh
keytool -genkeypair \
  -v \
  -keystore android/syntac-release.jks \
  -storepass change-me \
  -keypass change-me \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias syntac \
  -dname "CN=Syntac, OU=Syntac, O=Syntac, L=Unknown, ST=Unknown, C=US"
```

Create `android/key.properties`:

```properties
storeFile=syntac-release.jks
storePassword=change-me
keyAlias=syntac
keyPassword=change-me
```

Build:

```sh
flutter build apk --release
```

APK output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Signing key and package lock

Android package name is locked to:

```text
com.syntac
```

Do not change it after public release unless you are intentionally creating a separate app. Android treats a different package name as a different install.

Use one long-lived release signing key for real builds. Keep it private. Do not commit it.

GitHub Actions release signing secrets:

```text
ANDROID_KEYSTORE_BASE64      base64 of the .jks/.keystore file
ANDROID_KEYSTORE_PASSWORD    keystore password
ANDROID_KEY_ALIAS            key alias inside the keystore
ANDROID_KEY_PASSWORD         key password
```

Optional Google Antigravity OAuth build secrets:

```text
SYNTAC_GOOGLE_OAUTH_CLIENT_ID
SYNTAC_GOOGLE_OAUTH_CLIENT_SECRET
```

If omitted, Google Antigravity sign-in fails safely instead of using embedded repository credentials.

Create base64 value:

```sh
base64 -w 0 syntac-release.jks
```

On macOS, if `-w` is unsupported:

```sh
base64 -i syntac-release.jks | tr -d '\n'
```

The release workflow fails if signing secrets are missing. That is intentional: real update/install compatibility depends on every public APK using the same locked signing key.

## GitHub Actions

Included workflows:

- `CI`: format check, analysis, and tests on push/PR.
- `Android APK`: release APK build on tags or manual dispatch.

## Contributing

Read `CONTRIBUTING.md` before opening a pull request.

Read `PROJECT_STRUCTURE.md` if you want to add or remove providers, tools, runtimes, update channels, storage fields, UI screens, or packaging logic.

## License

No license file is currently included. Ask DraxonV1 before reusing or redistributing this code outside the repository.
