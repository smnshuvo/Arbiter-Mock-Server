import '../../../domain/entities/endpoint.dart';
import '../../../domain/entities/profile.dart';
import '../local/log_local_datasource.dart';
import 'http_server_service.dart';

class ServerManager {
  final Map<String, HttpServerService> _runningServers = {};
  final LogLocalDataSource logDataSource;

  ServerManager({
    required this.logDataSource,
  });

  /// Start a server for a specific profile
  Future<void> startProfileServer(
      Profile profile,
      List<Endpoint> endpoints,
      ) async {
    // Check if profile is already running
    if (_runningServers.containsKey(profile.id)) {
      throw Exception('Server for profile "${profile.name}" is already running');
    }

    // Check if port is already in use by another profile
    final usedPorts = _runningServers.values.map((s) => s.port).toList();
    if (usedPorts.contains(profile.port)) {
      throw Exception('Port ${profile.port} is already in use by another profile');
    }

    // Create new server instance for this profile
    final serverService = HttpServerService(
      profileId: profile.id,
      logDataSource: logDataSource,
      onEndpointsNeeded: () {
        // This callback is called when the server needs endpoints
        // The endpoints are already filtered and provided
      },
    );

    // Configure server settings from profile
    serverService.globalPassThroughUrl = profile.settings.globalPassThroughUrl;
    serverService.autoPassThrough = profile.settings.autoPassThrough;
    serverService.useDeviceIp = profile.settings.useDeviceIp;

    // Update endpoints for this server
    serverService.updateEndpoints(endpoints);

    // Start the server
    await serverService.start(
      profile.port,
      useDeviceIp: profile.settings.useDeviceIp,
    );

    // Store the running server
    _runningServers[profile.id] = serverService;

    print('Server started for profile "${profile.name}" on port ${profile.port}');
  }

  /// Stop a server for a specific profile
  Future<void> stopProfileServer(String profileId) async {
    final server = _runningServers[profileId];
    if (server == null) {
      throw Exception('No running server found for profile ID: $profileId');
    }

    await server.stop();
    _runningServers.remove(profileId);
    print('Server stopped for profile ID: $profileId');
  }

  /// Check if a profile's server is running
  bool isProfileRunning(String profileId) {
    return _runningServers.containsKey(profileId);
  }

  /// Get all running profile IDs
  List<String> getRunningProfileIds() {
    return _runningServers.keys.toList();
  }

  /// Get server instance for a specific profile
  HttpServerService? getServerForProfile(String profileId) {
    return _runningServers[profileId];
  }

  /// Stop all running servers
  Future<void> stopAllServers() async {
    final serverIds = List<String>.from(_runningServers.keys);

    for (final profileId in serverIds) {
      try {
        await stopProfileServer(profileId);
      } catch (e) {
        print('Error stopping server for profile $profileId: $e');
      }
    }

    _runningServers.clear();
    print('All servers stopped');
  }

  /// Get count of running servers
  int getRunningServerCount() {
    return _runningServers.length;
  }

  /// Update endpoints for a running profile server
  Future<void> updateProfileEndpoints(
      String profileId,
      List<Endpoint> endpoints,
      ) async {
    final server = _runningServers[profileId];
    if (server != null) {
      server.updateEndpoints(endpoints);
      print('Endpoints updated for profile ID: $profileId');
    }
  }

  /// Get server URL for a specific profile
  String? getServerUrlForProfile(String profileId) {
    final server = _runningServers[profileId];
    return server?.serverUrl;
  }

  /// Check if a port is available (not in use)
  bool isPortAvailable(int port, {String? excludeProfileId}) {
    for (final entry in _runningServers.entries) {
      if (excludeProfileId != null && entry.key == excludeProfileId) {
        continue;
      }
      if (entry.value.port == port) {
        return false;
      }
    }
    return true;
  }
}