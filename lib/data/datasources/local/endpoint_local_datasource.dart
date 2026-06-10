import 'package:sqflite/sqflite.dart';

import '../../models/endpoint_model.dart';
import 'database_helper.dart';

abstract class EndpointLocalDataSource {
  Future<List<EndpointModel>> getAllEndpoints({String? profileId});
  Future<EndpointModel?> getEndpointById(String id);
  Future<void> insertEndpoint(EndpointModel endpoint);
  Future<void> updateEndpoint(EndpointModel endpoint);
  Future<void> deleteEndpoint(String id);
  Future<void> deleteAllEndpoints({String? profileId});
  Future<void> toggleAllEndpoints({required String profileId, required bool enabled});
}

class EndpointLocalDataSourceImpl implements EndpointLocalDataSource {
  final DatabaseHelper databaseHelper;

  EndpointLocalDataSourceImpl(this.databaseHelper);

  @override
  Future<List<EndpointModel>> getAllEndpoints({String? profileId}) async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'endpoints',
      where: profileId != null ? 'profileId = ?' : null,
      whereArgs: profileId != null ? [profileId] : null,
      orderBy: 'updatedAt DESC',
    );

    return List.generate(maps.length, (i) {
      return EndpointModel.fromMap(maps[i]);
    });
  }

  @override
  Future<EndpointModel?> getEndpointById(String id) async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'endpoints',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return EndpointModel.fromMap(maps.first);
  }

  @override
  Future<void> insertEndpoint(EndpointModel endpoint) async {
    final db = await databaseHelper.database;
    await db.insert(
      'endpoints',
      endpoint.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> updateEndpoint(EndpointModel endpoint) async {
    final db = await databaseHelper.database;
    await db.update(
      'endpoints',
      endpoint.toMap(),
      where: 'id = ?',
      whereArgs: [endpoint.id],
    );
  }

  @override
  Future<void> deleteEndpoint(String id) async {
    final db = await databaseHelper.database;
    await db.delete(
      'endpoints',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteAllEndpoints({String? profileId}) async {
    final db = await databaseHelper.database;
    await db.delete(
      'endpoints',
      where: profileId != null ? 'profileId = ?' : null,
      whereArgs: profileId != null ? [profileId] : null,
    );
  }

  @override
  Future<void> toggleAllEndpoints({required String profileId, required bool enabled}) async {
    final db = await databaseHelper.database;
    await db.update(
      'endpoints',
      {'isEnabled': enabled ? 1 : 0, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'profileId = ?',
      whereArgs: [profileId],
    );
  }
}