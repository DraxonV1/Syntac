// Apply bounded multi-file patches inside project root.

import 'dart:convert';
import 'dart:io';

import 'tool_context.dart';

class _PreparedPatch {
  const _PreparedPatch({
    required this.path,
    required this.operation,
    required this.file,
    required this.content,
  });

  final String path;
  final String operation;
  final File file;
  final String? content;
}

mixin ApplyPatchTool on ToolContext {
  Future<Map<String, Object?>> applyPatch(String patch) async {
    final normalized = patch.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    if (lines.isEmpty || lines.first.trim() != '*** Begin Patch') {
      throw ToolFailure('Patch must start with *** Begin Patch');
    }
    final prepared = <_PreparedPatch>[];
    var index = 1;
    var sawEnd = false;
    while (index < lines.length) {
      final line = lines[index];
      if (line.trim().isEmpty) {
        index++;
        continue;
      }
      if (line.trim() == '*** End Patch') {
        sawEnd = true;
        break;
      }
      if (line.startsWith('*** Update File: ')) {
        final path = line.substring('*** Update File: '.length).trim();
        final filePath = await resolvePath(path);
        final file = File(filePath);
        if (!await file.exists()) {
          throw ToolFailure('File does not exist: $path');
        }
        final original = await file.readAsString();
        final updated = _applyUpdate(path, original, lines, index + 1);
        prepared.add(
          _PreparedPatch(
            path: path,
            operation: 'update',
            file: file,
            content: updated.content,
          ),
        );
        index = updated.nextIndex;
        continue;
      }
      if (line.startsWith('*** Add File: ')) {
        final path = line.substring('*** Add File: '.length).trim();
        final filePath = await resolvePath(path, forWrite: true);
        final file = File(filePath);
        if (await file.exists()) {
          throw ToolFailure('File already exists: $path');
        }
        final added = _parseAddedFile(path, lines, index + 1);
        prepared.add(
          _PreparedPatch(
            path: path,
            operation: 'add',
            file: file,
            content: added.content,
          ),
        );
        index = added.nextIndex;
        continue;
      }
      if (line.startsWith('*** Delete File: ')) {
        final path = line.substring('*** Delete File: '.length).trim();
        final filePath = await resolvePath(path);
        final file = File(filePath);
        if (!await file.exists()) {
          throw ToolFailure('File does not exist: $path');
        }
        prepared.add(
          _PreparedPatch(
            path: path,
            operation: 'delete',
            file: file,
            content: null,
          ),
        );
        index++;
        continue;
      }
      throw ToolFailure('Unsupported patch directive: $line');
    }
    if (!sawEnd) throw ToolFailure('Patch must end with *** End Patch');
    if (prepared.isEmpty) throw ToolFailure('Patch contains no file changes');

    for (final change in prepared) {
      if (change.operation == 'delete') {
        await change.file.delete();
      } else {
        await change.file.parent.create(recursive: true);
        await atomicWriteString(change.file, change.content ?? '');
      }
    }
    final files = prepared
        .map(
          (change) => {
            'path': change.path,
            'operation': change.operation,
            if (change.content != null)
              'bytes': utf8.encode(change.content!).length,
          },
        )
        .toList(growable: false);
    return {
      'files': files,
      'changedFiles': files,
      'fileCount': files.length,
      'diff': normalized,
    };
  }

  ({String content, int nextIndex}) _applyUpdate(
    String path,
    String original,
    List<String> lines,
    int index,
  ) {
    final hadTrailingNewline = original.endsWith('\n');
    final current = _contentLines(original);
    var cursor = 0;
    var hunkCount = 0;
    while (index < lines.length &&
        !lines[index].startsWith('*** ') &&
        lines[index].trim() != '*** End Patch') {
      if (!lines[index].startsWith('@@')) {
        throw ToolFailure('Update patch for $path requires @@ hunks');
      }
      hunkCount++;
      index++;
      final oldLines = <String>[];
      final newLines = <String>[];
      while (index < lines.length &&
          !lines[index].startsWith('@@') &&
          !lines[index].startsWith('*** ') &&
          lines[index].trim() != '*** End Patch') {
        final hunkLine = lines[index];
        if (hunkLine == r'\ No newline at end of file') {
          index++;
          continue;
        }
        if (hunkLine.isEmpty || !' +-'.contains(hunkLine[0])) {
          throw ToolFailure('Invalid update patch line for $path: $hunkLine');
        }
        final value = hunkLine.substring(1);
        if (hunkLine[0] != '+') oldLines.add(value);
        if (hunkLine[0] != '-') newLines.add(value);
        index++;
      }
      final start = oldLines.isEmpty
          ? cursor
          : _findBlock(current, oldLines, cursor);
      if (start < 0) {
        throw ToolFailure('Patch context not found for $path');
      }
      current.replaceRange(start, start + oldLines.length, newLines);
      cursor = start + newLines.length;
    }
    if (hunkCount == 0) {
      throw ToolFailure('Update patch for $path has no hunks');
    }
    final content = current.join('\n') + (hadTrailingNewline ? '\n' : '');
    return (content: content, nextIndex: index);
  }

  ({String content, int nextIndex}) _parseAddedFile(
    String path,
    List<String> lines,
    int index,
  ) {
    final contentLines = <String>[];
    while (index < lines.length &&
        !lines[index].startsWith('*** ') &&
        lines[index].trim() != '*** End Patch') {
      final line = lines[index];
      if (line.isEmpty || !line.startsWith('+')) {
        throw ToolFailure('Added file lines must start with + for $path');
      }
      contentLines.add(line.substring(1));
      index++;
    }
    return (content: '${contentLines.join('\n')}\n', nextIndex: index);
  }

  List<String> _contentLines(String content) {
    final lines = content.split('\n');
    if (content.endsWith('\n')) lines.removeLast();
    return lines;
  }

  int _findBlock(List<String> content, List<String> block, int from) {
    if (block.isEmpty) return from;
    for (var start = from; start + block.length <= content.length; start++) {
      var matches = true;
      for (var offset = 0; offset < block.length; offset++) {
        if (content[start + offset] != block[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) return start;
    }
    return -1;
  }
}
