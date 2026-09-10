// Shared sandbox, output bounds, and attachment URI helpers for project tools.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import '../runtime/shell_executor.dart';

class ToolFailure implements Exception {
  ToolFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef ToolUpdateCallback = FutureOr<void> Function(Map<String, Object?>);

enum CommandRisk {
  readOnly,
  workspaceWrite,
  destructive,
  network,
  packageInstall,
  persistentService,
}

class CommandApprovalRequest {
  const CommandApprovalRequest({
    required this.command,
    required this.workingDirectory,
    required this.runtime,
    required this.risk,
    required this.reason,
    required this.timeout,
    required this.background,
  });

  final String command;
  final String workingDirectory;
  final String runtime;
  final CommandRisk risk;
  final String reason;
  final Duration timeout;
  final bool background;
}

typedef CommandApprovalHandler =
    Future<bool> Function(CommandApprovalRequest request);

CommandRisk assessCommandRisk(String command, {bool background = false}) {
  final normalized = command.trim();
  if (RegExp(
    r'\brm\s+-[^\n]*r|'
    r'\bmkfs(?:\.|[ \t])|\bdd\s+if=|\bgit\s+reset\s+--hard|'
    r'\bshutdown\b|\breboot\b',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    return CommandRisk.destructive;
  }
  if (RegExp(
    r'\b(?:pacman\s+-[^\n]*S|apt(?:-get)?\s+install|apk\s+add|'
    r'(?:pip|pip3|npm|pnpm|yarn|cargo)\s+(?:install|add))\b',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    return CommandRisk.packageInstall;
  }
  final network = RegExp(
    r'\b(curl|wget|cloudflared|nc|ncat|netcat|uvicorn|gunicorn)\b|python(?:3)?\s+-m\s+http\.server',
    caseSensitive: false,
  ).hasMatch(normalized);
  if (background && network) return CommandRisk.persistentService;
  if (network) return CommandRisk.network;
  if (RegExp(
    r'(?:^|[;&|])[ \t]*(?:tee|mv|cp|touch|mkdir)\b|>>?|2>>?|sed\s+-i\b',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    return CommandRisk.workspaceWrite;
  }
  return CommandRisk.readOnly;
}

bool commandRequiresApproval(CommandRisk risk) =>
    risk == CommandRisk.destructive ||
    risk == CommandRisk.packageInstall ||
    risk == CommandRisk.persistentService;

String commandRiskLabel(CommandRisk risk) => switch (risk) {
  CommandRisk.readOnly => 'read-only',
  CommandRisk.workspaceWrite => 'workspace write',
  CommandRisk.destructive => 'destructive',
  CommandRisk.network => 'network',
  CommandRisk.packageInstall => 'package install',
  CommandRisk.persistentService => 'persistent service',
};

class ToolContext {
  ToolContext({
    required this.projectRoot,
    required this.shellExecutor,
    this.commandApproval,
    this.attachments = const <Attachment>[],
    this.maxReadBytes = 200000,
    this.maxSearchResults = 80,
    this.maxCommandOutputCharacters = maxPersistedTextCharacters,
  });

  final String projectRoot;
  final ShellExecutor shellExecutor;
  final CommandApprovalHandler? commandApproval;
  final List<Attachment> attachments;
  final int maxReadBytes;
  final int maxSearchResults;
  final int maxCommandOutputCharacters;

  static const maxReadLines = 500;
  static const maxPreviewLines = 50;
  static const maxArtifactCharacters = 8 * 1024 * 1024;
  static const maxInlineImageBytes = 3 * 1024 * 1024;

  Future<String> resolveLocalPath(String inputPath) async {
    if (inputPath.startsWith('local://attachment-')) {
      return _resolveLocalAttachment(inputPath);
    }
    final raw = inputPath.substring('local://'.length).replaceAll('\\', '/');
    final relative = raw.startsWith('.syntac/')
        ? raw
        : raw.startsWith('.omp/')
        ? raw
        : p.join('.syntac', 'agent', 'blobs', raw);
    return resolvePath(relative);
  }

  Future<String> resolvePath(String inputPath, {bool forWrite = false}) async {
    final raw = inputPath.trim();
    if (raw.isEmpty) throw ToolFailure('Path is required');
    if (Uri.tryParse(raw)?.hasScheme ?? false) {
      throw ToolFailure('URI paths are not supported for project tools');
    }
    final lexicalRoot = p.normalize(p.absolute(projectRoot));
    final joined = p.isAbsolute(raw) ? raw : p.join(lexicalRoot, raw);
    final lexicalTarget = p.normalize(p.absolute(joined));
    if (!isWithinOrSame(lexicalRoot, lexicalTarget)) {
      throw ToolFailure('Path escapes project root: $inputPath');
    }
    if (!forWrite && p.basename(lexicalTarget).isEmpty) {
      throw ToolFailure('Invalid path: $inputPath');
    }

    final rootReal = await realPathForExisting(
      Directory(lexicalRoot),
      inputPath,
    );
    final targetType = await FileSystemEntity.type(
      lexicalTarget,
      followLinks: false,
    );
    if (targetType != FileSystemEntityType.notFound) {
      final targetReal = await realPathForExisting(
        FileSystemEntity.isDirectorySync(lexicalTarget)
            ? Directory(lexicalTarget)
            : File(lexicalTarget),
        inputPath,
      );
      if (!isWithinOrSame(rootReal, targetReal)) {
        throw ToolFailure(
          'Path escapes project root through symlink: $inputPath',
        );
      }
      return lexicalTarget;
    }

    final ancestor = await nearestExistingAncestor(lexicalTarget);
    final ancestorReal = await realPathForExisting(ancestor, inputPath);
    if (!isWithinOrSame(rootReal, ancestorReal)) {
      throw ToolFailure(
        'Path escapes project root through symlink: $inputPath',
      );
    }
    return lexicalTarget;
  }

  Future<String> _resolveLocalAttachment(String inputPath) async {
    final raw = inputPath.substring('local://'.length).replaceAll('\\', '/');
    final slash = raw.indexOf('/');
    final id = slash < 0 ? raw : raw.substring(0, slash);
    final match = RegExp(r'^attachment-(\d+)$').firstMatch(id);
    final index = int.tryParse(match?.group(1) ?? '') ?? 0;
    if (index < 1 || index > attachments.length) {
      throw ToolFailure('Attached file is no longer available: $inputPath');
    }
    final attachment = attachments[index - 1];
    final path = p.normalize(p.absolute(attachment.path));
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw ToolFailure('Attached file does not exist: ${attachment.name}');
    }
    return path;
  }

  Future<FileSystemEntity> nearestExistingAncestor(String path) async {
    var cursor = Directory(p.dirname(path));
    while (!await cursor.exists()) {
      final parent = p.dirname(cursor.path);
      if (parent == cursor.path) return cursor;
      cursor = Directory(parent);
    }
    return cursor;
  }

  Future<String> realPathForExisting(
    FileSystemEntity entity,
    String inputPath,
  ) async {
    try {
      return p.normalize(await entity.resolveSymbolicLinks());
    } on FileSystemException catch (error) {
      throw ToolFailure(
        'Path contains an invalid symlink or inaccessible ancestor: $inputPath (${error.message})',
      );
    }
  }

  bool isWithinOrSame(String root, String candidate) {
    final normalizedRoot = p.normalize(root);
    final normalizedCandidate = p.normalize(candidate);
    return normalizedCandidate == normalizedRoot ||
        p.isWithin(normalizedRoot, normalizedCandidate);
  }

  String entityTypeName(FileSystemEntityType type) {
    if (type == FileSystemEntityType.file) return 'file';
    if (type == FileSystemEntityType.directory) return 'directory';
    if (type == FileSystemEntityType.link) return 'link';
    if (type == FileSystemEntityType.notFound) return 'notFound';
    return 'unknown';
  }

  bool looksBinary(List<int> bytes) =>
      bytes.take(4096).any((byte) => byte == 0);

  int countOccurrences(String content, String target) {
    var count = 0;
    var index = 0;
    while (true) {
      index = content.indexOf(target, index);
      if (index < 0) return count;
      count++;
      index += target.length;
    }
  }

  int lineCount(String value) =>
      value.isEmpty ? 0 : '\n'.allMatches(value).length + 1;

  Future<void> atomicWriteString(File file, String content) async {
    final temp = File(
      '${file.path}.syntac-tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temp.writeAsString(content);
    try {
      await temp.rename(file.path);
    } on FileSystemException {
      await file.writeAsString(content);
      if (await temp.exists()) await temp.delete();
    }
  }

  ({String text, bool truncated}) boundedOutput(
    String value, {
    int? maxLength,
    bool limitLines = true,
  }) {
    final limit = maxLength ?? maxCommandOutputCharacters;
    final lines = value.split('\n');
    final lineTruncated = limitLines && lines.length > maxPreviewLines;
    final linePreview = lineTruncated
        ? lines.take(maxPreviewLines).join('\n')
        : value;
    if (linePreview.length <= limit) {
      return (text: linePreview, truncated: lineTruncated);
    }
    return (
      text: truncatePersistedText(linePreview, maxLength: limit),
      truncated: true,
    );
  }

  ({String stdout, bool stdoutTruncated, String stderr, bool stderrTruncated})
  boundedOutputPair(String stdout, String stderr, {bool limitLines = true}) {
    final initialStdout = boundedOutput(stdout, limitLines: limitLines);
    final initialStderr = boundedOutput(stderr, limitLines: limitLines);
    final initialTotal = initialStdout.text.length + initialStderr.text.length;
    if (initialTotal <= maxCommandOutputCharacters) {
      return (
        stdout: initialStdout.text,
        stdoutTruncated: initialStdout.truncated,
        stderr: initialStderr.text,
        stderrTruncated: initialStderr.truncated,
      );
    }

    var stdoutBudget = minInt(
      initialStdout.text.length,
      maxCommandOutputCharacters ~/ 2,
    );
    var stderrBudget = minInt(
      initialStderr.text.length,
      maxCommandOutputCharacters - stdoutBudget,
    );
    var remaining = maxCommandOutputCharacters - stdoutBudget - stderrBudget;
    if (remaining > 0) {
      final stdoutRoom = initialStdout.text.length - stdoutBudget;
      final stdoutExtra = minInt(remaining, stdoutRoom);
      stdoutBudget += stdoutExtra;
      remaining -= stdoutExtra;
    }
    if (remaining > 0) {
      stderrBudget += minInt(
        remaining,
        initialStderr.text.length - stderrBudget,
      );
    }
    final boundedStdout = boundedOutput(
      stdout,
      maxLength: stdoutBudget,
      limitLines: limitLines,
    );
    final boundedStderr = boundedOutput(
      stderr,
      maxLength: stderrBudget,
      limitLines: limitLines,
    );
    return (
      stdout: boundedStdout.text,
      stdoutTruncated: boundedStdout.truncated || boundedStdout.text != stdout,
      stderr: boundedStderr.text,
      stderrTruncated: boundedStderr.truncated || boundedStderr.text != stderr,
    );
  }

  Future<String?> writeOutputArtifact({
    required String command,
    required String stdout,
    required String stderr,
  }) async {
    final directory = Directory(
      p.join(projectRoot, '.syntac', 'agent', 'blobs'),
    );
    await directory.create(recursive: true);
    final name = 'bash-run-${DateTime.now().microsecondsSinceEpoch}.log';
    final file = File(p.join(directory.path, name));
    final content = StringBuffer()
      ..writeln('command: $command')
      ..writeln()
      ..writeln(stdout)
      ..writeln()
      ..writeln('--- stderr ---')
      ..writeln(stderr);
    final text = content.toString();
    await file.writeAsString(
      text.length > maxArtifactCharacters
          ? '${text.substring(0, maxArtifactCharacters)}\n\n[artifact truncated at $maxArtifactCharacters characters]'
          : text,
    );
    return 'local://$name';
  }

  List<String>? stringList(Object? value) {
    if (value is! List) return null;
    return value.whereType<String>().toList(growable: false);
  }

  bool matchesGlob(String path, String glob) {
    final normalized = glob.replaceAll('\\', '/');
    final escaped = RegExp.escape(normalized)
        .replaceAll(r'\*\*', '§DOUBLESTAR§')
        .replaceAll(r'\*', '[^/]*')
        .replaceAll('§DOUBLESTAR§', '.*')
        .replaceAll(r'\?', '[^/]');
    return RegExp('^$escaped\$').hasMatch(path);
  }

  int minInt(int a, int b) => a < b ? a : b;
}
