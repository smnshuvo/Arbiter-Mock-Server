import 'package:flutter/material.dart';
import '../../../../core/theme/arbiter_tokens.dart';

/// Uppercase mono section label used above editor fields.
class ArbSectionLabel extends StatelessWidget {
  const ArbSectionLabel(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.only(left: 2, bottom: 9),
      child: Text(text.toUpperCase(), style: t.label),
    );
  }
}
