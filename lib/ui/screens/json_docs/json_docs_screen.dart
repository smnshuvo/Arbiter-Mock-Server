import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';
import 'json_docs_controller.dart';
import 'json_document_view.dart';

/// A single-window, browser-tabbed JSON document editor. Each open .json is a
/// tab; the active tab hosts the Form/Code editor with save-in-place.
class JsonDocsScreen extends StatefulWidget {
  const JsonDocsScreen({super.key});

  @override
  State<JsonDocsScreen> createState() => _JsonDocsScreenState();
}

class _JsonDocsScreenState extends State<JsonDocsScreen> {
  final JsonDocsController _c = JsonDocsController.instance;

  Future<void> _save(JsonDoc doc) async {
    final ok = await _c.save(doc);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save ${doc.fileName}')),
      );
    }
  }

  void _close(int index) {
    _c.close(index);
    if (_c.isEmpty && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: t.canvas,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tabStrip(t),
                Divider(height: 1, color: t.border),
                Expanded(
                  child: _c.isEmpty
                      ? _empty(t)
                      : IndexedStack(
                          index: _c.activeIndex,
                          children: [
                            for (final doc in _c.docs)
                              JsonDocumentView(
                                key: ValueKey(doc.path),
                                doc: doc,
                                onChanged: _c.touch,
                                onSave: () => _save(doc),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tabStrip(ArbTokens t) {
    return Container(
      height: 44,
      color: t.surfaceMuted,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              itemCount: _c.docs.length,
              itemBuilder: (context, i) => _tab(t, i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(ArbTokens t, int i) {
    final doc = _c.docs[i];
    final active = i == _c.activeIndex;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: active ? t.canvas : t.surface,
        borderRadius: BorderRadius.circular(t.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radiusSm),
          onTap: () => _c.select(i),
          child: Container(
            padding: const EdgeInsets.only(left: 12, right: 6),
            constraints: const BoxConstraints(maxWidth: 220),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radiusSm),
              border: Border.all(
                color: active ? t.accent.withValues(alpha: 0.5) : t.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (doc.dirty)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 7),
                    decoration:
                        BoxDecoration(color: t.accent, shape: BoxShape.circle),
                  ),
                Flexible(
                  child: Text(
                    doc.fileName,
                    overflow: TextOverflow.ellipsis,
                    style: t.sans(
                      size: 12.5,
                      weight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? t.textPrimary : t.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => _close(i),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(Icons.close, size: 13, color: t.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(ArbTokens t) {
    return Center(
      child: Text('No file open',
          style: t.sans(size: 14, color: t.textSecondary)),
    );
  }
}
