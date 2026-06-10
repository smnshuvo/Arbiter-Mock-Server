import '../repositories/server_repository.dart';
import '../entities/interception_mode.dart';
import '../../core/services/server_manager.dart';

class StartServer {
  final ServerRepository repository;

  StartServer(this.repository);

  Future<void> call(int port, {bool useDeviceIp = false}) async {
    await repository.startServer(port, useDeviceIp: useDeviceIp);
  }
}

class StopServer {
  final ServerRepository repository;

  StopServer(this.repository);

  Future<void> call() async {
    await repository.stopServer();
  }
}

class GetServerStatus {
  final ServerRepository repository;

  GetServerStatus(this.repository);

  bool call() {
    return repository.isServerRunning();
  }
}

class GetServerUrl {
  final ServerRepository repository;

  GetServerUrl(this.repository);

  String call() {
    return repository.getServerUrl();
  }
}

class SetServerPort {
  final ServerRepository repository;

  SetServerPort(this.repository);

  Future<void> call(int port) async {
    await repository.setPort(port);
  }
}

class SetGlobalPassThroughUrl {
  final ServerRepository repository;

  SetGlobalPassThroughUrl(this.repository);

  Future<void> call(String? url) async {
    await repository.setGlobalPassThroughUrl(url);
  }
}

class GetGlobalPassThroughUrl {
  final ServerRepository repository;

  GetGlobalPassThroughUrl(this.repository);

  String? call() {
    return repository.getGlobalPassThroughUrl();
  }
}

class SetAutoPassThrough {
  final ServerRepository repository;

  SetAutoPassThrough(this.repository);

  Future<void> call(bool enabled) async {
    await repository.setAutoPassThrough(enabled);
  }
}

class GetAutoPassThrough {
  final ServerRepository repository;

  GetAutoPassThrough(this.repository);

  bool call() {
    return repository.isAutoPassThroughEnabled();
  }
}

class SetUseDeviceIp {
  final ServerRepository repository;

  SetUseDeviceIp(this.repository);

  Future<void> call(bool enabled) async {
    await repository.setUseDeviceIp(enabled);
  }
}

class GetUseDeviceIp {
  final ServerRepository repository;

  GetUseDeviceIp(this.repository);

  bool call() {
    return repository.isUsingDeviceIp();
  }
}

class GetDeviceIpAddress {
  final ServerRepository repository;

  GetDeviceIpAddress(this.repository);

  Future<String?> call() async {
    return await repository.getDeviceIpAddress();
  }
}

class SetServerInterceptionEnabled {
  final ServerRepository repository;

  SetServerInterceptionEnabled(this.repository);

  Future<void> call(bool enabled) async {
    await repository.setInterceptionEnabled(enabled);
  }
}

class GetServerInterceptionEnabled {
  final ServerRepository repository;

  GetServerInterceptionEnabled(this.repository);

  bool call() {
    return repository.isInterceptionEnabled();
  }
}

class SetServerInterceptionMode {
  final ServerRepository repository;

  SetServerInterceptionMode(this.repository);

  Future<void> call(InterceptionMode mode) async {
    await repository.setInterceptionMode(mode);
  }
}

class GetServerInterceptionMode {
  final ServerRepository repository;

  GetServerInterceptionMode(this.repository);

  InterceptionMode call() {
    return repository.getInterceptionMode();
  }
}

class StartProfile {
  final ServerRepository repository;
  StartProfile(this.repository);

  Future<void> call({
    required String profileId,
    required String profileName,
    required int port,
    bool useDeviceIp = false,
    String? passThroughUrl,
    bool autoPassThrough = false,
  }) async {
    await repository.startProfile(
      profileId: profileId,
      profileName: profileName,
      port: port,
      useDeviceIp: useDeviceIp,
      passThroughUrl: passThroughUrl,
      autoPassThrough: autoPassThrough,
    );
  }
}

class StopProfile {
  final ServerRepository repository;
  StopProfile(this.repository);

  Future<void> call(String profileId) => repository.stopProfile(profileId);
}

class StopAllProfiles {
  final ServerRepository repository;
  StopAllProfiles(this.repository);

  Future<void> call() => repository.stopAllProfiles();
}

class GetRunningServers {
  final ServerRepository repository;
  GetRunningServers(this.repository);

  List<RunningServerInfo> call() => repository.getRunningServers();
}

class IsProfileRunning {
  final ServerRepository repository;
  IsProfileRunning(this.repository);

  bool call(String profileId) => repository.isProfileRunning(profileId);
}