import '../repositories/server_repository.dart';

// ========== LEGACY USE CASES ==========

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

// ========== NEW PROFILE-BASED USE CASES ==========

class StartProfileServer {
  final ServerRepository repository;

  StartProfileServer(this.repository);

  Future<void> call(String profileId) async {
    await repository.startProfileServer(profileId);
  }
}

class StopProfileServer {
  final ServerRepository repository;

  StopProfileServer(this.repository);

  Future<void> call(String profileId) async {
    await repository.stopProfileServer(profileId);
  }
}

class StopAllServers {
  final ServerRepository repository;

  StopAllServers(this.repository);

  Future<void> call() async {
    await repository.stopAllServers();
  }
}

class GetRunningProfiles {
  final ServerRepository repository;

  GetRunningProfiles(this.repository);

  List<String> call() {
    return repository.getRunningProfileIds();
  }
}

class IsProfileServerRunning {
  final ServerRepository repository;

  IsProfileServerRunning(this.repository);

  bool call(String profileId) {
    return repository.isProfileServerRunning(profileId);
  }
}

class GetServerUrlForProfile {
  final ServerRepository repository;

  GetServerUrlForProfile(this.repository);

  String? call(String profileId) {
    return repository.getServerUrlForProfile(profileId);
  }
}

class GetRunningServerCount {
  final ServerRepository repository;

  GetRunningServerCount(this.repository);

  int call() {
    return repository.getRunningServerCount();
  }
}

class IsPortAvailable {
  final ServerRepository repository;

  IsPortAvailable(this.repository);

  bool call(int port, {String? excludeProfileId}) {
    return repository.isPortAvailable(port, excludeProfileId: excludeProfileId);
  }
}