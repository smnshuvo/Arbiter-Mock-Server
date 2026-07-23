import '../entities/interception_mode.dart';
import '../entities/network_condition.dart';
import '../../core/services/server_manager.dart';

abstract class ServerRepository {
  // Single-profile (default profile) operations — kept for backward compat
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

  // Multi-profile operations
  Future<void> startProfile({
    required String profileId,
    required String profileName,
    required int port,
    bool useDeviceIp,
    String? passThroughUrl,
    bool autoPassThrough,
    NetworkCondition networkCondition,
  });
  Future<void> stopProfile(String profileId);
  Future<void> stopAllProfiles();
  bool isProfileRunning(String profileId);
  List<RunningServerInfo> getRunningServers();
  void setProfileNetworkCondition(String profileId, NetworkCondition condition);

  // Interception methods
  Future<void> setInterceptionEnabled(bool enabled);
  bool isInterceptionEnabled();
  Future<void> setInterceptionMode(InterceptionMode mode);
  InterceptionMode getInterceptionMode();
}