# AGENTS.md

## Scope

`lib/src/tools/` exposes model-callable project tools.

## Main file

- `agent_tools.dart`: tool specs, path validation, read/write/edit/delete/list/search/bash handlers, output bounds, live command update plumbing.

## Change here when

- Adding/removing tool.
- Changing tool result schema.
- Changing sandbox/path validation.
- Changing bash output streaming or persistence metadata.

## Invariants

- All file paths resolve inside `projectRoot` after symlink/realpath checks.
- Reject URI/fake SAF paths and invalid symlink ancestors.
- Bound read/search/bash output before returning and before persistence.
- Bash stdout/stderr share aggregate cap.
- Running bash updates must be bounded and safe to persist often.
- Tool errors must be structured enough for model and UI, not raw stack traces.
- Keep old stored tool execution records renderable after schema changes.

## Tests

Use `test/app_foundation_test.dart` for file tool contracts, sandbox escapes, bash exit codes, timeout/runtime failure categories, output caps, live output updates, and cancellation behavior.
