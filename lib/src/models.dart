import 'dart:convert';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

DateTime _dt(Object? value) {
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.parse(value);
  return DateTime.fromMillisecondsSinceEpoch(0);
}

int _ms(DateTime value) => value.millisecondsSinceEpoch;

T enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString();
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

const int maxPersistedTextCharacters = 64000;
const int maxPersistedRawJsonCharacters = 256000;
const int maxLoadedChatTextCharacters = maxPersistedTextCharacters;
const int maxToolCardJsonPreviewCharacters = 12000;
const String persistenceTruncationNotice =
    '[stored output truncated to keep chat responsive]';

String? encodeJson(Object? value) {
  if (value == null) return null;
  final encoded = jsonEncode(sanitizeJsonForPersistence(value));
  if (encoded.length <= maxPersistedRawJsonCharacters) return encoded;
  return jsonEncode({
    'recovered': true,
    'originalLength': encoded.length,
    'jsonPreview': truncatePersistedText(encoded),
  });
}

Object? decodeJson(String? value) => value == null ? null : jsonDecode(value);

String truncatePersistedText(
  String value, {
  int maxLength = maxPersistedTextCharacters,
}) {
  if (value.length <= maxLength) return value;
  final marker =
      '\n\n[$persistenceTruncationNotice; original ${value.length} characters]\n\n';
  final available = maxLength - marker.length;
  if (available <= 0) return _safePrefix(value, maxLength);
  final headLength = (available * 0.7).floor();
  final tailLength = available - headLength;
  return '${_safePrefix(value, headLength)}$marker${_safeSuffix(value, tailLength)}';
}

Object? sanitizeJsonForPersistence(Object? value) {
  if (value is String) return truncatePersistedText(value);
  if (value is List) {
    return value.map(sanitizeJsonForPersistence).toList(growable: false);
  }
  if (value is Map) {
    final sanitized = <String, Object?>{};
    value.forEach((key, child) {
      final name = key.toString();
      sanitized[name] = sanitizeJsonForPersistence(child);
      if (child is String && child.length > maxPersistedTextCharacters) {
        sanitized.putIfAbsent('${name}Truncated', () => true);
        sanitized.putIfAbsent('${name}OriginalLength', () => child.length);
      }
    });
    return sanitized;
  }
  return value;
}

String? recoverPersistedJsonText(String? raw, {required String fallbackKey}) {
  if (raw == null || raw.isEmpty) return raw;
  if (raw.length > maxPersistedRawJsonCharacters) {
    return encodeJson({
      'recovered': true,
      'originalLength': raw.length,
      fallbackKey: truncatePersistedText(raw),
    });
  }
  try {
    final encoded = jsonEncode(sanitizeJsonForPersistence(jsonDecode(raw)));
    if (encoded.length <= maxPersistedRawJsonCharacters) return encoded;
  } catch (_) {}
  return encodeJson({
    'recovered': true,
    'originalLength': raw.length,
    fallbackKey: truncatePersistedText(raw),
  });
}

String _safePrefix(String value, int length) {
  var end = length.clamp(0, value.length).toInt();
  if (end > 0) {
    final last = value.codeUnitAt(end - 1);
    if (last >= 0xd800 && last <= 0xdbff) end--;
  }
  return value.substring(0, end);
}

String _safeSuffix(String value, int length) {
  var start = (value.length - length).clamp(0, value.length).toInt();
  if (start < value.length) {
    final first = value.codeUnitAt(start);
    if (first >= 0xdc00 && first <= 0xdfff) start++;
  }
  return value.substring(start);
}

enum ChatStatus { idle, running, completed, interrupted, error }

enum MessageRole { system, user, assistant, tool, internal }

enum ToolExecutionStatus { running, success, error, cancelled }

enum AgentJobState { idle, running, completed, interrupted, error }

enum RuntimeState {
  unavailable,
  configurationRequired,
  notInstalled,
  downloading,
  verifying,
  extracting,
  initializing,
  testing,
  ready,
  commandRunning,
  commandFailed,
  error,
}

enum ShellRuntimeId {
  termux,
  archLinux;

  String get label => switch (this) {
    ShellRuntimeId.termux => 'Termux Runtime',
    ShellRuntimeId.archLinux => 'ARCH Linux Runtime',
  };
}

enum AttachmentKind { text, image, binary }

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.folderPath,
    required this.mountName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Project.create({
    required String name,
    required String folderPath,
    String? mountName,
  }) {
    final now = DateTime.now();
    return Project(
      id: newId(),
      name: name,
      folderPath: folderPath,
      mountName: mountName ?? ProjectMountNames.fromName(name),
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Project.fromMap(Map<String, Object?> map) => Project(
    id: map['id']! as String,
    name: map['name']! as String,
    folderPath: map['folder_path']! as String,
    mountName:
        map['mount_name']?.toString() ??
        ProjectMountNames.fromName(map['name']! as String),
    createdAt: _dt(map['created_at']),
    updatedAt: _dt(map['updated_at']),
  );

  final String id;
  final String name;
  final String folderPath;
  final String mountName;
  final DateTime createdAt;
  final DateTime updatedAt;

  Project copyWith({
    String? name,
    String? folderPath,
    String? mountName,
    DateTime? updatedAt,
  }) => Project(
    id: id,
    name: name ?? this.name,
    folderPath: folderPath ?? this.folderPath,
    mountName: mountName ?? this.mountName,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'folder_path': folderPath,
    'mount_name': mountName,
    'created_at': _ms(createdAt),
    'updated_at': _ms(updatedAt),
  };
}

class ProjectMountNames {
  static String fromName(String name) {
    final lower = name.toLowerCase();
    final normalized = lower
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'project' : normalized;
  }

  static String unique(String name, Iterable<String> existing) {
    final base = fromName(name);
    final used = existing.toSet();
    if (!used.contains(base)) return base;
    var index = 2;
    while (used.contains('$base-$index')) {
      index++;
    }
    return '$base-$index';
  }
}

class ProjectSummary {
  const ProjectSummary({
    required this.project,
    required this.chatCount,
    required this.runningCount,
    required this.errorCount,
  });

  final Project project;
  final int chatCount;
  final int runningCount;
  final int errorCount;
}

class Chat {
  static const Object _unset = Object();

  const Chat({
    required this.id,
    required this.projectId,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.providerId,
    this.modelId,
    this.error,
  });

  factory Chat.create({
    required String projectId,
    required String title,
    String? providerId,
    String? modelId,
  }) {
    final now = DateTime.now();
    return Chat(
      id: newId(),
      projectId: projectId,
      title: title,
      status: ChatStatus.idle,
      createdAt: now,
      updatedAt: now,
      providerId: providerId,
      modelId: modelId,
    );
  }

  factory Chat.fromMap(Map<String, Object?> map) => Chat(
    id: map['id']! as String,
    projectId: map['project_id']! as String,
    title: truncatePersistedText(map['title']! as String),
    status: enumByName(ChatStatus.values, map['status'], ChatStatus.idle),
    createdAt: _dt(map['created_at']),
    updatedAt: _dt(map['updated_at']),
    providerId: map['provider_id'] as String?,
    modelId: map['model_id'] as String?,
    error: map['error'] == null
        ? null
        : truncatePersistedText(map['error']!.toString()),
  );

  final String id;
  final String projectId;
  final String title;
  final ChatStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? providerId;
  final String? modelId;
  final String? error;

  Chat copyWith({
    String? title,
    ChatStatus? status,
    DateTime? updatedAt,
    String? providerId,
    String? modelId,
    Object? error = _unset,
  }) => Chat(
    id: id,
    projectId: projectId,
    title: title ?? this.title,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    providerId: providerId ?? this.providerId,
    modelId: modelId ?? this.modelId,
    error: identical(error, _unset) ? this.error : error as String?,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'project_id': projectId,
    'title': truncatePersistedText(title),
    'status': status.name,
    'created_at': _ms(createdAt),
    'updated_at': _ms(updatedAt),
    'provider_id': providerId,
    'model_id': modelId,
    'error': error == null ? null : truncatePersistedText(error!),
  };
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.toolCallId,
    this.metadataJson,
  });

  factory ChatMessage.create({
    required String chatId,
    required MessageRole role,
    required String content,
    String? toolCallId,
    Object? metadata,
  }) => ChatMessage(
    id: newId(),
    chatId: chatId,
    role: role,
    content: truncatePersistedText(content),
    createdAt: DateTime.now(),
    toolCallId: toolCallId,
    metadataJson: encodeJson(metadata),
  );

  factory ChatMessage.fromMap(Map<String, Object?> map) => ChatMessage(
    id: map['id']! as String,
    chatId: map['chat_id']! as String,
    role: enumByName(MessageRole.values, map['role'], MessageRole.internal),
    content: truncatePersistedText(map['content'] as String? ?? ''),
    createdAt: _dt(map['created_at']),
    toolCallId: map['tool_call_id'] as String?,
    metadataJson: recoverPersistedJsonText(
      map['metadata_json'] as String?,
      fallbackKey: 'metadata',
    ),
  );

  final String id;
  final String chatId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;
  final String? toolCallId;
  final String? metadataJson;

  ChatMessage copyWith({
    String? content,
    String? metadataJson,
    String? toolCallId,
  }) => ChatMessage(
    id: id,
    chatId: chatId,
    role: role,
    content: truncatePersistedText(content ?? this.content),
    createdAt: createdAt,
    toolCallId: toolCallId ?? this.toolCallId,
    metadataJson: recoverPersistedJsonText(
      metadataJson ?? this.metadataJson,
      fallbackKey: 'metadata',
    ),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'chat_id': chatId,
    'role': role.name,
    'content': truncatePersistedText(content),
    'created_at': _ms(createdAt),
    'tool_call_id': toolCallId,
    'metadata_json': recoverPersistedJsonText(
      metadataJson,
      fallbackKey: 'metadata',
    ),
  };
}

class ToolExecution {
  const ToolExecution({
    required this.id,
    required this.chatId,
    required this.name,
    required this.argumentsJson,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    this.resultJson,
    this.error,
  });

  factory ToolExecution.start({
    required String chatId,
    required String name,
    required Object? arguments,
  }) => ToolExecution(
    id: newId(),
    chatId: chatId,
    name: name,
    argumentsJson: encodeJson(arguments) ?? '{}',
    status: ToolExecutionStatus.running,
    startedAt: DateTime.now(),
  );

  factory ToolExecution.fromMap(Map<String, Object?> map) => ToolExecution(
    id: map['id']! as String,
    chatId: map['chat_id']! as String,
    name: map['name']! as String,
    argumentsJson:
        recoverPersistedJsonText(
          map['arguments_json'] as String?,
          fallbackKey: 'arguments',
        ) ??
        '{}',
    status: enumByName(
      ToolExecutionStatus.values,
      map['status'],
      ToolExecutionStatus.error,
    ),
    startedAt: _dt(map['started_at']),
    finishedAt: map['finished_at'] == null ? null : _dt(map['finished_at']),
    resultJson: recoverPersistedJsonText(
      map['result_json'] as String?,
      fallbackKey: 'result',
    ),
    error: map['error'] == null
        ? null
        : truncatePersistedText(map['error'].toString()),
  );

  final String id;
  final String chatId;
  final String name;
  final String argumentsJson;
  final ToolExecutionStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? resultJson;
  final String? error;

  ToolExecution finish({
    required ToolExecutionStatus status,
    Object? result,
    String? error,
  }) => ToolExecution(
    id: id,
    chatId: chatId,
    name: name,
    argumentsJson: argumentsJson,
    status: status,
    startedAt: startedAt,
    finishedAt: DateTime.now(),
    resultJson: encodeJson(result),
    error: error == null ? null : truncatePersistedText(error),
  );

  ToolExecution runningResult(Object? result) => ToolExecution(
    id: id,
    chatId: chatId,
    name: name,
    argumentsJson: argumentsJson,
    status: ToolExecutionStatus.running,
    startedAt: startedAt,
    resultJson: encodeJson(result),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'chat_id': chatId,
    'name': name,
    'arguments_json':
        recoverPersistedJsonText(argumentsJson, fallbackKey: 'arguments') ??
        '{}',
    'status': status.name,
    'started_at': _ms(startedAt),
    'finished_at': finishedAt == null ? null : _ms(finishedAt!),
    'result_json': recoverPersistedJsonText(resultJson, fallbackKey: 'result'),
    'error': error == null ? null : truncatePersistedText(error!),
  };
}

class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.providerKey,
    required this.authType,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProviderConfig.create({
    required String name,
    required String baseUrl,
    String providerKey = 'custom-openai-compatible',
    String authType = 'apiKey',
  }) {
    final now = DateTime.now();
    return ProviderConfig(
      id: newId(),
      name: name,
      baseUrl: baseUrl,
      providerKey: providerKey,
      authType: authType,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory ProviderConfig.fromMap(Map<String, Object?> map) => ProviderConfig(
    id: map['id']! as String,
    name: map['name']! as String,
    baseUrl: map['base_url']! as String,
    providerKey: map['provider_key'] as String? ?? 'custom-openai-compatible',
    authType: map['auth_type'] as String? ?? 'apiKey',
    createdAt: _dt(map['created_at']),
    updatedAt: _dt(map['updated_at']),
  );

  final String id;
  final String name;
  final String baseUrl;
  final String providerKey;
  final String authType;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProviderConfig copyWith({
    String? name,
    String? baseUrl,
    String? providerKey,
    String? authType,
  }) => ProviderConfig(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    providerKey: providerKey ?? this.providerKey,
    authType: authType ?? this.authType,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'base_url': baseUrl,
    'provider_key': providerKey,
    'auth_type': authType,
    'created_at': _ms(createdAt),
    'updated_at': _ms(updatedAt),
  };
}

class ProviderModel {
  const ProviderModel({
    required this.id,
    required this.providerId,
    required this.model,
    required this.createdAt,
  });

  factory ProviderModel.create({
    required String providerId,
    required String model,
  }) => ProviderModel(
    id: newId(),
    providerId: providerId,
    model: model,
    createdAt: DateTime.now(),
  );

  factory ProviderModel.fromMap(Map<String, Object?> map) => ProviderModel(
    id: map['id']! as String,
    providerId: map['provider_id']! as String,
    model: map['model']! as String,
    createdAt: _dt(map['created_at']),
  );

  final String id;
  final String providerId;
  final String model;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'provider_id': providerId,
    'model': model,
    'created_at': _ms(createdAt),
  };
}

class Attachment {
  const Attachment({
    required this.id,
    required this.messageId,
    required this.path,
    required this.kind,
    required this.name,
    required this.createdAt,
    this.mimeType,
  });

  factory Attachment.create({
    required String messageId,
    required String path,
    required AttachmentKind kind,
    required String name,
    String? mimeType,
  }) => Attachment(
    id: newId(),
    messageId: messageId,
    path: path,
    kind: kind,
    name: name,
    mimeType: mimeType,
    createdAt: DateTime.now(),
  );

  factory Attachment.fromMap(Map<String, Object?> map) => Attachment(
    id: map['id']! as String,
    messageId: map['message_id']! as String,
    path: map['path']! as String,
    kind: enumByName(AttachmentKind.values, map['kind'], AttachmentKind.binary),
    name: map['name']! as String,
    mimeType: map['mime_type'] as String?,
    createdAt: _dt(map['created_at']),
  );

  final String id;
  final String messageId;
  final String path;
  final AttachmentKind kind;
  final String name;
  final String? mimeType;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'message_id': messageId,
    'path': path,
    'kind': kind.name,
    'name': name,
    'mime_type': mimeType,
    'created_at': _ms(createdAt),
  };
}

class AgentJob {
  const AgentJob({
    required this.id,
    required this.projectId,
    required this.chatId,
    required this.state,
    required this.startedAt,
    this.currentAction,
    this.completedAt,
    this.error,
  });

  factory AgentJob.start({required String projectId, required String chatId}) =>
      AgentJob(
        id: newId(),
        projectId: projectId,
        chatId: chatId,
        state: AgentJobState.running,
        startedAt: DateTime.now(),
        currentAction: 'Thinking',
      );

  factory AgentJob.fromMap(Map<String, Object?> map) => AgentJob(
    id: map['id']! as String,
    projectId: map['project_id']! as String,
    chatId: map['chat_id']! as String,
    state: enumByName(AgentJobState.values, map['state'], AgentJobState.error),
    currentAction: map['current_action'] as String?,
    startedAt: _dt(map['started_at']),
    completedAt: map['completed_at'] == null ? null : _dt(map['completed_at']),
    error: map['error'] as String?,
  );

  final String id;
  final String projectId;
  final String chatId;
  final AgentJobState state;
  final String? currentAction;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? error;

  AgentJob update({
    AgentJobState? state,
    String? currentAction,
    String? error,
    bool complete = false,
  }) => AgentJob(
    id: id,
    projectId: projectId,
    chatId: chatId,
    state: state ?? this.state,
    currentAction: currentAction ?? this.currentAction,
    startedAt: startedAt,
    completedAt: complete ? DateTime.now() : completedAt,
    error: error,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'project_id': projectId,
    'chat_id': chatId,
    'state': state.name,
    'current_action': currentAction,
    'started_at': _ms(startedAt),
    'completed_at': completedAt == null ? null : _ms(completedAt!),
    'error': error,
  };
}

class RuntimeStatus {
  const RuntimeStatus({
    required this.state,
    required this.message,
    this.details,
  });

  factory RuntimeStatus.fromMap(Map<Object?, Object?> map) => RuntimeStatus(
    state: enumByName(
      RuntimeState.values,
      map['state'],
      RuntimeState.unavailable,
    ),
    message: map['message']?.toString() ?? '',
    details: map['details']?.toString(),
  );

  final RuntimeState state;
  final String message;
  final String? details;

  Map<String, Object?> toMap() => {
    'state': state.name,
    'message': message,
    'details': details,
  };
}

class ShellRuntimeSettings {
  const ShellRuntimeSettings({this.selected = ShellRuntimeId.termux});

  factory ShellRuntimeSettings.fromMap(Map<String, Object?> map) {
    final selectedName = map['selected']?.toString();
    final legacyRuntimeId = String.fromCharCodes([
      100,
      114,
      97,
      120,
      111,
      110,
      76,
      111,
      99,
      97,
      108,
    ]);
    final normalizedSelected = selectedName == legacyRuntimeId
        ? ShellRuntimeId.archLinux.name
        : selectedName;
    return ShellRuntimeSettings(
      selected: enumByName(
        ShellRuntimeId.values,
        normalizedSelected,
        ShellRuntimeId.termux,
      ),
    );
  }

  final ShellRuntimeId selected;

  Map<String, Object?> toMap() => {'selected': selected.name};
}

class AgentLimits {
  const AgentLimits({
    this.maxIterations = 12,
    this.commandTimeoutSeconds = 120,
    this.maxContextCharacters = 64000,
  });

  factory AgentLimits.fromMap(Map<String, Object?> map) => AgentLimits(
    maxIterations: map['max_iterations'] as int? ?? 12,
    commandTimeoutSeconds: map['command_timeout_seconds'] as int? ?? 120,
    maxContextCharacters: map['max_context_characters'] as int? ?? 64000,
  );

  final int maxIterations;
  final int commandTimeoutSeconds;
  final int maxContextCharacters;

  Map<String, Object?> toMap() => {
    'max_iterations': maxIterations,
    'command_timeout_seconds': commandTimeoutSeconds,
    'max_context_characters': maxContextCharacters,
  };
}

class OnboardingState {
  const OnboardingState({this.completed = false, this.step = 0});

  factory OnboardingState.fromMap(Map<String, Object?> map) => OnboardingState(
    completed: map['completed'] as bool? ?? false,
    step: map['step'] as int? ?? 0,
  );

  final bool completed;
  final int step;

  OnboardingState copyWith({bool? completed, int? step}) => OnboardingState(
    completed: completed ?? this.completed,
    step: step ?? this.step,
  );

  Map<String, Object?> toMap() => {'completed': completed, 'step': step};
}
