import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/profile.dart';
import '../../domain/entities/endpoint.dart';
import '../bloc/profile/profile_bloc.dart';
import '../bloc/endpoint/endpoint_bloc.dart';
import 'profile_form_screen.dart';
import 'endpoint_selection_screen.dart';

class ProfileDetailScreen extends StatefulWidget {
  final Profile profile;

  const ProfileDetailScreen({Key? key, required this.profile}) : super(key: key);

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  late Profile _currentProfile;
  List<Endpoint> _allEndpoints = [];
  List<Endpoint> _profileEndpoints = [];
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.profile;
    context.read<EndpointBloc>().add(LoadEndpointsEvent());
    _checkServerStatus();
  }

  void _checkServerStatus() {
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is ProfilesLoaded) {
      _isRunning = profileState.runningProfileIds.contains(_currentProfile.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentProfile.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileFormScreen(profile: _currentProfile),
                ),
              );
              // Reload profile
              context.read<ProfileBloc>().add(LoadProfilesEvent());
            },
            tooltip: 'Edit Profile',
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: () {
              context.read<ProfileBloc>().add(ExportProfileEvent(_currentProfile.id));
            },
            tooltip: 'Export Profile',
          ),
        ],
      ),
      body: BlocListener<ProfileBloc, ProfileState>(
        listener: (context, state) {
          if (state is ProfilesLoaded) {
            final updatedProfile = state.profiles.firstWhere(
                  (p) => p.id == _currentProfile.id,
              orElse: () => _currentProfile,
            );
            setState(() {
              _currentProfile = updatedProfile;
              _isRunning = state.runningProfileIds.contains(_currentProfile.id);
            });
          }
        },
        child: BlocListener<EndpointBloc, EndpointState>(
          listener: (context, state) {
            if (state is EndpointLoaded) {
              setState(() {
                _allEndpoints = state.endpoints;
                _profileEndpoints = state.endpoints
                    .where((e) => _currentProfile.endpointIds.contains(e.id))
                    .toList();
              });
            }
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildServerStatusCard(),
                const SizedBox(height: 16),
                _buildProfileInfoCard(),
                const SizedBox(height: 16),
                _buildSettingsCard(),
                const SizedBox(height: 16),
                _buildEndpointsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerStatusCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _isRunning ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                    boxShadow: _isRunning
                        ? [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.5),
                        blurRadius: 12,
                        spreadRadius: 3,
                      ),
                    ]
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _isRunning ? 'Server Running' : 'Server Stopped',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (_isRunning) ...[
              const SizedBox(height: 16),
              Text(
                'http://localhost:${_currentProfile.port}',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: 'http://localhost:${_currentProfile.port}'),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('URL copied to clipboard')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy URL'),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (_isRunning) {
                    context
                        .read<ProfileBloc>()
                        .add(StopProfileServerEvent(_currentProfile.id));
                  } else {
                    context
                        .read<ProfileBloc>()
                        .add(StartProfileServerEvent(_currentProfile.id));
                  }
                },
                icon: Icon(
                  _isRunning ? Icons.stop : Icons.play_arrow,
                  color: Colors.white,
                ),
                label: Text(
                  _isRunning ? 'Stop Server' : 'Start Server',
                  style: const TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRunning ? Colors.red : Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Profile Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Name', _currentProfile.name),
            if (_currentProfile.description.isNotEmpty)
              _buildInfoRow('Description', _currentProfile.description),
            _buildInfoRow('Port', _currentProfile.port.toString()),
            _buildInfoRow(
              'Created',
              _formatDate(_currentProfile.createdAt),
            ),
            _buildInfoRow(
              'Last Updated',
              _formatDate(_currentProfile.updatedAt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Server Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildSettingTile(
              icon: Icons.wifi,
              title: 'Use Device IP',
              value: _currentProfile.settings.useDeviceIp,
            ),
            _buildSettingTile(
              icon: Icons.swap_horiz,
              title: 'Auto Pass-Through',
              value: _currentProfile.settings.autoPassThrough,
            ),
            if (_currentProfile.settings.globalPassThroughUrl != null)
              _buildInfoRow(
                'Global Pass-Through URL',
                _currentProfile.settings.globalPassThroughUrl!,
              ),
            _buildSettingTile(
              icon: Icons.all_inclusive,
              title: 'Pass Through All',
              value: _currentProfile.settings.passThroughAll,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndpointsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Assigned Endpoints (${_profileEndpoints.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push<List<String>>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EndpointSelectionScreen(
                          selectedEndpointIds: _currentProfile.endpointIds,
                        ),
                      ),
                    );

                    if (result != null) {
                      context.read<ProfileBloc>().add(
                        AssignEndpointsEvent(_currentProfile.id, result),
                      );
                    }
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Manage'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_profileEndpoints.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'No endpoints assigned',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            else
              ..._profileEndpoints.map((endpoint) => _buildEndpointTile(endpoint)),
          ],
        ),
      ),
    );
  }

  Widget _buildEndpointTile(Endpoint endpoint) {
    return ListTile(
      leading: Icon(
        endpoint.mode == EndpointMode.mock ? Icons.code : Icons.swap_horiz,
        color: endpoint.isEnabled ? Colors.blue : Colors.grey,
      ),
      title: Text(
        endpoint.pattern,
        style: TextStyle(
          decoration: endpoint.isEnabled ? null : TextDecoration.lineThrough,
        ),
      ),
      subtitle: Row(
        children: [
          _buildChip(
            endpoint.mode == EndpointMode.mock ? 'Mock' : 'Pass-through',
            endpoint.mode == EndpointMode.mock ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          _buildChip(
            endpoint.matchType.name.toUpperCase(),
            Colors.blue,
          ),
        ],
      ),
      trailing: endpoint.isEnabled
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.cancel, color: Colors.grey),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required bool value,
  }) {
    return ListTile(
      leading: Icon(icon, color: value ? Colors.blue : Colors.grey),
      title: Text(title),
      trailing: Icon(
        value ? Icons.check_circle : Icons.cancel,
        color: value ? Colors.green : Colors.grey,
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}