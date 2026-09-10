# AGENTS.md

## Scope

`lib/src/tools/` exposes model-callable project tools.

## Main files

- `agent_tools.dart`: tool specs and dispatch for `read`, `write`, `apply_patch`, `delete`, `list`, `glob`, `search`, `bash`, `jobs.*`, and `copy`.
- `tool_context.dart`: project-root realpath sandbox, explicit read-only systemwide path resolver, output bounds, and local artifact helpers.
- `apply_patch_tool.dart`: bounded multi-file patch parser and atomic project writes.
- `glob_tool.dart`: bounded project file/directory matching.
- `runtime_jobs_tool.dart`: status, log follow, wait, and cancel APIs over durable runtime capability.

## Change here when

- Adding/removing tool.
- Changing tool result schema.
- Changing sandbox/path validation.
- Changing bash output streaming or persistence metadata.

## Invariants

- Normal file paths resolve inside `projectRoot` after symlink/realpath checks.
- `read` systemwide mode requires an absolute path, remains read-only, and blocks sensitive path patterns.
- Reject URI/fake SAF paths and invalid symlink ancestors.
- Bound read/search/bash/job output before returning and before persistence.
- `read` defaults to at most 500 lines; continuation metadata must identify next offset.
- Bash stdout/stderr share aggregate cap; current runtime stream cap is 2,000,000 characters per stream.
- Large command output gets persisted through local artifact references, not unbounded JSONL.
- Running bash and `jobs.logs` updates must be bounded and safe to persist often.
- Tool errors must be structured enough for model and UI, not raw stack traces.
- Keep old stored tool execution records renderable after schema changes.

## Tests

Use `test/app_foundation_test.dart` for file tool contracts, sandbox escapes, bash exit codes, timeout/runtime failure categories, output caps, live output updates, and cancellation behavior.

## Documentation

Keep `README.md` aligned with tool schemas, sandbox rules, output caps, artifact references, update callbacks, compatibility handling, and focused tests. Update `PROJECT_STRUCTURE.md` when tool ownership or files change.
