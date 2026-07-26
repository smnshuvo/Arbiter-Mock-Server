import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/ads/ad_banner.dart';
import '../../../core/ads/ad_config.dart';
import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/endpoint.dart';
import '../../../domain/entities/profile.dart';
import '../../bloc/endpoint/endpoint_bloc.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../bloc/server/server_bloc.dart';
import '../desktop/desktop_endpoints_pane.dart';
import '../endpoint_form_screen.dart';
import 'manage_profile_sheet.dart';

/// Full-screen mobile equivalent of the desktop workspace's endpoints pane —
/// phones push a new screen for the endpoint list, and another for the
/// editor, instead of the desktop's side-by-side panes (no room for both on
/// a phone). Opened by tapping a server card on [HomeScreen].
///
/// The server is passed in explicitly rather than read from [ProfileBloc]'s
/// active profile. Callers dispatch `SwitchActiveProfileEvent` before pushing
/// this screen, but that handler is async (it awaits the settings write and a
/// profile reload), so the active id in state is still the *previous* one when
/// this screen's `initState` runs — reading it there opened whichever server
/// happened to be active before, which showed up as landing on the wrong
/// endpoint list right after creating or deleting a server.
class MobileEndpointsScreen extends StatefulWidget {
  final String profileId;

  const MobileEndpointsScreen({super.key, required this.profileId});

  @override
  State<MobileEndpointsScreen> createState() => _MobileEndpointsScreenState();
}

class _MobileEndpointsScreenState extends State<MobileEndpointsScreen> {
  String get _profileId => widget.profileId;

  @override
  void initState() {
    super.initState();
    context.read<EndpointBloc>().add(LoadEndpointsEvent(_profileId));
  }

  bool _isRunning(ServerState state) {
    if (state is MultiServerRunning) {
      return state.runningServers.any((s) => s.profileId == _profileId);
    }
    if (state is ServerRunning) return state.profileId == _profileId;
    return false;
  }

  void _openEditor({Endpoint? endpoint}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EndpointFormScreen(endpoint: endpoint, profileId: _profileId),
      ),
    );
  }

  void _confirmDeleteServer(Profile profile, bool running) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete server'),
        content: Text(running
            ? 'Stop "${profile.name}" before deleting it.'
            : 'Delete "${profile.name}" and all of its endpoints? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          if (!running)
            TextButton(
              onPressed: () {
                context.read<ProfileBloc>().add(DeleteProfileEvent(profile.id));
                Navigator.pop(dialogContext); // close confirmation
                Navigator.pop(context); // leave the endpoints screen — profile is gone
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final running = _isRunning(context.watch<ServerBloc>().state);
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, profileState) {
        final profiles = profileState is ProfileLoaded ? profileState.profiles : <Profile>[];
        final profile = profiles.firstWhere(
          (p) => p.id == _profileId,
          orElse: () => Profile(
            id: _profileId,
            name: 'Server',
            settings: const ProfileSettings(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        final isDefault = profile.id == 'default';
        return Scaffold(
          backgroundColor: t.canvas,
          appBar: AppBar(
            title: Text(profile.name),
            actions: [
              IconButton(
                tooltip: isDefault ? "Can't delete the default server" : 'Delete server',
                icon: const Icon(Icons.delete_outline),
                onPressed: isDefault ? null : () => _confirmDeleteServer(profile, running),
              ),
              IconButton(
                tooltip: 'Manage server',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => showManageProfileSheet(
                  context: context,
                  profile: profile,
                  // Already on the endpoints screen — don't offer a button back to it.
                  showEndpointsAction: false,
                ),
              ),
            ],
          ),
          body: DesktopEndpointsPane(
            profileId: _profileId,
            profileName: profile.name,
            selectedEndpointId: null,
            onEndpointSelected: (ep) => _openEditor(endpoint: ep),
            onAddEndpoint: () => _openEditor(),
          ),
          bottomNavigationBar: AdBanner(adUnitId: AdConfig.bannerEndpoint),
        );
      },
    );
  }
}
