import '../../core/services/foreground_service.dart';

class StartForegroundService {
  final ForegroundService foregroundService;

  StartForegroundService(this.foregroundService);

  Future<bool> call() async {
    return await foregroundService.startForegroundService();
  }
}

class StopForegroundService {
  final ForegroundService foregroundService;

  StopForegroundService(this.foregroundService);

  Future<bool> call() async {
    return await foregroundService.stopForegroundService();
  }
}

class UpdateForegroundServiceNotification {
  final ForegroundService foregroundService;

  UpdateForegroundServiceNotification(this.foregroundService);

  Future<bool> call({
    required String method,
    required String path,
    required String timestamp,
    String? endpointName,
  }) async {
    return await foregroundService.updateNotification(
      method: method,
      path: path,
      timestamp: timestamp,
      endpointName: endpointName,
    );
  }
}
