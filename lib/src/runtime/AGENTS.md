# AGENTS.md

## Scope

`lib/src/runtime/` owns Dart shell execution abstraction and platform/runtime adapters.

## Main file

- `shell_executor.dart`: `CommandResult`, live `CommandOutputUpdate`, `ShellExecutor`, `RuntimeJobExecutor`, Termux runtime, Arch Linux runtime, local process executor for tests/dev. Runtime jobs are current-session records; only active records may be restored after process-owner restart.
## Change here when

- Adding runtime backend.
- Changing MethodChannel contract.
- Changing command output, cancellation, diagnostics, or runtime status parsing.

## Invariants

- MethodChannel name is `syntac/runtime`.
- Runtime diagnostics must redact local file paths and private app paths.
- Guest command exit code != 0 is command failure, not runtime crash.
- PRoot/native signal or launch failure is runtime failure.
- Native stdout/stderr streams cap at 2,000,000 characters per stream and report truncation.
- Durable job status includes start/finish timestamps, duration, exit code, terminal state, failure kind, restart count, and log truncation metadata for current-session inspection. Completed/cancelled records are not persisted.
- `RuntimeJobExecutor` keeps jobs tools independent from native MethodChannel details.
- Cancellation returns cancelled/interrupted state and must stop native process tree.

## Tests

Use `test/local_runtime_test.dart` for runtime status/diagnostics parsing and fixtures. Use `test/app_foundation_test.dart` for bash behavior through tools/agent loop.

## Documentation

Keep `README.md` aligned with adapter ownership, MethodChannel contracts, shared/private storage boundaries, process-tree cancellation, output limits, diagnostics, and physical-device verification. Update `PROJECT_STRUCTURE.md` when runtime files or ownership change.
