import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../endpoint_editor/widgets/arb_segmented.dart';
import '../endpoint_editor/widgets/json_code_editor.dart';
import '../endpoint_editor/widgets/json_form_editor.dart';
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
  });

  final JsonDoc doc;
  final VoidCallback onChanged;
  final VoidCallback onSave;

  @override
  State<JsonDocumentView> createState() => _JsonDocumentViewState();
}

class _JsonDocumentViewState extends State<JsonDocumentView> {
  late _BodyTab _tab;
  int _formEpoch = 0;

  @override
  void initState() {
    super.initState();
    _tab = _isJson(widget.doc.controller.text) ? _BodyTab.form : _BodyTab.code;
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
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
            child: Text(
              doc.path,
              overflow: TextOverflow.ellipsis,
              style: t.mono(size: 12, color: t.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 168,
            child: ArbSegmented(
              compact: true,
              segments: const [ArbSegment('▦ Form'), ArbSegment('</> Code')],
              selectedIndex: _tab.index,
              onChanged: (i) => setState(() {
                final next = _BodyTab.values[i];
                if (next == _BodyTab.form) _formEpoch++;
                _tab = next;
              }),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: (doc.dirty && !doc.saving) ? widget.onSave : null,
            style: FilledButton.styleFrom(
              backgroundColor: t.accent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.radiusSm),
              ),
            ),
            child: doc.saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(doc.dirty ? 'Save' : 'Saved',
                    style: t.sans(
                        size: 13, weight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _body(ArbTokens t) {
    final doc = widget.doc;
    if (_tab == _BodyTab.code) {
      return JsonCodeEditor(
        controller: doc.controller,
        minLines: 18,
        onChanged: (_) => widget.onChanged(),
      );
    }
    if (_isJson(doc.controller.text)) {
      return JsonFormEditor(
        key: ValueKey(_formEpoch),
        initialJson: doc.controller.text,
        onChanged: (json) {
          doc.controller.text = json;
          widget.onChanged();
        },
      );
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
