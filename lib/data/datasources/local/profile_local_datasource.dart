import 'package:sqflite/sqflite.dart';
import '../../models/profile_model.dart';
import 'database_helper.dart';

abstract class ProfileLocalDataSource {
  Future<List<ProfileModel>> getAllProfiles();
  Future<ProfileModel?> getProfileById(String id);
  Future<void> insertProfile(ProfileModel profile);
  Future<void> updateProfile(ProfileModel profile);
  Future<void> deleteProfile(String id);
  Future<List<String>> getEndpointIdsForProfile(String profileId);
  Future<void> setEndpointsForProfile(String profileId, List<String> endpointIds);
  Future<List<ProfileModel>> getActiveProfiles();
}

class ProfileLocalDataSourceImpl implements ProfileLocalDataSource {
  final DatabaseHelper databaseHelper;

  ProfileLocalDataSourceImpl(this.databaseHelper);

  @override
  Future<List<ProfileModel>> getAllProfiles() async {
    final db = await databaseHelper.database;
    final maps = await db.query('profiles', orderBy: 'createdAt DESC');
    return maps.map((map) => ProfileModel.fromMap(map)).toList();
  }

  @override
  Future<ProfileModel?> getProfileById(String id) async {
    final db = await databaseHelper.database;
    final maps = await db.query(
      'profiles',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return ProfileModel.fromMap(maps.first);
  }

  @override
  Future<void> insertProfile(ProfileModel profile) async {
    final db = await databaseHelper.database;
    await db.insert(
      'profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> updateProfile(ProfileModel profile) async {
    final db = await databaseHelper.database;
    await db.update(
      'profiles',
      profile.toMap(),
      where: 'id = ?',
      whereArgs: [profile.id],
    );
  }

  @override
  Future<void> deleteProfile(String id) async {
    final db = await databaseHelper.database;

    // Delete profile (CASCADE will delete profile_endpoints)
    await db.delete(
      'profiles',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<String>> getEndpointIdsForProfile(String profileId) async {
    final db = await databaseHelper.database;
    final maps = await db.query(
      'profile_endpoints',
      columns: ['endpointId'],
      where: 'profileId = ?',
      whereArgs: [profileId],
    );

    return maps.map((map) => map['endpointId'] as String).toList();
  }

  @override
  Future<void> setEndpointsForProfile(
      String profileId, List<String> endpointIds) async {
    final db = await databaseHelper.database;

    // Use transaction for atomicity
    await db.transaction((txn) async {
      // Delete existing associations
      await txn.delete(
        'profile_endpoints',
        where: 'profileId = ?',
        whereArgs: [profileId],
      );

      // Insert new associations
      for (final endpointId in endpointIds) {
        await txn.insert(
          'profile_endpoints',
          {
            'id': '${profileId}_$endpointId',
            'profileId': profileId,
            'endpointId': endpointId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<List<ProfileModel>> getActiveProfiles() async {
    final db = await databaseHelper.database;
    final maps = await db.query(
      'profiles',
      where: 'isActive = ?',
      whereArgs: [1],
      orderBy: 'createdAt DESC',
    );

    return maps.map((map) => ProfileModel.fromMap(map)).toList();
  }
}