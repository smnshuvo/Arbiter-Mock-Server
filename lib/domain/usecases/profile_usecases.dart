import '../entities/profile.dart';
import '../repositories/profile_repository.dart';

// Get all profiles
class GetAllProfiles {
  final ProfileRepository repository;

  GetAllProfiles(this.repository);

  Future<List<Profile>> call() async {
    return await repository.getAllProfiles();
  }
}

// Get profile by ID
class GetProfileById {
  final ProfileRepository repository;

  GetProfileById(this.repository);

  Future<Profile?> call(String id) async {
    return await repository.getProfileById(id);
  }
}

// Create new profile
class CreateProfile {
  final ProfileRepository repository;

  CreateProfile(this.repository);

  Future<void> call(Profile profile) async {
    await repository.createProfile(profile);
  }
}

// Update existing profile
class UpdateProfile {
  final ProfileRepository repository;

  UpdateProfile(this.repository);

  Future<void> call(Profile profile) async {
    await repository.updateProfile(profile);
  }
}

// Delete profile
class DeleteProfile {
  final ProfileRepository repository;

  DeleteProfile(this.repository);

  Future<void> call(String id) async {
    await repository.deleteProfile(id);
  }
}

// Duplicate profile
class DuplicateProfile {
  final ProfileRepository repository;

  DuplicateProfile(this.repository);

  Future<void> call(String id, String newName) async {
    await repository.duplicateProfile(id, newName);
  }
}

// Get active profiles
class GetActiveProfiles {
  final ProfileRepository repository;

  GetActiveProfiles(this.repository);

  Future<List<Profile>> call() async {
    return await repository.getActiveProfiles();
  }
}

// Export profile
class ExportProfile {
  final ProfileRepository repository;

  ExportProfile(this.repository);

  Future<String> call(String id) async {
    return await repository.exportProfile(id);
  }
}

// Import profile
class ImportProfile {
  final ProfileRepository repository;

  ImportProfile(this.repository);

  Future<void> call(String jsonData) async {
    await repository.importProfile(jsonData);
  }
}

// Assign endpoints to profile
class AssignEndpointsToProfile {
  final ProfileRepository repository;

  AssignEndpointsToProfile(this.repository);

  Future<void> call(String profileId, List<String> endpointIds) async {
    final profile = await repository.getProfileById(profileId);
    if (profile == null) {
      throw Exception('Profile not found');
    }

    final updatedProfile = profile.copyWith(
      endpointIds: endpointIds,
      updatedAt: DateTime.now(),
    );

    await repository.updateProfile(updatedProfile);
  }
}

// Get endpoints for profile
class GetEndpointsForProfile {
  final ProfileRepository repository;

  GetEndpointsForProfile(this.repository);

  Future<List<String>> call(String profileId) async {
    final profile = await repository.getProfileById(profileId);
    if (profile == null) {
      throw Exception('Profile not found');
    }
    return profile.endpointIds;
  }
}