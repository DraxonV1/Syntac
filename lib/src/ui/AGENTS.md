# AGENTS.md

## Scope

`lib/src/ui/` owns Flutter presentation only. `AppController` in `lib/src/app.dart` owns state and actions.

## Directories

- `screens/`: full pages: home, project chat, providers, runtime status, runtime jobs, settings, chats, project creation.
- `onboarding/`: first-run setup flow and step widgets.
- `chat/`: composer, message view, markdown, model selector, tool call cards.
- `theme/`: colors, typography, motion, icons, app theme.
- `components/` and `widgets/`: reusable surfaces/buttons/cards/overlays.
- `navigation/`: central navigation overlay.

## Change here when

- Adding/removing screen, onboarding step, visible action, setting, or tool rendering.
- Changing layout/responsiveness/theme.

## Invariants

- Do not put persistence/provider/runtime business logic in widgets.
- Call `AppController` actions; keep widgets rebuild-safe.
- Brand strings should come from `AppIdentity` where possible.
- No emoji icons; use `AppIcons`/vector icons.
- Keep portrait and landscape usable.
- Tool cards must show intent before bounded output. Apply-patch cards use line numbers, changed-line colors, compact paths, and delta badges; todo cards show operation target and completion count.
- Shell command cards use monospace bordered command blocks; normal output containers stay transparent, while diffs/code retain intentional surfaces.
- `MarkdownContent` uses `flutter_math_fork` for TeX and supports remote/data-URI images. `SyntaxHighlightedCode` follows active light/dark palette. Never replace TeX with hardcoded symbol substitution.
- Large tool output must use bounded previews and maximizable surfaces.
- Startup must show progress or retry, not blank/hanging UI.

## Tests

Use `test/widget_test.dart` for rendering/component behavior. Use `test/app_foundation_test.dart` when UI depends on controller initialization/onboarding/storage flow.

## Documentation

Keep `README.md` aligned with presentation boundaries, screen ownership, chat card layout, markdown/TeX/image behavior, responsive rules, accessibility expectations, and widget verification. Update `PROJECT_STRUCTURE.md` when UI folders or ownership change.
