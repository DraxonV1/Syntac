# AGENTS.md

## Scope

`lib/src/runtime/` owns Dart shell execution abstraction and platform/runtime adapters.

## Main file

- `shell_executor.dart`: `CommandResult`, live `CommandOutputUpdate`, `ShellExecutor`, Termux runtime, Arch Linux runtime, local process executor for tests/dev.

## Change here when

- Adding runtime backend.
- Changing MethodChannel contract.
- Changing command output, cancellation, diagnostics, or runtime status parsing.

## Invariants

- MethodChannel name is `syntac/runtime`.
- Runtime diagnostics must redact local file paths and private app paths.
- Guest command exit code != 0 is command failure, not runtime crash.
- PRoot/native signal or launch failure is runtime failure.
- Cancellation returns cancelled/interrupted state and must stop native process tree.
- Keep `ShellExecutor` abstraction clean; UI/tools should not know native details.

## Tests

Use `test/local_runtime_test.dart` for runtime status/diagnostics parsing and fixtures. Use `test/app_foundation_test.dart` for bash behavior through tools/agent loop.
