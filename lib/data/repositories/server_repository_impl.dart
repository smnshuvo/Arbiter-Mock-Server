import '../../domain/repositories/server_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/entities/interception_mode.dart';
import '../datasources/server/http_server_service.dart';
import '../datasources/server/interception_manager.dart';
import '../../core/utils/network_utils.dart';
import '../../core/services/foreground_service.dart';

class ServerRepositoryImpl implements ServerRepository {
  final HttpServerService serverService;
  final InterceptionManager interceptionManager;
  final ForegroundService foregroundService;
  final SettingsRepository settingsRepository;

  ServerRepositoryImpl(
    this.serverService,
    this.interceptionManager,
    this.foregroundService,
    this.settingsRepository,
  );

  @override
  Future<void> startServer(int port, {bool useDeviceIp = false}) async {
    // Start foreground service before starting HTTP server
    await foregroundService.startForegroundService();
    // Start HTTP server
    await serverService.start(port, useDeviceIp: useDeviceIp);
  }

  @override
  Future<void> stopServer() async {
    // Stop HTTP server first
    await serverService.stop();
    // Stop foreground service after HTTP server stops
    await foregroundService.stopForegroundService();
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

  @override
  Future<void> setGlobalPassThroughUrl(String? url) async {
    serverService.globalPassThroughUrl = url;
  }

  @override
  String? getGlobalPassThroughUrl() {
    return serverService.globalPassThroughUrl;
  }

  @override
  Future<void> setAutoPassThrough(bool enabled) async {
    serverService.autoPassThrough = enabled;
  }

  @override
  bool isAutoPassThroughEnabled() {
    return serverService.autoPassThrough;
  }

  @override
  Future<void> setUseDeviceIp(bool enabled) async {
    serverService.useDeviceIp = enabled;
  }

  @override
  bool isUsingDeviceIp() {
    return serverService.useDeviceIp;
  }

  @override
  Future<String?> getDeviceIpAddress() async {
    return await NetworkUtils.getDeviceIpAddress();
  }

  @override
  Future<void> setInterceptionEnabled(bool enabled) async {
    if (enabled) {
      interceptionManager.setMode(InterceptionMode.both);
    } else {
      interceptionManager.setMode(InterceptionMode.none);
    }
  }

  @override
  bool isInterceptionEnabled() {
    return interceptionManager.isEnabled;
  }

  @override
  Future<void> setInterceptionMode(InterceptionMode mode) async {
    interceptionManager.setMode(mode);
  }

  @override
  InterceptionMode getInterceptionMode() {
    return interceptionManager.mode;
  }
}