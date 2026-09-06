# User Interface

## Ownership

Screens coordinate visible state through `AppController`. Reusable presentation belongs in `components/`, `theme/`, or `widgets/`.

`chat/` owns transcript rows, composer controls, model selection, tool cards, markdown, image rendering, TeX rendering, syntax highlighting, and thinking disclosure. Keep persistence, provider calls, and runtime execution outside widgets.

## Rules

- Render state from controller inputs; do not open databases, call providers, or execute commands from build methods.
- Keep streamed and tool output bounded before creating widget trees.
- Preserve copy, maximize, expand/collapse, error, loading, and cancellation affordances.
- Use semantic labels, readable contrast, touch targets, keyboard-safe layouts, and dark-theme tokens from `theme/`.
- Keep code in `SyntaxHighlightedCode`, math in `flutter_math_fork`, and images behind bounded/failing widgets; never hardcode symbol substitutions.
- Keep screen navigation and modal ownership at screen level.

## Change workflow

1. Update the owning widget and its visible-state tests.
2. Preserve old stored tool/chat records as renderable input.
3. Verify narrow and wide layouts, long output, empty/error/loading states, and accessibility labels.
4. Use Flutter widget tests and physical Android checks for this app.

Use `test/widget_test.dart` for visible behavior and `test/app_foundation_test.dart` for controller integration.