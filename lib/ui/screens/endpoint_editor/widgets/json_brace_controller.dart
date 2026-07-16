import 'package:flutter/material.dart';
import '../../../../core/theme/arbiter_tokens.dart';

/// A [TextEditingController] that renders JSON braces/brackets in depth-cycling
/// "rainbow" colors so nesting is easy to track in the code editor. Braces
/// inside string literals are left untouched.
class JsonBraceController extends TextEditingController {
  JsonBraceController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final t = ArbTokens.of(context);
    final base = style ?? const TextStyle();
    final source = text;
    final spans = <TextSpan>[];
    final buffer = StringBuffer();
    var depth = 0;
    var inString = false;
    var escaped = false;

    void flush() {
      if (buffer.isNotEmpty) {
        spans.add(TextSpan(text: buffer.toString(), style: base));
        buffer.clear();
      }
    }

    void brace(String ch, int colorDepth) {
      flush();
      spans.add(TextSpan(
        text: ch,
        style: base.copyWith(
          color: t.depthColor(colorDepth),
          fontWeight: FontWeight.w700,
        ),
      ));
    }

    for (var i = 0; i < source.length; i++) {
      final ch = source[i];
      if (inString) {
        buffer.write(ch);
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      switch (ch) {
        case '"':
          buffer.write(ch);
          inString = true;
        case '{':
        case '[':
          brace(ch, depth);
          depth++;
        case '}':
        case ']':
          depth = depth > 0 ? depth - 1 : 0;
          brace(ch, depth);
        default:
          buffer.write(ch);
      }
    }
    flush();
    return TextSpan(style: base, children: spans);
  }
}
