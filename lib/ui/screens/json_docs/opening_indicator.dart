import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';

/// "Opening file" loader: the Arbiter logo as a planet with a tilted ring and a
/// dot orbiting it (Saturn-style).
class OpeningIndicator extends StatefulWidget {
  const OpeningIndicator({super.key, this.message = 'Opening file'});

  final String message;

  @override
  State<OpeningIndicator> createState() => _OpeningIndicatorState();
}

class _OpeningIndicatorState extends State<OpeningIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  // Ring tilt: how much the orbit is squashed vertically to read as 3D.
  static const double _tilt = 1.15;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final angle = _c.value * 2 * math.pi;
                const rx = 44.0;
                final ry = 44.0 * math.cos(_tilt);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Tilted ring (a circle rotated in X → reads as an ellipse).
                    Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateX(_tilt),
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: t.accent.withValues(alpha: 0.35),
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                    // The planet (app logo).
                    ClipOval(
                      child: Image.asset(
                        'assets/app_icon/app_icon.png',
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                      ),
                    ),
                    // Orbiting dot along the tilted ellipse.
                    Transform.translate(
                      offset: Offset(rx * math.cos(angle), ry * math.sin(angle)),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: t.accent.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Text(widget.message,
              style: t.sans(size: 14, weight: FontWeight.w600, color: t.textSecondary)),
        ],
      ),
    );
  }
}
