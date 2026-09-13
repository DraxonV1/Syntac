# Chat UI

## Ownership

`ChatMessageList` renders stable transcript rows. `ComposerView` owns input, attachments, model selection, reasoning effort, and thinking toggle callbacks.

`ToolCallCard` layout:

1. Tool intent/header.
2. Command, patch, or exact write-content block.
3. Bounded result/error details.

Normal command/output, error, diff, code, and maximized-view containers stay transparent against chat background. Shell commands retain monospace bordered intent blocks. Apply-patch cards use compact line-numbered colored diffs. Write cards show exact content without `+` markers or green diff styling, with syntax highlighting and copy support. Todo cards show operation/task intent and bounded completed/total state. Active todo state also stays visible in bounded panel above composer until every task is completed, abandoned, or removed. Job-log cards show bounded stdout/stderr updates while follow is active. Job-list cards show each job's ID, command, bounded output preview, and orange/green/red state indicator. User `!command` entries retain tool cards without model continuation. Stop controls are icon-only with tooltip/semantic labels; send and attachments remain available during running work.
`MarkdownContent` uses maintained GitHub Web/GFM parsing for headings, nested ordered/unordered/task lists, tables, strikethrough, blockquotes, horizontal rules, links, fenced/inline code, Unicode, remote/data-URI raster or SVG images, and inline/display TeX through `flutter_math_fork`. Completed and streamed messages share rich rendering while hostile-size content falls back to bounded selectable text. `SyntaxHighlightedCode` switches syntax palette with active display mode. `AnsiText` parses terminal SGR colors, bright/256-color/truecolor values, reset, inverse, bold, italic, and underline. Do not replace TeX with hardcoded symbol maps.
Provider failures appear once inside transcript. Composer clears text and pending attachments only after controller accepts message.

## Change workflow

- Keep card input tolerant of old JSONL records and malformed optional metadata.
- Keep thinking output collapsible, muted, bounded, and separate from answer text.
- Keep image decoding bounded with visible fallback text; never let malformed data crash message build.
- Test collapsed/expanded cards, Bash/patch/write differences, durable job logs, long output, images, TeX, composer toggles, and copy actions.

Run `flutter test test/widget_test.dart`, then analyze and physical Android UI smoke checks for layout changes.