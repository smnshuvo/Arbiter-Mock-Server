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
  final bool useDeviceIp;
  final String? deviceIp;

  ServerRunning(
      this.url,
      this.port, {
        this.globalPassThroughUrl,
        this.autoPassThrough = false,
        this.useDeviceIp = false,
        this.deviceIp,
      });

  @override
  List<Object?> get props => [url, port, globalPassThroughUrl, autoPassThrough, useDeviceIp, deviceIp];
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
  }) : super(ServerInitial()) {
    on<StartServerEvent>(_onStartServer);
    on<StopServerEvent>(_onStopServer);
    on<CheckServerStatusEvent>(_onCheckServerStatus);
    on<SetServerPortEvent>(_onSetServerPort);
    on<SetGlobalPassThroughUrlEvent>(_onSetGlobalPassThroughUrl);
    on<SetAutoPassThroughEvent>(_onSetAutoPassThrough);
    on<SetUseDeviceIpEvent>(_onSetUseDeviceIp);
    on<LoadDeviceIpEvent>(_onLoadDeviceIp);
  }

  Future<void> _onStartServer(
      StartServerEvent event,
      Emitter<ServerState> emit,
      ) async {
    emit(ServerLoading());
    try {
      await startServer(event.port, useDeviceIp: event.useDeviceIp);
      final url = getServerUrl();
      final passThroughUrl = getGlobalPassThroughUrl();
      final autoPassThrough = getAutoPassThrough();
      final useDeviceIp = getUseDeviceIp();
      final deviceIp = useDeviceIp ? await getDeviceIpAddress() : null;

      emit(ServerRunning(
        url,
        event.port,
        globalPassThroughUrl: passThroughUrl,
        autoPassThrough: autoPassThrough,
        useDeviceIp: useDeviceIp,
        deviceIp: deviceIp,
      ));
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onStopServer(
      StopServerEvent event,
      Emitter<ServerState> emit,
      ) async {
    print('ServerBloc: StopServerEvent received');
    emit(ServerLoading());
    try {
      final port = (state is ServerRunning) ? (state as ServerRunning).port : 8080;
      final passThroughUrl = getGlobalPassThroughUrl();
      final autoPassThrough = getAutoPassThrough();
      final useDeviceIp = getUseDeviceIp();
      final deviceIp = useDeviceIp ? await getDeviceIpAddress() : null;

      print('ServerBloc: Calling stopServer()');
      await stopServer();
      print('ServerBloc: Server stopped successfully');

      emit(ServerStopped(
        port,
        globalPassThroughUrl: passThroughUrl,
        autoPassThrough: autoPassThrough,
        useDeviceIp: useDeviceIp,
        deviceIp: deviceIp,
      ));
      print('ServerBloc: ServerStopped state emitted');
    } catch (e) {
      print('ServerBloc: Error stopping server: $e');
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
      final useDeviceIp = getUseDeviceIp();
      final deviceIp = useDeviceIp ? await getDeviceIpAddress() : null;

      if (isRunning) {
        final url = getServerUrl();
        emit(ServerRunning(
          url,
          8080,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: autoPassThrough,
          useDeviceIp: useDeviceIp,
          deviceIp: deviceIp,
        ));
      } else {
        emit(ServerStopped(
          8080,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: autoPassThrough,
          useDeviceIp: useDeviceIp,
          deviceIp: deviceIp,
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
        final currentState = state as ServerStopped;
        emit(ServerStopped(
          event.port,
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

  Future<void> _onSetGlobalPassThroughUrl(
      SetGlobalPassThroughUrlEvent event,
      Emitter<ServerState> emit,
      ) async {
    try {
      await setGlobalPassThroughUrl(event.url);
      final isRunning = getServerStatus();
      final autoPassThrough = getAutoPassThrough();
      final useDeviceIp = getUseDeviceIp();
      final deviceIp = useDeviceIp ? await getDeviceIpAddress() : null;

      if (isRunning && state is ServerRunning) {
        final currentState = state as ServerRunning;
        emit(ServerRunning(
          currentState.url,
          currentState.port,
          globalPassThroughUrl: event.url,
          autoPassThrough: autoPassThrough,
          useDeviceIp: useDeviceIp,
          deviceIp: deviceIp,
        ));
      } else if (state is ServerStopped) {
        final currentState = state as ServerStopped;
        emit(ServerStopped(
          currentState.port,
          globalPassThroughUrl: event.url,
          autoPassThrough: autoPassThrough,
          useDeviceIp: useDeviceIp,
          deviceIp: deviceIp,
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
      final useDeviceIp = getUseDeviceIp();
      final deviceIp = useDeviceIp ? await getDeviceIpAddress() : null;

      if (isRunning && state is ServerRunning) {
        final currentState = state as ServerRunning;
        emit(ServerRunning(
          currentState.url,
          currentState.port,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: event.enabled,
          useDeviceIp: useDeviceIp,
          deviceIp: deviceIp,
        ));
      } else if (state is ServerStopped) {
        final currentState = state as ServerStopped;
        emit(ServerStopped(
          currentState.port,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: event.enabled,
          useDeviceIp: useDeviceIp,
          deviceIp: deviceIp,
        ));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onSetUseDeviceIp(
      SetUseDeviceIpEvent event,
      Emitter<ServerState> emit,
      ) async {
    try {
      await setUseDeviceIp(event.enabled);
      final isRunning = getServerStatus();
      final passThroughUrl = getGlobalPassThroughUrl();
      final autoPassThrough = getAutoPassThrough();
      final deviceIp = event.enabled ? await getDeviceIpAddress() : null;

      if (state is ServerStopped) {
        final currentState = state as ServerStopped;
        emit(ServerStopped(
          currentState.port,
          globalPassThroughUrl: passThroughUrl,
          autoPassThrough: autoPassThrough,
          useDeviceIp: event.enabled,
          deviceIp: deviceIp,
        ));
      }
    } catch (e) {
      emit(ServerError(e.toString()));
    }
  }

  Future<void> _onLoadDeviceIp(
      LoadDeviceIpEvent event,
      Emitter<ServerState> emit,
      ) async {
    try {
      final deviceIp = await getDeviceIpAddress();
      final useDeviceIp = getUseDeviceIp();

      if (state is ServerStopped) {
        final currentState = state as ServerStopped;
        emit(ServerStopped(
          currentState.port,
          globalPassThroughUrl: currentState.globalPassThroughUrl,
          autoPassThrough: currentState.autoPassThrough,
          useDeviceIp: useDeviceIp,
          deviceIp: deviceIp,
        ));
      }
    } catch (e) {
      // Silently fail, not critical
    }
  }
}