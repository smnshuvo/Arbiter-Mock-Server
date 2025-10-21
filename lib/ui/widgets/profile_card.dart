// lib/presentation/widgets/profile_card.dart
import 'package:flutter/material.dart';
import '../../domain/entities/profile.dart';

class ProfileCard extends StatelessWidget {
  final Profile profile;
  final bool isRunning;
  final VoidCallback onTap;
  final VoidCallback onStartStop;
  final Function(String) onMenuAction;

  const ProfileCard({
    Key? key,
    required this.profile,
    required this.isRunning,
    required this.onTap,
    required this.onStartStop,
    required this.onMenuAction,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStatusIndicator(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      profile.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildPopupMenu(context),
                ],
              ),
              if (profile.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  profile.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              _buildInfoChips(),
              const SizedBox(height: 16),
              _buildActionButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: isRunning ? Colors.green : Colors.grey,
        shape: BoxShape.circle,
        boxShadow: isRunning
            ? [
          BoxShadow(
            color: Colors.green.withOpacity(0.5),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ]
            : null,
      ),
    );
  }

  Widget _buildPopupMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: onMenuAction,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 20),
              SizedBox(width: 8),
              Text('Edit'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.content_copy, size: 20),
              SizedBox(width: 8),
              Text('Duplicate'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              Icon(Icons.file_upload, size: 20),
              SizedBox(width: 8),
              Text('Export'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 20, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildInfoChip(
          icon: Icons.router,
          label: 'Port ${profile.port}',
          color: Colors.blue,
        ),
        _buildInfoChip(
          icon: Icons.api,
          label: '${profile.endpointIds.length} endpoints',
          color: Colors.purple,
        ),
        if (profile.settings.autoPassThrough)
          _buildInfoChip(
            icon: Icons.swap_horiz,
            label: 'Auto Pass-Through',
            color: Colors.orange,
          ),
        if (profile.settings.useDeviceIp)
          _buildInfoChip(
            icon: Icons.wifi,
            label: 'Device IP',
            color: Colors.teal,
          ),
      ],
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onStartStop,
        icon: Icon(
          isRunning ? Icons.stop : Icons.play_arrow,
          color: Colors.white,
        ),
        label: Text(
          isRunning ? 'Stop Server' : 'Start Server',
          style: const TextStyle(color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isRunning ? Colors.red : Colors.green,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

// ============================================================
// lib/presentation/widgets/profile_selector_dropdown.dart
// ============================================================

class ProfileSelectorDropdown extends StatelessWidget {
  final Profile? selectedProfile;
  final List<Profile> profiles;
  final ValueChanged<Profile?> onChanged;

  const ProfileSelectorDropdown({
    Key? key,
    required this.selectedProfile,
    required this.profiles,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Profile?>(
            value: selectedProfile,
            isExpanded: true,
            hint: const Text('Select a profile'),
            icon: const Icon(Icons.arrow_drop_down),
            items: [
              const DropdownMenuItem<Profile?>(
                value: null,
                child: Text('All Profiles'),
              ),
              ...profiles.map((profile) {
                return DropdownMenuItem<Profile?>(
                  value: profile,
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
                      Expanded(
                        child: Text(
                          profile.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        ':${profile.port}',
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
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// lib/presentation/widgets/running_servers_widget.dart
// ============================================================

class RunningServersWidget extends StatelessWidget {
  final List<Profile> runningProfiles;
  final Function(String) onStop;
  final Function(String) onCopyUrl;

  const RunningServersWidget({
    Key? key,
    required this.runningProfiles,
    required this.onStop,
    required this.onCopyUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (runningProfiles.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No servers running',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Running Servers (${runningProfiles.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (runningProfiles.length > 1)
                  TextButton.icon(
                    onPressed: () {
                      // Stop all action would be handled by parent
                    },
                    icon: const Icon(Icons.stop_circle, size: 18),
                    label: const Text('Stop All'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: runningProfiles.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final profile = runningProfiles[index];
              return _buildServerTile(profile);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildServerTile(Profile profile) {
    final url = 'http://localhost:${profile.port}';

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.play_arrow, color: Colors.green, size: 20),
      ),
      title: Text(
        profile.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        url,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.blue,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () => onCopyUrl(profile.id),
            tooltip: 'Copy URL',
          ),
          IconButton(
            icon: const Icon(Icons.stop, size: 18, color: Colors.red),
            onPressed: () => onStop(profile.id),
            tooltip: 'Stop',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// lib/presentation/widgets/endpoint_profile_badge.dart
// ============================================================

class EndpointProfileBadge extends StatelessWidget {
  final List<String> profileNames;

  const EndpointProfileBadge({
    Key? key,
    required this.profileNames,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (profileNames.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: profileNames.map((name) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                name,
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
    );
  }
}