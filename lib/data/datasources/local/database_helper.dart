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
        version: 4,
        onCreate: _createDB,
        onUpgrade: _onUpgrade,
      );
    }

    if (isDesktop) {
      sqfliteFfiInit();
      return databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 4,
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
        useConditionalMock INTEGER NOT NULL DEFAULT 0
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
        matchedEndpointId TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_logs_timestamp ON request_logs(timestamp)');
    await db.execute('CREATE INDEX idx_logs_method ON request_logs(method)');
    await db.execute('CREATE INDEX idx_logs_url ON request_logs(url)');
    await db.execute('CREATE INDEX idx_logs_profile ON request_logs(profileId)');
    await db.execute('CREATE INDEX idx_endpoints_profile ON endpoints(profileId)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE endpoints ADD COLUMN statusCode INTEGER NOT NULL DEFAULT 200');
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

      await db.execute("ALTER TABLE endpoints ADD COLUMN profileId TEXT NOT NULL DEFAULT 'default'");
      await db.execute("ALTER TABLE request_logs ADD COLUMN profileId TEXT NOT NULL DEFAULT 'default'");
      await db.execute('CREATE INDEX IF NOT EXISTS idx_logs_profile ON request_logs(profileId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_endpoints_profile ON endpoints(profileId)');
    }
    if (oldVersion < 4) {
      await db.execute("ALTER TABLE profiles ADD COLUMN type TEXT NOT NULL DEFAULT 'http'");
    }
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}