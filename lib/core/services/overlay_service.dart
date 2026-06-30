import 'dart:io';
import 'package:flutter/services.dart';

/// Bridge to the Android system-wide floating overlay ("chat-head" live activity).
///
/// Dart pushes server / log / interception state to the native [OverlayController]
/// and receives the overlay's action taps back through static callbacks. Showing
/// the overlay requires the "Display over other apps" (SYSTEM_ALERT_WINDOW)
/// permission. Every method no-ops off Android.
class OverlayService {
  static const MethodChannel _channel =
      MethodChannel('auravation.arbiter.mock_server/overlay');

  /// Called when the user taps "Stop" in the overlay.
  static Future<bool> Function()? onStopServerRequested;

  /// Called when the user releases a held request/response ("Continue").
  static void Function(String id)? onInterceptionContinue;

  /// Called when the user drops a held request/response ("Drop").
  static void Function(String id)? onInterceptionDrop;

  /// Called when the user taps "Logs" in the overlay.
  static void Function()? onOpenLogs;

  static bool get _supported => Platform.isAndroid;

  /// Registers the handler for actions coming from the overlay. Call once at startup.
  static void initialize() {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      final id = args['id'] as String? ?? '';
      switch (call.method) {
        case 'stopServer':
          return await onStopServerRequested?.call() ?? false;
        case 'interceptionContinue':
          onInterceptionContinue?.call(id);
          return true;
        case 'interceptionDrop':
          onInterceptionDrop?.call(id);
          return true;
        case 'openLogs':
          onOpenLogs?.call();
          return true;
        default:
          return false;
      }
    });
  }

  /// Whether the "Display over other apps" permission has been granted.
  Future<bool> hasPermission() async {
    if (!_supported) return false;
    final granted = await _channel.invokeMethod<bool>('hasOverlayPermission');
    return granted ?? false;
  }

  /// Opens the system settings page to grant the overlay permission.
  Future<void> requestPermission() => _invoke('requestOverlayPermission');

  /// Adds the floating overlay (no-op without permission). Returns whether it is showing.
  Future<bool> show() async {
    if (!_supported) return false;
    final shown = await _channel.invokeMethod<bool>('showOverlay');
    return shown ?? false;
  }

  /// Removes the floating overlay.
  Future<void> hide() => _invoke('hideOverlay');

  /// Updates the overlay header (address + port).
  Future<void> setServerStatus({required String address, required int port}) =>
      _invoke('setServerStatus', {'address': address, 'port': port});

  /// Appends a request to the live feed (latest few kept natively).
  Future<void> pushLog({
    required String method,
    required String path,
    required int statusCode,
    required int responseTimeMs,
  }) =>
      _invoke('pushLog', {
        'method': method,
        'path': path,
        'statusCode': statusCode,
        'responseTimeMs': responseTimeMs,
      });

  /// Configures what the collapsed bubble shows.
  Future<void> setOverlayContent({
    required bool method,
    required bool endpoint,
    required bool status,
    required bool time,
  }) =>
      _invoke('setOverlayContent', {
        'method': method,
        'endpoint': endpoint,
        'status': status,
        'time': time,
      });

  /// Flips the overlay to the intercepted call-to-action.
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

  /// Returns the overlay to the live feed.
  Future<void> clearIntercepted() => _invoke('clearIntercepted');

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod(method, args);
    } on PlatformException {
      // Best-effort; never block the server hot path on overlay updates.
    }
  }
}
