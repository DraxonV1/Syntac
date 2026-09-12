# Build Scripts

Scripts prepare packaged Arch rootfs, build/copy Android PRoot binaries, and refresh offline provider model metadata.

Workflow:

1. Change package/runtime inputs in script or source tree.
2. Rebuild generated runtime assets with matching Windows or Python helper.
3. Update pinned hashes/sizes in `LocalRuntimeConfig.kt`.
4. Update runtime fixture data only when structure change is intentional.
5. Run runtime tests and release APK build.

Refresh model metadata:

```sh
python scripts/update_model_catalog.py
```

Script validates required providers, writes Models.dev snapshot verbatim, and records source SHA-256 plus reviewed OMP/DeepSeek policy references in `assets/models/catalog-source.json`. Live provider discovery still decides model availability.

Rules:

- Do not commit unpacked rootfs output or machine-local build products.
- Keep bundle format compatible with `RootfsBundleInstaller.kt`.
- Keep generated paths and archives reproducible.
- Do not modify `.omp-reference/**`.