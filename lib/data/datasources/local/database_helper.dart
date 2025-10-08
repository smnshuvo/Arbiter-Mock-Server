import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE endpoints (
        id TEXT PRIMARY KEY,
        pattern TEXT NOT NULL,
        matchType TEXT NOT NULL,
        mode TEXT NOT NULL,
        mockResponse TEXT,
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

    await db.execute('''
      CREATE INDEX idx_logs_timestamp ON request_logs(timestamp)
    ''');

    await db.execute('''
      CREATE INDEX idx_logs_method ON request_logs(method)
    ''');

    await db.execute('''
      CREATE INDEX idx_logs_url ON request_logs(url)
    ''');
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}