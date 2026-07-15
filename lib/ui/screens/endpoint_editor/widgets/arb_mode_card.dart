import 'package:flutter/material.dart';
import '../../../../core/theme/arbiter_tokens.dart';

/// A selectable mode card (Mock / Code exec / Pass-through). Supports a
/// disabled state with an "upcoming" badge for modes that aren't wired yet.
class ArbModeCard extends StatelessWidget {
  const ArbModeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.badge,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final active = selected && enabled;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: active ? t.accentSoft : t.surface,
        borderRadius: BorderRadius.circular(t.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radius),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius),
              border: Border.all(
                color: active ? t.accent : t.border,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: t.sans(
                          size: 12,
                          weight: FontWeight.w700,
                          color: active ? t.accent : t.textPrimary,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 5),
                      _badge(t, badge!),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: t.sans(
                    size: 10,
                    weight: FontWeight.w500,
                    color: t.textSecondary,
                  ),
                ),
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
        color: t.surfaceMuted,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text.toUpperCase(),
        style: t.mono(size: 8, weight: FontWeight.w700, color: t.textMuted),
      ),
    );
  }
}
