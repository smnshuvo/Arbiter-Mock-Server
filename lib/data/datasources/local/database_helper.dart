import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit, databaseFactoryFfi;

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('network_interceptor.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final isMobileOrMac = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
    final isDesktop = Platform.isLinux || Platform.isWindows;

    if (isMobileOrMac) {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, filePath);
      return openDatabase(
        path,
        version: 7,
        onCreate: _createDB,
        onUpgrade: _onUpgrade,
      );
    }

    if (isDesktop) {
      sqfliteFfiInit();
      return databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: _createDB,
          onUpgrade: _onUpgrade,
        ),
      );
    }

    throw UnsupportedError('Unsupported platform');
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        port INTEGER NOT NULL DEFAULT 8080,
        type TEXT NOT NULL DEFAULT 'http',
        settings TEXT NOT NULL DEFAULT '{}',
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    final now = DateTime.now().toIso8601String();
    await db.insert('profiles', {
      'id': 'default',
      'name': 'Default',
      'description': '',
      'port': 8080,
      'type': 'http',
      'settings': '{}',
      'createdAt': now,
      'updatedAt': now,
    });

    await db.execute('''
      CREATE TABLE endpoints (
        id TEXT PRIMARY KEY,
        profileId TEXT NOT NULL DEFAULT 'default',
        pattern TEXT NOT NULL,
        method TEXT,
        matchType TEXT NOT NULL,
        mode TEXT NOT NULL,
        mockResponse TEXT,
        statusCode INTEGER NOT NULL DEFAULT 200,
        delayMs INTEGER NOT NULL,
        targetUrl TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        isEnabled INTEGER NOT NULL,
        conditionalMocksJson TEXT,
        useConditionalMock INTEGER NOT NULL DEFAULT 0,
        networkCondition TEXT NOT NULL DEFAULT 'none',
        conditionalMode TEXT NOT NULL DEFAULT 'query',
        promptCandidatesJson TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE request_logs (
        id TEXT PRIMARY KEY,
        profileId TEXT NOT NULL DEFAULT 'default',
        timestamp TEXT NOT NULL,
        method TEXT NOT NULL,
        url TEXT NOT NULL,
        headers TEXT NOT NULL,
        requestBody TEXT,
        statusCode INTEGER NOT NULL,
        responseBody TEXT,
        responseTimeMs INTEGER NOT NULL,
        logType TEXT NOT NULL,
        matchedEndpointId TEXT,
        ip TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_logs_timestamp ON request_logs(timestamp)');
    await db.execute('CREATE INDEX idx_logs_method ON request_logs(method)');
    await db.execute('CREATE INDEX idx_logs_url ON request_logs(url)');
    await db.execute('CREATE INDEX idx_logs_profile ON request_logs(profileId)');
    await db.execute('CREATE INDEX idx_endpoints_profile ON endpoints(profileId)');
  }

  /// Column names currently present on [table].
  Future<Set<String>> _columnsOf(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => r['name'] as String).toSet();
  }

  /// Adds a column only if it isn't already there.
  ///
  /// Migrations have to be idempotent because `user_version` can lag the real
  /// schema: editing `_createDB` without bumping the version leaves databases
  /// that already have a newer column but report an older version, and a plain
  /// `ALTER TABLE ... ADD COLUMN` then fails with "duplicate column name" and
  /// aborts the whole open — bricking the app rather than just that column.
  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    if ((await _columnsOf(db, table)).contains(column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(
          db, 'endpoints', 'statusCode', 'INTEGER NOT NULL DEFAULT 200');
    }
    if (oldVersion < 3) {
      final now = DateTime.now().toIso8601String();
      await db.execute('''
        CREATE TABLE IF NOT EXISTS profiles (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          port INTEGER NOT NULL DEFAULT 8080,
          settings TEXT NOT NULL DEFAULT '{}',
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        )
      ''');
      await db.insert('profiles', {
        'id': 'default',
        'name': 'Default',
        'description': '',
        'port': 8080,
        'settings': '{}',
        'createdAt': now,
        'updatedAt': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      await _addColumnIfMissing(
          db, 'endpoints', 'profileId', "TEXT NOT NULL DEFAULT 'default'");
      await _addColumnIfMissing(
          db, 'request_logs', 'profileId', "TEXT NOT NULL DEFAULT 'default'");
      await db.execute('CREATE INDEX IF NOT EXISTS idx_logs_profile ON request_logs(profileId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_endpoints_profile ON endpoints(profileId)');
    }
    if (oldVersion < 4) {
      await _addColumnIfMissing(
          db, 'profiles', 'type', "TEXT NOT NULL DEFAULT 'http'");
    }
    if (oldVersion < 5) {
      // HTTP method scoping; NULL = ANY verb (existing rows match every method).
      await _addColumnIfMissing(db, 'endpoints', 'method', 'TEXT');
    }
    if (oldVersion < 6) {
      // Simulated link speed; existing rows keep serving unthrottled.
      await _addColumnIfMissing(
          db, 'endpoints', 'networkCondition', "TEXT NOT NULL DEFAULT 'none'");
    }
    if (oldVersion < 7) {
      // Conditional "Prompt" mode: live pick-a-response instead of query rules.
      await _addColumnIfMissing(
          db, 'endpoints', 'conditionalMode', "TEXT NOT NULL DEFAULT 'query'");
      await _addColumnIfMissing(db, 'endpoints', 'promptCandidatesJson', 'TEXT');
      // Client IP captured per request for log filtering.
      await _addColumnIfMissing(db, 'request_logs', 'ip', 'TEXT');
    }
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}