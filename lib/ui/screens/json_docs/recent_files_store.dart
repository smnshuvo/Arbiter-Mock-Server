import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One entry in the recent-files list.
class RecentFile {
  RecentFile({
    required this.path,
    required this.name,
    this.size,
    this.modified,
    required this.openedAt,
  });

  final String path; // file path (macOS) or content:// URI (Android)
  final String name;
  final int? size; // bytes
  final int? modified; // epoch ms
  final int openedAt; // epoch ms

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'size': size,
        'modified': modified,
        'openedAt': openedAt,
      };

  factory RecentFile.fromJson(Map<String, dynamic> j) => RecentFile(
        path: j['path'] as String,
        name: j['name'] as String? ?? '',
        size: (j['size'] as num?)?.toInt(),
        modified: (j['modified'] as num?)?.toInt(),
        openedAt: (j['openedAt'] as num?)?.toInt() ?? 0,
      );
}

/// Persists recently opened JSON documents (most-recent first).
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
      return [];
    }
  }

  Future<void> add(RecentFile file) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await list()..removeWhere((e) => e.path == file.path);
    items.insert(0, file);
    if (items.length > _max) items.removeRange(_max, items.length);
    await prefs.setString(
        _key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> remove(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await list()..removeWhere((e) => e.path == path);
    await prefs.setString(
        _key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }
}
