import 'dart:convert';

import 'package:syntac/src/agent/agent_loop.dart';
import 'package:syntac/src/models.dart';
import 'package:syntac/src/ui/chat/ansi_text.dart';
import 'package:syntac/src/ui/chat/chat_message_list.dart';
import 'package:syntac/src/ui/chat/composer_view.dart';
import 'package:syntac/src/ui/chat/empty_chat_view.dart';
import 'package:syntac/src/ui/chat/markdown_content.dart';
import 'package:syntac/src/ui/chat/model_selector_sheet.dart';
import 'package:syntac/src/ui/chat/tool_call_card.dart';
import 'package:syntac/src/ui/widgets/badge_chip.dart';
import 'package:syntac/src/ui/widgets/status_indicator.dart';
import 'package:syntac/src/ui/screens/home_screen.dart';
import 'package:syntac/src/ui/theme/app_colors.dart';
import 'package:syntac/src/ui/theme/app_theme.dart';
import 'package:syntac/src/core/app_identity.dart';
import 'package:syntac/src/ui/onboarding/steps/welcome_step.dart';
import 'package:syntac/src/ui/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:syntac/src/ui/components/animated_hamburger.dart';
import 'package:syntac/src/ui/components/wipe_reveal_text.dart';
import 'package:syntac/src/ui/navigation/central_navigation_overlay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_math_fork/flutter_math.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: ThemeMode.dark,
    home: Scaffold(body: child),
  );
}

void main() {
  test('deterministic chat titles do not require a model', () {
    expect(titleFromPrompt('Fix navbar'), 'Fix navbar');
    expect(titleFromPrompt(''), 'New chat');
    expect(
      titleFromPrompt(
        'Implement authentication with JSON web tokens and session store',
      ),
      'Implement authentication with JSON web tokens...',
    );
  });

  testWidgets('StatusIndicator renders correct status colors', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Column(
          children: [
            StatusIndicator(status: ChatStatus.running),
            StatusIndicator(status: ChatStatus.completed),
            StatusIndicator(status: ChatStatus.error),
          ],
        ),
      ),
    );

    expect(find.byType(StatusIndicator), findsNWidgets(3));
  });

  testWidgets('chat list opens and switches chats at latest message', (
    tester,
  ) async {
    final firstMessages = List<ChatMessage>.generate(
      60,
      (index) => ChatMessage.create(
        chatId: 'chat-1',
        role: MessageRole.user,
        content: 'Message $index',
      ),
    );
    final secondMessages = List<ChatMessage>.generate(
      60,
      (index) => ChatMessage.create(
        chatId: 'chat-2',
        role: MessageRole.user,
        content: 'Other message $index',
      ),
    );

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          height: 220,
          child: ChatMessageList(
            chatId: 'chat-1',
            messages: firstMessages,
            toolExecutions: const [],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    var list = tester.widget<ListView>(
      find.byKey(const ValueKey('chat-message-list-scroll')),
    );
    expect(
      list.controller!.offset,
      closeTo(list.controller!.position.maxScrollExtent, 0.1),
    );

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          height: 220,
          child: ChatMessageList(
            chatId: 'chat-2',
            messages: secondMessages,
            toolExecutions: const [],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    list = tester.widget<ListView>(
      find.byKey(const ValueKey('chat-message-list-scroll')),
    );
    expect(
      list.controller!.offset,
      closeTo(list.controller!.position.maxScrollExtent, 0.1),
    );
  });

  testWidgets('light mode uses readable dark text tokens', (tester) async {
    final previous = AppColors.lightMode;
    AppColors.lightMode = true;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          themeMode: ThemeMode.light,
          home: const Text('Readable light text'),
        ),
      );

      expect(
        AppTheme.lightTheme.textTheme.bodyLarge!.color,
        AppColors.textPrimary,
      );
      expect(AppTheme.lightTheme.colorScheme.onSurface, AppColors.textPrimary);
    } finally {
      AppColors.lightMode = previous;
    }
  });

  testWidgets('ANSI output renders styled spans without escape sequences', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AnsiText(
          text: '\u001b[31mred\u001b[0m plain \u001b[38;2;0;128;255mblue',
        ),
      ),
    );

    final rendered = tester.widget<SelectableText>(find.byType(SelectableText));
    final spans = rendered.textSpan!.children!.cast<TextSpan>();
    expect(
      spans.map((span) => span.text),
      containsAll(['red', ' plain ', 'blue']),
    );
    expect(spans.first.style!.color, isNot(AppColors.textPrimary));
    expect(spans.last.style!.color, const Color(0xFF0080FF));
    expect(find.textContaining('\u001b['), findsNothing);
  });
  testWidgets('BadgeChip renders diff and metadata badges', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            BadgeChip.diff(added: 14, removed: 3),
            BadgeChip.success(label: 'Completed'),
            BadgeChip.error(label: 'Failed'),
          ],
        ),
      ),
    );

    expect(find.text('+14 -3'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
  });

  testWidgets('MarkdownContent renders headings, text, and code blocks', (
    tester,
  ) async {
    const markdown = '''
# Overview
This is a test description with `inline_code`.

```dart
void main() {
  print("hello");
}
```
''';

    await tester.pumpWidget(
      _wrap(
        const SingleChildScrollView(child: MarkdownContent(content: markdown)),
      ),
    );

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('inline_code'), findsOneWidget);
    expect(find.text('dart'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.textContaining('void main()'), findsOneWidget);
  });
  testWidgets('MarkdownContent renders TeX and embedded base64 images', (
    tester,
  ) async {
    const markdown =
        r'Equation: $\frac{a}{b} + \alpha$ ![pixel](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=)';

    await tester.pumpWidget(
      _wrap(
        const SingleChildScrollView(child: MarkdownContent(content: markdown)),
      ),
    );
    await tester.pump();

    expect(find.byType(Math), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('MarkdownContent survives malformed TeX', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SingleChildScrollView(
          child: MarkdownContent(content: r'Broken math: $\frac{'),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining(r'\frac{'), findsOneWidget);
  });

  testWidgets('MarkdownContent bounds hostile 500KB response', (tester) async {
    final content = 'x' * 500000;
    await tester.pumpWidget(
      _wrap(SingleChildScrollView(child: MarkdownContent(content: content))),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('content truncated for display'),
      findsOneWidget,
    );
  });

  testWidgets('MarkdownContent caps pathological list and streaming trees', (
    tester,
  ) async {
    final list = List.generate(1000, (index) => '- item $index').join('\n');
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: Column(
            children: [
              MarkdownContent(content: list),
              const MarkdownContent(
                content: '```dart\nfinal value = 1;\n```',
                streaming: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(MarkdownContent), findsNWidgets(2));
  });

  testWidgets('ToolCallCard renders collapsed bash and expands on tap', (
    tester,
  ) async {
    final execution = ToolExecution(
      id: 'tool_1',
      chatId: 'chat_1',
      name: 'bash',
      argumentsJson: '{"command": "flutter test"}',
      status: ToolExecutionStatus.success,
      startedAt: DateTime.now().subtract(const Duration(seconds: 3)),
      finishedAt: DateTime.now(),
      resultJson:
          '{"ok": true, "result": {"command": "flutter test", "workingDirectory": "/tmp/project", "stdout": "All tests passed!", "stderr": "", "exitCode": 0, "durationMs": 3200, "success": true, "category": "success"}}',
    );

    await tester.pumpWidget(
      _wrap(ToolCallCard(execution: execution, initiallyExpanded: false)),
    );

    expect(find.text('Bash'), findsOneWidget);
    expect(find.text('flutter test'), findsOneWidget);
    expect(find.text('3.2s'), findsOneWidget);

    // Tap to expand
    await tester.tap(find.text('Bash'));
    await tester.pumpAndSettle();

    expect(find.text('All tests passed!'), findsOneWidget);
    final highlight = tester.widget<HighlightView>(
      find.byType(HighlightView).last,
    );
    expect(highlight.theme['root']?.backgroundColor, Colors.transparent);
  });

  testWidgets('ToolCallCard shows bash exit failures and stderr', (
    tester,
  ) async {
    final execution = ToolExecution(
      id: 'tool_fail',
      chatId: 'chat_1',
      name: 'bash',
      argumentsJson: '{"command": "false"}',
      status: ToolExecutionStatus.error,
      startedAt: DateTime.now().subtract(const Duration(milliseconds: 42)),
      finishedAt: DateTime.now(),
      resultJson:
          '{"ok": true, "result": {"command": "false", "workingDirectory": "/tmp/project", "stdout": "", "stderr": "", "exitCode": 1, "durationMs": 42, "success": false, "category": "command_exit_error"}}',
    );

    await tester.pumpWidget(
      _wrap(ToolCallCard(execution: execution, initiallyExpanded: true)),
    );

    expect(find.text('exit 1'), findsOneWidget);
    expect(find.text('(no output)'), findsOneWidget);
  });

  testWidgets('ToolCallCard renders write content preview', (tester) async {
    final execution = ToolExecution(
      id: 'tool_write',
      chatId: 'chat_1',
      name: 'write',
      argumentsJson:
          '{"path": "lib/main.txt", "content": "first line\\nsecond line"}',
      status: ToolExecutionStatus.success,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      resultJson:
          '{"ok": true, "result": {"path": "lib/main.txt", "bytes": 22}}',
    );

    await tester.pumpWidget(
      _wrap(ToolCallCard(execution: execution, initiallyExpanded: true)),
    );

    expect(find.text('CONTENT'), findsOneWidget);
    expect(find.textContaining('first line'), findsOneWidget);
    expect(find.textContaining('+first line'), findsNothing);
  });

  testWidgets('ToolCallCard renders apply patch diff preview', (tester) async {
    final execution = ToolExecution(
      id: 'tool_apply_patch',
      chatId: 'chat_1',
      name: 'apply_patch',
      argumentsJson: '{"patch": "*** Begin Patch ..."}',
      status: ToolExecutionStatus.success,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      resultJson:
          '{"ok": true, "result": {"changedFiles": [{"path": "lib/main.txt"}], "diff": "*** Begin Patch\\n- old line\\n+ new line\\n*** End Patch"}}',
    );

    await tester.pumpWidget(
      _wrap(ToolCallCard(execution: execution, initiallyExpanded: true)),
    );

    expect(find.text('Apply patch'), findsOneWidget);
    expect(find.text('PATCH'), findsOneWidget);
    expect(find.textContaining('- old line'), findsOneWidget);
    expect(find.textContaining('+ new line'), findsOneWidget);
  });

  testWidgets('ToolCallCard renders apply patch file badge', (tester) async {
    final execution = ToolExecution(
      id: 'tool_2',
      chatId: 'chat_1',
      name: 'apply_patch',
      argumentsJson: '{"patch": "*** Begin Patch ..."}',
      status: ToolExecutionStatus.success,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      resultJson:
          '{"path": "lib/auth.dart", "changedFiles": [{"path": "lib/auth.dart"}]}',
    );

    await tester.pumpWidget(_wrap(ToolCallCard(execution: execution)));

    expect(find.text('Apply patch'), findsOneWidget);
    expect(find.text('1 files'), findsOneWidget);
  });

  testWidgets('ToolCallCard summarizes persistent todo progress', (
    tester,
  ) async {
    final execution = ToolExecution(
      id: 'tool_todo',
      chatId: 'chat_1',
      name: 'todo',
      argumentsJson: '{"op":"done","task":"Verify provider"}',
      status: ToolExecutionStatus.success,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      resultJson: '{"ok":true,"result":{"phases":[],"completed":2,"total":3}}',
    );

    await tester.pumpWidget(_wrap(ToolCallCard(execution: execution)));

    expect(find.text('Todo'), findsOneWidget);
    expect(find.text('done · Verify provider'), findsOneWidget);
    expect(find.text('2/3 done'), findsOneWidget);
  });

  testWidgets('ToolCallCard renders runtime job summaries with state colors', (
    tester,
  ) async {
    final execution = ToolExecution(
      id: 'tool_jobs',
      chatId: 'chat_1',
      name: 'jobs.list',
      argumentsJson: '{}',
      status: ToolExecutionStatus.success,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      resultJson: jsonEncode({
        'ok': true,
        'result': {
          'category': 'jobs_list',
          'success': true,
          'jobs': [
            {
              'jobId': 'job-running',
              'state': 'running',
              'command': 'npm run dev',
              'stdoutPreview': '\u001b[33mListening\u001b[0m on 3000',
            },
            {
              'jobId': 'job-completed',
              'state': 'completed',
              'command': 'npm test',
              'stdoutPreview': 'All tests passed',
            },
            {
              'jobId': 'job-failed',
              'state': 'failed',
              'command': 'npm run build',
              'stderrPreview': 'Build failed',
            },
          ],
        },
      }),
    );

    await tester.pumpWidget(
      _wrap(ToolCallCard(execution: execution, initiallyExpanded: true)),
    );

    expect(find.text('RUNNING'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.text('FAILED'), findsOneWidget);
    expect(find.text('job-running'), findsOneWidget);
    expect(find.text('job-completed'), findsOneWidget);
    expect(find.text('job-failed'), findsOneWidget);
    expect(find.text('\$ npm run dev'), findsOneWidget);
    expect(find.byType(AnsiText), findsOneWidget);
    expect(
      tester.widget<AnsiText>(find.byType(AnsiText)).text,
      contains('Listening'),
    );
    expect(find.text('All tests passed'), findsOneWidget);
    expect(find.text('Build failed'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('RUNNING')).style!.color,
      AppColors.warning,
    );
    expect(
      tester.widget<Text>(find.text('COMPLETED')).style!.color,
      AppColors.success,
    );
    expect(
      tester.widget<Text>(find.text('FAILED')).style!.color,
      AppColors.error,
    );
  });

  testWidgets('ComposerView renders input, attachments, and send button', (
    tester,
  ) async {
    String? sentText;

    final attachment = Attachment.create(
      messageId: 'pending',
      path: '/test/sample.txt',
      kind: AttachmentKind.text,
      name: 'sample.txt',
    );

    await tester.pumpWidget(
      _wrap(
        ComposerView(
          onSend: (text) => sentText = text,
          onStop: () {},
          onPickAttachment: () {},
          onSelectModel: () {},
          isRunning: false,
          selectedModelName: 'OpenRouter GPT-4o Mini',
          attachments: [attachment],
        ),
      ),
    );

    expect(find.text('sample.txt'), findsOneWidget);
    expect(find.text('OpenRouter GPT-4o Mini'), findsOneWidget);

    // Enter text and submit
    await tester.enterText(find.byType(TextField), 'Fix auth bug');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();

    expect(sentText, 'Fix auth bug');
  });
  testWidgets('ComposerView wraps advanced controls on narrow screens', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 320,
            child: ComposerView(
              onSend: (_) {},
              onStop: () {},
              onPickAttachment: () {},
              onSelectModel: () {},
              isRunning: false,
              selectedModelName: 'OpenRouter GPT-4o Mini',
            ),
          ),
        ),
      );
      await tester.pump();
    } finally {
      FlutterError.onError = previousErrorHandler;
    }

    expect(
      errors.where(
        (details) => details.exceptionAsString().contains('overflow'),
      ),
      isEmpty,
    );
  });

  testWidgets('ComposerView shows Stop button when agent is running', (
    tester,
  ) async {
    var stopped = false;

    await tester.pumpWidget(
      _wrap(
        ComposerView(
          onSend: (_) {},
          onStop: () => stopped = true,
          onPickAttachment: () {},
          onSelectModel: () {},
          isRunning: true,
          selectedModelName: 'OpenRouter GPT-4o Mini',
        ),
      ),
    );

    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(stopped, isTrue);
  });

  testWidgets('EmptyChatView renders suggestions and prompts', (tester) async {
    String? selectedPrompt;

    await tester.pumpWidget(
      _wrap(
        EmptyChatView(
          project: Project.create(name: 'MyApp', folderPath: '/projects/myapp'),
          onSuggestionTap: (prompt) => selectedPrompt = prompt,
        ),
      ),
    );

    expect(find.text('MyApp'), findsOneWidget);
    expect(find.text('What do you want to build?'), findsOneWidget);
    expect(find.text('Read project structure'), findsOneWidget);

    await tester.tap(find.text('Read project structure'));
    await tester.pump();

    expect(selectedPrompt, contains('Read the project structure'));
  });

  testWidgets('ModelSelectorSheet groups models and highlights active model', (
    tester,
  ) async {
    final provider = ProviderConfig.create(
      name: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
    );
    final model1 = ProviderModel.create(
      providerId: provider.id,
      model: 'openai/gpt-4o-mini',
    );
    final model2 = ProviderModel.create(
      providerId: provider.id,
      model: 'anthropic/claude-sonnet-4',
    );

    ProviderModel? selected;

    await tester.pumpWidget(
      _wrap(
        ModelSelectorSheet(
          providers: [provider],
          providerModels: {
            provider.id: [model1, model2],
          },
          selectedModelId: model1.id,
          onModelSelected: (m) => selected = m,
        ),
      ),
    );

    expect(find.text('OPENROUTER'), findsOneWidget);
    expect(find.text('openai/gpt-4o-mini'), findsOneWidget);
    expect(find.text('anthropic/claude-sonnet-4'), findsOneWidget);
    expect(find.byType(ModelSelectorSheet), findsOneWidget);

    await tester.tap(find.text('anthropic/claude-sonnet-4'));
    await tester.pump();

    expect(selected?.id, model2.id);
  });

  testWidgets('UpdateAvailableBanner renders version and action', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      _wrap(
        UpdateAvailableBanner(
          version: '0.1.2',
          channel: 'beta',
          mandatory: false,
          notes: 'Fixed chat recovery',
          onView: () => opened = true,
        ),
      ),
    );

    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('0.1.2'), findsOneWidget);
    expect(find.text('View Update'), findsOneWidget);

    await tester.tap(find.text('View Update'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('WelcomeStep renders dynamic branding from custom AppIdentity', (
    tester,
  ) async {
    const customIdentity = AppIdentity(
      appName: 'Nebula',
      appDisplayName: 'Nebula Code Studio',
      tagline: 'High performance AI assistant',
    );

    var continued = false;

    await tester.pumpWidget(
      _wrap(
        WelcomeStep(
          identity: customIdentity,
          onContinue: () => continued = true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Welcome to Nebula'), findsOneWidget);
    expect(find.text('High performance AI assistant'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.semanticLabel == 'Nebula logo',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Get Started'));
    await tester.pump();

    expect(continued, isTrue);
  });
  testWidgets('EmptyState renders with vector icons without emoji', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        EmptyState(
          icon: Icons.folder_open_rounded,
          title: 'No items',
          description: 'Create an item to get started',
          actionLabel: 'Add Item',
          onAction: () {},
        ),
      ),
    );

    expect(find.text('No items'), findsOneWidget);
    expect(find.text('Create an item to get started'), findsOneWidget);
    expect(find.text('Add Item'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);
  });

  test('OnboardingState model serializes and deserializes cleanly', () {
    const state = OnboardingState(completed: true, step: 4);
    final map = state.toMap();
    final restored = OnboardingState.fromMap(map);

    expect(restored.completed, isTrue);
    expect(restored.step, 4);
  });

  testWidgets('CentralNavigationOverlay renders navigation destinations', (
    tester,
  ) async {
    CentralNavDestination? selected;

    await tester.pumpWidget(
      _wrap(
        CentralNavigationOverlay(
          showNewChat: true,
          onSelect: (dest) => selected = dest,
        ),
      ),
    );

    expect(find.text('New Chat'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Providers'), findsOneWidget);
    expect(find.text('Runtime'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Projects'));
    await tester.pump();

    expect(selected, CentralNavDestination.projects);
  });

  testWidgets('AnimatedHamburger responds to taps', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      _wrap(
        Center(
          child: AnimatedHamburger(onTap: () => tapped = true, isCenter: true),
        ),
      ),
    );

    await tester.tap(find.byType(AnimatedHamburger), warnIfMissed: false);
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('WipeRevealText displays styled text', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const WipeRevealText(
          text: 'Autonomous Coding',
          style: TextStyle(fontSize: 20),
          delay: Duration.zero,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Autonomous Coding'), findsOneWidget);
  });
}
