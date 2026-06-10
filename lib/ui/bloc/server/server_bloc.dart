import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/services/server_manager.dart';
import '../../../domain/usecases/server_usecases.dart';

// Events
abstract class ServerEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class StartServerEvent extends ServerEvent {
  final int port;
  final bool useDeviceIp;

  StartServerEvent(this.port, {this.useDeviceIp = false});

  @override
  List<Object?> get props => [port, useDeviceIp];
}

class StopServerEvent extends ServerEvent {}

class CheckServerStatusEvent extends ServerEvent {}

class SetServerPortEvent extends ServerEvent {
  final int port;
  SetServerPortEvent(this.port);

  @override
  List<Object?> get props => [port];
}

class SetGlobalPassThroughUrlEvent extends ServerEvent {
  final String? url;
  SetGlobalPassThroughUrlEvent(this.url);

  @override
  List<Object?> get props => [url];
}

class SetAutoPassThroughEvent extends ServerEvent {
  final bool enabled;
  SetAutoPassThroughEvent(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

class SetUseDeviceIpEvent extends ServerEvent {
  final bool enabled;
  SetUseDeviceIpEvent(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

class LoadDeviceIpEvent extends ServerEvent {}

class StartProfileEvent extends ServerEvent {
  final String profileId;
  final String profileName;
  final int port;
  final bool useDeviceIp;
  final String? passThroughUrl;
  final bool autoPassThrough;

  StartProfileEvent({
    required this.profileId,
    required this.profileName,
    required this.port,
    this.useDeviceIp = false,
    this.passThroughUrl,
    this.autoPassThrough = false,
  });

  @override
  List<Object?> get props => [profileId, profileName, port, useDeviceIp, passThroughUrl, autoPassThrough];
}

class StopProfileEvent extends ServerEvent {
  final String profileId;
  StopProfileEvent(this.profileId);

  @override
  List<Object?> get props => [profileId];
}

class StopAllProfilesEvent extends ServerEvent {}

// States
abstract class ServerState extends Equatable {
  @override
  List<Object?> get props => [];
}

class ServerInitial extends ServerState {}

class ServerLoading extends ServerState {}

class ServerRunning extends ServerState {
  final String url;
  final int port;
  final String profileId;
  final String? globalPassThroughUrl;
  final bool autoPassThrough;
  final bool useDeviceIp;
  final String? deviceIp;

  ServerRunning(
      this.url,
      this.port, {
        this.profileId = 'default',
        this.globalPassThroughUrl,
        this.autoPassThrough = false,
        this.useDeviceIp = false,
        this.deviceIp,
      });

  @override
  List<Object?> get props => [url, port, profileId, globalPassThroughUrl, autoPassThrough, useDeviceIp, deviceIp];
}

class ServerStopped extends ServerState {
  final int port;
  final String? globalPassThroughUrl;
  final bool autoPassThrough;
  final bool useDeviceIp;
  final String? deviceIp;

  ServerStopped(
      this.port, {
        this.globalPassThroughUrl,
        this.autoPassThrough = false,
        this.useDeviceIp = false,
        this.deviceIp,
      });

  @override
  List<Object?> get props => [port, globalPassThroughUrl, autoPassThrough, useDeviceIp, deviceIp];
}

class MultiServerRunning extends ServerState {
  final List<RunningServerInfo> runningServers;

  MultiServerRunning(this.runningServers);

  @override
  List<Object?> get props => [runningServers];
}

class ServerError extends ServerState {
  final String message;

  ServerError(this.message);

  @override
  List<Object?> get props => [message];
}

// BLoC
class ServerBloc extends Bloc<ServerEvent, ServerState> {
  final StartServer startServer;
  final StopServer stopServer;
  final GetServerStatus getServerStatus;
  final GetServerUrl getServerUrl;
  final SetServerPort setServerPort;
  final SetGlobalPassThroughUrl setGlobalPassThroughUrl;
  final GetGlobalPassThroughUrl getGlobalPassThroughUrl;
  final SetAutoPassThrough setAutoPassThrough;
  final GetAutoPassThrough getAutoPassThrough;
  final SetUseDeviceIp setUseDeviceIp;
  final GetUseDeviceIp getUseDeviceIp;
  final GetDeviceIpAddress getDeviceIpAddress;
  final StartProfile startProfile;
  final StopProfile stopProfile;
  final StopAllProfiles stopAllProfiles;
  final GetRunningServers getRunningServers;

  ServerBloc({
    required this.startServer,
    required this.stopServer,
    required this.getServerStatus,
    required this.getServerUrl,
    required this.setServerPort,
    required this.setGlobalPassThroughUrl,
    required this.getGlobalPassThroughUrl,
    required this.setAutoPassThrough,
    required this.getAutoPassThrough,
    required this.setUseDeviceIp,
    required this.getUseDeviceIp,
    required this.getDeviceIpAddress,
    required this.startProfile,
    required this.stopProfile,
    required this.stopAllProfiles,
    required this.getRunningServers,
  }) : super(ServerInitial()) {
    on<StartServerEvent>(_onStartServer);
    on<StopServerEvent>(_onStopServer);
    on<CheckServerStatusEvent>(_onCheckServerStatus);
    on<SetServerPortEvent>(_onSetServerPort);
    on<SetGlobalPassThroughUrlEvent>(_onSetGlobalPassThroughUrl);
    on<SetAutoPassThroughEvent>(_onSetAutoPassThrough);
    on<SetUseDeviceIpEvent>(_onSetUseDeviceIp);
    on<LoadDeviceIpEvent>(_onLoadDeviceIp);
    on<StartProfileEvent>(_onStartProfile);
    on<StopProfileEvent>(_onStopProfile);
    on<StopAllProfilesEvent>(_onStopAllProfiles);
  }

  Future<void> _onStartServer(StartServerEvent event, Emitter<ServerState> emit) async {
    emit(ServerLoading());
    try {
      await startServer(event.port, useDeviceIp: event.useDeviceIp);
      final url = getServerUrl();
      final passThroughUrl = getGlobalPassThroughUrl();
      final autoPassThrough_ = getAutoPassThrough();
      final useDeviceIp_ = getUseDeviceIp();
      final deviceIp = useDeviceIp_ ? await getDeviceIpAddress() : null;

      emit(ServerRunning(url, event.port,
        globalPassThroughUrl: passThroughUrl,
        autoPassThrough: autoPassThrough_,
        useDeviceIp: useDeviceIp_,
        deviceIp: deviceIp,
      ));
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onStopServer(StopServerEvent event, Emitter<ServerState> emit) async {
    // Capture state before emitting ServerLoading — after emit, state changes
    final currentState = state;
    emit(ServerLoading());
    try {
      final port = currentState is ServerRunning ? currentState.port : 8080;
      final profileId = currentState is ServerRunning ? currentState.profileId : 'default';
      final passThroughUrl = getGlobalPassThroughUrl();
      final autoPassThrough_ = getAutoPassThrough();
      final useDeviceIp_ = getUseDeviceIp();
      final deviceIp = useDeviceIp_ ? await getDeviceIpAddress() : null;

      // Stop the correct profile, not always 'default'
      await stopProfile(profileId);

      emit(ServerStopped(port,
        globalPassThroughUrl: passThroughUrl,
        autoPassThrough: autoPassThrough_,
        useDeviceIp: useDeviceIp_,
        deviceIp: deviceIp,
      ));
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onCheckServerStatus(CheckServerStatusEvent event, Emitter<ServerState> emit) async {
    try {
      final running = getRunningServers();
      final passThroughUrl = getGlobalPassThroughUrl();
      final autoPassThrough_ = getAutoPassThrough();
      final useDeviceIp_ = getUseDeviceIp();

      if (running.length > 1) {
        emit(MultiServerRunning(running));
      } else if (running.length == 1) {
        final srv = running.first;
        emit(ServerRunning(srv.url, srv.port,
          profileId: srv.profileId,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: autoPassThrough_,
          useDeviceIp: useDeviceIp_,
        ));
      } else {
        final deviceIp = useDeviceIp_ ? await getDeviceIpAddress() : null;
        emit(ServerStopped(8080,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: autoPassThrough_,
          useDeviceIp: useDeviceIp_,
          deviceIp: deviceIp,
        ));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onSetServerPort(SetServerPortEvent event, Emitter<ServerState> emit) async {
    try {
      await setServerPort(event.port);
      if (state is ServerStopped) {
        final currentState = state as ServerStopped;
        emit(ServerStopped(event.port,
          globalPassThroughUrl: currentState.globalPassThroughUrl,
          autoPassThrough: currentState.autoPassThrough,
          useDeviceIp: currentState.useDeviceIp,
          deviceIp: currentState.deviceIp,
        ));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onSetGlobalPassThroughUrl(SetGlobalPassThroughUrlEvent event, Emitter<ServerState> emit) async {
    try {
      await setGlobalPassThroughUrl(event.url);
      final isRunning = getServerStatus();
      final autoPassThrough_ = getAutoPassThrough();
      final useDeviceIp_ = getUseDeviceIp();
      final deviceIp = useDeviceIp_ ? await getDeviceIpAddress() : null;

      if (isRunning && state is ServerRunning) {
        final currentState = state as ServerRunning;
        emit(ServerRunning(currentState.url, currentState.port,
          globalPassThroughUrl: event.url,
          autoPassThrough: autoPassThrough_,
          useDeviceIp: useDeviceIp_,
          deviceIp: deviceIp,
        ));
      } else if (state is ServerStopped) {
        final currentState = state as ServerStopped;
        emit(ServerStopped(currentState.port,
          globalPassThroughUrl: event.url,
          autoPassThrough: autoPassThrough_,
          useDeviceIp: useDeviceIp_,
          deviceIp: deviceIp,
        ));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onSetAutoPassThrough(SetAutoPassThroughEvent event, Emitter<ServerState> emit) async {
    try {
      await setAutoPassThrough(event.enabled);
      final isRunning = getServerStatus();
      final passThroughUrl = getGlobalPassThroughUrl();
      final useDeviceIp_ = getUseDeviceIp();
      final deviceIp = useDeviceIp_ ? await getDeviceIpAddress() : null;

      if (isRunning && state is ServerRunning) {
        final currentState = state as ServerRunning;
        emit(ServerRunning(currentState.url, currentState.port,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: event.enabled,
          useDeviceIp: useDeviceIp_,
          deviceIp: deviceIp,
        ));
      } else if (state is ServerStopped) {
        final currentState = state as ServerStopped;
        emit(ServerStopped(currentState.port,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: event.enabled,
          useDeviceIp: useDeviceIp_,
          deviceIp: deviceIp,
        ));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onSetUseDeviceIp(SetUseDeviceIpEvent event, Emitter<ServerState> emit) async {
    try {
      await setUseDeviceIp(event.enabled);
      final passThroughUrl = getGlobalPassThroughUrl();
      final autoPassThrough_ = getAutoPassThrough();
      final deviceIp = event.enabled ? await getDeviceIpAddress() : null;

      if (state is ServerStopped) {
        final currentState = state as ServerStopped;
        emit(ServerStopped(currentState.port,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: autoPassThrough_,
          useDeviceIp: event.enabled,
          deviceIp: deviceIp,
        ));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onLoadDeviceIp(LoadDeviceIpEvent event, Emitter<ServerState> emit) async {
    try {
      final deviceIp = await getDeviceIpAddress();
      final useDeviceIp_ = getUseDeviceIp();

      if (state is ServerStopped) {
        final currentState = state as ServerStopped;
        emit(ServerStopped(currentState.port,
          globalPassThroughUrl: currentState.globalPassThroughUrl,
          autoPassThrough: currentState.autoPassThrough,
          useDeviceIp: useDeviceIp_,
          deviceIp: deviceIp,
        ));
      }
    } catch (_) {
      // Silently fail — not critical
    }
  }

  Future<void> _onStartProfile(StartProfileEvent event, Emitter<ServerState> emit) async {
    emit(ServerLoading());
    try {
      await startProfile(
        profileId: event.profileId,
        profileName: event.profileName,
        port: event.port,
        useDeviceIp: event.useDeviceIp,
        passThroughUrl: event.passThroughUrl,
        autoPassThrough: event.autoPassThrough,
      );
      final running = getRunningServers();
      if (running.length > 1) {
        emit(MultiServerRunning(running));
      } else if (running.length == 1) {
        final srv = running.first;
        emit(ServerRunning(srv.url, srv.port, profileId: srv.profileId));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onStopProfile(StopProfileEvent event, Emitter<ServerState> emit) async {
    try {
      await stopProfile(event.profileId);
      final running = getRunningServers();
      if (running.isEmpty) {
        emit(ServerStopped(8080));
      } else if (running.length == 1) {
        final srv = running.first;
        emit(ServerRunning(srv.url, srv.port, profileId: srv.profileId));
      } else {
        emit(MultiServerRunning(running));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onStopAllProfiles(StopAllProfilesEvent event, Emitter<ServerState> emit) async {
    emit(ServerLoading());
    try {
      await stopAllProfiles();
      emit(ServerStopped(8080));
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }
}
