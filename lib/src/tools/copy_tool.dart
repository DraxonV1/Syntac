// Copies attached files or project files into a user-selected destination.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'tool_context.dart';

mixin CopyTool on ToolContext {
  static const maxCopyBytes = 32 * 1024 * 1024;

  Future<Map<String, Object?>> copyFile({
    required String source,
    required String target,
  }) async {
    final sourcePath = source.startsWith('local://')
        ? await resolveLocalPath(source)
        : await resolvePath(source);
    final sourceFile = File(sourcePath);
    final sourceType = await FileSystemEntity.type(
      sourcePath,
      followLinks: true,
    );
    if (sourceType != FileSystemEntityType.file) {
      throw ToolFailure('Copy source is not a file: $source');
    }

    final length = await sourceFile.length();
    if (length > maxCopyBytes) {
      throw ToolFailure(
        'Copy source exceeds ${maxCopyBytes ~/ (1024 * 1024)} MB limit: $source',
      );
    }
    final targetPath = await resolveCopyTarget(target);
    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);
    await sourceFile.copy(targetPath);
    return {'source': source, 'target': targetPath, 'bytes': length};
  }

  Future<String> resolveCopyTarget(String inputPath) async {
    final raw = inputPath.trim();
    if (raw.isEmpty) throw ToolFailure('Copy target is required');
    if (Uri.tryParse(raw)?.hasScheme ?? false) {
      throw ToolFailure('URI paths are not supported for copy targets');
    }

    final projectRootPath = p.normalize(p.absolute(projectRoot));
    final targetPath = p.normalize(
      p.absolute(p.isAbsolute(raw) ? raw : p.join(projectRoot, raw)),
    );
    if (isWithinOrSame(projectRootPath, targetPath)) {
      return resolvePath(raw, forWrite: true);
    }

    const sharedStorageRoot = '/storage/emulated/0';
    if (!Platform.isAndroid || !isWithinOrSame(sharedStorageRoot, targetPath)) {
      throw ToolFailure(
        'Copy target must stay inside project root or Android shared storage: $inputPath',
      );
    }

    final targetType = await FileSystemEntity.type(
      targetPath,
      followLinks: false,
    );
    if (targetType == FileSystemEntityType.directory) {
      throw ToolFailure('Copy target is a directory: $inputPath');
    }
    if (targetType != FileSystemEntityType.notFound) {
      final rootReal = await realPathForExisting(
        Directory(sharedStorageRoot),
        inputPath,
      );
      final targetReal = await realPathForExisting(File(targetPath), inputPath);
      if (!isWithinOrSame(rootReal, targetReal)) {
        throw ToolFailure('Copy target escapes shared storage: $inputPath');
      }
    } else {
      final ancestor = await nearestExistingAncestor(targetPath);
      final ancestorReal = await realPathForExisting(ancestor, inputPath);
      final rootReal = await realPathForExisting(
        Directory(sharedStorageRoot),
        inputPath,
      );
      if (!isWithinOrSame(rootReal, ancestorReal)) {
        throw ToolFailure('Copy target escapes shared storage: $inputPath');
      }
    }
    return targetPath;
  }
}
