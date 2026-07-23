import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/profile.dart';
import 'arb_bottom_sheet.dart';
import 'profile_settings_fields.dart';

/// ArbTokens-styled "Start Server" sheet, shown from the home screen when
/// running a stopped profile or creating a new one. Same save-then-start
/// behavior as before, restyled to match the rest of the redesign.
Future<void> showStartProfileSheet({
  required BuildContext context,
  required List<Profile> profiles,
  Set<String> runningProfileIds = const {},
  int defaultPort = 8080,
  bool defaultUseDeviceIp = false,
  String? initialProfileId,
  // Returns whether the sheet should close — lets the caller run an async
  // permission check first and keep the sheet open if it's denied.
  required Future<bool> Function(String profileId, String profileName, int port,
          bool useDeviceIp, String? passThroughUrl, bool autoPassThrough)
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
  final Future<bool> Function(String profileId, String profileName, int port,
      bool useDeviceIp, String? passThroughUrl, bool autoPassThrough) onStart;
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
  late TextEditingController _passThroughUrlController;

  List<Profile> get _availableProfiles =>
      widget.profiles.where((p) => !widget.runningProfileIds.contains(p.id)).toList();

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
    final url = _autoPassThrough && _passThroughUrlController.text.trim().isNotEmpty
        ? _passThroughUrlController.text.trim()
        : null;
    final shouldClose = await widget.onStart(
        _selectedProfileId!, profile.name, port, _useDeviceIp, url, _autoPassThrough);
    if (shouldClose && mounted) Navigator.pop(context);
  }

  void _createProfile() {
    Navigator.pop(context);
    widget.onCreateProfile?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final available = _availableProfiles;
    final allRunning = available.isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (allRunning) ...[
            Container(
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
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: Icon(Icons.add, color: t.accent),
              label: Text('Create new profile',
                  style: t.sans(size: 14, weight: FontWeight.w700, color: t.accent)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: t.accent.withValues(alpha: 0.4)),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
              ),
              onPressed: widget.onCreateProfile == null ? null : _createProfile,
            ),
          ] else ...[
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
            ProfileSettingsFields(
              portController: _portController,
              portEnabled: true,
              useDeviceIp: _useDeviceIp,
              onUseDeviceIpChanged: (v) => setState(() => _useDeviceIp = v),
              autoPassThrough: _autoPassThrough,
              onAutoPassThroughChanged: (v) => setState(() => _autoPassThrough = v),
              passThroughUrlController: _passThroughUrlController,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _selectedProfileId == null ? null : _start,
              style: FilledButton.styleFrom(
                backgroundColor: t.accent,
                disabledBackgroundColor: t.accent.withValues(alpha: 0.5),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
              ),
              child: Text('Start',
                  style: t.sans(size: 14, weight: FontWeight.w700, color: Colors.white)),
            ),
            if (widget.onCreateProfile != null) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                icon: Icon(Icons.add, size: 16, color: t.accent),
                label: Text('Or create a new profile',
                    style: t.sans(size: 13, weight: FontWeight.w600, color: t.accent)),
                onPressed: widget.onCreateProfile == null ? null : _createProfile,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
