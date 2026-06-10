import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/endpoint.dart';
import '../../domain/entities/profile.dart';
import '../bloc/endpoint/endpoint_bloc.dart';
import '../bloc/profile/profile_bloc.dart';
import 'endpoint_form_screen.dart';

class EndpointsScreen extends StatefulWidget {
  const EndpointsScreen({super.key});

  @override
  State<EndpointsScreen> createState() => _EndpointsScreenState();
}

class _EndpointsScreenState extends State<EndpointsScreen> {
  String _activeProfileId = 'default';

  @override
  void initState() {
    super.initState();
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is ProfileLoaded) {
      _activeProfileId = profileState.activeProfileId;
    }
    context.read<EndpointBloc>().add(LoadEndpointsEvent(_activeProfileId));
  }

  void _onProfileChanged(String profileId) {
    setState(() => _activeProfileId = profileId);
    context.read<EndpointBloc>().add(LoadEndpointsEvent(profileId));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProfileBloc, ProfileState>(
      listener: (context, state) {
        if (state is ProfileLoaded && state.activeProfileId != _activeProfileId) {
          _onProfileChanged(state.activeProfileId);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: BlocBuilder<ProfileBloc, ProfileState>(
            builder: (context, state) {
              if (state is ProfileLoaded) {
                final profile = state.profiles.firstWhere(
                  (p) => p.id == _activeProfileId,
                  orElse: () => state.profiles.first,
                );
                return Text('Endpoints · ${profile.name}');
              }
              return const Text('Endpoints');
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.switch_account_outlined),
              onPressed: _showProfileSelector,
              tooltip: 'Switch Profile',
            ),
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
        body: BlocConsumer<EndpointBloc, EndpointState>(
          listener: (context, state) {
            if (state is EndpointError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message), backgroundColor: Colors.red),
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
              return Column(
                children: [
                  _buildToggleAllBar(state.endpoints),
                  Expanded(
                    child: state.endpoints.isEmpty
                        ? _buildEmptyState()
                        : _buildEndpointList(state.endpoints),
                  ),
                ],
              );
            }

            return const SizedBox();
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EndpointFormScreen(profileId: _activeProfileId),
              ),
            );
            context.read<EndpointBloc>().add(LoadEndpointsEvent(_activeProfileId));
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildToggleAllBar(List<Endpoint> endpoints) {
    if (endpoints.isEmpty) return const SizedBox.shrink();
    final allEnabled = endpoints.every((e) => e.isEnabled);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '${endpoints.length} endpoint${endpoints.length == 1 ? '' : 's'}',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const Spacer(),
          TextButton.icon(
            icon: Icon(allEnabled ? Icons.toggle_off_outlined : Icons.toggle_on_outlined),
            label: Text(allEnabled ? 'Disable All' : 'Enable All'),
            onPressed: () {
              context.read<EndpointBloc>().add(ToggleAllEndpointsEvent(
                profileId: _activeProfileId,
                enabled: !allEnabled,
              ));
            },
          ),
        ],
      ),
    );
  }

  void _showProfileSelector() {
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is! ProfileLoaded) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => _ProfileSelectorSheet(
        profiles: profileState.profiles,
        activeProfileId: _activeProfileId,
        onSelect: (profileId) {
          Navigator.pop(ctx);
          context.read<ProfileBloc>().add(SwitchActiveProfileEvent(profileId));
          _onProfileChanged(profileId);
        },
        onCreateProfile: () {
          Navigator.pop(ctx);
          _showCreateProfileDialog();
        },
        onDeleteProfile: (profileId) {
          Navigator.pop(ctx);
          context.read<ProfileBloc>().add(DeleteProfileEvent(profileId));
          if (profileId == _activeProfileId) {
            _onProfileChanged('default');
          }
        },
      ),
    );
  }

  void _showCreateProfileDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Profile'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Profile name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context.read<ProfileBloc>().add(CreateProfileEvent(name: name));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.settings_ethernet, size: 100, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No endpoints configured',
              style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('Tap + to add an endpoint',
              style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildEndpointList(List<Endpoint> endpoints) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: endpoints.length,
      itemBuilder: (context, index) => _buildEndpointCard(endpoints[index]),
    );
  }

  Widget _buildEndpointCard(Endpoint endpoint) {
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
                  endpoint.mode == EndpointMode.mock ? Colors.green : Colors.orange,
                ),
                _buildChip(endpoint.matchType.name.toUpperCase(), Colors.blue),
                if (endpoint.mode == EndpointMode.mock)
                  _buildChip(_getStatusCodeText(endpoint.statusCode), _getStatusCodeColor(endpoint.statusCode)),
                if (endpoint.delayMs > 0)
                  _buildChip('${endpoint.delayMs}ms', Colors.purple),
                if (endpoint.useConditionalMock && endpoint.conditionalMocks.isNotEmpty)
                  _buildChip('${endpoint.conditionalMocks.length} Conditions', Colors.teal),
              ],
            ),
          ],
        ),
        trailing: Switch(
          value: endpoint.isEnabled,
          onChanged: (value) {
            context.read<EndpointBloc>().add(UpdateEndpointEvent(
              endpoint.copyWith(isEnabled: value),
            ));
          },
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EndpointFormScreen(endpoint: endpoint, profileId: _activeProfileId),
            ),
          );
          context.read<EndpointBloc>().add(LoadEndpointsEvent(_activeProfileId));
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
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }

  String _getStatusCodeText(int code) => '$code';

  Color _getStatusCodeColor(int code) {
    if (code >= 200 && code < 300) return Colors.green;
    if (code >= 400 && code < 500) return Colors.orange;
    if (code >= 500) return Colors.red;
    return Colors.grey;
  }

  void _showDeleteDialog(Endpoint endpoint) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Endpoint'),
        content: Text('Are you sure you want to delete "${endpoint.pattern}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              context.read<EndpointBloc>().add(DeleteEndpointEvent(endpoint.id, _activeProfileId));
              Navigator.pop(dialogContext);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
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
        final endpoints = endpointsJson.map((json) => _jsonToEndpoint(json)).toList();

        if (mounted) {
          context.read<EndpointBloc>().add(ImportEndpointsEvent(endpoints, _activeProfileId));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported ${endpoints.length} endpoints into current profile')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportEndpoints() async {
    context.read<EndpointBloc>().add(ExportEndpointsEvent(_activeProfileId));
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
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Endpoint _jsonToEndpoint(Map<String, dynamic> json) {
    return Endpoint(
      id: json['id'] ?? const Uuid().v4(),
      profileId: _activeProfileId,
      pattern: json['pattern'],
      matchType: MatchType.values.firstWhere((e) => e.name == json['matchType'], orElse: () => MatchType.exact),
      mode: EndpointMode.values.firstWhere((e) => e.name == json['mode'], orElse: () => EndpointMode.mock),
      mockResponse: json['mockResponse'],
      statusCode: json['statusCode'] ?? 200,
      delayMs: json['delayMs'] ?? 0,
      targetUrl: json['targetUrl'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : DateTime.now(),
      isEnabled: json['isEnabled'] == 1 || json['isEnabled'] == true,
    );
  }
}

class _ProfileSelectorSheet extends StatelessWidget {
  final List<Profile> profiles;
  final String activeProfileId;
  final void Function(String) onSelect;
  final VoidCallback onCreateProfile;
  final void Function(String) onDeleteProfile;

  const _ProfileSelectorSheet({
    required this.profiles,
    required this.activeProfileId,
    required this.onSelect,
    required this.onCreateProfile,
    required this.onDeleteProfile,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('Select Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(),
          ...profiles.map((profile) => ListTile(
            leading: Icon(
              Icons.folder_outlined,
              color: profile.id == activeProfileId ? Theme.of(context).colorScheme.primary : null,
            ),
            title: Text(
              profile.name,
              style: TextStyle(
                fontWeight: profile.id == activeProfileId ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: profile.description != null && profile.description!.isNotEmpty
                ? Text(profile.description!)
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (profile.id == activeProfileId)
                  Icon(Icons.check, color: Theme.of(context).colorScheme.primary),
                if (profile.id != 'default')
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => onDeleteProfile(profile.id),
                    tooltip: 'Delete profile',
                  ),
              ],
            ),
            onTap: () => onSelect(profile.id),
          )),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('New Profile'),
            onTap: onCreateProfile,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
