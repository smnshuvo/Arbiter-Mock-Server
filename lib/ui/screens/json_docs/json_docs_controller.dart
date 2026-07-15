import 'package:flutter/widgets.dart';

import '../../../core/services/json_document_service.dart';

/// One open .json document (a tab).
class JsonDoc {
  JsonDoc({required this.path, required String content})
      : controller = TextEditingController(text: content),
        _saved = content;

  final String path;
  final TextEditingController controller;
  String _saved;
  bool saving = false;

  String get fileName => path.split('/').last;
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

  bool get isEmpty => docs.isEmpty;
  JsonDoc? get active =>
      (activeIndex >= 0 && activeIndex < docs.length) ? docs[activeIndex] : null;

  /// Opens a file into a new tab (or activates it if already open).
  Future<void> openPath(String path) async {
    final existing = docs.indexWhere((d) => d.path == path);
    if (existing >= 0) {
      activeIndex = existing;
      notifyListeners();
      return;
    }
    final content = await _svc.read(path) ?? '';
    docs.add(JsonDoc(path: path, content: content));
    activeIndex = docs.length - 1;
    notifyListeners();
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
    final ok = await _svc.write(doc.path, doc.controller.text);
    if (ok) doc.markSaved();
    doc.saving = false;
    notifyListeners();
    return ok;
  }

  /// Notifies listeners so tab dirty-dots update as the editor changes.
  void touch() => notifyListeners();
}
