abstract class ServerRepository {
  // Legacy methods - kept for backward compatibility
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

  // NEW - Profile-based methods
  Future<void> startProfileServer(String profileId);
  Future<void> stopProfileServer(String profileId);
  Future<void> stopAllServers();
  bool isProfileServerRunning(String profileId);
  List<String> getRunningProfileIds();
  String? getServerUrlForProfile(String profileId);
  int getRunningServerCount();
  bool isPortAvailable(int port, {String? excludeProfileId});
}