// Match bounded file and directory paths inside project root.

import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import 'tool_context.dart';

mixin GlobTool on ToolContext {
  Future<Map<String, Object?>> globPaths(
    String? inputPattern, {
    String? path,
    int? maxResults,
    int? limit,
    int offset = 0,
    bool includeDirectories = true,
    bool includeFiles = true,
    bool? caseSensitive,
    bool hidden = true,
    bool gitignore = true,
  }) async {
    final rawInput = (inputPattern != null && inputPattern.trim().isNotEmpty)
        ? inputPattern
        : (path ?? '*');
    final trimmedInput = rawInput.trim();
    if (trimmedInput.isEmpty) throw ToolFailure('Glob pattern is required');
    if (trimmedInput.contains('\u0000')) {
      throw ToolFailure('Glob pattern contains an invalid character');
    }
    if (Uri.tryParse(trimmedInput)?.hasScheme ?? false) {
      throw ToolFailure('URI glob patterns are not supported');
    }

    final effectiveLimit = (limit ?? maxResults ?? 200).clamp(1, 500).toInt();
    final skip = offset.clamp(0, 1 << 30).toInt();
    final root = p.normalize(p.absolute(projectRoot));

    // Split semicolon-separated patterns
    final patterns = trimmedInput
        .split(';')
        .map((p) => p.trim().replaceAll('\\', '/'))
        .where((p) => p.isNotEmpty)
        .toList(growable: false);

    final seen = <String>{};
    final matches = <Map<String, Object?>>[];
    final stringList = <String>[];
    var matched = 0;
    var hasMore = false;

    for (var pattern in patterns) {
      if (pattern == '.' || pattern == './') {
        pattern = '*';
      }
      if (!pattern.contains('*') &&
          !pattern.contains('?') &&
          !pattern.contains('[')) {
        // If it's a directory name, append /*
        final fullTarget = p.join(root, pattern);
        if (Directory(fullTarget).existsSync()) {
          pattern = pattern.endsWith('/') ? '$pattern*' : '$pattern/*';
        }
      }
      final matcher = Glob(
        pattern,
        recursive: pattern.contains('**'),
        caseSensitive: caseSensitive ?? !Platform.isWindows,
      );

      await for (final entity in matcher.list(root: root, followLinks: false)) {
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        final isDirectory = type == FileSystemEntityType.directory;
        final isFile = type == FileSystemEntityType.file;
        if ((!includeDirectories && isDirectory) ||
            (!includeFiles && isFile) ||
            (!isDirectory && !isFile)) {
          continue;
        }
        final relative = p
            .relative(entity.path, from: root)
            .replaceAll(Platform.pathSeparator, '/');
        if (seen.contains(relative)) continue;
        seen.add(relative);

        final segments = relative.split('/');
        if (gitignore &&
            (segments.contains('.git') ||
                segments.contains('.dart_tool') ||
                segments.contains('build'))) {
          continue;
        }
        if (!hidden && segments.any((s) => s.startsWith('.') && s != '.')) {
          continue;
        }

        try {
          await resolvePath(relative);
        } on ToolFailure {
          continue;
        }

        matched++;
        if (matched <= skip) continue;
        if (matches.length >= effectiveLimit) {
          hasMore = true;
          break;
        }

        matches.add({
          'path': relative,
          'type': isDirectory ? 'directory' : 'file',
        });
        stringList.add(isDirectory ? '$relative/' : relative);
      }
      if (hasMore) break;
    }

    return {
      'pattern': trimmedInput,
      'path': trimmedInput,
      'offset': skip,
      'maxResults': effectiveLimit,
      'limit': effectiveLimit,
      'matches': matches,
      'paths': stringList,
      'content': stringList.join('\n'),
      'count': matches.length,
      'matched': matched,
      'hasMore': hasMore,
    };
  }
}
