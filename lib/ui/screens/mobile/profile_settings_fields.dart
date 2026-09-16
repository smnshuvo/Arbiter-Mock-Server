import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../endpoint_editor/widgets/arb_segmented.dart';
import '../../widgets/pass_through_url_field.dart';

/// Shared field group for a profile's port/host/pass-through settings —
/// reused by [ManageProfileSheet] (editing an existing, possibly-running
/// profile) and the home screen's start-a-server sheet (always stopped, so
/// callers just pass `portEnabled: true` and non-null change callbacks).
class ProfileSettingsFields extends StatelessWidget {
  final TextEditingController portController;
  final bool portEnabled;
  final String? portHelperText;

  final bool useDeviceIp;

  /// Null disables the switch (e.g. while running, since it needs a restart).
  final ValueChanged<bool>? onUseDeviceIpChanged;

  final bool autoPassThrough;
  final ValueChanged<bool> onAutoPassThroughChanged;
  final TextEditingController passThroughUrlController;

  /// Fired when the port or base-URL field is submitted — callers that need
  /// to persist live edits (while a server is already running) hook in here;
  /// callers that only save on a single explicit action (e.g. "Start") can
  /// leave this null.
  final VoidCallback? onFieldCommitted;

  const ProfileSettingsFields({
    super.key,
    required this.portController,
    required this.portEnabled,
    this.portHelperText,
    required this.useDeviceIp,
    required this.onUseDeviceIpChanged,
    required this.autoPassThrough,
    required this.onAutoPassThroughChanged,
    required this.passThroughUrlController,
    this.onFieldCommitted,
  });

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: portController,
          enabled: portEnabled,
          keyboardType: TextInputType.number,
          style: t.mono(size: 14),
          decoration: InputDecoration(
            labelText: 'Port',
            border: const OutlineInputBorder(),
            helperText: portHelperText,
          ),
          onSubmitted: onFieldCommitted == null ? null : (_) => onFieldCommitted!(),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Use Device IP', style: t.sans(size: 14, weight: FontWeight.w600)),
          subtitle: Text('Allow other devices to connect',
              style: t.sans(size: 12, color: t.textSecondary)),
          value: useDeviceIp,
          activeThumbColor: t.accent,
          onChanged: onUseDeviceIpChanged,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title:
              Text('Auto pass-through', style: t.sans(size: 14, weight: FontWeight.w600)),
          subtitle: Text('Forward unmatched requests to a base URL',
              style: t.sans(size: 12, color: t.textSecondary)),
          value: autoPassThrough,
          activeThumbColor: t.accent,
          onChanged: onAutoPassThroughChanged,
        ),
        if (autoPassThrough) ...[
          const SizedBox(height: 8),
          ArbSegmented(
            segments: const [
              ArbSegment('All requests'),
              ArbSegment('Specific endpoints', enabled: false, badge: 'Soon'),
            ],
            selectedIndex: 0,
            onChanged: (_) {},
          ),
          const SizedBox(height: 10),
          PassThroughUrlField(
            controller: passThroughUrlController,
            onCommitted: onFieldCommitted,
          ),
        ],
      ],
    );
  }
}
