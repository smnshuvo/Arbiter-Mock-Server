import 'dart:io';
import 'package:flutter/services.dart';

class ForegroundService {
  static const MethodChannel _channel =
      MethodChannel('auravation.arbiter.mock_server/foreground_service');

  /// Callback function to be called when stop server is requested from notification
  static Future<bool> Function()? onStopServerRequested;

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
      
      switch (call.method) {
        case 'stopServer':
          print('ForegroundService: STOP SERVER requested from notification');
          print('ForegroundService: Checking if onStopServerRequested callback is set...');
          if (onStopServerRequested != null) {
            print('ForegroundService: Callback is set, executing...');
            try {
              final result = await onStopServerRequested!();
              print('ForegroundService: Callback completed successfully with result: $result');
              return result;
            } catch (e, stackTrace) {
              print('ForegroundService: ERROR in callback execution: $e');
              print('ForegroundService: StackTrace: $stackTrace');
              return false;
            }
          } else {
            print('ForegroundService: ERROR - onStopServerRequested callback is NULL!');
            print('ForegroundService: This means HomeScreen did not set the callback');
            return false;
          }
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
}
