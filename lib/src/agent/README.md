# Agent Loop

## Ownership

`agent_loop.dart` owns one chat turn: persist user input, build bounded context, call selected provider, execute grouped tool calls, stream updates, persist assistant/tool messages, and finish job/chat state.

`context_builder.dart` assembles global `agent/SYSTEM.md`, project `.syntac/agent/SYSTEM.md` or `AGENTS.md` overrides, chat history, temporary attachment handles, and context limits. `system_prompt.dart` owns base model instructions.

## Rules

- Keep one active run per chat and reject work for deleted chats.
- Preserve assistant tool-call metadata before matching tool messages.
- Stop active tools on cancellation; never resume model generation afterward.
- Persist partial streamed text before provider/tool failure.
- Keep tool execution and messages scoped to owning chat.
- Keep provider credentials and raw transport errors out of messages and diagnostics.
- Bound every context section and preserve instruction precedence.

## Change workflow

1. Update provider request/event contracts with the corresponding AI transport.
2. Update persistence metadata and replay behavior when stream state changes.
3. Add focused tests for ordering, cancellation, retries, partial output, and deleted-chat races.
4. Keep orchestration in `AppController`/`AgentLoop`; widgets only trigger actions and render state.

Validate changes with focused agent-loop and persistence tests in `test/app_foundation_test.dart`.