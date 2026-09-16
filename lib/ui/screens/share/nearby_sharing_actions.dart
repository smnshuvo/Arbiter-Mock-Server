import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';
import 'nearby_receive_dialog.dart';
import 'nearby_share_dialog.dart';

/// "Share nearby" / "Receive nearby" buttons — shared by the desktop Settings
/// dialog and the mobile Settings screen.
class NearbySharingActions extends StatelessWidget {
  final String? initialProfileId;

  const NearbySharingActions({super.key, this.initialProfileId});

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final style = OutlinedButton.styleFrom(
      foregroundColor: t.textSecondary,
      side: BorderSide(color: t.border),
      padding: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
    );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: style,
            onPressed: () => showDialog(
              context: context,
              builder: (_) => NearbyShareDialog(initialProfileId: initialProfileId),
            ),
            icon: const Icon(Icons.wifi_tethering, size: 18),
            label: const Text('Share nearby'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: style,
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const NearbyReceiveDialog(),
            ),
            icon: const Icon(Icons.download_for_offline_outlined, size: 18),
            label: const Text('Receive nearby'),
          ),
        ),
      ],
    );
  }
}
