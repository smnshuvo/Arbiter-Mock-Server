import '../../domain/repositories/server_repository.dart';
import '../datasources/server/http_server_service.dart';

class ServerRepositoryImpl implements ServerRepository {
  final HttpServerService serverService;

  ServerRepositoryImpl(this.serverService);

  @override
  Future<void> startServer(int port) async {
    await serverService.start(port);
  }

  @override
  Future<void> stopServer() async {
    await serverService.stop();
  }

  @override
  bool isServerRunning() {
    return serverService.isRunning;
  }

  @override
  String getServerUrl() {
    return serverService.serverUrl;
  }

  @override
  int getCurrentPort() {
    return serverService.port;
  }

  @override
  Future<void> setPort(int port) async {
    serverService.port = port;
  }
}