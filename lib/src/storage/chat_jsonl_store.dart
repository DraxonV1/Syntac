import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';

class ChatJsonlStore {
  ChatJsonlStore(this.rootDirectory);

  final Directory rootDirectory;
  final _writeLocks = <String, Future<void>>{};
  bool _ready = false;

  File get _chatsFile => File(p.join(rootDirectory.path, 'chats.jsonl'));
  File get _attachmentsFile =>
      File(p.join(rootDirectory.path, 'attachments.jsonl'));
  File get _migrationMarker =>
      File(p.join(rootDirectory.path, 'sqlite-chat-migration-v1.done'));

  Future<void> ensureReady() async {
    if (_ready) return;
    await rootDirectory.create(recursive: true);
    await _recoverInterruptedWrites();
    _ready = true;
  }

  Future<T> _withFileLock<T>(File file, Future<T> Function() action) async {
    final key = file.absolute.path;
    final previous = _writeLocks[key] ?? Future<void>.value();
    final current = Completer<void>();
    _writeLocks[key] = current.future;
    try {
      await previous.catchError((_) {});
      return await action();
    } finally {
      current.complete();
      if (identical(_writeLocks[key], current.future)) {
        _writeLocks.remove(key);
      }
    }
  }

  Future<void> migrateFromSqlite(Database db) async {
    await ensureReady();
    if (await _migrationMarker.exists()) return;

    final rows = await db.query('chats', orderBy: 'created_at ASC');
    if (rows.isEmpty) {
      await _migrationMarker.writeAsString(DateTime.now().toIso8601String());
      return;
    }

    final existing = {for (final chat in await listAllChats()) chat.id: chat};
    final attachments = {
      for (final item in await listAllAttachments()) item.id: item,
    };

    for (final row in rows) {
      final chat = Chat.fromMap(row);
      existing.putIfAbsent(chat.id, () => chat);
      await _writeMessages(chat.id, await _loadSqliteMessages(db, chat.id));
      await _writeToolExecutions(
        chat.id,
        await _loadSqliteToolExecutions(db, chat.id),
      );
      await _writeAgentJobs(chat.id, await _loadSqliteAgentJobs(db, chat.id));
      for (final attachment in await _loadSqliteAttachments(db, chat.id)) {
        attachments[attachment.id] = attachment;
      }
    }

    await _writeChats(existing.values.toList());
    await _writeAttachments(attachments.values.toList());
    await _migrationMarker.writeAsString(DateTime.now().toIso8601String());
  }

  Future<List<ProjectSummary>> listProjectSummaries(
    Iterable<Project> projects,
  ) async {
    final chats = await listAllChats();
    return projects
        .map((project) {
          final projectChats = chats
              .where((chat) => chat.projectId == project.id)
              .toList(growable: false);
          return ProjectSummary(
            project: project,
            chatCount: projectChats.length,
            runningCount: projectChats
                .where((chat) => chat.status == ChatStatus.running)
                .length,
            errorCount: projectChats
                .where((chat) => chat.status == ChatStatus.error)
                .length,
          );
        })
        .toList(growable: false);
  }

  Future<List<Chat>> listAllChats() async {
    await ensureReady();
    final chats = await _readJsonl(_chatsFile, Chat.fromMap);
    chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return chats;
  }

  Future<List<Chat>> listChats(String projectId) async {
    final chats = await listAllChats();
    return chats
        .where((chat) => chat.projectId == projectId)
        .toList(growable: false);
  }

  Future<Chat?> getChat(String chatId) async {
    for (final chat in await listAllChats()) {
      if (chat.id == chatId) return chat;
    }
    return null;
  }

  Future<Chat> addChat(Chat chat) async {
    return _withFileLock(_chatsFile, () async {
      final chats = await _readJsonl(_chatsFile, Chat.fromMap);
      chats.removeWhere((item) => item.id == chat.id);
      chats.add(chat);
      chats.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _writeJsonlUnlocked(_chatsFile, chats.map((chat) => chat.toMap()));
      return chat;
    });
  }

  Future<void> updateChat(Chat chat) async {
    await _withFileLock(_chatsFile, () async {
      final chats = await _readJsonl(_chatsFile, Chat.fromMap);
      final index = chats.indexWhere((item) => item.id == chat.id);
      if (index == -1) return;
      chats[index] = chat;
      chats.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _writeJsonlUnlocked(_chatsFile, chats.map((chat) => chat.toMap()));
    });
  }

  Future<void> deleteChat(String chatId) async {
    final messages = await listMessages(chatId);
    final messageIds = messages.map((message) => message.id).toSet();
    final chats = await listAllChats();
    chats.removeWhere((chat) => chat.id == chatId);
    await _writeChats(chats);
    await _writeAttachments(
      (await listAllAttachments())
          .where((attachment) => !messageIds.contains(attachment.messageId))
          .toList(growable: false),
    );
    final dir = _chatDirectory(chatId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> deleteProjectChats(String projectId) async {
    final chats = await listAllChats();
    final removed = chats
        .where((chat) => chat.projectId == projectId)
        .map((chat) => chat.id)
        .toSet();
    if (removed.isEmpty) return;
    final removedMessageIds = <String>{};
    for (final chatId in removed) {
      removedMessageIds.addAll(
        (await listMessages(chatId)).map((message) => message.id),
      );
    }
    await _writeChats(
      chats.where((chat) => !removed.contains(chat.id)).toList(growable: false),
    );
    await _writeAttachments(
      (await listAllAttachments())
          .where(
            (attachment) => !removedMessageIds.contains(attachment.messageId),
          )
          .toList(growable: false),
    );
    for (final chatId in removed) {
      final dir = _chatDirectory(chatId);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  Future<void> reconcileStaleRunningJobs() async {
    final now = DateTime.now();
    final chats = await listAllChats();
    var changed = false;
    for (var i = 0; i < chats.length; i++) {
      if (chats[i].status == ChatStatus.running) {
        chats[i] = chats[i].copyWith(
          status: ChatStatus.interrupted,
          updatedAt: now,
          error: 'App restarted while agent was running',
        );
        changed = true;
      }
    }
    if (changed) await _writeChats(chats);

    for (final chat in chats) {
      final jobs = await listAgentJobs(chat.id);
      var jobsChanged = false;
      for (var i = 0; i < jobs.length; i++) {
        if (jobs[i].state == AgentJobState.running) {
          jobs[i] = jobs[i].update(
            state: AgentJobState.interrupted,
            error: 'App restarted while job was running',
            complete: true,
          );
          jobsChanged = true;
        }
      }
      if (jobsChanged) await _writeAgentJobs(chat.id, jobs);
    }
  }

  Future<List<ChatMessage>> listMessages(String chatId) async {
    final file = _chatFile(chatId, 'messages.jsonl');
    final messages = await _readJsonl(file, ChatMessage.fromMap);
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  Future<bool> _chatExists(String chatId) async => (await _readJsonl(
    _chatsFile,
    Chat.fromMap,
  )).any((chat) => chat.id == chatId);

  Future<ChatMessage> addMessage(ChatMessage message) async {
    final file = _chatFile(message.chatId, 'messages.jsonl');
    if (!await _chatExists(message.chatId)) {
      throw StateError('Cannot add message to deleted chat: ${message.chatId}');
    }
    return _withFileLock(file, () async {
      final messages = await _readJsonl(file, ChatMessage.fromMap);
      messages.removeWhere((item) => item.id == message.id);
      messages.add(message);
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _writeJsonlUnlocked(
        file,
        messages.map((message) => message.toMap()),
      );
      return message;
    });
  }

  Future<void> updateMessage(ChatMessage message) async {
    final file = _chatFile(message.chatId, 'messages.jsonl');
    await _withFileLock(file, () async {
      final messages = await _readJsonl(file, ChatMessage.fromMap);
      final index = messages.indexWhere((item) => item.id == message.id);
      if (index == -1) return;
      messages[index] = message;
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _writeJsonlUnlocked(
        file,
        messages.map((message) => message.toMap()),
      );
    });
  }

  Future<List<Attachment>> listAllAttachments() async {
    await ensureReady();
    return _readJsonl(_attachmentsFile, Attachment.fromMap);
  }

  Future<List<Attachment>> listAttachments(String messageId) async {
    return (await listAllAttachments())
        .where((attachment) => attachment.messageId == messageId)
        .toList(growable: false);
  }

  Future<Attachment> addAttachment(Attachment attachment) async {
    return _withFileLock(_attachmentsFile, () async {
      final attachments = await _readJsonl(
        _attachmentsFile,
        Attachment.fromMap,
      );
      attachments.removeWhere((item) => item.id == attachment.id);
      attachments.add(attachment);
      attachments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _writeJsonlUnlocked(
        _attachmentsFile,
        attachments.map((attachment) => attachment.toMap()),
      );
      return attachment;
    });
  }

  Future<ToolExecution> addToolExecution(ToolExecution execution) async {
    final file = _chatFile(execution.chatId, 'tool_executions.jsonl');
    if (!await _chatExists(execution.chatId)) {
      throw StateError(
        'Cannot add tool execution to deleted chat: ${execution.chatId}',
      );
    }
    return _withFileLock(file, () async {
      final executions = await _readJsonl(file, ToolExecution.fromMap);
      executions.removeWhere((item) => item.id == execution.id);
      executions.add(execution);
      executions.sort((a, b) => a.startedAt.compareTo(b.startedAt));
      await _writeJsonlUnlocked(
        file,
        executions.map((execution) => execution.toMap()),
      );
      return execution;
    });
  }

  Future<void> updateToolExecution(ToolExecution execution) async {
    final file = _chatFile(execution.chatId, 'tool_executions.jsonl');
    await _withFileLock(file, () async {
      final executions = await _readJsonl(file, ToolExecution.fromMap);
      final index = executions.indexWhere((item) => item.id == execution.id);
      if (index == -1) return;
      executions[index] = execution;
      executions.sort((a, b) => a.startedAt.compareTo(b.startedAt));
      await _writeJsonlUnlocked(
        file,
        executions.map((execution) => execution.toMap()),
      );
    });
  }

  Future<List<ToolExecution>> listToolExecutions(String chatId) async {
    final file = _chatFile(chatId, 'tool_executions.jsonl');
    final executions = await _readJsonl(file, ToolExecution.fromMap);
    executions.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return executions;
  }

  Future<AgentJob> addAgentJob(AgentJob job) async {
    final file = _chatFile(job.chatId, 'agent_jobs.jsonl');
    if (!await _chatExists(job.chatId)) {
      throw StateError('Cannot add agent job to deleted chat: ${job.chatId}');
    }
    return _withFileLock(file, () async {
      final jobs = await _readJsonl(file, AgentJob.fromMap);
      jobs.removeWhere((item) => item.id == job.id);
      jobs.add(job);
      jobs.sort((a, b) => a.startedAt.compareTo(b.startedAt));
      await _writeJsonlUnlocked(file, jobs.map((job) => job.toMap()));
      return job;
    });
  }

  Future<void> updateAgentJob(AgentJob job) async {
    final file = _chatFile(job.chatId, 'agent_jobs.jsonl');
    await _withFileLock(file, () async {
      final jobs = await _readJsonl(file, AgentJob.fromMap);
      final index = jobs.indexWhere((item) => item.id == job.id);
      if (index == -1) return;
      jobs[index] = job;
      jobs.sort((a, b) => a.startedAt.compareTo(b.startedAt));
      await _writeJsonlUnlocked(file, jobs.map((job) => job.toMap()));
    });
  }

  Future<List<AgentJob>> listAgentJobs(String chatId) async {
    final file = _chatFile(chatId, 'agent_jobs.jsonl');
    final jobs = await _readJsonl(file, AgentJob.fromMap);
    jobs.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return jobs;
  }

  Future<bool> hasRunningJobForChat(String chatId) async {
    return (await listAgentJobs(
      chatId,
    )).any((job) => job.state == AgentJobState.running);
  }

  Future<void> _writeChats(List<Chat> chats) async {
    chats.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    await _writeJsonl(_chatsFile, chats.map((chat) => chat.toMap()));
  }

  Future<void> _writeMessages(String chatId, List<ChatMessage> messages) async {
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    await _writeJsonl(
      _chatFile(chatId, 'messages.jsonl'),
      messages.map((message) => message.toMap()),
    );
  }

  Future<void> _writeToolExecutions(
    String chatId,
    List<ToolExecution> executions,
  ) async {
    executions.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    await _writeJsonl(
      _chatFile(chatId, 'tool_executions.jsonl'),
      executions.map((execution) => execution.toMap()),
    );
  }

  Future<void> _writeAttachments(List<Attachment> attachments) async {
    attachments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    await _writeJsonl(
      _attachmentsFile,
      attachments.map((attachment) => attachment.toMap()),
    );
  }

  Future<void> _writeAgentJobs(String chatId, List<AgentJob> jobs) async {
    jobs.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    await _writeJsonl(
      _chatFile(chatId, 'agent_jobs.jsonl'),
      jobs.map((job) => job.toMap()),
    );
  }

  Future<List<ChatMessage>> _loadSqliteMessages(
    Database db,
    String chatId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        id,
        chat_id,
        role,
        ${_loadedTextColumn('content')},
        created_at,
        tool_call_id,
        ${_loadedTextColumn('metadata_json')}
      FROM messages
      WHERE chat_id = ?
      ORDER BY created_at ASC, rowid ASC
      ''',
      [chatId],
    );
    return rows.map(ChatMessage.fromMap).toList(growable: false);
  }

  Future<List<ToolExecution>> _loadSqliteToolExecutions(
    Database db,
    String chatId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        id,
        chat_id,
        name,
        ${_loadedTextColumn('arguments_json')},
        status,
        started_at,
        finished_at,
        ${_loadedTextColumn('result_json')},
        ${_loadedTextColumn('error')}
      FROM tool_executions
      WHERE chat_id = ?
      ORDER BY started_at ASC
      ''',
      [chatId],
    );
    return rows.map(ToolExecution.fromMap).toList(growable: false);
  }

  Future<List<AgentJob>> _loadSqliteAgentJobs(
    Database db,
    String chatId,
  ) async {
    final rows = await db.query(
      'agent_jobs',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'started_at ASC',
    );
    return rows.map(AgentJob.fromMap).toList(growable: false);
  }

  Future<List<Attachment>> _loadSqliteAttachments(
    Database db,
    String chatId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT attachments.*
      FROM attachments
      INNER JOIN messages ON messages.id = attachments.message_id
      WHERE messages.chat_id = ?
      ORDER BY attachments.created_at ASC
      ''',
      [chatId],
    );
    return rows.map(Attachment.fromMap).toList(growable: false);
  }

  static String _loadedTextColumn(String column) =>
      '''
      CASE
        WHEN $column IS NULL THEN NULL
        WHEN length($column) > $maxLoadedChatTextCharacters
          THEN substr($column, 1, $maxLoadedChatTextCharacters)
            || '\n\n[$persistenceTruncationNotice; original '
            || length($column)
            || ' characters; database-projected]\n\n'
        ELSE $column
      END AS $column
      ''';

  Future<List<T>> _readJsonl<T>(
    File file,
    T Function(Map<String, Object?> map) convert,
  ) async {
    await ensureReady();
    if (!await file.exists()) return <T>[];
    final output = <T>[];
    var lineNumber = 0;
    await for (final line
        in file
            .openRead()
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())) {
      lineNumber++;
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) {
          throw const FormatException('JSONL row is not an object');
        }
        output.add(convert(decoded.cast<String, Object?>()));
      } catch (error) {
        await _quarantineBadJsonlLine(file, lineNumber, line, error);
      }
    }
    return output;
  }

  Future<void> _writeJsonl(
    File file,
    Iterable<Map<String, Object?>> rows,
  ) async {
    await _withFileLock(file, () => _writeJsonlUnlocked(file, rows));
  }

  Future<void> _writeJsonlUnlocked(
    File file,
    Iterable<Map<String, Object?>> rows,
  ) async {
    await ensureReady();
    await file.parent.create(recursive: true);
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final sink = temp.openWrite(encoding: utf8);
    try {
      for (final row in rows) {
        sink.writeln(jsonEncode(row));
      }
    } finally {
      await sink.close();
    }
    await _replaceWithTemp(temp, file);
  }

  Future<void> _replaceWithTemp(File temp, File file) async {
    Object? lastError;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await temp.rename(file.path);
        return;
      } catch (error) {
        lastError = error;
        try {
          await temp.copy(file.path);
          await temp.delete();
          return;
        } catch (_) {}
        await Future<void>.delayed(Duration(milliseconds: 20 * (attempt + 1)));
      }
    }
    throw lastError!;
  }

  Future<void> _quarantineBadJsonlLine(
    File file,
    int lineNumber,
    String rawLine,
    Object error,
  ) async {
    final badFile = File('${file.path}.bad');
    await badFile.parent.create(recursive: true);
    final boundedRaw = truncatePersistedText(rawLine, maxLength: 2000);
    await badFile.writeAsString(
      '${jsonEncode({'source': file.path, 'lineNumber': lineNumber, 'raw': boundedRaw, 'error': error.toString(), 'recordedAt': DateTime.now().toIso8601String()})}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> _recoverInterruptedWrites() async {
    if (!await rootDirectory.exists()) return;
    await for (final entity in rootDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.tmp')) continue;
      final targetPath = entity.path.replaceFirst(RegExp(r'\.\d+\.tmp$'), '');
      if (targetPath == entity.path) continue;
      final target = File(targetPath);
      if (await target.exists()) {
        await entity.delete();
      } else {
        await entity.rename(target.path);
      }
    }
  }

  File _chatFile(String chatId, String name) =>
      File(p.join(_chatDirectory(chatId).path, name));

  Directory _chatDirectory(String chatId) =>
      Directory(p.join(rootDirectory.path, 'chats', _safeId(chatId)));

  static String _safeId(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
}
