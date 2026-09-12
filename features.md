# Syntac Feature Roadmap

Status: planning source for Syntac Android release.

This roadmap maps current Oh My Pi capabilities into Syntac-compatible work. It separates release-critical behavior from optional future work. Product boundaries in `AGENTS.md` remain binding.

## Priority

- **P0 / Must**: required for reliable Android coding-agent use or existing product invariants.
- **P1 / Should**: high-value features compatible with current architecture.
- **P2 / Could**: useful future features after P0/P1 foundations.
- **Excluded**: intentionally outside Syntac product boundary unless separately requested.

## Current baseline

Already implemented:

- Local Android project browser and project-root file sandbox.
- SQLite metadata plus JSONL chat, message, job, tool, attachment storage.
- Secure API-key/OAuth credential storage.
- Streaming providers: OpenAI-compatible, ChatGPT Codex OAuth, Google Antigravity / Cloud Code Assist, Grok OAuth.
- File tools: `read`, `write`, `apply_patch`, `delete`, `list`, `glob`, `search`, `copy`, `display_image`; explicit read-only systemwide diagnostics.
- Bounded Bash through packaged Arch Linux PRoot or Termux `RUN_COMMAND`.
- Arch rootfs install, checksum validation, DNS setup, workspace mounts, cancellation, bounded output, diagnostics.
- Markdown, TeX, code highlighting, images, attachments, tool cards, streaming chat UI.
- Prompt files: global `.syntac/agent/SYSTEM.md`, project `.syntac/agent/SYSTEM.md`, `AGENTS.md`.
- Android foreground-service and battery/notification permission flow for active runtime work.
- Update channels, diagnostics, release APK packaging.
## P0 implementation status

Code delivered in current branch:

- Persistent Arch jobs: background/async Bash flags, timeout `0`, durable `jobId`, app-private registry/logs, foreground-service ownership, status/log/stop/restart/cancel channels, process-tree stop, lifecycle metadata, bounded output, port detection.
- Network safety: explicit Arch `PATH`/`HOME`/temp/locale/terminal/CA environment, proxy preservation, DNS/CA/HTTPS diagnostics.
- Crash containment: supervisor restores running records as `interrupted`, foreground service uses sticky restart only while jobs are active, native failures return structured results.
- Agent safety: Bash risk classification, explicit approval callback, background-job result categories, durable native job state.

Physical arm64 validation remains required before release claim. Dart analyzer and release APK build are verification gates; native service behavior still needs install, app-switch, lock-screen, force-stop, network, and descendant-stop tests on device.

## P0 — Must add now

### 1. Persistent Arch runtime jobs

Fixes FastAPI, Uvicorn, Node servers, workers, and `cloudflared` dying or taking down the active tool call.

- Add `background: true` / `async: true` Bash execution.
- Add `timeout_seconds: 0` meaning no command deadline.
- Return a durable `jobId` immediately after process launch.
- Persist job metadata under app-private runtime storage:
  - command and sanitized arguments
  - project and working directory handle
  - start time and state
  - process identity
  - stdout/stderr ring-buffer paths
  - exit code, signal, and failure category
- Move process ownership into `RuntimeForegroundService`, not Activity-owned threads.
- Add `runtimeJobs`, `jobStatus`, `jobLogs`, `stopJob`, `restartJob`, and `stopAllJobs` channel methods.
- Restore job registry after Activity recreation.
- Use `START_STICKY` only with safe restart policy and explicit user-visible notification state.
- Keep foreground notification while any persistent job is alive.
- Add notification actions for stop and open runtime screen.
- Keep process-tree cancellation; never kill only PRoot parent.
- Keep output bounded and spill full output to local artifacts.
- Show active ports and local URLs when detectable.

Acceptance:

- `python -m uvicorn app:app --host 0.0.0.0 --port 8000` survives app switching and screen lock.
- `cloudflared tunnel --url http://127.0.0.1:8000` stays alive in same Arch network namespace.
- App reopen shows job state and recent logs.
- Stop kills descendants and removes stale registry entries.
- App force-stop is reported as stopped; Android must not silently claim recovery.
- Physical arm64 device test required.

Dependencies: Kotlin runtime supervisor, foreground service lifecycle, persisted job registry, Dart job UI.

### 2. Runtime network reliability

- Preserve `PATH`, `HOME`, `TMPDIR`, `TERM`, locale, proxy, and CA variables when entering Arch.
- Set guest `PATH` explicitly instead of relying on shell defaults.
- Validate `/etc/resolv.conf`, CA bundle, clock/TLS, and IPv4/IPv6 behavior.
- Add network self-test separate from shell self-test:
  - DNS lookup
  - HTTPS request
  - localhost listener
  - outbound tunnel connectivity
- Add runtime diagnostics for network category without leaking paths or secrets.
- Document Android battery, notification, network, and storage requirements.
- Make local bind address and port explicit; do not imply internet exposure from `0.0.0.0`.

Acceptance: Arch `curl`, Python HTTPS, FastAPI localhost, and Cloudflare tunnel work on physical arm64 Android without app crash.

### 3. Runtime crash containment

- Treat guest nonzero exit as command failure.
- Treat PRoot/native signal as runtime failure, never Flutter process failure.
- Catch all native bridge exceptions and return structured results.
- Add crash-safe metadata writes and interrupted-job recovery.
- Prevent duplicate command IDs and stale callbacks.
- Add bounded launch/read/wait threads with guaranteed cleanup.
- Keep Activity destruction independent from runtime process ownership.

### 4. Command approval and safety

- Add risk classification before Bash execution: read-only, workspace write, destructive, network, package install, persistent service.
- Require user confirmation for destructive commands and persistent network services.
- Show exact command, cwd, runtime, ports, timeout, and environment overrides before execution.
- Add per-project approval rules stored locally.
- Never persist secrets in command logs, tool results, SQLite, or JSONL.
- Keep project-root and shared-storage containment checks after realpath/symlink resolution.

### 5. Durable jobs and cancellation hardening

- Extend durable registry to install, provider, and maintenance jobs.
- Keep queued/running/completed/failed/cancelled states persisted.
- Keep cancellation idempotent and observable.
- Do not resume model generation after cancellation.
- Reject jobs for deleted chats/projects.
- Add bounded retry only for infrastructure recovery, never blind command retry.

## P1 — Should add next

### 6. Hashline editing

Replace fragile text-target editing with content-hash anchored `apply_patch` operations.

- Read output includes stable line anchors.
- `apply_patch` accepts anchor ranges plus replacement content.
- Reject stale anchors before writing.
- Render proposed diff before apply.

Acceptance: stale model patch cannot overwrite unrelated changes; line-numbered diff remains visible.

### 7. AST search and AST edit

- Add structural search for Dart, Kotlin, Java, Python, JavaScript/TypeScript, JSON, YAML, and shell where parser support exists.
- Add staged AST edit preview with replacement count.
- Require explicit resolve/apply step for structural rewrites.
- Reject malformed or ambiguous rewrites.
- Keep plain text edit fallback.

Dependency: tree-sitter or equivalent native/Dart parser layer.

### 8. LSP integration

- Add `diagnostics`, `definition`, `references`, `hover`, `rename`, `code_actions`, `type_definition`, and `implementation` operations.
- Run language servers inside Arch when package/toolchain exists.
- Stream bounded diagnostics and restart crashed servers.
- Route rename through workspace file operations.
- Run post-edit diagnostics automatically when server is available.
- Keep LSP optional; file tools must work without it.

Initial servers: Dart analysis server, Python, TypeScript, Kotlin where install size and Android memory allow.

### 9. Structured plan and todo tools

- Add model-callable `todo` with phases and task states.
- Persist todo state per chat.
- Add plan mode requiring review before writes.
- Add plan review, approval, rejection, and resume after interruption.
- Show compact task HUD and full task sheet.
- Keep task state separate from chat prose.

### 10. Async task manager and bounded subagents

- Add `task` tool for independent investigations.
- Return typed/schema-validated results, not prose-only coordination.
- Enforce max depth, max concurrency, memory, and battery budgets.
- Support read-only workers first; add isolated write worktrees only after safe storage design.
- Add job cards, progress, cancel, logs, and result delivery.
- Prevent cross-chat result delivery.

Android default: one worker at a time; user can opt into bounded parallelism.

### 11. Session operations

- Fork chat into a new persisted session.
- Resume sessions by project and globally.
- Navigate message tree and create branches.
- Export chat/tool history to bounded HTML or Markdown.
- Fresh provider state without deleting local transcript.
- Clear context with durable reset boundary.
- Handoff summary into a new session.
- Pin, rename, archive, and safely delete sessions.

Keep existing deleted-chat invariant: deleted chats reject later messages, jobs, and tools.

### 12. Context, rules, and skills

- Discover nearest project instruction files deterministically.
- Support `.syntac/agent/RULES.md` for short sticky rules.
- Support safe `@path` imports with depth, cycle, and project-root guards.
- Add local skills at `.syntac/skills/<name>/SKILL.md`.
- Expose skill metadata in system prompt; load full content on demand.
- Add `skill://name` and `skill://name/relative-file` resolution with traversal protection.
- Add managed local skills only after explicit user request.
- Import existing `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, and similar files without overriding Syntac security rules.

Excluded: remote skill marketplace and untrusted automatic code installation.

### 13. Local durable memory

- Add project-scoped factual memory stored locally.
- Add `retain`, `recall`, `reflect`, and `memory_edit` operations.
- Use bounded lexical/tag search first.
- Keep memory opt-in, inspectable, editable, and deletable.
- Keep secrets and credentials out of memory.
- Separate project memory from user-global memory.

No embeddings required. No cloud memory backend.

### 14. Provider routing

- Add provider/model roles: default, fast, slow, vision, task, reviewer.
- Add per-provider fallback chains for timeout, rate limit, and quota failures.
- Add model capability filtering before selection.
- Add path-scoped provider/model configuration.
- Add credential rotation with secure-storage affinity and backoff.
- Keep provider errors sanitized and structured.

### 15. Better output artifacts

- Persist large Bash/read/search output as local artifacts.
- Add `artifact://` handles in model-visible results.
- Support bounded head/tail previews, byte and line counts, truncation reasons.
- Add copy/export actions from tool cards.
- Keep artifacts project/chat scoped and garbage-collectable.

## P2 — Could add later

### 16. Web research tools

- Add bounded `read` for HTTPS URLs.
- Add `web_search` with pluggable providers and local key storage.
- Add extraction for GitHub, package registries, arXiv, Stack Overflow, documentation, and vulnerability databases.
- Preserve links, anchors, citations, and source metadata.
- Apply domain allowlists, response-size caps, timeout, redirect limits, and secret redaction.

Do not add unrestricted scraping or hidden network calls.

### 17. Local security analysis

- Add local dependency and secret scanning.
- Add SARIF import/export.
- Add finding status, suppression rationale, and scan history.
- Add Android-safe scanners that run inside Arch or packaged native code.
- Keep cloud security scans out unless product boundary changes.

### 18. Interactive terminal and PTY

- Add optional PTY mode for interactive Arch commands.
- Add terminal resize, input, signal forwarding, and visible terminal surface.
- Keep non-PTY tool path for deterministic model calls.
- Never expose unrestricted terminal input without approval.

### 19. Browser and visual inspection

- Add Android WebView/Chrome tab inspection only if user explicitly enables it.
- Keep browser cookies and sessions outside Syntac storage.
- Add screenshots, DOM snapshots, navigation, and bounded interaction.
- Require visible permission and per-domain policy.

Host desktop `computer` control is not part of Android Syntac.

### 20. Voice

- Add optional on-device speech-to-text for prompt entry.
- Add optional text-to-speech for assistant responses.
- Keep model/provider voice data local unless user chooses remote service.
- Add push-to-talk, interruption, and battery controls.

### 21. Local model support

- Add OpenAI-compatible local endpoint configuration.
- Add optional Arch-hosted inference process where device memory permits.
- Add model download, checksum, storage budget, pause/resume, and removal.
- Keep local model providers separate from cloud credentials.

### 22. Local integration APIs

- Add localhost JSON-RPC or NDJSON mode for automation.
- Add Android intent/deep-link entry points for opening projects/chats.
- Add SDK only if a stable Syntac session contract exists.
- Keep APIs local-only by default with explicit authentication for remote use.

### 23. Collaboration without cloud dependency

- Add encrypted local-network session sharing only after threat model and permission design.
- Keep read-only sharing as default.
- Show participant identity and revoke controls.
- Never expose provider secrets or raw secure-storage values.

## OMP feature mapping

| OMP capability | Syntac decision |
| --- | --- |
| `read`, `write`, `edit`, `glob`, `grep` | Already present; improve anchors, AST, and artifacts |
| `bash` persistent shell, PTY, async jobs | P0; core fix for FastAPI/cloudflared |
| `eval` persistent Python/JavaScript | P1/P2; start with Python only inside Arch |
| `ast_grep`, `ast_edit` | P1 |
| `lsp` | P1 |
| `debug` / DAP | P2 after LSP and process supervisor |
| `task`, `hub` | P1 with Android resource limits |
| `todo`, plan, goal, workflow modes | P1; local structured state |
| advisor reviewer model | P2; opt-in cost and battery control |
| web search and URL readers | P2; bounded network/security design |
| GitHub/issue/PR tools | Excluded by current product boundary |
| memory tools | P1 with local lexical storage; no embeddings |
| skills and context discovery | P1, local-only |
| MCP/plugin marketplace | Excluded by current product boundary |
| browser relay and desktop computer | Excluded for Android-first product |
| TTS/STT | P2, optional Android capability |
| ACP/RPC/SDK | P2, only after stable local protocol |
| collaboration relay/share server | Excluded unless cloud boundary changes; local LAN may be revisited |
| cloud telemetry/usage dashboard | Excluded |
| cloud DB, accounts, billing | Excluded |

## Delivery order

1. Persistent Arch jobs and runtime supervisor.
2. Network diagnostics and crash containment.
3. Command approval, durable cancellation, and artifact storage.
4. Hashline edits and structured todo/plan mode.
5. LSP and AST operations.
6. Session fork/resume/tree and local skills.
7. Bounded subagents and local memory.
8. Provider roles/fallbacks.
9. Web research and local security analysis.
10. PTY, debugging, voice, browser, local models, and local protocol APIs.

## Non-negotiable acceptance gates

- Android release APK builds with pinned native/runtime assets.
- `flutter analyze` and focused/full Flutter tests pass.
- Runtime/storage changes pass physical arm64 Android validation.
- No secrets in SQLite, JSONL, logs, artifacts, diagnostics, or model-visible errors.
- Project files remain inside selected project roots after realpath/symlink checks.
- Output remains bounded and truncation is explicit.
- Cancellation stops active process trees and never resumes generation.
- Deleted chats/projects reject later work.
- Every new background capability has visible status, cancellation, recovery, and failure reporting.

## Reference source

Latest OMP compatibility audit: upstream `main`, commit `e24466515dae616f4027170027245c6222f28ab2`. Source inspected in detached external worktree; provenance recorded in `assets/models/catalog-source.json`.

Key source/docs reviewed:

- `packages/catalog/src/compat/rules/providers/deepseek.kdl`
- `packages/catalog/src/provider-models/descriptors.ts`
- `packages/coding-agent/src/edit/`
- `packages/coding-agent/src/tools/todo.ts`
- `packages/coding-agent/src/tools/builtin-names.ts`
- `docs/bash-tool-runtime.md`
- DeepSeek official thinking-mode and tool-call documentation
