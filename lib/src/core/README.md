# Core

`core/` contains cross-cutting primitives used by app orchestration without owning persistence, provider transport, runtime execution, or UI.

## Ownership

- `app_identity.dart` is single source for Syntac brand, repository, developer, version, and update channel.
- `cancellation.dart` defines shared stop signals for agent, tools, and shell runtimes.
- `update_service.dart` reads and compares public update manifests.

## Change rules

Keep identity values centralized. Keep cancellation idempotent and safe across already-finished work. Keep update errors user-safe and response data bounded. Platform bridges open URLs; core does not call Android APIs directly.

When changing contracts, update all callers, focused tests, `AGENTS.md`, and `PROJECT_STRUCTURE.md`. Verify with app foundation/update tests and `flutter analyze`.