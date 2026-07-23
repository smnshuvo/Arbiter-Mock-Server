import '../../data/datasources/local/log_local_datasource.dart';
import '../../data/datasources/server/http_server_service.dart';
import '../../data/datasources/server/interception_manager.dart';
import '../../data/datasources/server/prompt_interception_manager.dart';
import '../../domain/entities/endpoint.dart';
import '../../domain/entities/network_condition.dart';

class RunningServerInfo {
  final String profileId;
  final String profileName;
  final String url;
  final int port;

  RunningServerInfo({
    required this.profileId,
    required this.profileName,
    required this.url,
    required this.port,
  });
}

class ServerManager {
  final LogLocalDataSource logDataSource;
  final InterceptionManager interceptionManager;
  final PromptInterceptionManager promptInterceptionManager;
  final Future<List<Endpoint>> Function(String profileId) onEndpointsNeeded;
  Function(String profileId, String method, String path, String timestamp)? onRequestReceived;

  final Map<String, HttpServerService> _servers = {};
  final Map<String, String> _profileNames = {};

  ServerManager({
    required this.logDataSource,
    required this.interceptionManager,
    required this.promptInterceptionManager,
    required this.onEndpointsNeeded,
    this.onRequestReceived,
  });

  List<RunningServerInfo> get runningServers {
    return _servers.entries.map((e) {
      return RunningServerInfo(
        profileId: e.key,
        profileName: _profileNames[e.key] ?? e.key,
        url: e.value.serverUrl,
        port: e.value.port,
      );
    }).toList();
  }

  bool isProfileRunning(String profileId) => _servers.containsKey(profileId);

  String? getServerUrl(String profileId) => _servers[profileId]?.serverUrl;

  int getRunningCount() => _servers.length;

  Future<void> startProfile({
    required String profileId,
    required String profileName,
    required int port,
    bool useDeviceIp = false,
    String? passThroughUrl,
    bool autoPassThrough = false,
    NetworkCondition networkCondition = NetworkCondition.none,
  }) async {
    if (_servers.containsKey(profileId)) return;

    final service = HttpServerService(
      logDataSource: logDataSource,
      interceptionManager: interceptionManager,
      promptInterceptionManager: promptInterceptionManager,
      profileId: profileId,
      onEndpointsNeeded: () async {
        final endpoints = await onEndpointsNeeded(profileId);
        _servers[profileId]?.updateEndpoints(endpoints);
      },
      onRequestReceived: onRequestReceived != null
          ? (method, path, timestamp) => onRequestReceived!(profileId, method, path, timestamp)
          : null,
    );

    if (passThroughUrl != null) service.globalPassThroughUrl = passThroughUrl;
    service.autoPassThrough = autoPassThrough;
    service.profileNetworkCondition = networkCondition;

    // Warm the endpoint cache before accepting any requests — otherwise a
    // fresh HttpServerService starts with an empty cache and the very first
    // request races the per-request lazy refresh (onEndpointsNeeded above),
    // which is fire-and-forget and won't have completed in time. 404.
    service.updateEndpoints(await onEndpointsNeeded(profileId));

    await service.start(port, useDeviceIp: useDeviceIp);
    _servers[profileId] = service;
    _profileNames[profileId] = profileName;
  }

  Future<void> stopProfile(String profileId) async {
    final service = _servers.remove(profileId);
    _profileNames.remove(profileId);
    await service?.stop();
  }

  Future<void> stopAll() async {
    for (final service in _servers.values) {
      await service.stop();
    }
    _servers.clear();
    _profileNames.clear();
  }

  void updateEndpoints(String profileId, List<Endpoint> endpoints) {
    _servers[profileId]?.updateEndpoints(endpoints);
  }

  /// Applies a profile's network-throttle setting to its already-running
  /// server immediately, without needing a restart.
  void setNetworkCondition(String profileId, NetworkCondition condition) {
    _servers[profileId]?.profileNetworkCondition = condition;
  }
}
