import 'dart:convert';

import 'package:flutter/foundation.dart';

enum JsonType { string, number, boolean, nullType, object, array }

bool isContainerType(JsonType t) =>
    t == JsonType.object || t == JsonType.array;

/// One node in the JSON tree. Deliberately holds **no** TextEditingControllers:
/// rows create those lazily for the handful of nodes actually on screen.
class JsonNode {
  JsonNode({
    required this.id,
    required this.key,
    required this.type,
    this.value = '',
    List<JsonNode>? children,
  }) : children = children ?? [];

  final int id;
  String key;
  JsonType type;
  String value;
  List<JsonNode> children;

  /// View state (not part of the document).
  bool collapsed = false;
  bool keyExpanded = false;

  /// Cached rendered width of [key]; invalidated whenever the key changes so we
  /// don't run a TextPainter layout per row on every build.
  double? keyWidthCache;

  bool get isContainer => isContainerType(type);
}

enum JsonRowKind {
  /// A key/value row.
  node,

  /// The inline "Add field/item" affordance under an expanded container.
  addChild,

  /// The full-width dashed add button at the end of the root container.
  rootAdd,
}

/// A single visible line in the flattened tree — what `ListView.builder` and
/// `SliverList` render.
class JsonRow {
  const JsonRow({
    required this.node,
    required this.parent,
    required this.depth,
    required this.isArrayItem,
    required this.index,
    required this.kind,
  });

  /// For [JsonRowKind.node] the node itself; for the add kinds, the container
  /// being added into.
  final JsonNode node;
  final JsonNode? parent;
  final int depth;
  final bool isArrayItem;
  final int index;
  final JsonRowKind kind;

  /// Stable identity so list recycling never reuses a row's State across nodes.
  Key get widgetKey => ValueKey('${kind.name}-${node.id}');
}

// Top-level so they can run in an isolate via compute().
Object? _decodeJson(String source) => jsonDecode(source);
String _encodeJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

/// Owns the JSON tree and the flattened list of visible rows.
///
/// The tree is the source of truth: text edits mutate nodes in place and do
/// **not** serialize or rebuild the list (that used to run `jsonEncode` over the
/// whole document on every keystroke). [toJson] is pulled on demand — on save or
/// when switching to the Code tab. Structural edits rebuild the row list and
/// notify; [onDirty] fires once on the clean→dirty transition.
class JsonTreeController extends ChangeNotifier {
  /// Above this many nodes the tree loads collapsed below the root.
  static const int largeDocNodes = 200;

  /// Above this many bytes/nodes, decode/encode moves to an isolate.
  static const int computeBytesThreshold = 256 * 1024;
  static const int computeNodesThreshold = 5000;

  int _idSeq = 0;
  JsonNode _root = JsonNode(id: -1, key: '', type: JsonType.object);
  List<JsonRow> _rows = const [];
  bool _dirty = false;

  /// Fired once when the document first becomes dirty.
  VoidCallback? onDirty;

  List<JsonRow> get rows => _rows;
  JsonNode get root => _root;
  bool get isDirty => _dirty;

  // ---- Loading ----

  /// Builds the tree from [raw]. Large payloads decode in an isolate so the UI
  /// thread never blocks.
  Future<void> parse(String raw) async {
    final trimmed = raw.trim();
    dynamic decoded;
    try {
      if (trimmed.isEmpty) {
        decoded = <String, dynamic>{};
      } else if (trimmed.length > computeBytesThreshold) {
        decoded = await compute(_decodeJson, trimmed);
      } else {
        decoded = jsonDecode(trimmed);
      }
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    _idSeq = 0;
    _root = _build(decoded, '');
    _applySmartCollapse();
    _dirty = false;
    _rebuildRows();
    notifyListeners();
  }

  // ---- Serializing (on demand only) ----

  /// Synchronous serialize — fine for small documents (e.g. mock responses).
  String toJsonSync() => _encodeJson(_toValue(_root));

  /// Serializes, hopping to an isolate for large trees.
  Future<String> toJson() async {
    final value = _toValue(_root);
    if (_nodeCount(_root) > computeNodesThreshold) {
      return compute(_encodeJson, value);
    }
    return _encodeJson(value);
  }

  void markSaved() => _dirty = false;

  // ---- Edits ----

  /// Text edits: mutate in place, no list rebuild, no serialize.
  void setKey(JsonNode node, String value) {
    node.key = value;
    node.keyWidthCache = null;
    _markDirty();
  }

  void setValue(JsonNode node, String value) {
    node.value = value;
    _markDirty();
  }

  /// View-only; does not dirty the document.
  void toggleCollapse(JsonNode node) {
    node.collapsed = !node.collapsed;
    _rebuildRows();
    notifyListeners();
  }

  void addChild(JsonNode parent) {
    parent.collapsed = false;
    parent.children
        .add(JsonNode(id: _idSeq++, key: '', type: JsonType.string));
    _structuralChange();
  }

  void remove(JsonNode parent, JsonNode child) {
    parent.children.remove(child);
    _structuralChange();
  }

  void duplicate(JsonNode parent, JsonNode node) {
    final i = parent.children.indexOf(node);
    if (i < 0) return;
    parent.children.insert(i + 1, _clone(node));
    _structuralChange();
  }

  void changeType(JsonNode node, JsonType type) {
    if (node.isContainer && !isContainerType(type)) node.children = [];
    node.type = type;
    final v = node.value.toLowerCase();
    if (type == JsonType.boolean && v != 'true' && v != 'false') {
      node.value = 'true';
    }
    _structuralChange();
  }

  void _structuralChange() {
    _markDirty();
    _rebuildRows();
    notifyListeners();
  }

  void _markDirty() {
    if (_dirty) return;
    _dirty = true;
    onDirty?.call(); // once, not per keystroke
  }

  // ---- Internals ----

  JsonNode _build(dynamic value, String key) {
    final id = _idSeq++;
    if (value is Map) {
      return JsonNode(
        id: id,
        key: key,
        type: JsonType.object,
        children:
            value.entries.map((e) => _build(e.value, e.key.toString())).toList(),
      );
    }
    if (value is List) {
      return JsonNode(
        id: id,
        key: key,
        type: JsonType.array,
        children: value.map((v) => _build(v, '')).toList(),
      );
    }
    if (value is bool) {
      return JsonNode(
          id: id, key: key, type: JsonType.boolean, value: value.toString());
    }
    if (value is num) {
      return JsonNode(
          id: id, key: key, type: JsonType.number, value: value.toString());
    }
    if (value == null) return JsonNode(id: id, key: key, type: JsonType.nullType);
    return JsonNode(
        id: id, key: key, type: JsonType.string, value: value.toString());
  }

  JsonNode _clone(JsonNode node) => JsonNode(
        id: _idSeq++,
        key: node.key,
        type: node.type,
        value: node.value,
        children: node.children.map(_clone).toList(),
      )..collapsed = node.collapsed;

  dynamic _toValue(JsonNode node) {
    switch (node.type) {
      case JsonType.object:
        final map = <String, dynamic>{};
        for (final c in node.children) {
          map[c.key] = _toValue(c);
        }
        return map;
      case JsonType.array:
        return node.children.map(_toValue).toList();
      case JsonType.boolean:
        return node.value.toLowerCase() == 'true';
      case JsonType.number:
        return num.tryParse(node.value.trim()) ?? 0;
      case JsonType.nullType:
        return null;
      case JsonType.string:
        return node.value;
    }
  }

  int _nodeCount(JsonNode node) {
    var n = 1;
    for (final c in node.children) {
      n += _nodeCount(c);
    }
    return n;
  }

  /// Big documents load collapsed below the root so the first paint is cheap and
  /// you drill into what you need; small ones stay fully expanded.
  void _applySmartCollapse() {
    if (_nodeCount(_root) <= largeDocNodes) return;
    void walk(JsonNode n, int depth) {
      if (n.isContainer && depth >= 1) n.collapsed = true;
      for (final c in n.children) {
        walk(c, depth + 1);
      }
    }
    for (final c in _root.children) {
      walk(c, 1);
    }
  }

  void _rebuildRows() {
    final rows = <JsonRow>[];
    if (_root.isContainer) {
      _flatten(_root, 0, rows);
      rows.add(JsonRow(
        node: _root,
        parent: null,
        depth: 0,
        isArrayItem: false,
        index: -1,
        kind: JsonRowKind.rootAdd,
      ));
    } else {
      rows.add(JsonRow(
        node: _root,
        parent: null,
        depth: 0,
        isArrayItem: false,
        index: 0,
        kind: JsonRowKind.node,
      ));
    }
    _rows = rows;
  }

  void _flatten(JsonNode parent, int depth, List<JsonRow> out) {
    final isArray = parent.type == JsonType.array;
    for (var i = 0; i < parent.children.length; i++) {
      final child = parent.children[i];
      out.add(JsonRow(
        node: child,
        parent: parent,
        depth: depth,
        isArrayItem: isArray,
        index: i,
        kind: JsonRowKind.node,
      ));
      if (child.isContainer && !child.collapsed) {
        _flatten(child, depth + 1, out);
        out.add(JsonRow(
          node: child,
          parent: parent,
          depth: depth + 1,
          isArrayItem: false,
          index: -1,
          kind: JsonRowKind.addChild,
        ));
      }
    }
  }
}
