abstract class ServerRepository {
  Future<void> startServer(int port);
  Future<void> stopServer();
  bool isServerRunning();
  String getServerUrl();
  int getCurrentPort();
  Future<void> setPort(int port);
}