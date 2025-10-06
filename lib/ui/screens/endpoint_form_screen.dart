import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/endpoint.dart';
import '../bloc/endpoint/endpoint_bloc.dart';

class EndpointFormScreen extends StatefulWidget {
  final Endpoint? endpoint;

  const EndpointFormScreen({Key? key, this.endpoint}) : super(key: key);

  @override
  State<EndpointFormScreen> createState() => _EndpointFormScreenState();
}

class _EndpointFormScreenState extends State<EndpointFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _patternController;
  late TextEditingController _mockResponseController;
  late TextEditingController _delayController;
  late TextEditingController _targetUrlController;

  late MatchType _matchType;
  late EndpointMode _mode;

  @override
  void initState() {
    super.initState();
    _patternController = TextEditingController(
      text: widget.endpoint?.pattern ?? '',
    );
    _mockResponseController = TextEditingController(
      text: widget.endpoint?.mockResponse ?? '{}',
    );
    _delayController = TextEditingController(
      text: widget.endpoint?.delayMs.toString() ?? '0',
    );
    _targetUrlController = TextEditingController(
      text: widget.endpoint?.targetUrl ?? '',
    );
    _matchType = widget.endpoint?.matchType ?? MatchType.exact;
    _mode = widget.endpoint?.mode ?? EndpointMode.mock;
  }

  @override
  void dispose() {
    _patternController.dispose();
    _mockResponseController.dispose();
    _delayController.dispose();
    _targetUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.endpoint == null ? 'Add Endpoint' : 'Edit Endpoint'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveEndpoint,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _patternController,
                decoration: const InputDecoration(
                  labelText: 'URL Pattern',
                  hintText: '/api/users or /api/* or ^/api/user/\\d+\$',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a URL pattern';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<MatchType>(
                value: _matchType,
                decoration: const InputDecoration(
                  labelText: 'Match Type',
                  border: OutlineInputBorder(),
                ),
                items: MatchType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.name.toUpperCase()),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _matchType = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<EndpointMode>(
                value: _mode,
                decoration: const InputDecoration(
                  labelText: 'Mode',
                  border: OutlineInputBorder(),
                ),
                items: EndpointMode.values.map((mode) {
                  return DropdownMenuItem(
                    value: mode,
                    child: Text(
                      mode == EndpointMode.mock ? 'Mock Response' : 'Pass Through',
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _mode = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              if (_mode == EndpointMode.mock) ...[
                TextFormField(
                  controller: _mockResponseController,
                  decoration: const InputDecoration(
                    labelText: 'Mock Response (JSON)',
                    hintText: '{"message": "Success"}',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 8,
                  validator: (value) {
                    if (_mode == EndpointMode.mock && (value == null || value.isEmpty)) {
                      return 'Please enter mock response';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _delayController,
                  decoration: const InputDecoration(
                    labelText: 'Response Delay (ms)',
                    hintText: '0',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (int.tryParse(value) == null) {
                        return 'Please enter a valid number';
                      }
                    }
                    return null;
                  },
                ),
              ] else ...[
                TextFormField(
                  controller: _targetUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Target URL (HTTPS)',
                    hintText: 'https://api.example.com/api/users',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_mode == EndpointMode.passThrough && (value == null || value.isEmpty)) {
                      return 'Please enter target URL';
                    }
                    if (value != null && value.isNotEmpty && !value.startsWith('http')) {
                      return 'URL must start with http:// or https://';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saveEndpoint,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  widget.endpoint == null ? 'Create Endpoint' : 'Update Endpoint',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveEndpoint() {
    if (_formKey.currentState!.validate()) {
      final now = DateTime.now();
      final endpoint = Endpoint(
        id: widget.endpoint?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        pattern: _patternController.text,
        matchType: _matchType,
        mode: _mode,
        mockResponse: _mode == EndpointMode.mock ? _mockResponseController.text : null,
        delayMs: _mode == EndpointMode.mock ? int.tryParse(_delayController.text) ?? 0 : 0,
        targetUrl: _mode == EndpointMode.passThrough ? _targetUrlController.text : null,
        createdAt: widget.endpoint?.createdAt ?? now,
        updatedAt: now,
        isEnabled: widget.endpoint?.isEnabled ?? true,
      );

      if (widget.endpoint == null) {
        context.read<EndpointBloc>().add(CreateEndpointEvent(endpoint));
      } else {
        context.read<EndpointBloc>().add(UpdateEndpointEvent(endpoint));
      }

      Navigator.pop(context);
    }
  }
}