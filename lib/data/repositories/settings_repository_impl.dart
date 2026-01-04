import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/settings.dart';
import '../../domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  static const String _showEndpointHitsKey = 'show_endpoint_hits_in_notifications';
  final SharedPreferences sharedPreferences;

  SettingsRepositoryImpl(this.sharedPreferences);

  @override
  Future<Settings> getSettings() async {
    final showEndpointHits = sharedPreferences.getBool(_showEndpointHitsKey) ?? false;
    return Settings(showEndpointHitsInNotifications: showEndpointHits);
  }

  @override
  Future<void> setShowEndpointHitsInNotifications(bool value) async {
    await sharedPreferences.setBool(_showEndpointHitsKey, value);
  }
}
