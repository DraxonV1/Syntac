# AGENTS.md

## Scope

`lib/src/ai/` owns provider contracts, transports, diagnostics, OAuth credentials, and registry/default model metadata.

## Files

- `ai_provider.dart`: provider request/response/event interfaces.
- `openai_provider.dart`: OpenAI-compatible `/v1/chat/completions` streaming and `/v1/models`.
- `google_cloud_code_assist_provider.dart`: Google Antigravity/Cloud Code Assist streaming protocol.
- `ai_error_messages.dart`: safe user-facing error classification.
- `provider_diagnostics.dart`: diagnostic maps, redaction, stream metadata.
- `registry/provider_registry.dart`: built-in provider definitions, beta visibility, capabilities.
- `oauth/`: OAuth credential model and Google Antigravity OAuth flow.
- `auth/credential_store.dart`: credential storage abstraction.

## Change here when

- Adding/removing provider, transport, auth type, model discovery, or error mapping.
- Changing stream parsing, tool-call conversion, request payload shape, or diagnostics.

## Invariants

- Raw secrets never enter diagnostics, exceptions, SQLite, JSONL, or tests.
- Stream parsers must handle malformed data as provider errors, not app crashes.
- Provider errors map auth/rate-limit/context/server/network/timeout/malformed categories.
- Registry controls beta-visible providers; UI should filter through registry.
- Manual user models survive refresh/discovery merges.
- Unsupported Google model IDs must be filtered before persistence/use.
- OAuth callback redirects must validate expected port/path.

## Tests

Use `test/app_foundation_test.dart` for provider registry, streaming, tool calls, OAuth exchange/refresh, model discovery, sanitized diagnostics, and beta provider visibility.
