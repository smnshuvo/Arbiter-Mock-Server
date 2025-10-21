import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/endpoint.dart';
import '../../domain/entities/profile.dart';
import '../bloc/endpoint/endpoint_bloc.dart';
import '../bloc/profile/profile_bloc.dart';
import 'conditional_mock_screen.dart';

class EndpointFormScreen extends StatefulWidget {
  final Endpoint? endpoint;
  final String? initialProfileId; // NEW - auto-assign to this profile

  const EndpointFormScreen({
    Key? key,
    this.endpoint,
    this.initialProfileId,
  }) : super(key: key);

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

  // NEW - Profile assignment
  Set<String> _selectedProfileIds = {};
  List<Profile> _availableProfiles = [];
  bool _assignToProfiles = true;

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

    // NEW - Initialize profile assignment
    if (widget.initialProfileId != null) {
      _selectedProfileIds.add(widget.initialProfileId!);
    }

    // Load profiles
    context.read<ProfileBloc>().add(LoadProfilesEvent());
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
      body: BlocListener<ProfileBloc, ProfileState>(
        listener: (context, state) {
          if (state is ProfilesLoaded) {
            setState(() {
              _availableProfiles = state.profiles;

              // If editing, load existing profile assignments
              if (widget.endpoint != null) {
                _selectedProfileIds = state.profiles
                    .where((p) => p.endpointIds.contains(widget.endpoint!.id))
                    .map((p) => p.id)
                    .toSet();
              }
            });
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Endpoint Configuration Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Endpoint Configuration',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _patternController,
                          decoration: const InputDecoration(
                            labelText: 'URL Pattern',
                            hintText:
                                '/api/users or /api/* or ^/api/user/\\d+\$',
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
                                mode == EndpointMode.mock
                                    ? 'Mock Response'
                                    : 'Pass Through',
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _mode = value!;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Mock/Pass-through specific settings
                if (_mode == EndpointMode.mock) ...[
                  _buildMockSettingsCard(),
                ] else ...[
                  _buildPassThroughSettingsCard(),
                ],

                const SizedBox(height: 16),

                // NEW - Profile Assignment Card
                _buildProfileAssignmentCard(),

                const SizedBox(height: 24),

                // Save Button
                ElevatedButton(
                  onPressed: _saveEndpoint,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    widget.endpoint == null
                        ? 'Create Endpoint'
                        : 'Update Endpoint',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMockSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mock Response Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
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
              subtitle: const Text(
                  'Return different responses based on query params or body fields'),
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
                if (_mode == EndpointMode.mock &&
                    (value == null || value.isEmpty)) {
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
          ],
        ),
      ),
    );
  }

  Widget _buildPassThroughSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pass-Through Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _targetUrlController,
              decoration: const InputDecoration(
                labelText: 'Target URL (HTTPS)',
                hintText: 'https://api.example.com/api/users',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (_mode == EndpointMode.passThrough &&
                    (value == null || value.isEmpty)) {
                  return 'Please enter target URL';
                }
                if (value != null &&
                    value.isNotEmpty &&
                    !value.startsWith('http')) {
                  return 'URL must start with http:// or https://';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  // NEW - Profile Assignment Card
  Widget _buildProfileAssignmentCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Assign to Profiles',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Switch(
                  value: _assignToProfiles,
                  onChanged: (value) {
                    setState(() {
                      _assignToProfiles = value;
                      if (!value) {
                        _selectedProfileIds.clear();
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _assignToProfiles
                  ? 'Select which profiles should use this endpoint'
                  : 'This endpoint will not be assigned to any profile',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            if (_assignToProfiles) ...[
              const SizedBox(height: 16),
              if (_availableProfiles.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'No profiles available. Create a profile first.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                )
              else
                ..._availableProfiles.map((profile) {
                  final isSelected = _selectedProfileIds.contains(profile.id);
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedProfileIds.add(profile.id);
                        } else {
                          _selectedProfileIds.remove(profile.id);
                        }
                      });
                    },
                    title: Text(profile.name),
                    subtitle: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color:
                                profile.isActive ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Port ${profile.port}'),
                        const SizedBox(width: 8),
                        Text('${profile.endpointIds.length} endpoints'),
                      ],
                    ),
                    secondary: Icon(
                      Icons.folder,
                      color: isSelected ? Colors.blue : Colors.grey,
                    ),
                  );
                }),
              if (_selectedProfileIds.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${_selectedProfileIds.length} profile(s) selected',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _saveEndpoint() async {
    if (_formKey.currentState!.validate()) {
      final now = DateTime.now();
      final endpoint = Endpoint(
        id: widget.endpoint?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        pattern: _patternController.text,
        matchType: _matchType,
        mode: _mode,
        mockResponse:
            _mode == EndpointMode.mock ? _mockResponseController.text : null,
        statusCode: _mode == EndpointMode.mock ? _statusCode : 200,
        delayMs: _mode == EndpointMode.mock
            ? int.tryParse(_delayController.text) ?? 0
            : 0,
        targetUrl: _mode == EndpointMode.passThrough
            ? _targetUrlController.text
            : null,
        createdAt: widget.endpoint?.createdAt ?? now,
        updatedAt: now,
        isEnabled: widget.endpoint?.isEnabled ?? true,
        useConditionalMock:
            _mode == EndpointMode.mock ? _useConditionalMock : false,
        conditionalMocks: _mode == EndpointMode.mock && _useConditionalMock
            ? _conditionalMocks
            : [],
      );

      // Create or update endpoint
      if (widget.endpoint == null) {
        context.read<EndpointBloc>().add(CreateEndpointEvent(endpoint));
      } else {
        context.read<EndpointBloc>().add(UpdateEndpointEvent(endpoint));
      }

      // NEW - Assign to selected profiles
      if (_assignToProfiles && _selectedProfileIds.isNotEmpty) {
        final profileBloc = context.read<ProfileBloc>();
        for (final profileId in _selectedProfileIds) {
          // Get current profile
          final profileState = profileBloc.state;
          if (profileState is ProfilesLoaded) {
            final profile = profileState.profiles.firstWhere(
              (p) => p.id == profileId,
              orElse: () => profileState.profiles.first,
            );

            // Add endpoint to profile if not already there
            if (!profile.endpointIds.contains(endpoint.id)) {
              final updatedEndpointIds = [
                ...profile.endpointIds,
                endpoint.id,
              ];
              profileBloc.add(
                AssignEndpointsEvent(profileId, updatedEndpointIds),
              );
            }
          }
        }

        // Also remove from profiles that were deselected
        if (widget.endpoint != null) {
          final profileState = profileBloc.state;
          if (profileState is ProfilesLoaded) {
            final previouslyAssignedProfiles = profileState.profiles
                .where((p) => p.endpointIds.contains(endpoint.id))
                .map((p) => p.id)
                .toSet();

            final profilesToRemoveFrom =
                previouslyAssignedProfiles.difference(_selectedProfileIds);

            for (final profileId in profilesToRemoveFrom) {
              final profile = profileState.profiles.firstWhere(
                (p) => p.id == profileId,
              );
              final updatedEndpointIds =
                  profile.endpointIds.where((id) => id != endpoint.id).toList();
              profileBloc.add(
                AssignEndpointsEvent(profileId, updatedEndpointIds),
              );
            }
          }
        }
      }

      Navigator.pop(context);
    }
  }
}
