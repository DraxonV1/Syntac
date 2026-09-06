# Application Source

`src/` owns product behavior. Keep platform-specific code in `android/`; keep secrets behind `security/secret_store.dart`.

Storage boundary:

- Android user-visible metadata and chats prefer `/storage/emulated/0/.syntac/`.
- Runtime binaries and platform-required private state stay app-private.
- Project files remain in user-selected project roots.

UI consumes `AppController` actions instead of placing persistence or provider logic in widgets. Provider requests flow through `ai/`; model turns flow through `agent/`; tools flow through `tools/`.