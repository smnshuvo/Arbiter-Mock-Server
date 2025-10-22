import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/interception_request.dart';
import '../bloc/interception/interception_bloc.dart';
import '../bloc/interception/interception_event.dart';

class InterceptionDialog extends StatefulWidget {
  final InterceptionRequest interception;
  final int timeoutSeconds;

  const InterceptionDialog({
    Key? key,
    required this.interception,
    required this.timeoutSeconds,
  }) : super(key: key);

  @override
  State<InterceptionDialog> createState() => _InterceptionDialogState();
}

class _InterceptionDialogState extends State<InterceptionDialog> {
  late TextEditingController _urlController;
  late TextEditingController _bodyController;
  late TextEditingController _statusCodeController;
  late String _method;
  late Map<String, String> _headers;
  late int _remainingSeconds;
  Timer? _timer;
  bool _isModified = false;

  // Expansion states
  bool _headersExpanded = false;
  bool _bodyExpanded = true;

  // Body input mode
  bool _useKeyValueMode = false;
  List<MapEntry<String, dynamic>> _bodyKeyValuePairs = [];

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.interception.url);
    _method = widget.interception.method;
    _headers = Map<String, String>.from(widget.interception.headers);
    _remainingSeconds = widget.timeoutSeconds;

    if (widget.interception.isRequest) {
      _bodyController =
          TextEditingController(text: widget.interception.body ?? '');
      _statusCodeController = TextEditingController();
    } else {
      _bodyController =
          TextEditingController(text: widget.interception.responseBody ?? '');
      _statusCodeController = TextEditingController(
          text: widget.interception.statusCode?.toString() ?? '200');
    }

    _parseBodyToKeyValue();
    _startTimer();
  }

  void _parseBodyToKeyValue() {
    if (_bodyController.text.isNotEmpty) {
      try {
        final decoded = jsonDecode(_bodyController.text);
        if (decoded is Map) {
          _bodyKeyValuePairs =
              decoded.entries.toList() as List<MapEntry<String, dynamic>>;
        }
      } catch (e) {
        // Not valid JSON, keep empty
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _remainingSeconds--;
          if (_remainingSeconds <= 0) {
            timer.cancel();
            _continueWithoutModification();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _urlController.dispose();
    _bodyController.dispose();
    _statusCodeController.dispose();
    super.dispose();
  }

  void _continueWithoutModification() {
    context.read<InterceptionBloc>().add(
      ContinueWithoutModificationEvent(widget.interception.id),
    );
    Navigator.of(context).pop();
  }

  void _modifyAndContinue() {
    // Sync key-value mode to text
    if (_useKeyValueMode) {
      final map = Map.fromEntries(_bodyKeyValuePairs);
      _bodyController.text = jsonEncode(map);
    }

    final statusCode = widget.interception.isResponse
        ? int.tryParse(_statusCodeController.text)
        : null;

    context.read<InterceptionBloc>().add(
      ModifyAndContinueEvent(
        id: widget.interception.id,
        method: _method,
        url: _urlController.text,
        headers: _headers,
        body: _bodyController.text.isNotEmpty ? _bodyController.text : null,
        statusCode: statusCode,
      ),
    );
    Navigator.of(context).pop();
  }

  void _cancel() {
    context.read<InterceptionBloc>().add(
      CancelInterceptionEvent(widget.interception.id),
    );
    Navigator.of(context).pop();
  }

  String _formatJson(String? text) {
    if (text == null || text.isEmpty) return '';
    try {
      final decoded = jsonDecode(text);
      return JsonEncoder.withIndent('  ').convert(decoded);
    } catch (e) {
      return text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMethodAndUrl(),
                    const SizedBox(height: 16),
                    _buildHeadersSection(),
                    const SizedBox(height: 16),
                    _buildBodySection(),
                    if (widget.interception.isResponse) ...[
                      const SizedBox(height: 16),
                      _buildStatusCode(),
                    ],
                  ],
                ),
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.interception.isRequest ? Colors.blue : Colors.green,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            widget.interception.isRequest
                ? Icons.arrow_upward
                : Icons.arrow_downward,
            color: Colors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.interception.isRequest
                      ? 'Intercepted Request'
                      : 'Intercepted Response',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Auto-continue in $_remainingSeconds seconds',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              value: _remainingSeconds / widget.timeoutSeconds,
              backgroundColor: Colors.white30,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              strokeWidth: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodAndUrl() {
    return Row(
      children: [
        SizedBox(
          width: 115,
          child: DropdownButtonFormField<String>(
            value: _method,
            decoration: const InputDecoration(
              labelText: 'Method',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
            items: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD']
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: widget.interception.isRequest
                ? (value) {
              if (value != null) {
                setState(() {
                  _method = value;
                  _isModified = true;
                });
              }
            }
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'URL',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
            enabled: widget.interception.isRequest,
            onChanged: (_) => setState(() => _isModified = true),
          ),
        ),
      ],
    );
  }

  Widget _buildHeadersSection() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _headersExpanded = !_headersExpanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    _headersExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Headers',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_headers.length}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_headersExpanded) ...[
            const Divider(height: 1),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(12),
                itemCount: _headers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = _headers.entries.elementAt(index);
                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.value,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBodySection() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _bodyExpanded = !_bodyExpanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    _bodyExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Body',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  if (_bodyController.text.isNotEmpty && _bodyExpanded)
                    IconButton(
                      icon: const Icon(Icons.format_align_left, size: 18),
                      onPressed: () {
                        setState(() {
                          _bodyController.text = _formatJson(_bodyController.text);
                        });
                      },
                      tooltip: 'Format JSON',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
          ),
          if (_bodyExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Text', style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.text_fields, size: 16),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('Key-Value', style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.list, size: 16),
                            ),
                          ],
                          selected: {_useKeyValueMode},
                          onSelectionChanged: (Set<bool> selected) {
                            setState(() {
                              _useKeyValueMode = selected.first;
                              if (_useKeyValueMode) {
                                _parseBodyToKeyValue();
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_useKeyValueMode)
                    _buildKeyValueEditor()
                  else
                    _buildTextEditor(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextEditor() {
    return TextField(
      controller: _bodyController,
      maxLines: 8,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        hintText: 'Request/Response body',
        contentPadding: EdgeInsets.all(12),
      ),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      onChanged: (_) => setState(() => _isModified = true),
    );
  }

  Widget _buildKeyValueEditor() {
    return Column(
      children: [
        Container(
          constraints: const BoxConstraints(maxHeight: 250),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _bodyKeyValuePairs.length,
            itemBuilder: (context, index) {
              final entry = _bodyKeyValuePairs[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Key',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        ),
                        style: const TextStyle(fontSize: 12),
                        controller: TextEditingController(text: entry.key),
                        onChanged: (value) {
                          setState(() {
                            _bodyKeyValuePairs[index] = MapEntry(value, entry.value);
                            _isModified = true;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Value',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        ),
                        style: const TextStyle(fontSize: 12),
                        controller: TextEditingController(text: entry.value.toString()),
                        onChanged: (value) {
                          setState(() {
                            _bodyKeyValuePairs[index] = MapEntry(entry.key, value);
                            _isModified = true;
                          });
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20),
                      onPressed: () {
                        setState(() {
                          _bodyKeyValuePairs.removeAt(index);
                          _isModified = true;
                        });
                      },
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _bodyKeyValuePairs.add(const MapEntry('', ''));
              _isModified = true;
            });
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Field', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildStatusCode() {
    return SizedBox(
      width: 150,
      child: TextField(
        controller: _statusCodeController,
        decoration: const InputDecoration(
          labelText: 'Status Code',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        ),
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() => _isModified = true),
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.cancel, size: 18),
                  label: const Text('Cancel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _continueWithoutModification,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Continue'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          if (_isModified) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _modifyAndContinue,
                icon: const Icon(Icons.check_circle, size: 18),
                label: const Text('Modify & Continue'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}