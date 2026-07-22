import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/endpoint.dart';
import '../../../domain/entities/profile.dart';
import '../../bloc/endpoint/endpoint_bloc.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../bloc/server/server_bloc.dart';
import '../endpoint_editor/desktop_endpoint_editor.dart';
import '../endpoint_editor/widgets/arb_section_label.dart';
import '../endpoint_editor/widgets/arb_segmented.dart';

/// "Manage {server}" overlay: consolidates general settings (name/port/host),
/// interception config, and the endpoint list + inline editor that used to
/// live on separate screens — opened from the wide-layout workspace header.
/// Sections are stacked in one scrollable view (not tabbed).
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

  Endpoint? _editingEndpoint;
  bool _showEditor = false;
  int _newDraftSeq = 0;

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
    context.read<EndpointBloc>().add(LoadEndpointsEvent(_profile.id));
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

  void _saveGeneral() {
    final name = _nameController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? _profile.port;
    final updated = _profile.copyWith(
      name: name.isEmpty ? _profile.name : name,
      port: port,
      settings: _profile.settings.copyWith(
        useDeviceIp: _useDeviceIp,
        autoPassThrough: _autoPassThrough,
        globalPassThroughUrl: _passThroughUrlController.text.trim().isEmpty
            ? null
            : _passThroughUrlController.text.trim(),
        clearPassThroughUrl: _passThroughUrlController.text.trim().isEmpty,
      ),
      updatedAt: DateTime.now(),
    );
    context.read<ProfileBloc>().add(UpdateProfileEvent(updated));
    setState(() => _profile = updated);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
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
              child: _showEditor
                  ? _buildEndpointEditor()
                  : SingleChildScrollView(
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
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed: _saveGeneral,
                              style: FilledButton.styleFrom(backgroundColor: t.accent),
                              child: const Text('Save changes'),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Divider(color: t.border),
                          const SizedBox(height: 20),
                          const ArbSectionLabel('Endpoints', padding: EdgeInsets.zero),
                          const SizedBox(height: 12),
                          _buildEndpointsSection(t),
                          const SizedBox(height: 24),
                          Divider(color: t.border),
                          const SizedBox(height: 20),
                          _buildDeleteSection(t, running),
                        ],
                      ),
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
          TextField(
            controller: _passThroughUrlController,
            style: t.mono(size: 13),
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.example.com',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEndpointsSection(ArbTokens t) {
    return BlocBuilder<EndpointBloc, EndpointState>(
      builder: (context, state) {
        final endpoints = state is EndpointLoaded ? state.endpoints : <Endpoint>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Endpoints', style: t.sans(size: 14, weight: FontWeight.w700)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => setState(() {
                    _editingEndpoint = null;
                    _showEditor = true;
                    _newDraftSeq++;
                  }),
                  style: FilledButton.styleFrom(backgroundColor: t.accent),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (endpoints.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: Text('No endpoints yet', style: t.sans(color: t.textMuted))),
              )
            else
              for (final ep in endpoints) _buildEndpointRow(t, ep),
          ],
        );
      },
    );
  }

  Widget _buildEndpointRow(ArbTokens t, Endpoint ep) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(t.radiusSm),
      ),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
        title: Row(
          children: [
            _methodChip(t, ep.method ?? 'ANY'),
            const SizedBox(width: 8),
            Expanded(
              child: Text(ep.pattern, overflow: TextOverflow.ellipsis, style: t.mono(size: 12.5)),
            ),
          ],
        ),
        subtitle: Text(
          ep.mode == EndpointMode.mock ? 'Mock · ${ep.statusCode}' : 'Pass-through',
          style: t.sans(size: 11, weight: FontWeight.w500, color: t.textSecondary),
        ),
        onTap: () => setState(() {
          _editingEndpoint = ep;
          _showEditor = true;
        }),
      ),
    );
  }

  Widget _methodChip(ArbTokens t, String method) {
    final color = t.methodColor(method);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(method, style: t.mono(size: 10, weight: FontWeight.w700, color: color)),
    );
  }

  Widget _buildEndpointEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextButton.icon(
            onPressed: () => setState(() => _showEditor = false),
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('All endpoints'),
          ),
        ),
        Expanded(
          child: DesktopEndpointEditor(
            key: ValueKey(_editingEndpoint?.id ?? 'new-$_newDraftSeq'),
            endpoint: _editingEndpoint,
            profileId: _profile.id,
            onSaved: () {
              context.read<EndpointBloc>().add(LoadEndpointsEvent(_profile.id));
              setState(() => _showEditor = false);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDeleteSection(ArbTokens t, bool running) {
    const danger = Color(0xFFDC2626);
    final isDefault = _profile.id == 'default';
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: isDefault ? null : () => _confirmDelete(t, running),
        style: OutlinedButton.styleFrom(
          foregroundColor: danger,
          side: BorderSide(color: isDefault ? t.border : danger),
        ),
        icon: const Icon(Icons.delete_outline, size: 18),
        label: Text(isDefault ? "Can't delete the default server" : 'Delete this server'),
      ),
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
