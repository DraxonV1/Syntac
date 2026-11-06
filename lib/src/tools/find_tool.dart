// Semantic code and behavior search tool matching omp's find contract.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'pdf_parser.dart';
import 'tool_context.dart';

mixin FindTool on ToolContext {
  static const _stopwords = {
    'a',
    'an',
    'and',
    'are',
    'as',
    'at',
    'be',
    'by',
    'for',
    'from',
    'has',
    'he',
    'in',
    'is',
    'it',
    'its',
    'of',
    'on',
    'that',
    'the',
    'to',
    'was',
    'were',
    'will',
    'with',
    'how',
    'do',
    'i',
    'get',
    'can',
    'what',
    'when',
    'where',
    'which',
    'who',
    'why',
    'this',
    'find',
    'search',
  };

  Future<Map<String, Object?>> findBehavior({
    required String query,
    List<String> grepKeywords = const [],
    String? path,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      throw ToolFailure('query must be a non-empty description');
    }

    final root = p.normalize(p.absolute(projectRoot));
    final scope = (path == null || path.trim().isEmpty)
        ? root
        : p.normalize(p.join(root, path.trim()));

    // Tokenize query into significant terms
    final queryTokens = _tokenize(cleanQuery)
        .where((t) => !_stopwords.contains(t.toLowerCase()) && t.length > 1)
        .map((t) => t.toLowerCase())
        .toSet();

    final verbatimKeywords = grepKeywords
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList(growable: false);

    final hits = <_FindHit>[];
    final scopeDir = Directory(scope);
    final scopeFile = File(scope);

    final filesToScan = <File>[];
    if (await scopeFile.exists()) {
      filesToScan.add(scopeFile);
    } else if (await scopeDir.exists()) {
      await for (final entity in scopeDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          final rel = p.relative(entity.path, from: root).replaceAll('\\', '/');
          final parts = rel.split('/');
          if (parts.contains('.git') ||
              parts.contains('.dart_tool') ||
              parts.contains('build') ||
              parts.contains('.gradle')) {
            continue;
          }
          filesToScan.add(entity);
        }
      }
    }

    for (final file in filesToScan) {
      final rel = p.relative(file.path, from: root).replaceAll('\\', '/');

      List<String> lines;
      try {
        final length = await file.length();
        if (length > maxReadBytes * 10) continue;
        final bytes = await file.readAsBytes();

        if (PdfParser.isPdfPath(rel) || PdfParser.isPdfBytes(bytes)) {
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

      if (lines.isEmpty) continue;

      // Score file passages with sliding window
      final windowSize = 20;
      for (var i = 0; i < lines.length; i += 10) {
        final startLine = i + 1;
        final endLine = min(i + windowSize, lines.length);
        final passage = lines.sublist(i, endLine).join('\n');
        final passageLower = passage.toLowerCase();

        var score = 0.0;
        // 1. Verbatim keywords bonus
        for (final kw in verbatimKeywords) {
          if (passage.contains(kw)) {
            score += 0.40;
          } else if (passageLower.contains(kw.toLowerCase())) {
            score += 0.25;
          }
        }

        // 2. Query token matches
        var tokenMatches = 0;
        for (final token in queryTokens) {
          if (passageLower.contains(token)) {
            tokenMatches++;
          }
        }
        if (queryTokens.isNotEmpty) {
          score += (tokenMatches / queryTokens.length) * 0.50;
        }

        // 3. Filename match bonus
        final relLower = rel.toLowerCase();
        for (final token in queryTokens) {
          if (relLower.contains(token)) {
            score += 0.15;
            break;
          }
        }

        final normalizedScore = score.clamp(0.0, 1.0);
        if (normalizedScore >= 0.30) {
          final firstLineText = lines[i].trim();
          final preview = firstLineText.length > 100
              ? '${firstLineText.substring(0, 97)}...'
              : firstLineText;

          hits.add(
            _FindHit(
              path: rel,
              startLine: startLine,
              endLine: endLine,
              score: double.parse(normalizedScore.toStringAsFixed(2)),
              snippet: preview,
            ),
          );
        }
      }
    }

    // Sort hits strongest first
    hits.sort((a, b) => b.score.compareTo(a.score));

    // Limit to top 25 hits
    final topHits = hits.take(25).toList(growable: false);
    final buffer = StringBuffer();
    for (final hit in topHits) {
      buffer.writeln(
        '${hit.path}:${hit.startLine}-${hit.endLine} ${hit.score.toStringAsFixed(2)} ${hit.snippet}',
      );
    }

    final formatted = buffer.toString().trim();
    return {
      'query': cleanQuery,
      'grep_keywords': grepKeywords,
      'path': path ?? '.',
      'hits': topHits
          .map(
            (h) => {
              'path': h.path,
              'startLine': h.startLine,
              'endLine': h.endLine,
              'score': h.score,
              'snippet': h.snippet,
            },
          )
          .toList(growable: false),
      'totalHits': topHits.length,
      'content': formatted.isNotEmpty ? formatted : 'No behavior matches found',
    };
  }

  List<String> _tokenize(String text) {
    return text
        .split(RegExp(r'[^a-zA-Z0-9_\-\.]+'))
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
  }
}

class _FindHit {
  const _FindHit({
    required this.path,
    required this.startLine,
    required this.endLine,
    required this.score,
    required this.snippet,
  });

  final String path;
  final int startLine;
  final int endLine;
  final double score;
  final String snippet;
}
