# AI Providers

## Ownership

- `ai_provider.dart` defines provider-neutral requests, responses, tool calls, reasoning events, and errors. Concrete transports implement protocol behavior only.

`registry/` controls supported providers, capabilities, beta visibility, and defaults. `oauth/` owns login/refresh/discovery. `auth/` owns credential access. `provider_error_store.dart` writes redacted full request/response diagnostics by HTTP status and chat ID.

## Rules

- Keep API keys, OAuth tokens, refresh tokens, authorization codes, and cookies out of logs, diagnostics, persistence, and tests.
- Convert malformed streams and HTTP failures into sanitized provider errors, never uncaught UI failures.
- Preserve tool-call ordering, reasoning metadata, cancellation, and replay fields.
- Emit provider reasoning configuration only for transports/models that support it; map effort to each wire protocol's bounded values.
- Filter unsupported discovered models before persistence; preserve manual models during refresh merges.
- Validate OAuth callback port/path and state before exchanging codes.
- Keep provider-specific JSON mapping inside provider files; do not leak transport details into UI or `AgentLoop`.

## Change workflow

1. Update the common request/event contract only when at least one provider needs a durable observable field.
2. Update every affected transport, registry capability, auth path, and persistence/replay test.
3. Add protocol fixtures for streaming text, tool calls, reasoning, malformed data, auth failures, cancellation, and captured error payloads.
4. Sanitize all user-facing errors, bound displayed response bodies, persist redacted diagnostics, and run focused provider tests before full validation.

Run focused provider, stream, OAuth, discovery, and diagnostics tests in `test/app_foundation_test.dart`.