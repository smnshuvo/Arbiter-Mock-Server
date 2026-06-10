import '../entities/profile.dart';
import '../repositories/profile_repository.dart';

class GetAllProfiles {
  final ProfileRepository repository;
  GetAllProfiles(this.repository);
  Future<List<Profile>> call() => repository.getAllProfiles();
}

class GetProfileById {
  final ProfileRepository repository;
  GetProfileById(this.repository);
  Future<Profile?> call(String id) => repository.getProfileById(id);
}

class CreateProfile {
  final ProfileRepository repository;
  CreateProfile(this.repository);
  Future<void> call(Profile profile) => repository.createProfile(profile);
}

class UpdateProfile {
  final ProfileRepository repository;
  UpdateProfile(this.repository);
  Future<void> call(Profile profile) => repository.updateProfile(profile);
}

class DeleteProfile {
  final ProfileRepository repository;
  DeleteProfile(this.repository);
  Future<void> call(String id) => repository.deleteProfile(id);
}

class GetActiveProfileId {
  final ProfileRepository repository;
  GetActiveProfileId(this.repository);
  Future<String> call() => repository.getActiveProfileId();
}

class SetActiveProfileId {
  final ProfileRepository repository;
  SetActiveProfileId(this.repository);
  Future<void> call(String id) => repository.setActiveProfileId(id);
}
