import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._(this.database, this.path);

  final Database database;
  final String path;

  static const int schemaVersion = 3;

  static Future<LocalDatabase> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath =
        path ??
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          'syntac.sqlite',
        );
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _create,
        onUpgrade: _upgrade,
      ),
    );
    return LocalDatabase._(db, dbPath);
  }

  static Future<void> _upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 1) {
      await _create(db, newVersion);
      return;
    }
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE providers ADD COLUMN provider_key TEXT NOT NULL DEFAULT 'custom-openai-compatible'",
      );
      await db.execute(
        "ALTER TABLE providers ADD COLUMN auth_type TEXT NOT NULL DEFAULT 'apiKey'",
      );
    }
    if (oldVersion < 3) {
      await _addProjectMountNames(db);
    }
  }

  static Future<void> _create(Database db, int version) async {
    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE projects (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          folder_path TEXT NOT NULL,
          mount_name TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await txn.execute(
        'CREATE INDEX idx_projects_updated_at ON projects(updated_at DESC)',
      );
      await txn.execute(
        'CREATE UNIQUE INDEX idx_projects_mount_name ON projects(mount_name)',
      );

      await txn.execute('''
        CREATE TABLE chats (
          id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
          title TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          provider_id TEXT,
          model_id TEXT,
          error TEXT
        )
      ''');
      await txn.execute(
        'CREATE INDEX idx_chats_project_updated ON chats(project_id, updated_at DESC)',
      );

      await txn.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          tool_call_id TEXT,
          metadata_json TEXT
        )
      ''');
      await txn.execute(
        'CREATE INDEX idx_messages_chat_created ON messages(chat_id, created_at ASC)',
      );

      await txn.execute('''
        CREATE TABLE tool_executions (
          id TEXT PRIMARY KEY,
          chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
          name TEXT NOT NULL,
          arguments_json TEXT NOT NULL,
          status TEXT NOT NULL,
          started_at INTEGER NOT NULL,
          finished_at INTEGER,
          result_json TEXT,
          error TEXT
        )
      ''');
      await txn.execute(
        'CREATE INDEX idx_tool_executions_chat_started ON tool_executions(chat_id, started_at ASC)',
      );

      await txn.execute('''
        CREATE TABLE providers (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          base_url TEXT NOT NULL,
          provider_key TEXT NOT NULL,
          auth_type TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');

      await txn.execute('''
        CREATE TABLE models (
          id TEXT PRIMARY KEY,
          provider_id TEXT NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
          model TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          UNIQUE(provider_id, model)
        )
      ''');

      await txn.execute('''
        CREATE TABLE attachments (
          id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          path TEXT NOT NULL,
          kind TEXT NOT NULL,
          name TEXT NOT NULL,
          mime_type TEXT,
          created_at INTEGER NOT NULL
        )
      ''');

      await txn.execute('''
        CREATE TABLE agent_jobs (
          id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
          chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
          state TEXT NOT NULL,
          current_action TEXT,
          started_at INTEGER NOT NULL,
          completed_at INTEGER,
          error TEXT
        )
      ''');
      await txn.execute(
        'CREATE INDEX idx_agent_jobs_chat_state ON agent_jobs(chat_id, state)',
      );

      await txn.execute('''
        CREATE TABLE settings (
          key TEXT PRIMARY KEY,
          value_json TEXT NOT NULL
        )
      ''');
    });
  }

  static Future<void> _addProjectMountNames(Database db) async {
    await db.execute('ALTER TABLE projects ADD COLUMN mount_name TEXT');
    final rows = await db.query('projects', orderBy: 'created_at ASC');
    final used = <String>{};
    for (final row in rows) {
      final name = row['name']?.toString() ?? 'project';
      final mountName = _uniqueProjectMountName(name, used);
      used.add(mountName);
      await db.update(
        'projects',
        {'mount_name': mountName},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await db.execute(
      'CREATE UNIQUE INDEX idx_projects_mount_name ON projects(mount_name)',
    );
  }

  static String _uniqueProjectMountName(String name, Set<String> used) {
    final base = _projectMountName(name);
    if (!used.contains(base)) return base;
    var index = 2;
    while (used.contains('$base-$index')) {
      index++;
    }
    return '$base-$index';
  }

  static String _projectMountName(String name) {
    final normalized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'project' : normalized;
  }

  Future<void> close() => database.close();
}
