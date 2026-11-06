// Regex search tool matching omp's grep contract across workspace files and PDFs.

import 'dart:convert';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import '../models.dart';
import 'pdf_parser.dart';
import 'tool_context.dart';

mixin GrepTool on ToolContext {
  static const defaultFileLimit = 20;
  static const multiFilePerFileMatches = 20;

  Future<Map<String, Object?>> grep({
    required String pattern,
    String? path,
    bool caseSensitive = true,
    bool gitignore = true,
    int? skip,
  }) async {
    final cleanPattern = pattern.trim();
    if (cleanPattern.isEmpty) {
      throw ToolFailure('Grep pattern is required');
    }

    final RegExp regex;
    try {
      regex = RegExp(
        cleanPattern,
        caseSensitive: caseSensitive,
        multiLine: true,
      );
    } on FormatException catch (e) {
      throw ToolFailure('Invalid regex pattern: ${e.message}');
    }

    final root = p.normalize(p.absolute(projectRoot));
    final rawPath = (path == null || path.trim().isEmpty) ? '.' : path.trim();
    final pathSpecs = rawPath
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final skipFiles = (skip ?? 0).clamp(0, 1 << 30);
    final matchedFiles = <String>[];
    final allMatches = <Map<String, Object?>>[];
    final buffer = StringBuffer();
    var filesEncountered = 0;
    var totalMatches = 0;
    var hasMore = false;

    // Resolve target files
    final targetFiles = await _resolveGrepFiles(pathSpecs, root, gitignore);

    for (final fileInfo in targetFiles) {
      final relPath = fileInfo.relPath;
      final file = fileInfo.file;
      final lineSelector = fileInfo.lineSelector;

      List<String> lines;
      try {
        final length = await file.length();
        if (length > maxReadBytes * 10) continue;
        final bytes = await file.readAsBytes();

        if (PdfParser.isPdfPath(relPath) || PdfParser.isPdfBytes(bytes)) {
          lines = PdfParser.extractTextLines(bytes);
        } else if (looksBinary(bytes)) {
          continue;
        } else {
          lines = const LineSplitter().convert(
            utf8.decode(bytes, allowMalformed: true),
          );
        }
      } catch (_) {
        continue;
      }

      final fileMatches = <Map<String, Object?>>[];
      for (var i = 0; i < lines.length; i++) {
        final lineNum = i + 1;
        if (lineSelector != null && !lineSelector.contains(lineNum)) continue;

        final line = lines[i];
        final match = regex.firstMatch(line);
        if (match != null) {
          totalMatches++;
          if (fileMatches.length < multiFilePerFileMatches) {
            fileMatches.add({
              'path': relPath,
              'line': lineNum,
              'column': match.start + 1,
              'text': truncatePersistedText(line, maxLength: 500),
            });
          }
        }
      }

      if (fileMatches.isNotEmpty) {
        filesEncountered++;
        if (filesEncountered <= skipFiles) continue;
        if (matchedFiles.length >= defaultFileLimit) {
          hasMore = true;
          break;
        }

        matchedFiles.add(relPath);
        allMatches.addAll(fileMatches);
        for (final m in fileMatches) {
          buffer.writeln('${m['path']}:${m['line']}: ${m['text']}');
        }
      }
    }

    final formatted = buffer.toString().trim();
    return {
      'pattern': cleanPattern,
      'path': rawPath,
      'case': caseSensitive,
      'skip': skipFiles,
      'filesCount': matchedFiles.length,
      'totalMatches': totalMatches,
      'hasMore': hasMore,
      if (hasMore) 'nextSkip': skipFiles + matchedFiles.length,
      'matches': allMatches,
      'content': formatted.isNotEmpty ? formatted : 'No matches found',
    };
  }

  Future<List<_GrepTargetFile>> _resolveGrepFiles(
    List<String> specs,
    String root,
    bool gitignore,
  ) async {
    final targets = <_GrepTargetFile>[];
    final seen = <String>{};

    for (final spec in specs) {
      // Check for line range selector like path/file.dart:10-50
      final colonMatch = RegExp(r'^(.*?):(\d+)(?:-(\d+))?$').firstMatch(spec);
      final cleanPath = colonMatch != null ? colonMatch.group(1)! : spec;
      Set<int>? lineRange;
      if (colonMatch != null) {
        final start = int.parse(colonMatch.group(2)!);
        final end = colonMatch.group(3) != null
            ? int.parse(colonMatch.group(3)!)
            : start;
        lineRange = {for (var i = start; i <= end; i++) i};
      }

      if (cleanPath.contains('*') || cleanPath.contains('?')) {
        final glob = Glob(cleanPath, recursive: cleanPath.contains('**'));
        await for (final entity in glob.list(root: root, followLinks: false)) {
          if (entity is File) {
            final rel = p
                .relative(entity.path, from: root)
                .replaceAll('\\', '/');
            if (_shouldSkipPath(rel, gitignore) || seen.contains(rel)) continue;
            seen.add(rel);
            targets.add(
              _GrepTargetFile(
                relPath: rel,
                file: File(entity.path),
                lineSelector: lineRange,
              ),
            );
          }
        }
      } else {
        final targetPath = p.normalize(p.join(root, cleanPath));
        final type = await FileSystemEntity.type(
          targetPath,
          followLinks: false,
        );
        if (type == FileSystemEntityType.file) {
          final rel = p.relative(targetPath, from: root).replaceAll('\\', '/');
          if (!seen.contains(rel)) {
            seen.add(rel);
            targets.add(
              _GrepTargetFile(
                relPath: rel,
                file: File(targetPath),
                lineSelector: lineRange,
              ),
            );
          }
        } else if (type == FileSystemEntityType.directory) {
          await for (final entity in Directory(
            targetPath,
          ).list(recursive: true, followLinks: false)) {
            if (entity is File) {
              final rel = p
                  .relative(entity.path, from: root)
                  .replaceAll('\\', '/');
              if (_shouldSkipPath(rel, gitignore) || seen.contains(rel)) {
                continue;
              }
              seen.add(rel);
              targets.add(
                _GrepTargetFile(
                  relPath: rel,
                  file: File(entity.path),
                  lineSelector: lineRange,
                ),
              );
            }
          }
        }
      }
    }

    return targets;
  }

  bool _shouldSkipPath(String rel, bool gitignore) {
    final parts = rel.split('/');
    if (gitignore &&
        (parts.contains('.git') ||
            parts.contains('.dart_tool') ||
            parts.contains('build') ||
            parts.contains('.gradle'))) {
      return true;
    }
    return false;
  }
}

class _GrepTargetFile {
  const _GrepTargetFile({
    required this.relPath,
    required this.file,
    this.lineSelector,
  });

  final String relPath;
  final File file;
  final Set<int>? lineSelector;
}
