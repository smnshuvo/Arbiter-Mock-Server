import 'dart:io';

import 'package:flutter/services.dart';

/// Bridges macOS "open .json" events and security-scoped read/write to Dart.
/// No-ops on non-macOS platforms.
class JsonDocumentService {
  JsonDocumentService._();
  static final JsonDocumentService instance = JsonDocumentService._();

  static const MethodChannel _channel = MethodChannel('arbiter/json_docs');

  static bool get isSupported => Platform.isMacOS;

  /// Invoked when the OS opens .json file(s) while the app is already running.
  void Function(List<String> paths)? onFilesOpened;

  bool _initialized = false;

  void initialize() {
    if (!isSupported || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFiles') {
        final paths = (call.arguments as List).cast<String>();
        onFilesOpened?.call(paths);
      }
      return null;
    });
  }

  /// Files the OS asked to open before Dart was ready (drains the native buffer).
  Future<List<String>> getPending() async {
    if (!isSupported) return const [];
    final res = await _channel.invokeMethod<List<dynamic>>('getPendingFiles');
    return (res ?? const []).cast<String>();
  }

  Future<String?> read(String path) async {
    if (!isSupported) return null;
    return _channel.invokeMethod<String>('readFile', {'path': path});
  }

  Future<bool> write(String path, String content) async {
    if (!isSupported) return false;
    final ok = await _channel
        .invokeMethod<bool>('writeFile', {'path': path, 'content': content});
    return ok ?? false;
  }
}
