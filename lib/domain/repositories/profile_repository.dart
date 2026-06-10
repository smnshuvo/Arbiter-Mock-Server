import '../entities/profile.dart';

abstract class ProfileRepository {
  Future<List<Profile>> getAllProfiles();
  Future<Profile?> getProfileById(String id);
  Future<void> createProfile(Profile profile);
  Future<void> updateProfile(Profile profile);
  Future<void> deleteProfile(String id);
  Future<String> getActiveProfileId();
  Future<void> setActiveProfileId(String id);
}
