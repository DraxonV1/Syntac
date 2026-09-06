# AGENTS.md

## Scope

`lib/src/` owns Flutter product behavior. Root `AGENTS.md` and `PROJECT_STRUCTURE.md` apply first; child instructions override this file for their directories.

## Boundaries

- Keep orchestration in `app.dart` and domain types in `models.dart`.
- Keep provider protocol/auth code in `ai/`, persistence in `storage/`, secrets in `security/`, runtime adapters in `runtime/`, model-callable operations in `tools/`, and presentation in `ui/`.
- Keep Android-only code in `android/`; do not add platform channels to widgets.
- Keep project files in selected project roots. Keep shared user-visible app data under Android `.syntac`; keep runtime binaries and secrets private.
- Preserve bounded text, cancellation, deleted-chat guards, provider error sanitization, and tool-call ordering.

## Change workflow

1. Read child `AGENTS.md` and `README.md` before editing that area.
2. Search existing contracts and callers before adding symbols or files.
3. Update every affected persistence, UI, provider, platform, and test contract in one change.
4. Update `PROJECT_STRUCTURE.md` and affected folder docs when ownership, paths, or boundaries change.
5. Run focused tests, `flutter analyze`, and release APK build for release-facing changes.

Do not create parallel responsibility folders or leave stale documentation entries.