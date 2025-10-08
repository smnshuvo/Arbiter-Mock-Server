import '../repositories/server_repository.dart';

class StartServer {
  final ServerRepository repository;

  StartServer(this.repository);

  Future<void> call(int port) async {
    await repository.startServer(port);
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