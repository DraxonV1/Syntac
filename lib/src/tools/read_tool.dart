// Read project files and inspect attached images with bounded metadata.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'tool_context.dart';

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
  }) async {
    final path = inputPath.startsWith('local://')
        ? await resolveLocalPath(inputPath)
        : await resolvePath(inputPath);
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
    final readUnit = (unit ?? 'line').toLowerCase();
    if (readUnit == 'byte') {
      final start = (offset ?? 0).clamp(0, length).toInt();
      final requested = limit ?? maxReadBytes;
      final safeLimit = requested.clamp(0, maxReadBytes).toInt();
      final end = (start + safeLimit).clamp(start, length).toInt();
      final raf = await file.open();
      try {
        await raf.setPosition(start);
        final bytes = await raf.read(end - start);
        if (!raw && looksBinary(bytes)) {
          throw ToolFailure('Byte range appears to be binary: $inputPath');
        }
        return {
          'path': inputPath,
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
        in file
            .openRead()
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
}
