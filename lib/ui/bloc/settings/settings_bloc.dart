import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../domain/entities/settings.dart';
import '../../../domain/repositories/settings_repository.dart';

// Events
abstract class SettingsEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadSettingsEvent extends SettingsEvent {}

class ToggleShowEndpointHitsEvent extends SettingsEvent {
  final bool value;

  ToggleShowEndpointHitsEvent(this.value);

  @override
  List<Object?> get props => [value];
}

class ToggleShowFloatingOverlayEvent extends SettingsEvent {
  final bool value;

  ToggleShowFloatingOverlayEvent(this.value);

  @override
  List<Object?> get props => [value];
}

class SetOverlayContentEvent extends SettingsEvent {
  final bool method;
  final bool endpoint;
  final bool status;
  final bool time;

  SetOverlayContentEvent({
    required this.method,
    required this.endpoint,
    required this.status,
    required this.time,
  });

  @override
  List<Object?> get props => [method, endpoint, status, time];
}

// States
abstract class SettingsState extends Equatable {
  @override
  List<Object?> get props => [];
}

class SettingsInitial extends SettingsState {}

class SettingsLoading extends SettingsState {}

class SettingsLoaded extends SettingsState {
  final Settings settings;

  SettingsLoaded(this.settings);

  @override
  List<Object?> get props => [settings];
}

class SettingsError extends SettingsState {
  final String message;

  SettingsError(this.message);

  @override
  List<Object?> get props => [message];
}

// BLoC
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository settingsRepository;

  SettingsBloc(this.settingsRepository) : super(SettingsInitial()) {
    on<LoadSettingsEvent>(_onLoadSettings);
    on<ToggleShowEndpointHitsEvent>(_onToggleShowEndpointHits);
    on<ToggleShowFloatingOverlayEvent>(_onToggleShowFloatingOverlay);
    on<SetOverlayContentEvent>(_onSetOverlayContent);
  }

  Future<void> _onLoadSettings(
    LoadSettingsEvent event,
    Emitter<SettingsState> emit,
  ) async {
    emit(SettingsLoading());
    try {
      final settings = await settingsRepository.getSettings();
      emit(SettingsLoaded(settings));
    } catch (e) {
      emit(SettingsError(e.toString()));
    }
  }

  Future<void> _onToggleShowEndpointHits(
    ToggleShowEndpointHitsEvent event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      await settingsRepository.setShowEndpointHitsInNotifications(event.value);
      final settings = await settingsRepository.getSettings();
      emit(SettingsLoaded(settings));
    } catch (e) {
      emit(SettingsError(e.toString()));
    }
  }

  Future<void> _onToggleShowFloatingOverlay(
    ToggleShowFloatingOverlayEvent event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      await settingsRepository.setShowFloatingOverlay(event.value);
      final settings = await settingsRepository.getSettings();
      emit(SettingsLoaded(settings));
    } catch (e) {
      emit(SettingsError(e.toString()));
    }
  }

  Future<void> _onSetOverlayContent(
    SetOverlayContentEvent event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      await settingsRepository.setOverlayContent(
        method: event.method,
        endpoint: event.endpoint,
        status: event.status,
        time: event.time,
      );
      final settings = await settingsRepository.getSettings();
      emit(SettingsLoaded(settings));
    } catch (e) {
      emit(SettingsError(e.toString()));
    }
  }
}
