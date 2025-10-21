import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/entities/endpoint.dart';
import '../../domain/entities/profile.dart'; // NEW
import '../bloc/endpoint/endpoint_bloc.dart';
import '../bloc/profile/profile_bloc.dart'; // NEW
import 'endpoint_form_screen.dart';

class EndpointsScreen extends StatefulWidget {
  const EndpointsScreen({super.key});

  @override
  State<EndpointsScreen> createState() => _EndpointsScreenState();
}

class _EndpointsScreenState extends State<EndpointsScreen> {
  // NEW - Profile filter
  String? _selectedProfileFilter;
  List<Profile> _availableProfiles = [];

  @override
  void initState() {
    super.initState();
    context.read<EndpointBloc>().add(LoadEndpointsEvent());
    context.read<ProfileBloc>().add(LoadProfilesEvent()); // NEW
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Endpoints'),
        actions: [
          IconButton(
            icon: const Icon(Icons.downloading),
            onPressed: _importEndpoints,
            tooltip: 'Import',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _exportEndpoints,
            tooltip: 'Export',
          ),
        ],
      ),
      body: BlocListener<ProfileBloc, ProfileState>(
        listener: (context, state) {
          if (state is ProfilesLoaded) {
            setState(() {
              _availableProfiles = state.profiles;
            });
          }
        },
        child: Column(
          children: [
            // NEW - Profile filter
            _buildProfileFilter(),
            Expanded(
              child: BlocConsumer<EndpointBloc, EndpointState>(
                listener: (context, state) {
                  if (state is EndpointError) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(state.message),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else if (state is EndpointExported) {
                    _saveAndShareExport(state.jsonData);
                  }
                },
                builder: (context, state) {
                  if (state is EndpointLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is EndpointLoaded) {
                    // NEW - Filter endpoints by profile
                    final filteredEndpoints = _filterEndpointsByProfile(
                      state.endpoints,
                      _selectedProfileFilter,
                    );

                    if (filteredEndpoints.isEmpty) {
                      return _buildEmptyState();
                    }
                    return _buildEndpointList(filteredEndpoints);
                  }

                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EndpointFormScreen(
                initialProfileId: _selectedProfileFilter,
              ),
            ),
          );
          context.read<EndpointBloc>().add(LoadEndpointsEvent());
          context.read<ProfileBloc>().add(LoadProfilesEvent());
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  // NEW - Profile filter widget
  Widget _buildProfileFilter() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DropdownButtonFormField<String?>(
          value: _selectedProfileFilter,
          decoration: const InputDecoration(
            labelText: 'Filter by Profile',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.folder),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All Endpoints'),
            ),
            ..._availableProfiles.map((profile) {
              return DropdownMenuItem<String?>(
                value: profile.id,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: profile.isActive ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(profile.name)),
                    Text(
                      '(${_getEndpointCountForProfile(profile.id)} endpoints)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          onChanged: (value) {
            setState(() {
              _selectedProfileFilter = value;
            });
          },
        ),
      ),
    );
  }

  // NEW - Filter endpoints by profile
  List<Endpoint> _filterEndpointsByProfile(
      List<Endpoint> endpoints,
      String? profileId,
      ) {
    if (profileId == null) {
      return endpoints;
    }

    final profile = _availableProfiles.firstWhere(
          (p) => p.id == profileId,
      orElse: () => _availableProfiles.first,
    );

    return endpoints.where((e) => profile.endpointIds.contains(e.id)).toList();
  }

  // NEW - Get endpoint count for a profile
  int _getEndpointCountForProfile(String profileId) {
    try {
      final profile = _availableProfiles.firstWhere((p) => p.id == profileId);
      return profile.endpointIds.length;
    } catch (e) {
      return 0;
    }
  }

  // NEW - Get profiles that use this endpoint
  List<Profile> _getProfilesForEndpoint(String endpointId) {
    return _availableProfiles
        .where((p) => p.endpointIds.contains(endpointId))
        .toList();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.settings_ethernet,
            size: 100,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            _selectedProfileFilter != null
                ? 'No endpoints in this profile'
                : 'No endpoints configured',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to add an endpoint',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointList(List<Endpoint> endpoints) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: endpoints.length,
      itemBuilder: (context, index) {
        final endpoint = endpoints[index];
        return _buildEndpointCard(endpoint);
      },
    );
  }

  Widget _buildEndpointCard(Endpoint endpoint) {
    // NEW - Get profiles using this endpoint
    final usedInProfiles = _getProfilesForEndpoint(endpoint.id);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: Icon(
          endpoint.mode == EndpointMode.mock ? Icons.code : Icons.swap_horiz,
          color: endpoint.isEnabled ? Colors.blue : Colors.grey,
        ),
        title: Text(
          endpoint.pattern,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            decoration: endpoint.isEnabled ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 4.0,
              runSpacing: 4.0,
              children: [
                _buildChip(
                  endpoint.mode == EndpointMode.mock ? 'Mock' : 'Pass-through',
                  endpoint.mode == EndpointMode.mock
                      ? Colors.green
                      : Colors.orange,
                ),
                _buildChip(
                  endpoint.matchType.name.toUpperCase(),
                  Colors.blue,
                ),
                if (endpoint.mode == EndpointMode.mock) ...[
                  _buildChip(
                    _getStatusCodeText(endpoint.statusCode),
                    _getStatusCodeColor(endpoint.statusCode),
                  ),
                ],
                if (endpoint.delayMs > 0) ...[
                  _buildChip(
                    '${endpoint.delayMs}ms',
                    Colors.purple,
                  ),
                ],
                if (endpoint.useConditionalMock &&
                    endpoint.conditionalMocks.isNotEmpty) ...[
                  _buildChip(
                    '${endpoint.conditionalMocks.length} Conditions',
                    Colors.teal,
                  ),
                ],
              ],
            ),
            // NEW - Show profiles using this endpoint
            if (usedInProfiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: usedInProfiles.map((profile) {
                  return Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder, size: 12, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          profile.name,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
        trailing: Switch(
          value: endpoint.isEnabled,
          onChanged: (value) {
            final updated = endpoint.copyWith(
              isEnabled: value,
              updatedAt: DateTime.now(),
            );
            context.read<EndpointBloc>().add(UpdateEndpointEvent(updated));
          },
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EndpointFormScreen(endpoint: endpoint),
            ),
          );
          context.read<EndpointBloc>().add(LoadEndpointsEvent());
          context.read<ProfileBloc>().add(LoadProfilesEvent());
        },
        onLongPress: () => _showDeleteDialog(endpoint),
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getStatusCodeText(int code) {
    return '$code';
  }

  Color _getStatusCodeColor(int code) {
    if (code >= 200 && code < 300) {
      return Colors.green;
    } else if (code >= 400 && code < 500) {
      return Colors.orange;
    } else if (code >= 500) {
      return Colors.red;
    }
    return Colors.grey;
  }

  void _showDeleteDialog(Endpoint endpoint) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Endpoint'),
          content: Text('Are you sure you want to delete "${endpoint.pattern}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                context
                    .read<EndpointBloc>()
                    .add(DeleteEndpointEvent(endpoint.id));
                Navigator.pop(dialogContext);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _importEndpoints() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        final jsonData = jsonDecode(jsonString);

        final endpointsJson = jsonData['endpoints'] as List;
        final endpoints =
        endpointsJson.map((json) => _jsonToEndpoint(json)).toList();

        if (mounted) {
          context.read<EndpointBloc>().add(ImportEndpointsEvent(endpoints));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported ${endpoints.length} endpoints')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Import failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportEndpoints() async {
    context.read<EndpointBloc>().add(ExportEndpointsEvent());
  }

  Future<void> _saveAndShareExport(String jsonData) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/endpoints_export.json');
      await file.writeAsString(jsonData);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Network Interceptor Endpoints Export',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export successful')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Endpoint _jsonToEndpoint(Map<String, dynamic> json) {
    return Endpoint(
      id: json['id'],
      pattern: json['pattern'],
      matchType:
      MatchType.values.firstWhere((e) => e.name == json['matchType']),
      mode: EndpointMode.values.firstWhere((e) => e.name == json['mode']),
      mockResponse: json['mockResponse'],
      statusCode: json['statusCode'] ?? 200,
      delayMs: json['delayMs'],
      targetUrl: json['targetUrl'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      isEnabled: json['isEnabled'] == 1,
    );
  }
}