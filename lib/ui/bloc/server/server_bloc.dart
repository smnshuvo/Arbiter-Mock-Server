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

  ServerRunning(this.url, this.port);

  @override
  List<Object?> get props => [url, port];
}

class ServerStopped extends ServerState {
  final int port;

  ServerStopped(this.port);

  @override
  List<Object?> get props => [port];
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

  ServerBloc({
    required this.startServer,
    required this.stopServer,
    required this.getServerStatus,
    required this.getServerUrl,
    required this.setServerPort,
  }) : super(ServerInitial()) {
    on<StartServerEvent>(_onStartServer);
    on<StopServerEvent>(_onStopServer);
    on<CheckServerStatusEvent>(_onCheckServerStatus);
    on<SetServerPortEvent>(_onSetServerPort);
  }

  Future<void> _onStartServer(
      StartServerEvent event,
      Emitter<ServerState> emit,
      ) async {
    emit(ServerLoading());
    try {
      await startServer(event.port);
      final url = getServerUrl();
      emit(ServerRunning(url, event.port));
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
      await stopServer();
      emit(ServerStopped(port));
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
      if (isRunning) {
        final url = getServerUrl();
        emit(ServerRunning(url, 8080)); // Default port
      } else {
        emit(ServerStopped(8080));
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
        emit(ServerStopped(event.port));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }
}