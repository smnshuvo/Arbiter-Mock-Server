abstract class ServerRepository {
  Future<void> startServer(int port);
  Future<void> stopServer();
  bool isServerRunning();
  String getServerUrl();
  int getCurrentPort();
  Future<void> setPort(int port);
  Future<void> setGlobalPassThroughUrl(String? url);
  String? getGlobalPassThroughUrl();
  Future<void> setAutoPassThrough(bool enabled);
  bool isAutoPassThroughEnabled();
}