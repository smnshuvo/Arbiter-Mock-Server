import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../../core/theme/arbiter_tokens.dart';

/// Editable raw-JSON editor with a live validity indicator and a Format
/// (pretty-print) button. Shares its [controller] with the visual form editor
/// so the two tabs stay in sync.
class JsonCodeEditor extends StatelessWidget {
  const JsonCodeEditor({
    super.key,
    required this.controller,
    this.onChanged,
    this.minLines = 8,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final int minLines;

  bool _isValid(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return true;
    try {
      jsonDecode(trimmed);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _format(BuildContext context) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
      controller.value = TextEditingValue(
        text: pretty,
        selection: TextSelection.collapsed(offset: pretty.length),
      );
      onChanged?.call(pretty);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Can\'t format — the JSON isn\'t valid yet')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.codeBg,
        border: Border.all(color: t.codeBorder),
        borderRadius: BorderRadius.circular(t.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.codeBorder)),
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    final valid = _isValid(controller.text);
                    final color = valid ? t.green : const Color(0xFFFF7B72);
                    return Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration:
                              BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 7),
                        Text(valid ? 'Valid JSON' : 'Invalid JSON',
                            style: t.mono(
                                size: 11, weight: FontWeight.w700, color: color)),
                      ],
                    );
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _format(context),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: const Color(0x1A79C0FF),
                  ),
                  child: Text('Format',
                      style: t.mono(
                          size: 11,
                          weight: FontWeight.w700,
                          color: const Color(0xFF79C0FF))),
                ),
              ],
            ),
          ),
          TextField(
            controller: controller,
            onChanged: onChanged,
            minLines: minLines,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            cursorColor: t.accent,
            style: t.mono(size: 12.5, color: t.codeText),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.fromLTRB(15, 14, 15, 14),
            ),
          ),
        ],
      ),
    );
  }
}
