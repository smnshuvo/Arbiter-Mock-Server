import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/endpoint.dart';
import '../bloc/endpoint/endpoint_bloc.dart';
import 'conditional_mock_screen.dart';

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
  late int _statusCode;
  late bool _useConditionalMock;
  late List<ConditionalMock> _conditionalMocks;

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
    _statusCode = widget.endpoint?.statusCode ?? 200;
    _useConditionalMock = widget.endpoint?.useConditionalMock ?? false;
    _conditionalMocks = List.from(widget.endpoint?.conditionalMocks ?? []);
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
                DropdownButtonFormField<int>(
                  value: _statusCode,
                  decoration: const InputDecoration(
                    labelText: 'HTTP Status Code',
                    border: OutlineInputBorder(),
                    helperText: 'Select the response status code',
                  ),
                  items: HttpStatusCode.commonCodes.map((code) {
                    return DropdownMenuItem(
                      value: code,
                      child: Text(HttpStatusCode.getStatusText(code)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _statusCode = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Use Conditional Mock'),
                  subtitle: const Text('Return different responses based on query params or body fields'),
                  value: _useConditionalMock,
                  onChanged: (value) {
                    setState(() {
                      _useConditionalMock = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                if (_useConditionalMock) ...[
                  Card(
                    color: Colors.blue.shade50,
                    child: ListTile(
                      leading: const Icon(Icons.rule, color: Colors.blue),
                      title: Text(
                        '${_conditionalMocks.length} Conditional Mock(s)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text('Tap to manage conditional mocks'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () async {
                        final result = await Navigator.push<List<ConditionalMock>>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ConditionalMockScreen(
                              conditionalMocks: _conditionalMocks,
                            ),
                          ),
                        );
                        if (result != null) {
                          setState(() {
                            _conditionalMocks = result;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _mockResponseController,
                  decoration: InputDecoration(
                    labelText: _useConditionalMock
                        ? 'Default Mock Response (JSON)'
                        : 'Mock Response (JSON)',
                    hintText: '{"message": "Success"}',
                    border: const OutlineInputBorder(),
                    helperText: _useConditionalMock
                        ? 'Used when no conditional mock matches'
                        : null,
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
        statusCode: _mode == EndpointMode.mock ? _statusCode : 200,
        delayMs: _mode == EndpointMode.mock ? int.tryParse(_delayController.text) ?? 0 : 0,
        targetUrl: _mode == EndpointMode.passThrough ? _targetUrlController.text : null,
        createdAt: widget.endpoint?.createdAt ?? now,
        updatedAt: now,
        isEnabled: widget.endpoint?.isEnabled ?? true,
        useConditionalMock: _mode == EndpointMode.mock ? _useConditionalMock : false,
        conditionalMocks: _mode == EndpointMode.mock && _useConditionalMock ? _conditionalMocks : [],
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