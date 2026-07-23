import 'package:flutter/material.dart';

import '../../core/theme/arbiter_tokens.dart';
import '../../domain/entities/endpoint.dart';
import 'endpoint_editor/widgets/arb_section_label.dart';
import 'endpoint_editor/widgets/json_code_editor.dart';
import 'endpoint_editor/widgets/status_field.dart';

/// Manages the named response options offered by the "Prompt" conditional
/// mode — a list-plus-editor split mirroring [DesktopEndpointsPane] and
/// [DesktopEndpointEditor]: pick a response on the left (with its own
/// enable/disable switch) to edit it on the right, or add a new one the same
/// way you'd create a new endpoint.
class PromptCandidatesScreen extends StatefulWidget {
  final List<PromptCandidateResponse> candidates;

  const PromptCandidatesScreen({super.key, required this.candidates});

  @override
  State<PromptCandidatesScreen> createState() => _PromptCandidatesScreenState();
}

class _PromptCandidatesScreenState extends State<PromptCandidatesScreen> {
  late List<PromptCandidateResponse> _candidates;
  PromptCandidateResponse? _selected;
  bool _creatingNew = false;

  late final TextEditingController _labelController;
  late final TextEditingController _statusController;
  late final TextEditingController _bodyController;
  bool _draftEnabled = true;

  @override
  void initState() {
    super.initState();
    _candidates = List.from(widget.candidates);
    _labelController = TextEditingController();
    _statusController = TextEditingController(text: '200');
    _bodyController = TextEditingController(text: '{}');
  }

  @override
  void dispose() {
    _labelController.dispose();
    _statusController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _selectCandidate(PromptCandidateResponse c) {
    setState(() {
      _selected = c;
      _creatingNew = false;
      _labelController.text = c.label;
      _statusController.text = c.statusCode.toString();
      _bodyController.text = c.body;
      _draftEnabled = c.isEnabled;
    });
  }

  void _startNew() {
    setState(() {
      _selected = null;
      _creatingNew = true;
      _labelController.text = '';
      _statusController.text = '200';
      _bodyController.text = '{}';
      _draftEnabled = true;
    });
  }

  void _save() {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Give this response a label')));
      return;
    }
    final statusCode = int.tryParse(_statusController.text.trim()) ?? 200;
    final updated = PromptCandidateResponse(
      id: _selected?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      label: label,
      statusCode: statusCode,
      body: _bodyController.text,
      isEnabled: _draftEnabled,
    );
    setState(() {
      final existingIndex =
          _selected == null ? -1 : _candidates.indexWhere((c) => c.id == _selected!.id);
      if (existingIndex >= 0) {
        _candidates[existingIndex] = updated;
      } else {
        _candidates.add(updated);
      }
      _selected = updated;
      _creatingNew = false;
    });
  }

  void _delete(PromptCandidateResponse c) {
    setState(() {
      _candidates.removeWhere((x) => x.id == c.id);
      _selected = null;
    });
  }

  void _toggleEnabled(PromptCandidateResponse c, bool value) {
    setState(() {
      final i = _candidates.indexWhere((x) => x.id == c.id);
      final updated = c.copyWith(isEnabled: value);
      _candidates[i] = updated;
      if (_selected?.id == c.id) {
        _selected = updated;
        _draftEnabled = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Scaffold(
      backgroundColor: t.canvas,
      appBar: AppBar(
        backgroundColor: t.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: t.textPrimary),
        title: Text('Prompt responses',
            style: t.sans(size: 16, weight: FontWeight.w700, color: t.textPrimary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _candidates),
            child: Text('Done', style: t.sans(size: 13, weight: FontWeight.w700, color: t.accent)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 280, child: _buildList(t)),
          VerticalDivider(width: 1, color: t.border),
          Expanded(
            child: (_selected != null || _creatingNew) ? _buildEditor(t) : _buildEmptyState(t),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ArbTokens t) {
    return Container(
      color: t.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                      '${_candidates.length} response${_candidates.length == 1 ? '' : 's'}',
                      style: t.sans(size: 13, weight: FontWeight.w600, color: t.textSecondary)),
                ),
                IconButton(
                  tooltip: 'Add response',
                  icon: Icon(Icons.add, size: 20, color: t.accent),
                  onPressed: _startNew,
                ),
              ],
            ),
          ),
          Expanded(
            child: _candidates.isEmpty
                ? Center(child: Text('No responses yet', style: t.sans(color: t.textMuted)))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _candidates.length,
                    itemBuilder: (context, i) => _buildRow(t, _candidates[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(ArbTokens t, PromptCandidateResponse c) {
    final selected = !_creatingNew && _selected?.id == c.id;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: selected ? t.accentSoft : t.surface,
        borderRadius: BorderRadius.circular(t.radiusSm),
        border: Border.all(color: selected ? t.accent : t.border),
      ),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
        title: Row(
          children: [
            _statusChip(t, c.statusCode),
            const SizedBox(width: 8),
            Expanded(
              child: Text(c.label,
                  overflow: TextOverflow.ellipsis,
                  style: t.sans(
                      size: 12.5,
                      weight: FontWeight.w700,
                      color: c.isEnabled ? t.textPrimary : t.textMuted)),
            ),
          ],
        ),
        trailing: Switch(
          value: c.isEnabled,
          activeThumbColor: t.accent,
          onChanged: (v) => _toggleEnabled(c, v),
        ),
        onTap: () => _selectCandidate(c),
      ),
    );
  }

  Widget _statusChip(ArbTokens t, int code) {
    final color = t.statusColor(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration:
          BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6)),
      child: Text('$code', style: t.mono(size: 10, weight: FontWeight.w700, color: color)),
    );
  }

  Widget _buildEmptyState(ArbTokens t) {
    return Container(
      color: t.canvas,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: t.textMuted),
            const SizedBox(height: 10),
            Text('Select a response to edit, or add a new one',
                style: t.sans(size: 13, color: t.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(ArbTokens t) {
    return Container(
      color: t.canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_creatingNew ? 'New response' : 'Edit response',
                      style: t.sans(size: 16, weight: FontWeight.w700)),
                ),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(backgroundColor: t.accent),
                  child: Text(_creatingNew ? 'Add response' : 'Save changes'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ArbSectionLabel('Label', padding: EdgeInsets.zero),
                      TextField(
                        controller: _labelController,
                        style: t.sans(size: 14),
                        decoration: const InputDecoration(
                            hintText: '200 · Full list', border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ArbSectionLabel('Status', padding: EdgeInsets.zero),
                      StatusField(controller: _statusController),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Switch(
                  value: _draftEnabled,
                  activeThumbColor: t.accent,
                  onChanged: (v) => setState(() => _draftEnabled = v),
                ),
                const SizedBox(width: 8),
                Text('Enabled', style: t.sans(size: 13, weight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            const ArbSectionLabel('Response body', padding: EdgeInsets.zero),
            const SizedBox(height: 8),
            JsonCodeEditor(controller: _bodyController, minLines: 10),
            if (!_creatingNew) ...[
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _delete(_selected!),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626)),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete this response'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
