import '../entities/saved_base_url.dart';

/// App-wide library of named pass-through base URLs, shared by every server.
abstract class SavedBaseUrlRepository {
  /// Most recently used first.
  List<SavedBaseUrl> getAll();

  /// The saved entry for [url] (normalized), if any.
  SavedBaseUrl? find(String url);

  /// Adds or renames the entry for [url] and marks it used now.
  Future<void> save(String url, String name);

  /// Bumps [url] to most-recent; no-op when it isn't saved.
  Future<void> markUsed(String url);

  Future<void> delete(String url);
}
