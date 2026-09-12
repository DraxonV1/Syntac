# Chat UI

## Ownership

`ChatMessageList` renders stable transcript rows. `ComposerView` owns input, attachments, model selection, reasoning effort, and thinking toggle callbacks.

`ToolCallCard` layout:

1. Tool intent/header.
2. Command, patch, or exact write-content block.
3. Bounded result/error details.

Normal command/output containers stay transparent against chat background. Apply-patch diffs and code blocks retain intentional code surfaces. Shell commands use monospace bordered blocks. Apply-patch cards use compact line-numbered colored diffs. Write cards show content without `+` markers or green diff styling, with syntax highlighting and copy support. Todo cards show operation/task intent and bounded completed/total state. Job-log cards show bounded stdout/stderr updates while follow is active. Job-list cards show each job's ID, command, bounded output preview, and orange/green/red state indicator. User `!bashcommand` entries render as user input plus tool output and re-enter future model context as user-owned execution records.
`MarkdownContent` supports fenced code, Unicode, remote/data-URI images, and inline TeX through `flutter_math_fork`. `SyntaxHighlightedCode` switches syntax palette with active display mode. `AnsiText` parses terminal SGR colors, bright/256-color/truecolor values, reset, inverse, bold, italic, and underline. Do not replace TeX with hardcoded symbol maps.

## Change workflow

- Keep card input tolerant of old JSONL records and malformed optional metadata.
- Keep thinking output collapsible, muted, bounded, and separate from answer text.
- Keep image decoding bounded with visible fallback text; never let malformed data crash message build.
- Test collapsed/expanded cards, Bash/patch/write differences, durable job logs, long output, images, TeX, composer toggles, and copy actions.

Run `flutter test test/widget_test.dart`, then analyze and physical Android UI smoke checks for layout changes.