import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/network_condition.dart';
import '../../../domain/entities/profile.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../bloc/server/server_bloc.dart';
import '../desktop/endpoint_import_export_actions.dart';
import '../endpoint_editor/widgets/network_condition_field.dart';
import 'arb_bottom_sheet.dart';
import 'mobile_endpoints_screen.dart';
import 'profile_settings_fields.dart';
import '../../widgets/pass_through_url_field.dart';

/// Mobile equivalent of the desktop `ManageProfileDialog`, shown as a bottom
/// sheet from the endpoints screen's gear icon.
///
/// There is deliberately no "Save changes" button: port/host need a restart
/// so they're disabled while running and only take effect through the
/// primary "Start" action (which saves the whole profile, then starts it —
/// the same save-then-start pattern already used elsewhere for profiles).
/// Everything else (name, auto pass-through/URL, network throttle) saves
/// immediately as it changes while the server is already running, mirroring
/// the desktop workspace's quick-settings panel. Deleting the server lives in
/// the endpoints screen's app bar instead of here.
///
/// Set [showEndpointsAction] to false when the sheet is opened from the
/// endpoints screen itself — the "Manage endpoints" button would only lead
/// back to where the user already is.
void showManageProfileSheet({
  required BuildContext context,
  required Profile profile,
  bool showEndpointsAction = true,
}) {
  showArbBottomSheet(
    context: context,
    title: 'Manage ${profile.name}',
    builder: (_) => _ManageProfileSheetBody(
      profile: profile,
      showEndpointsAction: showEndpointsAction,
    ),
  );
}

class _ManageProfileSheetBody extends StatefulWidget {
  final Profile profile;
  final bool showEndpointsAction;
  const _ManageProfileSheetBody({
    required this.profile,
    required this.showEndpointsAction,
  });

  @override
  State<_ManageProfileSheetBody> createState() => _ManageProfileSheetBodyState();
}

class _ManageProfileSheetBodyState extends State<_ManageProfileSheetBody> {
  late Profile _profile;
  late TextEditingController _nameController;
  late TextEditingController _portController;
  late TextEditingController _passThroughUrlController;
  late bool _useDeviceIp;
  late bool _autoPassThrough;
  late NetworkCondition _networkCondition;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _nameController = TextEditingController(text: _profile.name);
    _portController = TextEditingController(text: _profile.port.toString());
    _passThroughUrlController =
        TextEditingController(text: _profile.settings.globalPassThroughUrl ?? '');
    _useDeviceIp = _profile.settings.useDeviceIp;
    _autoPassThrough = _profile.settings.autoPassThrough;
    _networkCondition = _profile.settings.networkCondition;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _portController.dispose();
    _passThroughUrlController.dispose();
    super.dispose();
  }

  bool _isRunning(ServerState state) {
    if (state is MultiServerRunning) {
      return state.runningServers.any((s) => s.profileId == _profile.id);
    }
    if (state is ServerRunning) return state.profileId == _profile.id;
    return false;
  }

  Profile _buildUpdatedProfile(int port) {
    final name = _nameController.text.trim();
    return _profile.copyWith(
      name: name.isEmpty ? _profile.name : name,
      port: port,
      settings: _profile.settings.copyWith(
        useDeviceIp: _useDeviceIp,
        autoPassThrough: _autoPassThrough,
        networkCondition: _networkCondition,
        globalPassThroughUrl: _passThroughUrlController.text.trim().isEmpty
            ? null
            : _passThroughUrlController.text.trim(),
        clearPassThroughUrl: _passThroughUrlController.text.trim().isEmpty,
      ),
      updatedAt: DateTime.now(),
    );
  }

  /// Persists live-appliable fields while the server is already running —
  /// only called when `running`, never while stopped (Start saves everything
  /// there instead).
  Future<void> _commitLive() async {
    if (_autoPassThrough) {
      await rememberPassThroughUrl(context, _passThroughUrlController.text);
      if (!mounted) return;
    }
    _saveLive();
  }

  void _saveLive() {
    final updated = _buildUpdatedProfile(_profile.port);
    context.read<ProfileBloc>().add(UpdateProfileEvent(updated));
    setState(() => _profile = updated);
  }

  void _onNetworkConditionChanged(NetworkCondition c, bool running) {
    setState(() => _networkCondition = c);
    if (running) {
      _saveLive();
      context.read<ServerBloc>().add(SetProfileNetworkConditionEvent(_profile.id, c));
    }
  }

  Future<void> _start() async {
    if (_autoPassThrough) {
      await rememberPassThroughUrl(context, _passThroughUrlController.text);
      if (!mounted) return;
    }
    final port = int.tryParse(_portController.text.trim()) ?? _profile.port;
    final updated = _buildUpdatedProfile(port);
    context.read<ProfileBloc>().add(UpdateProfileEvent(updated));
    context.read<ServerBloc>().add(StartProfileEvent(
          profileId: updated.id,
          profileName: updated.name,
          port: updated.port,
          useDeviceIp: updated.settings.useDeviceIp,
          passThroughUrl: updated.settings.globalPassThroughUrl,
          autoPassThrough: updated.settings.autoPassThrough,
          networkCondition: updated.settings.networkCondition,
        ));
    Navigator.pop(context);
  }

  void _stop() {
    context.read<ServerBloc>().add(StopProfileEvent(_profile.id));
    Navigator.pop(context);
  }

  void _openEndpoints() {
    context.read<ProfileBloc>().add(SwitchActiveProfileEvent(_profile.id));
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MobileEndpointsScreen(profileId: _profile.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final running = _isRunning(context.watch<ServerBloc>().state);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  style: t.sans(size: 14),
                  decoration:
                      const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                  onSubmitted: (_) {
                    if (running) _saveLive();
                  },
                ),
                const SizedBox(height: 14),
                Text('Simulated network', style: t.sans(size: 13, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'Throttles every response from this server — an endpoint with its '
                  'own network condition set overrides this.',
                  style: t.sans(size: 12, weight: FontWeight.w500, color: t.textSecondary),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 200,
                    child: NetworkConditionField(
                      value: _networkCondition,
                      onChanged: (c) => _onNetworkConditionChanged(c, running),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ProfileSettingsFields(
                  portController: _portController,
                  portEnabled: !running,
                  portHelperText: running ? 'Stop the server to change the port' : null,
                  useDeviceIp: _useDeviceIp,
                  onUseDeviceIpChanged: running ? null : (v) => setState(() => _useDeviceIp = v),
                  autoPassThrough: _autoPassThrough,
                  onAutoPassThroughChanged: (v) {
                    setState(() => _autoPassThrough = v);
                    if (running) _saveLive();
                  },
                  passThroughUrlController: _passThroughUrlController,
                  onFieldCommitted: running ? _commitLive : null,
                ),
                const SizedBox(height: 20),
                Text('Endpoints', style: t.sans(size: 13, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (widget.showEndpointsAction) ...[
                  OutlinedButton.icon(
                    onPressed: _openEndpoints,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.textSecondary,
                      side: BorderSide(color: t.border),
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    icon: const Icon(Icons.rule, size: 18),
                    label: const Text('Manage endpoints'),
                  ),
                  const SizedBox(height: 10),
                ],
                EndpointImportExportActions(profileId: _profile.id, profileName: _profile.name),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: FilledButton(
            onPressed: running ? _stop : _start,
            style: FilledButton.styleFrom(
              backgroundColor: running ? const Color(0xFFDC2626) : t.accent,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
            ),
            child: Text(running ? 'Stop' : 'Start',
                style: t.sans(size: 14, weight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
