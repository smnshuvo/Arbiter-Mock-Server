import 'package:sqflite/sqflite.dart';

import '../../../domain/repositories/log_repository.dart';
import '../../models/request_log_model.dart';
import 'database_helper.dart';

abstract class LogLocalDataSource {
  Future<List<RequestLogModel>> getAllLogs({LogFilter? filter});
  Future<RequestLogModel?> getLogById(String id);
  Future<void> insertLog(RequestLogModel log);
  Future<void> clearLogs();
  Future<void> clearFilteredLogs(LogFilter filter);
}

class LogLocalDataSourceImpl implements LogLocalDataSource {
  final DatabaseHelper databaseHelper;

  LogLocalDataSourceImpl(this.databaseHelper);

  @override
  Future<List<RequestLogModel>> getAllLogs({LogFilter? filter}) async {
    final db = await databaseHelper.database;

    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (filter != null) {
      List<String> conditions = [];

      if (filter.methods != null && filter.methods!.isNotEmpty) {
        final methodNames = filter.methods!.map((m) => m.name.toUpperCase()).toList();
        conditions.add('method IN (${List.filled(methodNames.length, '?').join(',')})');
        whereArgs.addAll(methodNames);
      }

      if (filter.statusCodes != null && filter.statusCodes!.isNotEmpty) {
        conditions.add('statusCode IN (${List.filled(filter.statusCodes!.length, '?').join(',')})');
        whereArgs.addAll(filter.statusCodes!);
      }

      if (filter.logTypes != null && filter.logTypes!.isNotEmpty) {
        final typeNames = filter.logTypes!.map((t) => t.name).toList();
        conditions.add('logType IN (${List.filled(typeNames.length, '?').join(',')})');
        whereArgs.addAll(typeNames);
      }

      if (filter.startDate != null) {
        conditions.add('timestamp >= ?');
        whereArgs.add(filter.startDate!.toIso8601String());
      }

      if (filter.endDate != null) {
        conditions.add('timestamp <= ?');
        whereArgs.add(filter.endDate!.toIso8601String());
      }

      if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
        conditions.add('(url LIKE ? OR method LIKE ?)');
        final searchPattern = '%${filter.searchQuery}%';
        whereArgs.add(searchPattern);
        whereArgs.add(searchPattern);
      }

      if (conditions.isNotEmpty) {
        whereClause = conditions.join(' AND ');
      }
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'request_logs',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'timestamp DESC',
    );

    return List.generate(maps.length, (i) {
      return RequestLogModel.fromMap(maps[i]);
    });
  }

  @override
  Future<RequestLogModel?> getLogById(String id) async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'request_logs',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return RequestLogModel.fromMap(maps.first);
  }

  @override
  Future<void> insertLog(RequestLogModel log) async {
    final db = await databaseHelper.database;
    await db.insert(
      'request_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> clearLogs() async {
    final db = await databaseHelper.database;
    await db.delete('request_logs');
  }

  @override
  Future<void> clearFilteredLogs(LogFilter filter) async {
    final db = await databaseHelper.database;

    String whereClause = '';
    List<dynamic> whereArgs = [];
    List<String> conditions = [];

    if (filter.methods != null && filter.methods!.isNotEmpty) {
      final methodNames = filter.methods!.map((m) => m.name.toUpperCase()).toList();
      conditions.add('method IN (${List.filled(methodNames.length, '?').join(',')})');
      whereArgs.addAll(methodNames);
    }

    if (filter.statusCodes != null && filter.statusCodes!.isNotEmpty) {
      conditions.add('statusCode IN (${List.filled(filter.statusCodes!.length, '?').join(',')})');
      whereArgs.addAll(filter.statusCodes!);
    }

    if (filter.logTypes != null && filter.logTypes!.isNotEmpty) {
      final typeNames = filter.logTypes!.map((t) => t.name).toList();
      conditions.add('logType IN (${List.filled(typeNames.length, '?').join(',')})');
      whereArgs.addAll(typeNames);
    }

    if (filter.startDate != null) {
      conditions.add('timestamp >= ?');
      whereArgs.add(filter.startDate!.toIso8601String());
    }

    if (filter.endDate != null) {
      conditions.add('timestamp <= ?');
      whereArgs.add(filter.endDate!.toIso8601String());
    }

    if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
      conditions.add('(url LIKE ? OR method LIKE ?)');
      final searchPattern = '%${filter.searchQuery}%';
      whereArgs.add(searchPattern);
      whereArgs.add(searchPattern);
    }

    if (conditions.isNotEmpty) {
      whereClause = conditions.join(' AND ');
    }

    await db.delete(
      'request_logs',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
    );
  }
}