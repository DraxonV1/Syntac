// PDF binary and FlateDecode text extractor.

import 'dart:convert';
import 'dart:io';

class PdfParser {
  const PdfParser._();

  static bool isPdfPath(String path) => path.toLowerCase().endsWith('.pdf');

  static bool isPdfBytes(List<int> bytes) {
    if (bytes.length < 4) return false;
    if (bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return true; // %PDF
    }
    // Check first 1024 bytes
    final limit = bytes.length < 1024 ? bytes.length : 1024;
    for (var i = 0; i < limit - 4; i++) {
      if (bytes[i] == 0x25 &&
          bytes[i + 1] == 0x50 &&
          bytes[i + 2] == 0x44 &&
          bytes[i + 3] == 0x46) {
        return true;
      }
    }
    return false;
  }

  static String extractText(List<int> bytes) {
    final lines = extractTextLines(bytes);
    return lines.join('\n');
  }

  static List<String> extractTextLines(List<int> bytes) {
    final rawString = latin1.decode(bytes);
    final streams = _extractStreams(bytes, rawString);
    final pages = <List<String>>[];
    var currentPageLines = <String>[];

    for (final stream in streams) {
      final textLines = _extractTextFromStream(stream.content);
      if (textLines.isEmpty) continue;
      if (stream.isPageBoundary && currentPageLines.isNotEmpty) {
        pages.add(currentPageLines);
        currentPageLines = <String>[];
      }
      currentPageLines.addAll(textLines);
    }

    if (currentPageLines.isNotEmpty) {
      pages.add(currentPageLines);
    }

    if (pages.isEmpty) {
      // Fallback: search for any visible literal strings in uncompressed dictionary/objects
      final fallbackLines = _fallbackExtract(rawString);
      return fallbackLines.isNotEmpty
          ? fallbackLines
          : const ['[PDF: No text content found or scanned document]'];
    }

    if (pages.length == 1) {
      return pages.single;
    }

    final formatted = <String>[];
    for (var p = 0; p < pages.length; p++) {
      formatted.add('--- Page ${p + 1} ---');
      formatted.addAll(pages[p]);
      if (p < pages.length - 1) {
        formatted.add('');
      }
    }
    return formatted;
  }

  static List<_PdfStream> _extractStreams(List<int> bytes, String raw) {
    final streams = <_PdfStream>[];
    final streamKeyword = 'stream';
    final endStreamKeyword = 'endstream';

    var searchPos = 0;
    while (searchPos < raw.length) {
      final streamIdx = raw.indexOf(streamKeyword, searchPos);
      if (streamIdx == -1) break;

      // Ensure 'stream' is a keyword, not part of another word
      final before = streamIdx > 0 ? raw.codeUnitAt(streamIdx - 1) : 32;
      if (before != 10 && before != 13 && before != 32 && before != 62) {
        searchPos = streamIdx + 6;
        continue;
      }

      // Check dictionary preceding stream
      final dictStart = raw.lastIndexOf('<<', streamIdx);
      final dict = dictStart != -1 && dictStart < streamIdx
          ? raw.substring(dictStart, streamIdx)
          : '';

      // Skip newlines after 'stream'
      var startData = streamIdx + streamKeyword.length;
      if (startData < bytes.length && bytes[startData] == 13) startData++;
      if (startData < bytes.length && bytes[startData] == 10) startData++;

      final endStreamIdx = raw.indexOf(endStreamKeyword, startData);
      if (endStreamIdx == -1) break;

      var endData = endStreamIdx;
      if (endData > startData && bytes[endData - 1] == 10) endData--;
      if (endData > startData && bytes[endData - 1] == 13) endData--;

      if (startData <= endData && endData <= bytes.length) {
        final streamBytes = bytes.sublist(startData, endData);
        final isFlate = dict.contains('/FlateDecode');
        final isPage = dict.contains('/Page');

        String content = '';
        if (isFlate) {
          try {
            final decompressed = zlib.decode(streamBytes);
            content = latin1.decode(decompressed);
          } catch (_) {
            // Not a valid zlib stream or image stream
          }
        } else {
          content = latin1.decode(streamBytes);
        }

        if (content.isNotEmpty) {
          streams.add(_PdfStream(content: content, isPageBoundary: isPage));
        }
      }

      searchPos = endStreamIdx + endStreamKeyword.length;
    }

    return streams;
  }

  static List<String> _extractTextFromStream(String content) {
    final lines = <String>[];
    var currentLine = <String>[];

    // Find all BT ... ET (Begin Text ... End Text) sections
    final btRegex = RegExp(r'BT([\s\S]*?)ET');
    for (final btMatch in btRegex.allMatches(content)) {
      final block = btMatch.group(1)!;

      // Match PDF text operators:
      // - (text) Tj, ' or "
      // - [array] TJ
      // - <hex> Tj, ' or "
      // - T*, Td, TD (line breaks)
      final opRegex = RegExp(
        r'''\((?:\\\(|\\\)|[^)])*\)\s*(?:Tj|'|")|\[(?:[^\]]*)\]\s*TJ|<[0-9a-fA-F\s]+>\s*(?:Tj|'|")|T\*|(?:\-?\d+(?:\.\d+)?\s+){2}(?:Td|TD)''',
      );

      for (final m in opRegex.allMatches(block)) {
        final token = m.group(0)!.trim();

        if (token == 'T*' || token.endsWith('Td') || token.endsWith('TD')) {
          if (currentLine.isNotEmpty) {
            final joined = currentLine.join('').trim();
            if (joined.isNotEmpty) lines.add(joined);
            currentLine = <String>[];
          }
        } else if (token.endsWith('TJ')) {
          final openBracket = token.indexOf('[');
          final closeBracket = token.lastIndexOf(']');
          if (openBracket != -1 && closeBracket != -1) {
            final inner = token.substring(openBracket + 1, closeBracket);
            final strRegex = RegExp(
              r'''\((?:\\\(|\\\)|[^)])*\)|<[0-9a-fA-F\s]+>''',
            );
            final seg = StringBuffer();
            for (final sm in strRegex.allMatches(inner)) {
              final s = sm.group(0)!;
              if (s.startsWith('(') && s.endsWith(')')) {
                seg.write(_unescapePdfString(s.substring(1, s.length - 1)));
              } else if (s.startsWith('<') && s.endsWith('>')) {
                seg.write(_decodeHex(s.substring(1, s.length - 1)));
              }
            }
            if (seg.isNotEmpty) currentLine.add(seg.toString());
          }
        } else if (token.endsWith('Tj') ||
            token.endsWith("'") ||
            token.endsWith('"')) {
          if (token.startsWith('(')) {
            final endParen = token.lastIndexOf(')');
            if (endParen > 1) {
              currentLine.add(_unescapePdfString(token.substring(1, endParen)));
            }
          } else if (token.startsWith('<')) {
            final endHex = token.lastIndexOf('>');
            if (endHex > 1) {
              currentLine.add(_decodeHex(token.substring(1, endHex)));
            }
          }
          if (token.endsWith("'") || token.endsWith('"')) {
            if (currentLine.isNotEmpty) {
              final joined = currentLine.join('').trim();
              if (joined.isNotEmpty) lines.add(joined);
              currentLine = <String>[];
            }
          }
        }
      }

      if (currentLine.isNotEmpty) {
        final joined = currentLine.join('').trim();
        if (joined.isNotEmpty) lines.add(joined);
        currentLine = <String>[];
      }
    }

    return lines;
  }

  static String _unescapePdfString(String s) {
    if (s.startsWith('\xFE\xFF') ||
        (s.length >= 2 && s.codeUnitAt(0) == 0xFE && s.codeUnitAt(1) == 0xFF)) {
      // UTF-16BE encoded string
      final codeUnits = <int>[];
      for (var i = 2; i < s.length - 1; i += 2) {
        codeUnits.add((s.codeUnitAt(i) << 8) | s.codeUnitAt(i + 1));
      }
      return String.fromCharCodes(codeUnits);
    }

    return s
        .replaceAllMapped(RegExp(r'\\([0-7]{1,3})'), (m) {
          final octal = int.parse(m.group(1)!, radix: 8);
          return String.fromCharCode(octal);
        })
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\b', '\b')
        .replaceAll(r'\f', '\f')
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll(r'\\', r'\');
  }

  static String _decodeHex(String rawHex) {
    final clean = rawHex.replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) return '';
    final hex = clean.length % 2 != 0 ? '${clean}0' : clean;

    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      final b = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (b != null) bytes.add(b);
    }

    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      // UTF-16BE
      final codeUnits = <int>[];
      for (var i = 2; i < bytes.length - 1; i += 2) {
        codeUnits.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(codeUnits);
    }

    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static List<String> _fallbackExtract(String raw) {
    final matches = RegExp(r'\(([^)]{4,})\)\s*Tj').allMatches(raw);
    final lines = <String>[];
    for (final m in matches) {
      final text = _unescapePdfString(m.group(1)!).trim();
      if (text.isNotEmpty) lines.add(text);
    }
    return lines;
  }
}

class _PdfStream {
  const _PdfStream({required this.content, required this.isPageBoundary});

  final String content;
  final bool isPageBoundary;
}
