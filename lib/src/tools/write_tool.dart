// Create or overwrite project files through bounded sandbox paths.

import 'dart:io';

import 'tool_context.dart';

mixin WriteTool on ToolContext {
  Future<Map<String, Object?>> writeFile(
    String inputPath,
    String content,
  ) async {
    final path = await resolvePath(inputPath, forWrite: true);
    final file = File(path);
    await file.parent.create(recursive: true);
    await atomicWriteString(file, content);
    final stat = await file.stat();
    return {
      'path': inputPath,
      'bytes': stat.size,
      'modifiedAt': stat.modified.toIso8601String(),
    };
  }
}
