import 'dart:io';
import 'package:flutter/services.dart';

class ForegroundService {
  static const MethodChannel _channel =
      MethodChannel('auravation.arbiter.mock_server/foreground_service');

  /// Callback function to be called when stop server is requested from notification
  static Future<bool> Function()? onStopServerRequested;

  /// Called when the user releases a held request/response ("Continue").
  static void Function(String id)? onInterceptionContinue;

  /// Called when the user drops a held request/response ("Drop").
  static void Function(String id)? onInterceptionDrop;

  /// Called when the user taps "Edit" on a held request/response.
  static void Function(String id)? onInterceptionEdit;

  /// Called when the user taps "Logs" in the notification.
  static void Function()? onOpenLogs;

  /// Initialize the foreground service and set up method call handler
  /// This should be called once at app startup
  static void initialize() {
    if (!Platform.isAndroid) {
      print('ForegroundService: Not Android platform, skipping initialization');
      return;
    }

    print('ForegroundService: Initializing MethodChannel handler');
    _channel.setMethodCallHandler((call) async {
      print('ForegroundService: ============================================');
      print('ForegroundService: MethodChannel call received');
      print('ForegroundService: Method name: ${call.method}');
      print('ForegroundService: Arguments: ${call.arguments}');
      
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      final id = args['id'] as String? ?? '';
      switch (call.method) {
        case 'stopServer':
          if (onStopServerRequested != null) {
            try {
              return await onStopServerRequested!();
            } catch (e) {
              print('ForegroundService: ERROR in stop callback: $e');
              return false;
            }
          }
          return false;
        case 'interceptionContinue':
          onInterceptionContinue?.call(id);
          return true;
        case 'interceptionDrop':
          onInterceptionDrop?.call(id);
          return true;
        case 'interceptionEdit':
          onInterceptionEdit?.call(id);
          return true;
        case 'openLogs':
          onOpenLogs?.call();
          return true;
        default:
          print('ForegroundService: WARNING - Unknown method: ${call.method}');
          return false;
      }
    });
    
    print('ForegroundService: MethodChannel handler registered successfully');
    print('ForegroundService: ============================================');
  }

  /// Starts the foreground service
  /// Returns true if successful, false otherwise
  /// Only works on Android platform
  Future<bool> startForegroundService() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final bool result = await _channel.invokeMethod('startForegroundService');
      return result;
    } on PlatformException catch (e) {
      print('Failed to start foreground service: ${e.message}');
      return false;
    } catch (e) {
      print('Unexpected error starting foreground service: $e');
      return false;
    }
  }

  /// Stops the foreground service
  /// Returns true if successful, false otherwise
  /// Only works on Android platform
  Future<bool> stopForegroundService() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      print('ForegroundService: Stopping foreground service');
      final bool result = await _channel.invokeMethod('stopForegroundService');
      print('ForegroundService: Foreground service stopped with result: $result');
      return result;
    } on PlatformException catch (e) {
      print('ForegroundService: Failed to stop foreground service: ${e.message}');
      return false;
    } catch (e) {
      print('ForegroundService: Unexpected error stopping foreground service: $e');
      return false;
    }
  }

  /// Updates the notification with endpoint hit details
  /// [method] - HTTP method (GET, POST, etc.)
  /// [path] - Request path
  /// [timestamp] - Request timestamp
  /// [endpointName] - Optional endpoint name to display in notification
  /// Returns true if successful, false otherwise
  /// Only works on Android platform
  Future<bool> updateNotification({
    required String method,
    required String path,
    required String timestamp,
    String? endpointName,
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final bool result = await _channel.invokeMethod('updateNotification', {
        'method': method,
        'path': path,
        'timestamp': timestamp,
        if (endpointName != null) 'endpointName': endpointName,
      });
      return result;
    } on PlatformException catch (e) {
      print('Failed to update notification: ${e.message}');
      return false;
    } catch (e) {
      print('Unexpected error updating notification: $e');
      return false;
    }
  }

  // ── Live Activity (Android ongoing notification) ───────────────────────────

  /// Updates the notification header (address + port).
  Future<void> setServerStatus({required String address, required int port}) =>
      _invoke('setServerStatus', {'address': address, 'port': port});

  /// Appends a request to the live feed. The native side keeps the latest few
  /// rows and tracks running totals.
  Future<void> pushLog({
    required String method,
    required String path,
    required int statusCode,
  }) =>
      _invoke('pushLog', {
        'method': method,
        'path': path,
        'statusCode': statusCode,
      });

  /// Flips the notification to the intercepted call-to-action.
  Future<void> setIntercepted({
    required String id,
    required String type, // 'request' | 'response'
    required String method,
    required String url,
    int? statusCode,
    String? body,
  }) =>
      _invoke('setIntercepted', {
        'id': id,
        'type': type,
        'method': method,
        'url': url,
        if (statusCode != null) 'statusCode': statusCode,
        if (body != null) 'body': body,
      });

  /// Returns the notification to the live feed.
  Future<void> clearIntercepted() => _invoke('clearIntercepted');

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod(method, args);
    } on PlatformException {
      // Best-effort; never block the server hot path on UI updates.
    }
  }
}
