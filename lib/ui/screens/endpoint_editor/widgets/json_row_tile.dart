import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../../core/theme/arbiter_tokens.dart';
import 'json_tree_controller.dart';

/// One row of the JSON tree.
///
/// Owns its `TextEditingController`s for the lifetime of the row only — the
/// list builds ~15 of these at a time, so a huge document no longer allocates a
/// controller per node. Typing writes straight through to the node and rebuilds
/// **this row only**, never the whole editor.
class JsonRowTile extends StatefulWidget {
  const JsonRowTile({
    super.key,
    required this.row,
    required this.controller,
    required this.isRoot,
  });

  final JsonRow row;
  final JsonTreeController controller;
  final bool isRoot;

  @override
  State<JsonRowTile> createState() => _JsonRowTileState();
}

class _JsonRowTileState extends State<JsonRowTile> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _valueCtrl;

  static const double _compactKeyW = 104;

  JsonNode get _node => widget.row.node;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: _node.key);
    _valueCtrl = TextEditingController(text: _node.value);
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  /// Measured once per key, cached on the node.
  double _keyTextWidth(ArbTokens t) {
    final cached = _node.keyWidthCache;
    if (cached != null) return cached;
    final tp = TextPainter(
      text: TextSpan(text: _node.key, style: t.mono(size: 13)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return _node.keyWidthCache = tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final row = widget.row;
    final c = widget.controller;
    final isRoot = widget.isRoot;
    final isObjectKey = !isRoot && !row.isArrayItem;

    final keyTextW = isObjectKey ? _keyTextWidth(t) : 0.0;
    final clipped = keyTextW > _compactKeyW - 22;
    final showToggle = isObjectKey && (clipped || _node.keyExpanded);

    final inner = LayoutBuilder(
      builder: (context, constraints) {
        double keyW = _compactKeyW;
        if (isObjectKey && _node.keyExpanded) {
          final maxKeyW = (constraints.maxWidth - 150)
              .clamp(_compactKeyW, constraints.maxWidth);
          keyW = (keyTextW + 26).clamp(_compactKeyW, maxKeyW);
        }
        return Row(
          children: [
            if (_node.isContainer)
              _iconBtn(
                _node.collapsed ? Icons.chevron_right : Icons.expand_more,
                () => c.toggleCollapse(_node),
              )
            else
              const SizedBox(width: 24),
            if (!isRoot && row.isArrayItem)
              Container(
                constraints: const BoxConstraints(minWidth: 24),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text('${row.index}',
                    style: t.mono(size: 12, color: t.textMuted)),
              )
            else if (!isRoot)
              SizedBox(
                width: keyW,
                child: _miniField(_keyCtrl, 'key', (v) {
                  c.setKey(_node, v);
                  setState(() {}); // this row only — chevron may appear/vanish
                }),
              ),
            if (showToggle)
              _iconBtn(
                _node.keyExpanded ? Icons.chevron_left : Icons.chevron_right,
                () => setState(() => _node.keyExpanded = !_node.keyExpanded),
                color: t.textMuted,
                tooltip: _node.keyExpanded ? 'Shrink field' : 'Show full name',
              ),
            const SizedBox(width: 6),
            _typeButton(t),
            const SizedBox(width: 6),
            Expanded(child: _valueEditor(t)),
          ],
        );
      },
    );

    return CustomPaint(
      painter: JsonGuidesPainter(
          depth: row.depth, colorFor: (i) => t.depthColor(i)),
      child: Padding(
        padding: EdgeInsets.only(left: 14.0 * row.depth, top: 3, bottom: 3),
        child: Row(
          children: [
            Expanded(child: inner),
            if (!isRoot) _rowActions(t, c, row),
          ],
        ),
      ),
    );
  }

  /// Per-row Duplicate/Delete. On mobile these collapse into a single ⋮ menu so
  /// the small tap targets can't be mistouched; on desktop they stay as icons.
  Widget _rowActions(ArbTokens t, JsonTreeController c, JsonRow row) {
    const danger = Color(0xFFDC2626);
    if (Platform.isAndroid) {
      return PopupMenuButton<String>(
        tooltip: 'Row actions',
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        icon: Icon(Icons.more_horiz, size: 18, color: t.textMuted),
        onSelected: (v) {
          if (v == 'duplicate') c.duplicate(row.parent!, _node);
          if (v == 'delete') c.remove(row.parent!, _node);
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'duplicate',
            child: Row(children: [
              Icon(Icons.copy_all_outlined, size: 18, color: t.textSecondary),
              const SizedBox(width: 12),
              const Text('Duplicate'),
            ]),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              const Icon(Icons.delete_outline, size: 18, color: danger),
              const SizedBox(width: 12),
              const Text('Delete', style: TextStyle(color: danger)),
            ]),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconBtn(Icons.copy_all_outlined, () => c.duplicate(row.parent!, _node),
            color: t.textMuted, tooltip: 'Duplicate'),
        _iconBtn(Icons.delete_outline, () => c.remove(row.parent!, _node),
            color: t.textMuted, tooltip: 'Delete'),
      ],
    );
  }

  Widget _valueEditor(ArbTokens t) {
    switch (_node.type) {
      case JsonType.object:
        return Text('{ ${_node.children.length} }',
            style: t.mono(size: 12, color: t.textMuted));
      case JsonType.array:
        return Text('[ ${_node.children.length} ]',
            style: t.mono(size: 12, color: t.textMuted));
      case JsonType.nullType:
        return Text('null', style: t.mono(size: 13, color: t.textMuted));
      case JsonType.boolean:
        final isTrue = _node.value.toLowerCase() == 'true';
        return Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () {
              widget.controller.setValue(_node, (!isTrue).toString());
              _valueCtrl.text = _node.value;
              setState(() {});
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: t.border),
              foregroundColor: isTrue ? t.green : t.textSecondary,
            ),
            child: Text(_node.value,
                style: t.mono(
                    size: 12,
                    weight: FontWeight.w600,
                    color: isTrue ? t.green : t.textSecondary)),
          ),
        );
      case JsonType.number:
        return _miniField(_valueCtrl, '0',
            (v) => widget.controller.setValue(_node, v),
            mono: true);
      case JsonType.string:
        return _miniField(_valueCtrl, 'value',
            (v) => widget.controller.setValue(_node, v),
            mono: true);
    }
  }

  Widget _typeButton(ArbTokens t) {
    return PopupMenuButton<JsonType>(
      tooltip: 'Change type',
      padding: EdgeInsets.zero,
      onSelected: (type) {
        widget.controller.changeType(_node, type);
        _valueCtrl.text = _node.value;
      },
      itemBuilder: (_) => [
        for (final type in JsonType.values)
          PopupMenuItem(value: type, child: Text(typeLabel(type))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: t.surfaceMuted,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(typeLabel(_node.type),
            style:
                t.mono(size: 10, weight: FontWeight.w700, color: t.textSecondary)),
      ),
    );
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
        border: _fieldBorder(t.border),
        enabledBorder: _fieldBorder(t.border),
        focusedBorder: _fieldBorder(t.accent),
      ),
    );
  }

  OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color),
      );

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
}

String typeLabel(JsonType type) {
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

/// Paints dashed vertical nesting-guide lines down the left indent of a row,
/// one per ancestor depth, colored by [ArbTokens.depthColor]. Consecutive rows
/// stack so the dashes read as continuous tree lines.
class JsonGuidesPainter extends CustomPainter {
  JsonGuidesPainter({required this.depth, required this.colorFor});

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
        final end = y + _dash;
        canvas.drawLine(
            Offset(x, y), Offset(x, end > size.height ? size.height : end), paint);
        y += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(JsonGuidesPainter old) => old.depth != depth;
}
