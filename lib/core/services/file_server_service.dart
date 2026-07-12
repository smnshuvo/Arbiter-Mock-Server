import 'dart:io';
import 'package:flutter/services.dart';

/// A shared folder the user has granted the app persistent access to.
class SharedFolder {
  const SharedFolder({required this.uri, required this.name});

  final String uri;
  final String name;
}

/// Live state of the native file server, queried when the File Server screen
/// (re)opens — the foreground service keeps the server running after the
/// screen is disposed, so the UI cannot rely on its own state alone.
class FileServerStatus {
  const FileServerStatus({
    required this.running,
    required this.port,
    required this.requestCount,
  });

  static const stopped = FileServerStatus(running: false, port: -1, requestCount: 0);

  final bool running;
  final int port;
  final int requestCount;
}

/// A Tier-3 transcode currently in progress (see TranscodeController.ongoing).
class TranscodeOngoing {
  const TranscodeOngoing({
    required this.mediaId,
    required this.title,
    required this.pct,
    required this.startedAt,
  });

  factory TranscodeOngoing.fromMap(Map<dynamic, dynamic> m) => TranscodeOngoing(
        mediaId: (m['mediaId'] as num).toInt(),
        title: m['title'] as String? ?? 'Unknown',
        pct: (m['pct'] as num?)?.toInt() ?? 0,
        startedAt: DateTime.fromMillisecondsSinceEpoch((m['startedAt'] as num).toInt()),
      );

  final int mediaId;
  final String title;
  final int pct;
  final DateTime startedAt;
}

/// One finished Tier-3 transcode job (see TranscodeController.recentLog).
class TranscodeLogEntry {
  const TranscodeLogEntry({
    required this.mediaId,
    required this.title,
    required this.startedAt,
    required this.finishedAt,
    required this.outcome,
    this.reason,
  });

  factory TranscodeLogEntry.fromMap(Map<dynamic, dynamic> m) => TranscodeLogEntry(
        mediaId: (m['mediaId'] as num).toInt(),
        title: m['title'] as String? ?? 'Unknown',
        startedAt: DateTime.fromMillisecondsSinceEpoch((m['startedAt'] as num).toInt()),
        finishedAt: DateTime.fromMillisecondsSinceEpoch((m['finishedAt'] as num).toInt()),
        outcome: m['outcome'] as String? ?? 'failed',
        reason: m['reason'] as String?,
      );

  final int mediaId;
  final String title;
  final DateTime startedAt;
  final DateTime finishedAt;
  final String outcome; // "ready" | "failed" | "cancelled"
  final String? reason;

  Duration get duration => finishedAt.difference(startedAt);
  bool get succeeded => outcome == 'ready';
}

/// Ongoing Tier-3 jobs plus recent history, for the Settings screen's log view.
class TranscodeLog {
  const TranscodeLog({required this.ongoing, required this.history});

  final List<TranscodeOngoing> ongoing;
  final List<TranscodeLogEntry> history;
}

/// An event pushed from the native file server (scan progress, request count,
/// or connected remote-control clients).
class FileServerEvent {
  const FileServerEvent.scan({
    required this.done,
    required this.total,
    required this.complete,
  })  : type = FileServerEventType.scan,
        requestCount = 0,
        remoteClients = 0,
        positionMs = 0,
        durationMs = 0,
        paused = true,
        volume = 1.0;

  const FileServerEvent.requests(this.requestCount)
      : type = FileServerEventType.requests,
        done = 0,
        total = 0,
        complete = false,
        remoteClients = 0,
        positionMs = 0,
        durationMs = 0,
        paused = true,
        volume = 1.0;

  const FileServerEvent.remote(this.remoteClients)
      : type = FileServerEventType.remote,
        done = 0,
        total = 0,
        complete = false,
        requestCount = 0,
        positionMs = 0,
        durationMs = 0,
        paused = true,
        volume = 1.0;

  const FileServerEvent.playback({
    required this.positionMs,
    required this.durationMs,
    required this.paused,
    required this.volume,
  })  : type = FileServerEventType.playback,
        done = 0,
        total = 0,
        complete = false,
        requestCount = 0,
        remoteClients = 0;

  const FileServerEvent.stopped()
      : type = FileServerEventType.stopped,
        done = 0,
        total = 0,
        complete = false,
        requestCount = 0,
        remoteClients = 0,
        positionMs = 0,
        durationMs = 0,
        paused = true,
        volume = 1.0;

  final FileServerEventType type;
  final int done;
  final int total;
  final bool complete;
  final int requestCount;
  final int remoteClients;
  final int positionMs;
  final int durationMs;
  final bool paused;
  final double volume;
}

enum FileServerEventType { scan, requests, remote, playback, stopped }

/// Dart bridge to the native NanoHTTPD Wi-Fi file server (Android only).
///
/// Mirrors [ForegroundService]/[OverlayService]: a thin MethodChannel wrapper that
/// no-ops on every non-Android platform. Scan progress and the live request counter
/// arrive over a companion [EventChannel] exposed as [events].
class FileServerService {
  static const MethodChannel _channel =
      MethodChannel('auravation.arbiter.mock_server/file_server');
  static const EventChannel _events =
      EventChannel('auravation.arbiter.mock_server/file_server_events');

  static bool get _supported => Platform.isAndroid;

  /// Whether the file server is available on this platform (Android-only for now).
  static bool get isSupported => _supported;

  /// Broadcast of scan-progress and request-count events from native.
  Stream<FileServerEvent> get events {
    if (!_supported) return const Stream.empty();
    return _events.receiveBroadcastStream().map((dynamic e) {
      final map = (e as Map).cast<String, dynamic>();
      if (map['type'] == 'scan') {
        return FileServerEvent.scan(
          done: (map['done'] as int?) ?? 0,
          total: (map['total'] as int?) ?? 0,
          complete: (map['complete'] as bool?) ?? false,
        );
      }
      if (map['type'] == 'remote') {
        return FileServerEvent.remote((map['count'] as int?) ?? 0);
      }
      if (map['type'] == 'playback') {
        return FileServerEvent.playback(
          positionMs: (map['positionMs'] as int?) ?? 0,
          durationMs: (map['durationMs'] as int?) ?? 0,
          paused: (map['paused'] as bool?) ?? true,
          volume: ((map['volume'] as num?) ?? 1.0).toDouble(),
        );
      }
      if (map['type'] == 'stopped') {
        return const FileServerEvent.stopped();
      }
      return FileServerEvent.requests((map['count'] as int?) ?? 0);
    });
  }

  /// Opens the SAF folder picker and persists access. Returns null if cancelled.
  Future<SharedFolder?> pickFolder() async {
    if (!_supported) return null;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('pickFolder');
      if (result == null) return null;
      return SharedFolder(
        uri: result['uri'] as String,
        name: result['name'] as String,
      );
    } on PlatformException catch (e) {
      print('FileServerService.pickFolder failed: ${e.message}');
      return null;
    }
  }

  /// The previously picked folder if its permission still holds, else null.
  Future<SharedFolder?> getSavedFolder() async {
    if (!_supported) return null;
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getSavedFolder');
      if (result == null) return null;
      return SharedFolder(
        uri: result['uri'] as String,
        name: result['name'] as String,
      );
    } on PlatformException catch (e) {
      print('FileServerService.getSavedFolder failed: ${e.message}');
      return null;
    }
  }

  /// Starts the native server on [port] serving [rootUri]. Returns success.
  ///
  /// When [authUser] is non-empty the server requires HTTP Basic login with
  /// [authUser]/[authPass]; otherwise access is anonymous.
  Future<bool> startServer({
    required int port,
    required String rootUri,
    bool uploadsEnabled = false,
    bool transcodeAllowed = false,
    String? authUser,
    String? authPass,
    bool stopIfIdle = true,
  }) async {
    if (!_supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('startServer', {
        'port': port,
        'rootUri': rootUri,
        'uploadsEnabled': uploadsEnabled,
        'transcodeAllowed': transcodeAllowed,
        'authUser': authUser,
        'authPass': authPass,
        'stopIfIdle': stopIfIdle,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      print('FileServerService.startServer failed: ${e.message}');
      return false;
    }
  }

  /// Applies Basic-auth credentials to the (possibly running) server.
  /// A null/empty [user] switches back to anonymous access.
  Future<void> setAuth(String? user, String? pass) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('setAuth', {'user': user, 'pass': pass});
    } on PlatformException catch (e) {
      print('FileServerService.setAuth failed: ${e.message}');
    }
  }

  /// Sends a logical remote-control key ('up', 'down', 'left', 'right', 'ok',
  /// 'back', 'playpause', 'seekback', 'seekfwd') to connected browsers.
  Future<void> sendRemoteKey(String key) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('sendRemoteKey', {'key': key});
    } on PlatformException catch (e) {
      print('FileServerService.sendRemoteKey failed: ${e.message}');
    }
  }

  /// Seeks the TV player to an absolute position (seconds).
  Future<void> seekTo(double seconds) =>
      sendRemoteKey('seek:${seconds.toStringAsFixed(2)}');

  /// Sets the TV player's volume (0..1).
  Future<void> setVolume(double volume) =>
      sendRemoteKey('vol:${volume.clamp(0.0, 1.0).toStringAsFixed(2)}');

  /// Sends search text to connected browsers (lands in the library search box).
  Future<void> sendRemoteText(String text) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('sendRemoteText', {'text': text});
    } on PlatformException catch (e) {
      print('FileServerService.sendRemoteText failed: ${e.message}');
    }
  }

  /// A crisp native vibrator click for remote-button feedback (Flutter's
  /// HapticFeedback is gated by the system touch-feedback setting on Android).
  Future<void> hapticTick() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('hapticTick');
    } on PlatformException {
      // Non-essential; ignore.
    }
  }

  /// Number of browsers currently listening for remote-control input.
  Future<int> getRemoteClients() async {
    if (!_supported) return 0;
    try {
      return await _channel.invokeMethod<int>('getRemoteClients') ?? 0;
    } on PlatformException catch (e) {
      print('FileServerService.getRemoteClients failed: ${e.message}');
      return 0;
    }
  }

  /// Enables/disables browser uploads on the (possibly running) server.
  Future<void> setUploadsEnabled(bool enabled) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('setUploadsEnabled', {'enabled': enabled});
    } on PlatformException catch (e) {
      print('FileServerService.setUploadsEnabled failed: ${e.message}');
    }
  }

  /// Enables/disables on-device Tier-3 transcoding (a hardware-costly full
  /// re-encode) on the (possibly running) server. Off by default — the player
  /// only offers it as a last-resort fallback when this is on.
  Future<void> setTranscodeAllowed(bool enabled) async {
    if (!_supported) return;
    try {
      await _channel
          .invokeMethod<void>('setTranscodeAllowed', {'enabled': enabled});
    } on PlatformException catch (e) {
      print('FileServerService.setTranscodeAllowed failed: ${e.message}');
    }
  }

  /// Ongoing Tier-3 jobs plus the last 20 finished ones (see TranscodeController).
  Future<TranscodeLog> getTranscodeLog() async {
    if (!_supported) return const TranscodeLog(ongoing: [], history: []);
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getTranscodeLog');
      if (result == null) return const TranscodeLog(ongoing: [], history: []);
      final ongoing = (result['ongoing'] as List<dynamic>? ?? [])
          .map((m) => TranscodeOngoing.fromMap(Map<dynamic, dynamic>.from(m as Map)))
          .toList();
      final history = (result['history'] as List<dynamic>? ?? [])
          .map((m) => TranscodeLogEntry.fromMap(Map<dynamic, dynamic>.from(m as Map)))
          .toList();
      return TranscodeLog(ongoing: ongoing, history: history);
    } on PlatformException catch (e) {
      print('FileServerService.getTranscodeLog failed: ${e.message}');
      return const TranscodeLog(ongoing: [], history: []);
    }
  }

  /// Total bytes moved (served + uploaded) since the server last started.
  Future<int> getTotalBytes() async {
    if (!_supported) return 0;
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getTrafficStats');
      return (result?['totalBytes'] as int?) ?? 0;
    } on PlatformException catch (e) {
      print('FileServerService.getTotalBytes failed: ${e.message}');
      return 0;
    }
  }

  /// Whether the native server is currently running (and on which port).
  Future<FileServerStatus> getStatus() async {
    if (!_supported) return FileServerStatus.stopped;
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getStatus');
      if (result == null) return FileServerStatus.stopped;
      return FileServerStatus(
        running: (result['running'] as bool?) ?? false,
        port: (result['port'] as int?) ?? -1,
        requestCount: (result['requestCount'] as int?) ?? 0,
      );
    } on PlatformException catch (e) {
      print('FileServerService.getStatus failed: ${e.message}');
      return FileServerStatus.stopped;
    }
  }

  Future<bool> stopServer() async {
    if (!_supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('stopServer');
      return ok ?? false;
    } on PlatformException catch (e) {
      print('FileServerService.stopServer failed: ${e.message}');
      return false;
    }
  }

  /// The device's current local Wi-Fi IPv4 address, or null if not connected.
  Future<String?> getLocalIp() async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>('getLocalIp');
    } on PlatformException catch (e) {
      print('FileServerService.getLocalIp failed: ${e.message}');
      return null;
    }
  }

  /// Starts an incremental library scan of [rootUri] (or the saved folder).
  Future<bool> scanLibrary({String? rootUri}) async {
    if (!_supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('scanLibrary', {
        if (rootUri != null) 'rootUri': rootUri,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      print('FileServerService.scanLibrary failed: ${e.message}');
      return false;
    }
  }

  Future<bool> cancelScan() async {
    if (!_supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('cancelScan');
      return ok ?? false;
    } on PlatformException catch (e) {
      print('FileServerService.cancelScan failed: ${e.message}');
      return false;
    }
  }

  Future<bool> isScanning() async {
    if (!_supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('isScanning');
      return ok ?? false;
    } on PlatformException catch (e) {
      print('FileServerService.isScanning failed: ${e.message}');
      return false;
    }
  }
}
