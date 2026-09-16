import 'package:flutter/material.dart';

import '../../core/theme/arbiter_tokens.dart';
import '../../domain/entities/saved_base_url.dart';
import '../../domain/repositories/saved_base_url_repository.dart';
import '../bloc/dependency_container.dart';

/// Records [url] as recently used. When it isn't in the saved library yet,
/// asks the user to name it first (they can skip). Call from every path that
/// commits a pass-through URL — save, start, submit — before persisting.
Future<void> rememberPassThroughUrl(BuildContext context, String url) async {
  final normalized = SavedBaseUrl.normalize(url);
  if (normalized.isEmpty) return;
  final repo = sl<SavedBaseUrlRepository>();
  if (repo.find(normalized) != null) {
    await repo.markUsed(normalized);
    return;
  }
  final result = await showDialog<({String name, String url})>(
    context: context,
    builder: (_) => BaseUrlFormDialog(
      title: 'Name this base URL',
      initialUrl: normalized,
      urlEditable: false,
      cancelLabel: 'Skip',
    ),
  );
  if (result != null) await repo.save(result.url, result.name);
}

/// Base URL text field backed by the saved-URL library: a picker button to
/// choose/rename/delete/add saved URLs, and a hint naming the current one.
class PassThroughUrlField extends StatefulWidget {
  final TextEditingController controller;

  /// Fired on Enter and after picking a saved URL.
  final VoidCallback? onCommitted;
  final bool dense;

  const PassThroughUrlField({
    super.key,
    required this.controller,
    this.onCommitted,
    this.dense = false,
  });

  @override
  State<PassThroughUrlField> createState() => _PassThroughUrlFieldState();
}

class _PassThroughUrlFieldState extends State<PassThroughUrlField> {
  final SavedBaseUrlRepository _repo = sl<SavedBaseUrlRepository>();

  Future<void> _openLibrary() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => SavedBaseUrlsDialog(currentUrl: widget.controller.text),
    );
    if (picked == null || !mounted) return;
    widget.controller.text = picked;
    await _repo.markUsed(picked);
    widget.onCommitted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final saved = _repo.find(value.text);
        return TextField(
          controller: widget.controller,
          style: t.mono(size: widget.dense ? 12.5 : 13),
          onSubmitted: widget.onCommitted == null ? null : (_) => widget.onCommitted!(),
          decoration: InputDecoration(
            labelText: 'Base URL',
            hintText: 'https://api.example.com',
            isDense: widget.dense,
            border: const OutlineInputBorder(),
            helperText: saved != null ? 'Saved as “${saved.name}”' : null,
            suffixIcon: IconButton(
              tooltip: 'Saved URLs',
              icon: Icon(Icons.bookmarks_outlined, size: 19, color: t.textSecondary),
              onPressed: _openLibrary,
            ),
          ),
        );
      },
    );
  }
}

/// The saved-URL library. Pops with the chosen URL, or null.
class SavedBaseUrlsDialog extends StatefulWidget {
  final String currentUrl;

  const SavedBaseUrlsDialog({super.key, required this.currentUrl});

  @override
  State<SavedBaseUrlsDialog> createState() => _SavedBaseUrlsDialogState();
}

class _SavedBaseUrlsDialogState extends State<SavedBaseUrlsDialog> {
  final SavedBaseUrlRepository _repo = sl<SavedBaseUrlRepository>();

  Future<void> _edit({SavedBaseUrl? entry}) async {
    final result = await showDialog<({String name, String url})>(
      context: context,
      builder: (_) => BaseUrlFormDialog(
        title: entry == null ? 'New base URL' : 'Rename base URL',
        initialUrl: entry?.url ?? '',
        initialName: entry?.name,
        urlEditable: entry == null,
      ),
    );
    if (result == null) return;
    await _repo.save(result.url, result.name);
    if (mounted) setState(() {});
  }

  Future<void> _delete(SavedBaseUrl entry) async {
    await _repo.delete(entry.url);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final entries = _repo.getAll();
    final current = SavedBaseUrl.normalize(widget.currentUrl);
    return AlertDialog(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      title: Text('Saved base URLs', style: t.sans(size: 16, weight: FontWeight.w700)),
      content: SizedBox(
        width: 440,
        child: entries.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No saved URLs yet. Add one, or save a server with a base URL and '
                  "you'll be asked to name it.",
                  style: t.sans(size: 12.5, color: t.textMuted),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in entries)
                    ListTile(
                      dense: true,
                      selected: entry.url == current,
                      selectedTileColor: t.accentSoft,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(t.radiusSm)),
                      title: Text(entry.name, style: t.sans(size: 13, weight: FontWeight.w700)),
                      subtitle: Text(entry.url,
                          overflow: TextOverflow.ellipsis,
                          style: t.mono(size: 11.5, color: t.textSecondary)),
                      onTap: () => Navigator.pop(context, entry.url),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Rename',
                            icon: Icon(Icons.edit_outlined, size: 18, color: t.textSecondary),
                            onPressed: () => _edit(entry: entry),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: Icon(Icons.delete_outline, size: 18, color: t.textMuted),
                            onPressed: () => _delete(entry),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: t.accent),
          onPressed: () => _edit(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New URL'),
        ),
      ],
    );
  }
}

/// Name (+ optionally URL) form. Pops with the trimmed values, or null.
class BaseUrlFormDialog extends StatefulWidget {
  final String title;
  final String initialUrl;
  final String? initialName;
  final bool urlEditable;
  final String cancelLabel;

  const BaseUrlFormDialog({
    super.key,
    required this.title,
    required this.initialUrl,
    this.initialName,
    this.urlEditable = true,
    this.cancelLabel = 'Cancel',
  });

  @override
  State<BaseUrlFormDialog> createState() => _BaseUrlFormDialogState();
}

class _BaseUrlFormDialogState extends State<BaseUrlFormDialog> {
  late final TextEditingController _url = TextEditingController(text: widget.initialUrl);
  late final TextEditingController _name = TextEditingController(
      text: widget.initialName ??
          (widget.initialUrl.isEmpty ? '' : SavedBaseUrl.suggestName(widget.initialUrl)));

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      SavedBaseUrl.normalize(_url.text).startsWith(RegExp(r'https?://'));

  void _submit() {
    if (!_valid) return;
    Navigator.pop(context, (name: _name.text.trim(), url: SavedBaseUrl.normalize(_url.text)));
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: ListenableBuilder(
          listenable: Listenable.merge([_url, _name]),
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Staging',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                enabled: widget.urlEditable,
                style: t.mono(size: 13),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://api.example.com',
                  border: const OutlineInputBorder(),
                  errorText: _url.text.trim().isEmpty ||
                          SavedBaseUrl.normalize(_url.text).startsWith(RegExp(r'https?://'))
                      ? null
                      : 'Must start with http:// or https://',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancelLabel)),
        ListenableBuilder(
          listenable: Listenable.merge([_url, _name]),
          builder: (context, _) =>
              FilledButton(onPressed: _valid ? _submit : null, child: const Text('Save')),
        ),
      ],
    );
  }
}
