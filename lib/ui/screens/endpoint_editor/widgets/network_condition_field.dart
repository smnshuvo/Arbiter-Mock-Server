import 'package:flutter/material.dart';

import '../../../../core/theme/arbiter_tokens.dart';
import '../../../../domain/entities/network_condition.dart';

/// Picker for the endpoint's simulated link speed.
///
/// There are too many options for an [ArbSegmented] row, so this renders as a
/// field-shaped popup menu matching [DelayStepper]/[StatusField].
class NetworkConditionField extends StatelessWidget {
  const NetworkConditionField({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 46,
  });

  final NetworkCondition value;
  final ValueChanged<NetworkCondition> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final spec = value.spec;
    final accent = _colorFor(t, value);

    return PopupMenuButton<NetworkCondition>(
      tooltip: 'Simulated network',
      initialValue: value,
      onSelected: onChanged,
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusSm),
        side: BorderSide(color: t.border),
      ),
      itemBuilder: (_) => [
        for (final c in NetworkCondition.values)
          PopupMenuItem(
            value: c,
            child: Row(
              children: [
                Icon(_iconFor(c), size: 16, color: _colorFor(t, c)),
                const SizedBox(width: 10),
                // Flexible: the description is long enough to overflow a
                // narrow menu otherwise.
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.spec.label,
                          style: t.sans(size: 13, weight: FontWeight.w600)),
                      Text(c.spec.description,
                          style: t.sans(size: 11, color: t.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(
              color: value.isThrottled ? accent.withValues(alpha: 0.45) : t.border),
          borderRadius: BorderRadius.circular(t.radius - 1),
        ),
        child: Row(
          children: [
            Icon(_iconFor(value), size: 16, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                spec.label,
                overflow: TextOverflow.ellipsis,
                style: t.sans(
                    size: 13,
                    weight: FontWeight.w600,
                    color: value.isThrottled ? accent : t.textSecondary),
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: t.textMuted),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(NetworkCondition c) {
    switch (c) {
      case NetworkCondition.none:
        return Icons.flash_on;
      case NetworkCondition.unstable2G:
        return Icons.signal_cellular_connected_no_internet_0_bar;
      case NetworkCondition.gprs:
      case NetworkCondition.edge:
        return Icons.signal_cellular_alt_1_bar;
      case NetworkCondition.threeG:
        return Icons.signal_cellular_alt_2_bar;
      case NetworkCondition.fourG:
      case NetworkCondition.fiveG:
        return Icons.signal_cellular_alt;
    }
  }

  /// Green = fast, amber = slow, red = deliberately broken.
  Color _colorFor(ArbTokens t, NetworkCondition c) {
    switch (c) {
      case NetworkCondition.none:
        return t.textSecondary;
      case NetworkCondition.unstable2G:
        return const Color(0xFFDC2626);
      case NetworkCondition.gprs:
      case NetworkCondition.edge:
        return const Color(0xFFF59E0B);
      case NetworkCondition.threeG:
        return t.purple;
      case NetworkCondition.fourG:
      case NetworkCondition.fiveG:
        return t.green;
    }
  }
}
