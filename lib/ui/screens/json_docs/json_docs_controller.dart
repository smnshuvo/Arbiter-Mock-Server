import 'package:flutter/widgets.dart';

import '../../../core/services/json_document_service.dart';
import '../endpoint_editor/widgets/json_brace_controller.dart';
import 'recent_files_store.dart';

/// One open .json document (a tab).
class JsonDoc {
  JsonDoc({required this.path, required this.title, required String content})
      : controller = JsonBraceController(text: content),
        _saved = content;

  /// File path (macOS) or content:// URI (Android). May change after a Save-As.
  String path;

  /// Friendly document name (content-URI safe); shown on the tab and toolbar.
  String title;
  final TextEditingController controller;
  String _saved;
  bool saving = false;

  String get fileName => title;
  bool get dirty => controller.text != _saved;

  void markSaved() => _saved = controller.text;
  void dispose() => controller.dispose();
}

/// Shared state for the tabbed JSON document window. A single instance is used
/// so files opened at launch and while running land in the same tab strip.
class JsonDocsController extends ChangeNotifier {
  JsonDocsController._();
  static final JsonDocsController instance = JsonDocsController._();

  final _svc = JsonDocumentService.instance;
  final List<JsonDoc> docs = [];
  int activeIndex = 0;
  int _opening = 0;

  /// Android keeps a single document in memory (RAM-friendly) and records a
  /// recent-files list instead of a multi-tab window.
  bool singleDocument = false;

  /// True while one or more files are being read/opened.
  bool get opening => _opening > 0;
  bool get isEmpty => docs.isEmpty;
  JsonDoc? get active =>
      (activeIndex >= 0 && activeIndex < docs.length) ? docs[activeIndex] : null;

  /// Opens a file into a tab (or activates it if already open). Returns false
  /// when the content can't be read (e.g. an expired Android URI grant).
  Future<bool> openPath(String path) async {
    final existing = docs.indexWhere((d) => d.path == path);
    if (existing >= 0) {
      activeIndex = existing;
      notifyListeners();
      return true;
    }
    _opening++;
    notifyListeners();
    try {
      // Android: only one document in memory at a time.
      if (singleDocument) {
        for (final d in docs) {
          d.dispose();
        }
        docs.clear();
      }
      final raw = await _svc.read(path);
      // Android read failure (lost grant) — don't create an empty document.
      if (raw == null && singleDocument) return false;
      final title = await _svc.displayName(path);
      docs.add(JsonDoc(path: path, title: title, content: raw ?? ''));
      activeIndex = docs.length - 1;
      if (singleDocument) {
        final info = await _svc.fileInfo(path);
        await RecentFilesStore.instance.add(RecentFile(
          path: path,
          name: info.name,
          size: info.size,
          modified: info.modified,
          openedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
      return true;
    } finally {
      _opening--;
      notifyListeners();
    }
  }

  void select(int index) {
    if (index < 0 || index >= docs.length) return;
    activeIndex = index;
    notifyListeners();
  }

  void close(int index) {
    if (index < 0 || index >= docs.length) return;
    docs.removeAt(index).dispose();
    if (activeIndex >= docs.length) activeIndex = docs.length - 1;
    if (activeIndex < 0) activeIndex = 0;
    notifyListeners();
  }

  Future<bool> save(JsonDoc doc) async {
    doc.saving = true;
    notifyListeners();
    var ok = await _svc.write(doc.path, doc.controller.text);
    if (!ok) {
      // In-place write denied (common with read-only content:// opens on
      // Android) — let the user choose a writable location instead.
      final newPath = await _svc.saveAs(doc.controller.text, doc.title);
      if (newPath != null) {
        doc.path = newPath;
        doc.title = await _svc.displayName(newPath);
        ok = true;
      }
    }
    if (ok) doc.markSaved();
    doc.saving = false;
    notifyListeners();
    return ok;
  }

  /// Explicit "Save as…": always prompts for a location (Android). Returns true
  /// if the document was saved to a new location.
  Future<bool> saveAsExplicit(JsonDoc doc) async {
    doc.saving = true;
    notifyListeners();
    final newPath = await _svc.saveAs(doc.controller.text, doc.title);
    var ok = false;
    if (newPath != null) {
      doc.path = newPath;
      doc.title = await _svc.displayName(newPath);
      doc.markSaved();
      ok = true;
    }
    doc.saving = false;
    notifyListeners();
    return ok;
  }

  /// Notifies listeners so tab dirty-dots update as the editor changes.
  void touch() => notifyListeners();
}
