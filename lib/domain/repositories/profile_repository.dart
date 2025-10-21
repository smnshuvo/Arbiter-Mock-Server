import '../entities/profile.dart';

abstract class ProfileRepository {
  Future<List<Profile>> getAllProfiles();
  Future<Profile?> getProfileById(String id);
  Future<void> createProfile(Profile profile);
  Future<void> updateProfile(Profile profile);
  Future<void> deleteProfile(String id);
  Future<void> duplicateProfile(String id, String newName);
  Future<List<Profile>> getActiveProfiles();
  Future<String> exportProfile(String id);
  Future<void> importProfile(String jsonData);
}