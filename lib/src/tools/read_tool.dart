// Read project files and inspect attached images with bounded metadata.

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:path/path.dart' as p;

import 'tool_context.dart';
import 'pdf_parser.dart';
import 'file_snapshot.dart';
import 'web_reader.dart';

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
    final paths = parsePathList(inputPath);
    if (paths.length > 1) {
      return readBulkFiles(
        paths,
        offset: offset,
        limit: limit,
        startLine: startLine,
        endLine: endLine,
        unit: unit,
        raw: raw,
        includeImage: includeImage,
        systemwide: systemwide,
      );
    }
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
    if (PdfParser.isPdfPath(path) ||
        (snapshotBytes != null && PdfParser.isPdfBytes(snapshotBytes))) {
      final pdfBytes = snapshotBytes ?? await file.readAsBytes();
      return _readPdfBytes(
        inputPath,
        pdfBytes,
        offset: offset,
        limit: limit,
        startLine: startLine,
        endLine: endLine,
        unit: unit,
        raw: raw,
      );
    }
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
    final parsedTarget = WebReader.parseUrlTarget(url);
    final targetUrl = parsedTarget.url;
    final effectiveRaw = raw || parsedTarget.raw;

    final WebReadResult result;
    try {
      result = await WebReader.fetchUrl(
        targetUrl,
        raw: effectiveRaw,
        client: httpClient,
      );
    } catch (e) {
      throw ToolFailure('Failed to fetch $targetUrl: $e');
    }

    if (result.isImage) {
      final bytes = result.rawBytes ?? const <int>[];
      final dims = imageDimensions(bytes, result.contentType);
      return {
        'path': targetUrl,
        'kind': 'image',
        'mimeType': result.contentType,
        'bytes': bytes.length,
        if (dims != null) 'width': dims.$1,
        if (dims != null) 'height': dims.$2,
        if (includeImage && bytes.length <= ToolContext.maxInlineImageBytes)
          'base64': base64Encode(bytes),
      };
    }

    final contentText = result.content;
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
        'path': targetUrl,
        'snapshot': snapshot,
        'bytes': length,
        'unit': 'byte',
        'startByte': start,
        'endByteExclusive': end,
        'content': utf8.decode(slice, allowMalformed: true),
        'truncated': requested > safeLimit || end < length,
      };
    }

    if (readUnit != 'line') throw ToolFailure('Unsupported read unit: $unit');
    final start = (startLine ?? parsedTarget.startLine ?? offset ?? 1)
        .clamp(1, 1 << 30)
        .toInt();
    final requestedEndInput =
        endLine ??
        parsedTarget.endLine ??
        (limit == null ? null : start + limit - 1);
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
      'path': targetUrl,
      'snapshot': snapshot,
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
      'contentType': result.contentType,
      if (result.notes.isNotEmpty) 'notes': result.notes,
    };
  }

  static List<String> parsePathList(
    String? rawPath, [
    List<dynamic>? rawPaths,
  ]) {
    if (rawPaths != null && rawPaths.isNotEmpty) {
      return rawPaths
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    if (rawPath == null || rawPath.trim().isEmpty) return const [];
    final trimmed = rawPath.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false);
        }
      } catch (_) {}
    }
    if (trimmed.contains(';')) {
      return trimmed
          .split(';')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    if (trimmed.contains(',')) {
      final firstColon = trimmed.indexOf(':');
      final firstComma = trimmed.indexOf(',');
      if (firstColon == -1 || firstComma < firstColon) {
        return trimmed
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
      }
    }
    return [trimmed];
  }

  Future<Map<String, Object?>> readBulkFiles(
    List<String> paths, {
    int? offset,
    int? limit,
    int? startLine,
    int? endLine,
    String? unit,
    bool raw = false,
    bool includeImage = false,
    bool systemwide = false,
  }) async {
    final results = <Map<String, Object?>>[];
    final buffer = StringBuffer();
    var totalLines = 0;

    for (final p in paths) {
      try {
        final res = await readFile(
          p,
          offset: offset,
          limit: limit,
          startLine: startLine,
          endLine: endLine,
          unit: unit,
          raw: raw,
          includeImage: includeImage,
          systemwide: systemwide,
        );
        results.add(res);
        final snap = res['snapshot'] != null ? '#${res['snapshot']}' : '';
        buffer.writeln('[$p$snap]');
        final content = res['content']?.toString() ?? '';
        final lines = content.split('\n');
        final start = (res['startLine'] as int?) ?? 1;
        for (var i = 0; i < lines.length; i++) {
          totalLines++;
          buffer.writeln('${start + i}: ${lines[i]}');
        }
        buffer.writeln('');
      } on ToolFailure catch (e) {
        buffer.writeln('[$p]');
        buffer.writeln('Error: ${e.message}\n');
      }
    }

    return {
      'paths': paths,
      'count': results.length,
      'files': results,
      'totalLines': totalLines,
      'content': buffer.toString().trim(),
      'unit': 'line',
    };
  }

  Future<Map<String, Object?>> _readPdfBytes(
    String inputPath,
    List<int> bytes, {
    int? offset,
    int? limit,
    int? startLine,
    int? endLine,
    String? unit,
    bool raw = false,
  }) async {
    final length = bytes.length;
    final readUnit = (unit ?? 'line').toLowerCase();

    if (raw || readUnit == 'byte') {
      final start = (offset ?? 0).clamp(0, length).toInt();
      final requested = limit ?? maxReadBytes;
      final safeLimit = requested.clamp(0, maxReadBytes).toInt();
      final end = (start + safeLimit).clamp(start, length).toInt();
      final slice = bytes.sublist(start, end);
      return {
        'path': inputPath,
        'bytes': length,
        'kind': 'pdf',
        'unit': 'byte',
        'startByte': start,
        'endByteExclusive': end,
        'content': utf8.decode(slice, allowMalformed: true),
        'truncated': requested > safeLimit || end < length,
      };
    }

    if (readUnit != 'line') throw ToolFailure('Unsupported read unit: $unit');
    final pdfLines = PdfParser.extractTextLines(bytes);
    final totalLines = pdfLines.length;
    final contentText = pdfLines.join('\n');
    final contentBytes = utf8.encode(contentText);
    final snapshot = fileSnapshot(contentBytes);

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
    var selectedBytes = 0;
    var truncated = false;

    for (var i = 0; i < totalLines; i++) {
      final lineNum = i + 1;
      if (lineNum < start) continue;
      if (lineNum > requestedEnd) continue;
      if (truncated) continue;
      final line = pdfLines[i];
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
      'snapshot': snapshot,
      'bytes': length,
      'kind': 'pdf',
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
}
