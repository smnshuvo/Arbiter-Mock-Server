import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/profile.dart';
import '../../../domain/entities/request_log.dart';
import '../../bloc/endpoint/endpoint_bloc.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../bloc/server/server_bloc.dart';
import 'desktop_detail_pane.dart';
import 'desktop_logs_pane.dart';
import 'manage_profile_dialog.dart';
import 'server_rail.dart';

/// Wide-layout workspace shown by [HomeScreen] once the window/screen crosses
/// [kWideLayoutBreakpoint]: server rail | logs feed | request/response detail,
/// with server settings and the endpoint editor tucked into a "Manage" overlay.
class DesktopWorkspaceScreen extends StatefulWidget {
  final ServerState serverState;
  final Map<String, int> endpointCounts;

  const DesktopWorkspaceScreen({
    super.key,
    required this.serverState,
    required this.endpointCounts,
  });

  @override
  State<DesktopWorkspaceScreen> createState() => _DesktopWorkspaceScreenState();
}

class _DesktopWorkspaceScreenState extends State<DesktopWorkspaceScreen> {
  String? _selectedProfileId;
  RequestLog? _selectedLog;
  bool _urlCopied = false;

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    setState(() => _urlCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _urlCopied = false);
    });
  }

  @override
  void initState() {
    super.initState();
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is ProfileLoaded) {
      _selectedProfileId = profileState.activeProfileId;
    }
    context.read<EndpointBloc>().add(LoadEndpointsEvent(_selectedProfileId ?? 'default'));
  }

  Map<String, ({String url, int port})> _runningMap(ServerState state) {
    if (state is MultiServerRunning) {
      return {
        for (final srv in state.runningServers) srv.profileId: (url: srv.url, port: srv.port),
      };
    }
    if (state is ServerRunning) {
      return {state.profileId: (url: state.url, port: state.port)};
    }
    return const {};
  }

  void _selectProfile(String profileId) {
    setState(() {
      _selectedProfileId = profileId;
      _selectedLog = null;
    });
    context.read<ProfileBloc>().add(SwitchActiveProfileEvent(profileId));
    context.read<EndpointBloc>().add(LoadEndpointsEvent(profileId));
  }

  void _toggleRun(Profile profile, bool running) {
    if (running) {
      context.read<ServerBloc>().add(StopProfileEvent(profile.id));
    } else {
      context.read<ServerBloc>().add(StartProfileEvent(
            profileId: profile.id,
            profileName: profile.name,
            port: profile.port,
            useDeviceIp: profile.settings.useDeviceIp,
            passThroughUrl: profile.settings.globalPassThroughUrl,
            autoPassThrough: profile.settings.autoPassThrough,
          ));
    }
  }

  void _openManage(Profile profile) {
    showDialog(
      context: context,
      builder: (dialogContext) => ManageProfileDialog(
        profile: profile,
        onDeleted: () {
          if (profile.id == _selectedProfileId) _selectProfile('default');
        },
      ),
    );
  }

  void _showCreateProfileDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New server'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Server name'),
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

  @override
  Widget build(BuildContext context) {
    final runningMap = _runningMap(widget.serverState);
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, profileState) {
        final profiles = profileState is ProfileLoaded ? profileState.profiles : <Profile>[];
        final selectedId = _selectedProfileId ?? (profiles.isNotEmpty ? profiles.first.id : 'default');
        final selectedProfile = profiles.firstWhere(
          (p) => p.id == selectedId,
          orElse: () => Profile(
            id: 'default',
            name: 'Default',
            settings: const ProfileSettings(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        final running = runningMap.containsKey(selectedProfile.id);
        final t = ArbTokens.of(context);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 240,
              child: ServerRail(
                selectedProfileId: selectedId,
                runningMap: runningMap,
                endpointCounts: widget.endpointCounts,
                onSelect: _selectProfile,
                onCreateProfile: _showCreateProfileDialog,
              ),
            ),
            VerticalDivider(width: 1, color: t.border),
            Expanded(
              child: Column(
                children: [
                  _buildHeader(selectedProfile, running, runningMap[selectedProfile.id]),
                  Divider(height: 1, color: t.border),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: DesktopLogsPane(
                            profileId: selectedProfile.id,
                            selectedLogId: _selectedLog?.id,
                            onLogSelected: (log) => setState(() => _selectedLog = log),
                          ),
                        ),
                        VerticalDivider(width: 1, color: t.border),
                        Expanded(
                          flex: 4,
                          child: DesktopDetailPane(log: _selectedLog),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(Profile profile, bool running, ({String url, int port})? runningInfo) {
    final t = ArbTokens.of(context);
    final url = runningInfo?.url ?? 'http://localhost:${profile.port}';
    return Container(
      color: t.surface,
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.asset(
              'assets/app_icon/app_icon.png',
              width: 22,
              height: 22,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: running ? t.green : t.textMuted,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.name,
                    overflow: TextOverflow.ellipsis,
                    style: t.sans(size: 16, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(url,
                          overflow: TextOverflow.ellipsis, style: t.mono(size: 11.5, color: t.textMuted)),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => _copyUrl(url),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Text(_urlCopied ? 'Copied' : 'Copy',
                            style: t.sans(
                                size: 11, weight: FontWeight.w700, color: t.accent)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => _toggleRun(profile, running),
            style: FilledButton.styleFrom(
              backgroundColor: running ? const Color(0xFFDC2626) : t.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
            ),
            child: Text(running ? 'Stop' : 'Run',
                style: t.sans(size: 12.5, weight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _openManage(profile),
            style: OutlinedButton.styleFrom(
              foregroundColor: t.textSecondary,
              side: BorderSide(color: t.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
            ),
            icon: const Icon(Icons.more_horiz, size: 18),
            label: Text('Manage', style: t.sans(size: 12.5)),
          ),
        ],
      ),
    );
  }
}
