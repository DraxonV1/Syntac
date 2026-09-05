import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../ai/auth/credential_store.dart';
import '../ai/oauth/oauth_credential.dart';
import '../ai/registry/provider_registry.dart';
import '../models.dart';
import '../security/secret_store.dart';
import 'chat_jsonl_store.dart';
import 'local_database.dart';

class AppRepository implements CredentialStore {
  AppRepository({
    required LocalDatabase localDatabase,
    required SecretStore secretStore,
    Directory? chatStorageDirectory,
  }) : _db = localDatabase.database,
       _localDatabasePath = localDatabase.path,
       _chatStore = ChatJsonlStore(
         chatStorageDirectory ??
             Directory(
               p.join(File(localDatabase.path).parent.path, 'chats_jsonl'),
             ),
       ),
       _secretStore = secretStore;

  final Database _db;
  final String _localDatabasePath;
  final ChatJsonlStore _chatStore;
  final SecretStore _secretStore;
  Future<void>? _chatMigration;

  String get localDatabasePath => _localDatabasePath;

  String _providerSecretKey(String providerId) =>
      'provider_api_key_$providerId';
  String _providerOAuthSecretKey(String providerId) =>
      'provider_oauth_$providerId';

  Future<void> _ensureChatsMigrated() =>
      _chatMigration ??= _chatStore.migrateFromSqlite(_db);

  Future<void> reconcileStaleRunningJobs() async {
    await _ensureChatsMigrated();
    await _chatStore.reconcileStaleRunningJobs();
  }

  Future<List<Project>> listProjects() async {
    final rows = await _db.query('projects', orderBy: 'updated_at DESC');
    return rows.map(Project.fromMap).toList();
  }

  Future<List<ProjectSummary>> listProjectSummaries() async {
    await _ensureChatsMigrated();
    return _chatStore.listProjectSummaries(await listProjects());
  }

  Future<Project?> getProject(String id) async {
    final rows = await _db.query(
      'projects',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Project.fromMap(rows.first);
  }

  Future<Project> createProject({
    required String name,
    required String folderPath,
  }) async {
    final cleanName = name.trim();
    final cleanPath = folderPath.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Project name is required');
    }
    if (cleanPath.isEmpty) {
      throw ArgumentError.value(
        folderPath,
        'folderPath',
        'Project folder path is required',
      );
    }
    final existing = await _db.query('projects', columns: ['mount_name']);
    final mountName = ProjectMountNames.unique(
      cleanName,
      existing.map((row) => row['mount_name']?.toString()).whereType<String>(),
    );
    final project = Project.create(
      name: cleanName,
      folderPath: cleanPath,
      mountName: mountName,
    );
    await _db.insert('projects', project.toMap());
    return project;
  }

  Future<void> updateProject(Project project) async {
    await _db.update(
      'projects',
      project.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  Future<void> removeProjectFromApp(String projectId) async {
    await _ensureChatsMigrated();
    await _chatStore.deleteProjectChats(projectId);
    await _db.delete('projects', where: 'id = ?', whereArgs: [projectId]);
  }

  Future<List<Chat>> listChats(String projectId) async {
    await _ensureChatsMigrated();
    return _chatStore.listChats(projectId);
  }

  Future<Chat?> getChat(String chatId) async {
    await _ensureChatsMigrated();
    return _chatStore.getChat(chatId);
  }

  Future<Chat> createChat({
    required String projectId,
    required String title,
    String? providerId,
    String? modelId,
  }) async {
    await _ensureChatsMigrated();
    final chat = Chat.create(
      projectId: projectId,
      title: title.trim().isEmpty ? 'New chat' : title.trim(),
      providerId: providerId,
      modelId: modelId,
    );
    await _chatStore.addChat(chat);
    await _touchProject(projectId);
    return chat;
  }

  Future<void> updateChat(Chat chat) async {
    await _ensureChatsMigrated();
    await _chatStore.updateChat(chat.copyWith(updatedAt: DateTime.now()));
    await _touchProject(chat.projectId);
  }

  Future<void> deleteChat(String chatId) async {
    await _ensureChatsMigrated();
    final chat = await getChat(chatId);
    await _chatStore.deleteChat(chatId);
    if (chat != null) {
      await _touchProject(chat.projectId);
    }
  }

  Future<void> setChatStatus(
    String chatId,
    ChatStatus status, {
    String? error,
  }) async {
    final chat = await getChat(chatId);
    if (chat == null) return;
    await updateChat(chat.copyWith(status: status, error: error));
  }

  Future<List<ChatMessage>> listMessages(String chatId) async {
    await _ensureChatsMigrated();
    return _chatStore.listMessages(chatId);
  }

  Future<ChatMessage> addMessage(ChatMessage message) async {
    await _ensureChatsMigrated();
    final stored = await _chatStore.addMessage(message);
    final chat = await getChat(message.chatId);
    if (chat != null) {
      await updateChat(chat.copyWith(updatedAt: DateTime.now()));
    }
    return stored;
  }

  Future<void> updateMessage(ChatMessage message) async {
    await _ensureChatsMigrated();
    await _chatStore.updateMessage(message);
    final chat = await getChat(message.chatId);
    if (chat != null) {
      await updateChat(chat.copyWith(updatedAt: DateTime.now()));
    }
  }

  Future<List<Attachment>> listAttachments(String messageId) async {
    await _ensureChatsMigrated();
    return _chatStore.listAttachments(messageId);
  }

  Future<Attachment> addAttachment(Attachment attachment) async {
    await _ensureChatsMigrated();
    return _chatStore.addAttachment(attachment);
  }

  Future<ToolExecution> addToolExecution(ToolExecution execution) async {
    await _ensureChatsMigrated();
    return _chatStore.addToolExecution(execution);
  }

  Future<void> updateToolExecution(ToolExecution execution) async {
    await _ensureChatsMigrated();
    await _chatStore.updateToolExecution(execution);
  }

  Future<List<ToolExecution>> listToolExecutions(String chatId) async {
    await _ensureChatsMigrated();
    return _chatStore.listToolExecutions(chatId);
  }

  Future<AgentJob> addAgentJob(AgentJob job) async {
    await _ensureChatsMigrated();
    return _chatStore.addAgentJob(job);
  }

  Future<void> updateAgentJob(AgentJob job) async {
    await _ensureChatsMigrated();
    await _chatStore.updateAgentJob(job);
  }

  Future<List<AgentJob>> listAgentJobs(String chatId) async {
    await _ensureChatsMigrated();
    return _chatStore.listAgentJobs(chatId);
  }

  Future<bool> hasRunningJobForChat(String chatId) async {
    await _ensureChatsMigrated();
    return _chatStore.hasRunningJobForChat(chatId);
  }

  Future<List<ProviderConfig>> listProviders() async {
    final rows = await _db.query('providers', orderBy: 'updated_at DESC');
    return rows.map(ProviderConfig.fromMap).toList();
  }

  Future<ProviderConfig?> getProvider(String providerId) async {
    final rows = await _db.query(
      'providers',
      where: 'id = ?',
      whereArgs: [providerId],
      limit: 1,
    );
    return rows.isEmpty ? null : ProviderConfig.fromMap(rows.first);
  }

  Future<ProviderConfig> saveProvider({
    String? id,
    required String name,
    required String baseUrl,
    required String apiKey,
    String providerKey = 'custom-openai-compatible',
    String authType = 'apiKey',
    required List<String> models,
  }) async {
    final cleanModels = models
        .map((model) => model.trim())
        .where((model) => model.isNotEmpty)
        .toSet()
        .toList();
    final provider = id == null
        ? ProviderConfig.create(
            name: name.trim(),
            baseUrl: baseUrl.trim(),
            providerKey: providerKey,
            authType: authType,
          )
        : (await getProvider(id))!.copyWith(
            name: name.trim(),
            baseUrl: baseUrl.trim(),
            providerKey: providerKey,
            authType: authType,
          );
    await _db.transaction((txn) async {
      if (id == null) {
        await txn.insert('providers', provider.toMap());
      } else {
        await txn.update(
          'providers',
          provider.toMap(),
          where: 'id = ?',
          whereArgs: [provider.id],
        );
        await txn.delete(
          'models',
          where: 'provider_id = ?',
          whereArgs: [provider.id],
        );
      }
      for (final model in cleanModels) {
        await txn.insert(
          'models',
          ProviderModel.create(providerId: provider.id, model: model).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
    if (apiKey.isNotEmpty) {
      await _secretStore.write(_providerSecretKey(provider.id), apiKey);
    }
    return provider;
  }

  Future<void> deleteProvider(String providerId) async {
    await _db.delete('providers', where: 'id = ?', whereArgs: [providerId]);
    await deleteProviderCredentials(providerId);
  }

  Future<List<ProviderModel>> listProviderModels(String providerId) async {
    final rows = await _db.query(
      'models',
      where: 'provider_id = ?',
      whereArgs: [providerId],
      orderBy: 'model ASC',
    );
    return rows.map(ProviderModel.fromMap).toList();
  }

  @override
  Future<String?> readApiKey(String providerId) =>
      _secretStore.read(_providerSecretKey(providerId));

  Future<String?> readProviderApiKey(String providerId) =>
      readApiKey(providerId);

  @override
  Future<void> saveApiKey(String providerId, String apiKey) =>
      _secretStore.write(_providerSecretKey(providerId), apiKey);

  @override
  Future<void> saveOAuthCredential(
    String providerId,
    OAuthCredential credential,
  ) => _secretStore.write(
    _providerOAuthSecretKey(providerId),
    jsonEncode(credential.toJson()),
  );

  @override
  Future<OAuthCredential?> readOAuthCredential(String providerId) async {
    final raw = await _secretStore.read(_providerOAuthSecretKey(providerId));
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Stored OAuth credential is malformed');
    }
    return OAuthCredential.fromJson(decoded.cast<String, Object?>());
  }

  @override
  Future<void> deleteProviderCredentials(String providerId) async {
    await _secretStore.delete(_providerSecretKey(providerId));
    await _secretStore.delete(_providerOAuthSecretKey(providerId));
  }

  @override
  Future<ProviderCredential?> resolveProviderCredential(
    ProviderConfig provider,
  ) async {
    return switch (authTypeForProvider(provider)) {
      ProviderAuthType.apiKey => switch (await readApiKey(provider.id)) {
        final key? when key.isNotEmpty => ApiKeyProviderCredential(key),
        _ => null,
      },
      ProviderAuthType.googleAntigravityOAuth ||
      ProviderAuthType.openAICodexOAuth ||
      ProviderAuthType.xaiOAuth => switch (await readOAuthCredential(
        provider.id,
      )) {
        final credential? => OAuthProviderCredential(credential),
        _ => null,
      },
    };
  }

  Future<AgentLimits> readAgentLimits() async {
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['agent_limits'],
      limit: 1,
    );
    if (rows.isEmpty) return const AgentLimits();
    return AgentLimits.fromMap(
      jsonDecode(rows.first['value_json']! as String) as Map<String, Object?>,
    );
  }

  Future<void> saveAgentLimits(AgentLimits limits) async {
    await _db.insert('settings', {
      'key': 'agent_limits',
      'value_json': jsonEncode(limits.toMap()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<ShellRuntimeSettings> readShellRuntimeSettings() async {
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['shell_runtime'],
      limit: 1,
    );
    if (rows.isEmpty) return const ShellRuntimeSettings();
    return ShellRuntimeSettings.fromMap(
      jsonDecode(rows.first['value_json']! as String) as Map<String, Object?>,
    );
  }

  Future<void> saveShellRuntimeSettings(ShellRuntimeSettings settings) async {
    await _db.insert('settings', {
      'key': 'shell_runtime',
      'value_json': jsonEncode(settings.toMap()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<OnboardingState> readOnboardingState() async {
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['onboarding_state'],
      limit: 1,
    );
    if (rows.isEmpty) return const OnboardingState();
    return OnboardingState.fromMap(
      jsonDecode(rows.first['value_json']! as String) as Map<String, Object?>,
    );
  }

  Future<void> saveOnboardingState(OnboardingState state) async {
    await _db.insert('settings', {
      'key': 'onboarding_state',
      'value_json': jsonEncode(state.toMap()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> readGlobalSystemPrompt() async {
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['global_system_prompt'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.first['value_json']! as String);
    return decoded is Map ? decoded['prompt'] as String? : decoded?.toString();
  }

  Future<void> saveGlobalSystemPrompt(String prompt) async {
    await _db.insert('settings', {
      'key': 'global_system_prompt',
      'value_json': jsonEncode({'prompt': prompt}),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>?> readDefaultModelSelection() async {
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['default_model_selection'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.first['value_json']! as String);
    if (decoded is! Map) return null;
    final providerId = decoded['providerId'];
    final model = decoded['model'];
    if (providerId is! String || model is! String) return null;
    return {'providerId': providerId, 'model': model};
  }

  Future<void> saveDefaultModelSelection({
    required String providerId,
    required String model,
  }) async {
    await _db.insert('settings', {
      'key': 'default_model_selection',
      'value_json': jsonEncode({'providerId': providerId, 'model': model}),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _touchProject(String projectId) async {
    await _db.update(
      'projects',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }
}
