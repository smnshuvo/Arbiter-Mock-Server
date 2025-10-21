import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/profile/profile_bloc.dart';
import '../bloc/server/server_bloc.dart';
import '../../domain/entities/profile.dart';
import 'profiles_screen.dart';
import 'endpoint_screen.dart';
import 'logs_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const iconAssetPath = 'assets/app_icon/app_icon.png';

  @override
  void initState() {
    super.initState();
    context.read<ProfileBloc>().add(LoadProfilesEvent());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arbiter'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<ProfileBloc>().add(LoadProfilesEvent());
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: BlocBuilder<ProfileBloc, ProfileState>(
        builder: (context, state) {
          if (state is ProfileLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is ProfilesLoaded) {
            final runningProfiles = state.profiles
                .where((p) => state.runningProfileIds.contains(p.id))
                .toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildServerStatusSummary(
                    state.profiles.length,
                    runningProfiles.length,
                  ),
                  const SizedBox(height: 16),
                  if (runningProfiles.isNotEmpty) ...[
                    _buildRunningServersSection(runningProfiles),
                    const SizedBox(height: 16),
                  ],
                  _buildQuickActions(),
                ],
              ),
            );
          }

          return _buildEmptyState();
        },
      ),
    );
  }

  Widget _buildServerStatusSummary(int totalProfiles, int runningCount) {
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
                    color: runningCount > 0 ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                    boxShadow: runningCount > 0
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
                  runningCount > 0
                      ? '$runningCount Server${runningCount > 1 ? 's' : ''} Running'
                      : 'No Servers Running',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatCard(
                  icon: Icons.folder,
                  label: 'Total Profiles',
                  value: totalProfiles.toString(),
                  color: Colors.blue,
                ),
                _buildStatCard(
                  icon: Icons.play_circle,
                  label: 'Active',
                  value: runningCount.toString(),
                  color: Colors.green,
                ),
                _buildStatCard(
                  icon: Icons.pause_circle,
                  label: 'Inactive',
                  value: (totalProfiles - runningCount).toString(),
                  color: Colors.orange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildRunningServersSection(List<Profile> runningProfiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Running Servers',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                context.read<ProfileBloc>().add(StopAllServersEvent());
              },
              icon: const Icon(Icons.stop_circle, color: Colors.red),
              label: const Text(
                'Stop All',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...runningProfiles.map((profile) => _buildRunningServerCard(profile)),
      ],
    );
  }

  Widget _buildRunningServerCard(Profile profile) {
    final url = 'http://localhost:${profile.port}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.play_arrow, color: Colors.green),
        ),
        title: Text(
          profile.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              url,
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildChip('Port ${profile.port}', Colors.blue),
                const SizedBox(width: 8),
                _buildChip(
                  '${profile.endpointIds.length} endpoints',
                  Colors.purple,
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('URL copied to clipboard')),
                );
              },
              tooltip: 'Copy URL',
            ),
            IconButton(
              icon: const Icon(Icons.stop, size: 20, color: Colors.red),
              onPressed: () {
                context
                    .read<ProfileBloc>()
                    .add(StopProfileServerEvent(profile.id));
              },
              tooltip: 'Stop Server',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _buildActionCard(
          icon: Icons.folder,
          title: 'Manage Profiles',
          subtitle: 'Create, edit, and manage server profiles',
          color: Colors.blue,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfilesScreen()),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildActionCard(
          icon: Icons.api,
          title: 'Manage Endpoints',
          subtitle: 'Configure API endpoints and mock responses',
          color: Colors.purple,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const EndpointsScreen()),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildActionCard(
          icon: Icons.list_alt,
          title: 'View Logs',
          subtitle: 'Monitor request and response logs',
          color: Colors.orange,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const LogsScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.rocket_launch,
            size: 100,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'Welcome to Arbiter',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Get started by creating your first profile',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfilesScreen()),
              );
            },
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'Create Profile',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
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
}
