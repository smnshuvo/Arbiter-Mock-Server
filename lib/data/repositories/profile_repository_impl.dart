import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/local/profile_local_datasource.dart';
import '../models/profile_model.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  static const _keyActiveProfileId = 'active_profile_id';

  final ProfileLocalDataSource localDataSource;
  final SharedPreferences sharedPreferences;

  ProfileRepositoryImpl(this.localDataSource, this.sharedPreferences);

  @override
  Future<List<Profile>> getAllProfiles() async {
    final models = await localDataSource.getAllProfiles();
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<Profile?> getProfileById(String id) async {
    final model = await localDataSource.getProfileById(id);
    return model?.toEntity();
  }

  @override
  Future<void> createProfile(Profile profile) async {
    await localDataSource.insertProfile(ProfileModel.fromEntity(profile));
  }

  @override
  Future<void> updateProfile(Profile profile) async {
    await localDataSource.updateProfile(ProfileModel.fromEntity(profile));
  }

  @override
  Future<void> deleteProfile(String id) async {
    await localDataSource.deleteProfile(id);
  }

  @override
  Future<String> getActiveProfileId() async {
    return sharedPreferences.getString(_keyActiveProfileId) ?? 'default';
  }

  @override
  Future<void> setActiveProfileId(String id) async {
    await sharedPreferences.setString(_keyActiveProfileId, id);
  }
}
