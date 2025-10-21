import 'dart:convert';
import '../../domain/entities/profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/local/profile_local_datasource.dart';
import '../models/profile_model.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  final ProfileLocalDataSource localDataSource;

  ProfileRepositoryImpl(this.localDataSource);

  @override
  Future<List<Profile>> getAllProfiles() async {
    final profileModels = await localDataSource.getAllProfiles();

    final profiles = <Profile>[];
    for (final model in profileModels) {
      final endpointIds = await localDataSource.getEndpointIdsForProfile(model.id);
      profiles.add(model.toEntity(endpointIds));
    }

    return profiles;
  }

  @override
  Future<Profile?> getProfileById(String id) async {
    final model = await localDataSource.getProfileById(id);
    if (model == null) return null;

    final endpointIds = await localDataSource.getEndpointIdsForProfile(id);
    return model.toEntity(endpointIds);
  }

  @override
  Future<void> createProfile(Profile profile) async {
    final model = ProfileModel.fromEntity(profile);
    await localDataSource.insertProfile(model);

    // Set endpoint associations
    if (profile.endpointIds.isNotEmpty) {
      await localDataSource.setEndpointsForProfile(
        profile.id,
        profile.endpointIds,
      );
    }
  }

  @override
  Future<void> updateProfile(Profile profile) async {
    final model = ProfileModel.fromEntity(profile);
    await localDataSource.updateProfile(model);

    // Update endpoint associations
    await localDataSource.setEndpointsForProfile(
      profile.id,
      profile.endpointIds,
    );
  }

  @override
  Future<void> deleteProfile(String id) async {
    await localDataSource.deleteProfile(id);
  }

  @override
  Future<void> duplicateProfile(String id, String newName) async {
    final original = await getProfileById(id);
    if (original == null) {
      throw Exception('Profile not found');
    }

    final now = DateTime.now();
    final duplicate = Profile(
      id: now.millisecondsSinceEpoch.toString(),
      name: newName,
      description: '${original.description} (Copy)',
      port: original.port + 1, // Increment port to avoid conflicts
      isActive: false, // Duplicated profiles start as inactive
      endpointIds: List.from(original.endpointIds),
      createdAt: now,
      updatedAt: now,
      settings: original.settings,
    );

    await createProfile(duplicate);
  }

  @override
  Future<List<Profile>> getActiveProfiles() async {
    final profileModels = await localDataSource.getActiveProfiles();

    final profiles = <Profile>[];
    for (final model in profileModels) {
      final endpointIds = await localDataSource.getEndpointIdsForProfile(model.id);
      profiles.add(model.toEntity(endpointIds));
    }

    return profiles;
  }

  @override
  Future<String> exportProfile(String id) async {
    final profile = await getProfileById(id);
    if (profile == null) {
      throw Exception('Profile not found');
    }

    final exportData = {
      'version': '1.0',
      'exportDate': DateTime.now().toIso8601String(),
      'profile': {
        'name': profile.name,
        'description': profile.description,
        'port': profile.port,
        'endpointIds': profile.endpointIds,
        'settings': {
          'globalPassThroughUrl': profile.settings.globalPassThroughUrl,
          'autoPassThrough': profile.settings.autoPassThrough,
          'passThroughAll': profile.settings.passThroughAll,
          'useDeviceIp': profile.settings.useDeviceIp,
        },
      },
    };

    return jsonEncode(exportData);
  }

  @override
  Future<void> importProfile(String jsonData) async {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final profileData = data['profile'] as Map<String, dynamic>;
      final settingsData = profileData['settings'] as Map<String, dynamic>;

      final now = DateTime.now();
      final profile = Profile(
        id: now.millisecondsSinceEpoch.toString(),
        name: profileData['name'] as String,
        description: profileData['description'] as String? ?? '',
        port: profileData['port'] as int,
        isActive: false, // Imported profiles start as inactive
        endpointIds: (profileData['endpointIds'] as List?)
            ?.map((e) => e.toString())
            .toList() ?? [],
        createdAt: now,
        updatedAt: now,
        settings: ProfileSettings(
          globalPassThroughUrl: settingsData['globalPassThroughUrl'] as String?,
          autoPassThrough: settingsData['autoPassThrough'] as bool? ?? false,
          passThroughAll: settingsData['passThroughAll'] as bool? ?? false,
          useDeviceIp: settingsData['useDeviceIp'] as bool? ?? false,
        ),
      );

      await createProfile(profile);
    } catch (e) {
      throw Exception('Failed to import profile: $e');
    }
  }
}