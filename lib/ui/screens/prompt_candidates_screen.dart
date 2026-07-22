import 'package:flutter/material.dart';
import '../../domain/entities/endpoint.dart';
import 'endpoint_editor/widgets/json_brace_controller.dart';

/// Manages the named response options offered by the "Prompt" conditional
/// mode. Mirrors [ConditionalMockScreen]'s list-management pattern — a full
/// screen with add/edit/remove, returned to the caller on the check action.
class PromptCandidatesScreen extends StatefulWidget {
  final List<PromptCandidateResponse> candidates;

  const PromptCandidatesScreen({super.key, required this.candidates});

  @override
  State<PromptCandidatesScreen> createState() => _PromptCandidatesScreenState();
}

class _PromptCandidatesScreenState extends State<PromptCandidatesScreen> {
  late List<PromptCandidateResponse> _candidates;

  @override
  void initState() {
    super.initState();
    _candidates = List.from(widget.candidates);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prompt responses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context, _candidates),
          ),
        ],
      ),
      body: _candidates.isEmpty ? _buildEmptyState() : _buildList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCandidate,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined, size: 100, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No prompt responses yet',
              style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('Tap + to add one the developer can pick at request time',
              style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _candidates.length,
      itemBuilder: (context, index) {
        final candidate = _candidates[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            title: Text(candidate.label, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Row(
              children: [
                _buildStatusChip(candidate.statusCode),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    candidate.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600], fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => setState(() => _candidates.removeAt(index)),
            ),
            onTap: () => _editCandidate(index),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(int statusCode) {
    final color = _statusColor(statusCode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$statusCode',
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _statusColor(int code) {
    if (code < 300) return Colors.green;
    if (code < 400) return Colors.orange;
    return Colors.red;
  }

  void _addCandidate() async {
    final result = await _showCandidateDialog(null);
    if (result != null) setState(() => _candidates.add(result));
  }

  void _editCandidate(int index) async {
    final result = await _showCandidateDialog(_candidates[index]);
    if (result != null) setState(() => _candidates[index] = result);
  }

  Future<PromptCandidateResponse?> _showCandidateDialog(
    PromptCandidateResponse? existing,
  ) async {
    final labelController = TextEditingController(text: existing?.label ?? '');
    final bodyController = JsonBraceController(text: existing?.body ?? '{}');
    int selectedStatusCode = existing?.statusCode ?? 200;

    return showDialog<PromptCandidateResponse>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add response' : 'Edit response'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelController,
                      decoration: const InputDecoration(
                        labelText: 'Label',
                        hintText: '200 · Full list',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: selectedStatusCode,
                      decoration: const InputDecoration(
                        labelText: 'HTTP Status Code',
                        border: OutlineInputBorder(),
                      ),
                      items: HttpStatusCode.commonCodes
                          .map((code) => DropdownMenuItem(
                                value: code,
                                child: Text(HttpStatusCode.getStatusText(code)),
                              ))
                          .toList(),
                      onChanged: (value) => setDialogState(() => selectedStatusCode = value!),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: bodyController,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'Response body (JSON)',
                        hintText: '{"message": "ok"}',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 8,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (labelController.text.isNotEmpty && bodyController.text.isNotEmpty) {
                      Navigator.pop(
                        dialogContext,
                        PromptCandidateResponse(
                          id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                          label: labelController.text,
                          statusCode: selectedStatusCode,
                          body: bodyController.text,
                        ),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
