import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:syntac/src/app.dart';
import 'package:syntac/src/agent/agent_loop.dart';
import 'package:syntac/src/agent/context_builder.dart';
import 'package:syntac/src/ai/ai_provider.dart';
import 'package:syntac/src/ai/ai_error_messages.dart';
import 'package:syntac/src/ai/google_cloud_code_assist_provider.dart';
import 'package:syntac/src/ai/oauth/google_antigravity_oauth.dart';
import 'package:syntac/src/ai/oauth/oauth_credential.dart';
import 'package:syntac/src/ai/oauth/openai_codex_oauth.dart';
import 'package:syntac/src/ai/oauth/xai_oauth.dart';
import 'package:syntac/src/ai/openai_codex_provider.dart';
import 'package:syntac/src/ai/openai_provider.dart';
import 'package:syntac/src/ai/models_dev_catalog.dart';
import 'package:syntac/src/ai/registry/provider_registry.dart';
import 'package:syntac/src/ai/provider_diagnostics.dart';
import 'package:syntac/src/core/cancellation.dart';
import 'package:syntac/src/core/update_service.dart';
import 'package:syntac/src/models.dart';
import 'package:syntac/src/runtime/shell_executor.dart';
import 'package:syntac/src/security/secret_store.dart';
import 'package:syntac/src/storage/app_repository.dart';
import 'package:syntac/src/storage/chat_jsonl_store.dart';
import 'package:syntac/src/storage/local_database.dart';
import 'package:syntac/src/tools/agent_tools.dart';
import 'package:syntac/src/ui/onboarding/onboarding_screen.dart';
import 'package:syntac/src/ui/screens/home_screen.dart';
import 'package:syntac/src/ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  Future<AppRepository> repository() async {
    final db = await LocalDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final chatDir = await Directory.systemTemp.createTemp('syntac_chats_test_');
    return AppRepository(
      localDatabase: db,
      secretStore: MemorySecretStore(),
      chatStorageDirectory: chatDir,
    );
  }

  Widget wrapHome(AppController controller) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: HomeScreen(controller: controller),
    );
  }

  testWidgets('home waits for controller initialization before onboarding', (
    tester,
  ) async {
    final blockedInit = Completer<LocalDatabase>();
    final controller = AppController(
      openDatabase: () => blockedInit.future,
      secretStore: MemorySecretStore(),
    );
    unawaited(controller.initialize());

    await tester.pumpWidget(wrapHome(controller));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    blockedInit.completeError(StateError('stopped'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('startup initialization failure shows retry action', (
    tester,
  ) async {
    var attempts = 0;
    final retryInit = Completer<LocalDatabase>();
    final controller = AppController(
      openDatabase: () async {
        attempts += 1;
        if (attempts == 1) throw StateError('open failed');
        return retryInit.future;
      },
      secretStore: MemorySecretStore(),
    );
    await controller.initialize();

    await tester.pumpWidget(wrapHome(controller));
    await tester.pump();

    expect(find.text('Startup failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    retryInit.completeError(StateError('stopped'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('persistence', () {
    test(
      'creates projects chats messages providers and keeps secrets out of SQLite',
      () async {
        final repo = await repository();
        final dir = await Directory.systemTemp.createTemp('syntac_repo_test_');
        final project = await repo.createProject(
          name: 'Website',
          folderPath: dir.path,
        );
        expect(project.mountName, 'website');
        final chat = await repo.createChat(
          projectId: project.id,
          title: 'Build auth',
        );
        await repo.addMessage(
          ChatMessage.create(
            chatId: chat.id,
            role: MessageRole.user,
            content: 'hello',
          ),
        );
        final provider = await repo.saveProvider(
          name: 'OpenRouter',
          baseUrl: 'https://openrouter.ai/api/v1',
          apiKey: 'secret-key',
          models: ['openai/gpt-4o-mini'],
        );

        expect((await repo.listProjectSummaries()).single.chatCount, 1);
        expect((await repo.listMessages(chat.id)).single.content, 'hello');
        expect(
          (await repo.listProviderModels(provider.id)).single.model,
          'openai/gpt-4o-mini',
        );
        expect(await repo.readProviderApiKey(provider.id), 'secret-key');
        final oauthProvider = await repo.saveProvider(
          name: 'Google Antigravity',
          baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
          providerKey: 'google-antigravity',
          authType: 'googleAntigravityOAuth',
          apiKey: '',
          models: ['gemini-3.1-pro'],
        );
        await repo.saveOAuthCredential(
          oauthProvider.id,
          OAuthCredential(
            provider: OAuthProviderId.googleAntigravity,
            accessToken: 'access-token',
            refreshToken: 'refresh-token',
            expiresAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
            projectId: 'project-123',
            email: 'user@example.com',
          ),
        );
        expect(
          (await repo.readOAuthCredential(oauthProvider.id))!.projectId,
          'project-123',
        );

        expect(provider.toMap().values, isNot(contains('secret-key')));

        final firstDuplicate = await repo.createProject(
          name: 'Website',
          folderPath: '${dir.path}_one',
        );
        final secondDuplicate = await repo.createProject(
          name: 'Website',
          folderPath: '${dir.path}_two',
        );
        expect(firstDuplicate.mountName, 'website-2');
        expect(secondDuplicate.mountName, 'website-3');
        expect(
          (await repo.listProjects()).map((item) => item.mountName),
          containsAll(['website-2', 'website-3']),
        );

        await repo.removeProjectFromApp(project.id);
        expect(await dir.exists(), isTrue);
        await dir.delete(recursive: true);
      },
    );
    test('persists selected default provider model', () async {
      final repo = await repository();
      await repo.saveDefaultModelSelection(
        providerId: 'provider-1',
        model: 'gemini-3.1-pro',
      );

      expect(await repo.readDefaultModelSelection(), {
        'providerId': 'provider-1',
        'model': 'gemini-3.1-pro',
      });
    });

    test('reconciles stale running jobs into interrupted state', () async {
      final repo = await repository();
      final dir = await Directory.systemTemp.createTemp('syntac_repo_test_');
      final project = await repo.createProject(
        name: 'API',
        folderPath: dir.path,
      );
      final chat = await repo.createChat(
        projectId: project.id,
        title: 'Run task',
      );
      await repo.addAgentJob(
        AgentJob.start(projectId: project.id, chatId: chat.id),
      );
      await repo.setChatStatus(chat.id, ChatStatus.running);

      await repo.reconcileStaleRunningJobs();

      expect((await repo.getChat(chat.id))!.status, ChatStatus.interrupted);
      await dir.delete(recursive: true);
    });
    test('migrates legacy SQLite chats into bounded JSONL files', () async {
      final db = await LocalDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      final chatDir = await Directory.systemTemp.createTemp(
        'syntac_chats_test_',
      );
      final repo = AppRepository(
        localDatabase: db,
        secretStore: MemorySecretStore(),
        chatStorageDirectory: chatDir,
      );
      final dir = await Directory.systemTemp.createTemp('syntac_repo_test_');
      final project = await repo.createProject(
        name: 'Crashy',
        folderPath: dir.path,
      );
      final chat = Chat.create(projectId: project.id, title: 'Big');
      final largeText = 'x' * (maxPersistedTextCharacters + 1000);
      await db.database.insert('chats', chat.toMap());
      await db.database.insert('messages', {
        'id': 'msg_big',
        'chat_id': chat.id,
        'role': 'assistant',
        'content': largeText,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await db.database.insert('tool_executions', {
        'id': 'tool_big',
        'chat_id': chat.id,
        'name': 'bash',
        'arguments_json': '{"command":"pacman -Sy --noconfirm python"}',
        'status': 'success',
        'started_at': DateTime.now().millisecondsSinceEpoch,
        'finished_at': DateTime.now().millisecondsSinceEpoch,
        'result_json': jsonEncode({
          'result': {'stdout': largeText, 'stderr': '', 'exitCode': 0},
        }),
      });

      final messages = await repo.listMessages(chat.id);
      expect(messages.single.content, contains(persistenceTruncationNotice));
      expect(messages.single.content, contains('database-projected'));
      expect(
        messages.single.content.length,
        lessThanOrEqualTo(maxPersistedTextCharacters),
      );

      final execution = (await repo.listToolExecutions(chat.id)).single;
      final decoded = jsonDecode(execution.resultJson!) as Map<String, Object?>;
      expect(decoded['recovered'], isTrue);
      expect(decoded['result'].toString(), contains('database-projected'));
      expect(
        decoded['result'].toString().length,
        lessThan(maxPersistedTextCharacters + 1000),
      );

      final chatIndex = File(
        '${chatDir.path}${Platform.pathSeparator}chats.jsonl',
      );
      expect(await chatIndex.exists(), isTrue);
      expect(await chatIndex.readAsString(), contains(chat.id));
      await dir.delete(recursive: true);
      await chatDir.delete(recursive: true);
    });

    test(
      'quarantines malformed JSONL rows without dropping valid rows',
      () async {
        final chatDir = await Directory.systemTemp.createTemp(
          'syntac_jsonl_bad_',
        );
        final store = ChatJsonlStore(chatDir);
        final chat = Chat.create(projectId: 'project', title: 'Bad row');
        await store.addChat(chat);
        final message = ChatMessage.create(
          chatId: chat.id,
          role: MessageRole.assistant,
          content: 'survives',
        );
        final file = File(
          '${chatDir.path}${Platform.pathSeparator}chats${Platform.pathSeparator}${chat.id}${Platform.pathSeparator}messages.jsonl',
        );
        await file.parent.create(recursive: true);
        await file.writeAsString('not-json\n${jsonEncode(message.toMap())}\n');

        final messages = await store.listMessages(chat.id);

        expect(messages.single.content, 'survives');
        final bad = File('${file.path}.bad');
        expect(await bad.exists(), isTrue);
        final badJson = jsonDecode((await bad.readAsLines()).single) as Map;
        expect(badJson['lineNumber'], 1);
        expect(badJson['raw'], 'not-json');
        await chatDir.delete(recursive: true);
      },
    );

    test('recovers orphaned JSONL temp files on startup', () async {
      final chatDir = await Directory.systemTemp.createTemp(
        'syntac_jsonl_tmp_',
      );
      final chat = Chat.create(projectId: 'project', title: 'Recovered');
      final message = ChatMessage.create(
        chatId: chat.id,
        role: MessageRole.assistant,
        content: 'recovered',
      );
      final chatFile = File(
        '${chatDir.path}${Platform.pathSeparator}chats.jsonl',
      );
      final messageFile = File(
        '${chatDir.path}${Platform.pathSeparator}chats${Platform.pathSeparator}${chat.id}${Platform.pathSeparator}messages.jsonl',
      );
      await messageFile.parent.create(recursive: true);
      await chatFile.parent.create(recursive: true);
      await chatFile.writeAsString('${jsonEncode(chat.toMap())}\n');
      await File(
        '${messageFile.path}.123.tmp',
      ).writeAsString('${jsonEncode(message.toMap())}\n');

      final store = ChatJsonlStore(chatDir);
      final messages = await store.listMessages(chat.id);

      expect(messages.single.content, 'recovered');
      expect(await File('${messageFile.path}.123.tmp').exists(), isFalse);
      await chatDir.delete(recursive: true);
    });

    test(
      'serializes concurrent JSONL writes without resurrecting deleted chats',
      () async {
        final chatDir = await Directory.systemTemp.createTemp(
          'syntac_jsonl_race_',
        );
        final store = ChatJsonlStore(chatDir);
        final chat = Chat.create(projectId: 'project', title: 'Race');
        await store.addChat(chat);
        final tool = await store.addToolExecution(
          ToolExecution.start(
            chatId: chat.id,
            name: 'bash',
            arguments: {'command': 'echo'},
          ),
        );

        await Future.wait([
          for (var i = 0; i < 30; i++)
            store.addMessage(
              ChatMessage.create(
                chatId: chat.id,
                role: MessageRole.assistant,
                content: 'message-$i',
              ),
            ),
          for (var i = 0; i < 30; i++)
            store.updateToolExecution(
              tool.runningResult({'stdout': 'chunk-$i'}),
            ),
        ]);

        expect(await store.listMessages(chat.id), hasLength(30));
        expect(
          (await store.listToolExecutions(chat.id)).single.resultJson,
          isNotNull,
        );
        await store.deleteChat(chat.id);
        await expectLater(
          store.addMessage(
            ChatMessage.create(
              chatId: chat.id,
              role: MessageRole.assistant,
              content: 'late',
            ),
          ),
          throwsStateError,
        );
        expect(await store.getChat(chat.id), isNull);
        expect(await store.listMessages(chat.id), isEmpty);
        await chatDir.delete(recursive: true);
      },
    );
  });

  group('tools', () {
    test('rejects symlink paths escaping the project root', () async {
      final dir = await Directory.systemTemp.createTemp('syntac_tools_test_');
      final outside = await Directory.systemTemp.createTemp(
        'syntac_tools_outside_',
      );
      final outsideFile = File(
        '${outside.path}${Platform.pathSeparator}secret.txt',
      );
      await outsideFile.writeAsString('secret');
      final tools = ProjectTools(
        projectRoot: dir.path,
        shellExecutor: CapturingShellExecutor(
          const CommandResult(
            stdout: '',
            stderr: '',
            exitCode: 0,
            duration: Duration.zero,
            timedOut: false,
            cancelled: false,
          ),
        ),
      );

      try {
        await Link(
          '${dir.path}${Platform.pathSeparator}outside_link',
        ).create(outsideFile.path);
        await Link(
          '${dir.path}${Platform.pathSeparator}dangling_link',
        ).create('${outside.path}${Platform.pathSeparator}missing.txt');
      } on FileSystemException {
        await dir.delete(recursive: true);
        await outside.delete(recursive: true);
        return;
      }

      final linked = await tools.execute('read', {'path': 'outside_link'});
      final dangling = await tools.execute('write', {
        'path': 'dangling_link',
        'content': 'x',
      });

      expect(linked['ok'], isFalse);
      expect(dangling['ok'], isFalse);
      await dir.delete(recursive: true);
      await outside.delete(recursive: true);
    });

    test(
      'validates paths and supports read write edit delete list search bash',
      () async {
        final dir = await Directory.systemTemp.createTemp('syntac_tools_test_');
        final tools = ProjectTools(
          projectRoot: dir.path,
          shellExecutor: LocalProcessShellExecutor(),
        );

        final writeResult = await tools.writeFile(
          'lib/main.txt',
          'hello world\nsecond line',
        );
        expect(writeResult['bytes'], greaterThan(0));
        expect(
          (await tools.readFile(
            'lib/main.txt',
            offset: 2,
            limit: 1,
          ))['content'],
          'second line',
        );

        final rangedRead = await tools.readFile(
          'lib/main.txt',
          startLine: 1,
          endLine: 1,
        );
        expect(rangedRead['content'], 'hello world');
        expect(rangedRead['totalLines'], 2);
        expect(rangedRead['hasMore'], isTrue);

        final byteRange = await tools.readFile(
          'lib/main.txt',
          unit: 'byte',
          offset: 6,
          limit: 5,
        );
        expect(byteRange['content'], 'world');
        expect(byteRange['startByte'], 6);

        final firstEdit = await tools.editFile('lib/main.txt', 'hello', 'hi');
        expect(
          (await File(
            '${dir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}main.txt',
          ).readAsString()).startsWith('hi'),
          isTrue,
        );
        expect(firstEdit['replacedLines'], 1);
        expect(firstEdit['newLines'], 1);

        await tools.editFile(
          'lib/main.txt',
          'i',
          'I',
          replaceAll: true,
          requireUnique: false,
          expectedReplacements: 2,
        );
        expect(
          await File(
            '${dir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}main.txt',
          ).readAsString(),
          'hI world\nsecond lIne',
        );

        final listResult = await tools.listDirectory('.', depth: 2);
        expect(
          (listResult['entries'] as List).any(
            (entry) => (entry as Map)['path'].toString().contains('main.txt'),
          ),
          isTrue,
        );

        final searchResult = await tools.search(
          r'second\s+line',
          regex: true,
          caseSensitive: false,
          contextLines: 1,
          include: ['lib/*.txt'],
        );
        final searchMatches = searchResult['results'] as List;
        expect(searchMatches, isNotEmpty);
        expect((searchMatches.first as Map)['line'], 2);
        expect((searchMatches.first as Map)['before'], contains('hI world'));
        final pagedSearch = await tools.search(
          'i',
          caseSensitive: false,
          maxResults: 1,
          offset: 1,
        );
        expect(pagedSearch['offset'], 1);
        expect((pagedSearch['results'] as List), hasLength(1));

        final bashResult = await tools.runBash(
          'echo tool-ok',
          timeout: const Duration(seconds: 10),
        );
        expect(bashResult['exitCode'], 0);
        expect(bashResult['stdout'].toString(), contains('tool-ok'));

        final liveUpdates = <Map<String, Object?>>[];
        final liveResult = await tools.runBash(
          'echo live-stream',
          timeout: const Duration(seconds: 10),
          onUpdate: liveUpdates.add,
        );
        expect(liveResult['exitCode'], 0);
        expect(liveUpdates, isNotEmpty);
        expect(
          liveUpdates.any(
            (update) => update['stdout'].toString().contains('live-stream'),
          ),
          isTrue,
        );

        expect(
          () => tools.readFile('../escape.txt'),
          throwsA(isA<ToolFailure>()),
        );
        await tools.deletePath('lib/main.txt');
        expect(
          await File(
            '${dir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}main.txt',
          ).exists(),
          isFalse,
        );
        await dir.delete(recursive: true);
      },
    );
  });

  group('provider', () {
    test('maps OpenAI-compatible HTTP errors', () async {
      final provider = OpenAICompatibleProvider(
        baseUrl: 'https://example.test',
        client: MockClient(
          (request) async =>
              http.Response('{"error":{"message":"slow down"}}', 429),
        ),
      );
      expect(
        provider.testConnection(apiKey: 'k'),
        throwsA(
          isA<AIProviderException>().having(
            (error) => error.kind,
            'kind',
            'rate_limited',
          ),
        ),
      );
    });

    test(
      'normalizes OpenAI-compatible base paths without duplicating v1',
      () async {
        final seen = <Uri>[];
        final provider = OpenAICompatibleProvider(
          baseUrl: 'https://openrouter.ai/api/v1/',
          client: MockClient((request) async {
            seen.add(request.url);
            return http.Response('{}', 200);
          }),
        );

        await provider.testConnection(apiKey: 'k');

        expect(seen.single.toString(), 'https://openrouter.ai/api/v1/models');
      },
    );

    test('parses streamed text and tool calls', () async {
      final provider = OpenAICompatibleProvider(
        baseUrl: 'https://example.test',
        client: StreamingClient([
          'data: {"choices":[{"delta":{"content":"hi"}}]}\n\n',
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"read","arguments":"{\\"path\\":"}}]}}]}\n\n',
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"pubspec.yaml\\"}"}}]},"finish_reason":"tool_calls"}]}\n\n',
          'data: [DONE]\n\n',
        ]),
      );
      final response = await provider.completeChat(
        const AIChatRequest(model: 'model', messages: [], tools: []),
        apiKey: 'k',
      );
      expect(response.text, 'hi');
      expect(response.toolCalls.single.name, 'read');
      expect(
        response.toolCalls.single.argumentsJson,
        '{"path":"pubspec.yaml"}',
      );
    });

    test('maps transport diagnostics without exposing raw exceptions', () async {
      final provider = OpenAICompatibleProvider(
        baseUrl: 'https://openrouter.ai',
        client: MockClient((request) async {
          throw http.ClientException(
            "ClientException with SocketException: Failed host lookup: 'openrouter.ai' (OS Error: No address associated with hostname, errno = 7)",
            request.url,
          );
        }),
      );

      await expectLater(
        provider.testConnection(apiKey: 'k'),
        throwsA(
          isA<AIProviderException>()
              .having((error) => error.kind, 'kind', 'dns_failure')
              .having(
                (error) => error.message,
                'message',
                'DNS lookup failed for openrouter.ai',
              ),
        ),
      );

      final userMessage = describeAIErrorForUser(
        const AIProviderException('raw network details', kind: 'dns_failure'),
        providerName: 'OpenRouter',
      );
      expect(
        userMessage,
        "Couldn't find OpenRouter. Check your internet connection and provider URL.",
      );
      expect(userMessage, isNot(contains('ClientException')));
      expect(userMessage, isNot(contains('SocketException')));
    });

    test('rejects malformed provider endpoints before HTTP', () {
      expect(
        () => OpenAICompatibleProvider(baseUrl: 'openrouter.ai'),
        throwsA(
          isA<AIProviderException>().having(
            (error) => error.kind,
            'kind',
            'malformed_endpoint',
          ),
        ),
      );
    });

    test(
      'ports Google Antigravity OAuth exchange discovery and refresh',
      () async {
        final calls = <String>[];
        final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
        final flow = GoogleAntigravityOAuthFlow(
          now: () => now,
          clientId: 'test-client-id',
          clientSecret: 'test-client-secret',
          client: MockClient((request) async {
            calls.add('${request.method} ${request.url}');
            if (request.url.toString() == GoogleAntigravityOAuthFlow.tokenUrl &&
                request.method == 'POST') {
              final body = request.bodyFields;
              if (body['grant_type'] == 'authorization_code') {
                expect(body['client_id'], isNotEmpty);
                expect(body['client_secret'], isNotEmpty);
                expect(
                  body['redirect_uri'],
                  'http://127.0.0.1:51121/oauth-callback',
                );
                return http.Response(
                  jsonEncode({
                    'access_token': 'access-1',
                    'refresh_token': 'refresh-1',
                    'expires_in': 3600,
                  }),
                  200,
                );
              }
              if (body['grant_type'] == 'refresh_token') {
                expect(body['refresh_token'], 'refresh-1');
                return http.Response(
                  jsonEncode({'access_token': 'access-2', 'expires_in': 7200}),
                  200,
                );
              }
            }
            if (request.url.host == 'www.googleapis.com') {
              expect(request.headers['Authorization'], 'Bearer access-1');
              return http.Response(
                jsonEncode({'email': 'user@example.com'}),
                200,
              );
            }
            if (request.url.toString() ==
                '${GoogleAntigravityOAuthFlow.dailyCloudCodeEndpoint}/v1internal:loadCodeAssist') {
              expect(request.headers['Authorization'], 'Bearer access-1');
              expect(
                request.headers['User-Agent'],
                contains('antigravity/hub/2.8.0'),
              );
              expect(
                jsonDecode(request.body)['metadata']['ideType'],
                'ANTIGRAVITY',
              );
              return http.Response(
                jsonEncode({
                  'cloudaicompanionProject': {'id': 'project-123'},
                  'supportedModels': [
                    {'model': 'gemini-3.5-flash'},
                    {'id': 'models/gemini-3.1-pro'},
                    {'name': 'not-a-gemini-model'},
                    {'modelId': 'MODEL_PLACEHOLDER'},
                  ],
                }),
                200,
              );
            }
            fail('Unexpected request: ${request.method} ${request.url}');
          }),
        );

        final authUrl = Uri.parse(
          flow.buildAuthorizationUrl(
            state: 'state-1',
            redirectUri: 'http://127.0.0.1:51121/oauth-callback',
          ),
        );
        expect(authUrl.queryParameters['access_type'], 'offline');
        expect(authUrl.queryParameters['prompt'], 'consent');
        expect(
          authUrl.queryParameters['scope'],
          contains('experimentsandconfigs'),
        );

        final credential = await flow.exchangeAuthorizationCode(
          code: 'code-1',
          redirectUri: 'http://127.0.0.1:51121/oauth-callback',
        );
        final email = await flow.fetchUserEmail(credential.accessToken);
        final projectId = await flow.discoverProject(credential.accessToken);
        final models = await flow.discoverModels(credential.accessToken);
        final refreshed = await flow.refreshToken(
          credential.copyWith(projectId: projectId, email: email),
        );

        expect(projectId, 'project-123');
        expect(models, containsAll(['gemini-3.5-flash', 'gemini-3.1-pro']));
        expect(models, isNot(contains('not-a-gemini-model')));
        expect(models, isNot(contains('MODEL_PLACEHOLDER')));
        expect(email, 'user@example.com');
        expect(refreshed.accessToken, 'access-2');
        expect(refreshed.refreshToken, 'refresh-1');
        expect(calls, contains('POST https://oauth2.googleapis.com/token'));
      },
    );

    test('rejects Google OAuth redirect URI on unexpected port', () {
      final flow = GoogleAntigravityOAuthFlow(
        client: MockClient((_) async {
          fail('Invalid redirect URI should not send HTTP');
        }),
        clientId: 'test-client-id',
        clientSecret: 'test-client-secret',
      );

      expect(
        () => flow.buildAuthorizationUrl(
          state: 'state',
          redirectUri: 'http://127.0.0.1:1455/oauth-callback',
        ),
        throwsA(
          isA<AIProviderException>().having(
            (error) => error.kind,
            'kind',
            'oauth_error',
          ),
        ),
      );
    });
    test(
      'Google Antigravity polls onboarding operation with current payload',
      () async {
        var loadCalls = 0;
        var onboardCalls = 0;
        final flow = GoogleAntigravityOAuthFlow(
          client: MockClient((request) async {
            if (request.url.toString().endsWith('v1internal:loadCodeAssist')) {
              loadCalls++;
              final body = jsonDecode(request.body) as Map<String, Object?>;
              expect(body['metadata'], {'ideType': 'ANTIGRAVITY'});
              if (loadCalls == 1) {
                return http.Response(
                  jsonEncode({
                    'allowedTiers': [
                      {'id': 'free-tier'},
                    ],
                  }),
                  200,
                );
              }
              return http.Response(
                jsonEncode({'cloudaicompanionProject': 'project-123'}),
                200,
              );
            }
            if (request.url.toString().endsWith('v1internal:onboardUser')) {
              onboardCalls++;
              expect(jsonDecode(request.body), {
                'tierId': 'free-tier',
                'metadata': {'ideType': 'ANTIGRAVITY'},
              });
              return http.Response(
                jsonEncode({'name': 'operations/onboard-123'}),
                200,
              );
            }
            if (request.method == 'GET' &&
                request.url.toString().endsWith(
                  'v1internal/operations/onboard-123',
                )) {
              return http.Response(
                jsonEncode({
                  'done': true,
                  'response': {'cloudaicompanionProject': 'project-123'},
                }),
                200,
              );
            }
            fail('Unexpected request: ${request.method} ${request.url}');
          }),
        );

        expect(await flow.discoverProject('access-token'), 'project-123');
        expect(loadCalls, 3);
        expect(onboardCalls, 1);
      },
    );

    test('Google OAuth rejects explicitly missing client credentials', () {
      final flow = GoogleAntigravityOAuthFlow(
        client: MockClient((_) async {
          fail('Missing OAuth credentials should not send HTTP');
        }),
        clientId: '',
        clientSecret: '',
      );

      expect(
        () => flow.buildAuthorizationUrl(
          state: 'state',
          redirectUri: 'http://127.0.0.1:51121/oauth-callback',
        ),
        throwsA(
          isA<AIProviderException>().having(
            (error) => error.kind,
            'kind',
            'oauth_error',
          ),
        ),
      );
    });
    test('beta registry uses live discovery without model hardcodes', () {
      final ids = ProviderRegistry.builtIns.map((provider) => provider.id);

      expect(ids, contains('openai-codex'));
      expect(ids, contains('xai'));
      expect(ids, contains('xai-oauth'));
      expect(ids, isNot(contains('grok')));
      for (final provider in ProviderRegistry.builtIns) {
        expect(provider.defaultModels, isEmpty);
      }
    });
    test('Models.dev bundle supplies model limits and capabilities', () async {
      final catalog = await ModelsDevCatalog.load();
      final model = catalog.lookup(providerKey: 'xai', modelId: 'grok-4.3');

      expect(model, isNotNull);
      expect(model!.contextWindow, greaterThan(0));
      expect(model.outputLimit, greaterThan(0));
      expect(model.toolCall, isTrue);
    });
    test('builds ChatGPT Codex PKCE authorization URL', () {
      final flow = OpenAICodexOAuthFlow();
      final url = Uri.parse(
        flow.buildAuthorizationUrl(
          state: 'state',
          redirectUri: 'http://localhost:1455/auth/callback',
          codeChallenge: 'challenge',
        ),
      );

      expect(url.host, 'auth.openai.com');
      expect(url.queryParameters['client_id'], OpenAICodexOAuthFlow.clientId);
      expect(url.queryParameters['code_challenge_method'], 'S256');
      expect(url.queryParameters['state'], 'state');
      expect(url.queryParameters['originator'], 'pi');
    });
    test('exchanges ChatGPT Codex token and extracts account id', () async {
      final payload = base64UrlEncode(
        utf8.encode(
          jsonEncode({
            'https://api.openai.com/auth': {
              'chatgpt_account_id': 'account-123',
            },
            'https://api.openai.com/profile': {'email': 'user@example.com'},
          }),
        ),
      ).replaceAll('=', '');
      final flow = OpenAICodexOAuthFlow(
        client: MockClient((request) async {
          expect(request.url.toString(), OpenAICodexOAuthFlow.tokenUrl);
          expect(request.bodyFields['code_verifier'], 'verifier');
          return http.Response(
            jsonEncode({
              'access_token': 'header.$payload.signature',
              'refresh_token': 'refresh-token',
              'expires_in': 3600,
            }),
            200,
          );
        }),
      );

      final credential = await flow.exchangeAuthorizationCode(
        code: 'code',
        verifier: 'verifier',
        redirectUri: 'http://localhost:1455/auth/callback',
      );

      expect(credential.provider, OAuthProviderId.openAICodex);
      expect(credential.accountId, 'account-123');
      expect(credential.email, 'user@example.com');
    });

    test('parses ChatGPT Codex Responses stream', () async {
      final provider = OpenAICodexProvider(
        baseUrl: OpenAICodexOAuthFlow.defaultBaseUrl,
        client: StreamingClient([
          'event: response.output_text.delta\n'
              'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': 'hi'})}\n\n',
          'data: ${jsonEncode({
            'type': 'response.completed',
            'response': {'status': 'completed'},
          })}\n\n',
        ]),
      );

      final response = await provider.completeChat(
        const AIChatRequest(model: 'gpt-5.3-codex', messages: [], tools: []),
        apiKey: 'codex-token',
      );

      expect(response.text, 'hi');
      expect(response.finishReason, 'completed');
    });
    test('Codex Responses disables server-side response storage', () async {
      http.Request? captured;
      final provider = OpenAICodexProvider(
        baseUrl: OpenAICodexOAuthFlow.defaultBaseUrl,
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            'data: ${jsonEncode({
              'type': 'response.completed',
              'response': {'status': 'completed'},
            })}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );

      await provider.completeChat(
        const AIChatRequest(model: 'gpt-5.3-codex', messages: [], tools: []),
        apiKey: 'codex-token',
      );

      expect(jsonDecode(captured!.body)['store'], false);
    });

    test('Codex chat omits unsupported output token cap', () async {
      http.Request? captured;
      final provider = OpenAICodexProvider(
        baseUrl: OpenAICodexOAuthFlow.defaultBaseUrl,
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            'data: ${jsonEncode({
              'type': 'response.completed',
              'response': {'status': 'completed'},
            })}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );

      await provider.completeChat(
        const AIChatRequest(
          model: 'gpt-5.3-codex',
          messages: [AIChatMessage(role: 'user', content: 'hello')],
          tools: [],
          maxOutputTokens: 4096,
        ),
        apiKey: 'codex-token',
      );

      expect(
        (jsonDecode(captured!.body) as Map).containsKey('max_output_tokens'),
        isFalse,
      );
    });
  });

  test('discovers Codex models from OMP model endpoint', () async {
    http.Request? captured;
    final provider = OpenAICodexProvider(
      baseUrl: 'https://chatgpt.com/backend-api',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'models': [
              {'slug': 'gpt-5.2', 'display_name': 'GPT-5.2'},
              {'id': 'hidden-model', 'visibility': 'hidden'},
            ],
          }),
          200,
        );
      }),
    );

    final models = await provider.discoverCodexModels(
      credential: OAuthCredential(
        provider: OAuthProviderId.openAICodex,
        accessToken: 'codex-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        accountId: 'account-id',
      ),
    );

    expect(models, ['gpt-5.2']);
    expect(
      captured?.url.toString(),
      'https://chatgpt.com/backend-api/codex/models?client_version=0.144.1',
    );
    expect(captured?.headers['chatgpt-account-id'], 'account-id');
    expect(captured?.headers['originator'], 'pi');
    expect(captured?.headers['version'], '0.144.1');
    expect(captured?.headers['User-Agent'], 'Syntac');
  });

  test('routes xAI through Responses API and discovers models', () async {
    http.Request? captured;
    final provider = OpenAIResponsesProvider(
      baseUrl: 'https://api.x.ai/v1',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'grok-4.6'},
            ],
          }),
          200,
        );
      }),
    );

    final models = await provider.discoverModels(apiKey: 'xai-key');

    expect(models, ['grok-4.6']);
    expect(captured?.url.toString(), 'https://api.x.ai/v1/models');
    expect(captured?.headers['authorization'], 'Bearer xai-key');
    expect(
      provider.resolvedResponsesUri.toString(),
      'https://api.x.ai/v1/responses',
    );
  });

  test('converts chat tool specs to Responses tools for Grok', () async {
    http.Request? captured;
    final provider = OpenAIResponsesProvider(
      baseUrl: 'https://api.x.ai/v1',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          'data: ${jsonEncode({
            'type': 'response.completed',
            'response': {'status': 'completed'},
          })}\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );

    await provider.completeChat(
      AIChatRequest(
        model: 'grok-4.6',
        messages: const [AIChatMessage(role: 'user', content: 'read file')],
        tools: [
          {
            'type': 'function',
            'function': {
              'name': 'read',
              'description': 'Read file',
              'parameters': {
                'type': 'object',
                'properties': {
                  'path': {'type': 'string'},
                },
                'required': ['path'],
                'anyOf': [
                  {
                    'required': ['path'],
                  },
                  {
                    'required': ['path'],
                    'title': 'duplicate',
                  },
                ],
              },
            },
          },
        ],
      ),
      apiKey: 'xai-key',
    );

    final body = jsonDecode(captured!.body) as Map<String, Object?>;
    final tool = (body['tools'] as List).single as Map;
    expect(tool['type'], 'function');
    expect(tool['name'], 'read');
    expect(tool['description'], 'Read file');
    final parameters = tool['parameters'] as Map;
    expect(parameters['type'], 'object');
    expect(parameters['anyOf'], isNull);
  });

  test(
    'does not replay empty assistant message beside Grok tool call',
    () async {
      http.Request? captured;
      final provider = OpenAIResponsesProvider(
        baseUrl: 'https://api.x.ai/v1',
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            'data: ${jsonEncode({
              'type': 'response.completed',
              'response': {'status': 'completed'},
            })}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );

      await provider.completeChat(
        AIChatRequest(
          model: 'grok-4.6',
          messages: [
            const AIChatMessage(role: 'user', content: 'read file'),
            AIChatMessage(
              role: 'assistant',
              content: '',
              toolCalls: const [
                AIToolCall(
                  id: 'call_1',
                  name: 'read',
                  argumentsJson: '{"path":"README.md"}',
                ),
              ],
            ),
            const AIChatMessage(
              role: 'tool',
              content: 'file contents',
              toolCallId: 'call_1',
            ),
            const AIChatMessage(role: 'user', content: 'continue'),
          ],
          tools: const [],
        ),
        apiKey: 'xai-key',
      );

      final body = jsonDecode(captured!.body) as Map<String, Object?>;
      final input = body['input'] as List;
      expect(
        input.whereType<Map>().where((item) => item['type'] == 'function_call'),
        hasLength(1),
      );
      expect(
        input.whereType<Map>().where(
          (item) => item['type'] == 'message' && item['role'] == 'assistant',
        ),
        isEmpty,
      );
    },
  );

  test('runs xAI device OAuth with OMP client and scope', () async {
    final requests = <http.Request>[];
    final flow = XAIOAuthFlow(
      client: MockClient((request) async {
        requests.add(request);
        switch (request.url.toString()) {
          case XAIOAuthFlow.deviceCodeUrl:
            return http.Response(
              jsonEncode({
                'device_code': 'device',
                'user_code': 'ABCD',
                'verification_uri': 'https://auth.x.ai/activate',
                'verification_uri_complete':
                    'https://auth.x.ai/activate?user_code=ABCD',
                'expires_in': 600,
                'interval': 1,
              }),
              200,
            );
          case XAIOAuthFlow.discoveryUrl:
            return http.Response(
              jsonEncode({'token_endpoint': 'https://auth.x.ai/oauth2/token'}),
              200,
            );
          case 'https://auth.x.ai/oauth2/token':
            return http.Response(
              jsonEncode({
                'access_token': 'header.eyJzdWIiOiJzdWJqZWN0In0.sig',
                'refresh_token': 'refresh',
                'expires_in': 3600,
              }),
              200,
            );
          case XAIOAuthFlow.userInfoUrl:
            return http.Response(
              jsonEncode({'sub': 'subject', 'email': 'USER@example.com'}),
              200,
            );
        }
        return http.Response('{}', 404);
      }),
      sleep: (_) async {},
    );
    OAuthAuthRequest? authRequest;

    final credential = await flow.login(
      onAuthRequest: (request) => authRequest = request,
    );

    expect(credential.provider, OAuthProviderId.xaiOAuth);
    expect(credential.accountId, 'subject');
    expect(authRequest?.launchUrl, contains('user_code=ABCD'));
    expect(requests.first.body, contains('client_id=${XAIOAuthFlow.clientId}'));
    expect(requests.first.body, contains('scope=openid'));
    expect(requests[2].body, contains('grant_type=urn%3Aietf%3Aparams'));
  });
  group('agent loop', () {
    test(
      'executes tool calls, persists structured tool history, and completes',
      () async {
        final repo = await repository();
        final dir = await Directory.systemTemp.createTemp('syntac_agent_test_');
        final project = await repo.createProject(
          name: 'Bot',
          folderPath: dir.path,
        );
        final provider = await repo.saveProvider(
          name: 'Fake',
          baseUrl: 'https://fake.test',
          apiKey: 'key',
          models: ['fake-model'],
        );
        final model = (await repo.listProviderModels(provider.id)).single;
        final chat = await repo.createChat(
          projectId: project.id,
          title: 'New chat',
          providerId: provider.id,
          modelId: model.id,
        );
        final fakeProvider = QueueProvider(
          Queue<AIChatResponse>.from([
            const AIChatResponse(
              text: '',
              toolCalls: [
                AIToolCall(
                  id: 'call_write',
                  name: 'write',
                  argumentsJson: '{"path":"README.md","content":"hello"}',
                ),
              ],
              finishReason: 'tool_calls',
            ),
            const AIChatResponse(
              text: 'done',
              toolCalls: [],
              finishReason: 'stop',
            ),
          ]),
        );
        final toolSnapshots = <List<ToolExecution>>[];
        final loop = AgentLoop(
          repository: repo,
          providerFactory: (_) => fakeProvider,
          onMessagesChanged: (chatId) async {
            toolSnapshots.add(await repo.listToolExecutions(chatId));
          },
        );

        await loop.send(
          project: project,
          chat: chat,
          userText: 'create readme',
        );

        expect(
          await File(
            '${dir.path}${Platform.pathSeparator}README.md',
          ).readAsString(),
          'hello',
        );
        final execution = (await repo.listToolExecutions(chat.id)).single;
        expect(execution.status, ToolExecutionStatus.success);
        final canonicalToolResult =
            jsonDecode(execution.resultJson!) as Map<String, Object?>;
        expect(canonicalToolResult['ok'], isTrue);
        expect(
          (canonicalToolResult['result'] as Map<String, Object?>)['path'],
          'README.md',
        );
        expect(
          toolSnapshots.any(
            (items) =>
                items.isNotEmpty &&
                items.single.status == ToolExecutionStatus.running,
          ),
          isTrue,
        );
        expect(
          toolSnapshots.any(
            (items) =>
                items.isNotEmpty &&
                items.single.status == ToolExecutionStatus.success,
          ),
          isTrue,
        );
        expect((await repo.getChat(chat.id))!.status, ChatStatus.completed);
        expect(
          (await repo.listMessages(
            chat.id,
          )).where((message) => message.role == MessageRole.tool),
          isNotEmpty,
        );
        expect(fakeProvider.requests, hasLength(2));
        final secondRequest = fakeProvider.requests.last;
        final assistantToolMessage = secondRequest.messages.lastWhere(
          (message) => message.role == 'assistant',
        );
        expect(assistantToolMessage.toolCalls?.single.id, 'call_write');
        expect(
          secondRequest.messages
              .lastWhere((message) => message.role == 'tool')
              .toolCallId,
          'call_write',
        );
        await dir.delete(recursive: true);
      },
    );

    test('uses first configured model when chat has no model', () async {
      final repo = await repository();
      final dir = await Directory.systemTemp.createTemp('syntac_agent_test_');
      final project = await repo.createProject(
        name: 'Bot',
        folderPath: dir.path,
      );
      await repo.saveProvider(
        name: 'Fake',
        baseUrl: 'https://fake.test',
        apiKey: 'key',
        models: ['fallback-model'],
      );
      final chat = await repo.createChat(
        projectId: project.id,
        title: 'New chat',
      );
      final fakeProvider = QueueProvider(
        Queue<AIChatResponse>.from([
          const AIChatResponse(
            text: 'done',
            toolCalls: [],
            finishReason: 'stop',
          ),
        ]),
      );
      final loop = AgentLoop(
        repository: repo,
        providerFactory: (_) => fakeProvider,
      );

      await loop.send(project: project, chat: chat, userText: 'hello');

      expect(fakeProvider.requests.single.model, 'fallback-model');
      await dir.delete(recursive: true);
    });

    test('executes parallel tool calls from one assistant turn', () async {
      final repo = await repository();
      final dir = await Directory.systemTemp.createTemp('syntac_agent_test_');
      final project = await repo.createProject(
        name: 'Bot',
        folderPath: dir.path,
      );
      final provider = await repo.saveProvider(
        name: 'Fake',
        baseUrl: 'https://fake.test',
        apiKey: 'key',
        models: ['fake-model'],
      );
      final model = (await repo.listProviderModels(provider.id)).single;
      final chat = await repo.createChat(
        projectId: project.id,
        title: 'Parallel',
        providerId: provider.id,
        modelId: model.id,
      );
      final fakeProvider = QueueProvider(
        Queue<AIChatResponse>.from([
          const AIChatResponse(
            text: '',
            toolCalls: [
              AIToolCall(
                id: 'call_a',
                name: 'write',
                argumentsJson: '{"path":"a.txt","content":"A"}',
              ),
              AIToolCall(
                id: 'call_b',
                name: 'write',
                argumentsJson: '{"path":"b.txt","content":"B"}',
              ),
            ],
            finishReason: 'tool_calls',
          ),
          const AIChatResponse(
            text: 'done',
            toolCalls: [],
            finishReason: 'stop',
          ),
        ]),
      );
      final loop = AgentLoop(
        repository: repo,
        providerFactory: (_) => fakeProvider,
      );

      await loop.send(project: project, chat: chat, userText: 'write both');

      expect(
        await File('${dir.path}${Platform.pathSeparator}a.txt').readAsString(),
        'A',
      );
      expect(
        await File('${dir.path}${Platform.pathSeparator}b.txt').readAsString(),
        'B',
      );
      final executions = await repo.listToolExecutions(chat.id);
      expect(executions, hasLength(2));
      expect(
        executions.map((execution) => execution.status),
        everyElement(ToolExecutionStatus.success),
      );
      final toolMessages = (await repo.listMessages(
        chat.id,
      )).where((message) => message.role == MessageRole.tool).toList();
      expect(toolMessages.map((message) => message.toolCallId), [
        'call_a',
        'call_b',
      ]);
      await dir.delete(recursive: true);
    });

    test(
      'returns malformed tool call errors to the model and can continue',
      () async {
        final repo = await repository();
        final dir = await Directory.systemTemp.createTemp('syntac_agent_test_');
        final project = await repo.createProject(
          name: 'Bot',
          folderPath: dir.path,
        );
        final provider = await repo.saveProvider(
          name: 'Fake',
          baseUrl: 'https://fake.test',
          apiKey: 'key',
          models: ['fake-model'],
        );
        final model = (await repo.listProviderModels(provider.id)).single;
        final chat = await repo.createChat(
          projectId: project.id,
          title: 'New chat',
          providerId: provider.id,
          modelId: model.id,
        );
        final fake = Queue<AIChatResponse>.from([
          const AIChatResponse(
            text: '',
            toolCalls: [
              AIToolCall(id: 'bad', name: 'read', argumentsJson: '{bad'),
            ],
            finishReason: 'tool_calls',
          ),
          const AIChatResponse(
            text: 'recovered',
            toolCalls: [],
            finishReason: 'stop',
          ),
        ]);
        final loop = AgentLoop(
          repository: repo,
          providerFactory: (_) => QueueProvider(fake),
        );

        await loop.send(project: project, chat: chat, userText: 'read file');

        expect(
          (await repo.listToolExecutions(chat.id)).single.status,
          ToolExecutionStatus.error,
        );
        expect((await repo.getChat(chat.id))!.status, ChatStatus.completed);
        await dir.delete(recursive: true);
      },
    );

    test('refreshes Google OAuth credential before agent request', () async {
      final repo = await repository();
      final dir = await Directory.systemTemp.createTemp('syntac_agent_test_');
      final project = await repo.createProject(
        name: 'Bot',
        folderPath: dir.path,
      );
      final provider = await repo.saveProvider(
        name: 'Google Antigravity',
        baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
        apiKey: '',
        providerKey: ProviderRegistry.googleAntigravity.id,
        authType: ProviderAuthType.googleAntigravityOAuth.name,
        models: ['gemini-3.5-flash'],
      );
      final model = (await repo.listProviderModels(provider.id)).single;
      final chat = await repo.createChat(
        projectId: project.id,
        title: 'New chat',
        providerId: provider.id,
        modelId: model.id,
      );
      await repo.saveOAuthCredential(
        provider.id,
        OAuthCredential(
          provider: OAuthProviderId.googleAntigravity,
          accessToken: 'stale-token',
          refreshToken: 'refresh-token',
          expiresAt: DateTime.now().add(const Duration(minutes: 1)),
          projectId: 'project-123',
        ),
      );
      final fakeProvider = CapturingProvider();
      var refreshCount = 0;
      final loop = AgentLoop(
        repository: repo,
        providerFactory: (_) => fakeProvider,
        googleOAuthRefresh: (credential) async {
          refreshCount++;
          return credential.copyWith(
            accessToken: 'fresh-token',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          );
        },
      );

      await loop.send(project: project, chat: chat, userText: 'hello');

      expect(refreshCount, 1);
      expect(fakeProvider.tokens, ['fresh-token']);
      expect(
        (await repo.readOAuthCredential(provider.id))!.accessToken,
        'fresh-token',
      );
      expect((await repo.getChat(chat.id))!.status, ChatStatus.completed);
      await dir.delete(recursive: true);
    });

    test('refreshes Google OAuth credential once after 401', () async {
      final repo = await repository();
      final dir = await Directory.systemTemp.createTemp('syntac_agent_test_');
      final project = await repo.createProject(
        name: 'Bot',
        folderPath: dir.path,
      );
      final provider = await repo.saveProvider(
        name: 'Google Antigravity',
        baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
        apiKey: '',
        providerKey: ProviderRegistry.googleAntigravity.id,
        authType: ProviderAuthType.googleAntigravityOAuth.name,
        models: ['gemini-3.5-flash'],
      );
      final model = (await repo.listProviderModels(provider.id)).single;
      final chat = await repo.createChat(
        projectId: project.id,
        title: 'New chat',
        providerId: provider.id,
        modelId: model.id,
      );
      await repo.saveOAuthCredential(
        provider.id,
        OAuthCredential(
          provider: OAuthProviderId.googleAntigravity,
          accessToken: 'stale-token',
          refreshToken: 'refresh-token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          projectId: 'project-123',
        ),
      );
      final fakeProvider = CapturingProvider(failFirstWith401: true);
      var refreshCount = 0;
      final loop = AgentLoop(
        repository: repo,
        providerFactory: (_) => fakeProvider,
        googleOAuthRefresh: (credential) async {
          refreshCount++;
          return credential.copyWith(
            accessToken: 'fresh-token',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          );
        },
      );

      await loop.send(project: project, chat: chat, userText: 'hello');

      expect(refreshCount, 1);
      expect(fakeProvider.tokens, ['stale-token', 'fresh-token']);
      expect(
        (await repo.readOAuthCredential(provider.id))!.accessToken,
        'fresh-token',
      );
      expect((await repo.getChat(chat.id))!.status, ChatStatus.completed);
      expect(
        (await repo.listMessages(
          chat.id,
        )).where((message) => message.role == MessageRole.assistant),
        hasLength(1),
      );
      await dir.delete(recursive: true);
    });

    test('preflight provider errors are persisted on chat and job', () async {
      final repo = await repository();
      final dir = await Directory.systemTemp.createTemp('syntac_agent_test_');
      final project = await repo.createProject(
        name: 'Bot',
        folderPath: dir.path,
      );
      final chat = await repo.createChat(
        projectId: project.id,
        title: 'New chat',
      );
      final loop = AgentLoop(repository: repo);

      await expectLater(
        loop.send(project: project, chat: chat, userText: 'hello'),
        throwsA(isA<StateError>()),
      );

      expect((await repo.getChat(chat.id))!.status, ChatStatus.error);
      expect(
        (await repo.listAgentJobs(chat.id)).single.state,
        AgentJobState.error,
      );
      expect(
        (await repo.listMessages(chat.id)).map((message) => message.role),
        containsAll([MessageRole.user, MessageRole.internal]),
      );
      await dir.delete(recursive: true);
    });

    test('provider network failures persist safe user-facing text', () async {
      final repo = await repository();
      final dir = await Directory.systemTemp.createTemp('syntac_agent_test_');
      final project = await repo.createProject(
        name: 'Bot',
        folderPath: dir.path,
      );
      final provider = await repo.saveProvider(
        name: 'OpenRouter',
        baseUrl: 'https://openrouter.ai',
        apiKey: 'key',
        models: ['openrouter-model'],
      );
      final model = (await repo.listProviderModels(provider.id)).single;
      final chat = await repo.createChat(
        projectId: project.id,
        title: 'New chat',
        providerId: provider.id,
        modelId: model.id,
      );
      final loop = AgentLoop(
        repository: repo,
        providerFactory: (_) => FailingProvider(
          const AIProviderException(
            "ClientException with SocketException: Failed host lookup: 'openrouter.ai'",
            kind: 'dns_failure',
          ),
        ),
      );

      await expectLater(
        loop.send(project: project, chat: chat, userText: 'hello'),
        throwsA(isA<AIProviderException>()),
      );

      final failedChat = (await repo.getChat(chat.id))!;
      expect(failedChat.status, ChatStatus.error);
      expect(
        failedChat.error,
        "Couldn't find OpenRouter. Check your internet connection and provider URL.",
      );
      final internal = (await repo.listMessages(
        chat.id,
      )).lastWhere((message) => message.role == MessageRole.internal);
      expect(internal.content, contains("Couldn't find OpenRouter"));
      expect(internal.content, isNot(contains('ClientException')));
      expect(internal.content, isNot(contains('SocketException')));
      await dir.delete(recursive: true);
    });

    test('stop cancels a running chat and marks it interrupted', () async {
      final repo = await repository();
      final dir = await Directory.systemTemp.createTemp('syntac_agent_test_');
      final project = await repo.createProject(
        name: 'Bot',
        folderPath: dir.path,
      );
      final provider = await repo.saveProvider(
        name: 'Fake',
        baseUrl: 'https://fake.test',
        apiKey: 'key',
        models: ['fake-model'],
      );
      final model = (await repo.listProviderModels(provider.id)).single;
      final chat = await repo.createChat(
        projectId: project.id,
        title: 'New chat',
        providerId: provider.id,
        modelId: model.id,
      );
      final loop = AgentLoop(
        repository: repo,
        providerFactory: (_) => HangingProvider(),
      );

      final run = loop.send(project: project, chat: chat, userText: 'wait');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await loop.stop(chat.id);
      await run;

      expect((await repo.getChat(chat.id))!.status, ChatStatus.interrupted);
      await dir.delete(recursive: true);
    });

    test('stop cancels a running bash tool without resuming model', () async {
      final repo = await repository();
      final dir = await Directory.systemTemp.createTemp('syntac_agent_test_');
      final project = await repo.createProject(
        name: 'Bot',
        folderPath: dir.path,
      );
      final provider = await repo.saveProvider(
        name: 'Fake',
        baseUrl: 'https://fake.test',
        apiKey: 'key',
        models: ['fake-model'],
      );
      final model = (await repo.listProviderModels(provider.id)).single;
      final chat = await repo.createChat(
        projectId: project.id,
        title: 'New chat',
        providerId: provider.id,
        modelId: model.id,
      );
      final shell = CancellableShellExecutor();
      final fakeProvider = QueueProvider(
        Queue<AIChatResponse>.from([
          const AIChatResponse(
            text: '',
            toolCalls: [
              AIToolCall(
                id: 'call_bash',
                name: 'bash',
                argumentsJson: '{"command":"sleep 30"}',
              ),
            ],
            finishReason: 'tool_calls',
          ),
          const AIChatResponse(
            text: 'should not resume',
            toolCalls: [],
            finishReason: 'stop',
          ),
        ]),
      );
      final loop = AgentLoop(
        repository: repo,
        providerFactory: (_) => fakeProvider,
        shellExecutorFactory: (_) async => shell,
      );

      final run = loop.send(project: project, chat: chat, userText: 'run');
      await shell.started.future;
      await loop.stop(chat.id);
      await run;

      expect(shell.cancelObserved, isTrue);
      expect(fakeProvider.requests, hasLength(1));
      expect((await repo.getChat(chat.id))!.status, ChatStatus.interrupted);
      final execution = (await repo.listToolExecutions(chat.id)).single;
      expect(execution.status, ToolExecutionStatus.cancelled);
      expect(
        (await repo.listMessages(
          chat.id,
        )).where((message) => message.role == MessageRole.tool),
        isEmpty,
      );
      await dir.delete(recursive: true);
    });
  });

  test('streaming chunks update assistant message incrementally', () async {
    final repo = await repository();
    final dir = await Directory.systemTemp.createTemp('syntac_stream_test_');
    final project = await repo.createProject(name: 'Bot', folderPath: dir.path);
    final provider = await repo.saveProvider(
      name: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      apiKey: 'key',
      models: ['openai/gpt-4o-mini'],
    );
    final model = (await repo.listProviderModels(provider.id)).single;
    final chat = await repo.createChat(
      projectId: project.id,
      title: 'New chat',
      providerId: provider.id,
      modelId: model.id,
    );
    final snapshots = <String>[];
    final loop = AgentLoop(
      repository: repo,
      providerFactory: (_) => SlowStreamingProvider(),
      onMessagesChanged: (chatId) async {
        final assistantMessages = (await repo.listMessages(
          chatId,
        )).where((message) => message.role == MessageRole.assistant).toList();
        if (assistantMessages.isNotEmpty) {
          snapshots.add(assistantMessages.last.content);
        }
      },
    );

    await loop.send(project: project, chat: chat, userText: 'hello');

    expect(snapshots, contains('He'));
    expect(snapshots.last, 'Hello');
    final assistant = (await repo.listMessages(
      chat.id,
    )).lastWhere((message) => message.role == MessageRole.assistant);
    final metadata =
        jsonDecode(assistant.metadataJson!) as Map<String, Object?>;
    final diagnostics = metadata['streamDiagnostics'] as Map<String, Object?>;
    expect(diagnostics['realStreamingObserved'], isTrue);
    final firstUiDeltaAt = DateTime.parse(
      diagnostics['firstUiDeltaAt']!.toString(),
    );
    final streamCompletedAt = DateTime.parse(
      diagnostics['streamCompletedAt']!.toString(),
    );
    expect(firstUiDeltaAt.isBefore(streamCompletedAt), isTrue);
    await dir.delete(recursive: true);
  });

  test('streaming error preserves partial assistant message', () async {
    final repo = await repository();
    final dir = await Directory.systemTemp.createTemp(
      'syntac_stream_error_test_',
    );
    final project = await repo.createProject(name: 'Bot', folderPath: dir.path);
    final provider = await repo.saveProvider(
      name: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      apiKey: 'key',
      models: ['openai/gpt-4o-mini'],
    );
    final model = (await repo.listProviderModels(provider.id)).single;
    final chat = await repo.createChat(
      projectId: project.id,
      title: 'New chat',
      providerId: provider.id,
      modelId: model.id,
    );
    final loop = AgentLoop(
      repository: repo,
      providerFactory: (_) => ErrorAfterTextProvider(),
    );

    await expectLater(
      loop.send(project: project, chat: chat, userText: 'hello'),
      throwsA(isA<AIProviderException>()),
    );

    final assistant = (await repo.listMessages(
      chat.id,
    )).where((message) => message.role == MessageRole.assistant).single;
    expect(assistant.content, 'partial');
    expect((await repo.getChat(chat.id))!.status, ChatStatus.error);
    await dir.delete(recursive: true);
  });

  test('bash timeout parsing and runtime failures are structured', () async {
    final dir = await Directory.systemTemp.createTemp('syntac_runtime_test_');
    final tools = ProjectTools(
      projectRoot: dir.path,
      shellExecutor: CapturingShellExecutor(
        CommandResult(
          stdout: '',
          stderr: 'no callback',
          exitCode: -1,
          duration: const Duration(seconds: 10),
          failureKind: 'CallbackFailed',
          timedOut: false,
          cancelled: false,
        ),
      ),
    );

    final result = await tools.execute('bash', {
      'command': 'echo hello',
      'timeout_seconds': 10,
    });

    expect(result['ok'], isTrue);
    final payload = result['result'] as Map<String, Object?>;
    expect(payload['workingDirectory'], dir.path);
    expect(payload['category'], 'runtime_failure');
    expect(payload['failureKind'], 'CallbackFailed');
    expect(
      payload['message'],
      'Runtime did not return a command result callback.',
    );
    await dir.delete(recursive: true);
  });

  test('bash command failures preserve stdout stderr and exit code', () async {
    final dir = await Directory.systemTemp.createTemp('syntac_runtime_test_');
    final tools = ProjectTools(
      projectRoot: dir.path,
      shellExecutor: CapturingShellExecutor(
        const CommandResult(
          stdout: '',
          stderr: 'sh: nope: not found',
          exitCode: 127,
          duration: Duration(milliseconds: 42),
          timedOut: false,
          cancelled: false,
        ),
      ),
    );

    final result = await tools.execute('bash', {'command': 'nope'});

    expect(result['ok'], isTrue);
    final payload = result['result'] as Map<String, Object?>;
    expect(payload['success'], isFalse);
    expect(payload['category'], 'command_exit_error');
    expect(payload['stderr'], 'sh: nope: not found');
    expect(payload['exitCode'], 127);
    await dir.delete(recursive: true);
  });
  test('bash output is capped before tool result persistence', () async {
    final dir = await Directory.systemTemp.createTemp('syntac_runtime_test_');
    final largeText = 'o' * (maxPersistedTextCharacters + 1000);
    final tools = ProjectTools(
      projectRoot: dir.path,
      shellExecutor: CapturingShellExecutor(
        CommandResult(
          stdout: largeText,
          stderr: '',
          exitCode: 0,
          duration: const Duration(milliseconds: 10),
          timedOut: false,
          cancelled: false,
        ),
      ),
    );

    final result = await tools.execute('bash', {'command': 'pacman -Sy'});

    expect(result['ok'], isTrue);
    final payload = result['result'] as Map<String, Object?>;
    expect(
      payload['stdout'].toString().length,
      lessThanOrEqualTo(maxPersistedTextCharacters),
    );
    expect(payload['stdout'], contains(persistenceTruncationNotice));
    expect(payload['stdoutTruncated'], isTrue);
    expect(payload['stdoutOriginalLength'], largeText.length);
    await dir.delete(recursive: true);
  });

  test('bash stdout and stderr share aggregate output cap', () async {
    final dir = await Directory.systemTemp.createTemp('syntac_runtime_test_');
    final largeStdout = 'o' * 40000;
    final largeStderr = 'e' * 40000;
    final tools = ProjectTools(
      projectRoot: dir.path,
      shellExecutor: CapturingShellExecutor(
        CommandResult(
          stdout: largeStdout,
          stderr: largeStderr,
          exitCode: 1,
          duration: const Duration(milliseconds: 10),
          timedOut: false,
          cancelled: false,
        ),
      ),
    );

    final result = await tools.execute('bash', {'command': 'noisy'});

    final payload = result['result'] as Map<String, Object?>;
    expect(
      payload['stdout'].toString().length + payload['stderr'].toString().length,
      lessThanOrEqualTo(maxPersistedTextCharacters),
    );
    expect(payload['stdoutTruncated'], isTrue);
    expect(payload['stderrTruncated'], isTrue);
    await dir.delete(recursive: true);
  });

  test('bash streaming updates expose bounded running output', () async {
    final dir = await Directory.systemTemp.createTemp('syntac_runtime_test_');
    final updates = <Map<String, Object?>>[];
    final tools = ProjectTools(
      projectRoot: dir.path,
      shellExecutor: CapturingShellExecutor(
        const CommandResult(
          stdout: 'final',
          stderr: '',
          exitCode: 0,
          duration: Duration(milliseconds: 10),
          timedOut: false,
          cancelled: false,
        ),
        outputUpdates: [
          const CommandOutputUpdate(
            stream: 'stdout',
            text: 'partial',
            stdout: 'partial',
          ),
        ],
      ),
    );

    final result = await tools.execute('bash', {
      'command': 'pacman -Sy',
    }, onUpdate: updates.add);

    expect(result['ok'], isTrue);
    expect(updates, isNotEmpty);
    expect(updates.single['category'], 'running');
    expect(updates.single['stdout'], 'partial');
    await dir.delete(recursive: true);
  });

  test('Termux background restriction interrupts agent without retry', () async {
    final repo = await repository();
    final dir = await Directory.systemTemp.createTemp('syntac_runtime_test_');
    final project = await repo.createProject(name: 'Bot', folderPath: dir.path);
    final provider = await repo.saveProvider(
      name: 'Google Antigravity',
      baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
      providerKey: 'google-antigravity',
      authType: 'googleAntigravityOAuth',
      apiKey: '',
      models: ['gemini-3.1-pro'],
    );
    await repo.saveOAuthCredential(
      provider.id,
      OAuthCredential(
        provider: OAuthProviderId.googleAntigravity,
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        projectId: 'project-123',
      ),
    );
    final model = (await repo.listProviderModels(provider.id)).single;
    final chat = await repo.createChat(
      projectId: project.id,
      title: 'New chat',
      providerId: provider.id,
      modelId: model.id,
    );
    final fakeProvider = QueueProvider(
      Queue<AIChatResponse>.from([
        const AIChatResponse(
          text: '',
          toolCalls: [
            AIToolCall(
              id: 'call_bash',
              name: 'bash',
              argumentsJson: '{"command":"ls"}',
            ),
          ],
          finishReason: 'tool_calls',
        ),
      ]),
    );
    final loop = AgentLoop(
      repository: repo,
      providerFactory: (_) => fakeProvider,
      shellExecutorFactory: (_) async => CapturingShellExecutor(
        CommandResult(
          stdout: '',
          stderr:
              'Android blocked starting a Termux command while Syntac was in the background.',
          exitCode: -1,
          duration: const Duration(milliseconds: 10),
          failureKind: 'TermuxBackgroundRestricted',
          timedOut: false,
          cancelled: false,
        ),
      ),
    );

    await loop.send(project: project, chat: chat, userText: 'run ls');

    final failedChat = (await repo.getChat(chat.id))!;
    expect(failedChat.status, ChatStatus.interrupted);
    expect(failedChat.error, contains('Android blocked Termux execution'));
    final execution = (await repo.listToolExecutions(chat.id)).single;
    expect(execution.status, ToolExecutionStatus.error);
    final payload =
        (jsonDecode(execution.resultJson!) as Map<String, Object?>)['result']
            as Map<String, Object?>;
    expect(payload['category'], 'termux_background_restricted');
    expect(fakeProvider.requests, hasLength(1));
    await dir.delete(recursive: true);
  });

  test('provider error details are shown sanitized', () {
    final details = ProviderErrorDetails(
      providerName: 'OpenRouter',
      modelId: 'openai/gpt-4o-mini',
      requestUrl: 'https://openrouter.ai/api/v1/chat/completions',
      method: 'POST',
      httpStatus: 401,
      errorType: 'auth_error',

      responseBody:
          '{"error":{"message":"bad"},"access_token":"secret","Authorization":"Bearer abc"}',
    );

    final message = describeAIErrorForUser(
      AIProviderException(
        'bad',
        statusCode: 401,
        kind: 'auth_error',
        details: details,
      ),
      providerName: 'OpenRouter',
    );

    expect(message, contains('Provider: OpenRouter'));
    expect(message, contains('Status: 401'));
    expect(
      message,
      contains('Endpoint: https://openrouter.ai/api/v1/chat/completions'),
    );
    expect(message, isNot(contains('secret')));
    expect(message, isNot(contains('Bearer abc')));
  });

  test('Google Antigravity uses Cloud Code Assist streaming protocol', () async {
    final seen = <String>[];
    final provider = GoogleCloudCodeAssistProvider(
      baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
      client: MockClient((request) async {
        seen.add('${request.method} ${request.url}');
        expect(request.headers['Authorization'], startsWith('Bearer '));
        expect(request.headers['Accept'], 'text/event-stream');
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['model'], 'gemini-3.1-pro-low');
        expect(body['requestType'], 'agent');
        expect(body['request'], isA<Map>());
        return http.Response(
          'data: ${jsonEncode({
            'response': {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'hi'},
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
            },
          })}\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );

    final credential = OAuthCredential(
      provider: OAuthProviderId.googleAntigravity,
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      projectId: 'project-123',
    );

    final response = await provider.completeChat(
      AIChatRequest(
        model: 'gemini-3.1-pro',
        messages: const [AIChatMessage(role: 'user', content: 'hello')],
        tools: const [],
      ),
      apiKey: credential.toStructuredApiKey(),
    );

    expect(response.text, 'hi');
    expect(
      seen.single,
      'POST https://daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse',
    );
  });

  test('Antigravity matches OMP routed model output cap', () async {
    Map<String, Object?>? captured;
    final provider = GoogleCloudCodeAssistProvider(
      baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
      client: MockClient((request) async {
        captured = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          'data: ${jsonEncode({
            'response': {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'ok'},
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
            },
          })}\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );

    await provider.completeChat(
      const AIChatRequest(
        model: 'gemini-3.1-pro-preview',
        messages: [
          AIChatMessage(role: 'system', content: 'You are a coding agent.'),
          AIChatMessage(role: 'user', content: 'hello'),
        ],
        tools: [],
        maxOutputTokens: 65536,
      ),
      apiKey: jsonEncode({'token': 'access-token', 'projectId': 'project-123'}),
    );

    expect(captured!['model'], 'gemini-3.1-pro-low');
    final request = captured!['request'] as Map;
    final generationConfig = request['generationConfig'] as Map;
    expect(generationConfig['maxOutputTokens'], 65535);
    final systemInstruction = request['systemInstruction'] as Map;
    expect(systemInstruction['role'], 'user');
  });
  test('Google Antigravity merges consecutive user turns', () async {
    Map<String, Object?>? captured;
    final provider = GoogleCloudCodeAssistProvider(
      baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
      client: MockClient((request) async {
        captured = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          'data: ${jsonEncode({
            'response': {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'ok'},
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
            },
          })}\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );

    await provider.completeChat(
      const AIChatRequest(
        model: 'gemini-3.1-pro',
        messages: [
          AIChatMessage(role: 'user', content: 'one'),
          AIChatMessage(role: 'user', content: 'two'),
          AIChatMessage(role: 'user', content: 'three'),
        ],
        tools: [],
      ),
      apiKey: jsonEncode({'token': 'access-token', 'projectId': 'project-123'}),
    );

    final body = captured!['request'] as Map<String, Object?>;
    final contents = body['contents'] as List<Object?>;
    expect(contents, hasLength(1));
    expect(
      ((contents.single as Map)['parts'] as List).map(
        (part) => (part as Map)['text'],
      ),
      ['one', 'two', 'three'],
    );
  });

  test(
    'Google request groups parallel function responses and omits ids',
    () async {
      Map<String, Object?>? secondRequestBody;
      var requestCount = 0;
      final provider = GoogleCloudCodeAssistProvider(
        baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
        client: MockClient((request) async {
          requestCount++;
          if (requestCount == 2) {
            secondRequestBody =
                jsonDecode(request.body) as Map<String, Object?>;
          }
          final parts = requestCount == 1
              ? [
                  {
                    'functionCall': {
                      'name': 'read',
                      'args': {'path': 'a.txt'},
                    },
                    'thoughtSignature': 'sig_a',
                  },
                  {
                    'functionCall': {
                      'name': 'list',
                      'args': {'path': '.'},
                    },
                    'thoughtSignature': 'sig_b',
                  },
                ]
              : [
                  {'text': 'done'},
                ];
          return http.Response(
            'data: ${jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {'parts': parts},
                    'finishReason': 'STOP',
                  },
                ],
              },
            })}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      final credential = OAuthCredential(
        provider: OAuthProviderId.googleAntigravity,
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        projectId: 'project-123',
      );
      final first = await provider.completeChat(
        AIChatRequest(
          model: 'gemini-3.1-pro',
          messages: const [AIChatMessage(role: 'user', content: 'call tools')],
          tools: const [],
        ),
        apiKey: credential.toStructuredApiKey(),
      );
      expect(first.toolCalls, hasLength(2));
      await provider.completeChat(
        AIChatRequest(
          model: 'gemini-3.1-pro',
          messages: [
            const AIChatMessage(role: 'user', content: 'call tools'),
            AIChatMessage(
              role: 'assistant',
              content: '',
              toolCalls: first.toolCalls,
              providerMetadata: first.providerMetadata,
            ),
            AIChatMessage(
              role: 'tool',
              content: '{"ok":true}',
              toolCallId: first.toolCalls[0].id,
            ),
            AIChatMessage(
              role: 'tool',
              content: '{"ok":true}',
              toolCallId: first.toolCalls[1].id,
            ),
          ],
          tools: const [],
        ),
        apiKey: credential.toStructuredApiKey(),
      );
      final request = secondRequestBody!['request'] as Map<String, Object?>;
      final contents = request['contents'] as List;
      final responseTurns = contents
          .where(
            (turn) =>
                turn is Map &&
                (turn['parts'] as List).any(
                  (part) => part is Map && part['functionResponse'] != null,
                ),
          )
          .toList();
      expect(responseTurns, hasLength(1));
      final responseParts = (responseTurns.single as Map)['parts'] as List;
      expect(responseParts, hasLength(2));
      expect(jsonEncode(responseParts), isNot(contains('"id"')));
    },
  );
  test(
    'Google Antigravity preserves thought signatures across sequential tools',
    () async {
      final repo = await repository();
      final dir = await Directory.systemTemp.createTemp('syntac_gemini_test_');
      await File(
        '${dir.path}${Platform.pathSeparator}hello.txt',
      ).writeAsString('Hello');
      final project = await repo.createProject(
        name: 'Bot',
        folderPath: dir.path,
      );
      final providerConfig = await repo.saveProvider(
        name: 'Google Antigravity',
        baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
        providerKey: 'google-antigravity',
        authType: 'googleAntigravityOAuth',
        apiKey: '',
        models: ['gemini-3.1-pro'],
      );
      await repo.saveOAuthCredential(
        providerConfig.id,
        OAuthCredential(
          provider: OAuthProviderId.googleAntigravity,
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          projectId: 'project-123',
        ),
      );
      final model = (await repo.listProviderModels(providerConfig.id)).single;
      final chat = await repo.createChat(
        projectId: project.id,
        title: 'New chat',
        providerId: providerConfig.id,
        modelId: model.id,
      );
      var requestCount = 0;
      final provider = GoogleCloudCodeAssistProvider(
        baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
        client: MockClient((request) async {
          requestCount++;
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final requestBody = body['request'] as Map<String, Object?>;
          final contentsJson = jsonEncode(requestBody['contents']);
          if (requestCount > 1) {
            expect(contentsJson, contains('sig_${requestCount - 1}'));
          }
          final part = switch (requestCount) {
            1 => {
              'functionCall': {
                'id': 'call_list',
                'name': 'list',
                'args': {'path': '.'},
              },
              'thoughtSignature': 'sig_1',
            },
            2 => {
              'functionCall': {
                'id': 'call_read',
                'name': 'read',
                'args': {'path': 'hello.txt'},
              },
              'thoughtSignature': 'sig_2',
            },
            3 => {
              'functionCall': {
                'id': 'call_edit',
                'name': 'edit',
                'args': {
                  'path': 'hello.txt',
                  'target': 'Hello',
                  'replacement': 'Hello World',
                },
              },
              'thoughtSignature': 'sig_3',
            },
            _ => {'text': 'done'},
          };
          return http.Response(
            'data: ${jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [part],
                    },
                    'finishReason': requestCount < 4 ? 'STOP' : 'STOP',
                  },
                ],
              },
            })}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      final loop = AgentLoop(
        repository: repo,
        providerFactory: (_) => provider,
      );

      await loop.send(
        project: project,
        chat: chat,
        userText: 'list, read, edit, final',
      );

      expect(requestCount, 4);
      expect(
        await File(
          '${dir.path}${Platform.pathSeparator}hello.txt',
        ).readAsString(),
        'Hello World',
      );
      final assistantMessages = (await repo.listMessages(
        chat.id,
      )).where((message) => message.role == MessageRole.assistant).toList();
      final firstMetadata =
          jsonDecode(assistantMessages.first.metadataJson!)
              as Map<String, Object?>;
      final continuity = firstMetadata['providerToolContinuity'] as List;
      expect(continuity.single['thoughtSignatureReceived'], isTrue);
      expect(continuity.single['thoughtSignaturePersisted'], isTrue);
      await dir.delete(recursive: true);
    },
  );

  test('context trimming drops partial parallel Gemini tool exchanges', () {
    final builder = ContextBuilder(maxCharacters: 100000);
    final chatId = newId();
    final messages = [
      ChatMessage.create(
        chatId: chatId,
        role: MessageRole.user,
        content: 'start',
      ),
      ChatMessage.create(
        chatId: chatId,
        role: MessageRole.assistant,
        content: '',
        metadata: {
          'toolCalls': [
            {
              'id': 'call_read',
              'function': {'name': 'read', 'arguments': '{"path":"a.txt"}'},
            },
            {
              'id': 'call_list',
              'function': {'name': 'list', 'arguments': '{"path":"."}'},
            },
          ],
        },
      ),
      ChatMessage.create(
        chatId: chatId,
        role: MessageRole.tool,
        toolCallId: 'call_list',
        content: '{"ok":true,"items":[]}',
      ),
      ChatMessage.create(
        chatId: chatId,
        role: MessageRole.user,
        content: 'continue',
      ),
    ];

    final built = builder.build(history: messages);

    expect(built.first.role, 'system');
    expect(built.where((message) => message.role == 'user'), hasLength(2));
    expect(built.last.content, 'continue');
    expect(
      built.skip(1).where((message) => message.role == 'assistant'),
      isEmpty,
    );
    expect(built.skip(1).where((message) => message.role == 'tool'), isEmpty);
  });

  test(
    'Google Antigravity preserves model text and function call turn',
    () async {
      Map<String, Object?>? secondRequestBody;
      var requestCount = 0;
      final provider = GoogleCloudCodeAssistProvider(
        baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
        client: MockClient((request) async {
          requestCount++;
          if (requestCount == 2) {
            secondRequestBody =
                jsonDecode(request.body) as Map<String, Object?>;
          }
          final parts = requestCount == 1
              ? [
                  {'text': 'Need file'},
                  {
                    'functionCall': {
                      'name': 'read',
                      'args': {'path': 'a.txt'},
                    },
                    'thoughtSignature': 'sig_read',
                  },
                ]
              : [
                  {'text': 'done'},
                ];
          return http.Response(
            'data: ${jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {'parts': parts},
                    'finishReason': 'STOP',
                  },
                ],
              },
            })}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      final credential = OAuthCredential(
        provider: OAuthProviderId.googleAntigravity,
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        projectId: 'project-123',
      );
      final first = await provider.completeChat(
        AIChatRequest(
          model: 'gemini-3.5-flash',
          messages: const [AIChatMessage(role: 'user', content: 'read file')],
          tools: const [],
        ),
        apiKey: credential.toStructuredApiKey(),
      );
      expect(first.text, 'Need file');
      expect(first.toolCalls.single.name, 'read');

      await provider.completeChat(
        AIChatRequest(
          model: 'gemini-3.5-flash',
          messages: [
            const AIChatMessage(role: 'user', content: 'read file'),
            AIChatMessage(
              role: 'assistant',
              content: first.text,
              toolCalls: first.toolCalls,
              providerMetadata: first.providerMetadata,
            ),
            AIChatMessage(
              role: 'tool',
              content: '{"ok":true}',
              toolCallId: first.toolCalls.single.id,
            ),
          ],
          tools: const [],
        ),
        apiKey: credential.toStructuredApiKey(),
      );
      final request = secondRequestBody!['request'] as Map<String, Object?>;
      final contents = request['contents'] as List;
      expect(contents, hasLength(3));
      final modelTurn = contents[1] as Map;
      expect(modelTurn['role'], 'model');
      final modelParts = modelTurn['parts'] as List;
      expect(
        modelParts.where((part) => part is Map && part['text'] != null),
        hasLength(1),
      );
      expect(
        modelParts.where((part) => part is Map && part['functionCall'] != null),
        hasLength(1),
      );
      final responseTurn = contents[2] as Map;
      final responseParts = responseTurn['parts'] as List;
      final functionResponse =
          (responseParts.single as Map)['functionResponse'] as Map;
      expect(functionResponse['name'], 'read');
    },
  );

  test(
    'Google Antigravity preflight rejects orphan function call turns',
    () async {
      final provider = GoogleCloudCodeAssistProvider(
        baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
        client: MockClient(
          (_) async => fail('Malformed request should not send'),
        ),
      );
      final credential = OAuthCredential(
        provider: OAuthProviderId.googleAntigravity,
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        projectId: 'project-123',
      );

      await expectLater(
        provider.completeChat(
          AIChatRequest(
            model: 'gemini-3.5-flash',
            messages: const [
              AIChatMessage(
                role: 'assistant',
                content: '',
                toolCalls: [
                  AIToolCall(
                    id: 'call_read',
                    name: 'read',
                    argumentsJson: '{"path":"a.txt"}',
                  ),
                ],
              ),
            ],
            tools: const [],
          ),
          apiKey: credential.toStructuredApiKey(),
        ),
        throwsA(
          isA<AIProviderException>()
              .having((error) => error.kind, 'kind', 'malformed_request')
              .having(
                (error) => error.details?.finalResponse,
                'trace',
                contains('contents[0]'),
              ),
        ),
      );
    },
  );
  test('generic agent errors include structured category and detail', () {
    expect(
      describeAIErrorForUser(StateError('chat already running')),
      'agent_state_error: chat already running',
    );
    expect(
      describeAIErrorForUser(const FormatException('bad tool json')),
      'invalid_agent_data: bad tool json',
    );
  });

  test(
    'update service returns newer beta manifest from fallback endpoint',
    () async {
      final calls = <Uri>[];
      final service = UpdateService(
        client: MockClient((request) async {
          calls.add(request.url);
          if (calls.length == 1) return http.Response('missing', 404);
          return http.Response(
            jsonEncode({
              'version': '0.1.2-beta.1',
              'versionCode': 13,
              'apkUrl':
                  'https://github.com/DraxonV1/Syntac/releases/download/v0.1.2-beta.1/syntac-arm64.apk',
              'sha256': 'abc123',
              'size': 151433720,
              'mandatory': false,
              'minSupportedVersionCode': 10,
              'notes': ['Update banner copy', 'Runtime diagnostics'],
            }),
            200,
          );
        }),
        endpoints: [
          Uri.parse('https://syntac.com/download/beta.json'),
          Uri.parse(
            'https://raw.githubusercontent.com/DraxonV1/Syntac/main/update/beta.json',
          ),
        ],
      );

      final update = await service.check(
        channel: UpdateChannel.beta,
        currentVersionCode: 12,
      );

      expect(calls, hasLength(2));
      expect(update?.version, '0.1.2-beta.1');
      expect(update?.versionCode, 13);
      expect(update?.channel, UpdateChannel.beta);
      expect(update?.downloadUrl, contains('syntac-arm64.apk'));
      expect(update?.notes, contains('Update banner copy'));
    },
  );

  test('update service ignores current or older manifests', () async {
    final service = UpdateService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'version': '0.1.1-beta.2',
            'versionCode': 12,
            'apkUrl':
                'https://github.com/DraxonV1/Syntac/releases/download/v0.1.1-beta.2/syntac-arm64.apk',
            'sha256': 'abc123',
            'size': 151433720,
            'mandatory': false,
            'minSupportedVersionCode': 10,
            'notes': ['Current build'],
          }),
          200,
        ),
      ),
      endpoints: [Uri.parse('https://syntac.com/download/beta.json')],
    );

    expect(
      await service.check(channel: UpdateChannel.beta, currentVersionCode: 12),
      isNull,
    );
  });

  test('unsupported runtime capability maps are parsed', () {
    final status = RuntimeStatus.fromMap({
      'state': 'configurationRequired',
      'message': 'grant permission',
    });
    expect(status.state, RuntimeState.configurationRequired);
    expect(status.message, contains('grant'));
    expect(
      titleFromPrompt(
        '  Build authentication with email and password support across many screens  ',
      ),
      'Build authentication with email and password ...',
    );
  });
  test('Cloud Code Assist normalizes unsupported tool schema fields', () async {
    Map<String, Object?>? captured;
    final provider = GoogleCloudCodeAssistProvider(
      baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
      client: MockClient((request) async {
        captured = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          'data: ${jsonEncode({
            'response': {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'ok'},
                    ],
                  },
                },
              ],
            },
          })}\n'
          'data: ${jsonEncode({
            'response': {
              'candidates': [
                {'finishReason': 'STOP'},
              ],
            },
          })}\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );

    final credential = OAuthCredential(
      provider: OAuthProviderId.googleAntigravity,
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      projectId: 'project-123',
    );
    await provider.completeChat(
      AIChatRequest(
        model: 'gemini-3.5-flash',
        messages: const [AIChatMessage(role: 'user', content: 'hello')],
        tools: const [
          {
            'type': 'function',
            'function': {
              'name': 'read',
              'parameters': {
                'type': 'object',
                'additionalProperties': false,
                'properties': {
                  'path': {'type': 'string', 'format': 'uri'},
                  'optional': true,
                },
              },
            },
          },
        ],
      ),
      apiKey: credential.toStructuredApiKey(),
    );
    final request = captured!['request'] as Map<String, Object?>;
    final declarations = request['tools'] as List;
    final declaration =
        (declarations.single as Map)['functionDeclarations'] as List;
    final parameters = (declaration.single as Map)['parameters'] as Map;
    expect(parameters['additionalProperties'], isNull);
    expect((parameters['properties'] as Map)['path']['format'], isNull);
    expect((parameters['properties'] as Map)['optional'], isA<Map>());
  });
  test('Cloud Code Assist accepts normal agent tool payload', () async {
    Map<String, Object?>? captured;
    final provider = GoogleCloudCodeAssistProvider(
      baseUrl: GoogleAntigravityOAuthFlow.defaultBaseUrl,
      client: MockClient((request) async {
        captured = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          'data: ${jsonEncode({
            'response': {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'ok'},
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
            },
          })}\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );
    final tools = ProjectTools(
      projectRoot: '.',
      shellExecutor: CapturingShellExecutor(
        const CommandResult(
          stdout: '',
          stderr: '',
          exitCode: 0,
          duration: Duration.zero,
          timedOut: false,
          cancelled: false,
        ),
      ),
    ).specs;

    await provider.completeChat(
      AIChatRequest(
        model: 'gemini-3.1-pro-preview',
        messages: const [
          AIChatMessage(role: 'system', content: 'You are a coding agent.'),
          AIChatMessage(role: 'user', content: 'Read pubspec.yaml'),
        ],
        tools: tools,
        maxOutputTokens: 65536,
      ),
      apiKey: jsonEncode({'token': 'access-token', 'projectId': 'project-123'}),
    );

    final request = captured!['request'] as Map<String, Object?>;
    expect((request['contents'] as List), hasLength(1));
    expect(request['systemInstruction'], isA<Map>());
    final declarations =
        ((request['tools'] as List).single as Map)['functionDeclarations']
            as List;
    expect(declarations, hasLength(tools.length));
    for (final declaration in declarations) {
      expect((declaration as Map)['parameters'], isA<Map>());
    }
  });
}

class StreamingClient extends http.BaseClient {
  StreamingClient(this.lines);

  final List<String> lines;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(lines.map(utf8.encode)),
      200,
    );
  }
}

class CapturingProvider extends AIProvider {
  CapturingProvider({this.failFirstWith401 = false});

  final bool failFirstWith401;
  final tokens = <String>[];
  var calls = 0;

  @override
  Stream<AIStreamEvent> streamChat(
    AIChatRequest request, {
    required String apiKey,
    CancellationToken? cancellationToken,
  }) async* {
    calls++;
    tokens.add((jsonDecode(apiKey) as Map<String, Object?>)['token'] as String);
    if (failFirstWith401 && calls == 1) {
      throw const AIProviderException(
        'expired',
        statusCode: 401,
        kind: 'auth_error',
      );
    }
    yield AIStreamEvent.text('done');
    yield AIStreamEvent.done(toolCalls: const [], finishReason: 'stop');
  }
}

class QueueProvider extends AIProvider {
  QueueProvider(this.responses);

  final Queue<AIChatResponse> responses;
  final requests = <AIChatRequest>[];

  @override
  Stream<AIStreamEvent> streamChat(
    AIChatRequest request, {
    required String apiKey,
    CancellationToken? cancellationToken,
  }) async* {
    requests.add(request);
    final response = responses.removeFirst();
    if (response.text.isNotEmpty) yield AIStreamEvent.text(response.text);
    yield AIStreamEvent.done(
      toolCalls: response.toolCalls,
      finishReason: response.finishReason,
    );
  }
}

class HangingProvider extends AIProvider {
  @override
  Stream<AIStreamEvent> streamChat(
    AIChatRequest request, {
    required String apiKey,
    CancellationToken? cancellationToken,
  }) async* {
    await cancellationToken!.whenCancelled;
    throw const OperationCancelledException();
  }
}

class FailingProvider extends AIProvider {
  FailingProvider(this.error);

  final Object error;

  @override
  Stream<AIStreamEvent> streamChat(
    AIChatRequest request, {
    required String apiKey,
    CancellationToken? cancellationToken,
  }) async* {
    throw error;
  }
}

class ErrorAfterTextProvider extends AIProvider {
  @override
  Stream<AIStreamEvent> streamChat(
    AIChatRequest request, {
    required String apiKey,
    CancellationToken? cancellationToken,
  }) async* {
    yield AIStreamEvent.text('partial');
    throw const AIProviderException('stream failed', kind: 'provider_error');
  }
}

class SlowStreamingProvider extends AIProvider {
  @override
  Stream<AIStreamEvent> streamChat(
    AIChatRequest request, {
    required String apiKey,
    CancellationToken? cancellationToken,
  }) async* {
    yield AIStreamEvent.text('H');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    yield AIStreamEvent.text('e');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    yield AIStreamEvent.text('llo');
    yield AIStreamEvent.done(toolCalls: [], finishReason: 'stop');
  }
}

class CapturingShellExecutor implements ShellExecutor {
  CapturingShellExecutor(this.result, {this.outputUpdates = const []});

  final CommandResult result;
  final List<CommandOutputUpdate> outputUpdates;

  @override
  String get runtimeId => 'capturing';

  @override
  Future<void> cancel(String commandId) async {}

  @override
  Future<CommandResult> run({
    required String command,
    required String workingDirectory,
    required Duration timeout,
    CancellationToken? cancellationToken,
    CommandOutputCallback? onOutput,
  }) async {
    for (final update in outputUpdates) {
      await onOutput?.call(update);
    }
    return result;
  }

  @override
  Future<RuntimeStatus> status() async =>
      const RuntimeStatus(state: RuntimeState.ready, message: 'ready');
}

class CancellableShellExecutor implements ShellExecutor {
  final started = Completer<void>();
  var cancelObserved = false;

  @override
  String get runtimeId => 'cancellable';

  @override
  Future<void> cancel(String commandId) async {
    cancelObserved = true;
  }

  @override
  Future<CommandResult> run({
    required String command,
    required String workingDirectory,
    required Duration timeout,
    CancellationToken? cancellationToken,
    CommandOutputCallback? onOutput,
  }) async {
    started.complete();
    await onOutput?.call(
      const CommandOutputUpdate(
        stream: 'stdout',
        text: 'running',
        stdout: 'running',
      ),
    );
    await cancellationToken!.whenCancelled;
    cancelObserved = true;
    return const CommandResult(
      stdout: 'running',
      stderr: 'Command cancelled by user.',
      exitCode: -1,
      duration: Duration(milliseconds: 1),
      failureKind: 'cancelled',
      timedOut: false,
      cancelled: true,
    );
  }

  @override
  Future<RuntimeStatus> status() async =>
      const RuntimeStatus(state: RuntimeState.ready, message: 'ready');
}
