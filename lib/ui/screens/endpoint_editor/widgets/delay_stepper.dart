import 'package:flutter/material.dart';
import '../../../../core/theme/arbiter_tokens.dart';

/// A −/＋ stepper for the response delay in milliseconds.
class DelayStepper extends StatelessWidget {
  const DelayStepper({
    super.key,
    required this.valueMs,
    required this.onChanged,
    this.step = 100,
    this.height = 46,
  });

  final int valueMs;
  final ValueChanged<int> onChanged;
  final int step;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(t.radius - 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          _button(t, '−', () {
            final next = valueMs - step;
            onChanged(next < 0 ? 0 : next);
          }),
          Expanded(
            child: Center(
              child: Text(
                '$valueMs ms',
                style: t.mono(size: 14, weight: FontWeight.w600),
              ),
            ),
          ),
          _button(t, '＋', () => onChanged(valueMs + step)),
        ],
      ),
    );
  }

  Widget _button(ArbTokens t, String glyph, VoidCallback onTap) {
    return SizedBox(
      width: 42,
      height: double.infinity,
      child: Material(
        color: t.surfaceMuted,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              glyph,
              style: TextStyle(
                fontSize: 18,
                color: t.textSecondary,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
