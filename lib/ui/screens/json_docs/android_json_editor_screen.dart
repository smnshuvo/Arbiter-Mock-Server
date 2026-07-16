import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';
import 'json_docs_controller.dart';
import 'json_document_view.dart';
import 'opening_indicator.dart';
import 'recent_files_view.dart';

/// Android JSON editor — a single RAM-light route (no multi-tab window). Shows a
/// slim branded header over either the open document (editor mode) or the
/// recent-files list when nothing is open. Closing a file returns to the list.
class AndroidJsonEditorScreen extends StatefulWidget {
  const AndroidJsonEditorScreen({super.key});

  @override
  State<AndroidJsonEditorScreen> createState() =>
      _AndroidJsonEditorScreenState();
}

class _AndroidJsonEditorScreenState extends State<AndroidJsonEditorScreen> {
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

  void _closeFile() {
    if (_c.active != null) _c.close(_c.activeIndex); // → recent-files mode
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final doc = _c.active;
        // Back closes the open file (to the recent list); with no file open,
        // back leaves the JSON editor entirely.
        return PopScope(
          canPop: doc == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && doc != null) _closeFile();
          },
          child: Scaffold(
            backgroundColor: t.canvas,
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(t, doc != null),
                  Divider(height: 1, color: t.border),
                  Expanded(child: _body(doc)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(JsonDoc? doc) {
    if (doc != null) {
      return JsonDocumentView(
        key: ValueKey(doc.path),
        doc: doc,
        onChanged: _c.touch,
        onSave: () => _save(doc),
        onSaveAs: () => _c.saveAsExplicit(doc),
      );
    }
    // No document open: recent-files list, with the loader as an overlay while
    // a file is being (re)opened so the list stays mounted underneath.
    final t = ArbTokens.of(context);
    return Stack(
      children: [
        const RecentFilesView(),
        if (_c.opening)
          Positioned.fill(
            child: Container(
              color: t.canvas.withValues(alpha: 0.85),
              child: const OpeningIndicator(),
            ),
          ),
      ],
    );
  }

  Widget _header(ArbTokens t, bool fileOpen) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset('assets/app_icon/app_icon.png',
                width: 24, height: 24, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Arbiter JSON Editor',
                style: t.sans(size: 15, weight: FontWeight.w700)),
          ),
          if (fileOpen)
            IconButton(
              tooltip: 'Close file',
              icon: Icon(Icons.close, size: 22, color: t.textSecondary),
              onPressed: _closeFile,
            ),
        ],
      ),
    );
  }
}
