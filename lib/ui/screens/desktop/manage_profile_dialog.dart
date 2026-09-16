import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/network_condition.dart';
import '../../../domain/entities/profile.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../bloc/server/server_bloc.dart';
import '../endpoint_editor/widgets/arb_section_label.dart';
import '../endpoint_editor/widgets/arb_segmented.dart';
import '../endpoint_editor/widgets/network_condition_field.dart';
import '../../widgets/pass_through_url_field.dart';
import 'endpoint_import_export_actions.dart';

/// "Manage {server}" overlay: consolidates general settings (name/port/host),
/// interception config, and endpoint import/export — opened from the
/// wide-layout workspace header. The endpoint list itself has its own
/// "Manage endpoints" view in the workspace.
class ManageProfileDialog extends StatefulWidget {
  final Profile profile;

  /// Called after the profile is deleted, so the caller can fall back its
  /// selection away from the now-gone profile.
  final VoidCallback? onDeleted;

  const ManageProfileDialog({super.key, required this.profile, this.onDeleted});

  @override
  State<ManageProfileDialog> createState() => _ManageProfileDialogState();
}

class _ManageProfileDialogState extends State<ManageProfileDialog> {
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

  Future<void> _saveGeneral() async {
    if (_autoPassThrough) {
      await rememberPassThroughUrl(context, _passThroughUrlController.text);
      if (!mounted) return;
    }
    final name = _nameController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? _profile.port;
    final updated = _profile.copyWith(
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
    context.read<ProfileBloc>().add(UpdateProfileEvent(updated));
    if (_isRunning(context.read<ServerBloc>().state)) {
      context
          .read<ServerBloc>()
          .add(SetProfileNetworkConditionEvent(_profile.id, _networkCondition));
    }
    // Close the dialog on save — the snackbar goes to the workspace's
    // messenger (captured before popping) so it's still seen afterwards.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text('Saved ${updated.name}')));
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final running = _isRunning(context.watch<ServerBloc>().state);
    return Dialog(
      backgroundColor: t.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Column(
          children: [
            _buildHeader(t),
            Divider(height: 1, color: t.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ArbSectionLabel('General', padding: EdgeInsets.zero),
                    const SizedBox(height: 12),
                    _buildGeneralSection(t, running),
                    const SizedBox(height: 24),
                    Divider(color: t.border),
                    const SizedBox(height: 20),
                    const ArbSectionLabel('Interception', padding: EdgeInsets.zero),
                    const SizedBox(height: 12),
                    _buildInterceptionSection(t),
                    const SizedBox(height: 24),
                    Divider(color: t.border),
                    const SizedBox(height: 20),
                    const ArbSectionLabel('Endpoints', padding: EdgeInsets.zero),
                    const SizedBox(height: 12),
                    EndpointImportExportActions(
                        profileId: _profile.id, profileName: _profile.name),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: t.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  _buildDeleteButton(t, running),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saveGeneral,
                    style: FilledButton.styleFrom(backgroundColor: t.accent),
                    child: const Text('Save changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ArbTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          Expanded(
            child: Text('Manage ${_profile.name}',
                style: t.sans(size: 15, weight: FontWeight.w700)),
          ),
          IconButton(
            icon: Icon(Icons.close, color: t.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralSection(ArbTokens t, bool running) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _nameController,
                style: t.sans(size: 14),
                decoration: const InputDecoration(
                    labelText: 'Name', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _portController,
                enabled: !running,
                keyboardType: TextInputType.number,
                style: t.mono(size: 14),
                decoration: InputDecoration(
                  labelText: 'Port',
                  border: const OutlineInputBorder(),
                  helperText: running ? 'Stop the server to change the port' : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const ArbSectionLabel('Host'),
        ArbSegmented(
          segments: [
            ArbSegment('Localhost', enabled: !running),
            ArbSegment('Network (0.0.0.0)', enabled: !running),
          ],
          selectedIndex: _useDeviceIp ? 1 : 0,
          onChanged: (i) => setState(() => _useDeviceIp = i == 1),
        ),
      ],
    );
  }

  Widget _buildInterceptionSection(ArbTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Simulated network', style: t.sans(size: 14, weight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Throttles every response from this server — an endpoint with its '
          'own network condition set overrides this.',
          style: t.sans(size: 12, weight: FontWeight.w500, color: t.textSecondary),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 220,
          child: NetworkConditionField(
            value: _networkCondition,
            onChanged: (c) => setState(() => _networkCondition = c),
          ),
        ),
        const SizedBox(height: 20),
        Divider(color: t.border),
        const SizedBox(height: 16),
        Row(
          children: [
            Switch(
              value: _autoPassThrough,
              activeThumbColor: t.accent,
              onChanged: (v) => setState(() => _autoPassThrough = v),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Auto pass-through', style: t.sans(size: 14, weight: FontWeight.w700)),
            ),
          ],
        ),
        Text(
          'Forward unmatched requests to a base URL — applies to the whole collection',
          style: t.sans(size: 12, weight: FontWeight.w500, color: t.textSecondary),
        ),
        if (_autoPassThrough) ...[
          const SizedBox(height: 14),
          ArbSegmented(
            segments: const [
              ArbSegment('All requests'),
              ArbSegment('Specific endpoints', enabled: false, badge: 'Soon'),
            ],
            selectedIndex: 0,
            onChanged: (_) {},
          ),
          const SizedBox(height: 4),
          Text(
            '"Specific endpoints" scoping is coming soon — auto pass-through '
            'currently applies to all unmatched requests.',
            style: t.sans(size: 11.5, weight: FontWeight.w500, color: t.textMuted),
          ),
          const SizedBox(height: 12),
          PassThroughUrlField(controller: _passThroughUrlController),
        ],
      ],
    );
  }

  Widget _buildDeleteButton(ArbTokens t, bool running) {
    const danger = Color(0xFFDC2626);
    final isDefault = _profile.id == 'default';
    return OutlinedButton.icon(
      onPressed: isDefault ? null : () => _confirmDelete(t, running),
      style: OutlinedButton.styleFrom(
        foregroundColor: danger,
        side: BorderSide(color: isDefault ? t.border : danger),
      ),
      icon: const Icon(Icons.delete_outline, size: 18),
      label: Text(isDefault ? "Can't delete" : 'Delete server'),
    );
  }

  void _confirmDelete(ArbTokens t, bool running) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete server'),
        content: Text(running
            ? 'Stop "${_profile.name}" before deleting it.'
            : 'Delete "${_profile.name}" and all of its endpoints? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          if (!running)
            TextButton(
              onPressed: () {
                context.read<ProfileBloc>().add(DeleteProfileEvent(_profile.id));
                Navigator.pop(ctx); // close confirmation
                Navigator.pop(context); // close the Manage dialog
                widget.onDeleted?.call();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }
}
