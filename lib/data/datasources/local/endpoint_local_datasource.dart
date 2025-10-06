import 'package:sqflite/sqflite.dart';

import '../../models/endpoint_model.dart';
import 'database_helper.dart';

abstract class EndpointLocalDataSource {
  Future<List<EndpointModel>> getAllEndpoints();
  Future<EndpointModel?> getEndpointById(String id);
  Future<void> insertEndpoint(EndpointModel endpoint);
  Future<void> updateEndpoint(EndpointModel endpoint);
  Future<void> deleteEndpoint(String id);
  Future<void> deleteAllEndpoints();
}

class EndpointLocalDataSourceImpl implements EndpointLocalDataSource {
  final DatabaseHelper databaseHelper;

  EndpointLocalDataSourceImpl(this.databaseHelper);

  @override
  Future<List<EndpointModel>> getAllEndpoints() async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'endpoints',
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
  Future<void> deleteAllEndpoints() async {
    final db = await databaseHelper.database;
    await db.delete('endpoints');
  }
}