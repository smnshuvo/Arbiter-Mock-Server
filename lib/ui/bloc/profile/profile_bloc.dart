import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../../domain/entities/profile.dart';
import '../../../domain/usecases/profile_usecases.dart';

// Events
abstract class ProfileEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadProfilesEvent extends ProfileEvent {}

class CreateProfileEvent extends ProfileEvent {
  final String name;
  final String? description;
  CreateProfileEvent({required this.name, this.description});

  @override
  List<Object?> get props => [name, description];
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

class SwitchActiveProfileEvent extends ProfileEvent {
  final String profileId;
  SwitchActiveProfileEvent(this.profileId);

  @override
  List<Object?> get props => [profileId];
}

// States
abstract class ProfileState extends Equatable {
  @override
  List<Object?> get props => [];
}

class ProfileInitial extends ProfileState {}

class ProfileLoading extends ProfileState {}

class ProfileLoaded extends ProfileState {
  final List<Profile> profiles;
  final String activeProfileId;

  ProfileLoaded(this.profiles, this.activeProfileId);

  Profile get activeProfile =>
      profiles.firstWhere((p) => p.id == activeProfileId, orElse: () => profiles.first);

  @override
  List<Object?> get props => [profiles, activeProfileId];
}

class ProfileError extends ProfileState {
  final String message;
  ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}

// BLoC
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final GetAllProfiles getAllProfiles;
  final CreateProfile createProfile;
  final UpdateProfile updateProfile;
  final DeleteProfile deleteProfile;
  final GetActiveProfileId getActiveProfileId;
  final SetActiveProfileId setActiveProfileId;

  ProfileBloc({
    required this.getAllProfiles,
    required this.createProfile,
    required this.updateProfile,
    required this.deleteProfile,
    required this.getActiveProfileId,
    required this.setActiveProfileId,
  }) : super(ProfileInitial()) {
    on<LoadProfilesEvent>(_onLoadProfiles);
    on<CreateProfileEvent>(_onCreateProfile);
    on<UpdateProfileEvent>(_onUpdateProfile);
    on<DeleteProfileEvent>(_onDeleteProfile);
    on<SwitchActiveProfileEvent>(_onSwitchProfile);
  }

  Future<void> _onLoadProfiles(LoadProfilesEvent event, Emitter<ProfileState> emit) async {
    emit(ProfileLoading());
    try {
      final profiles = await getAllProfiles();
      final activeId = await getActiveProfileId();
      final validActiveId = profiles.any((p) => p.id == activeId) ? activeId : (profiles.isNotEmpty ? profiles.first.id : 'default');
      emit(ProfileLoaded(profiles, validActiveId));
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  Future<void> _onCreateProfile(CreateProfileEvent event, Emitter<ProfileState> emit) async {
    try {
      final now = DateTime.now();
      final profile = Profile(
        id: const Uuid().v4(),
        name: event.name,
        description: event.description,
        port: 8080,
        settings: const ProfileSettings(),
        createdAt: now,
        updatedAt: now,
      );
      await createProfile(profile);
      final profiles = await getAllProfiles();
      final activeId = await getActiveProfileId();
      emit(ProfileLoaded(profiles, activeId));
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  Future<void> _onUpdateProfile(UpdateProfileEvent event, Emitter<ProfileState> emit) async {
    try {
      await updateProfile(event.profile);
      final profiles = await getAllProfiles();
      final activeId = await getActiveProfileId();
      emit(ProfileLoaded(profiles, activeId));
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  Future<void> _onDeleteProfile(DeleteProfileEvent event, Emitter<ProfileState> emit) async {
    if (event.id == 'default') return; // Cannot delete default profile
    try {
      await deleteProfile(event.id);
      final profiles = await getAllProfiles();
      final currentActiveId = await getActiveProfileId();
      // If we deleted the active profile, switch to default
      final newActiveId = profiles.any((p) => p.id == currentActiveId)
          ? currentActiveId
          : 'default';
      await setActiveProfileId(newActiveId);
      emit(ProfileLoaded(profiles, newActiveId));
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  Future<void> _onSwitchProfile(SwitchActiveProfileEvent event, Emitter<ProfileState> emit) async {
    try {
      await setActiveProfileId(event.profileId);
      final profiles = await getAllProfiles();
      emit(ProfileLoaded(profiles, event.profileId));
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }
}
