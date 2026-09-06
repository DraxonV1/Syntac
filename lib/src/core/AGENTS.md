# AGENTS.md

## Scope

`lib/src/core/` owns app-wide identity, cancellation primitives, and update checking.

## Files

- `app_identity.dart`: brand, developer, repository, version, channel, and display identity.
- `cancellation.dart`: cancellation tokens shared by agent, tool, and runtime flows.
- `update_service.dart`: stable/beta/nightly manifest lookup and version comparison.

## Rules

- Keep brand strings centralized in `AppIdentity`; do not duplicate names, URLs, versions, or channels in widgets.
- Cancellation must be cooperative, observable, idempotent, and must not resume model generation after stop.
- Update checks must validate channel/manifests, sanitize network failures, and never persist credentials or raw responses.
- Keep platform-specific URL opening in the Android bridge; this layer only requests the action.

## Change workflow

Update callers, tests, README, and `PROJECT_STRUCTURE.md` when public identity, cancellation, update channels, or manifest contracts change. Run focused app/update tests and `flutter analyze`.