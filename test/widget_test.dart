import 'package:syntac/src/agent/agent_loop.dart';
import 'package:syntac/src/models.dart';
import 'package:syntac/src/ui/chat/composer_view.dart';
import 'package:syntac/src/ui/chat/empty_chat_view.dart';
import 'package:syntac/src/ui/chat/markdown_content.dart';
import 'package:syntac/src/ui/chat/model_selector_sheet.dart';
import 'package:syntac/src/ui/chat/tool_call_card.dart';
import 'package:syntac/src/ui/screens/home_screen.dart';
import 'package:syntac/src/ui/theme/app_theme.dart';
import 'package:syntac/src/ui/widgets/badge_chip.dart';
import 'package:syntac/src/ui/widgets/status_indicator.dart';
import 'package:syntac/src/core/app_identity.dart';
import 'package:syntac/src/ui/onboarding/steps/welcome_step.dart';
import 'package:syntac/src/ui/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:syntac/src/ui/components/animated_hamburger.dart';
import 'package:syntac/src/ui/components/wipe_reveal_text.dart';
import 'package:syntac/src/ui/navigation/central_navigation_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('app identity exposes release metadata', () {
    const identity = AppIdentity();
    expect(identity.developerName, 'DraxonV1');
    expect(identity.repositoryUrl, 'https://github.com/DraxonV1/Syntac');
    expect(identity.version, '0.1.1-beta.2');
    expect(identity.versionCode, 12);
    expect(identity.updateChannel, 'beta');
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

    expect(find.text('COMMAND'), findsOneWidget);
    expect(find.text('STDOUT'), findsOneWidget);
    expect(find.text('All tests passed!'), findsOneWidget);
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

    expect(find.text('Exit 1'), findsOneWidget);
    expect(find.text('STDOUT'), findsOneWidget);
    expect(find.text('STDERR'), findsOneWidget);
    expect(find.text('(empty)'), findsWidgets);
    expect(find.text('Exit code: 1'), findsOneWidget);
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
    expect(find.textContaining('+first line'), findsOneWidget);
    expect(find.textContaining('+second line'), findsOneWidget);
  });

  testWidgets('ToolCallCard renders edit diff preview', (tester) async {
    final execution = ToolExecution(
      id: 'tool_edit',
      chatId: 'chat_1',
      name: 'edit',
      argumentsJson:
          '{"path": "lib/main.txt", "target": "old line", "replacement": "new line"}',
      status: ToolExecutionStatus.success,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      resultJson:
          '{"ok": true, "result": {"path": "lib/main.txt", "replacedBytes": 8, "newBytes": 8, "replacedLines": 1, "newLines": 1, "replacements": 1}}',
    );

    await tester.pumpWidget(
      _wrap(ToolCallCard(execution: execution, initiallyExpanded: true)),
    );

    expect(find.text('DIFF'), findsOneWidget);
    expect(find.textContaining('-old line'), findsOneWidget);
    expect(find.textContaining('+new line'), findsOneWidget);
  });

  testWidgets('ToolCallCard renders edit diff badge using lines', (
    tester,
  ) async {
    final execution = ToolExecution(
      id: 'tool_2',
      chatId: 'chat_1',
      name: 'edit',
      argumentsJson: '{"path": "lib/auth.dart"}',
      status: ToolExecutionStatus.success,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      resultJson:
          '{"path": "lib/auth.dart", "replacedBytes": 3, "newBytes": 14, "replacedLines": 3, "newLines": 1}',
    );

    await tester.pumpWidget(_wrap(ToolCallCard(execution: execution)));

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('lib/auth.dart'), findsOneWidget);
    expect(find.text('+1 -3'), findsOneWidget);
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

    expect(find.text('Navigation Hub'), findsOneWidget);
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
