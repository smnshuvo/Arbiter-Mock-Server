import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../domain/entities/profile.dart';
import '../../../domain/usecases/profile_usecases.dart';
import '../../../domain/usecases/server_usecases.dart';

// ========== EVENTS ==========

abstract class ProfileEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadProfilesEvent extends ProfileEvent {}

class CreateProfileEvent extends ProfileEvent {
  final Profile profile;

  CreateProfileEvent(this.profile);

  @override
  List<Object?> get props => [profile];
}

class UpdateProfileEvent extends ProfileEvent {
  final Profile profile;

  UpdateProfileEvent(this.profile);

  @override
  List<Object?> get props => [profile];
}

class DeleteProfileEvent extends ProfileEvent {
  final String id;

  DeleteProfileEvent(this.id);

  @override
  List<Object?> get props => [id];
}

class DuplicateProfileEvent extends ProfileEvent {
  final String id;
  final String newName;

  DuplicateProfileEvent(this.id, this.newName);

  @override
  List<Object?> get props => [id, newName];
}

class StartProfileServerEvent extends ProfileEvent {
  final String profileId;

  StartProfileServerEvent(this.profileId);

  @override
  List<Object?> get props => [profileId];
}

class StopProfileServerEvent extends ProfileEvent {
  final String profileId;

  StopProfileServerEvent(this.profileId);

  @override
  List<Object?> get props => [profileId];
}

class StopAllServersEvent extends ProfileEvent {}

class AssignEndpointsEvent extends ProfileEvent {
  final String profileId;
  final List<String> endpointIds;

  AssignEndpointsEvent(this.profileId, this.endpointIds);

  @override
  List<Object?> get props => [profileId, endpointIds];
}

class ExportProfileEvent extends ProfileEvent {
  final String profileId;

  ExportProfileEvent(this.profileId);

  @override
  List<Object?> get props => [profileId];
}

class ImportProfileEvent extends ProfileEvent {
  final String jsonData;

  ImportProfileEvent(this.jsonData);

  @override
  List<Object?> get props => [jsonData];
}

// ========== STATES ==========

abstract class ProfileState extends Equatable {
  @override
  List<Object?> get props => [];
}

class ProfileInitial extends ProfileState {}

class ProfileLoading extends ProfileState {}

class ProfilesLoaded extends ProfileState {
  final List<Profile> profiles;
  final List<String> runningProfileIds;

  ProfilesLoaded(this.profiles, this.runningProfileIds);

  @override
  List<Object?> get props => [profiles, runningProfileIds];
}

class ProfileServerStarted extends ProfileState {
  final String profileId;
  final String message;

  ProfileServerStarted(this.profileId, this.message);

  @override
  List<Object?> get props => [profileId, message];
}

class ProfileServerStopped extends ProfileState {
  final String profileId;
  final String message;

  ProfileServerStopped(this.profileId, this.message);

  @override
  List<Object?> get props => [profileId, message];
}

class AllServersStopped extends ProfileState {
  final String message;

  AllServersStopped(this.message);

  @override
  List<Object?> get props => [message];
}

class ProfileExported extends ProfileState {
  final String jsonData;

  ProfileExported(this.jsonData);

  @override
  List<Object?> get props => [jsonData];
}

class ProfileError extends ProfileState {
  final String message;

  ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}

// ========== BLOC ==========

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final GetAllProfiles getAllProfiles;
  final GetProfileById getProfileById;
  final CreateProfile createProfile;
  final UpdateProfile updateProfile;
  final DeleteProfile deleteProfile;
  final DuplicateProfile duplicateProfile;
  final GetActiveProfiles getActiveProfiles;
  final ExportProfile exportProfile;
  final ImportProfile importProfile;
  final AssignEndpointsToProfile assignEndpointsToProfile;
  final StartProfileServer startProfileServer;
  final StopProfileServer stopProfileServer;
  final StopAllServers stopAllServers;
  final GetRunningProfiles getRunningProfiles;

  ProfileBloc({
    required this.getAllProfiles,
    required this.getProfileById,
    required this.createProfile,
    required this.updateProfile,
    required this.deleteProfile,
    required this.duplicateProfile,
    required this.getActiveProfiles,
    required this.exportProfile,
    required this.importProfile,
    required this.assignEndpointsToProfile,
    required this.startProfileServer,
    required this.stopProfileServer,
    required this.stopAllServers,
    required this.getRunningProfiles,
  }) : super(ProfileInitial()) {
    on<LoadProfilesEvent>(_onLoadProfiles);
    on<CreateProfileEvent>(_onCreateProfile);
    on<UpdateProfileEvent>(_onUpdateProfile);
    on<DeleteProfileEvent>(_onDeleteProfile);
    on<DuplicateProfileEvent>(_onDuplicateProfile);
    on<StartProfileServerEvent>(_onStartProfileServer);
    on<StopProfileServerEvent>(_onStopProfileServer);
    on<StopAllServersEvent>(_onStopAllServers);
    on<AssignEndpointsEvent>(_onAssignEndpoints);
    on<ExportProfileEvent>(_onExportProfile);
    on<ImportProfileEvent>(_onImportProfile);
  }

  Future<void> _onLoadProfiles(
      LoadProfilesEvent event,
      Emitter<ProfileState> emit,
      ) async {
    emit(ProfileLoading());
    try {
      final profiles = await getAllProfiles();
      final runningIds = getRunningProfiles();
      emit(ProfilesLoaded(profiles, runningIds));
    } catch (e) {
      emit(ProfileError('Failed to load profiles: $e'));
    }
  }

  Future<void> _onCreateProfile(
      CreateProfileEvent event,
      Emitter<ProfileState> emit,
      ) async {
    try {
      await createProfile(event.profile);
      final profiles = await getAllProfiles();
      final runningIds = getRunningProfiles();
      emit(ProfilesLoaded(profiles, runningIds));
    } catch (e) {
      emit(ProfileError('Failed to create profile: $e'));
    }
  }

  Future<void> _onUpdateProfile(
      UpdateProfileEvent event,
      Emitter<ProfileState> emit,
      ) async {
    try {
      await updateProfile(event.profile);
      final profiles = await getAllProfiles();
      final runningIds = getRunningProfiles();
      emit(ProfilesLoaded(profiles, runningIds));
    } catch (e) {
      emit(ProfileError('Failed to update profile: $e'));
    }
  }

  Future<void> _onDeleteProfile(
      DeleteProfileEvent event,
      Emitter<ProfileState> emit,
      ) async {
    try {
      await deleteProfile(event.id);
      final profiles = await getAllProfiles();
      final runningIds = getRunningProfiles();
      emit(ProfilesLoaded(profiles, runningIds));
    } catch (e) {
      emit(ProfileError('Failed to delete profile: $e'));
    }
  }

  Future<void> _onDuplicateProfile(
      DuplicateProfileEvent event,
      Emitter<ProfileState> emit,
      ) async {
    try {
      await duplicateProfile(event.id, event.newName);
      final profiles = await getAllProfiles();
      final runningIds = getRunningProfiles();
      emit(ProfilesLoaded(profiles, runningIds));
    } catch (e) {
      emit(ProfileError('Failed to duplicate profile: $e'));
    }
  }

  Future<void> _onStartProfileServer(
      StartProfileServerEvent event,
      Emitter<ProfileState> emit,
      ) async {
    try {
      await startProfileServer(event.profileId);

      final profile = await getProfileById(event.profileId);
      final profileName = profile?.name ?? 'Unknown';

      emit(ProfileServerStarted(
        event.profileId,
        'Server started for profile: $profileName',
      ));

      // Reload profiles to reflect the active state
      final profiles = await getAllProfiles();
      final runningIds = getRunningProfiles();
      emit(ProfilesLoaded(profiles, runningIds));
    } catch (e) {
      emit(ProfileError('Failed to start profile server: $e'));
    }
  }

  Future<void> _onStopProfileServer(
      StopProfileServerEvent event,
      Emitter<ProfileState> emit,
      ) async {
    try {
      await stopProfileServer(event.profileId);

      final profile = await getProfileById(event.profileId);
      final profileName = profile?.name ?? 'Unknown';

      emit(ProfileServerStopped(
        event.profileId,
        'Server stopped for profile: $profileName',
      ));

      // Reload profiles to reflect the inactive state
      final profiles = await getAllProfiles();
      final runningIds = getRunningProfiles();
      emit(ProfilesLoaded(profiles, runningIds));
    } catch (e) {
      emit(ProfileError('Failed to stop profile server: $e'));
    }
  }

  Future<void> _onStopAllServers(
      StopAllServersEvent event,
      Emitter<ProfileState> emit,
      ) async {
    try {
      await stopAllServers();

      emit(AllServersStopped('All servers stopped successfully'));

      // Reload profiles
      final profiles = await getAllProfiles();
      final runningIds = getRunningProfiles();
      emit(ProfilesLoaded(profiles, runningIds));
    } catch (e) {
      emit(ProfileError('Failed to stop all servers: $e'));
    }
  }

  Future<void> _onAssignEndpoints(
      AssignEndpointsEvent event,
      Emitter<ProfileState> emit,
      ) async {
    try {
      await assignEndpointsToProfile(event.profileId, event.endpointIds);
      final profiles = await getAllProfiles();
      final runningIds = getRunningProfiles();
      emit(ProfilesLoaded(profiles, runningIds));
    } catch (e) {
      emit(ProfileError('Failed to assign endpoints: $e'));
    }
  }

  Future<void> _onExportProfile(
      ExportProfileEvent event,
      Emitter<ProfileState> emit,
      ) async {
    try {
      final jsonData = await exportProfile(event.profileId);
      emit(ProfileExported(jsonData));
    } catch (e) {
      emit(ProfileError('Failed to export profile: $e'));
    }
  }

  Future<void> _onImportProfile(
      ImportProfileEvent event,
      Emitter<ProfileState> emit,
      ) async {
    try {
      await importProfile(event.jsonData);
      final profiles = await getAllProfiles();
      final runningIds = getRunningProfiles();
      emit(ProfilesLoaded(profiles, runningIds));
    } catch (e) {
      emit(ProfileError('Failed to import profile: $e'));
    }
  }
}