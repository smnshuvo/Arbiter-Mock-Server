import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A recently opened JSON document, shown on the Android recent-files screen.
class RecentFile {
  const RecentFile({
    required this.path,
    required this.name,
    required this.openedAt,
    this.size,
    this.modified,
  });

  /// File path (macOS) or content:// URI (Android).
  final String path;
  final String name;

  /// Size in bytes, when known.
  final int? size;

  /// Last-modified time (epoch ms), when known.
  final int? modified;

  /// When this file was last opened in the app (epoch ms).
  final int openedAt;

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'size': size,
        'modified': modified,
        'openedAt': openedAt,
      };

  factory RecentFile.fromJson(Map<String, dynamic> json) => RecentFile(
        path: json['path'] as String,
        name: json['name'] as String? ?? '',
        size: (json['size'] as num?)?.toInt(),
        modified: (json['modified'] as num?)?.toInt(),
        openedAt: (json['openedAt'] as num?)?.toInt() ?? 0,
      );
}

/// Persists the list of recently opened JSON documents (newest first).
class RecentFilesStore {
  RecentFilesStore._();
  static final RecentFilesStore instance = RecentFilesStore._();

  static const _key = 'json_recent_files';
  static const _max = 40;

  Future<List<RecentFile>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw) as List;
      return data
          .map((e) => RecentFile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return []; // corrupt storage — start fresh rather than crash
    }
  }

  /// Adds (or refreshes) an entry, moving it to the front and de-duping by path.
  Future<void> add(RecentFile file) async {
    final items = await list()..removeWhere((e) => e.path == file.path);
    items.insert(0, file);
    if (items.length > _max) items.removeRange(_max, items.length);
    await _save(items);
  }

  Future<void> remove(String path) async {
    final items = await list()..removeWhere((e) => e.path == path);
    await _save(items);
  }

  Future<void> _save(List<RecentFile> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }
}
