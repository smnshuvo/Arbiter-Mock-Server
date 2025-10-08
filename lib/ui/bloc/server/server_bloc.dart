import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../domain/usecases/server_usecases.dart';

// Events
abstract class ServerEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class StartServerEvent extends ServerEvent {
  final int port;
  StartServerEvent(this.port);

  @override
  List<Object?> get props => [port];
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
  final String? globalPassThroughUrl;
  final bool autoPassThrough;

  ServerRunning(
      this.url,
      this.port, {
        this.globalPassThroughUrl,
        this.autoPassThrough = false,
      });

  @override
  List<Object?> get props => [url, port, globalPassThroughUrl, autoPassThrough];
}

class ServerStopped extends ServerState {
  final int port;
  final String? globalPassThroughUrl;
  final bool autoPassThrough;

  ServerStopped(
      this.port, {
        this.globalPassThroughUrl,
        this.autoPassThrough = false,
      });

  @override
  List<Object?> get props => [port, globalPassThroughUrl, autoPassThrough];
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
  }) : super(ServerInitial()) {
    on<StartServerEvent>(_onStartServer);
    on<StopServerEvent>(_onStopServer);
    on<CheckServerStatusEvent>(_onCheckServerStatus);
    on<SetServerPortEvent>(_onSetServerPort);
    on<SetGlobalPassThroughUrlEvent>(_onSetGlobalPassThroughUrl);
    on<SetAutoPassThroughEvent>(_onSetAutoPassThrough);
  }

  Future<void> _onStartServer(
      StartServerEvent event,
      Emitter<ServerState> emit,
      ) async {
    emit(ServerLoading());
    try {
      await startServer(event.port);
      final url = getServerUrl();
      final passThroughUrl = getGlobalPassThroughUrl();
      final autoPassThrough = getAutoPassThrough();
      emit(ServerRunning(
        url,
        event.port,
        globalPassThroughUrl: passThroughUrl,
        autoPassThrough: autoPassThrough,
      ));
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onStopServer(
      StopServerEvent event,
      Emitter<ServerState> emit,
      ) async {
    emit(ServerLoading());
    try {
      final port = (state is ServerRunning) ? (state as ServerRunning).port : 8080;
      final passThroughUrl = getGlobalPassThroughUrl();
      final autoPassThrough = getAutoPassThrough();
      await stopServer();
      emit(ServerStopped(
        port,
        globalPassThroughUrl: passThroughUrl,
        autoPassThrough: autoPassThrough,
      ));
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onCheckServerStatus(
      CheckServerStatusEvent event,
      Emitter<ServerState> emit,
      ) async {
    try {
      final isRunning = getServerStatus();
      final passThroughUrl = getGlobalPassThroughUrl();
      final autoPassThrough = getAutoPassThrough();

      if (isRunning) {
        final url = getServerUrl();
        emit(ServerRunning(
          url,
          8080,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: autoPassThrough,
        ));
      } else {
        emit(ServerStopped(
          8080,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: autoPassThrough,
        ));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onSetServerPort(
      SetServerPortEvent event,
      Emitter<ServerState> emit,
      ) async {
    try {
      await setServerPort(event.port);
      if (state is ServerStopped) {
        final passThroughUrl = getGlobalPassThroughUrl();
        final autoPassThrough = getAutoPassThrough();
        emit(ServerStopped(
          event.port,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: autoPassThrough,
        ));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onSetGlobalPassThroughUrl(
      SetGlobalPassThroughUrlEvent event,
      Emitter<ServerState> emit,
      ) async {
    try {
      await setGlobalPassThroughUrl(event.url);
      final isRunning = getServerStatus();
      final autoPassThrough = getAutoPassThrough();

      if (isRunning && state is ServerRunning) {
        final currentState = state as ServerRunning;
        emit(ServerRunning(
          currentState.url,
          currentState.port,
          globalPassThroughUrl: event.url,
          autoPassThrough: autoPassThrough,
        ));
      } else if (state is ServerStopped) {
        final currentState = state as ServerStopped;
        emit(ServerStopped(
          currentState.port,
          globalPassThroughUrl: event.url,
          autoPassThrough: autoPassThrough,
        ));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onSetAutoPassThrough(
      SetAutoPassThroughEvent event,
      Emitter<ServerState> emit,
      ) async {
    try {
      await setAutoPassThrough(event.enabled);
      final isRunning = getServerStatus();
      final passThroughUrl = getGlobalPassThroughUrl();

      if (isRunning && state is ServerRunning) {
        final currentState = state as ServerRunning;
        emit(ServerRunning(
          currentState.url,
          currentState.port,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: event.enabled,
        ));
      } else if (state is ServerStopped) {
        final currentState = state as ServerStopped;
        emit(ServerStopped(
          currentState.port,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: event.enabled,
        ));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }
}