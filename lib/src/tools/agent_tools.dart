import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/cancellation.dart';
import '../models.dart';
import '../runtime/shell_executor.dart';

class ToolFailure implements Exception {
  ToolFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef ToolUpdateCallback = FutureOr<void> Function(Map<String, Object?>);

class ProjectTools {
  ProjectTools({
    required this.projectRoot,
    required ShellExecutor shellExecutor,
    this.maxReadBytes = 200000,
    this.maxSearchResults = 80,
    this.maxCommandOutputCharacters = maxPersistedTextCharacters,
  }) : _shellExecutor = shellExecutor;

  final String projectRoot;
  final ShellExecutor _shellExecutor;
  final int maxReadBytes;
  final int maxSearchResults;
  final int maxCommandOutputCharacters;

  List<Map<String, Object?>> get specs => [
    _spec(
      'read',
      'Read a bounded file range inside the project.',
      {
        'path': _string('Relative file path'),
        'offset': {
          'type': 'integer',
          'description':
              'Line offset for line reads, byte offset for byte reads',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum lines or bytes to return',
        },
        'startLine': {'type': 'integer'},
        'endLine': {'type': 'integer'},
        'unit': {
          'type': 'string',
          'enum': ['line', 'byte'],
        },
        'raw': {'type': 'boolean'},
      },
      ['path'],
    ),
    _spec(
      'write',
      'Create or overwrite a file inside the project.',
      {
        'path': _string('Relative file path'),
        'content': _string('File content'),
      },
      ['path', 'content'],
    ),
    _spec(
      'edit',
      'Replace one unambiguous text target inside a file.',
      {
        'path': _string('Relative file path'),
        'target': _string('Existing text'),
        'replacement': _string('Replacement text'),
        'requireUnique': {'type': 'boolean'},
        'replaceAll': {'type': 'boolean'},
        'expectedReplacements': {'type': 'integer'},
      },
      ['path', 'target', 'replacement'],
    ),
    _spec(
      'delete',
      'Delete a file inside the project. Recursive directory deletion is disabled unless explicitly requested.',
      {
        'path': _string('Relative path'),
        'recursive': {'type': 'boolean'},
      },
      ['path'],
    ),
    _spec(
      'list',
      'List directory contents inside the project.',
      {
        'path': _string('Relative directory path'),
        'depth': {'type': 'integer'},
      },
      ['path'],
    ),
    _spec(
      'search',
      'Search filenames and text content with bounded, pageable results.',
      {
        'query': _string('Search query'),
        'path': _string('Optional relative directory path'),
        'maxResults': {'type': 'integer'},
        'offset': {
          'type': 'integer',
          'description': 'Number of matches to skip for pagination',
        },
        'regex': {'type': 'boolean'},
        'caseSensitive': {'type': 'boolean'},
        'include': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'exclude': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'contextLines': {'type': 'integer'},
      },
      ['query'],
    ),
    _spec(
      'bash',
      'Run a shell command in the project directory through the configured runtime.',
      {
        'command': _string('Command'),
        'timeout_seconds': {
          'type': 'integer',
          'description': 'Optional timeout in seconds, 1-1800',
        },
      },
      ['command'],
    ),
  ];

  static Map<String, Object?> _string(String description) => {
    'type': 'string',
    'description': description,
  };

  static Map<String, Object?> _spec(
    String name,
    String description,
    Map<String, Object?> properties,
    List<String> required,
  ) => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': required,
      },
    },
  };
  static int _timeoutSeconds(Object? raw, Duration? fallback) {
    final parsed = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    return (parsed ?? fallback?.inSeconds ?? 120).clamp(1, 1800).toInt();
  }

  Future<Map<String, Object?>> execute(
    String name,
    Map<String, Object?> args, {
    CancellationToken? cancellationToken,
    Duration? commandTimeout,
    ToolUpdateCallback? onUpdate,
  }) async {
    try {
      cancellationToken?.throwIfCancelled();
      final result = switch (name) {
        'read' => await readFile(
          args['path'] as String? ?? '',
          offset: args['offset'] as int?,
          limit: args['limit'] as int?,
          startLine: args['startLine'] as int?,
          endLine: args['endLine'] as int?,
          unit: args['unit'] as String?,
          raw: args['raw'] == true,
        ),
        'write' => await writeFile(
          args['path'] as String? ?? '',
          args['content'] as String? ?? '',
        ),
        'edit' => await editFile(
          args['path'] as String? ?? '',
          args['target'] as String? ?? '',
          args['replacement'] as String? ?? '',
          requireUnique: args['requireUnique'] as bool? ?? true,
          replaceAll: args['replaceAll'] == true,
          expectedReplacements: args['expectedReplacements'] as int?,
        ),
        'delete' => await deletePath(
          args['path'] as String? ?? '',
          recursive: args['recursive'] as bool? ?? false,
        ),
        'list' => await listDirectory(
          args['path'] as String? ?? '.',
          depth: args['depth'] as int? ?? 1,
        ),
        'search' => await search(
          args['query'] as String? ?? '',
          path: args['path'] as String?,
          maxResults: args['maxResults'] as int?,
          offset: args['offset'] as int?,
          regex: args['regex'] == true,
          caseSensitive: args['caseSensitive'] as bool?,
          include: _stringList(args['include']),
          exclude: _stringList(args['exclude']),
          contextLines: args['contextLines'] as int?,
        ),
        'bash' => await runBash(
          args['command'] as String? ?? '',
          timeout: Duration(
            seconds: _timeoutSeconds(
              args['timeout_seconds'] ?? args['timeoutSeconds'],
              commandTimeout,
            ),
          ),
          cancellationToken: cancellationToken,
          onUpdate: onUpdate,
        ),
        _ => throw ToolFailure('Unknown tool: $name'),
      };
      return {'ok': true, 'result': result};
    } on OperationCancelledException {
      return {
        'ok': false,
        'category': 'cancelled',
        'cancelled': true,
        'error': 'Tool execution cancelled',
      };
    } on ToolFailure catch (error) {
      return {
        'ok': false,
        'category': 'validation_error',
        'error': error.message,
      };
    } on FileSystemException catch (error) {
      return {
        'ok': false,
        'category': 'filesystem_error',
        'error': error.message,
        'osError': error.osError?.message,
        'path': error.path,
      };
    } catch (error) {
      return {'ok': false, 'category': 'tool_error', 'error': error.toString()};
    }
  }

  Future<Map<String, Object?>> readFile(
    String inputPath, {
    int? offset,
    int? limit,
    int? startLine,
    int? endLine,
    String? unit,
    bool raw = false,
  }) async {
    final path = await _resolve(inputPath);
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) {
      throw ToolFailure('File does not exist: $inputPath');
    }
    if (type == FileSystemEntityType.directory) {
      throw ToolFailure('Path is a directory, not a file: $inputPath');
    }
    final file = File(path);
    final length = await file.length();
    final readUnit = (unit ?? 'line').toLowerCase();
    if (readUnit == 'byte') {
      final start = (offset ?? 0).clamp(0, length).toInt();
      final requested = limit ?? maxReadBytes;
      final safeLimit = requested.clamp(0, maxReadBytes).toInt();
      final end = (start + safeLimit).clamp(start, length).toInt();
      final raf = await file.open();
      try {
        await raf.setPosition(start);
        final bytes = await raf.read(end - start);
        if (!raw && _looksBinary(bytes)) {
          throw ToolFailure('Byte range appears to be binary: $inputPath');
        }
        return {
          'path': inputPath,
          'bytes': length,
          'unit': 'byte',
          'startByte': start,
          'endByteExclusive': end,
          'content': utf8.decode(bytes, allowMalformed: true),
          'truncated': requested > safeLimit || end < length,
        };
      } finally {
        await raf.close();
      }
    }
    if (readUnit != 'line') throw ToolFailure('Unsupported read unit: $unit');
    final start = (startLine ?? offset ?? 1).clamp(1, 1 << 30).toInt();
    final requestedEnd = endLine ?? (limit == null ? null : start + limit - 1);
    if (requestedEnd != null && requestedEnd < start) {
      throw ToolFailure('endLine must be greater than or equal to startLine');
    }
    final selected = <String>[];
    var totalLines = 0;
    var selectedBytes = 0;
    var truncated = false;
    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      totalLines++;
      if (totalLines < start) continue;
      if (requestedEnd != null && totalLines > requestedEnd) continue;
      if (truncated) continue;
      final lineBytes = utf8.encode(line).length + 1;
      if (selectedBytes + lineBytes > maxReadBytes) {
        truncated = true;
        continue;
      }
      selected.add(line);
      selectedBytes += lineBytes;
    }
    final end = selected.isEmpty ? start - 1 : start + selected.length - 1;
    final requestedLimit = requestedEnd == null
        ? null
        : requestedEnd - start + 1;
    return {
      'path': inputPath,
      'bytes': length,
      'unit': 'line',
      'startLine': start,
      'endLine': end,
      'totalLines': totalLines,
      'content': selected.join(raw ? '\n' : '\n'),
      'truncated': truncated,
      'contentTruncated': truncated,
      'hasMore': requestedEnd == null
          ? end < totalLines
          : requestedEnd < totalLines,
      'requestedLines': requestedLimit,
    };
  }

  Future<Map<String, Object?>> writeFile(
    String inputPath,
    String content,
  ) async {
    final path = await _resolve(inputPath, forWrite: true);
    final file = File(path);
    await file.parent.create(recursive: true);
    await _atomicWriteString(file, content);
    final stat = await file.stat();
    return {
      'path': inputPath,
      'bytes': stat.size,
      'modifiedAt': stat.modified.toIso8601String(),
    };
  }

  Future<Map<String, Object?>> editFile(
    String inputPath,
    String target,
    String replacement, {
    bool requireUnique = true,
    bool replaceAll = false,
    int? expectedReplacements,
  }) async {
    if (target.isEmpty) throw ToolFailure('Edit target must not be empty');
    final path = await _resolve(inputPath);
    final file = File(path);
    if (!await file.exists()) {
      throw ToolFailure('File does not exist: $inputPath');
    }
    final content = await file.readAsString();
    final occurrences = _countOccurrences(content, target);
    if (occurrences == 0) throw ToolFailure('Edit target not found');
    if (requireUnique && !replaceAll && occurrences > 1) {
      throw ToolFailure('Edit target occurs more than once');
    }
    if (expectedReplacements != null && occurrences != expectedReplacements) {
      throw ToolFailure(
        'Edit target occurrence count $occurrences did not match expectedReplacements=$expectedReplacements',
      );
    }
    final updated = replaceAll
        ? content.replaceAll(target, replacement)
        : content.replaceFirst(target, replacement);
    await _atomicWriteString(file, updated);
    final replacements = replaceAll ? occurrences : 1;
    return {
      'path': inputPath,
      'replacedBytes': utf8.encode(target).length,
      'newBytes': utf8.encode(replacement).length,
      'replacedLines': _lineCount(target) * replacements,
      'newLines': _lineCount(replacement) * replacements,
      'replacements': replacements,
    };
  }

  Future<Map<String, Object?>> deletePath(
    String inputPath, {
    bool recursive = false,
  }) async {
    final path = await _resolve(inputPath);
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) {
      return {'path': inputPath, 'deleted': false, 'reason': 'not_found'};
    }
    if (type == FileSystemEntityType.directory && !recursive) {
      throw ToolFailure('Refusing to delete directory without recursive=true');
    }
    if (await FileSystemEntity.isDirectory(path)) {
      await Directory(path).delete(recursive: recursive);
    } else {
      await File(path).delete();
    }
    return {'path': inputPath, 'deleted': true};
  }

  Future<Map<String, Object?>> listDirectory(
    String inputPath, {
    int depth = 1,
  }) async {
    final path = await _resolve(inputPath);
    final dir = Directory(path);
    if (!await dir.exists()) {
      throw ToolFailure('Directory does not exist: $inputPath');
    }
    final entries = <Map<String, Object?>>[];
    await _list(
      dir,
      inputPath == '.' ? '' : inputPath,
      depth.clamp(0, 4),
      entries,
    );
    return {'path': inputPath, 'entries': entries};
  }

  Future<void> _list(
    Directory dir,
    String relative,
    int depth,
    List<Map<String, Object?>> entries,
  ) async {
    if (entries.length >= maxSearchResults) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entries.length >= maxSearchResults) break;
      final name = p.basename(entity.path);
      if (name.startsWith('.git')) continue;
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      final rel = relative.isEmpty ? name : p.join(relative, name);
      entries.add({'path': rel, 'type': _entityTypeName(type)});
      if (depth > 1 && type == FileSystemEntityType.directory) {
        await _list(Directory(entity.path), rel, depth - 1, entries);
      }
    }
  }

  Future<Map<String, Object?>> search(
    String query, {
    String? path,
    int? maxResults,
    int? offset,
    bool regex = false,
    bool? caseSensitive,
    List<String>? include,
    List<String>? exclude,
    int? contextLines,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) throw ToolFailure('Search query is required');
    final root = Directory(
      await _resolve(path == null || path.isEmpty ? '.' : path),
    );
    if (!await root.exists()) throw ToolFailure('Search path does not exist');
    final resultLimit = (maxResults ?? maxSearchResults).clamp(1, 500).toInt();
    final skip = (offset ?? 0).clamp(0, 1 << 30).toInt();
    final beforeAfter = (contextLines ?? 0).clamp(0, 5).toInt();
    final pattern = regex ? cleanQuery : RegExp.escape(cleanQuery);
    final RegExp matcher;
    try {
      matcher = RegExp(
        pattern,
        caseSensitive: caseSensitive ?? regex,
        multiLine: true,
      );
    } on FormatException catch (error) {
      throw ToolFailure('Invalid search regex: ${error.message}');
    }
    final includeGlobs = include
        ?.map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final excludeGlobs = exclude
        ?.map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final results = <Map<String, Object?>>[];
    var scannedFiles = 0;
    var skippedLargeFiles = 0;
    var skippedBinaryFiles = 0;
    var skippedByInclude = 0;
    var skippedByExclude = 0;
    var totalMatches = 0;
    var hasMore = false;

    void addMatch(Map<String, Object?> match) {
      if (totalMatches++ < skip) return;
      if (results.length >= resultLimit) {
        hasMore = true;
        return;
      }
      results.add(match);
    }

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final rel = p.relative(entity.path, from: projectRoot);
      if (rel.split(p.separator).contains('.git')) continue;
      final normalizedRel = rel.replaceAll(p.separator, '/');
      if (includeGlobs != null &&
          !includeGlobs.any((glob) => _matchesGlob(normalizedRel, glob))) {
        skippedByInclude++;
        continue;
      }
      if (excludeGlobs != null &&
          excludeGlobs.any((glob) => _matchesGlob(normalizedRel, glob))) {
        skippedByExclude++;
        continue;
      }
      final nameHit = matcher.hasMatch(normalizedRel);
      if (entity is File) {
        scannedFiles++;
        if (nameHit) {
          addMatch({'path': rel, 'kind': 'filename', 'match': 'filename'});
        }
        try {
          final length = await entity.length();
          if (length > maxReadBytes) {
            skippedLargeFiles++;
            continue;
          }
          final bytes = await entity.readAsBytes();
          if (_looksBinary(bytes)) {
            skippedBinaryFiles++;
            continue;
          }
          final lines = const LineSplitter().convert(
            utf8.decode(bytes, allowMalformed: true),
          );
          for (var i = 0; i < lines.length; i++) {
            final match = matcher.firstMatch(lines[i]);
            if (match == null) continue;
            addMatch({
              'path': rel,
              'kind': 'content',
              'line': i + 1,
              'column': match.start + 1,
              'text': truncatePersistedText(lines[i], maxLength: 1000),
              if (beforeAfter > 0)
                'before': lines
                    .sublist(
                      (i - beforeAfter).clamp(0, lines.length).toInt(),
                      i,
                    )
                    .map((line) => truncatePersistedText(line, maxLength: 1000))
                    .toList(growable: false),
              if (beforeAfter > 0)
                'after': lines
                    .sublist(
                      i + 1,
                      (i + 1 + beforeAfter).clamp(0, lines.length).toInt(),
                    )
                    .map((line) => truncatePersistedText(line, maxLength: 1000))
                    .toList(growable: false),
            });
          }
        } on FormatException catch (error) {
          throw ToolFailure('Invalid search regex: ${error.message}');
        } catch (_) {}
      } else if (nameHit) {
        addMatch({'path': rel, 'kind': 'filename', 'match': 'filename'});
      }
    }
    return {
      'query': query,
      'regex': regex,
      'caseSensitive': caseSensitive ?? regex,
      'offset': skip,
      'results': results,
      'truncated': hasMore,
      'hasMore': hasMore,
      if (hasMore) 'nextOffset': skip + results.length,
      'totalMatchesSeen': totalMatches,
      'scannedFiles': scannedFiles,
      'skippedLargeFiles': skippedLargeFiles,
      'skippedBinaryFiles': skippedBinaryFiles,
      'skippedByInclude': skippedByInclude,
      'skippedByExclude': skippedByExclude,
    };
  }

  static int _lineCount(String value) =>
      value.isEmpty ? 0 : '\n'.allMatches(value).length + 1;
  static List<String>? _stringList(Object? value) {
    if (value is! List) return null;
    return value.whereType<String>().toList(growable: false);
  }

  static bool _matchesGlob(String path, String glob) {
    final normalized = glob.replaceAll('\\', '/');
    final escaped = RegExp.escape(normalized)
        .replaceAll(r'\*\*', '§DOUBLESTAR§')
        .replaceAll(r'\*', '[^/]*')
        .replaceAll('§DOUBLESTAR§', '.*')
        .replaceAll(r'\?', '[^/]');
    return RegExp('^$escaped\$').hasMatch(path);
  }

  Future<Map<String, Object?>> runBash(
    String command, {
    required Duration timeout,
    CancellationToken? cancellationToken,
    ToolUpdateCallback? onUpdate,
  }) async {
    if (command.trim().isEmpty) throw ToolFailure('Command is required');
    var liveStdout = '';
    var liveStderr = '';
    var liveStdoutTruncated = false;
    var liveStderrTruncated = false;
    int? liveStdoutOriginalLength;
    int? liveStderrOriginalLength;
    final result = await _shellExecutor.run(
      command: command,
      workingDirectory: projectRoot,
      timeout: timeout,
      cancellationToken: cancellationToken,
      onOutput: onUpdate == null
          ? null
          : (update) async {
              if (update.stdout != null) {
                liveStdout = update.stdout!;
                liveStdoutTruncated = update.stdoutTruncated;
                liveStdoutOriginalLength = update.stdoutOriginalLength;
              }
              if (update.stderr != null) {
                liveStderr = update.stderr!;
                liveStderrTruncated = update.stderrTruncated;
                liveStderrOriginalLength = update.stderrOriginalLength;
              }
              final output = _boundedOutputPair(liveStdout, liveStderr);
              await onUpdate({
                'command': command,
                'workingDirectory': projectRoot,
                'success': false,
                'runtime': _shellExecutor.runtimeId,
                'category': 'running',
                'stdout': output.stdout,
                'stderr': output.stderr,
                if (output.stdoutTruncated || liveStdoutTruncated)
                  'stdoutTruncated': true,
                if (output.stderrTruncated || liveStderrTruncated)
                  'stderrTruncated': true,
                ...?liveStdoutOriginalLength == null
                    ? null
                    : {'stdoutOriginalLength': liveStdoutOriginalLength},
                ...?liveStderrOriginalLength == null
                    ? null
                    : {'stderrOriginalLength': liveStderrOriginalLength},
              });
            },
    );
    final json = result.toJson();
    final output = _boundedOutputPair(result.stdout, result.stderr);
    json['stdout'] = output.stdout;
    json['stderr'] = output.stderr;
    if (output.stdoutTruncated) {
      json['stdoutTruncated'] = true;
      json.putIfAbsent('stdoutOriginalLength', () => result.stdout.length);
    }
    if (output.stderrTruncated) {
      json['stderrTruncated'] = true;
      json.putIfAbsent('stderrOriginalLength', () => result.stderr.length);
    }
    final failureKind = result.failureKind;
    final category = result.cancelled
        ? 'cancelled'
        : failureKind == 'TermuxBackgroundRestricted'
        ? 'termux_background_restricted'
        : failureKind != null
        ? 'runtime_failure'
        : result.timedOut
        ? 'timeout'
        : result.exitCode == 0
        ? 'success'
        : 'command_exit_error';
    return {
      'command': command,
      'workingDirectory': projectRoot,
      'success': result.success,
      'runtime': _shellExecutor.runtimeId,
      'category': category,
      ...?failureKind == null ? null : {'failureKind': failureKind},
      if (result.timedOut)
        'message': 'Command exceeded ${timeout.inSeconds} seconds.',
      if (failureKind == 'CallbackFailed')
        'message': 'Runtime did not return a command result callback.',
      if (failureKind == 'TermuxBackgroundRestricted')
        'message':
            'Android blocked starting a Termux command while Syntac was in the background.',
      ...json,
    };
  }

  Future<String> _resolve(String inputPath, {bool forWrite = false}) async {
    final raw = inputPath.trim();
    if (raw.isEmpty) throw ToolFailure('Path is required');
    if (Uri.tryParse(raw)?.hasScheme ?? false) {
      throw ToolFailure('URI paths are not supported for project tools');
    }
    final lexicalRoot = p.normalize(p.absolute(projectRoot));
    final joined = p.isAbsolute(raw) ? raw : p.join(lexicalRoot, raw);
    final lexicalTarget = p.normalize(p.absolute(joined));
    if (!_isWithinOrSame(lexicalRoot, lexicalTarget)) {
      throw ToolFailure('Path escapes project root: $inputPath');
    }
    if (!forWrite && p.basename(lexicalTarget).isEmpty) {
      throw ToolFailure('Invalid path: $inputPath');
    }

    final rootReal = await _realPathForExisting(
      Directory(lexicalRoot),
      inputPath,
    );
    final targetType = await FileSystemEntity.type(
      lexicalTarget,
      followLinks: false,
    );
    if (targetType != FileSystemEntityType.notFound) {
      final targetReal = await _realPathForExisting(
        FileSystemEntity.isDirectorySync(lexicalTarget)
            ? Directory(lexicalTarget)
            : File(lexicalTarget),
        inputPath,
      );
      if (!_isWithinOrSame(rootReal, targetReal)) {
        throw ToolFailure(
          'Path escapes project root through symlink: $inputPath',
        );
      }
      return lexicalTarget;
    }

    final ancestor = await _nearestExistingAncestor(lexicalTarget);
    final ancestorReal = await _realPathForExisting(ancestor, inputPath);
    if (!_isWithinOrSame(rootReal, ancestorReal)) {
      throw ToolFailure(
        'Path escapes project root through symlink: $inputPath',
      );
    }
    return lexicalTarget;
  }

  Future<FileSystemEntity> _nearestExistingAncestor(String path) async {
    var cursor = Directory(p.dirname(path));
    while (!await cursor.exists()) {
      final parent = p.dirname(cursor.path);
      if (parent == cursor.path) return cursor;
      cursor = Directory(parent);
    }
    return cursor;
  }

  Future<String> _realPathForExisting(
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

  bool _isWithinOrSame(String root, String candidate) {
    final normalizedRoot = p.normalize(root);
    final normalizedCandidate = p.normalize(candidate);
    return normalizedCandidate == normalizedRoot ||
        p.isWithin(normalizedRoot, normalizedCandidate);
  }

  String _entityTypeName(FileSystemEntityType type) {
    if (type == FileSystemEntityType.file) return 'file';
    if (type == FileSystemEntityType.directory) return 'directory';
    if (type == FileSystemEntityType.link) return 'link';
    if (type == FileSystemEntityType.notFound) return 'notFound';
    return 'unknown';
  }

  bool _looksBinary(List<int> bytes) {
    final sample = bytes.take(4096);
    return sample.any((byte) => byte == 0);
  }

  int _countOccurrences(String content, String target) {
    var count = 0;
    var index = 0;
    while (true) {
      index = content.indexOf(target, index);
      if (index < 0) return count;
      count++;
      index += target.length;
    }
  }

  Future<void> _atomicWriteString(File file, String content) async {
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

  ({String text, bool truncated}) _boundedOutput(
    String value, {
    int? maxLength,
  }) {
    final limit = maxLength ?? maxCommandOutputCharacters;
    if (value.length <= limit) {
      return (text: value, truncated: false);
    }
    return (
      text: truncatePersistedText(value, maxLength: limit),
      truncated: true,
    );
  }

  ({String stdout, bool stdoutTruncated, String stderr, bool stderrTruncated})
  _boundedOutputPair(String stdout, String stderr) {
    if (stdout.length + stderr.length <= maxCommandOutputCharacters) {
      return (
        stdout: stdout,
        stdoutTruncated: false,
        stderr: stderr,
        stderrTruncated: false,
      );
    }
    final stdoutBudget = stdout.length <= maxCommandOutputCharacters ~/ 2
        ? stdout.length
        : maxCommandOutputCharacters ~/ 2;
    final stderrBudget = maxCommandOutputCharacters - stdoutBudget;
    final boundedStdout = _boundedOutput(stdout, maxLength: stdoutBudget);
    final boundedStderr = _boundedOutput(stderr, maxLength: stderrBudget);
    return (
      stdout: boundedStdout.text,
      stdoutTruncated: boundedStdout.truncated,
      stderr: boundedStderr.text,
      stderrTruncated: boundedStderr.truncated,
    );
  }
}
