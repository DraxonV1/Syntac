# Build Scripts

Scripts prepare the packaged Arch rootfs and build/copy Android PRoot binaries.

Workflow:

1. Change package/runtime inputs in script or source tree.
2. Rebuild generated runtime assets with matching Windows or Python helper.
3. Update pinned hashes/sizes in `LocalRuntimeConfig.kt`.
4. Update runtime fixture data only when structure change is intentional.
5. Run runtime tests and release APK build.

Rules:

- Do not commit unpacked rootfs output or machine-local build products.
- Keep bundle format compatible with `RootfsBundleInstaller.kt`.
- Keep generated paths and archives reproducible.
- Do not modify `.omp-reference/**`.