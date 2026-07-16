import 'dart:io';

import 'package:flutter/services.dart';

/// Bridges macOS "open .json" events and security-scoped read/write to Dart.
/// No-ops on non-macOS platforms.
class JsonDocumentService {
  JsonDocumentService._();
  static final JsonDocumentService instance = JsonDocumentService._();

  static const MethodChannel _channel = MethodChannel('arbiter/json_docs');

  static bool get isSupported => Platform.isMacOS || Platform.isAndroid;

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

  /// Human-friendly document name (last path component on macOS; the content
  /// provider's display name on Android).
  Future<String> displayName(String path) async {
    if (!isSupported) return path.split('/').last;
    final name =
        await _channel.invokeMethod<String>('displayName', {'path': path});
    return (name == null || name.isEmpty) ? path.split('/').last : name;
  }

  /// Name + size (bytes) + last-modified (epoch ms) for the recent-files list.
  Future<({String name, int? size, int? modified})> fileInfo(String path) async {
    final fallback = path.split('/').last;
    if (!isSupported) return (name: fallback, size: null, modified: null);
    final m = await _channel
        .invokeMapMethod<String, dynamic>('fileInfo', {'path': path});
    if (m == null) return (name: fallback, size: null, modified: null);
    return (
      name: (m['name'] as String?)?.isNotEmpty == true
          ? m['name'] as String
          : fallback,
      size: (m['size'] as num?)?.toInt(),
      modified: (m['modified'] as num?)?.toInt(),
    );
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

  /// Fallback when in-place write is denied (Android read-only opens): shows the
  /// system "create document" picker and writes [content] there. Returns the
  /// new path/URI, or null if unavailable/cancelled.
  Future<String?> saveAs(String content, String suggestedName) async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>(
        'saveAs', {'content': content, 'name': suggestedName});
  }

  /// Android: pick a .json via the system document picker (persistable grant, so
  /// it reopens from recents). Returns the URI, or null if cancelled.
  Future<String?> pickJson() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('pickJson');
  }
}
