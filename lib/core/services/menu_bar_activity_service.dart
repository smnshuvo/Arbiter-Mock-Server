import 'dart:io';
import 'package:flutter/services.dart';

/// macOS "Live Activity" menu bar extra bridge.
///
/// Mirrors [ForegroundService] (the Android pattern): Dart pushes server / log /
/// interception state to the native [MenuBarController] over a [MethodChannel],
/// and receives user actions (stop, continue, drop, edit) back through static
/// callbacks set by the UI layer. Every method no-ops off macOS.
class MenuBarActivityService {
  static const MethodChannel _channel =
      MethodChannel('auravation.arbiter.mock_server/menu_bar');

  /// Called when the user taps "Stop" in the panel. Returns success.
  static Future<bool> Function()? onStopServerRequested;

  /// Called when the user releases a held request/response ("Continue").
  static void Function(String id)? onInterceptionContinue;

  /// Called when the user drops a held request/response ("Drop").
  static void Function(String id)? onInterceptionDrop;

  /// Called when the user chooses to edit a held request/response ("Edit").
  static void Function(String id)? onInterceptionEdit;

  static bool get _supported => Platform.isMacOS;

  /// Registers the handler for actions coming from the native panel.
  /// Call once at startup (before the server is started).
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
        case 'interceptionEdit':
          onInterceptionEdit?.call(id);
          return true;
        default:
          return false;
      }
    });
  }

  /// Shows the status bar item (called when the server starts).
  Future<void> show() => _invoke('show');

  /// Removes the status bar item (called when the server stops).
  Future<void> hide() => _invoke('hide');

  /// Updates the panel header (running badge + address).
  Future<void> updateStatus({
    required bool running,
    required String address,
    required int port,
  }) =>
      _invoke('updateStatus', {
        'running': running,
        'address': address,
        'port': port,
      });

  /// Appends a request to the live feed. The native side keeps the latest few
  /// and tracks the running totals.
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

  /// Flips the panel to the intercepted call-to-action.
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

  /// Returns the panel to the live feed.
  Future<void> clearIntercepted() => _invoke('clearIntercepted');

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod(method, args);
    } on PlatformException {
      // Best-effort surface; never block the server hot path on UI updates.
    }
  }
}
