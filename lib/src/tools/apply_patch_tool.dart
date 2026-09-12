// Apply bounded multi-file patches inside project root.

import 'dart:convert';
import 'dart:io';

import 'tool_context.dart';
import 'file_snapshot.dart';

class _PreparedPatch {
  const _PreparedPatch({
    required this.path,
    required this.operation,
    required this.file,
    required this.content,
    this.original,
  });

  final String path;
  final String operation;
  final File file;
  final String? content;
  final List<int>? original;
}

mixin ApplyPatchTool on ToolContext {
  Future<Map<String, Object?>> applyPatch(
    String patch, {
    Map<String, Object?> expectedSnapshots = const {},
  }) async {
    if (patch.length > maxPatchCharacters) {
      throw ToolFailure(
        'Patch exceeds $maxPatchCharacters characters; split it',
      );
    }
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
        final originalBytes = await readPatchBytes(file);
        _checkSnapshot(path, originalBytes, expectedSnapshots);
        final original = utf8.decode(originalBytes).replaceAll('\r\n', '\n');
        final updated = _applyUpdate(path, original, lines, index + 1);
        prepared.add(
          _PreparedPatch(
            path: path,
            operation: 'update',
            file: file,
            content: updated.content,
            original: originalBytes,
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
        final originalBytes = await readPatchBytes(file);
        _checkSnapshot(path, originalBytes, expectedSnapshots);
        prepared.add(
          _PreparedPatch(
            path: path,
            operation: 'delete',
            file: file,
            content: null,
            original: originalBytes,
          ),
        );
        index++;
        continue;
      }
      throw ToolFailure('Unsupported patch directive: $line');
    }
    if (!sawEnd) throw ToolFailure('Patch must end with *** End Patch');
    if (prepared.isEmpty) throw ToolFailure('Patch contains no file changes');
    if (lines.skip(index + 1).any((line) => line.trim().isNotEmpty)) {
      throw ToolFailure('Unexpected content after *** End Patch');
    }
    final paths = <String>{};
    var originalSize = 0;
    for (final change in prepared) {
      final key = Platform.isWindows
          ? change.file.path.toLowerCase()
          : change.file.path;
      if (!paths.add(key)) {
        throw ToolFailure('Duplicate patch path: ${change.path}');
      }
      originalSize += change.original?.length ?? 0;
      if (prepared.length > 32 || originalSize > 8 * 1024 * 1024) {
        throw ToolFailure('Patch exceeds 32 files or 8 MiB of originals');
      }
      if (change.content != null &&
          utf8.encode(change.content!).length > maxPatchFileBytes) {
        throw ToolFailure(
          'Patched file exceeds $maxPatchFileBytes bytes: ${change.path}',
        );
      }
    }

    // Validate every precondition again before first mutation. In-process rollback
    // protects against write errors; external writers/crashes are not a transaction.
    for (final change in prepared) {
      final resolved = await resolvePath(
        change.path,
        forWrite: change.original == null,
      );
      if (resolved != change.file.path) {
        throw ToolFailure('Patch path changed: ${change.path}');
      }
      if (change.original == null) {
        if (await change.file.exists()) {
          throw ToolFailure('File already exists: ${change.path}');
        }
      } else {
        _checkSnapshot(
          change.path,
          await readPatchBytes(change.file),
          expectedSnapshots,
        );
      }
    }
    final applied = <_PreparedPatch>[];
    try {
      for (final change in prepared) {
        applied.add(change);
        if (change.operation == 'delete') {
          await change.file.delete();
        } else {
          await change.file.parent.create(recursive: true);
          await atomicWriteString(change.file, change.content!);
        }
      }
    } catch (error) {
      final failedRollbacks = <String>[];
      for (final change in applied.reversed) {
        try {
          if (change.original != null) {
            await change.file.writeAsBytes(change.original!, flush: true);
          } else if (await change.file.exists()) {
            await change.file.delete();
          }
        } catch (_) {
          failedRollbacks.add(change.path);
        }
      }
      if (failedRollbacks.isNotEmpty) {
        throw ToolFailure(
          'Patch failed; rollback also failed for: ${failedRollbacks.join(', ')}. Inspect files before retrying.',
        );
      }
      throw ToolFailure('Patch failed; file contents restored: $error');
    }
    final files = prepared
        .map(
          (change) => {
            'path': change.path,
            'operation': change.operation,
            if (change.content != null)
              'bytes': utf8.encode(change.content!).length,
            if (change.content != null)
              'snapshot': fileSnapshot(utf8.encode(change.content!)),
          },
        )
        .toList(growable: false);
    return {
      'files': files,
      'changedFiles': files,
      'fileCount': files.length,
      'diff': normalized.length <= maxPatchDiffCharacters
          ? normalized
          : normalized.substring(0, maxPatchDiffCharacters),
      'diffTruncated': normalized.length > maxPatchDiffCharacters,
    };
  }

  void _checkSnapshot(
    String path,
    List<int> bytes,
    Map<String, Object?> expected,
  ) {
    final snapshot = expected[path];
    if (snapshot is! String || snapshot != fileSnapshot(bytes)) {
      throw ToolFailure(
        'Missing or stale snapshot for $path. Read file again and pass its snapshot in expectedSnapshots.',
      );
    }
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
