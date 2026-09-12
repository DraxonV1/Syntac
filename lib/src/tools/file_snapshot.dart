// Snapshots bind patches to bytes actually read, not timestamps or path spelling.
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'tool_context.dart';

const maxPatchFileBytes = 2 * 1024 * 1024;
const maxPatchCharacters = 64000;
const maxPatchDiffCharacters = 12000;

String fileSnapshot(List<int> bytes) => sha256.convert(bytes).toString();

Future<Uint8List> readPatchBytes(File file) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in file.openRead(0, maxPatchFileBytes + 1)) {
    builder.add(chunk);
  }
  if (builder.length > maxPatchFileBytes) {
    throw ToolFailure('Patch files must not exceed $maxPatchFileBytes bytes');
  }
  return builder.takeBytes();
}
