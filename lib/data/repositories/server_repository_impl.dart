import '../../core/services/server_manager.dart';
import '../../core/utils/network_utils.dart';
import '../../core/services/foreground_service.dart';
import '../../data/datasources/server/interception_manager.dart';
import '../../domain/entities/interception_mode.dart';
import '../../domain/repositories/server_repository.dart';

class ServerRepositoryImpl implements ServerRepository {
  final ServerManager serverManager;
  final InterceptionManager interceptionManager;
  final ForegroundService foregroundService;

  // In-memory defaults for the single-profile (default) use case
  int _port = 8080;
  String? _globalPassThroughUrl;
  bool _autoPassThrough = false;
  bool _useDeviceIp = false;

  ServerRepositoryImpl(
    this.serverManager,
    this.interceptionManager,
    this.foregroundService,
  );

  // ── Single-profile (default) helpers ────────────────────────────────────

  @override
  Future<void> startServer(int port, {bool useDeviceIp = false}) async {
    await foregroundService.startForegroundService();
    await serverManager.startProfile(
      profileId: 'default',
      profileName: 'Default',
      port: port,
      useDeviceIp: useDeviceIp,
      passThroughUrl: _globalPassThroughUrl,
      autoPassThrough: _autoPassThrough,
    );
  }

  @override
  Future<void> stopServer() async {
    await serverManager.stopProfile('default');
    await foregroundService.stopForegroundService();
  }

  @override
  bool isServerRunning() => serverManager.isProfileRunning('default');

  @override
  String getServerUrl() => serverManager.getServerUrl('default') ?? 'http://localhost:$_port';

  @override
  int getCurrentPort() => _port;

  @override
  Future<void> setPort(int port) async {
    _port = port;
  }

  @override
  Future<void> setGlobalPassThroughUrl(String? url) async {
    _globalPassThroughUrl = url;
  }

  @override
  String? getGlobalPassThroughUrl() => _globalPassThroughUrl;

  @override
  Future<void> setAutoPassThrough(bool enabled) async {
    _autoPassThrough = enabled;
  }

  @override
  bool isAutoPassThroughEnabled() => _autoPassThrough;

  @override
  Future<void> setUseDeviceIp(bool enabled) async {
    _useDeviceIp = enabled;
  }

  @override
  bool isUsingDeviceIp() => _useDeviceIp;

  @override
  Future<String?> getDeviceIpAddress() => NetworkUtils.getDeviceIpAddress();

  // ── Multi-profile operations ─────────────────────────────────────────────

  @override
  Future<void> startProfile({
    required String profileId,
    required String profileName,
    required int port,
    bool useDeviceIp = false,
    String? passThroughUrl,
    bool autoPassThrough = false,
  }) async {
    if (serverManager.getRunningCount() == 0) {
      await foregroundService.startForegroundService();
    }
    await serverManager.startProfile(
      profileId: profileId,
      profileName: profileName,
      port: port,
      useDeviceIp: useDeviceIp,
      passThroughUrl: passThroughUrl,
      autoPassThrough: autoPassThrough,
    );
  }

  @override
  Future<void> stopProfile(String profileId) async {
    await serverManager.stopProfile(profileId);
    if (serverManager.getRunningCount() == 0) {
      await foregroundService.stopForegroundService();
    }
  }

  @override
  Future<void> stopAllProfiles() async {
    await serverManager.stopAll();
    await foregroundService.stopForegroundService();
  }

  @override
  bool isProfileRunning(String profileId) => serverManager.isProfileRunning(profileId);

  @override
  List<RunningServerInfo> getRunningServers() => serverManager.runningServers;

  // ── Interception ─────────────────────────────────────────────────────────

  @override
  Future<void> setInterceptionEnabled(bool enabled) async {
    interceptionManager.setMode(enabled ? InterceptionMode.both : InterceptionMode.none);
  }

  @override
  bool isInterceptionEnabled() => interceptionManager.isEnabled;

  @override
  Future<void> setInterceptionMode(InterceptionMode mode) async {
    interceptionManager.setMode(mode);
  }

  @override
  InterceptionMode getInterceptionMode() => interceptionManager.mode;
}
