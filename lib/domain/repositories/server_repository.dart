import '../entities/interception_mode.dart';

abstract class ServerRepository {
  Future<void> startServer(int port, {bool useDeviceIp = false});
  Future<void> stopServer();
  bool isServerRunning();
  String getServerUrl();
  int getCurrentPort();
  Future<void> setPort(int port);
  Future<void> setGlobalPassThroughUrl(String? url);
  String? getGlobalPassThroughUrl();
  Future<void> setAutoPassThrough(bool enabled);
  bool isAutoPassThroughEnabled();
  Future<void> setUseDeviceIp(bool enabled);
  bool isUsingDeviceIp();
  Future<String?> getDeviceIpAddress();

  // Interception methods
  Future<void> setInterceptionEnabled(bool enabled);
  bool isInterceptionEnabled();
  Future<void> setInterceptionMode(InterceptionMode mode);
  InterceptionMode getInterceptionMode();
}