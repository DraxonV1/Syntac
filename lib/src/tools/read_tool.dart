// Read project files and inspect attached images with bounded metadata.

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;

import 'package:path/path.dart' as p;

import 'tool_context.dart';
import 'file_snapshot.dart';

mixin ReadTool on ToolContext {
  Future<Map<String, Object?>> readFile(
    String inputPath, {
    int? offset,
    int? limit,
    int? startLine,
    int? endLine,
    String? unit,
    bool raw = false,
    bool includeImage = false,
    bool systemwide = false,
  }) async {
    final trimmed = inputPath.trim();
    if (_isWebUrl(trimmed)) {
      return _readWebUrl(
        trimmed,
        offset: offset,
        limit: limit,
        startLine: startLine,
        endLine: endLine,
        unit: unit,
        raw: raw,
        includeImage: includeImage,
      );
    }
    final attachedPath = inputPath.startsWith('local://')
        ? null
        : await resolveAttachedAbsolutePath(inputPath);
    final path = inputPath.startsWith('local://')
        ? await resolveLocalPath(inputPath)
        : attachedPath ??
              (systemwide
                  ? await resolveSystemPath(inputPath)
                  : await resolvePath(inputPath));
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) {
      throw ToolFailure('File does not exist: $inputPath');
    }
    if (type == FileSystemEntityType.directory) {
      throw ToolFailure('Path is a directory, not a file: $inputPath');
    }
    final file = File(path);
    final length = await file.length();
    final imageMimeType = imageMimeTypeFor(path);
    if (imageMimeType != null) {
      return imageMetadata(
        inputPath,
        file,
        length,
        imageMimeType,
        includeImage: includeImage,
      );
    }
    final snapshotBytes = length <= maxPatchFileBytes
        ? await readPatchBytes(file)
        : null;
    final snapshot = snapshotBytes == null ? null : fileSnapshot(snapshotBytes);
    final readUnit = (unit ?? 'line').toLowerCase();
    if (readUnit == 'byte') {
      final start = (offset ?? 0).clamp(0, length).toInt();
      final requested = limit ?? maxReadBytes;
      final safeLimit = requested.clamp(0, maxReadBytes).toInt();
      final end = (start + safeLimit).clamp(start, length).toInt();
      final raf = await file.open();
      try {
        await raf.setPosition(start);
        final bytes = snapshotBytes == null
            ? await raf.read(end - start)
            : snapshotBytes.sublist(
                start.clamp(0, snapshotBytes.length),
                end.clamp(0, snapshotBytes.length),
              );
        if (!raw && looksBinary(bytes)) {
          throw ToolFailure('Byte range appears to be binary: $inputPath');
        }
        return {
          'path': inputPath,
          'snapshot': ?snapshot,
          'bytes': length,
          'unit': 'byte',
          'startByte': start,
          'endByteExclusive': end,
          'content': utf8.decode(bytes, allowMalformed: true),
          'truncated': requested > safeLimit || end < length,
        };
      } finally {
        await raf.close();
      }
    }
    if (readUnit != 'line') throw ToolFailure('Unsupported read unit: $unit');
    final start = (startLine ?? offset ?? 1).clamp(1, 1 << 30).toInt();
    final requestedEndInput =
        endLine ?? (limit == null ? null : start + limit - 1);
    if (requestedEndInput != null && requestedEndInput < start) {
      throw ToolFailure('endLine must be greater than or equal to startLine');
    }
    final requestedEnd = requestedEndInput == null
        ? start + ToolContext.maxReadLines - 1
        : requestedEndInput
              .clamp(start, start + ToolContext.maxReadLines - 1)
              .toInt();
    final selected = <String>[];
    var totalLines = 0;
    var selectedBytes = 0;
    var truncated = false;
    await for (final line
        in (snapshotBytes == null
                ? file.openRead()
                : Stream<List<int>>.value(snapshotBytes))
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      totalLines++;
      if (totalLines < start) continue;
      if (totalLines > requestedEnd) continue;
      if (truncated) continue;
      final lineBytes = utf8.encode(line).length + 1;
      if (selectedBytes + lineBytes > maxReadBytes) {
        truncated = true;
        continue;
      }
      selected.add(line);
      selectedBytes += lineBytes;
    }
    final end = selected.isEmpty ? start - 1 : start + selected.length - 1;
    final requestedLimit = requestedEnd - start + 1;
    final hasMore = end < totalLines;
    return {
      'path': inputPath,
      'snapshot': ?snapshot,
      'bytes': length,
      'unit': 'line',
      'startLine': start,
      'endLine': end,
      'totalLines': totalLines,
      'content': selected.join('\n'),
      'truncated': truncated || hasMore,
      'contentTruncated': truncated || hasMore,
      'hasMore': hasMore,
      'requestedLines': requestedLimit,
      if (hasMore) 'nextStartLine': end + 1,
      if (hasMore)
        'notice':
            'Output truncated at ${ToolContext.maxReadLines} lines. Read again with startLine ${end + 1} (or :${end + 1}) to continue.',
    };
  }

  Future<Map<String, Object?>> displayImage(String inputPath) async {
    final result = await readFile(inputPath);
    if (result['kind'] != 'image') {
      throw ToolFailure('Not an image file: $inputPath');
    }
    return {...result, 'displayImage': true};
  }

  String? imageMimeTypeFor(String path) {
    return switch (p.extension(path).toLowerCase()) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.bmp' => 'image/bmp',
      '.tif' || '.tiff' => 'image/tiff',
      _ => null,
    };
  }

  Future<Map<String, Object?>> imageMetadata(
    String inputPath,
    File file,
    int length,
    String mimeType, {
    required bool includeImage,
  }) async {
    final bytes = await file
        .openRead(0, minInt(length, 64))
        .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
    final dimensions = imageDimensions(bytes, mimeType);
    final result = <String, Object?>{
      'path': inputPath,
      'filePath': file.path,
      'kind': 'image',
      'mimeType': mimeType,
      'bytes': length,
      'width': dimensions?.$1,
      'height': dimensions?.$2,
      'readable': true,
      'imageUri': inputPath,
    };
    if (includeImage && length <= ToolContext.maxInlineImageBytes) {
      result['imageDataUri'] =
          'data:$mimeType;base64,${base64Encode(await file.readAsBytes())}';
    } else if (includeImage) {
      result['imageDataOmitted'] = true;
      result['imageDataLimitBytes'] = ToolContext.maxInlineImageBytes;
    }
    return result;
  }

  (int, int)? imageDimensions(List<int> bytes, String mimeType) {
    int u16(int offset, {bool littleEndian = false}) {
      if (offset + 2 > bytes.length) return 0;
      return littleEndian
          ? bytes[offset] | bytes[offset + 1] << 8
          : bytes[offset] << 8 | bytes[offset + 1];
    }

    int u24(int offset) {
      if (offset + 3 > bytes.length) return 0;
      return bytes[offset] | bytes[offset + 1] << 8 | bytes[offset + 2] << 16;
    }

    int u32(int offset) {
      if (offset + 4 > bytes.length) return 0;
      return bytes[offset] << 24 |
          bytes[offset + 1] << 16 |
          bytes[offset + 2] << 8 |
          bytes[offset + 3];
    }

    if (mimeType == 'image/png' &&
        bytes.length >= 24 &&
        bytes.sublist(0, 8).join(',') ==
            const [137, 80, 78, 71, 13, 10, 26, 10].join(',')) {
      return (u32(16), u32(20));
    }
    if (mimeType == 'image/gif' && bytes.length >= 10) {
      return (u16(6, littleEndian: true), u16(8, littleEndian: true));
    }
    if (mimeType == 'image/webp' &&
        bytes.length >= 30 &&
        String.fromCharCodes(bytes.sublist(12, 16)) == 'VP8X') {
      return (1 + u24(24), 1 + u24(27));
    }
    if (mimeType == 'image/jpeg' && bytes.length >= 4) {
      var offset = 2;
      while (offset + 8 < bytes.length) {
        if (bytes[offset] != 0xff) {
          offset++;
          continue;
        }
        final marker = bytes[offset + 1];
        offset += 2;
        if (marker == 0xd8 || marker == 0xd9) continue;
        final segmentLength = u16(offset);
        if (segmentLength < 2 || offset + segmentLength > bytes.length) break;
        final isFrame =
            (marker >= 0xc0 && marker <= 0xc3) ||
            (marker >= 0xc5 && marker <= 0xc7) ||
            (marker >= 0xc9 && marker <= 0xcb) ||
            (marker >= 0xcd && marker <= 0xcf);
        if (isFrame && offset + 7 < bytes.length) {
          return (u16(offset + 5), u16(offset + 3));
        }
        offset += segmentLength;
      }
    }
    return null;
  }

  bool _isWebUrl(String path) {
    final lower = path.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  Future<Map<String, Object?>> _readWebUrl(
    String url, {
    int? offset,
    int? limit,
    int? startLine,
    int? endLine,
    String? unit,
    bool raw = false,
    bool includeImage = false,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      throw ToolFailure('Invalid web URL: $url');
    }

    final http.Response response;
    try {
      response = await httpClient
          .get(
            uri,
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,text/plain,*/*;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 30));
    } on SocketException catch (e) {
      throw ToolFailure('Failed to connect to $url: ${e.message}');
    } on TimeoutException {
      throw ToolFailure('Timed out fetching $url after 30 seconds');
    } catch (e) {
      throw ToolFailure('Failed to fetch $url: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ToolFailure('Failed to fetch $url: HTTP ${response.statusCode}');
    }

    final contentType = response.headers['content-type'] ?? '';
    final mime = contentType.split(';').first.trim().toLowerCase();

    if (mime.startsWith('image/')) {
      final bytes = response.bodyBytes;
      final dims = imageDimensions(bytes, mime);
      return {
        'path': url,
        'kind': 'image',
        'mimeType': mime,
        'bytes': bytes.length,
        if (dims != null) 'width': dims.$1,
        if (dims != null) 'height': dims.$2,
        if (includeImage && bytes.length <= ToolContext.maxInlineImageBytes)
          'base64': base64Encode(bytes),
      };
    }

    String contentText;
    if (raw) {
      contentText = response.body;
    } else if (mime.contains('html') || _looksLikeHtml(response.body)) {
      contentText = _convertHtmlToMarkdown(response.body, baseUrl: uri);
    } else {
      contentText = response.body;
    }

    final bytes = utf8.encode(contentText);
    final length = bytes.length;
    final snapshot = length <= maxPatchFileBytes ? fileSnapshot(bytes) : null;
    final readUnit = (unit ?? 'line').toLowerCase();

    if (readUnit == 'byte') {
      final start = (offset ?? 0).clamp(0, length).toInt();
      final requested = limit ?? maxReadBytes;
      final safeLimit = requested.clamp(0, maxReadBytes).toInt();
      final end = (start + safeLimit).clamp(start, length).toInt();
      final slice = bytes.sublist(start, end);
      return {
        'path': url,
        'snapshot': ?snapshot,
        'bytes': length,
        'unit': 'byte',
        'startByte': start,
        'endByteExclusive': end,
        'content': utf8.decode(slice, allowMalformed: true),
        'truncated': requested > safeLimit || end < length,
      };
    }

    if (readUnit != 'line') throw ToolFailure('Unsupported read unit: $unit');
    final start = (startLine ?? offset ?? 1).clamp(1, 1 << 30).toInt();
    final requestedEndInput =
        endLine ?? (limit == null ? null : start + limit - 1);
    if (requestedEndInput != null && requestedEndInput < start) {
      throw ToolFailure('endLine must be greater than or equal to startLine');
    }
    final requestedEnd = requestedEndInput == null
        ? start + ToolContext.maxReadLines - 1
        : requestedEndInput
              .clamp(start, start + ToolContext.maxReadLines - 1)
              .toInt();

    final lines = const LineSplitter().convert(contentText);
    final totalLines = lines.length;
    final selected = <String>[];
    var selectedBytes = 0;
    var truncated = false;

    for (var i = 0; i < totalLines; i++) {
      final lineNum = i + 1;
      if (lineNum < start) continue;
      if (lineNum > requestedEnd) continue;
      if (truncated) continue;
      final line = lines[i];
      final lineBytes = utf8.encode(line).length + 1;
      if (selectedBytes + lineBytes > maxReadBytes) {
        truncated = true;
        continue;
      }
      selected.add(line);
      selectedBytes += lineBytes;
    }

    final end = selected.isEmpty ? start - 1 : start + selected.length - 1;
    final requestedLimit = requestedEnd - start + 1;
    final hasMore = end < totalLines;
    return {
      'path': url,
      'snapshot': ?snapshot,
      'bytes': length,
      'unit': 'line',
      'startLine': start,
      'endLine': end,
      'totalLines': totalLines,
      'content': selected.join('\n'),
      'truncated': truncated || hasMore,
      'contentTruncated': truncated || hasMore,
      'hasMore': hasMore,
      'requestedLines': requestedLimit,
      if (hasMore) 'nextStartLine': end + 1,
      if (hasMore)
        'notice':
            'Output truncated at ${ToolContext.maxReadLines} lines. Read again with startLine ${end + 1} (or :${end + 1}) to continue.',
    };
  }

  bool _looksLikeHtml(String text) {
    final prefix = text.trimLeft().toLowerCase();
    return prefix.startsWith('<!doctype') ||
        prefix.startsWith('<html') ||
        prefix.startsWith('<head') ||
        prefix.startsWith('<body');
  }

  String _convertHtmlToMarkdown(String html, {Uri? baseUrl}) {
    var text = html
        .replaceAll(
          RegExp(r'<script\b[^>]*>[\s\S]*?<\/script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<style\b[^>]*>[\s\S]*?<\/style>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'<noscript\b[^>]*>[\s\S]*?<\/noscript>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'<svg\b[^>]*>[\s\S]*?<\/svg>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    String? title;
    final titleMatch = RegExp(
      r'<title\b[^>]*>([\s\S]*?)<\/title>',
      caseSensitive: false,
    ).firstMatch(text);
    if (titleMatch != null) {
      title = _decodeHtmlEntities(titleMatch.group(1)!.trim());
    }

    for (var i = 1; i <= 6; i++) {
      final prefix = '#' * i;
      text = text.replaceAllMapped(
        RegExp('<h$i\\b[^>]*>([\\s\\S]*?)<\\/h$i>', caseSensitive: false),
        (m) =>
            '\n\n$prefix ${_decodeHtmlEntities(_stripTags(m.group(1)!)).trim()}\n\n',
      );
    }

    text = text.replaceAllMapped(
      RegExp(
        r'''<a\b[^>]*\bhref\s*=\s*(?:["']([^"']*)["'])[^>]*>([\s\S]*?)<\/a>''',
        caseSensitive: false,
      ),
      (m) {
        var href = (m.group(1) ?? '').trim();
        final linkText = _decodeHtmlEntities(_stripTags(m.group(2)!)).trim();
        if (linkText.isEmpty) return '';
        if (href.startsWith('/') && baseUrl != null) {
          href = baseUrl.resolve(href).toString();
        }
        if (href.startsWith('http://') || href.startsWith('https://')) {
          return '[$linkText]($href)';
        }
        return linkText;
      },
    );

    text = text.replaceAllMapped(
      RegExp(
        r'<pre\b[^>]*><code\b[^>]*>([\s\S]*?)<\/code><\/pre>',
        caseSensitive: false,
      ),
      (m) => '\n\n```\n${_decodeHtmlEntities(m.group(1)!)}\n```\n\n',
    );
    text = text.replaceAllMapped(
      RegExp(r'<pre\b[^>]*>([\s\S]*?)<\/pre>', caseSensitive: false),
      (m) => '\n\n```\n${_decodeHtmlEntities(m.group(1)!)}\n```\n\n',
    );
    text = text.replaceAllMapped(
      RegExp(r'<code\b[^>]*>([\s\S]*?)<\/code>', caseSensitive: false),
      (m) => '`${_decodeHtmlEntities(m.group(1)!)}`',
    );

    text = text.replaceAllMapped(
      RegExp(
        r'<(?:strong|b)\b[^>]*>([\s\S]*?)<\/(?:strong|b)>',
        caseSensitive: false,
      ),
      (m) => '**${_stripTags(m.group(1)!)}**',
    );
    text = text.replaceAllMapped(
      RegExp(r'<(?:em|i)\b[^>]*>([\s\S]*?)<\/(?:em|i)>', caseSensitive: false),
      (m) => '*${_stripTags(m.group(1)!)}*',
    );

    text = text.replaceAllMapped(
      RegExp(r'<li\b[^>]*>([\s\S]*?)<\/li>', caseSensitive: false),
      (m) => '\n- ${_stripTags(m.group(1)!).trim()}',
    );

    text = text.replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), '\n');
    text = text.replaceAllMapped(
      RegExp(r'<p\b[^>]*>([\s\S]*?)<\/p>', caseSensitive: false),
      (m) => '\n\n${m.group(1)!}\n\n',
    );
    text = text.replaceAllMapped(
      RegExp(
        r'<blockquote\b[^>]*>([\s\S]*?)<\/blockquote>',
        caseSensitive: false,
      ),
      (m) => '\n\n> ${_stripTags(m.group(1)!).trim()}\n\n',
    );
    text = text.replaceAll(
      RegExp(
        r'<\/?(?:div|section|article|nav|main|header|footer)\b[^>]*>',
        caseSensitive: false,
      ),
      '\n',
    );

    text = _stripTags(text);
    text = _decodeHtmlEntities(text);

    text = text
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .join('\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    if (title != null && title.isNotEmpty && !text.startsWith('# ')) {
      text = '# $title\n\n$text';
    }
    return text;
  }

  static String _stripTags(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>'), '');

  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '…')
        .replaceAllMapped(
          RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)),
        )
        .replaceAllMapped(
          RegExp(r'&#x([0-9a-fA-F]+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
        );
  }
}
