# Project Tools

`agent_tools.dart` exposes sandboxed `read`, `write`, `edit`, `delete`, `list`, `search`, `bash`, and `copy` operations.

## Rules

- Resolve every path inside selected project root after lexical, realpath, and symlink checks.
- Keep file reads at 500 lines or `maxReadBytes`; use `startLine`/`nextStartLine` for continuation.
- Keep search results page-sized and report skipped files or additional matches.
- Keep Bash output at 50 preview lines and bounded characters. Persist full bounded output under project `.syntac/agent/blobs/` and return `local://` reference when preview truncates.
- Attachment paths are temporary `local://attachment-N` handles. Use `copy` with an explicit destination to retain a user attachment before editing it.
- Keep running updates bounded; final result must preserve exit code, timeout, cancellation, runtime failure, truncation, and artifact metadata.
- Never leak raw stack traces or secrets into model-visible results.

## Change workflow

1. Update tool schema and handler together.
2. Preserve result keys consumed by `AgentLoop`, JSONL persistence, and `ToolCallCard`.
3. Add focused tests for boundaries, continuation, artifacts, failures, and cancellation.
4. Update `AGENTS.md` and `PROJECT_STRUCTURE.md` when tool ownership or limits change.