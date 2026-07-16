import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../core/theme/arbiter_tokens.dart';

enum JsonType { string, number, boolean, nullType, object, array }

/// One editable node in the JSON tree. Objects/arrays hold [children];
/// scalars hold a string [value] (coerced at serialize time).
class _JsonNode {
  _JsonNode({
    required this.id,
    required this.key,
    required this.type,
    this.value = '',
    List<_JsonNode>? children,
  }) : children = children ?? [] {
    keyController = TextEditingController(text: key);
    valueController = TextEditingController(text: value);
  }

  final int id;
  String key;
  JsonType type;
  String value;
  List<_JsonNode> children;
  bool collapsed = false;
  bool keyExpanded = false; // enlarge the (otherwise compact) key field

  late final TextEditingController keyController;
  late final TextEditingController valueController;

  bool get isContainer => type == JsonType.object || type == JsonType.array;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
    for (final c in children) {
      c.dispose();
    }
  }
}

/// A visual JSON tree editor. Consumes a **valid** JSON string and emits the
/// serialized JSON on every edit. Supports arbitrarily nested objects/arrays,
/// per-item duplicate and delete, and inline type changes.
class JsonFormEditor extends StatefulWidget {
  const JsonFormEditor({
    super.key,
    required this.initialJson,
    required this.onChanged,
  });

  final String initialJson;
  final ValueChanged<String> onChanged;

  @override
  State<JsonFormEditor> createState() => _JsonFormEditorState();
}

class _JsonFormEditorState extends State<JsonFormEditor> {
  int _idSeq = 0;
  late _JsonNode _root;

  @override
  void initState() {
    super.initState();
    _root = _build(_decode(widget.initialJson), '');
  }

  @override
  void dispose() {
    _root.dispose();
    super.dispose();
  }

  dynamic _decode(String raw) {
    try {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return <String, dynamic>{};
      return jsonDecode(trimmed);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  _JsonNode _build(dynamic value, String key) {
    final id = _idSeq++;
    if (value is Map) {
      return _JsonNode(
        id: id,
        key: key,
        type: JsonType.object,
        children: value.entries
            .map((e) => _build(e.value, e.key.toString()))
            .toList(),
      );
    }
    if (value is List) {
      return _JsonNode(
        id: id,
        key: key,
        type: JsonType.array,
        children: value.map((v) => _build(v, '')).toList(),
      );
    }
    if (value is bool) {
      return _JsonNode(
          id: id, key: key, type: JsonType.boolean, value: value.toString());
    }
    if (value is num) {
      return _JsonNode(
          id: id, key: key, type: JsonType.number, value: value.toString());
    }
    if (value == null) {
      return _JsonNode(id: id, key: key, type: JsonType.nullType);
    }
    return _JsonNode(
        id: id, key: key, type: JsonType.string, value: value.toString());
  }

  /// Deep-copy a node (fresh ids + controllers) for duplication.
  _JsonNode _clone(_JsonNode node) {
    return _JsonNode(
      id: _idSeq++,
      key: node.key,
      type: node.type,
      value: node.value,
      children: node.children.map(_clone).toList(),
    )..collapsed = node.collapsed;
  }

  dynamic _toValue(_JsonNode node) {
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

  void _emit() {
    const encoder = JsonEncoder.withIndent('  ');
    widget.onChanged(encoder.convert(_toValue(_root)));
  }

  void _addChild(_JsonNode parent) {
    setState(() {
      parent.collapsed = false;
      parent.children.add(_JsonNode(id: _idSeq++, key: '', type: JsonType.string));
    });
    _emit();
  }

  void _duplicate(_JsonNode parent, _JsonNode node) {
    setState(() {
      final index = parent.children.indexOf(node);
      parent.children.insert(index + 1, _clone(node));
    });
    _emit();
  }

  void _remove(_JsonNode parent, _JsonNode child) {
    setState(() {
      parent.children.remove(child);
      child.dispose();
    });
    _emit();
  }

  void _changeType(_JsonNode node, JsonType type) {
    setState(() {
      if (node.isContainer && !_isContainerType(type)) {
        for (final c in node.children) {
          c.dispose();
        }
        node.children = [];
      }
      node.type = type;
      if (type == JsonType.boolean &&
          node.value.toLowerCase() != 'true' &&
          node.value.toLowerCase() != 'false') {
        node.value = 'true';
        node.valueController.text = 'true';
      }
    });
    _emit();
  }

  bool _isContainerType(JsonType t) =>
      t == JsonType.object || t == JsonType.array;

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final rootIsContainer = _root.isContainer;

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(t.radius),
      ),
      padding: const EdgeInsets.all(11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rootIsContainer)
            ..._renderChildren(_root, 0)
          else
            _row(_root, _root, isArrayItem: false, index: 0, depth: 0),
          if (rootIsContainer) ...[
            const SizedBox(height: 10),
            _addButton(
              t,
              _root.type == JsonType.array ? '＋ Add item' : '＋ Add field',
              () => _addChild(_root),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _renderChildren(_JsonNode parent, int depth) {
    final rows = <Widget>[];
    final isArray = parent.type == JsonType.array;
    for (var i = 0; i < parent.children.length; i++) {
      final child = parent.children[i];
      rows.add(_row(parent, child,
          isArrayItem: isArray, index: i, depth: depth));
      if (child.isContainer && !child.collapsed) {
        rows.addAll(_renderChildren(child, depth + 1));
        final t = ArbTokens.of(context);
        rows.add(CustomPaint(
          painter:
              _GuidesPainter(depth: depth + 1, colorFor: (i) => t.depthColor(i)),
          child: Padding(
            padding:
                EdgeInsets.only(left: 14.0 * (depth + 1) + 8, top: 2, bottom: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _inlineAdd(
                child.type == JsonType.array ? 'Add item' : 'Add field',
                () => _addChild(child),
              ),
            ),
          ),
        ));
      }
    }
    return rows;
  }

  Widget _row(
    _JsonNode parent,
    _JsonNode node, {
    required bool isArrayItem,
    required int index,
    required int depth,
  }) {
    final t = ArbTokens.of(context);
    final isRoot = node == _root;

    const compactKeyW = 104.0;
    final isObjectKey = !isRoot && !isArrayItem;
    // Measure the actual key text so the toggle appears whenever it's clipped
    // (even by a character or two), not on a rough length guess.
    final keyTextW = isObjectKey ? _keyTextWidth(node.key, t) : 0.0;
    final clipped = keyTextW > compactKeyW - 22;
    final showToggle = isObjectKey && (clipped || node.keyExpanded);

    // Inner content sized precisely; action icons stay pinned on the right.
    final inner = LayoutBuilder(
      builder: (context, constraints) {
        // When enlarged, take exactly the width the key needs (capped so the
        // value stays visible); otherwise stay compact.
        double keyW = compactKeyW;
        if (isObjectKey && node.keyExpanded) {
          final maxKeyW = (constraints.maxWidth - 150).clamp(compactKeyW, constraints.maxWidth);
          keyW = (keyTextW + 26).clamp(compactKeyW, maxKeyW);
        }
        return Row(
          children: [
            if (node.isContainer)
              _iconBtn(
                node.collapsed ? Icons.chevron_right : Icons.expand_more,
                () => setState(() => node.collapsed = !node.collapsed),
              )
            else
              const SizedBox(width: 24),
            if (!isRoot && isArrayItem)
              Container(
                constraints: const BoxConstraints(minWidth: 24),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child:
                    Text('$index', style: t.mono(size: 12, color: t.textMuted)),
              )
            else if (!isRoot)
              SizedBox(
                width: keyW,
                child: _miniField(node.keyController, 'key', (v) {
                  node.key = v;
                  setState(() {});
                  _emit();
                }),
              ),
            if (showToggle)
              _iconBtn(
                node.keyExpanded ? Icons.chevron_left : Icons.chevron_right,
                () => setState(() => node.keyExpanded = !node.keyExpanded),
                color: t.textMuted,
                tooltip: node.keyExpanded ? 'Shrink field' : 'Show full name',
              ),
            const SizedBox(width: 6),
            _typeButton(node),
            const SizedBox(width: 6),
            Expanded(child: _valueEditor(node)),
          ],
        );
      },
    );

    return CustomPaint(
      painter: _GuidesPainter(depth: depth, colorFor: (i) => t.depthColor(i)),
      child: Padding(
        padding: EdgeInsets.only(left: 14.0 * depth, top: 3, bottom: 3),
        child: Row(
          children: [
            Expanded(child: inner),
            if (!isRoot) ...[
              _iconBtn(Icons.copy_all_outlined, () => _duplicate(parent, node),
                  color: t.textMuted, tooltip: 'Duplicate'),
              _iconBtn(Icons.delete_outline, () => _remove(parent, node),
                  color: t.textMuted, tooltip: 'Delete'),
            ],
          ],
        ),
      ),
    );
  }

  /// Rendered width of the key text in the field's font, used to decide when
  /// the enlarge toggle is needed and how wide the enlarged field should be.
  double _keyTextWidth(String text, ArbTokens t) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: t.mono(size: 13)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  Widget _valueEditor(_JsonNode node) {
    final t = ArbTokens.of(context);
    switch (node.type) {
      case JsonType.object:
        return Text('{ ${node.children.length} }',
            style: t.mono(size: 12, color: t.textMuted));
      case JsonType.array:
        return Text('[ ${node.children.length} ]',
            style: t.mono(size: 12, color: t.textMuted));
      case JsonType.nullType:
        return Text('null', style: t.mono(size: 13, color: t.textMuted));
      case JsonType.boolean:
        final isTrue = node.value.toLowerCase() == 'true';
        return Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                node.value = (!isTrue).toString();
                node.valueController.text = node.value;
              });
              _emit();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: t.border),
              foregroundColor: isTrue ? t.green : t.textSecondary,
            ),
            child: Text(node.value,
                style: t.mono(
                    size: 12,
                    weight: FontWeight.w600,
                    color: isTrue ? t.green : t.textSecondary)),
          ),
        );
      case JsonType.number:
        return _miniField(node.valueController, '0', (v) {
          node.value = v;
          _emit();
        }, mono: true);
      case JsonType.string:
        return _miniField(node.valueController, 'value', (v) {
          node.value = v;
          _emit();
        }, mono: true);
    }
  }

  Widget _typeButton(_JsonNode node) {
    final t = ArbTokens.of(context);
    return PopupMenuButton<JsonType>(
      tooltip: 'Change type',
      padding: EdgeInsets.zero,
      onSelected: (type) => _changeType(node, type),
      itemBuilder: (_) => [
        for (final type in JsonType.values)
          PopupMenuItem(value: type, child: Text(_typeLabel(type))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: t.surfaceMuted,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _typeLabel(node.type),
          style:
              t.mono(size: 10, weight: FontWeight.w700, color: t.textSecondary),
        ),
      ),
    );
  }

  String _typeLabel(JsonType type) {
    switch (type) {
      case JsonType.string:
        return 'str';
      case JsonType.number:
        return 'num';
      case JsonType.boolean:
        return 'bool';
      case JsonType.nullType:
        return 'null';
      case JsonType.object:
        return '{ }';
      case JsonType.array:
        return '[ ]';
    }
  }

  Widget _miniField(
    TextEditingController controller,
    String hint,
    ValueChanged<String> onChanged, {
    bool mono = false,
  }) {
    final t = ArbTokens.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: mono ? t.mono(size: 13) : t.sans(size: 13, weight: FontWeight.w500),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: t.mono(size: 12, color: t.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        filled: true,
        fillColor: t.canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: t.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: t.accent),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap,
      {Color? color, String? tooltip}) {
    final t = ArbTokens.of(context);
    final button = InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: color ?? t.textSecondary),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }

  Widget _inlineAdd(String label, VoidCallback onTap) {
    final t = ArbTokens.of(context);
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(Icons.add, size: 14, color: t.textSecondary),
      label: Text(label,
          style:
              t.sans(size: 11, weight: FontWeight.w700, color: t.textSecondary)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _addButton(ArbTokens t, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(t.radiusSm),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.radiusSm),
          border: Border.all(color: t.border, width: 1.5),
        ),
        child: Center(
          child: Text(label,
              style: t.sans(
                  size: 12, weight: FontWeight.w700, color: t.textSecondary)),
        ),
      ),
    );
  }
}

/// Paints dashed vertical nesting-guide lines down the left indent of a row,
/// one per ancestor depth, colored by [ArbTokens.depthColor]. Consecutive rows
/// stack so the dashes read as continuous tree lines.
class _GuidesPainter extends CustomPainter {
  _GuidesPainter({required this.depth, required this.colorFor});

  final int depth;
  final Color Function(int) colorFor;

  static const double _step = 14;
  static const double _dash = 3;
  static const double _gap = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < depth; i++) {
      final paint = Paint()
        ..color = colorFor(i).withValues(alpha: 0.5)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      final x = _step * i + 7;
      var y = 0.0;
      while (y < size.height) {
        canvas.drawLine(
            Offset(x, y), Offset(x, math.min(y + _dash, size.height)), paint);
        y += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_GuidesPainter old) => old.depth != depth;
}
