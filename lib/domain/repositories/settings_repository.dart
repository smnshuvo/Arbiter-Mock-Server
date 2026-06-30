import '../entities/settings.dart';

abstract class SettingsRepository {
  Future<Settings> getSettings();
  Future<void> setShowEndpointHitsInNotifications(bool value);
  Future<void> setShowFloatingOverlay(bool value);
  Future<void> setOverlayContent({
    required bool method,
    required bool endpoint,
    required bool status,
    required bool time,
  });
}
