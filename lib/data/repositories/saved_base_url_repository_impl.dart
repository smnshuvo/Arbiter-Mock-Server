import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/saved_base_url.dart';
import '../../domain/repositories/saved_base_url_repository.dart';

/// Stored as one JSON list in SharedPreferences — a handful of entries, read
/// synchronously so menus can build straight from it.
class SavedBaseUrlRepositoryImpl implements SavedBaseUrlRepository {
  static const _key = 'saved_pass_through_urls';

  final SharedPreferences prefs;
  final DateTime Function() _now;

  SavedBaseUrlRepositoryImpl(this.prefs, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  @override
  List<SavedBaseUrl> getAll() {
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = [
        for (final e in jsonDecode(raw) as List) SavedBaseUrl.fromJson(e as Map<String, dynamic>),
      ];
      return list..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    } catch (_) {
      return [];
    }
  }

  @override
  SavedBaseUrl? find(String url) {
    final normalized = SavedBaseUrl.normalize(url);
    for (final entry in getAll()) {
      if (entry.url == normalized) return entry;
    }
    return null;
  }

  @override
  Future<void> save(String url, String name) async {
    final normalized = SavedBaseUrl.normalize(url);
    if (normalized.isEmpty) return;
    final entries = getAll()..removeWhere((e) => e.url == normalized);
    entries.add(SavedBaseUrl(name: name.trim(), url: normalized, lastUsedAt: _now()));
    await _write(entries);
  }

  @override
  Future<void> markUsed(String url) async {
    final normalized = SavedBaseUrl.normalize(url);
    final entries = getAll();
    final i = entries.indexWhere((e) => e.url == normalized);
    if (i < 0) return;
    entries[i] = entries[i].copyWith(lastUsedAt: _now());
    await _write(entries);
  }

  @override
  Future<void> delete(String url) async {
    final normalized = SavedBaseUrl.normalize(url);
    await _write(getAll()..removeWhere((e) => e.url == normalized));
  }

  Future<void> _write(List<SavedBaseUrl> entries) =>
      prefs.setString(_key, jsonEncode([for (final e in entries) e.toJson()]));
}
