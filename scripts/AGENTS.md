# AGENTS.md

## Scope

`scripts/` owns Android runtime asset preparation/build helpers.

## Files

- `prepare_arch_rootfs.py`: prepares packaged Arch Linux rootfs bundle and manifest fixture inputs.
- `build_android_proot.py`: builds/copies Android PRoot native assets.
- `build_android_proot.ps1`: Windows helper wrapper.

## Change here when

- Updating rootfs bundle format, manifest, package set, or extraction assumptions.
- Updating native PRoot build/copy process.
- Renaming runtime assets.

## Invariants

- Keep generated rootfs bundle compatible with `RootfsBundleInstaller.kt`.
- Update `LocalRuntimeConfig.kt` pinned hashes/sizes after bundle changes.
- Update `test/fixtures/archlinux_aarch64_pd_v4_29_0_structure.json` and `test/local_runtime_test.dart` with intentional fixture changes.
- Do not place full unpacked rootfs in base source tree.

## Verification

Run runtime fixture tests and release APK build after script/runtime asset changes.
