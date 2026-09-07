// Replace unambiguous text targets inside project files.

import 'dart:convert';
import 'dart:io';

import 'tool_context.dart';

mixin EditTool on ToolContext {
  Future<Map<String, Object?>> editFile(
    String inputPath,
    String target,
    String replacement, {
    bool requireUnique = true,
    bool replaceAll = false,
    int? expectedReplacements,
  }) async {
    if (target.isEmpty) throw ToolFailure('Edit target must not be empty');
    final path = await resolvePath(inputPath);
    final file = File(path);
    if (!await file.exists()) {
      throw ToolFailure('File does not exist: $inputPath');
    }
    final content = await file.readAsString();
    final occurrences = countOccurrences(content, target);
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
    await atomicWriteString(file, updated);
    final replacements = replaceAll ? occurrences : 1;
    return {
      'path': inputPath,
      'replacedBytes': utf8.encode(target).length,
      'newBytes': utf8.encode(replacement).length,
      'replacedLines': lineCount(target) * replacements,
      'newLines': lineCount(replacement) * replacements,
      'replacements': replacements,
    };
  }
}
