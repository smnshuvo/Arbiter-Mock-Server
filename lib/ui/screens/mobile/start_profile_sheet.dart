import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/network_condition.dart';
import '../../../domain/entities/profile.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../desktop/endpoint_import_export_actions.dart';
import '../endpoint_editor/widgets/network_condition_field.dart';
import 'arb_bottom_sheet.dart';
import 'mobile_endpoints_screen.dart';
import 'profile_settings_fields.dart';
import '../../widgets/pass_through_url_field.dart';

/// ArbTokens-styled "Start Server" sheet, shown from the home screen when
/// running a stopped profile or creating a new one. Same save-then-start
/// behavior as before, restyled to match the rest of the redesign.
///
/// Carries the same options as the Manage sheet — simulated network, port,
/// host, pass-through, endpoints and import/export — so starting a server
/// never means backing out to configure it somewhere else first. The one
/// deliberate omission is renaming: the server is picked by name from the
/// dropdown here, so an editable name field would fight the selector.
Future<void> showStartProfileSheet({
  required BuildContext context,
  required List<Profile> profiles,
  Set<String> runningProfileIds = const {},
  int defaultPort = 8080,
  bool defaultUseDeviceIp = false,
  String? initialProfileId,
  // Returns whether the sheet should close — lets the caller run an async
  // permission check first and keep the sheet open if it's denied.
  required Future<bool> Function(
          String profileId,
          String profileName,
          int port,
          bool useDeviceIp,
          String? passThroughUrl,
          bool autoPassThrough,
          NetworkCondition networkCondition)
      onStart,
  VoidCallback? onCreateProfile,
}) {
  return showArbBottomSheet(
    context: context,
    title: 'Start server',
    builder: (_) => _StartProfileSheetBody(
      profiles: profiles,
      runningProfileIds: runningProfileIds,
      defaultPort: defaultPort,
      defaultUseDeviceIp: defaultUseDeviceIp,
      initialProfileId: initialProfileId,
      onStart: onStart,
      onCreateProfile: onCreateProfile,
    ),
  );
}

class _StartProfileSheetBody extends StatefulWidget {
  final List<Profile> profiles;
  final Set<String> runningProfileIds;
  final int defaultPort;
  final bool defaultUseDeviceIp;
  final String? initialProfileId;
  final Future<bool> Function(
      String profileId,
      String profileName,
      int port,
      bool useDeviceIp,
      String? passThroughUrl,
      bool autoPassThrough,
      NetworkCondition networkCondition) onStart;
  final VoidCallback? onCreateProfile;

  const _StartProfileSheetBody({
    required this.profiles,
    required this.onStart,
    this.runningProfileIds = const {},
    this.defaultPort = 8080,
    this.defaultUseDeviceIp = false,
    this.initialProfileId,
    this.onCreateProfile,
  });

  @override
  State<_StartProfileSheetBody> createState() => _StartProfileSheetBodyState();
}

class _StartProfileSheetBodyState extends State<_StartProfileSheetBody> {
  String? _selectedProfileId;
  late TextEditingController _portController;
  late bool _useDeviceIp;
  bool _autoPassThrough = false;
  NetworkCondition _networkCondition = NetworkCondition.none;
  late TextEditingController _passThroughUrlController;

  List<Profile> get _availableProfiles =>
      widget.profiles.where((p) => !widget.runningProfileIds.contains(p.id)).toList();

  Profile? get _selectedProfile {
    final id = _selectedProfileId;
    if (id == null) return null;
    for (final p in widget.profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(text: widget.defaultPort.toString());
    _useDeviceIp = widget.defaultUseDeviceIp;
    final available = _availableProfiles;
    if (available.isNotEmpty) {
      final initial = widget.initialProfileId != null
          ? available.firstWhere(
              (p) => p.id == widget.initialProfileId,
              orElse: () => available.first,
            )
          : available.first;
      _selectedProfileId = initial.id;
      _autoPassThrough = initial.settings.autoPassThrough;
      _networkCondition = initial.settings.networkCondition;
      _passThroughUrlController = TextEditingController(
        text: initial.settings.globalPassThroughUrl ?? '',
      );
    } else {
      _passThroughUrlController = TextEditingController();
    }
  }

  void _onProfileSelected(String? profileId) {
    if (profileId == null) return;
    final profile = widget.profiles.firstWhere((p) => p.id == profileId);
    setState(() {
      _selectedProfileId = profileId;
      _autoPassThrough = profile.settings.autoPassThrough;
      _networkCondition = profile.settings.networkCondition;
      _passThroughUrlController.text = profile.settings.globalPassThroughUrl ?? '';
    });
  }

  @override
  void dispose() {
    _portController.dispose();
    _passThroughUrlController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final port = int.tryParse(_portController.text) ?? widget.defaultPort;
    final profile = widget.profiles.firstWhere((p) => p.id == _selectedProfileId);
    if (_autoPassThrough) {
      await rememberPassThroughUrl(context, _passThroughUrlController.text);
      if (!mounted) return;
    }
    final url = _autoPassThrough && _passThroughUrlController.text.trim().isNotEmpty
        ? _passThroughUrlController.text.trim()
        : null;
    final shouldClose = await widget.onStart(_selectedProfileId!, profile.name, port,
        _useDeviceIp, url, _autoPassThrough, _networkCondition);
    if (shouldClose && mounted) Navigator.pop(context);
  }

  void _createProfile() {
    Navigator.pop(context);
    widget.onCreateProfile?.call();
  }

  /// Leaves for the endpoint list of the server being configured. The
  /// navigator is captured up front because this sheet's own route is popped
  /// first — its context is defunct by the time the push runs.
  void _openEndpoints(Profile profile) {
    final navigator = Navigator.of(context);
    context.read<ProfileBloc>().add(SwitchActiveProfileEvent(profile.id));
    navigator.pop();
    navigator.push(
      MaterialPageRoute(builder: (_) => MobileEndpointsScreen(profileId: profile.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final available = _availableProfiles;
    final allRunning = available.isEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: allRunning
                ? _buildAllRunningNotice(t)
                : _buildSettings(t, available),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: allRunning
              ? OutlinedButton.icon(
                  icon: Icon(Icons.add, color: t.accent),
                  label: Text('Create new profile',
                      style: t.sans(size: 14, weight: FontWeight.w700, color: t.accent)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: t.accent.withValues(alpha: 0.4)),
                    minimumSize: const Size.fromHeight(46),
                    shape:
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
                  ),
                  onPressed: widget.onCreateProfile == null ? null : _createProfile,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: _selectedProfileId == null ? null : _start,
                      style: FilledButton.styleFrom(
                        backgroundColor: t.accent,
                        disabledBackgroundColor: t.accent.withValues(alpha: 0.5),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(t.radiusSm)),
                      ),
                      child: Text('Start',
                          style: t.sans(size: 14, weight: FontWeight.w700, color: Colors.white)),
                    ),
                    if (widget.onCreateProfile != null)
                      TextButton.icon(
                        icon: Icon(Icons.add, size: 16, color: t.accent),
                        label: Text('Or create a new profile',
                            style: t.sans(size: 13, weight: FontWeight.w600, color: t.accent)),
                        onPressed: _createProfile,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildAllRunningNotice(ArbTokens t) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(t.radiusSm),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: Text(
        'All profiles are already running. Create a new profile to start another '
        'server instance.',
        style: t.sans(size: 13, color: t.textSecondary),
      ),
    );
  }

  Widget _buildSettings(ArbTokens t, List<Profile> available) {
    final selected = _selectedProfile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedProfileId,
          style: t.sans(size: 14, color: t.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Server',
            border: OutlineInputBorder(),
          ),
          items: available
              .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
              .toList(),
          onChanged: _onProfileSelected,
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
              onChanged: (c) => setState(() => _networkCondition = c),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ProfileSettingsFields(
          portController: _portController,
          portEnabled: true,
          useDeviceIp: _useDeviceIp,
          onUseDeviceIpChanged: (v) => setState(() => _useDeviceIp = v),
          autoPassThrough: _autoPassThrough,
          onAutoPassThroughChanged: (v) => setState(() => _autoPassThrough = v),
          passThroughUrlController: _passThroughUrlController,
        ),
        if (selected != null) ...[
          const SizedBox(height: 20),
          Text('Endpoints', style: t.sans(size: 13, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _openEndpoints(selected),
            style: OutlinedButton.styleFrom(
              foregroundColor: t.textSecondary,
              side: BorderSide(color: t.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
              minimumSize: const Size.fromHeight(44),
            ),
            icon: const Icon(Icons.rule, size: 18),
            label: const Text('Manage endpoints'),
          ),
          const SizedBox(height: 10),
          EndpointImportExportActions(profileId: selected.id, profileName: selected.name),
        ],
      ],
    );
  }
}
