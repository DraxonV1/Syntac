# AGENTS.md

## Scope

`lib/src/agent/` owns prompt construction and the run loop that turns chat messages into model calls, tool executions, persisted updates, and final chat/job state.

## Files

- `agent_loop.dart`: run lifecycle, provider selection, streaming, tool execution, cancellation, job/chat state.
- `context_builder.dart`: bounded context assembly, global/project `AGENTS.md` instruction loading, message trimming.
- `system_prompt.dart`: base model instructions and tool-use expectations.

## Change here when

- Adding/removing model loop behavior.
- Changing context trimming or project instruction precedence.
- Changing tool-call execution order or persistence.
- Changing cancellation/error handling for active chat runs.

## Invariants

- One active run per chat.
- Persist user message before model call.
- Preserve assistant `tool_calls` metadata exactly enough for provider protocol replay.
- Matching tool messages must follow assistant tool-call turn.
- Parallel tool calls from one assistant turn stay grouped correctly.
- Cancellation stops current tool and marks chat/job interrupted.
- After cancellation, do not resume model.
- Partial streamed assistant text must persist on provider/tool error.
- Tool executions/messages stay scoped to owning chat.

## Tests

Use `test/app_foundation_test.dart` for agent loop contracts: duplicate runs, tool calls, malformed tool calls, cancellation, streaming errors, context trimming, provider preflight errors.
