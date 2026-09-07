// Search bounded project filenames and text content.

import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'package:path/path.dart' as p;

import 'tool_context.dart';

mixin SearchTool on ToolContext {
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
      await resolvePath(path == null || path.isEmpty ? '.' : path),
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
          !includeGlobs.any((glob) => matchesGlob(normalizedRel, glob))) {
        skippedByInclude++;
        continue;
      }
      if (excludeGlobs != null &&
          excludeGlobs.any((glob) => matchesGlob(normalizedRel, glob))) {
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
          if (looksBinary(bytes)) {
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
}
