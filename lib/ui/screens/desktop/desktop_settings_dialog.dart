import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../endpoint_editor/widgets/arb_section_label.dart';
import '../share/nearby_sharing_actions.dart';

/// App-wide settings for the wide layout, opened from the server rail. The
/// mobile [SettingsScreen] isn't reachable from the workspace, so settings the
/// desktop needs get a home here.
class DesktopSettingsDialog extends StatelessWidget {
  /// Preselected collection for "Share nearby" — the workspace's current one.
  final String? selectedProfileId;

  const DesktopSettingsDialog({super.key, this.selectedProfileId});

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Dialog(
      backgroundColor: t.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Settings', style: t.sans(size: 15, weight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: t.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: t.border),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ArbSectionLabel('Nearby sharing', padding: EdgeInsets.zero),
                  const SizedBox(height: 6),
                  Text(
                    'Send a collection to another Arbiter user on the same Wi-Fi, or '
                    'receive one. The sender shows a PIN; the receiver names the new '
                    'server before it is saved.',
                    style: t.sans(size: 12, weight: FontWeight.w500, color: t.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  NearbySharingActions(initialProfileId: selectedProfileId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
