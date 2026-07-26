import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';

/// Tallest a sheet may grow, as a fraction of the screen.
const double _maxHeightFraction = 0.65;

/// Rounded-top, ArbTokens-styled chrome for `showModalBottomSheet` content —
/// drag handle + title — shared by the mobile screens' bottom sheets so they
/// look consistent with the rest of the redesign instead of the plain
/// Material default sheet.
///
/// Capped at [_maxHeightFraction] of the screen so a sheet never reads as a
/// full-screen page. Bodies are handed a [Flexible] slot, so they should scroll
/// their own content and pin any primary action below that scroll area rather
/// than letting the button scroll out of reach.
Future<T?> showArbBottomSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final t = ArbTokens.of(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * _maxHeightFraction,
          ),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(t.radius)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Text(title, style: t.sans(size: 16, weight: FontWeight.w700)),
                ),
                Flexible(child: builder(ctx)),
              ],
            ),
          ),
        ),
      );
    },
  );
}
