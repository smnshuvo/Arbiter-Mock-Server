import '../entities/settings.dart';

abstract class SettingsRepository {
  Future<Settings> getSettings();
  Future<void> setShowEndpointHitsInNotifications(bool value);
}
