// List bounded project directory contents.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'tool_context.dart';

mixin ListTool on ToolContext {
  Future<Map<String, Object?>> listDirectory(
    String inputPath, {
    int depth = 1,
  }) async {
    final path = await resolvePath(inputPath);
    final dir = Directory(path);
    if (!await dir.exists()) {
      throw ToolFailure('Directory does not exist: $inputPath');
    }
    final entries = <Map<String, Object?>>[];
    await _listDirectoryEntries(
      dir,
      inputPath == '.' ? '' : inputPath,
      depth.clamp(0, 4),
      entries,
    );
    return {'path': inputPath, 'entries': entries};
  }

  Future<void> _listDirectoryEntries(
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
      entries.add({'path': rel, 'type': entityTypeName(type)});
      if (depth > 1 && type == FileSystemEntityType.directory) {
        await _listDirectoryEntries(
          Directory(entity.path),
          rel,
          depth - 1,
          entries,
        );
      }
    }
  }
}
