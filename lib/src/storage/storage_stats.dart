import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/app_identity.dart';
import 'app_repository.dart';

class StorageCategorySize {
  const StorageCategorySize({
    required this.label,
    required this.bytes,
    required this.path,
  });

  final String label;
  final int bytes;
  final String path;

  String get formattedSize {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class StorageStatsResult {
  const StorageStatsResult({
    required this.categories,
    required this.totalAppBytes,
  });

  final List<StorageCategorySize> categories;
  final int totalAppBytes;
}

/// Computes application storage usage asynchronously without blocking UI isolate.
class StorageStatsService {
  static Future<StorageStatsResult> computeStats(
    AppRepository repository,
  ) async {
    final categories = <StorageCategorySize>[];
    int total = 0;

    final app = AppIdentity.instance;

    // 1. Projects
    try {
      final projects = await repository.listProjects();
      int projectBytes = 0;
      for (final project in projects) {
        projectBytes += await _dirSize(Directory(project.folderPath));
      }
      categories.add(
        StorageCategorySize(
          label: 'Projects',
          bytes: projectBytes,
          path: app.defaultSharedStoragePath,
        ),
      );
      total += projectBytes;
    } catch (_) {}

    // 2. Chats (JSONL)
    try {
      final dbPath = File(repository.localDatabasePath);
      final chatsDir = Directory(p.join(dbPath.parent.path, 'chats_jsonl'));
      final chatBytes = await _dirSize(chatsDir);
      categories.add(
        StorageCategorySize(
          label: 'Chats & Transcripts',
          bytes: chatBytes,
          path: chatsDir.path,
        ),
      );
      total += chatBytes;
    } catch (_) {}

    // 3. App Config & Database
    try {
      final dbFile = File(repository.localDatabasePath);
      int configBytes = 0;
      if (await dbFile.exists()) {
        configBytes += await dbFile.length();
      }
      categories.add(
        StorageCategorySize(
          label: 'App Config & DB',
          bytes: configBytes,
          path: dbFile.path,
        ),
      );
      total += configBytes;
    } catch (_) {}

    // 4. Runtime
    try {
      final runtimeDir = Directory(
        p.join(File(repository.localDatabasePath).parent.path, 'runtime'),
      );
      final runtimeBytes = await _dirSize(runtimeDir);
      categories.add(
        StorageCategorySize(
          label: 'Runtime & Tools',
          bytes: runtimeBytes,
          path: runtimeDir.path,
        ),
      );
      total += runtimeBytes;
    } catch (_) {}

    return StorageStatsResult(categories: categories, totalAppBytes: total);
  }

  static Future<int> _dirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int size = 0;
    try {
      await for (final file in dir.list(recursive: true, followLinks: false)) {
        if (file is File) {
          try {
            size += await file.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return size;
  }
}
