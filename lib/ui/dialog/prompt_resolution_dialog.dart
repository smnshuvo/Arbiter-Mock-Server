import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/arbiter_tokens.dart';
import '../../domain/entities/endpoint.dart';
import '../../domain/entities/prompt.dart';
import '../bloc/prompt/prompt_bloc.dart';
import '../bloc/prompt/prompt_event.dart';
import '../bloc/prompt/prompt_state.dart';
import '../screens/endpoint_editor/widgets/json_brace_controller.dart';

/// Live "choose a response" dialog for the Prompt conditional mode — shows
/// one [PendingPrompt] at a time (anything else queues behind it, per
/// [PromptInterceptionManager]) with a countdown that mirrors the server's
/// own per-prompt timeout.
class PromptResolutionDialog extends StatefulWidget {
  final PendingPrompt prompt;

  const PromptResolutionDialog({super.key, required this.prompt});

  @override
  State<PromptResolutionDialog> createState() => _PromptResolutionDialogState();
}

class _PromptResolutionDialogState extends State<PromptResolutionDialog> {
  late int _remainingSeconds;
  Timer? _timer;
  String? _editingCandidateId;
  final Map<String, JsonBraceController> _editControllers = {};
  final Map<String, TextEditingController> _statusControllers = {};
  bool _dismissed = false;

  /// Title-only quick pick — skips the body preview/Edit affordance so a
  /// candidate can be chosen with a single tap.
  bool _compact = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.prompt.timeoutSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _remainingSeconds = _remainingSeconds > 0 ? _remainingSeconds - 1 : 0);
      // The server resolves its own timeout independently and the dialog
      // dismisses via the BlocListener below when that happens — this timer
      // is purely the visible countdown, not a second source of truth.
      if (_remainingSeconds <= 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _editControllers.values) {
      c.dispose();
    }
    for (final c in _statusControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _use(PromptCandidateResponse candidate) {
    context.read<PromptBloc>().add(UsePromptCandidateEvent(widget.prompt.id, candidate));
    _dismiss();
  }

  void _startEdit(PromptCandidateResponse candidate) {
    setState(() {
      _editingCandidateId = candidate.id;
      _editControllers[candidate.id] ??= JsonBraceController(text: candidate.body);
      _statusControllers[candidate.id] ??=
          TextEditingController(text: candidate.statusCode.toString());
    });
  }

  void _cancelEdit() => setState(() => _editingCandidateId = null);

  void _serveEdited(PromptCandidateResponse candidate) {
    final body = _editControllers[candidate.id]?.text ?? candidate.body;
    final statusCode =
        int.tryParse(_statusControllers[candidate.id]?.text ?? '') ?? candidate.statusCode;
    context.read<PromptBloc>().add(
          ServeEditedPromptEvent(widget.prompt.id, statusCode: statusCode, body: body),
        );
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return BlocListener<PromptBloc, PromptState>(
      listener: (context, state) {
        final stillActive = state is PromptActive && state.prompt.id == widget.prompt.id;
        if (!stillActive) _dismiss();
      },
      child: Dialog(
        backgroundColor: t.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(t),
              Divider(height: 1, color: t.border),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _compact ? _buildCompactList(t) : _buildCandidateGrid(t),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ArbTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Incoming request — choose a response',
                    style: t.sans(size: 15, weight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('${widget.prompt.method} ${widget.prompt.path}',
                    style: t.mono(size: 12, color: t.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: _compact ? 'Show details' : 'Titles only — quick pick',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _compact = !_compact),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: _compact ? t.accentSoft : t.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _compact ? t.accent : t.border),
                ),
                child: Icon(
                  _compact ? Icons.view_agenda_outlined : Icons.view_headline,
                  size: 17,
                  color: _compact ? t.accent : t.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _remainingSeconds / widget.prompt.timeoutSeconds,
                  strokeWidth: 3,
                  color: t.accent,
                  backgroundColor: t.accentSoft,
                ),
                Text('$_remainingSeconds',
                    style: t.mono(size: 11, weight: FontWeight.w700, color: t.accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Title-only rows — one tap serves that candidate immediately, no body
  /// preview or Edit affordance to read through first.
  Widget _buildCompactList(ArbTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in widget.prompt.candidates) ...[
          _buildCompactRow(t, c),
          if (c != widget.prompt.candidates.last) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildCompactRow(ArbTokens t, PromptCandidateResponse candidate) {
    return Material(
      color: t.canvas,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _use(candidate),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _statusBadge(t, candidate.statusCode),
              const SizedBox(width: 10),
              Expanded(
                child: Text(candidate.label,
                    style: t.sans(size: 13, weight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
              Icon(Icons.chevron_right, size: 18, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCandidateGrid(ArbTokens t) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: widget.prompt.candidates.map((c) => _buildCandidateCard(t, c)).toList(),
    );
  }

  Widget _buildCandidateCard(ArbTokens t, PromptCandidateResponse candidate) {
    final editing = _editingCandidateId == candidate.id;
    return Container(
      width: 300,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.canvas,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _statusBadge(t, candidate.statusCode),
              const SizedBox(width: 9),
              Expanded(
                child: Text(candidate.label,
                    style: t.sans(size: 12, weight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (editing) ...[
            TextField(
              controller: _statusControllers[candidate.id],
              keyboardType: TextInputType.number,
              style: t.mono(size: 13),
              decoration: const InputDecoration(
                  labelText: 'Status', isDense: true, border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _editControllers[candidate.id],
              maxLines: 6,
              style: t.mono(size: 11.5),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: _cancelEdit, child: const Text('Cancel')),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _serveEdited(candidate),
                    style: FilledButton.styleFrom(backgroundColor: t.green),
                    child: const Text('Serve edited'),
                  ),
                ),
              ],
            ),
          ] else ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 130),
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: t.codeBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: SingleChildScrollView(
                child: Text(candidate.body, style: t.mono(size: 11, color: t.codeText)),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _startEdit(candidate),
                    child: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _use(candidate),
                    style: FilledButton.styleFrom(backgroundColor: t.accent),
                    child: const Text('Use this'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(ArbTokens t, int code) {
    final color = t.statusColor(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$code', style: t.mono(size: 11, weight: FontWeight.w700, color: color)),
    );
  }
}
