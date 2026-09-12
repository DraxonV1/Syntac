# User Interface

## Ownership

Screens coordinate visible state through `AppController`. Reusable presentation belongs in `components/`, `theme/`, or `widgets/`.

`chat/` owns transcript rows, composer controls, persistent active-todo presentation, model selection, tool cards, markdown, image rendering, TeX rendering, syntax highlighting, and thinking disclosure. `onboarding/steps/provider_step.dart` owns user-visible provider connection choices, including native DeepSeek setup. `screens/runtime_screen.dart` owns runtime capability/status; `screens/runtime_jobs_screen.dart` owns current-session job inspection and controls. Keep persistence, provider calls, and runtime execution outside widgets.

## Rules

- Render state from controller inputs; do not open databases, call providers, or execute commands from build methods.
- Keep provider/auth failures inside provider surfaces; only initialization and onboarding-state failures may replace the app with the startup error view.
- Keep streamed and tool output bounded before creating widget trees.
- Preserve copy, maximize, expand/collapse, error, loading, and cancellation affordances.
- Show at most the first 300 persisted code/content lines inline. Copy and maximize must retain complete persisted value, including large write arguments.
- Keep running tool cards mounted while streamed arguments and partial execution output replace their visible state.
- Use semantic labels, readable contrast, touch targets, keyboard-safe layouts, and dynamic light/dark tokens from `theme/`.
- Keep code in `SyntaxHighlightedCode`, math in `flutter_math_fork`, and images behind bounded/failing widgets; never hardcode symbol substitutions.
- Keep screen navigation and modal ownership at screen level.

## Change workflow

1. Update the owning widget and its visible-state tests.
2. Preserve old stored tool/chat records as renderable input.
3. Verify narrow and wide layouts, long output, empty/error/loading states, and accessibility labels.
4. Use Flutter widget tests and physical Android checks for this app.

Use `test/widget_test.dart` for visible behavior and `test/app_foundation_test.dart` for controller integration.