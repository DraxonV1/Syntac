// Delete project files through sandbox-validated paths.

import 'dart:io';

import 'tool_context.dart';

mixin DeleteTool on ToolContext {
  Future<Map<String, Object?>> deletePath(
    String inputPath, {
    bool recursive = false,
  }) async {
    final path = await resolvePath(inputPath);
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
}
