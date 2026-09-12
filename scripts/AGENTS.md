# AGENTS.md

## Scope

`scripts/` owns Android runtime asset preparation/build helpers and offline model-catalog refresh.

## Files

- `prepare_arch_rootfs.py`: prepares packaged Arch Linux rootfs bundle and manifest fixture inputs.
- `build_android_proot.py`: builds/copies Android PRoot native assets.
- `build_android_proot.ps1`: Windows helper wrapper.
- `update_model_catalog.py`: fetches and validates offline Models.dev metadata plus source provenance.

## Change here when

- Updating rootfs bundle format, manifest, package set, or extraction assumptions.
- Updating native PRoot build/copy process.
- Renaming runtime assets.
- Refreshing bundled offline model metadata; provider availability still comes from live discovery.

## Invariants

- Keep generated rootfs bundle compatible with `RootfsBundleInstaller.kt`.
- Update `LocalRuntimeConfig.kt` pinned hashes/sizes after bundle changes.
- Update `test/fixtures/archlinux_aarch64_pd_v4_29_0_structure.json` and `test/local_runtime_test.dart` with intentional fixture changes.
- Keep model snapshot source, SHA-256, and OMP policy reference in `assets/models/catalog-source.json`.
- Do not place full unpacked rootfs in base source tree.

## Verification

Run `python scripts/update_model_catalog.py` plus model catalog tests after metadata changes. Run runtime fixture tests and release APK build after script/runtime asset changes.

## Documentation

Keep `README.md` aligned with generation inputs, reproducibility rules, pinned asset updates, fixture updates, and verification commands. Update `PROJECT_STRUCTURE.md` when scripts or generated artifacts change.
