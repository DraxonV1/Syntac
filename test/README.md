# Tests

Tests defend observable contracts.

- `app_foundation_test.dart`: controller, repository, providers, agent loop, tools, storage, migration, and errors.
- `local_runtime_test.dart`: runtime status, diagnostics, output bounds, and pinned fixtures.
- `widget_test.dart`: chat rendering, composer actions, cards, screens, onboarding, and visible states.
- `fixtures/`: deterministic runtime structure data.

Rules:

- Add regression coverage for every behavior change.
- Prefer deterministic temp directories/in-memory databases.
- Assert user-visible behavior, boundaries, transitions, error categories, and security invariants; never source text.
- Keep old-data compatibility tests when changing persistence.
- Run focused file/tests first, then full suite before release claims.