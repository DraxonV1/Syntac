// Match bounded file and directory paths inside project root.

import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import 'tool_context.dart';

mixin GlobTool on ToolContext {
  Future<Map<String, Object?>> globPaths(
    String inputPattern, {
    int maxResults = 200,
    int offset = 0,
    bool includeDirectories = true,
    bool includeFiles = true,
    bool? caseSensitive,
  }) async {
    final pattern = inputPattern.trim().replaceAll('\\', '/');
    if (pattern.isEmpty) throw ToolFailure('Glob pattern is required');
    if (pattern.contains('\u0000')) {
      throw ToolFailure('Glob pattern contains an invalid character');
    }
    if (Uri.tryParse(pattern)?.hasScheme ?? false) {
      throw ToolFailure('URI glob patterns are not supported');
    }
    if (p.isAbsolute(pattern)) {
      throw ToolFailure('Glob pattern must stay inside project root');
    }
    if (!includeDirectories && !includeFiles) {
      throw ToolFailure('Glob must include files, directories, or both');
    }

    final resultLimit = maxResults.clamp(1, 500).toInt();
    final skip = offset.clamp(0, 1 << 30).toInt();
    final matcher = Glob(
      pattern,
      recursive: pattern.contains('**'),
      caseSensitive: caseSensitive ?? !Platform.isWindows,
    );
    final matches = <Map<String, Object?>>[];
    var matched = 0;
    var hasMore = false;
    final root = p.normalize(p.absolute(projectRoot));

    await for (final entity in matcher.list(root: root, followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
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
      try {
        await resolvePath(relative);
      } on ToolFailure {
        continue;
      }
      matched++;
      if (matched <= skip) continue;
      if (matches.length >= resultLimit) {
        hasMore = true;
        break;
      }
      matches.add({
        'path': relative,
        'type': isDirectory ? 'directory' : 'file',
      });
    }

    return {
      'pattern': inputPattern,
      'offset': skip,
      'maxResults': resultLimit,
      'matches': matches,
      'count': matches.length,
      'matched': matched,
      'hasMore': hasMore,
    };
  }
}
