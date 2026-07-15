import 'package:flutter/material.dart';
import '../../../../core/theme/arbiter_tokens.dart';

/// A single option inside an [ArbSegmented] control.
class ArbSegment {
  const ArbSegment(this.label, {this.enabled = true, this.badge});

  final String label;

  /// When false the segment is shown but cannot be selected (e.g. "Upcoming").
  final bool enabled;

  /// Optional small trailing badge text (e.g. "Soon").
  final String? badge;
}

/// A pill-style segmented control matching the design's Exact/Wildcard/Regex
/// and Form/Code toggles. Supports disabled segments with an "upcoming" badge.
class ArbSegmented extends StatelessWidget {
  const ArbSegmented({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.compact = false,
  });

  final List<ArbSegment> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surfaceMuted,
        borderRadius: BorderRadius.circular(t.radius - 1),
      ),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++)
            Expanded(child: _segment(context, t, i)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, ArbTokens t, int i) {
    final seg = segments[i];
    final selected = i == selectedIndex;
    final enabled = seg.enabled;

    final Color fg = !enabled
        ? t.textMuted
        : selected
            ? t.textPrimary
            : t.textSecondary;

    return Padding(
      padding: EdgeInsets.only(right: i == segments.length - 1 ? 0 : 4),
      child: Material(
        color: selected ? t.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(t.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radiusSm),
          onTap: enabled ? () => onChanged(i) : null,
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: compact ? 7 : 9,
              horizontal: 6,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    seg.label,
                    overflow: TextOverflow.ellipsis,
                    style: t.sans(size: 12, weight: FontWeight.w700, color: fg),
                  ),
                ),
                if (seg.badge != null) ...[
                  const SizedBox(width: 5),
                  _badge(t, seg.badge!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(ArbTokens t, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: t.accentSoft,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text.toUpperCase(),
        style: t.mono(size: 8, weight: FontWeight.w700, color: t.accent),
      ),
    );
  }
}
