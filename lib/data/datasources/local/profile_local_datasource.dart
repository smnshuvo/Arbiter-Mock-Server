import 'package:sqflite/sqflite.dart';
import '../../models/profile_model.dart';
import 'database_helper.dart';

abstract class ProfileLocalDataSource {
  Future<List<ProfileModel>> getAllProfiles();
  Future<ProfileModel?> getProfileById(String id);
  Future<void> insertProfile(ProfileModel profile);
  Future<void> updateProfile(ProfileModel profile);
  Future<void> deleteProfile(String id);
}

class ProfileLocalDataSourceImpl implements ProfileLocalDataSource {
  final DatabaseHelper databaseHelper;

  ProfileLocalDataSourceImpl(this.databaseHelper);

  @override
  Future<List<ProfileModel>> getAllProfiles() async {
    final db = await databaseHelper.database;
    final maps = await db.query('profiles', orderBy: 'createdAt ASC');
    return maps.map((m) => ProfileModel.fromMap(m)).toList();
  }

  @override
  Future<ProfileModel?> getProfileById(String id) async {
    final db = await databaseHelper.database;
    final maps = await db.query('profiles', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return ProfileModel.fromMap(maps.first);
  }

  @override
  Future<void> insertProfile(ProfileModel profile) async {
    final db = await databaseHelper.database;
    await db.insert('profiles', profile.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> updateProfile(ProfileModel profile) async {
    final db = await databaseHelper.database;
    await db.update('profiles', profile.toMap(), where: 'id = ?', whereArgs: [profile.id]);
  }

  @override
  Future<void> deleteProfile(String id) async {
    final db = await databaseHelper.database;
    await db.delete('profiles', where: 'id = ?', whereArgs: [id]);
  }
}
