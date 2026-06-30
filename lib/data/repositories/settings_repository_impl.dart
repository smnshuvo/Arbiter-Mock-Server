import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/settings.dart';
import '../../domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  static const String _showEndpointHitsKey = 'show_endpoint_hits_in_notifications';
  static const String _showFloatingOverlayKey = 'show_floating_overlay';
  static const String _overlayMethodKey = 'overlay_show_method';
  static const String _overlayEndpointKey = 'overlay_show_endpoint';
  static const String _overlayStatusKey = 'overlay_show_status';
  static const String _overlayTimeKey = 'overlay_show_time';
  final SharedPreferences sharedPreferences;

  SettingsRepositoryImpl(this.sharedPreferences);

  @override
  Future<Settings> getSettings() async {
    return Settings(
      showEndpointHitsInNotifications: sharedPreferences.getBool(_showEndpointHitsKey) ?? false,
      showFloatingOverlay: sharedPreferences.getBool(_showFloatingOverlayKey) ?? false,
      overlayShowMethod: sharedPreferences.getBool(_overlayMethodKey) ?? true,
      overlayShowEndpoint: sharedPreferences.getBool(_overlayEndpointKey) ?? true,
      overlayShowStatus: sharedPreferences.getBool(_overlayStatusKey) ?? true,
      overlayShowTime: sharedPreferences.getBool(_overlayTimeKey) ?? false,
    );
  }

  @override
  Future<void> setShowEndpointHitsInNotifications(bool value) async {
    await sharedPreferences.setBool(_showEndpointHitsKey, value);
  }

  @override
  Future<void> setShowFloatingOverlay(bool value) async {
    await sharedPreferences.setBool(_showFloatingOverlayKey, value);
  }

  @override
  Future<void> setOverlayContent({
    required bool method,
    required bool endpoint,
    required bool status,
    required bool time,
  }) async {
    await sharedPreferences.setBool(_overlayMethodKey, method);
    await sharedPreferences.setBool(_overlayEndpointKey, endpoint);
    await sharedPreferences.setBool(_overlayStatusKey, status);
    await sharedPreferences.setBool(_overlayTimeKey, time);
  }
}
