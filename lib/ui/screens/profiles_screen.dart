import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';

import '../../domain/entities/profile.dart';
import '../bloc/profile/profile_bloc.dart';
import 'profile_detail_screen.dart';
import 'profile_form_screen.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({Key? key}) : super(key: key);

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ProfileBloc>().add(LoadProfilesEvent());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profiles'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _importProfile,
            tooltip: 'Import Profile',
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle),
            onPressed: () {
              _showStopAllDialog();
            },
            tooltip: 'Stop All Servers',
          ),
        ],
      ),
      body: BlocConsumer<ProfileBloc, ProfileState>(
        listener: (context, state) {
          if (state is ProfileError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          } else if (state is ProfileServerStarted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
          } else if (state is ProfileServerStopped) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.orange,
              ),
            );
          } else if (state is AllServersStopped) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.blue,
              ),
            );
          } else if (state is ProfileExported) {
            _saveAndShareExport(state.jsonData);
          }
        },
        builder: (context, state) {
          if (state is ProfileLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is ProfilesLoaded) {
            if (state.profiles.isEmpty) {
              return _buildEmptyState();
            }
            return _buildProfileList(state.profiles, state.runningProfileIds);
          }

          return const SizedBox();
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ProfileFormScreen(),
            ),
          );
          context.read<ProfileBloc>().add(LoadProfilesEvent());
        },
        icon: const Icon(Icons.add),
        label: const Text('New Profile'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 100,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No profiles configured',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to create a profile',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileList(List<Profile> profiles, List<String> runningIds) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: profiles.length,
      itemBuilder: (context, index) {
        final profile = profiles[index];
        final isRunning = runningIds.contains(profile.id);
        return _buildProfileCard(profile, isRunning);
      },
    );
  }

  Widget _buildProfileCard(Profile profile, bool isRunning) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      elevation: 2,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProfileDetailScreen(profile: profile),
            ),
          );
          context.read<ProfileBloc>().add(LoadProfilesEvent());
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Status Indicator
                  Container(
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
                  ),
                  const SizedBox(width: 12),

                  // Profile Name
                  Expanded(
                    child: Text(
                      profile.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // More Menu
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) => _handleMenuAction(value, profile),
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
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Description
              if (profile.description.isNotEmpty)
                Text(
                  profile.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

              const SizedBox(height: 12),

              // Info Chips
              Wrap(
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
              ),

              const SizedBox(height: 16),

              // Start/Stop Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (isRunning) {
                      context
                          .read<ProfileBloc>()
                          .add(StopProfileServerEvent(profile.id));
                    } else {
                      context
                          .read<ProfileBloc>()
                          .add(StartProfileServerEvent(profile.id));
                    }
                  },
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
              ),
            ],
          ),
        ),
      ),
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

  void _handleMenuAction(String action, Profile profile) {
    switch (action) {
      case 'edit':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileFormScreen(profile: profile),
          ),
        ).then((_) => context.read<ProfileBloc>().add(LoadProfilesEvent()));
        break;
      case 'duplicate':
        _showDuplicateDialog(profile);
        break;
      case 'export':
        context.read<ProfileBloc>().add(ExportProfileEvent(profile.id));
        break;
      case 'delete':
        _showDeleteDialog(profile);
        break;
    }
  }

  void _showDuplicateDialog(Profile profile) {
    final nameController = TextEditingController(text: '${profile.name} (Copy)');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Duplicate Profile'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'New Profile Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                context.read<ProfileBloc>().add(
                  DuplicateProfileEvent(profile.id, nameController.text),
                );
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Duplicate'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(Profile profile) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Profile'),
        content: Text('Are you sure you want to delete "${profile.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<ProfileBloc>().add(DeleteProfileEvent(profile.id));
              Navigator.pop(dialogContext);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showStopAllDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop All Servers'),
        content: const Text('Are you sure you want to stop all running servers?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<ProfileBloc>().add(StopAllServersEvent());
              Navigator.pop(dialogContext);
            },
            child: const Text('Stop All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _importProfile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();

        if (mounted) {
          context.read<ProfileBloc>().add(ImportProfileEvent(jsonString));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile imported successfully')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveAndShareExport(String jsonData) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/profile_export.json');
      await file.writeAsString(jsonData);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Profile Export',
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
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}