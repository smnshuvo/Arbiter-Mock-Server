import '../../domain/repositories/server_repository.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/repositories/endpoint_repository.dart';
import '../datasources/server/server_manager.dart';
import '../datasources/server/http_server_service.dart';
import '../../core/utils/network_utils.dart';

class ServerRepositoryImpl implements ServerRepository {
  final ServerManager serverManager;
  final ProfileRepository profileRepository;
  final EndpointRepository endpointRepository;

  // Legacy single server support (for backward compatibility)
  HttpServerService? _legacyServer;

  ServerRepositoryImpl({
    required this.serverManager,
    required this.profileRepository,
    required this.endpointRepository,
  });

  // ========== NEW PROFILE-BASED METHODS ==========

  @override
  Future<void> startProfileServer(String profileId) async {
    // Get profile
    final profile = await profileRepository.getProfileById(profileId);
    if (profile == null) {
      throw Exception('Profile not found: $profileId');
    }

    // Get endpoints assigned to this profile
    final allEndpoints = await endpointRepository.getAllEndpoints();
    final profileEndpoints = allEndpoints
        .where((endpoint) => profile.endpointIds.contains(endpoint.id))
        .toList();

    // Start server for this profile
    await serverManager.startProfileServer(profile, profileEndpoints);

    // Update profile to active
    final updatedProfile = profile.copyWith(
      isActive: true,
      updatedAt: DateTime.now(),
    );
    await profileRepository.updateProfile(updatedProfile);
  }

  @override
  Future<void> stopProfileServer(String profileId) async {
    await serverManager.stopProfileServer(profileId);

    // Update profile to inactive
    final profile = await profileRepository.getProfileById(profileId);
    if (profile != null) {
      final updatedProfile = profile.copyWith(
        isActive: false,
        updatedAt: DateTime.now(),
      );
      await profileRepository.updateProfile(updatedProfile);
    }
  }

  @override
  Future<void> stopAllServers() async {
    final runningProfileIds = serverManager.getRunningProfileIds();

    // Stop all servers
    await serverManager.stopAllServers();

    // Update all profiles to inactive
    for (final profileId in runningProfileIds) {
      final profile = await profileRepository.getProfileById(profileId);
      if (profile != null) {
        final updatedProfile = profile.copyWith(
          isActive: false,
          updatedAt: DateTime.now(),
        );
        await profileRepository.updateProfile(updatedProfile);
      }
    }
  }

  @override
  bool isProfileServerRunning(String profileId) {
    return serverManager.isProfileRunning(profileId);
  }

  @override
  List<String> getRunningProfileIds() {
    return serverManager.getRunningProfileIds();
  }

  @override
  String? getServerUrlForProfile(String profileId) {
    return serverManager.getServerUrlForProfile(profileId);
  }

  @override
  int getRunningServerCount() {
    return serverManager.getRunningServerCount();
  }

  @override
  bool isPortAvailable(int port, {String? excludeProfileId}) {
    return serverManager.isPortAvailable(port, excludeProfileId: excludeProfileId);
  }

  // ========== LEGACY METHODS (for backward compatibility) ==========

  @override
  Future<void> startServer(int port, {bool useDeviceIp = false}) async {
    // This is kept for backward compatibility
    // In the new architecture, use startProfileServer instead
    if (_legacyServer != null && _legacyServer!.isRunning) {
      throw Exception('Server is already running');
    }

    // Create a temporary legacy server
    // Note: This should be migrated to use profiles
    throw Exception('Legacy startServer is deprecated. Please use profile-based server management.');
  }

  @override
  Future<void> stopServer() async {
    // Legacy method - stop all servers for now
    await stopAllServers();
  }

  @override
  bool isServerRunning() {
    return serverManager.getRunningServerCount() > 0;
  }

  @override
  String getServerUrl() {
    final runningIds = serverManager.getRunningProfileIds();
    if (runningIds.isEmpty) {
      return 'http://localhost:8080'; // Default
    }
    return serverManager.getServerUrlForProfile(runningIds.first) ?? 'http://localhost:8080';
  }

  @override
  int getCurrentPort() {
    return 8080; // Default, legacy method
  }

  @override
  Future<void> setPort(int port) async {
    // Legacy method - not applicable in multi-profile architecture
  }

  @override
  Future<void> setGlobalPassThroughUrl(String? url) async {
    // Legacy method - should be set per profile
  }

  @override
  String? getGlobalPassThroughUrl() {
    return null; // Legacy method
  }

  @override
  Future<void> setAutoPassThrough(bool enabled) async {
    // Legacy method - should be set per profile
  }

  @override
  bool isAutoPassThroughEnabled() {
    return false; // Legacy method
  }

  @override
  Future<void> setUseDeviceIp(bool enabled) async {
    // Legacy method - should be set per profile
  }

  @override
  bool isUsingDeviceIp() {
    return false; // Legacy method
  }

  @override
  Future<String?> getDeviceIpAddress() async {
    return await NetworkUtils.getDeviceIpAddress();
  }
}