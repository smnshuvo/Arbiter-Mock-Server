import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/theme/arbiter_tokens.dart';
import 'arb_segmented.dart';
import 'json_code_editor.dart';
import 'json_form_editor.dart';
import 'json_tree_controller.dart';

enum _ViewTab { code, form }

/// Read-only Code/Form viewer for a request or response body — reuses the
/// same [JsonCodeEditor]/[JsonFormEditor] widgets the endpoint editor uses for
/// mock responses (in `readOnly` mode) so log detail bodies look consistent
/// with response editing, just non-editable, with expand-all/collapse-all
/// for the Form view.
class JsonBodyViewer extends StatefulWidget {
  const JsonBodyViewer({
    super.key,
    required this.label,
    required this.jsonString,
    this.onOpenInEditor,
  });

  final String label;
  final String jsonString;

  /// When set, shows an "Open in editor" button that hands [jsonString] off
  /// to a fuller, editable view (e.g. the JSON Docs tabbed editor).
  final VoidCallback? onOpenInEditor;

  @override
  State<JsonBodyViewer> createState() => _JsonBodyViewerState();
}

class _JsonBodyViewerState extends State<JsonBodyViewer> {
  late final TextEditingController _codeController;
  late final JsonTreeController _treeController;
  _ViewTab _tab = _ViewTab.code;
  bool _isJson = false;

  /// Code view shows the body pretty-printed rather than as received
  /// (proxied responses are often minified onto a single line).
  bool _formatted = false;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.jsonString);
    _treeController = JsonTreeController();
    _load(widget.jsonString);
  }

  @override
  void didUpdateWidget(JsonBodyViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jsonString != widget.jsonString) {
      _load(widget.jsonString);
      _syncCodeText();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _treeController.dispose();
    super.dispose();
  }

  void _load(String raw) {
    _isJson = _looksLikeJson(raw);
    if (_isJson) _treeController.parse(raw);
  }

  void _syncCodeText() {
    _codeController.text = _formatted && _isJson ? _pretty(widget.jsonString) : widget.jsonString;
  }

  String _pretty(String raw) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw.trim()));
    } catch (_) {
      return raw;
    }
  }

  void _toggleFormatted() {
    setState(() => _formatted = !_formatted);
    _syncCodeText();
  }

  bool _looksLikeJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return false;
    try {
      jsonDecode(trimmed);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(widget.label, style: t.label),
            const Spacer(),
            if (widget.onOpenInEditor != null) ...[
              IconButton(
                tooltip: 'Open in editor',
                icon: Icon(Icons.open_in_new, size: 16, color: t.textSecondary),
                visualDensity: VisualDensity.compact,
                onPressed: widget.onOpenInEditor,
              ),
              const SizedBox(width: 4),
            ],
            if (_isJson && _tab == _ViewTab.code) ...[
              TextButton.icon(
                onPressed: _toggleFormatted,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(_formatted ? Icons.notes : Icons.format_align_left,
                    size: 15, color: _formatted ? t.accent : t.textSecondary),
                label: Text(_formatted ? 'Raw' : 'Format',
                    style: t.sans(
                        size: 11.5,
                        weight: FontWeight.w700,
                        color: _formatted ? t.accent : t.textSecondary)),
              ),
              const SizedBox(width: 6),
            ],
            if (_isJson)
              SizedBox(
                width: 148,
                child: ArbSegmented(
                  compact: true,
                  segments: const [ArbSegment('</> Code'), ArbSegment('▦ Form')],
                  selectedIndex: _tab.index,
                  onChanged: (i) => setState(() => _tab = _ViewTab.values[i]),
                ),
              ),
          ],
        ),
        if (_isJson && _tab == _ViewTab.form)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _headerButton(t, 'Expand all', _treeController.expandAll),
                _headerButton(t, 'Collapse all', _treeController.collapseAll),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (!_isJson || _tab == _ViewTab.code)
          JsonCodeEditor(controller: _codeController, readOnly: true)
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: JsonFormEditor(controller: _treeController, readOnly: true),
          ),
      ],
    );
  }

  Widget _headerButton(ArbTokens t, String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label,
          style: t.sans(size: 11, weight: FontWeight.w700, color: t.textSecondary)),
    );
  }
}
