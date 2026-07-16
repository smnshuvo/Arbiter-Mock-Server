import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../endpoint_editor/widgets/arb_segmented.dart';
import '../endpoint_editor/widgets/json_code_editor.dart';
import '../endpoint_editor/widgets/json_form_editor.dart';
import '../endpoint_editor/widgets/json_tree_controller.dart';
import 'json_docs_controller.dart';

enum _BodyTab { form, code }

/// Editor for a single open .json document: Form/Code toggle over the shared
/// JSON editors, plus a Save-in-place action. Kept alive per tab so its state
/// (active sub-tab, tree edits) survives tab switches.
class JsonDocumentView extends StatefulWidget {
  const JsonDocumentView({
    super.key,
    required this.doc,
    required this.onChanged,
    required this.onSave,
    required this.onSaveAs,
  });

  final JsonDoc doc;
  final VoidCallback onChanged;
  final VoidCallback onSave;
  final VoidCallback onSaveAs;

  @override
  State<JsonDocumentView> createState() => _JsonDocumentViewState();
}

class _JsonDocumentViewState extends State<JsonDocumentView> {
  late _BodyTab _tab;
  final JsonTreeController _tree = JsonTreeController();
  bool _treeReady = false;

  /// Text the tree was last serialized to when leaving the Form tab. If the Code
  /// tab didn't change it, we keep the existing tree (and its expand/collapse +
  /// scroll) instead of re-parsing.
  String? _codeSnapshot;

  @override
  void initState() {
    super.initState();
    _tab = _isJson(widget.doc.controller.text) ? _BodyTab.form : _BodyTab.code;
    // Fires once per clean→dirty transition, so the Save button and tab dot
    // update without rebuilding anything on every keystroke.
    _tree.onDirty = () {
      widget.doc.treeDirty = true;
      widget.onChanged();
    };
    if (_tab == _BodyTab.form) _loadTree();
  }

  @override
  void dispose() {
    _tree.dispose();
    super.dispose();
  }

  bool _isJson(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return true;
    try {
      jsonDecode(t);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadTree() async {
    setState(() => _treeReady = false);
    await _tree.parse(widget.doc.controller.text);
    if (mounted) setState(() => _treeReady = true);
  }

  /// Serializes the tree back into the document text. Called only when the text
  /// is actually needed — on save and when leaving the Form tab.
  Future<void> _syncTreeToText() async {
    if (_tab != _BodyTab.form || !_tree.isDirty) return;
    widget.doc.controller.text = await _tree.toJson();
    _tree.markSaved();
    widget.doc.treeDirty = false; // the text now carries the edit
  }

  Future<void> _handleSave() async {
    await _syncTreeToText();
    widget.onSave();
  }

  Future<void> _handleSaveAs() async {
    await _syncTreeToText();
    widget.onSaveAs();
  }

  Future<void> _switchTab(_BodyTab next) async {
    if (next == _tab) return;
    if (next == _BodyTab.code) {
      await _syncTreeToText();
      _codeSnapshot = widget.doc.controller.text;
      if (!mounted) return;
      setState(() => _tab = next);
    } else {
      setState(() => _tab = next);
      // Only re-parse if the Code tab actually changed the text; otherwise keep
      // the tree so expand/collapse and scroll position survive the round-trip.
      if (widget.doc.controller.text != _codeSnapshot) {
        await _loadTree();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Container(
      color: t.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(t),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
              child: _body(t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(ArbTokens t) {
    final doc = widget.doc;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 16, color: t.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: doc.path,
              child: Text(
                doc.title,
                overflow: TextOverflow.ellipsis,
                style: t.mono(size: 12, color: t.textSecondary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 168,
            child: ArbSegmented(
              compact: true,
              segments: const [ArbSegment('▦ Form'), ArbSegment('</> Code')],
              selectedIndex: _tab.index,
              onChanged: (i) => _switchTab(_BodyTab.values[i]),
            ),
          ),
          const SizedBox(width: 12),
          _saveControl(t),
        ],
      ),
    );
  }

  Widget _saveControl(ArbTokens t) {
    final doc = widget.doc;
    final enabled = doc.dirty && !doc.saving;

    Widget label() => doc.saving
        ? const SizedBox(
            width: 14,
            height: 14,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Text(doc.dirty ? 'Save' : 'Saved',
            style: t.sans(size: 13, weight: FontWeight.w700, color: Colors.white));

    // macOS: plain Save (in-place always works under the security scope).
    if (!Platform.isAndroid) {
      return FilledButton(
        onPressed: enabled ? _handleSave : null,
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          disabledBackgroundColor: t.accent.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radiusSm),
          ),
        ),
        child: label(),
      );
    }

    // Android: split button — Save (long-press = Save as…) + a caret menu.
    final r = Radius.circular(t.radiusSm);
    final bg = enabled || doc.saving ? t.accent : t.accent.withValues(alpha: 0.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          borderRadius: BorderRadius.horizontal(left: r),
          child: InkWell(
            borderRadius: BorderRadius.horizontal(left: r),
            onTap: enabled ? _handleSave : null,
            onLongPress: doc.saving ? null : _handleSaveAs,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: label(),
            ),
          ),
        ),
        Container(width: 1, height: 22, color: Colors.white24),
        Material(
          color: bg,
          borderRadius: BorderRadius.horizontal(right: r),
          child: PopupMenuButton<String>(
            tooltip: 'Save options',
            enabled: !doc.saving,
            position: PopupMenuPosition.under,
            onSelected: (v) {
              if (v == 'saveAs') _handleSaveAs();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'saveAs',
                child: Row(
                  children: [
                    Icon(Icons.save_as_outlined, size: 18, color: t.textSecondary),
                    const SizedBox(width: 10),
                    const Text('Save as…'),
                  ],
                ),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 11),
              child: Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(ArbTokens t) {
    final doc = widget.doc;
    if (_tab == _BodyTab.code) {
      // One TextField — cheap to scroll conventionally.
      return SingleChildScrollView(
        child: JsonCodeEditor(
          controller: doc.controller,
          minLines: 18,
          onChanged: (_) => widget.onChanged(),
        ),
      );
    }
    if (_isJson(doc.controller.text)) {
      if (!_treeReady) {
        return const Center(child: CircularProgressIndicator());
      }
      // Fills the Expanded and lazily builds only the visible rows.
      return JsonFormEditor(controller: _tree);
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x14DC2626),
        border: Border.all(color: const Color(0x33DC2626)),
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This file isn\'t valid JSON yet, so the visual editor can\'t show it.',
            style: t.sans(size: 12.5, color: const Color(0xFFB4432B)),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() => _tab = _BodyTab.code),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: t.surface,
            ),
            child: Text('Edit in Code',
                style:
                    t.sans(size: 12, weight: FontWeight.w700, color: t.accent)),
          ),
        ],
      ),
    );
  }
}
