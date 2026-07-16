import 'package:flutter/material.dart';

import '../../../core/services/json_document_service.dart';
import '../../../core/theme/arbiter_tokens.dart';
import 'json_docs_controller.dart';
import 'recent_files_store.dart';

/// The recent-files list (name, size, last modified) shown when no document is
/// open. Opening one just loads it into the controller — the parent editor
/// screen then switches to editor mode on its own.
class RecentFilesView extends StatefulWidget {
  const RecentFilesView({super.key});

  @override
  State<RecentFilesView> createState() => _RecentFilesViewState();
}

class _RecentFilesViewState extends State<RecentFilesView> {
  final JsonDocsController _c = JsonDocsController.instance;
  late Future<List<RecentFile>> _future;

  @override
  void initState() {
    super.initState();
    _future = RecentFilesStore.instance.list();
  }

  void _refresh() =>
      setState(() => _future = RecentFilesStore.instance.list());

  Future<void> _open(String path) async {
    final ok = await _c.openPath(path);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Couldn\'t open — access may have expired. '
            'Use “Open a file” to pick it again.'),
      ));
      await RecentFilesStore.instance.remove(path);
      _refresh();
    }
    // On success the controller notifies and the editor screen shows the doc.
  }

  Future<void> _browse() async {
    final path = await JsonDocumentService.instance.pickJson();
    if (path == null) return;
    await _open(path);
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: OutlinedButton.icon(
            onPressed: _browse,
            style: OutlinedButton.styleFrom(
              foregroundColor: t.accent,
              side: BorderSide(color: t.accent.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.radiusSm),
              ),
            ),
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Open a JSON file'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
          child: Text('RECENT',
              style: t.label.copyWith(color: t.textMuted)),
        ),
        Expanded(
          child: FutureBuilder<List<RecentFile>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data ?? const [];
              if (items.isEmpty) return _empty(t);
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: t.border, indent: 16, endIndent: 16),
                itemBuilder: (context, i) => _tile(t, items[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tile(ArbTokens t, RecentFile f) {
    return ListTile(
      leading: Icon(Icons.description_outlined, color: t.accent),
      title: Text(f.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.sans(size: 14, weight: FontWeight.w600)),
      subtitle: Text(_subtitle(f),
          style: t.sans(size: 12, color: t.textSecondary)),
      trailing: IconButton(
        icon: Icon(Icons.close, size: 18, color: t.textMuted),
        tooltip: 'Remove from recents',
        onPressed: () async {
          await RecentFilesStore.instance.remove(f.path);
          _refresh();
        },
      ),
      onTap: () => _open(f.path),
    );
  }

  Widget _empty(ArbTokens t) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 56, color: t.textMuted),
          const SizedBox(height: 12),
          Text('No recent files',
              style: t.sans(size: 15, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Open a .json file to get started',
              style: t.sans(size: 12.5, color: t.textSecondary)),
        ],
      ),
    );
  }

  String _subtitle(RecentFile f) {
    final parts = <String>[];
    if (f.size != null) parts.add(_humanSize(f.size!));
    final mod = f.modified ?? (f.openedAt == 0 ? null : f.openedAt);
    if (mod != null) parts.add(_formatDate(mod));
    return parts.join(' · ');
  }

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB'];
    double v = bytes / 1024;
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return '${v.toStringAsFixed(v >= 10 ? 0 : 1)} ${units[u]}';
  }

  String _formatDate(int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
