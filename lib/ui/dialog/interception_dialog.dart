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

    _startTimer();
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
                    _buildHeaders(),
                    const SizedBox(height: 16),
                    _buildBody(),
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
          CircularProgressIndicator(
            value: _remainingSeconds / widget.timeoutSeconds,
            backgroundColor: Colors.white30,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
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
            ),
            enabled: widget.interception.isRequest,
            onChanged: (_) => setState(() => _isModified = true),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaders() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Headers',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Column(
                  children: _headers.entries
                      .map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${e.key}: ${e.value}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Body',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (_bodyController.text.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _bodyController.text = _formatJson(_bodyController.text);
                  });
                },
                icon: const Icon(Icons.format_align_left, size: 16),
                label: const Text('Format JSON'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _bodyController,
          maxLines: 10,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Request/Response body',
          ),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          onChanged: (_) => setState(() => _isModified = true),
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
        color: Theme.of(context).colorScheme.surface,
        border: Border(
            top: BorderSide(
          color: Colors.grey.shade800,
        )),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: SizedBox(
        width: double.maxFinite,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ElevatedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.cancel),
              label: const Text('Cancel Request'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _continueWithoutModification,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Continue'),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _isModified ? _modifyAndContinue : null,
              icon: const Icon(Icons.edit),
              label: const Text('Modify & Continue'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
